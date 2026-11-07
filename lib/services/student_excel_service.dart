import 'dart:io';
import 'package:excel/excel.dart';

class StudentData {
  final String seatNo;
  final String name;
  final String grade;
  final String secretCode;

  StudentData({
    required this.seatNo,
    required this.name,
    this.grade = '',
    required this.secretCode,
  });
}

class StudentExcelResult {
  final List<StudentData> students;
  final int subjectCode;
  final String matchedSubjectName;
  final int totalMonths;

  StudentExcelResult({
    required this.students,
    required this.subjectCode,
    required this.matchedSubjectName,
    this.totalMonths = 8,
  });
}

class StudentExcelService {
  /// استخراج النص النقي الخام من خلية الإكسيل متجاوزاً تغليف الكائنات ومحارف التنسيق المخفية
  static String _extractCleanText(dynamic cell) {
    if (cell == null) return '';
    final val = (cell is Data) ? cell.value : cell;
    if (val == null) return '';

    String text;
    if (val is TextCellValue) {
      // حزمة excel ترجع TextSpan داخل val.value فنستخرج text مع معالجة null
      text = val.value.text ?? '';
    } else if (val is IntCellValue) {
      text = val.value.toString();
    } else if (val is DoubleCellValue) {
      text = val.value.toInt().toString();
    } else {
      text = val.toString();
    }

    // إزالة غلاف الكائن إن وجد مثل TextCellValue(...)
    if (text.startsWith('TextCellValue(') && text.endsWith(')')) {
      text = text.substring(14, text.length - 1);
    }

    // إزالة المحارف المخفية (Zero-width spaces) والمسافات غير المرئية
    return text.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), '').trim();
  }

  /// تطبيع موحد للحروف والكلمات العربية لضمان المقارنة الصادقة والمجردة
  static String _normalizeArabic(String text) {
    var s = _extractCleanText(text).toLowerCase();
    // توحيد الألف والهمزات
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    // توحيد التاء المربوطة والهاء
    s = s.replaceAll('ة', 'ه');
    // توحيد الياء والألف المقصورة
    s = s.replaceAll('ى', 'ي');
    // إزالة الحركات وعلامات التشكيل
    s = s.replaceAll(RegExp(r'[\u064B-\u0652]'), '');
    // إزالة كلمة "الصف" إن وجدت
    s = s.replaceAll('الصف', '').trim();
    // إزالة جميع المسافات لإجراء مقارنة مجردة تماماً
    s = s.replaceAll(RegExp(r'\s+'), '');
    return s;
  }

  /// فحص تطابق الصف بين المدخل وما هو مكتوب في خلية الإكسيل (العمود C)
  static bool _isGradeMatch(String studentGradeCell, String targetGrade) {
    final normCell = _normalizeArabic(studentGradeCell);
    final normTarget = _normalizeArabic(targetGrade);

    if (normTarget.isEmpty) return true; // إذا لم يُحدد صف يتم استيراد الجميع
    if (normCell.isEmpty) return false;  // إذا طُلب صف محدد وخانة الطالب فارغة يُستبعد

    // التطابق المباشر التام أو الجزئي بعد التجريد
    if (normCell == normTarget || normCell.contains(normTarget) || normTarget.contains(normCell)) {
      return true;
    }

    // توافق مسميات الصف التاسع (تاسع / ثالث إعدادي / 9 / ٩)
    final isTargetGrade9 = normTarget.contains('تاسع') || normTarget == '9' || normTarget == '٩' || normTarget.contains('ثالث');
    if (isTargetGrade9 && (normCell.contains('تاسع') || normCell.contains('ثالث') || normCell == '9' || normCell == '٩')) {
      return true;
    }

    // توافق مسميات الصف الثامن (ثامن / ثاني إعدادي / 8 / ٨)
    final isTargetGrade8 = normTarget.contains('ثامن') || normTarget == '8' || normTarget == '٨' || normTarget.contains('ثاني');
    if (isTargetGrade8 && (normCell.contains('ثامن') || normCell.contains('ثاني') || normCell == '8' || normCell == '٨')) {
      return true;
    }

    // توافق مسميات الصف السابع (سابع / أول إعدادي / 7 / ٧)
    final isTargetGrade7 = normTarget.contains('سابع') || normTarget == '7' || normTarget == '٧' || normTarget.contains('اول');
    if (isTargetGrade7 && (normCell.contains('سابع') || normCell.contains('اول') || normCell == '7' || normCell == '٧')) {
      return true;
    }

    // بقية الصفوف الأساسية (سادس، خامس، رابع...)
    for (final g in ['سادس', 'خامس', 'رابع', 'ثالث', 'ثاني', 'اول']) {
      if (normTarget.contains(g) && normCell.contains(g)) return true;
    }

    return false;
  }

  /// فحص ما إذا كان ملف الإكسيل يعتمد نظام 8 أشهر أم 6 أشهر تلقائياً من خلايا الصف الثاني
  static int detectTotalMonths(Sheet sheet) {
    // في نظام 8 أشهر: الشهر الرابع يقع في العمود 19 (E=4, J=9, O=14, T=19)
    // في نظام 6 أشهر: العمود 19 يكون مخصصاً لـ [م١]
    final cellFourthMonth = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: 1));
    final rawText = _extractCleanText(cellFourthMonth);
    final text = _normalizeArabic(rawText);

    if (text.isEmpty || text == 'م1' || text == 'م١' || text.contains('محصله') || text.contains('فصل1')) {
      return 6;
    }
    return 8;
  }

  /// التحقق الصارم من بنية ملف الإكسيل ومطابقته للتنسيق المعتمد
  static Future<bool> validateExcelStructure(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) return false;

      final sheet = excel.tables.values.first;
      if (sheet.maxRows < 4) return false;

      // فحص عناوين رأس الأعمدة في الصف الثالث (index = 2) مع استخراج النص النقي أولاً
      final seatCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2));
      final nameCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2));

      final seatHeader = _normalizeArabic(_extractCleanText(seatCell));
      final nameHeader = _normalizeArabic(_extractCleanText(nameCell));

      bool hasExpectedHeaders = (seatHeader.contains('جلوس') || seatHeader.contains('رقم')) ||
          (nameHeader.contains('اسم') || nameHeader.contains('طالب'));

      // فحص وجود سجلات طلاب فعلية في الصف الرابع (index = 3)
      final testSeat = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)));
      final testName = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3)));
      bool hasStudentRow = testSeat.isNotEmpty || testName.isNotEmpty;

      return hasExpectedHeaders || hasStudentRow;
    } catch (_) {
      return false;
    }
  }

  /// استخراج أسماء الشهور ديناميكياً من الصف الثاني (rowIndex = 1) بدءاً من العمود E (columnIndex = 4)
  static List<String> extractMonthsFromSheet(Sheet sheet, {int? totalMonths}) {
    final int resolvedTotal = totalMonths ?? detectTotalMonths(sheet);
    List<String> months = [];
    int currentCol = 4; // عمود E
    final int monthsInTerm1 = (resolvedTotal == 6) ? 3 : 4;

    for (int m = 1; m <= resolvedTotal; m++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: currentCol, rowIndex: 1));
      final monthName = _extractCleanText(cell);
      if (monthName.isNotEmpty) {
        months.add(monthName);
      } else {
        months.add('شهر $m');
      }

      currentCol += 5;
      if (m == monthsInTerm1) {
        currentCol += 2; // تخطي عمودي [م١ ، ف١]
      }
    }
    return months;
  }

  /// استخراج ترتيب الشهر عند ورود كلمة شهر في العنوان
  static int _extractMonthOrderFromTitle(String examTitle, Sheet sheet, int totalMonths) {
    final title = _normalizeArabic(examTitle);

    // 1. البحث في أسماء الشهور الفعلية المقروءة من الصف الثاني بورقة العمل
    final dynamicMonths = extractMonthsFromSheet(sheet, totalMonths: totalMonths);
    for (int i = 0; i < dynamicMonths.length; i++) {
      final cleanMonthName = _normalizeArabic(dynamicMonths[i]);
      if (cleanMonthName.isNotEmpty && (title.contains(cleanMonthName) || cleanMonthName.contains(title))) {
        return i + 1; // ترتيب الشهر ديناميكياً (1, 2, 3...)
      }
    }

    // 2. فحص الأشهر الهجرية المعروفة
    const hijriMonths = {
      'محرم': 1,
      'صفر': 2,
      'ربيعالاول': 3,
      'ربيعاول': 3,
      'ربيعثاني': 4,
      'ربيعالثاني': 4,
      'جماديالاولي': 5,
      'جماديالاول': 5,
      'جماديالاخره': 6,
      'جماديالثانيه': 6,
      'رجب': 7,
      'شعبان': 8,
      'رمضان': 9,
      'شوال': 10,
      'ذوالقعده': 11,
      'ذوالحجه': 12,
    };
    for (final entry in hijriMonths.entries) {
      if (title.contains(entry.key)) {
        return entry.value;
      }
    }

    // 3. فحص الأشهر الميلادية الدراسية
    const gregorianMonths = {
      'سبتمبر': 1,
      'اكتوبر': 2,
      'نوفمبر': 3,
      'ديسمبر': 4,
      'يناير': 5,
      'فبراير': 6,
      'مارس': 7,
      'ابريل': 8,
      'مايو': 9,
    };
    for (final entry in gregorianMonths.entries) {
      if (title.contains(entry.key)) {
        return entry.value;
      }
    }

    // 4. مطابقة الأرقام المباشرة بعد كلمة شهر (شهر 1، شهر 2...)
    final match = RegExp(r'شهر\s*([1-8١-٨])').firstMatch(title);
    if (match != null) {
      final d = match.group(1)!;
      return int.tryParse(d
          .replaceAll('١', '1')
          .replaceAll('٢', '2')
          .replaceAll('٣', '3')
          .replaceAll('٤', '4')
          .replaceAll('٥', '5')
          .replaceAll('٦', '6')
          .replaceAll('٧', '7')
          .replaceAll('٨', '8')) ?? 1;
    }

    return 1;
  }

  /// تحديد الرقم الذكي المطبوع يمين الـ QR Code ديناميكياً وفق عنوان الاختبار وملف الإكسيل
  static int resolveSmartQrCodeNumberDynamic({
    required String examTitle,
    required String subjectName,
    required Excel excel,
    int? totalMonths,
  }) {
    final title = _normalizeArabic(examTitle);
    final sheet = excel.tables.values.first;
    final int resolvedTotal = totalMonths ?? detectTotalMonths(sheet);

    // حساب رقم ترتيب ورقة العمل التي تحمل اسم المادة (1-based index)
    int subjectSheetOrder = 1;
    final sheets = excel.tables.keys.toList();
    final cleanSubject = _normalizeArabic(subjectName);

    for (int i = 0; i < sheets.length; i++) {
      final cleanSheet = _normalizeArabic(sheets[i]);
      if (cleanSheet == cleanSubject || cleanSheet.contains(cleanSubject) || cleanSubject.contains(cleanSheet)) {
        subjectSheetOrder = i + 1;
        break;
      }
    }

    // 1. اختبارات نهاية الشهور: إذا كان بعد عبارة (اختبار نهاية) كلمة شهر -> ترتيب اسم الشهر
    if (title.contains('شهر')) {
      return _extractMonthOrderFromTitle(examTitle, sheet, resolvedTotal);
    }

    // 2. اختبار نهاية الفصل الدراسي: إذا كان بعد (اختبار نهاية) إما الفصل الأول أو الفصل الثاني -> رقم ترتيب ورقة المادة
    if (title.contains('فصل1') ||
        title.contains('فصلالاول') ||
        title.contains('فصل2') ||
        title.contains('فصلالثاني')) {
      return subjectSheetOrder;
    }

    // في حال عدم التطابق مع الشرطين نعتمد رقم ترتيب ورقة المادة كخيار قياسي
    return subjectSheetOrder;
  }

  /// حساب فهرس عمود التحريري لاختبارات الشهور العادية
  static int calculateWrittenExamColumn({
    required int monthNumber,
    required int totalMonths,
  }) {
    final int term1Months = (totalMonths == 6) ? 3 : 4;
    if (monthNumber <= term1Months) {
      // عمود تحريري كل شهر هو الخانة الرابعة في كتلته (Index = 4 + (m-1)*5 + 3 = 2 + m*5)
      return 2 + (monthNumber * 5);
    } else {
      // قفز عمودي م١ وف١
      return 2 + (monthNumber * 5) + 2;
    }
  }

  /// حساب موقع عمود الرصد المستهدف (الشهور، أو ف١، أو ف٢) مع مراعاة إزاحة الـ 5 والـ 10 أعمدة بدقة
  static int resolveTargetExamColumnIndex({
    required String selectedPeriod,
    required int totalMonths,
  }) {
    final clean = _normalizeArabic(selectedPeriod);
    final int term1Months = (totalMonths == 6) ? 3 : 4;

    // 1. حساب موقع عمود نهاية الفصل الأول (ف١)
    if (clean == 'ف1' || clean == 'ف١' || clean.contains('فصل1') || clean.contains('فصل اول')) {
      // في نظام 8 أشهر: 4 + (4 * 5) + 1 = 25
      // في نظام 6 أشهر: 4 + (3 * 5) + 1 = 20 (تراجع 5 أعمدة)
      return 4 + (term1Months * 5) + 1;
    }

    // 2. حساب موقع عمود نهاية الفصل الثاني (ف٢)
    if (clean == 'ف2' || clean == 'ف٢' || clean.contains('فصل2') || clean.contains('فصل ثاني')) {
      // في نظام 8 أشهر: 4 + (8 * 5) + 2 + 1 = 47
      // في نظام 6 أشهر: 4 + (6 * 5) + 2 + 1 = 37 (تراجع 10 أعمدة)
      return 4 + (totalMonths * 5) + 2 + 1;
    }

    // 3. حساب عمود اختبار الشهور العادية
    final match = RegExp(r'\d+').firstMatch(clean);
    int monthIndex = 1;
    if (match != null) {
      monthIndex = int.tryParse(match.group(0)!) ?? 1;
    }

    return calculateWrittenExamColumn(
      monthNumber: monthIndex,
      totalMonths: totalMonths,
    );
  }

  /// قراءة ملف الإكسيل واستخراج بيانات طلاب الصف المحدد من ورقة المادة المطابقة
  /// بناءً على مقارنة اسم الصف بالعمود C من أول طالب حتى آخر طالب في الصف
  static Future<StudentExcelResult> parseExcelFile(
    String filePath, {
    String? expectedSubject,
    String? targetGrade,
    String? examTitle,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      throw Exception('ملف الإكسيل فارغ ولا يحتوي على جداول بيانات.');
    }

    // 1. التنشيط التلقائي لورقة المادة المطابقة لاسم المادة في ترويسة الاختبار
    String targetSheetName = excel.tables.keys.first;
    final cleanExpected = _normalizeArabic(expectedSubject ?? '');

    if (cleanExpected.isNotEmpty) {
      for (final sheetName in excel.tables.keys) {
        final normSheet = _normalizeArabic(sheetName);
        if (normSheet == cleanExpected || normSheet.contains(cleanExpected) || cleanExpected.contains(normSheet)) {
          targetSheetName = sheetName;
          break;
        }
      }
    }

    final sheet = excel.tables[targetSheetName]!;
    final rows = sheet.rows;

    if (rows.length < 4) {
      throw Exception('ورقة العمل لا تحتوي على بيانات كافية (الطلاب يبدأون من الصف الرابع).');
    }

    final int detectedMonths = detectTotalMonths(sheet);
    final String cleanTargetGrade = _normalizeArabic(targetGrade ?? '');
    final List<StudentData> students = [];

    // 2. احتساب الكود الذكي يمين الـ QR ديناميكياً بحسب عنوان الاختبار وترتيب ورقة المادة
    final int calculatedCode = resolveSmartQrCodeNumberDynamic(
      examTitle: examTitle ?? '',
      subjectName: expectedSubject ?? targetSheetName,
      excel: excel,
      totalMonths: detectedMonths,
    );

    // 3. البدء الصارم من الصف الرابع (index = 3) ومسح العمود C لجلب نطاق الصف المحدد
    const int startRowIndex = 3;
    bool foundGradeBlock = false;

    for (int r = startRowIndex; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      // عمود A (رقم الجلوس - index 0)
      final rawSeat = row.isNotEmpty ? _extractCleanText(row[0]) : '';
      // عمود B (اسم الطالب - index 1)
      final rawName = row.length > 1 ? _extractCleanText(row[1]) : '';
      // عمود C (الصف الدراسي - index 2)
      final rawGrade = row.length > 2 ? _extractCleanText(row[2]) : '';
      // عمود D (الرقم السري - index 3)
      final rawSecret = row.length > 3 ? _extractCleanText(row[3]) : '';

      // تجاهل الأسطر الفارغة تماماً
      if (rawSeat.isEmpty && rawName.isEmpty && rawSecret.isEmpty) {
        continue;
      }

      // فحص مطابقة الصف بالعمود C
      bool isMatch = false;
      if (cleanTargetGrade.isEmpty) {
        isMatch = true; // استيراد الجميع إذا لم يحدد صف
      } else {
        isMatch = _isGradeMatch(rawGrade, targetGrade!);
      }

      if (isMatch) {
        foundGradeBlock = true;
        // الرقم السري المعتمد لرمز الـ QR: إن لم يوجد في عمود D يُربط رقم الجلوس بالكود الذكي
        final finalSecretCode = rawSecret.isNotEmpty ? rawSecret : '$rawSeat-$calculatedCode';

        students.add(StudentData(
          seatNo: rawSeat,
          name: rawName,
          grade: rawGrade.isNotEmpty ? rawGrade : (targetGrade ?? ''),
          secretCode: finalSecretCode,
        ));
      } else {
        // إذا كنا داخل نطاق الصف وبدأ صف دراسي جديد مختلف ننهي النطاق
        if (foundGradeBlock && rawGrade.trim().isNotEmpty) {
          break;
        }
      }
    }

    // 4. فرز الطلاب تصاعدياً برقم الجلوس لضمان صحة تسلسل الطباعة
    students.sort((a, b) {
      final intA = int.tryParse(a.seatNo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final intB = int.tryParse(b.seatNo.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (intA > 0 && intB > 0) return intA.compareTo(intB);
      return a.seatNo.compareTo(b.seatNo);
    });

    return StudentExcelResult(
      students: students,
      subjectCode: calculatedCode,
      matchedSubjectName: targetSheetName,
      totalMonths: detectedMonths,
    );
  }

  /// تحديث ورصد الدرجة مباشرة في ملف الإكسيل
  static Future<bool> updateStudentMarkInExcel({
    required String filePath,
    required String secretCode,
    required String sheetName,
    required double mark,
    required int targetColumnIndex,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      if (!excel.tables.containsKey(sheetName)) return false;
      final sheet = excel.tables[sheetName]!;

      int targetRowIndex = -1;
      final cleanSecret = _extractCleanText(secretCode);

      for (int r = 3; r < sheet.maxRows; r++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r));
        final val = _extractCleanText(cell);
        if (val == cleanSecret) {
          targetRowIndex = r;
          break;
        }
      }

      if (targetRowIndex == -1) return false;

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: targetColumnIndex, rowIndex: targetRowIndex))
          .value = DoubleCellValue(mark);

      final updatedBytes = excel.save();
      if (updatedBytes != null) {
        await file.writeAsBytes(updatedBytes, flush: true);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

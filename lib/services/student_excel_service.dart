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

  StudentExcelResult({
    required this.students,
    required this.subjectCode,
    required this.matchedSubjectName,
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

  /// تطبيع موحد للحروف والكلمات العربية
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

  /// فحص تطابق الصف بين المدخل وما هو مكتوب في خلية الإكسيل
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
    final isTargetGrade9 = normTarget.contains('تاسع') || normTarget == '9' || normTarget == '٩';
    if (isTargetGrade9 && (normCell.contains('تاسع') || normCell.contains('ثالث') || normCell == '9' || normCell == '٩')) {
      return true;
    }

    // توافق مسميات الصف الثامن (ثامن / ثاني إعدادي / 8 / ٨)
    final isTargetGrade8 = normTarget.contains('ثامن') || normTarget == '8' || normTarget == '٨';
    if (isTargetGrade8 && (normCell.contains('ثامن') || normCell.contains('ثاني') || normCell == '8' || normCell == '٨')) {
      return true;
    }

    // توافق مسميات الصف السابع (سابع / أول إعدادي / 7 / ٧)
    final isTargetGrade7 = normTarget.contains('سابع') || normTarget == '7' || normTarget == '٧';
    if (isTargetGrade7 && (normCell.contains('سابع') || normCell.contains('اول') || normCell == '7' || normCell == '٧')) {
      return true;
    }

    return false;
  }

  /// استخراج أسماء الشهور ديناميكياً من الصف الثاني (rowIndex = 1) بدءاً من العمود E (columnIndex = 4)
  static List<String> extractMonthsFromSheet(Sheet sheet, {int totalMonths = 8}) {
    List<String> months = [];
    int currentCol = 4; // عمود E
    final int monthsInTerm1 = (totalMonths == 6) ? 3 : 4;

    for (int m = 1; m <= totalMonths; m++) {
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

  /// تحديد الرقم الذكي المطبوع يمين الـ QR Code ديناميكياً وفق عنوان الاختبار وملف الإكسيل
  static int resolveSmartQrCodeNumberDynamic({
    required String examTitle,
    required String subjectName,
    required Excel excel,
    int totalMonths = 8,
  }) {
    final title = _normalizeArabic(examTitle);

    // 1. اختبارات نهاية الشهور: البحث عن اسم الشهر المطابق في الصف الثاني
    if (title.contains('شهر')) {
      final sheet = excel.tables.values.first;
      final dynamicMonths = extractMonthsFromSheet(sheet, totalMonths: totalMonths);

      for (int i = 0; i < dynamicMonths.length; i++) {
        final cleanMonthName = _normalizeArabic(dynamicMonths[i]);
        if (cleanMonthName.isNotEmpty && (title.contains(cleanMonthName) || cleanMonthName.contains(title))) {
          return i + 1; // ترتيب الشهر ديناميكياً (1, 2, 3...)
        }
      }

      // مطابقة احتياطية في حال كُتب رقم الشهر مباشرة
      final match = RegExp(r'شهر\s*([1-8١-٨])').firstMatch(title);
      if (match != null) {
        final d = match.group(1)!;
        return int.tryParse(d.replaceAll('١', '1').replaceAll('٢', '2').replaceAll('٣', '3')
            .replaceAll('٤', '4').replaceAll('٥', '5').replaceAll('٦', '6')
            .replaceAll('٧', '7').replaceAll('٨', '8')) ?? 1;
      }
    }

    // 2. اختبار نهاية الفصل الدراسي: ترتيب ورقة عمل المادة (من اليمين إلى اليسار)
    final sheets = excel.tables.keys.toList();
    final cleanSubject = _normalizeArabic(subjectName);

    for (int i = 0; i < sheets.length; i++) {
      final cleanSheet = _normalizeArabic(sheets[i]);
      if (cleanSheet == cleanSubject || cleanSheet.contains(cleanSubject) || cleanSubject.contains(cleanSheet)) {
        return i + 1; // رقم ترتيب ورقة المادة (1, 2, 3...)
      }
    }

    return 1;
  }

  /// قراءة ملف الإكسيل واستخراج بيانات طلاب الصف المحدد فقط مع احتساب الكود الذكي
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

    // 1. التنشيط التلقائي لورقة المادة
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

    final String requiredGrade = targetGrade?.trim() ?? '';
    final List<StudentData> students = [];

    // 2. البدء الصارم من الصف الرابع (index = 3)
    const int startRowIndex = 3;

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

      // 3. فلترة الصف الدراسي الصارمة بحسب العمود C
      if (requiredGrade.isNotEmpty) {
        final matches = _isGradeMatch(rawGrade, requiredGrade);
        if (!matches) {
          // استبعاد الطالب فوراً إذا لم يتطابق الصف
          continue;
        }
      }

      // إضافة الطالب المطابق فقط
      students.add(StudentData(
        seatNo: rawSeat,
        name: rawName,
        grade: rawGrade.isNotEmpty ? rawGrade : requiredGrade,
        secretCode: rawSecret.isNotEmpty ? rawSecret : rawSeat,
      ));
    }

    // 4. احتساب الكود الذكي يمين الـ QR ديناميكياً بحسب عنوان الاختبار
    final int calculatedCode = resolveSmartQrCodeNumberDynamic(
      examTitle: examTitle ?? '',
      subjectName: expectedSubject ?? targetSheetName,
      excel: excel,
    );

    return StudentExcelResult(
      students: students,
      subjectCode: calculatedCode,
      matchedSubjectName: targetSheetName,
    );
  }

  /// حساب عمود التحريري
  static int calculateWrittenExamColumn({
    required int monthNumber,
    required int totalMonths,
  }) {
    final int term1Months = (totalMonths == 6) ? 3 : 4;
    if (monthNumber <= term1Months) {
      return 2 + (monthNumber * 5); // شهر 1: عمود H (فهرس 7)
    } else {
      return 2 + (monthNumber * 5) + 2; // قفز عمودي م1 وف1
    }
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

      final bytes = await File(filePath).readAsBytes();
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

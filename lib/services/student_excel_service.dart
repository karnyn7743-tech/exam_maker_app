import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';
import 'excel_file_access_service.dart';

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

class StudentSheetOptions {
  final List<String> grades;
  final List<String> periods;

  const StudentSheetOptions({
    required this.grades,
    required this.periods,
  });
}

class StudentExcelService {
  /// إصلاح أبعاد ملف الإكسيل المخزنة بشكل خاطئ
  static Uint8List _fixExcelDimensions(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();

      for (final file in archive) {
        if (file.isFile && file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml')) {
          final contentBytes = file.content as List<int>;
          String content = utf8.decode(contentBytes);
          
          if (content.contains('<dimension')) {
            content = content.replaceAll(RegExp(r'<dimension[^>]*>'), '<dimension ref="A1:Z10000"/>');
          }
          
          final newFile = ArchiveFile(file.name, content.length, utf8.encode(content));
          newArchive.addFile(newFile);
        } else {
          newArchive.addFile(file);
        }
      }

      final zipEncoder = ZipEncoder();
      final encoded = zipEncoder.encode(newArchive); 
      
      if (encoded != null) {
        return Uint8List.fromList(encoded);
      }
      return bytes;
    } catch (e) {
      return bytes; 
    }
  }

  /// استخراج النص النقي الخام
  static String _extractCleanText(dynamic cell) {
    if (cell == null) return '';
    final val = (cell is Data) ? cell.value : cell;
    if (val == null) return '';

    String text;
    if (val is TextCellValue) {
      text = val.value.text ?? '';
    } else if (val is IntCellValue) {
      text = val.value.toString();
    } else if (val is DoubleCellValue) {
      text = val.value.toInt().toString();
    } else {
      text = val.toString();
    }

    if (text.startsWith('TextCellValue(') && text.endsWith(')')) {
      text = text.substring(14, text.length - 1);
    }

    // إزالة المسافات الخفية وعلامات الاتجاه
    return text.replaceAll(RegExp(r'[\u200B-\u200F\u061C\uFEFF\u00A0\u00AD]'), '').trim();
  }

  /// تطبيع الحروف
  static String _normalizeArabic(String text) {
    var s = _extractCleanText(text).toLowerCase();
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    s = s.replaceAll('ة', 'ه');
    s = s.replaceAll('ى', 'ي');
    s = s.replaceAll(RegExp(r'[\u064B-\u0652]'), ''); // إزالة التشكيل
    s = s.replaceAll('\u0640', ''); // إزالة التطويل (الكشيدة)
    s = s.replaceAll('الصف', '').replaceAll('اساسي', '').replaceAll('الاساسي', '').trim();
    s = s.replaceAll(RegExp(r'\s+'), ''); // إزالة كل المسافات
    return s;
  }

  /// ✅ التعديل الجذري: التطابق التام المباشر فقط
  static bool _isGradeMatch(String studentGradeCell, String targetGrade) {
    final normCell = _normalizeArabic(studentGradeCell);
    final normTarget = _normalizeArabic(targetGrade);

    if (normTarget.isEmpty) return true;
    if (normCell.isEmpty) return false;

    // 1. التطابق التام المباشر (تاسع == تاسع)
    if (normCell == normTarget) return true;

    // 2. التطابق بعد إزالة "ال" التعريف (تاسع == التاسع)
    final cellClean = normCell.replaceFirst(RegExp(r'^ال'), '');
    final targetClean = normTarget.replaceFirst(RegExp(r'^ال'), '');
    if (cellClean == targetClean) return true;

    // 3. مطابقة الأرقام (9 == تاسع)
    final Map<String, List<String>> map = {
      'اول': ['1', '١'],
      'ثاني': ['2', '٢'],
      'ثالث': ['3', '٣'],
      'رابع': ['4', '٤'],
      'خامس': ['5', '٥'],
      'سادس': ['6', '٦'],
      'سابع': ['7', '٧'],
      'ثامن': ['8', '٨'],
      'تاسع': ['9', '٩'],
    };

    for (final entry in map.entries) {
      if (cellClean == entry.key || entry.value.contains(cellClean)) {
        if (targetClean == entry.key || entry.value.contains(targetClean)) {
          return true;
        }
      }
    }

    return false;
  }

  static int detectTotalMonths(Sheet sheet) {
    final cellFourthMonth = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 19, rowIndex: 1));
    final rawText = _extractCleanText(cellFourthMonth);
    final text = _normalizeArabic(rawText);

    if (text.isEmpty || text == 'م1' || text == 'م١' || text.contains('محصله') || text.contains('فصل1')) {
      return 6;
    }
    return 8;
  }

  static Future<bool> validateExcelStructure(String filePath) async {
    try {
      final bytes = await ExcelFileAccessService.readBytes(filePath);
      final fixedBytes = _fixExcelDimensions(bytes);
      final excel = Excel.decodeBytes(fixedBytes);
      
      if (excel.tables.isEmpty) return false;

      final sheet = excel.tables.values.first;
      if (sheet.maxRows < 4) return false;

      final seatCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2));
      final nameCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2));

      final seatHeader = _normalizeArabic(_extractCleanText(seatCell));
      final nameHeader = _normalizeArabic(_extractCleanText(nameCell));

      bool hasExpectedHeaders = (seatHeader.contains('جلوس') || seatHeader.contains('رقم')) ||
          (nameHeader.contains('اسم') || nameHeader.contains('طالب'));

      final testSeat = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3)));
      final testName = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3)));
      bool hasStudentRow = testSeat.isNotEmpty || testName.isNotEmpty;

      return hasExpectedHeaders || hasStudentRow;
    } catch (_) {
      return false;
    }
  }

  static List<String> extractMonthsFromSheet(Sheet sheet, {int? totalMonths}) {
    final int resolvedTotal = totalMonths ?? detectTotalMonths(sheet);
    List<String> months = [];
    int currentCol = 4;
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
        currentCol += 2;
      }
    }
    return months;
  }

  /// أسماء أوراق المواد التي تحتوي على كشف طلاب صحيح.
  static Future<List<String>> getSubjectSheetNames(String filePath) async {
    final bytes = await ExcelFileAccessService.readBytes(filePath);
    final excel = Excel.decodeBytes(_fixExcelDimensions(bytes));
    return excel.tables.entries
        .where((entry) => _isSubjectSheet(entry.value))
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  /// الصفوف الدراسية وأسماء الأشهر والفصلين من ورقة المادة المختارة.
  static Future<StudentSheetOptions> getSheetOptions(
    String filePath,
    String sheetName,
  ) async {
    final bytes = await ExcelFileAccessService.readBytes(filePath);
    final excel = Excel.decodeBytes(_fixExcelDimensions(bytes));
    final sheet = excel.tables[sheetName];
    if (sheet == null || !_isSubjectSheet(sheet)) {
      throw Exception('ورقة المادة المحددة لا تحتوي على كشف طلاب صالح.');
    }

    final grades = <String>[];
    final seenGrades = <String>{};
    for (int row = 3; row < sheet.maxRows; row++) {
      final grade = _extractCleanText(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)),
      );
      final key = _normalizeArabic(grade);
      if (grade.isNotEmpty && key.isNotEmpty && seenGrades.add(key)) {
        grades.add(grade);
      }
    }

    final periods = <String>[
      ...extractMonthsFromSheet(sheet),
      'الفصل الدراسي الأول',
      'الفصل الدراسي الثاني',
    ];

    return StudentSheetOptions(grades: grades, periods: periods);
  }

  static int _extractMonthOrderFromTitle(String examTitle, Sheet sheet, int totalMonths) {
    final title = _normalizeArabic(examTitle);
    final dynamicMonths = extractMonthsFromSheet(sheet, totalMonths: totalMonths);

    // The monthly code must come from the month sequence in row 2 of the
    // selected Excel worksheet; never substitute a hard-coded calendar order.
    for (int i = 0; i < dynamicMonths.length; i++) {
      final cleanMonthName = _normalizeArabic(dynamicMonths[i]);
      if (cleanMonthName.isNotEmpty &&
          (title.contains(cleanMonthName) || cleanMonthName.contains(title))) {
        return i + 1;
      }
    }

    throw Exception(
      'لم يتم العثور على اسم الشهر في عنوان الاختبار ضمن أسماء الأشهر في الصف الثاني من ورقة Excel المحددة. راجع عنوان الاختبار وورقة المادة.',
    );
  }

  /// يميز أوراق المواد من أوراق البيانات والإعدادات اعتماداً على
  /// ترويسة كشف الطلاب الموجودة في الصف الثالث (الفهرس 2).
  static bool _isSubjectSheet(Sheet sheet) {
    if (sheet.maxRows < 4 || sheet.maxColumns < 2) return false;

    final seatHeader = _normalizeArabic(_extractCleanText(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)),
    ));
    final nameHeader = _normalizeArabic(_extractCleanText(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)),
    ));

    final hasSeatHeader =
        seatHeader.contains('جلوس') || seatHeader == 'رقم' ||
        seatHeader.contains('رقمالجلوس');
    final hasNameHeader =
        nameHeader.contains('اسم') || nameHeader.contains('طالب');

    if (!hasSeatHeader || !hasNameHeader) return false;

    // لا نعد ورقة فارغة أو ورقة إعدادات ورقة مادة لمجرد وجود عنوان مشابه.
    for (int row = 3; row < sheet.maxRows && row < 12; row++) {
      final seat = _extractCleanText(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)),
      );
      final name = _extractCleanText(
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)),
      );
      if (seat.isNotEmpty || name.isNotEmpty) return true;
    }
    return false;
  }

  static bool _isSemesterTitle(String normalizedTitle) {
    // نزيل علامات الترقيم والمسافات والرموز الخفية حتى لا يتأثر
    // التعرف باختلاف كتابة العبارة أو وجود نقطتين بعد "الدراسي".
    final cleanTitle = normalizedTitle.replaceAll(
      RegExp(r'[^ء-ي0-9٠-٩]'),
      '',
    );

    // يكفي وجود كلمة "فصل" مع تحديد الأول أو الثاني؛ وهذا يشمل:
    // الفصل الدراسي الأول/الثاني، ونهاية الفصل الدراسي: الأول/الثاني.
    final hasSemesterWord = cleanTitle.contains('فصل');
    final isFirstSemester =
        cleanTitle.contains('اول') ||
        cleanTitle.contains('١') ||
        cleanTitle.contains('1');
    final isSecondSemester =
        cleanTitle.contains('ثاني') ||
        cleanTitle.contains('٢') ||
        cleanTitle.contains('2');

    return hasSemesterWord && (isFirstSemester || isSecondSemester);
  }

  static int resolveSmartQrCodeNumberDynamic({
    required String examTitle,
    required String subjectName,
    required Excel excel,
    int? totalMonths,
  }) {
    final title = _normalizeArabic(examTitle);
    final cleanSubject = _normalizeArabic(subjectName);

    if (cleanSubject.isEmpty) {
      throw Exception('يرجى تحديد اسم المادة أولاً.');
    }

    // الترتيب يحسب بين أوراق المواد فقط، مع تجاهل أوراق البيانات والإعدادات.
    final subjectSheets = excel.tables.entries
        .where((entry) => _isSubjectSheet(entry.value))
        .toList();

    int selectedSubjectIndex = -1;
    for (int i = 0; i < subjectSheets.length; i++) {
      final cleanSheet = _normalizeArabic(subjectSheets[i].key);
      if (cleanSheet == cleanSubject ||
          cleanSheet.contains(cleanSubject) ||
          cleanSubject.contains(cleanSheet)) {
        selectedSubjectIndex = i;
        break;
      }
    }

    if (selectedSubjectIndex < 0) {
      throw Exception(
        'لم يتم العثور على ورقة المادة المحددة ضمن أوراق المواد في ملف Excel. تحقق من اسم المادة وترويسة ورقة الطلاب.',
      );
    }

    final selectedSheet = subjectSheets[selectedSubjectIndex].value;
    final subjectSheetOrder = selectedSubjectIndex + 1;
    final int resolvedTotal = totalMonths ?? detectTotalMonths(selectedSheet);

    // الفصل الدراسي الأول أو الثاني: رقم ترتيب المادة بين أوراق المواد فقط.
    if (_isSemesterTitle(title)) {
      return subjectSheetOrder;
    }

    // بقية العناوين الشهرية تطابق اسم الشهر في الصف الثاني من ورقة المادة.
    return _extractMonthOrderFromTitle(examTitle, selectedSheet, resolvedTotal);
  }

  static int calculateWrittenExamColumn({
    required int monthNumber,
    required int totalMonths,
  }) {
    final int term1Months = (totalMonths == 6) ? 3 : 4;
    if (monthNumber <= term1Months) {
      return 2 + (monthNumber * 5);
    } else {
      return 2 + (monthNumber * 5) + 2;
    }
  }

  /// يحول اسم الشهر المختار إلى عمود الرصد اعتماداً على عناوين الصف الثاني
  /// في ورقة المادة، ولا يفترض أن اسم الشهر يحتوي على رقم.
  static Future<int> resolveTargetExamColumnIndexForSheet({
    required String filePath,
    required String sheetName,
    required String selectedPeriod,
  }) async {
    final bytes = await ExcelFileAccessService.readBytes(filePath);
    final excel = Excel.decodeBytes(_fixExcelDimensions(bytes));
    final sheet = excel.tables[sheetName];
    if (sheet == null || !_isSubjectSheet(sheet)) {
      throw Exception('ورقة المادة المحددة غير صالحة لحساب عمود الرصد.');
    }

    final cleanPeriod = _normalizeArabic(selectedPeriod);
    if (cleanPeriod == 'ف1' || cleanPeriod == 'ف١' ||
        cleanPeriod.contains('فصل1') || cleanPeriod.contains('فصل اول') ||
        cleanPeriod.contains('الفصلالاول')) {
      return resolveTargetExamColumnIndex(selectedPeriod: 'ف١', totalMonths: detectTotalMonths(sheet));
    }
    if (cleanPeriod == 'ف2' || cleanPeriod == 'ف٢' ||
        cleanPeriod.contains('فصل2') || cleanPeriod.contains('فصل ثاني') ||
        cleanPeriod.contains('الفصلالثاني')) {
      return resolveTargetExamColumnIndex(selectedPeriod: 'ف٢', totalMonths: detectTotalMonths(sheet));
    }

    final months = extractMonthsFromSheet(sheet);
    for (int i = 0; i < months.length; i++) {
      if (_normalizeArabic(months[i]) == cleanPeriod) {
        return calculateWrittenExamColumn(
          monthNumber: i + 1,
          totalMonths: detectTotalMonths(sheet),
        );
      }
    }
    throw Exception('اسم فترة الرصد غير موجود ضمن عناوين الأشهر في ورقة المادة.');
  }

  static int resolveTargetExamColumnIndex({
    required String selectedPeriod,
    required int totalMonths,
  }) {
    final clean = _normalizeArabic(selectedPeriod);
    final int term1Months = (totalMonths == 6) ? 3 : 4;

    if (clean == 'ف1' || clean == 'ف١' || clean.contains('فصل1') || clean.contains('فصل اول')) {
      return 4 + (term1Months * 5) + 1;
    }

    if (clean == 'ف2' || clean == 'ف٢' || clean.contains('فصل2') || clean.contains('فصل ثاني')) {
      return 4 + (totalMonths * 5) + 2 + 1;
    }

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

  static Future<StudentExcelResult> parseExcelFile(
    String filePath, {
    String? expectedSubject,
    String? targetGrade,
    String? examTitle,
  }) async {
    final bytes = await ExcelFileAccessService.readBytes(filePath);
    return parseExcelBytes(
      bytes,
      expectedSubject: expectedSubject,
      targetGrade: targetGrade,
      examTitle: examTitle,
    );
  }

  static StudentExcelResult parseExcelBytes(
    Uint8List bytes, {
    String? expectedSubject,
    String? targetGrade,
    String? examTitle,
  }) {
    final fixedBytes = _fixExcelDimensions(bytes);
    final excel = Excel.decodeBytes(fixedBytes);

    if (excel.tables.isEmpty) {
      throw Exception('ملف الإكسيل فارغ ولا يحتوي على جداول بيانات.');
    }

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

    if (sheet.maxRows < 4) {
      throw Exception('ورقة العمل لا تحتوي على بيانات كافية (الطلاب يبدأون من الصف الرابع).');
    }

    final int detectedMonths = detectTotalMonths(sheet);
    final String requiredGrade = targetGrade?.trim() ?? '';
    final List<StudentData> students = [];

    final int calculatedCode = resolveSmartQrCodeNumberDynamic(
      examTitle: examTitle ?? '',
      subjectName: expectedSubject ?? targetSheetName,
      excel: excel,
      totalMonths: detectedMonths,
    );

    const int colSeat = 0;
    const int colName = 1;
    const int colGrade = 2;
    const int colSecret = 3;

    int r = 3;
    int consecutiveEmptyRows = 0;
    int safeLimit = sheet.maxRows + 50;

    while (r < safeLimit) {
      final rawSeat = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: colSeat, rowIndex: r)));
      final rawName = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: colName, rowIndex: r)));
      final rawGrade = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: colGrade, rowIndex: r)));
      final rawSecret = _extractCleanText(sheet.cell(CellIndex.indexByColumnRow(columnIndex: colSecret, rowIndex: r)));

      if (rawSeat.isEmpty && rawName.isEmpty) {
        consecutiveEmptyRows++;
        if (consecutiveEmptyRows > 30) break; 
        r++;
        continue;
      }
      
      consecutiveEmptyRows = 0; 

      // تجاوز صف العناوين فقط، دون استبعاد أسماء الطلاب التي تحتوي على «اسم».
      final normalizedSeatHeader = _normalizeArabic(rawSeat);
      final normalizedNameHeader = _normalizeArabic(rawName);
      final bool isHeaderRow =
          normalizedSeatHeader.contains('جلوس') ||
          normalizedNameHeader == 'اسم' ||
          normalizedNameHeader.startsWith('اسمالطالب');

      if (isHeaderRow) {
        r++;
        continue;
      }

      if (requiredGrade.isNotEmpty) {
        final bool isMatch = _isGradeMatch(rawGrade, requiredGrade);
        if (!isMatch) {
          r++;
          continue; 
        }
      }

      final finalSecretCode = rawSecret.isNotEmpty ? rawSecret : '$rawSeat-$calculatedCode';

      students.add(StudentData(
        seatNo: rawSeat,
        name: rawName,
        grade: rawGrade.isNotEmpty ? rawGrade : requiredGrade,
        secretCode: finalSecretCode,
      ));
      
      r++;
    }

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


  static String _normalizeSecretCode(dynamic value) {
    var text = value?.toString() ?? '';
    const digits = {
      '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
      '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
      '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
      '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    };
    digits.forEach((key, replacement) {
      text = text.replaceAll(key, replacement);
    });
    return text.replaceAll(
      RegExp(r'[\u200B-\u200F\u061C\uFEFF\u00A0\u00AD\s]'),
      '',
    );
  }

  static String _normalizeZipEntryPath(String path) {
    final parts = <String>[];
    for (final part in path.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(part);
      }
    }
    return parts.join('/');
  }

  static String _worksheetPath(Archive archive, String sheetName) {
    final workbookFile = archive.findFile('xl/workbook.xml');
    final relsFile = archive.findFile('xl/_rels/workbook.xml.rels');
    if (workbookFile == null || relsFile == null) {
      throw Exception('بنية ملف Excel لا تحتوي على روابط أوراق العمل.');
    }
    final workbook = XmlDocument.parse(utf8.decode(workbookFile.content as List<int>));
    final rels = XmlDocument.parse(utf8.decode(relsFile.content as List<int>));
    XmlElement? selected;
    for (final element in workbook.descendants.whereType<XmlElement>()) {
      if (element.name.local == 'sheet' &&
          element.getAttribute('name')?.trim() == sheetName.trim()) {
        selected = element;
        break;
      }
    }
    if (selected == null) throw Exception('لم يتم العثور على ورقة العمل: $sheetName');
    String? relationId;
    for (final attribute in selected.attributes) {
      if (attribute.name.local == 'id') relationId = attribute.value;
    }
    if (relationId == null) throw Exception('تعذر تحديد رابط ورقة العمل.');
    for (final relation in rels.descendants.whereType<XmlElement>()) {
      if (relation.name.local == 'Relationship' &&
          relation.getAttribute('Id') == relationId) {
        final target = relation.getAttribute('Target');
        if (target == null) break;
        return _normalizeZipEntryPath(
          target.startsWith('/') ? target.substring(1) : 'xl/' + target,
        );
      }
    }
    throw Exception('تعذر الوصول إلى ملف ورقة العمل داخل المصنف.');
  }

  static String _excelColumnLetters(int columnIndex) {
    var number = columnIndex + 1;
    var result = '';
    while (number > 0) {
      final remainder = (number - 1) % 26;
      result = String.fromCharCode(65 + remainder) + result;
      number = (number - 1) ~/ 26;
    }
    return result;
  }

  static Uint8List _patchExcelMarkBytes({
    required Uint8List originalBytes,
    required String sheetName,
    required int rowIndex,
    required int columnIndex,
    required double mark,
  }) {
    final archive = ZipDecoder().decodeBytes(originalBytes);
    final sheetPath = _worksheetPath(archive, sheetName);
    ArchiveFile? sheetFile;
    for (final entry in archive.files) {
      if (entry.isFile && _normalizeZipEntryPath(entry.name) == sheetPath) {
        sheetFile = entry;
        break;
      }
    }
    if (sheetFile == null) throw Exception('تعذر العثور على ملف ورقة العمل داخل Excel.');
    final rawXml = utf8.decode(sheetFile.content as List<int>);
    final cellRef = _excelColumnLetters(columnIndex) + (rowIndex + 1).toString();
    final rowNumber = rowIndex + 1;
    final rowPattern = RegExp(
      r'(<row\b[^>]*\br="' + rowNumber.toString() + r'"[^>]*>)(.*?)(</row>)',
      dotAll: true,
    );
    if (!rowPattern.hasMatch(rawXml)) {
      throw Exception('تعذر العثور على صف الطالب داخل ورقة Excel.');
    }

    final updatedXml = rawXml.replaceFirstMapped(rowPattern, (rowMatch) {
      final rowOpen = rowMatch.group(1)!;
      var rowBody = rowMatch.group(2)!;
      final rowClose = rowMatch.group(3)!;
      final cellPattern = RegExp(
        r'<c\b(?=[^>]*\br="' + cellRef + r'")[^>]*(?:/>|>.*?</c>)',
        dotAll: true,
      );
      if (cellPattern.hasMatch(rowBody)) {
        rowBody = rowBody.replaceFirstMapped(cellPattern, (cellMatch) {
          var cellXml = cellMatch.group(0)!;
          final valuePattern = RegExp(r'<v(?:\s[^>]*)?>.*?</v>', dotAll: true);
          final valueXml = '<v>' + mark.toString() + '</v>';
          if (valuePattern.hasMatch(cellXml)) {
            return cellXml.replaceFirst(valuePattern, valueXml);
          }
          if (cellXml.endsWith('/>')) {
            return cellXml.replaceFirst(RegExp(r'/>$'), '>' + valueXml + '</c>');
          }
          if (cellXml.contains('</f>')) {
            return cellXml.replaceFirst('</f>', '</f>' + valueXml);
          }
          return cellXml.replaceFirst('</c>', valueXml + '</c>');
        });
      } else {
        rowBody = rowBody + '<c r="' + cellRef + '"><v>' + mark.toString() + '</v></c>';
      }
      return rowOpen + rowBody + rowClose;
    });

    final rebuilt = Archive();
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      if (_normalizeZipEntryPath(entry.name) == sheetPath) {
        final data = utf8.encode(updatedXml);
        rebuilt.addFile(ArchiveFile(entry.name, data.length, data));
      } else {
        final data = entry.content as List<int>;
        rebuilt.addFile(ArchiveFile(entry.name, data.length, data));
      }
    }
    final encoded = ZipEncoder().encode(rebuilt);
    if (encoded == null) throw Exception('تعذر إعادة تكوين ملف Excel بعد تحديث الدرجة.');
    return Uint8List.fromList(encoded);
  }

  /// القيم المعادة: saved, alreadyExists, studentNotFound, duplicateStudent, invalidTarget, error.
  static Future<String> saveOmrMarkToExcel({
    required String filePath,
    required String secretCode,
    required String sheetName,
    required double mark,
    required int targetColumnIndex,
    bool allowOverwrite = false,
  }) async {
    try {
      if (targetColumnIndex < 4 || mark < 0) return 'invalidTarget';
      final bytes = await ExcelFileAccessService.readBytes(filePath);
      final excel = Excel.decodeBytes(_fixExcelDimensions(bytes));
      final sheet = excel.tables[sheetName];
      if (sheet == null) return 'invalidTarget';

      final cleanSecret = _normalizeSecretCode(secretCode);
      if (cleanSecret.isEmpty) return 'studentNotFound';

      final matchingRows = <int>[];
      for (int row = 3; row < sheet.maxRows; row++) {
        final value = _extractCleanText(
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)),
        );
        if (_normalizeSecretCode(value) == cleanSecret) matchingRows.add(row);
      }
      if (matchingRows.isEmpty) return 'studentNotFound';
      if (matchingRows.length > 1) return 'duplicateStudent';

      final targetCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: targetColumnIndex, rowIndex: matchingRows.single),
      );
      final existingValue = _extractCleanText(targetCell);
      if (existingValue.isNotEmpty && !allowOverwrite) return 'alreadyExists';

      // تحديث خلية واحدة في XML الأصلي؛ لا نعيد حفظ المصنف عبر Excel.save()
      // حتى لا تتغير التنسيقات أو المعادلات أو خصائص الأوراق الأخرى.
      final updatedBytes = _patchExcelMarkBytes(
        originalBytes: bytes,
        sheetName: sheetName,
        rowIndex: matchingRows.single,
        columnIndex: targetColumnIndex,
        mark: mark,
      );
      await ExcelFileAccessService.writeBytes(filePath, updatedBytes);
      return 'saved';
    } catch (_) {
      return 'error';
    }
  }

  static Future<bool> updateStudentMarkInExcel({
    required String filePath,
    required String secretCode,
    required String sheetName,
    required double mark,
    required int targetColumnIndex,
  }) async {
    final result = await saveOmrMarkToExcel(
      filePath: filePath,
      secretCode: secretCode,
      sheetName: sheetName,
      mark: mark,
      targetColumnIndex: targetColumnIndex,
      allowOverwrite: true,
    );
    return result == 'saved';
  }
}
), '><v>$mark</v></c>');
          }
          if (cellXml.contains('</f>')) {
            return cellXml.replaceFirst('</f>', '</f><v>$mark</v>');
          }
          return cellXml.replaceFirst('</c>', '<v>$mark</v></c>');
        });
      } else {
        rowBody = '$rowBody<c r="$cellRef"><v>$mark</v></c>';
      }
      return '$rowOpen$rowBody$rowClose';
    });

    final rebuilt = Archive();
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      if (_normalizeArchivePath(entry.name) == sheetPath) {
        final data = utf8.encode(updatedXml);
        rebuilt.addFile(ArchiveFile(entry.name, data.length, data));
      } else {
        final data = entry.content as List<int>;
        rebuilt.addFile(ArchiveFile(entry.name, data.length, data));
      }
    }
    final encoded = ZipEncoder().encode(rebuilt);
    if (encoded == null) throw Exception('تعذر إعادة تكوين ملف Excel بعد تحديث الدرجة.');
    return Uint8List.fromList(encoded);
  }

  /// حفظ درجة OMR مع منع الكتابة فوق درجة موجودة دون موافقة صريحة.
  /// القيم المعادة: saved, alreadyExists, studentNotFound, duplicateStudent, invalidTarget, error.
  static Future<String> saveOmrMarkToExcel({
    required String filePath,
    required String secretCode,
    required String sheetName,
    required double mark,
    required int targetColumnIndex,
    bool allowOverwrite = false,
  }) async {
    try {
      if (targetColumnIndex < 4 || mark < 0) return 'invalidTarget';
      final file = File(filePath);
      if (!await file.exists()) return 'error';

      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(_fixExcelDimensions(bytes));
      final sheet = excel.tables[sheetName];
      if (sheet == null) return 'invalidTarget';

      final cleanSecret = _extractCleanText(secretCode);
      if (cleanSecret.isEmpty) return 'studentNotFound';

      final matchingRows = <int>[];
      for (int row = 3; row < sheet.maxRows; row++) {
        final value = _extractCleanText(
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)),
        );
        if (value == cleanSecret) matchingRows.add(row);
      }
      if (matchingRows.isEmpty) return 'studentNotFound';
      if (matchingRows.length > 1) return 'duplicateStudent';

      final targetCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: targetColumnIndex, rowIndex: matchingRows.single),
      );
      final existingValue = _extractCleanText(targetCell);
      if (existingValue.isNotEmpty && !allowOverwrite) return 'alreadyExists';

      targetCell.value = DoubleCellValue(mark);
      final updatedBytes = excel.save();
      if (updatedBytes == null) return 'error';
      await file.writeAsBytes(updatedBytes, flush: true);
      return 'saved';
    } catch (_) {
      return 'error';
    }
  }

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
      final fixedBytes = _fixExcelDimensions(bytes);
      final excel = Excel.decodeBytes(fixedBytes);

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

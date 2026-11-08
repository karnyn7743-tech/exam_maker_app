import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
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
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
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

  static int _extractMonthOrderFromTitle(String examTitle, Sheet sheet, int totalMonths) {
    final title = _normalizeArabic(examTitle);

    final dynamicMonths = extractMonthsFromSheet(sheet, totalMonths: totalMonths);
    for (int i = 0; i < dynamicMonths.length; i++) {
      final cleanMonthName = _normalizeArabic(dynamicMonths[i]);
      if (cleanMonthName.isNotEmpty && (title.contains(cleanMonthName) || cleanMonthName.contains(title))) {
        return i + 1;
      }
    }

    const hijriMonths = {
      'محرم': 1, 'صفر': 2, 'ربيعالاول': 3, 'ربيعاول': 3, 'ربيعثاني': 4, 'ربيعالثاني': 4,
      'جماديالاولي': 5, 'جماديالاول': 5, 'جماديالاخره': 6, 'جماديالثانيه': 6,
      'رجب': 7, 'شعبان': 8, 'رمضان': 9, 'شوال': 10, 'ذوالقعده': 11, 'ذوالحجه': 12,
    };
    for (final entry in hijriMonths.entries) {
      if (title.contains(entry.key)) {
        return entry.value;
      }
    }

    const gregorianMonths = {
      'سبتمبر': 1, 'اكتوبر': 2, 'نوفمبر': 3, 'ديسمبر': 4,
      'يناير': 5, 'فبراير': 6, 'مارس': 7, 'ابريل': 8, 'مايو': 9,
    };
    for (final entry in gregorianMonths.entries) {
      if (title.contains(entry.key)) {
        return entry.value;
      }
    }

    final match = RegExp(r'شهر\s*([1-8١-٨])').firstMatch(title);
    if (match != null) {
      final d = match.group(1)!;
      return int.tryParse(d
          .replaceAll('١', '1').replaceAll('٢', '2').replaceAll('٣', '3')
          .replaceAll('٤', '4').replaceAll('٥', '5').replaceAll('٦', '6')
          .replaceAll('٧', '7').replaceAll('٨', '8')) ?? 1;
    }

    return 1;
  }

  static int resolveSmartQrCodeNumberDynamic({
    required String examTitle,
    required String subjectName,
    required Excel excel,
    int? totalMonths,
  }) {
    final title = _normalizeArabic(examTitle);
    final sheet = excel.tables.values.first;
    final int resolvedTotal = totalMonths ?? detectTotalMonths(sheet);

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

    if (title.contains('شهر')) {
      return _extractMonthOrderFromTitle(examTitle, sheet, resolvedTotal);
    }

    if (title.contains('فصل1') || title.contains('فصلالاول') ||
        title.contains('فصل2') || title.contains('فصلالثاني')) {
      return subjectSheetOrder;
    }

    return subjectSheetOrder;
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
    final bytes = await File(filePath).readAsBytes();
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

      if (rawSeat.contains('جلوس') || rawName.contains('اسم')) {
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

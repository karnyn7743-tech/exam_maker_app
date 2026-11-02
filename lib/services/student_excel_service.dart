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
  /// دالة ذكية لتطبيع ومطابقة أسماء الصفوف الدراسية في اليمن
  static String _normalizeArabic(String text) {
    var s = text.trim().toLowerCase();
    // توحيد الهمزات والألفات
    s = s.replaceAll(RegExp(r'[أإآ]'), 'ا');
    // توحيد التاء المربوطة والهاء
    s = s.replaceAll('ة', 'ه');
    // توحيد الياء والألف المقصورة
    s = s.replaceAll('ى', 'ي');
    // إزالة علامات التشكيل والفراغات الزائدة
    s = s.replaceAll(RegExp(r'[\u064B-\u0652]'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    // حذف كلمة "الصف" إن وجدت للمقارنة النظيفة
    s = s.replaceAll('الصف', '').trim();

    // ربط مسميات صفوف المرحلة الأساسية المتبادلة
    if (s == 'تاسع' || s == 'التاسع' || s == '9' || s == '٩' || s == 'ثالث اعدادي' || s == 'ثالث') {
      // تنبيه: في بعض المدارس يسمون الصف التاسع "ثالث" (أي ثالث متوسط/إعدادي)
    }
    return s;
  }

  /// فحص تطابق الصف بين المدخل وما هو مكتوب في خلية الإكسيل
  static bool _isGradeMatch(String studentGradeCell, String targetGrade) {
    final normCell = _normalizeArabic(studentGradeCell);
    final normTarget = _normalizeArabic(targetGrade);

    if (normTarget.isEmpty) return true; // إذا لم يحدد صفاً يستورد الجميع
    if (normCell.isEmpty) return false; // إذا كان هناك صف مستهدف وخلية الطالب فارغة يُرفض

    // تطابق مباشر
    if (normCell == normTarget || normCell.contains(normTarget) || normTarget.contains(normCell)) {
      return true;
    }

    // توافق خاص بالصف التاسع / الثالث إعدادي
    final isTargetGrade9 = normTarget.contains('تاسع') || normTarget == '9' || normTarget == '٩';
    if (isTargetGrade9 && (normCell.contains('تاسع') || normCell.contains('ثالث') || normCell == '9' || normCell == '٩')) {
      return true;
    }

    // توافق خاص بالصف الثامن / الثاني إعدادي
    final isTargetGrade8 = normTarget.contains('ثامن') || normTarget == '8' || normTarget == '٨';
    if (isTargetGrade8 && (normCell.contains('ثامن') || normCell.contains('ثاني') || normCell == '8' || normCell == '٨')) {
      return true;
    }

    // توافق خاص بالصف السابع / الأول إعدادي
    final isTargetGrade7 = normTarget.contains('سابع') || normTarget == '7' || normTarget == '٧';
    if (isTargetGrade7 && (normCell.contains('سابع') || normCell.contains('اول') || normCell == '7' || normCell == '٧')) {
      return true;
    }

    return false;
  }

  /// قراءة ملف الإكسيل واستخراج بيانات طلاب الصف المحدد فقط
  static Future<StudentExcelResult> parseExcelFile(
    String filePath, {
    String? expectedSubject,
    String? targetGrade,
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
      final rawSeat = row.isNotEmpty ? (row[0]?.value?.toString().trim() ?? '') : '';
      // عمود B (اسم الطالب - index 1)
      final rawName = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
      // عمود C (الصف الدراسي - index 2)
      final rawGrade = row.length > 2 ? (row[2]?.value?.toString().trim() ?? '') : '';
      // عمود D (الرقم السري - index 3)
      final rawSecret = row.length > 3 ? (row[3]?.value?.toString().trim() ?? '') : '';

      // تجاهل الأسطر الفارغة تماماً
      if (rawSeat.isEmpty && rawName.isEmpty && rawSecret.isEmpty) {
        continue;
      }

      // 3. فلترة الصف الدراسي الصارمة
      if (requiredGrade.isNotEmpty) {
        final matches = _isGradeMatch(rawGrade, requiredGrade);
        if (!matches) {
          // إذا لم يطابق الصف المطلوب يتم استبعاده فوراً
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

    return StudentExcelResult(
      students: students,
      subjectCode: 1,
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

      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      if (!excel.tables.containsKey(sheetName)) return false;
      final sheet = excel.tables[sheetName]!;

      int targetRowIndex = -1;
      final cleanSecret = secretCode.trim();

      for (int r = 3; r < sheet.maxRows; r++) {
        final cellVal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value;
        if (cellVal != null && cellVal.toString().trim() == cleanSecret) {
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

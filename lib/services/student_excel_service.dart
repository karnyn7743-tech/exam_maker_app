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
  /// قراءة ملف الإكسيل واستخراج بيانات الطلاب بدءاً من الصف الرابع (فهرس 3)
  /// مع تنشيط ورقة المادة المطابقة تلقائياً إن وجدت
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

    // 1. التنشيط الذكي لورقة العمل (Sheet) المطابقة لاسم المادة
    String targetSheetName = excel.tables.keys.first;
    final cleanExpected = expectedSubject?.trim().toLowerCase() ?? '';

    if (cleanExpected.isNotEmpty) {
      for (final sheetName in excel.tables.keys) {
        final cleanSheet = sheetName.trim().toLowerCase();
        if (cleanSheet == cleanExpected || cleanSheet.contains(cleanExpected) || cleanExpected.contains(cleanSheet)) {
          targetSheetName = sheetName;
          break;
        }
      }
    }

    final sheet = excel.tables[targetSheetName]!;
    final rows = sheet.rows;

    if (rows.length < 4) {
      throw Exception('ورقة العمل لا تحتوي على بيانات طلاب كافية (البيانات تبدأ من الصف الرابع).');
    }

    final cleanTargetGrade = targetGrade?.trim().toLowerCase() ?? '';
    final List<StudentData> students = [];

    // 2. البدء الصارم من الصف الرابع الفعلي (فهرس 3)
    const int startRowIndex = 3;

    for (int r = startRowIndex; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      // عمود A (رقم الجلوس - فهرس 0)
      final rawSeat = row.isNotEmpty ? (row[0]?.value?.toString().trim() ?? '') : '';
      // عمود B (اسم الطالب - فهرس 1)
      final rawName = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
      // عمود C (الصف الدراسي - فهرس 2)
      final rawGrade = row.length > 2 ? (row[2]?.value?.toString().trim() ?? '') : '';
      // عمود D (الرقم السري - فهرس 3) وهو محتوى الـ QR الحصري
      final rawSecret = row.length > 3 ? (row[3]?.value?.toString().trim() ?? '') : '';

      // شرط وجود الطالب: وجود الرقم السري أو الاسم
      if (rawSecret.isNotEmpty || rawName.isNotEmpty) {
        if (cleanTargetGrade.isNotEmpty && rawGrade.isNotEmpty) {
          final cleanStudentGrade = rawGrade.toLowerCase();
          if (!cleanStudentGrade.contains(cleanTargetGrade) && !cleanTargetGrade.contains(cleanStudentGrade)) {
            continue;
          }
        }

        students.add(StudentData(
          seatNo: rawSeat,
          name: rawName,
          grade: rawGrade,
          secretCode: rawSecret.isNotEmpty ? rawSecret : rawSeat,
        ));
      }
    }

    return StudentExcelResult(
      students: students,
      subjectCode: 1,
      matchedSubjectName: targetSheetName,
    );
  }

  /// حساب عمود التحريري في الإكسيل بناءً على رقم الشهر ونظام السنة (6 أو 8 أشهر)
  static int calculateWrittenExamColumn({
    required int monthNumber, // 1..8
    required int totalMonths, // 6 أو 8
  }) {
    final int term1Months = (totalMonths == 6) ? 3 : 4;
    // أول شهر تحريري هو H (فهرس 7 بنظام 0-based)
    if (monthNumber <= term1Months) {
      return 2 + (monthNumber * 5); // شهر 1: 2+5 = 7 (العمود H)
    } else {
      // قفز عمودين إضافيين لتخطي عمودي محصلة ف1 واختبار ف1 [م1 ، ف1]
      return 2 + (monthNumber * 5) + 2;
    }
  }

  /// رصد وتحديث درجة الطالب مباشرة في نفس مسار الملف ونفس الخلية
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

      // البحث عن صف الطالب بالرقم السري في العمود D (فهرس 3) بدءاً من الصف الرابع
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

      // كتابة الدرجة في خلية التقاطع المحددة
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: targetColumnIndex, rowIndex: targetRowIndex))
          .value = DoubleCellValue(mark);

      // حفظ مباشر في نفس الملف المختار
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

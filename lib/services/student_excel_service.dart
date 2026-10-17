import 'dart:io';
import 'package:excel/excel.dart';

class StudentData {
  final String seatNo;
  final String name;
  final String secretCode;

  StudentData({
    required this.seatNo,
    required this.name,
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
  /// قراءة ملف الإكسيل واستخراج بيانات الطلاب وكود المادة
  static Future<StudentExcelResult> parseExcelFile(
    String filePath, {
    String? expectedSubject,
  }) async {
    final bytes = await File(filePath).readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    if (excel.tables.isEmpty) {
      throw Exception('ملف الإكسيل فارغ ولا يحتوي على جداول بيانات.');
    }

    final sheet = excel.tables.values.first;
    final rows = sheet.rows;

    if (rows.isEmpty) {
      throw Exception('ورقة العمل لا تحتوي على صفوف.');
    }

    // 1. تحديد كود المادة من الصف الأول (العناوين) من العمود E (فهرس 4) إلى العمود S (فهرس 18)
    int subjectCode = 1;
    String matchedSubjectName = '';

    final headerRow = rows.first;
    final cleanExpected = expectedSubject?.trim().toLowerCase() ?? '';

    for (int colIndex = 4; colIndex <= 18 && colIndex < headerRow.length; colIndex++) {
      final cellValue = headerRow[colIndex]?.value?.toString().trim() ?? '';
      final currentSubjectNum = (colIndex - 4) + 1;

      if (cleanExpected.isNotEmpty &&
          cellValue.isNotEmpty &&
          (cellValue.toLowerCase().contains(cleanExpected) || cleanExpected.contains(cellValue.toLowerCase()))) {
        subjectCode = currentSubjectNum;
        matchedSubjectName = cellValue;
        break;
      }
    }

    // 2. قراءة صفوف الطلاب (تخطي الصف الأول)
    final List<StudentData> students = [];

    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      // عمود A (رقم الجلوس)
      final rawSeat = row.isNotEmpty ? (row[0]?.value?.toString().trim() ?? '') : '';
      // عمود B (اسم الطالب)
      final rawName = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
      // عمود D (الرقم السري المشفر لتوليد الـ QR)
      final rawSecret = row.length > 3 ? (row[3]?.value?.toString().trim() ?? '') : '';

      if (rawSeat.isNotEmpty && rawName.isNotEmpty) {
        students.add(StudentData(
          seatNo: rawSeat,
          name: rawName,
          // إذا كان العمود D فارغاً، نضع رقم الجلوس كبديل آمن لمحتوى الـ QR
          secretCode: rawSecret.isNotEmpty ? rawSecret : rawSeat,
        ));
      }
    }

    return StudentExcelResult(
      students: students,
      subjectCode: subjectCode,
      matchedSubjectName: matchedSubjectName,
    );
  }
}

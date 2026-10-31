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
  /// قراءة ملف الإكسيل واستخراج بيانات الطلاب وكود المادة مع إمكانية التصفية بحسب الصف الدراسي
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

    final cleanTargetGrade = targetGrade?.trim().toLowerCase() ?? '';
    final List<StudentData> students = [];

    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      // عمود A (رقم الجلوس - فهرس 0)
      final rawSeat = row.isNotEmpty ? (row[0]?.value?.toString().trim() ?? '') : '';
      // عمود B (اسم الطالب - فهرس 1)
      final rawName = row.length > 1 ? (row[1]?.value?.toString().trim() ?? '') : '';
      // عمود C (الصف الدراسي - فهرس 2)
      final rawGrade = row.length > 2 ? (row[2]?.value?.toString().trim() ?? '') : '';
      // عمود D (الرقم السري المشفر لتوليد الـ QR - فهرس 3)
      final rawSecret = row.length > 3 ? (row[3]?.value?.toString().trim() ?? '') : '';

      if (rawSeat.isNotEmpty && rawName.isNotEmpty) {
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
      subjectCode: subjectCode,
      matchedSubjectName: matchedSubjectName,
    );
  }

  /// رصد وتحديث درجة الطالب مباشرة في عمود المادة المطابق داخل ملف الإكسيل
  static Future<bool> updateStudentMarkInExcel({
    required String filePath,
    required String studentIdentifier,
    required String subjectName,
    required double mark,
    int? subjectCode,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) return false;
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName]!;
      final rows = sheet.rows;

      if (rows.isEmpty) return false;

      int targetColIndex = -1;
      final headerRow = rows.first;
      final cleanSubject = subjectName.trim().toLowerCase();

      for (int col = 4; col <= 18 && col < headerRow.length; col++) {
        final cellText = headerRow[col]?.value?.toString().trim().toLowerCase() ?? '';
        final currentCode = (col - 4) + 1;

        if (subjectCode != null && subjectCode == currentCode) {
          targetColIndex = col;
          break;
        } else if (cleanSubject.isNotEmpty && cellText.isNotEmpty &&
            (cellText.contains(cleanSubject) || cleanSubject.contains(cellText))) {
          targetColIndex = col;
          break;
        }
      }

      if (targetColIndex == -1 && subjectCode != null) {
        targetColIndex = 3 + subjectCode;
      }

      if (targetColIndex == -1) return false;

      int targetRowIndex = -1;
      final cleanId = studentIdentifier.trim();

      for (int r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (row.isEmpty) continue;

        final seat = row.isNotEmpty ? (row[0]?.value?.toString().trim() ?? '') : '';
        final secret = row.length > 3 ? (row[3]?.value?.toString().trim() ?? '') : '';

        if (seat == cleanId || secret == cleanId) {
          targetRowIndex = r;
          break;
        }
      }

      if (targetRowIndex == -1) return false;

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: targetColIndex, rowIndex: targetRowIndex))
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

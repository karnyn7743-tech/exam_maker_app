import '../models/exam_models.dart';
import 'omr_scoring_service.dart';
import 'student_excel_service.dart';

enum OmrCommitStatus { saved, reviewRequired, studentNotFound, duplicateStudent, existingMark, invalidPeriod, saveFailed }

class OmrCommitResult {
  final OmrCommitStatus status;
  final String? studentName;
  final String? seatNumber;
  final int? targetColumn;
  const OmrCommitResult(this.status, {this.studentName, this.seatNumber, this.targetColumn});
}

/// يربط نتيجة التصحيح المعتمدة بكشف الطالب وعمود الفترة المحددة.
class OmrResultCommitService {
  static Future<OmrCommitResult> commit({
    required ExamModel exam,
    required OmrScoringResult scoring,
    required String excelPath,
    required String sheetName,
    required String selectedPeriod,
    required String qrSecretCode,
    bool allowOverwrite = false,
  }) async {
    if (!scoring.canBeAutomaticallyFinalized) {
      return const OmrCommitResult(OmrCommitStatus.reviewRequired);
    }
    try {
      final parsed = await StudentExcelService.parseExcelFile(
        excelPath, expectedSubject: sheetName,
        targetGrade: exam.header.grade, examTitle: exam.header.examTitle,
      );
      final matches = parsed.students.where((s) => s.secretCode.trim() == qrSecretCode.trim()).toList();
      if (matches.isEmpty) return const OmrCommitResult(OmrCommitStatus.studentNotFound);
      if (matches.length != 1) return const OmrCommitResult(OmrCommitStatus.duplicateStudent);
      final student = matches.single;
      final column = await StudentExcelService.resolveTargetExamColumnIndexForSheet(
        filePath: excelPath, sheetName: sheetName, selectedPeriod: selectedPeriod,
      );
      final saved = await StudentExcelService.saveOmrMarkToExcel(
        filePath: excelPath, secretCode: qrSecretCode, sheetName: sheetName,
        mark: scoring.earnedMark, targetColumnIndex: column, allowOverwrite: allowOverwrite,
      );
      final status = switch (saved) {
        'saved' => OmrCommitStatus.saved,
        'alreadyExists' => OmrCommitStatus.existingMark,
        'studentNotFound' => OmrCommitStatus.studentNotFound,
        'duplicateStudent' => OmrCommitStatus.duplicateStudent,
        _ => OmrCommitStatus.saveFailed,
      };
      return OmrCommitResult(status, studentName: student.name, seatNumber: student.seatNo, targetColumn: column);
    } catch (_) {
      return const OmrCommitResult(OmrCommitStatus.invalidPeriod);
    }
  }
}

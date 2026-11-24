import 'package:flutter_test/flutter_test.dart';
import 'package:exam_maker_app/models/exam_models.dart';
import 'package:exam_maker_app/services/omr_scoring_service.dart';

ExamModel sampleExam() => ExamModel(
  id: 'omr-test', fileName: 'sample.exam', examType: ExamType.automated,
  createdAt: DateTime(2026), updatedAt: DateTime(2026),
  header: HeaderModel(),
  automatedConfig: AutomatedExamConfig(trueFalseCount: 2, mcqCount: 2, choiceSymbolType: ChoiceSymbolType.arabicLetters),
  questions: [
    QuestionModel(id: '1', title: 'TF1', mark: 1, answerKey: 'ص', spans: []),
    QuestionModel(id: '2', title: 'TF2', mark: 2, answerKey: 'خ', spans: []),
    QuestionModel(id: '3', title: 'MCQ1', mark: 3, answerKey: 'أ', spans: []),
    QuestionModel(id: '4', title: 'MCQ2', mark: 4, answerKey: 'د', spans: []),
  ],
);

void main() {
  test('scores correct and incorrect answers using individual item marks', () {
    final result = OmrScoringService.score(exam: sampleExam(), detectedSelections: [['ص'], ['ص'], ['أ'], ['ب']]);
    expect(result.earnedMark, 4);
    expect(result.maximumMark, 10);
    expect(result.correctCount, 2);
    expect(result.incorrectCount, 2);
    expect(result.reviewCount, 0);
  });
  test('does not guess blank or multiple marks and flags multiple marks for review', () {
    final result = OmrScoringService.score(exam: sampleExam(), detectedSelections: [[], ['ص', 'خ'], ['أ'], ['د']]);
    expect(result.blankCount, 1);
    expect(result.reviewCount, 1);
    expect(result.items[1].status, OmrAnswerStatus.multiple);
    expect(result.canBeAutomaticallyFinalized, isFalse);
  });
  test('normalizes Arabic option glyphs consistently', () {
    final exam = sampleExam();
    exam.questions[2].answerKey = 'جـ';
    final result = OmrScoringService.score(
      exam: exam,
      detectedSelections: [['ص'], ['خ'], ['ج'], ['د']],
    );
    expect(result.items[2].status, OmrAnswerStatus.correct);
    expect(result.earnedMark, 10);
  });
  test('rejects a detected question count that differs from the dynamic sheet configuration', () {
    expect(() => OmrScoringService.score(exam: sampleExam(), detectedSelections: [['ص']]), throwsArgumentError);
  });
}

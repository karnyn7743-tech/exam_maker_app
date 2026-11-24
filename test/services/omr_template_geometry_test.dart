import 'package:flutter_test/flutter_test.dart';
import 'package:exam_maker_app/models/exam_models.dart';
import 'package:exam_maker_app/services/omr_template_geometry.dart';

ExamModel buildExam({required int tf, required int mcq}) {
  final count = tf + mcq;
  return ExamModel(
    id: 'geometry-test',
    fileName: 'geometry-test.exam',
    examType: ExamType.automated,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    header: HeaderModel(),
    automatedConfig: AutomatedExamConfig(
      trueFalseCount: tf,
      mcqCount: mcq,
      choiceSymbolType: ChoiceSymbolType.arabicLetters,
    ),
    questions: List.generate(
      count,
      (i) => QuestionModel(
        id: 'q${i + 1}',
        title: 'Question ${i + 1}',
        spans: [],
        answerKey: i < tf ? 'ص' : 'أ',
        mark: 1,
      ),
    ),
  );
}

void main() {
  test('uses one column for ten items and two columns after ten', () {
    final ten = OmrTemplateGeometry.buildQuestionGroups(
      buildExam(tf: 10, mcq: 0),
    );
    final eleven = OmrTemplateGeometry.buildQuestionGroups(
      buildExam(tf: 11, mcq: 0),
    );
    expect(ten, hasLength(10));
    expect(ten[0][0].x, closeTo(ten[9][0].x, 0.000001));
    expect(eleven, hasLength(11));
    expect(eleven[0][0].x, isNot(equals(eleven[6][0].x)));
  });

  test('supports dynamic MCQ option symbols and two-column split', () {
    final exam = buildExam(tf: 0, mcq: 21);
    exam.automatedConfig.choiceSymbolType = ChoiceSymbolType.numbers;
    final groups = OmrTemplateGeometry.buildQuestionGroups(exam);
    expect(groups, hasLength(21));
    expect(groups.first, hasLength(4));
    expect(groups.first.map((b) => b.option).toList(), ['١', '٢', '٣', '٤']);
    expect(groups[0][0].x, isNot(equals(groups[11][0].x)));
  });
}

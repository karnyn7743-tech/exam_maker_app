import '../models/exam_models.dart';

enum OmrAnswerStatus { correct, incorrect, blank, multiple, invalidKey, invalidSelection }

class OmrItemResult {
  final int questionNumber;
  final String expected;
  final List<String> selected;
  final double mark;
  final double earnedMark;
  final OmrAnswerStatus status;
  const OmrItemResult({required this.questionNumber, required this.expected, required this.selected, required this.mark, required this.earnedMark, required this.status});
  bool get requiresReview => status == OmrAnswerStatus.multiple || status == OmrAnswerStatus.invalidKey || status == OmrAnswerStatus.invalidSelection;
}

class OmrScoringResult {
  final List<OmrItemResult> items;
  final double earnedMark, maximumMark;
  final int correctCount, incorrectCount, blankCount, reviewCount;
  const OmrScoringResult({required this.items, required this.earnedMark, required this.maximumMark, required this.correctCount, required this.incorrectCount, required this.blankCount, required this.reviewCount});
  bool get canBeAutomaticallyFinalized => reviewCount == 0;
}

/// تصحيح حتمي منفصل عن قراءة الصورة: الصح والخطأ أولاً ثم الاختيار من متعدد.
class OmrScoringService {
  static OmrScoringResult score({required ExamModel exam, required List<List<String>> detectedSelections}) {
    final config = exam.automatedConfig;
    final expectedCount = config.trueFalseCount + config.mcqCount;
    if (exam.examType != ExamType.automated) throw ArgumentError('لا يمكن استخدام محرك OMR مع اختبار غير مؤتمت.');
    if (exam.questions.length < expectedCount) throw StateError('عدد فقرات مفتاح الإجابة أقل من العدد المحدد في إعدادات ورقة التظليل.');
    if (detectedSelections.length != expectedCount) throw ArgumentError('عدد نتائج قراءة الدوائر لا يطابق عدد فقرات ورقة التظليل.');
    final tfOptions = exam.isArabic ? const ['ص', 'خ'] : const ['T', 'F'];
    final mcqOptions = _mcqOptions(exam);
    final items = <OmrItemResult>[];
    var earned = 0.0, correct = 0, incorrect = 0, blank = 0, review = 0;
    for (var i = 0; i < expectedCount; i++) {
      final allowed = i < config.trueFalseCount ? tfOptions : mcqOptions;
      final question = exam.questions[i];
      final expected = _normalize(question.answerKey);
      final selected = detectedSelections[i].map(_normalize).where((v) => v.isNotEmpty).toList(growable: false);
      late OmrAnswerStatus status;
      var itemEarned = 0.0;
      if (!allowed.contains(expected)) { status = OmrAnswerStatus.invalidKey; review++; }
      else if (selected.isEmpty) { status = OmrAnswerStatus.blank; blank++; }
      else if (selected.length > 1) { status = OmrAnswerStatus.multiple; review++; }
      else if (!allowed.contains(selected.single)) { status = OmrAnswerStatus.invalidSelection; review++; }
      else if (selected.single == expected) { status = OmrAnswerStatus.correct; itemEarned = question.mark; earned += itemEarned; correct++; }
      else { status = OmrAnswerStatus.incorrect; incorrect++; }
      items.add(OmrItemResult(questionNumber: i + 1, expected: expected, selected: selected, mark: question.mark, earnedMark: itemEarned, status: status));
    }
    return OmrScoringResult(items: List.unmodifiable(items), earnedMark: earned, maximumMark: items.fold<double>(0, (sum, item) => sum + item.mark), correctCount: correct, incorrectCount: incorrect, blankCount: blank, reviewCount: review);
  }

  static List<String> _mcqOptions(ExamModel exam) {
    if (exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.numbers) return exam.isArabic ? const ['١', '٢', '٣', '٤'] : const ['1', '2', '3', '4'];
    if (exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.englishLetters) return const ['A', 'B', 'C', 'D'];
    return exam.isArabic ? const ['أ', 'ب', 'جـ', 'د'] : const ['A', 'B', 'C', 'D'];
  }
  static String _normalize(String value) => value.trim().replaceAll('ـ', '').replaceAll(RegExp(r'[\u200B-\u200F\uFEFF]'), '');
}

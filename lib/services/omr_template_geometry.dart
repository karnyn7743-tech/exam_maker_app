import '../models/exam_models.dart';
import 'omr_bubble_detector.dart';
import 'omr_perspective_rectifier.dart';

/// هندسة شبكة الورقة A4 وفق أبعاد ومكونات OmrSheetService.
/// تعتمد نفس قاعدة التوزيع: عمود واحد حتى 10، ثم عمودان متساويان تقريباً.
class OmrTemplateGeometry {
  static const double _pageWidth = OmrPerspectiveRectifier.pageWidthPt;
  static const double _pageHeight = OmrPerspectiveRectifier.pageHeightPt;
  static const double _contentLeft = 1.2 * 28.3465;
  static const double _contentRight = _pageWidth - _contentLeft;
  static const double _contentWidth = _contentRight - _contentLeft;
  static const double _sectionGap = 10;
  static const double _tfWidth = (_contentWidth - _sectionGap) * 0.4;
  static const double _mcqWidth = (_contentWidth - _sectionGap) * 0.6;
  static const double _tfCenterX = _contentRight - _tfWidth / 2;
  static const double _mcqCenterX = _contentLeft + _mcqWidth / 2;

  // ارتفاعات عناصر الترويسة والتعليمات وعنوان القسم كما يرسمها مولّد PDF.
  // هذه القيم لا تُستخدم كبديل عن علامات التسجيل؛ الورقة تُصحح منظورياً أولاً.
  static const double _firstBubbleCenterY = 115.5;
  static const double _rowPitch = 17.1;
  static const double _bubbleRadius = 6.75;

  static List<List<OmrBubbleSpec>> buildQuestionGroups(ExamModel exam) {
    if (exam.examType != ExamType.automated) {
      throw ArgumentError('هندسة OMR متاحة للاختبارات المؤتمتة فقط.');
    }
    final config = exam.automatedConfig;
    final tfSymbols = exam.isArabic ? const ['ص', 'خ'] : const ['T', 'F'];
    final mcqSymbols = _mcqSymbols(exam);
    final groups = <List<OmrBubbleSpec>>[];

    for (var i = 0; i < config.trueFalseCount; i++) {
      final localRow = config.trueFalseCount > 10
          ? (i < (config.trueFalseCount / 2).ceil()
              ? i
              : i - (config.trueFalseCount / 2).ceil())
          : i;
      final isSecondColumn = config.trueFalseCount > 10 &&
          i >= (config.trueFalseCount / 2).ceil();
      final columnOffset = config.trueFalseCount > 10 ? _tfWidth / 4 : 0.0;
      final firstSide = exam.isArabic ? 1.0 : -1.0;
      final centerX = _tfCenterX +
          (config.trueFalseCount > 10
              ? (isSecondColumn ? -firstSide : firstSide) * columnOffset
              : 0.0);
      final centerY = _firstBubbleCenterY + localRow * _rowPitch;
      final offsets = exam.isArabic ? const [0.75, -16.75] : const [3.25, 20.75];
      groups.add(List.generate(2, (optionIndex) => OmrBubbleSpec(
        option: tfSymbols[optionIndex],
        x: (centerX + offsets[optionIndex]) / _pageWidth,
        y: centerY / _pageHeight,
        radius: _bubbleRadius / _pageWidth,
      )));
    }

    for (var i = 0; i < config.mcqCount; i++) {
      final half = (config.mcqCount / 2).ceil();
      final localRow = config.mcqCount > 10
          ? (i < half ? i : i - half)
          : i;
      final isSecondColumn = config.mcqCount > 10 && i >= half;
      final columnOffset = config.mcqCount > 10 ? _mcqWidth / 4 : 0.0;
      final firstSide = exam.isArabic ? 1.0 : -1.0;
      final centerX = _mcqCenterX +
          (config.mcqCount > 10
              ? (isSecondColumn ? -firstSide : firstSide) * columnOffset
              : 0.0);
      final centerY = _firstBubbleCenterY + localRow * _rowPitch;
      final offsets = exam.isArabic
          ? const [14.85, -3.05, -20.95, -38.85]
          : const [-14.85, 3.05, 20.95, 38.85];
      groups.add(List.generate(4, (optionIndex) => OmrBubbleSpec(
        option: mcqSymbols[optionIndex],
        x: (centerX + offsets[optionIndex]) / _pageWidth,
        y: centerY / _pageHeight,
        radius: _bubbleRadius / _pageWidth,
      )));
    }
    return List.unmodifiable(groups);
  }

  static List<String> _mcqSymbols(ExamModel exam) {
    switch (exam.automatedConfig.choiceSymbolType) {
      case ChoiceSymbolType.numbers:
        return exam.isArabic
            ? const ['١', '٢', '٣', '٤']
            : const ['1', '2', '3', '4'];
      case ChoiceSymbolType.englishLetters:
        return const ['A', 'B', 'C', 'D'];
      case ChoiceSymbolType.arabicLetters:
        return exam.isArabic
            ? const ['أ', 'ب', 'جـ', 'د']
            : const ['A', 'B', 'C', 'D'];
    }
  }
}

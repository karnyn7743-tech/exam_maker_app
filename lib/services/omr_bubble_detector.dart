import 'package:image/image.dart' as img;

/// موضع دائرة واحدة بعد معايرة هندسة الورقة.
/// الإحداثيات ونصف القطر نسبية إلى أبعاد الصورة (من 0 إلى 1).
class OmrBubbleSpec {
  final String option;
  final double x;
  final double y;
  final double radius;

  const OmrBubbleSpec({
    required this.option,
    required this.x,
    required this.y,
    required this.radius,
  });
}

enum OmrBubbleGroupStatus { selected, blank, multiple, ambiguous, invalid }

class OmrBubbleSample {
  final String option;
  final double inkRatio;
  final bool selected;
  final bool ambiguous;

  const OmrBubbleSample({
    required this.option,
    required this.inkRatio,
    required this.selected,
    required this.ambiguous,
  });
}

class OmrBubbleGroupResult {
  final OmrBubbleGroupStatus status;
  final List<String> selectedOptions;
  final List<OmrBubbleSample> samples;

  const OmrBubbleGroupResult({
    required this.status,
    required this.selectedOptions,
    required this.samples,
  });
}

/// يقرأ امتلاء مركز الدائرة فقط، بعيداً عن حدها الخارجي ورمز الخيار المطبوع.
/// لا يحوّل الحالة الملتبسة إلى إجابة؛ بل يعيدها للمراجعة.
class OmrBubbleDetector {
  static const double _selectedThreshold = 0.30;
  static const double _ambiguousThreshold = 0.12;
  static const int _darkPixelThreshold = 145;
  static const double _innerRadiusRatio = 0.43;

  static OmrBubbleGroupResult readGroup(
    img.Image image,
    List<OmrBubbleSpec> bubbles,
  ) {
    if (bubbles.isEmpty) {
      return const OmrBubbleGroupResult(
        status: OmrBubbleGroupStatus.invalid,
        selectedOptions: [],
        samples: [],
      );
    }

    final samples = <OmrBubbleSample>[];
    for (final bubble in bubbles) {
      if (bubble.x < 0 || bubble.x > 1 ||
          bubble.y < 0 || bubble.y > 1 ||
          bubble.radius <= 0 || bubble.radius > 0.1) {
        return const OmrBubbleGroupResult(
          status: OmrBubbleGroupStatus.invalid,
          selectedOptions: [],
          samples: [],
        );
      }

      final centerX = (bubble.x * (image.width - 1)).round();
      final centerY = (bubble.y * (image.height - 1)).round();
      final radius = (bubble.radius * image.width).round();
      final innerRadius = (radius * _innerRadiusRatio).round();
      if (radius < 3 || innerRadius < 1 ||
          centerX - innerRadius < 0 || centerY - innerRadius < 0 ||
          centerX + innerRadius >= image.width ||
          centerY + innerRadius >= image.height) {
        return const OmrBubbleGroupResult(
          status: OmrBubbleGroupStatus.invalid,
          selectedOptions: [],
          samples: [],
        );
      }

      var dark = 0;
      var total = 0;
      final radiusSquared = innerRadius * innerRadius;
      for (var dy = -innerRadius; dy <= innerRadius; dy++) {
        for (var dx = -innerRadius; dx <= innerRadius; dx++) {
          if (dx * dx + dy * dy > radiusSquared) continue;
          final pixel = image.getPixel(centerX + dx, centerY + dy);
          final luminance =
              (pixel.r * 299 + pixel.g * 587 + pixel.b * 114) / 1000;
          if (luminance < _darkPixelThreshold) dark++;
          total++;
        }
      }

      if (total == 0) {
        return const OmrBubbleGroupResult(
          status: OmrBubbleGroupStatus.invalid,
          selectedOptions: [],
          samples: [],
        );
      }

      final ratio = dark / total;
      final selected = ratio >= _selectedThreshold;
      final ambiguous =
          ratio >= _ambiguousThreshold && ratio < _selectedThreshold;
      samples.add(OmrBubbleSample(
        option: bubble.option,
        inkRatio: ratio,
        selected: selected,
        ambiguous: ambiguous,
      ));
    }

    final selectedOptions = samples
        .where((sample) => sample.selected)
        .map((sample) => sample.option)
        .toList(growable: false);
    final hasAmbiguous = samples.any((sample) => sample.ambiguous);

    final OmrBubbleGroupStatus status;
    if (hasAmbiguous) {
      status = OmrBubbleGroupStatus.ambiguous;
    } else if (selectedOptions.length > 1) {
      status = OmrBubbleGroupStatus.multiple;
    } else if (selectedOptions.length == 1) {
      status = OmrBubbleGroupStatus.selected;
    } else {
      status = OmrBubbleGroupStatus.blank;
    }

    return OmrBubbleGroupResult(
      status: status,
      selectedOptions: selectedOptions,
      samples: List.unmodifiable(samples),
    );
  }

  static List<OmrBubbleGroupResult> readAll(
    img.Image image,
    List<List<OmrBubbleSpec>> questionGroups,
  ) =>
      List.unmodifiable(
        questionGroups.map((group) => readGroup(image, group)),
      );
}

import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// يكتشف مربعات التسجيل السوداء المطبوعة في زوايا ورقة OMR.
/// لا يعتمد على مواضع ثابتة؛ يعمل على مكونات الصورة المتصلة.
class OmrRegistrationDetector {
  static const int _darkThreshold = 85;

  static Future<OmrRegistrationResult> detectFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      return OmrRegistrationResult.failure('تعذر فك ترميز صورة الورقة.');
    }
    return detect(image);
  }

  static OmrRegistrationResult detect(img.Image sourceImage) {
    // تصغير الصور عالية الدقة قبل تحليل المكونات لتقليل استهلاك الذاكرة
    // وزمن المعالجة على الهواتف، مع الاحتفاظ بالإحداثيات النسبية.
    const maxDimension = 1200;
    final largest = sourceImage.width > sourceImage.height
        ? sourceImage.width
        : sourceImage.height;
    final img.Image image = largest > maxDimension
        ? img.copyResize(
            sourceImage,
            width: (sourceImage.width * maxDimension / largest).round(),
            height: (sourceImage.height * maxDimension / largest).round(),
            interpolation: img.Interpolation.average,
          )
        : sourceImage;

    final width = image.width;
    final height = image.height;
    if (width < 100 || height < 100) {
      return OmrRegistrationResult.failure('دقة الصورة منخفضة جدًا لاكتشاف علامات الورقة.');
    }

    final total = width * height;
    final visited = Uint8List(total);
    final queue = Queue<int>();
    final candidates = <_Component>[];

    bool isDark(int x, int y) {
      final p = image.getPixel(x, y);
      final luminance = (p.r * 299 + p.g * 587 + p.b * 114) / 1000;
      return luminance < _darkThreshold;
    }

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final start = y * width + x;
        if (visited[start] == 1 || !isDark(x, y)) continue;

        var minX = x, maxX = x, minY = y, maxY = y;
        var area = 0;
        queue.add(start);
        visited[start] = 1;

        while (queue.isNotEmpty) {
          final index = queue.removeFirst();
          final px = index % width;
          final py = index ~/ width;
          area++;
          if (px < minX) minX = px;
          if (px > maxX) maxX = px;
          if (py < minY) minY = py;
          if (py > maxY) maxY = py;

          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = px + dx, ny = py + dy;
              if (nx < 0 || ny < 0 || nx >= width || ny >= height) continue;
              final ni = ny * width + nx;
              if (visited[ni] == 0 && isDark(nx, ny)) {
                visited[ni] = 1;
                queue.add(ni);
              }
            }
          }
        }

        final boxWidth = maxX - minX + 1;
        final boxHeight = maxY - minY + 1;
        final boxArea = boxWidth * boxHeight;
        final aspect = boxWidth / boxHeight;
        final fillRatio = area / boxArea;
        final relativeWidth = boxWidth / width;
        final relativeHeight = boxHeight / height;

        if (aspect >= 0.72 &&
            aspect <= 1.38 &&
            fillRatio >= 0.55 &&
            relativeWidth >= 0.006 &&
            relativeWidth <= 0.08 &&
            relativeHeight >= 0.006 &&
            relativeHeight <= 0.08 &&
            boxArea >= 16) {
          candidates.add(_Component(
            (minX + maxX) / 2,
            (minY + maxY) / 2,
            boxArea,
          ));
        }
      }
    }

    if (candidates.length < 4) {
      return OmrRegistrationResult.failure(
        'لم يتم العثور على علامات التسجيل الأربع بوضوح (المكتشف: ${candidates.length}).',
        detectedCount: candidates.length,
      );
    }

    // نختار علامة مستقلة في كل ربع من الصورة، لا مجرد أقرب أربع علامات
    // إلى الحواف؛ فهذا يمنع اختيار علامتين من الركن نفسه.
    _Component? nearest(bool left, bool top) {
      final quadrant = candidates.where((c) {
        final nx = c.x / width;
        final ny = c.y / height;
        return (left ? nx < 0.5 : nx >= 0.5) &&
            (top ? ny < 0.5 : ny >= 0.5);
      }).toList();
      if (quadrant.isEmpty) return null;
      quadrant.sort((a, b) => _cornerDistance(a, width, height, left, top)
          .compareTo(_cornerDistance(b, width, height, left, top)));
      return quadrant.first;
    }

    final topLeft = nearest(true, true);
    final topRight = nearest(false, true);
    final bottomLeft = nearest(true, false);
    final bottomRight = nearest(false, false);

    if (topLeft == null || topRight == null ||
        bottomLeft == null || bottomRight == null) {
      return OmrRegistrationResult.failure(
        'لم تُكتشف علامة تسجيل منفصلة في كل ركن من أركان الورقة.',
        detectedCount: candidates.length,
      );
    }

    final horizontalTop = (topRight.x - topLeft.x) / width;
    final horizontalBottom = (bottomRight.x - bottomLeft.x) / width;
    final verticalLeft = (bottomLeft.y - topLeft.y) / height;
    final verticalRight = (bottomRight.y - topRight.y) / height;
    if (horizontalTop < 0.35 || horizontalBottom < 0.35 ||
        verticalLeft < 0.35 || verticalRight < 0.35) {
      return OmrRegistrationResult.failure(
        'علامات التسجيل متقاربة أو لا تحيط بمنطقة الإجابة؛ يرجى تصوير الورقة كاملة.',
        detectedCount: 4,
      );
    }

    return OmrRegistrationResult.success({
      'topLeft': OmrPoint(topLeft.x / width, topLeft.y / height),
      'topRight': OmrPoint(topRight.x / width, topRight.y / height),
      'bottomLeft': OmrPoint(bottomLeft.x / width, bottomLeft.y / height),
      'bottomRight': OmrPoint(bottomRight.x / width, bottomRight.y / height),
    });
  }

  static double _cornerDistance(
    _Component c,
    int width,
    int height,
    bool left,
    bool top,
  ) {
    final dx = c.x / width - (left ? 0.0 : 1.0);
    final dy = c.y / height - (top ? 0.0 : 1.0);
    return dx * dx + dy * dy;
  }

  static double _cornerScore(_Component c, int width, int height) {
    final nx = c.x / width;
    final ny = c.y / height;
    final horizontalEdge = (nx - 0.5).abs() * 2;
    final verticalEdge = (ny - 0.5).abs() * 2;
    return horizontalEdge + verticalEdge;
  }
}

class _Component {
  final double x;
  final double y;
  final int area;
  const _Component(this.x, this.y, this.area);
}

class OmrPoint {
  final double x;
  final double y;
  const OmrPoint(this.x, this.y);
}

class OmrRegistrationResult {
  final bool success;
  final Map<String, OmrPoint> corners;
  final String message;
  final int detectedCount;

  const OmrRegistrationResult._({
    required this.success,
    required this.corners,
    required this.message,
    required this.detectedCount,
  });

  factory OmrRegistrationResult.success(Map<String, OmrPoint> corners) =>
      OmrRegistrationResult._(
        success: true,
        corners: corners,
        message: 'تم اكتشاف علامات التسجيل الأربع.',
        detectedCount: 4,
      );

  factory OmrRegistrationResult.failure(
    String message, {
    int detectedCount = 0,
  }) =>
      OmrRegistrationResult._(
        success: false,
        corners: const {},
        message: message,
        detectedCount: detectedCount,
      );
}

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

  static OmrRegistrationResult detect(img.Image image) {
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

        // المربعات المطبوعة صغيرة نسبيًا، شبه مربعة وممتلئة.
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

    // نختار الأربع الأكثر قربًا من زوايا الصورة، ثم نرتبها هندسيًا.
    final sortedByCornerScore = List<_Component>.from(candidates)
      ..sort((a, b) => _cornerScore(b, width, height)
          .compareTo(_cornerScore(a, width, height)));
    final selected = sortedByCornerScore.take(4).toList();

    final left = selected.reduce((a, b) => a.x < b.x ? a : b);
    final right = selected.reduce((a, b) => a.x > b.x ? a : b);
    final top = selected.reduce((a, b) => a.y < b.y ? a : b);
    final bottom = selected.reduce((a, b) => a.y > b.y ? a : b);

    final corners = <String, OmrPoint>{
      'topLeft': OmrPoint(left.x / width, top.y / height),
      'topRight': OmrPoint(right.x / width, top.y / height),
      'bottomLeft': OmrPoint(left.x / width, bottom.y / height),
      'bottomRight': OmrPoint(right.x / width, bottom.y / height),
    };

    final horizontalSpan = (right.x - left.x) / width;
    final verticalSpan = (bottom.y - top.y) / height;
    if (horizontalSpan < 0.35 || verticalSpan < 0.35) {
      return OmrRegistrationResult.failure(
        'علامات التسجيل المكتشفة متقاربة؛ يرجى تصوير الورقة كاملة.',
        detectedCount: 4,
      );
    }

    return OmrRegistrationResult.success(corners);
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

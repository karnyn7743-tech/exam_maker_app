import 'package:image/image.dart' as img;
import 'omr_registration_detector.dart';

/// تصحيح المنظور إلى مقاس A4 اعتماداً على مراكز علامات التسجيل المطبوعة.
class OmrPerspectiveRectifier {
  static const double pageWidthPt = 595.276;
  static const double pageHeightPt = 841.89;

  static img.Image rectify(
    img.Image source,
    OmrRegistrationResult registration, {
    int outputWidth = 1190,
    int outputHeight = 1684,
  }) {
    if (!registration.success) {
      throw ArgumentError('لا يمكن تصحيح المنظور دون علامات تسجيل مكتملة.');
    }
    final c = registration.corners;
    final sourcePoints = [
      c['topLeft']!, c['topRight']!,
      c['bottomRight']!, c['bottomLeft']!,
    ].map((p) => <double>[p.x * (source.width - 1), p.y * (source.height - 1)]).toList();

    // مراكز مربعات التسجيل في ملف PDF: هامش 12mm + نصف مربع 8pt.
    const left = (12 * 2.83465 + 4) / pageWidthPt;
    const right = 1 - left;
    const top = (3 * 2.83465 + 4) / pageHeightPt;
    const bottom = 1 - (4 * 2.83465 + 4) / pageHeightPt;
    final destinationPoints = [
      [left * (outputWidth - 1), top * (outputHeight - 1)],
      [right * (outputWidth - 1), top * (outputHeight - 1)],
      [right * (outputWidth - 1), bottom * (outputHeight - 1)],
      [left * (outputWidth - 1), bottom * (outputHeight - 1)],
    ];

    final h = _solveHomography(destinationPoints, sourcePoints);
    final output = img.Image(width: outputWidth, height: outputHeight);
    img.fill(output, color: img.ColorRgb8(255, 255, 255));

    for (var y = 0; y < outputHeight; y++) {
      for (var x = 0; x < outputWidth; x++) {
        final denominator = h[6] * x + h[7] * y + 1;
        if (denominator.abs() < 1e-9) continue;
        final sx = (h[0] * x + h[1] * y + h[2]) / denominator;
        final sy = (h[3] * x + h[4] * y + h[5]) / denominator;
        if (sx < 0 || sy < 0 || sx >= source.width - 1 || sy >= source.height - 1) continue;
        final x0 = sx.floor(), y0 = sy.floor();
        final dx = sx - x0, dy = sy - y0;
        final p00 = source.getPixel(x0, y0);
        final p10 = source.getPixel(x0 + 1, y0);
        final p01 = source.getPixel(x0, y0 + 1);
        final p11 = source.getPixel(x0 + 1, y0 + 1);
        int blend(num a, num b, num c, num d) =>
            (a * (1 - dx) * (1 - dy) + b * dx * (1 - dy) +
             c * (1 - dx) * dy + d * dx * dy).round().clamp(0, 255).toInt();
        output.setPixel(
          x, y,
          img.ColorRgb8(
            blend(p00.r, p10.r, p01.r, p11.r),
            blend(p00.g, p10.g, p01.g, p11.g),
            blend(p00.b, p10.b, p01.b, p11.b),
          ),
        );
      }
    }
    return output;
  }

  static List<double> _solveHomography(
    List<List<double>> from,
    List<List<double>> to,
  ) {
    final matrix = List.generate(8, (_) => List<double>.filled(9, 0));
    for (var i = 0; i < 4; i++) {
      final x = from[i][0], y = from[i][1];
      final u = to[i][0], v = to[i][1];
      matrix[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
      matrix[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v];
    }
    for (var col = 0; col < 8; col++) {
      var pivot = col;
      for (var row = col + 1; row < 8; row++) {
        if (matrix[row][col].abs() > matrix[pivot][col].abs()) pivot = row;
      }
      if (matrix[pivot][col].abs() < 1e-10) {
        throw StateError('علامات التسجيل لا تسمح بحساب منظور موثوق.');
      }
      final temp = matrix[col];
      matrix[col] = matrix[pivot];
      matrix[pivot] = temp;
      final divisor = matrix[col][col];
      for (var j = col; j < 9; j++) matrix[col][j] /= divisor;
      for (var row = 0; row < 8; row++) {
        if (row == col) continue;
        final factor = matrix[row][col];
        for (var j = col; j < 9; j++) {
          matrix[row][j] -= factor * matrix[col][j];
        }
      }
    }
    return List.generate(8, (i) => matrix[i][8]);
  }
}

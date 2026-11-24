import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:exam_maker_app/services/omr_bubble_detector.dart';

img.Image blankSheet() {
  final image = img.Image(width: 200, height: 200);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  return image;
}

void main() {
  test('reads a fully filled bubble as selected', () {
    final image = blankSheet();
    img.fillCircle(
      image,
      x: 100,
      y: 100,
      radius: 5,
      color: img.ColorRgb8(10, 10, 10),
    );
    final result = OmrBubbleDetector.readGroup(image, const [
      OmrBubbleSpec(option: 'أ', x: 0.5, y: 0.5, radius: 0.05),
      OmrBubbleSpec(option: 'ب', x: 0.7, y: 0.5, radius: 0.05),
    ]);
    expect(result.status, OmrBubbleGroupStatus.selected);
    expect(result.selectedOptions, ['أ']);
  });

  test('does not invent an answer for an empty group', () {
    final result = OmrBubbleDetector.readGroup(blankSheet(), const [
      OmrBubbleSpec(option: 'أ', x: 0.5, y: 0.5, radius: 0.05),
      OmrBubbleSpec(option: 'ب', x: 0.7, y: 0.5, radius: 0.05),
    ]);
    expect(result.status, OmrBubbleGroupStatus.blank);
    expect(result.selectedOptions, isEmpty);
  });

  test('flags two filled bubbles instead of choosing one', () {
    final image = blankSheet();
    img.fillCircle(image, x: 80, y: 100, radius: 5, color: img.ColorRgb8(0, 0, 0));
    img.fillCircle(image, x: 120, y: 100, radius: 5, color: img.ColorRgb8(0, 0, 0));
    final result = OmrBubbleDetector.readGroup(image, const [
      OmrBubbleSpec(option: 'أ', x: 0.4, y: 0.5, radius: 0.05),
      OmrBubbleSpec(option: 'ب', x: 0.6, y: 0.5, radius: 0.05),
    ]);
    expect(result.status, OmrBubbleGroupStatus.multiple);
    expect(result.selectedOptions, ['أ', 'ب']);
  });
}

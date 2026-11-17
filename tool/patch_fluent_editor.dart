import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final configFile = File('.dart_tool/package_config.json');
  if (!await configFile.exists()) {
    stderr.writeln('package_config.json was not found. Run flutter pub get first.');
    exitCode = 1;
    return;
  }

  final config = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final packages = config['packages'] as List<dynamic>;
  final package = packages.cast<Map<String, dynamic>>().firstWhere(
    (item) => item['name'] == 'fluent_editor',
    orElse: () => <String, dynamic>{},
  );
  if (package.isEmpty) {
    stderr.writeln('fluent_editor package was not found in package_config.json.');
    exitCode = 1;
    return;
  }

  final rootUri = Uri.parse(package['rootUri'] as String);
  final sourceUri = rootUri.resolve('lib/widgets/nodes/virtualized_selectable_area.dart');
  final sourceFile = File.fromUri(sourceUri);
  if (!await sourceFile.exists()) {
    stderr.writeln('Fluent Editor selectable area source was not found: $sourceUri');
    exitCode = 1;
    return;
  }

  var source = await sourceFile.readAsString();
  const original = '''      _longPressTimer = Timer(_kLongPressTimeout, () {
        if (!_isDragging && _pointerDownPosition != null) {
          _isScrolling = true;
          _dismissKeyboard();
        }
      });''';
  const patched = '''      _longPressTimer = Timer(_kLongPressTimeout, () {
        if (!_isDragging && !_isScrolling && _pointerDownPosition != null) {
          // On touch screens, a long press starts text selection instead of
          // switching to scroll mode. Vertical movement before the timeout
          // still follows the normal ListView scrolling path.
          _isDragging = true;
          _tapTimer?.cancel();
          setState(() {});
          _startSelectionAt(_pointerDownPosition!);
        }
      });''';

  if (source.contains(patched)) {
    stdout.writeln('Fluent Editor long-press selection patch is already applied.');
    return;
  }
  if (!source.contains(original)) {
    stderr.writeln('Expected Fluent Editor long-press block was not found; refusing an unsafe patch.');
    exitCode = 1;
    return;
  }

  source = source.replaceFirst(original, patched);
  await sourceFile.writeAsString(source);
  stdout.writeln('Applied Fluent Editor long-press text-selection patch.');
}

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
  } else {
    if (!source.contains(original)) {
      stderr.writeln('Expected Fluent Editor long-press block was not found; refusing an unsafe patch.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(original, patched);
    await sourceFile.writeAsString(source);
    stdout.writeln('Applied Fluent Editor long-press text-selection patch.');
  }

  await patchImageDragging(rootUri);
}

Future<void> patchImageDragging(Uri rootUri) async {
  final imageUri = rootUri.resolve('lib/widgets/nodes/fluent_image_widget.dart');
  final imageFile = File.fromUri(imageUri);
  if (!await imageFile.exists()) {
    stderr.writeln('Fluent Editor image widget source was not found: $imageUri');
    exitCode = 1;
    return;
  }

  var source = await imageFile.readAsString();
  const panAnchor = '''          onLongPressStart: (details) => _showContextMenu(details.globalPosition),
          child: LayoutBuilder(''';
  const panReplacement = '''          onLongPressStart: (details) => _showContextMenu(details.globalPosition),
          onPanStart: (_) {
            if (_isResizeMode || widget.document.isResizingImage) return;
            widget.document.saveState(description: 'Move image', forceNewAction: true);
            _isDragging = true;
          },
          onPanUpdate: (details) {
            if (!_isDragging || _isResizeMode || widget.document.isResizingImage) return;
            _moveBlockImageTo(details.globalPosition);
          },
          onPanEnd: (_) {
            if (!_isDragging) return;
            _isDragging = false;
            widget.document.updateContent();
          },
          child: LayoutBuilder(''';
  if (!source.contains(panReplacement)) {
    if (!source.contains(panAnchor)) {
      stderr.writeln('Expected image gesture insertion point was not found; refusing an unsafe image-drag patch.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(panAnchor, panReplacement);
  }

  const methodAnchor = '''  Widget _buildImage(String src) {''';
  const moveMethod = '''  /// Reorders this block image among the document's top-level blocks.
  /// The model order is serialized by FluentDocument, so the new position
  /// survives save/reopen and participates in undo/redo.
  void _moveBlockImageTo(Offset globalPosition) {
    final blocks = widget.document.content.nodes;
    final currentIndex = blocks.indexWhere((item) => item.id == widget.node.id);
    if (currentIndex < 0) return;

    final remaining = List<FNode>.from(blocks)..removeAt(currentIndex);
    var targetIndex = 0;
    for (final block in remaining) {
      final renderObject = widget.document
          .getKeyForNode(block.id)
          .currentContext
          ?.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final centerY = renderObject.localToGlobal(
          Offset(0, renderObject.size.height / 2),
        ).dy;
        if (globalPosition.dy < centerY) break;
      }
      targetIndex++;
    }

    if (targetIndex == currentIndex) return;
    blocks
      ..removeAt(currentIndex)
      ..insert(targetIndex, widget.node);
    widget.document.updateContent();
  }

  Widget _buildImage(String src) {''';
  if (!source.contains(moveMethod)) {
    if (!source.contains(methodAnchor)) {
      stderr.writeln('Expected image helper insertion point was not found; refusing an unsafe image-drag patch.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(methodAnchor, moveMethod);
  }

  await imageFile.writeAsString(source);
  stdout.writeln('Applied persistent top-level image drag/reorder patch.');
}

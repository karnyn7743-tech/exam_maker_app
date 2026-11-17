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
  await patchTouchSelection(rootUri);
  await patchImageDragging(rootUri);
}

Future<void> patchTouchSelection(Uri rootUri) async {
  final uri = rootUri.resolve('lib/widgets/nodes/virtualized_selectable_area.dart');
  final file = File.fromUri(uri);
  if (!await file.exists()) {
    stderr.writeln('Fluent Editor selectable area source was not found: $uri');
    exitCode = 1;
    return;
  }

  var source = await file.readAsString();

  // A raw pointer timer does not win Flutter's gesture arena against the
  // ListView. Use GestureDetector's long-press recognizer so a long press
  // claims the gesture and subsequent finger movement updates the selection.
  const oldTimer = '''      _longPressTimer = Timer(_kLongPressTimeout, () {
        if (!_isDragging && _pointerDownPosition != null) {
          _isScrolling = true;
          _dismissKeyboard();
        }
      });''';
  const oldPatchedTimer = '''      _longPressTimer = Timer(_kLongPressTimeout, () {
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
  const disabledTimer = '''      // Long-press selection is handled by the GestureDetector below.
      _longPressTimer?.cancel();''';

  if (source.contains(oldTimer)) {
    source = source.replaceFirst(oldTimer, disabledTimer);
  } else if (source.contains(oldPatchedTimer)) {
    source = source.replaceFirst(oldPatchedTimer, disabledTimer);
  } else if (!source.contains(disabledTimer)) {
    stderr.writeln('Expected mobile long-press timer was not found; refusing unsafe selection patch.');
    exitCode = 1;
    return;
  }

  const methodAnchor = '''  /// Dismisses the virtual keyboard on mobile platforms
  void _dismissKeyboard() {''';
  const methods = '''  void _handleLongPressSelectionStart(LongPressStartDetails details) {
    if (widget.document.isResizingImage || widget.document.isResizingTable) return;
    _pointerDownPosition = details.globalPosition;
    _pointerDownButtons = 1;
    _tapTimer?.cancel();
    _longPressTimer?.cancel();
    _isDragging = true;
    _isScrolling = false;
    _isSelecting = false;
    setState(() {});
    _startSelectionAt(details.globalPosition);
  }

  void _handleLongPressSelectionMove(LongPressMoveUpdateDetails details) {
    if (_isDragging && _isSelecting) {
      _scheduleSelectionUpdate(details.globalPosition);
    }
  }

  void _handleLongPressSelectionEnd(LongPressEndDetails details) {
    if (!_isDragging) return;
    _selectionUpdateTimer?.cancel();
    _isDragging = false;
    _isScrolling = false;
    _isSelecting = false;
    _pointerDownPosition = null;
    _pointerDownButtons = 0;
    _lastSelectionResult = null;
    _lastSelectionPosition = null;
    setState(() {});
    widget.document.cursorOnlyUpdate();
  }

  /// Dismisses the virtual keyboard on mobile platforms
  void _dismissKeyboard() {''';

  if (!source.contains(methods)) {
    if (!source.contains(methodAnchor)) {
      stderr.writeln('Expected selection helper insertion point was not found.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(methodAnchor, methods);
  }

  const buildAnchor = '''    return MouseRegion(
      cursor: isResizeActive ? SystemMouseCursors.basic : SystemMouseCursors.text,
      child: Listener(''';
  const buildReplacement = '''    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: _handleLongPressSelectionStart,
      onLongPressMoveUpdate: _handleLongPressSelectionMove,
      onLongPressEnd: _handleLongPressSelectionEnd,
      child: MouseRegion(
      cursor: isResizeActive ? SystemMouseCursors.basic : SystemMouseCursors.text,
      child: Listener(''';
  if (!source.contains(buildReplacement)) {
    if (!source.contains(buildAnchor)) {
      stderr.writeln('Expected selectable-area build anchor was not found.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(buildAnchor, buildReplacement);
    const closingAnchor = '''          },
        ),
      ),
    );
  }
}

/// Tracks whether a top-level''';
    const closingReplacement = '''          },
        ),
      ),
      ),
    );
  }
}

/// Tracks whether a top-level''';
    if (!source.contains(closingAnchor)) {
      stderr.writeln('Expected selectable-area closing structure was not found.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(closingAnchor, closingReplacement);
  }

  await file.writeAsString(source);
  stdout.writeln('Applied gesture-arena-aware long-press text selection patch.');
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
          // Dragging the image body moves it; the eight child resize handles
          // retain their own more-specific pan recognizers.
          onPanStart: (_) {
            if (widget.document.isResizingImage) return;
            widget.document.saveState(description: 'Move image', forceNewAction: true);
            _isDragging = true;
          },
          onPanUpdate: (details) {
            if (!_isDragging || widget.document.isResizingImage) return;
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
      stderr.writeln('Expected image gesture insertion point was not found; refusing unsafe image-drag patch.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(panAnchor, panReplacement);
  }

  const methodAnchor = '''  Widget _buildImage(String src) {''';
  const moveMethod = '''  /// Reorders a block image vertically among top-level document blocks.
  /// This intentionally does not pretend to provide arbitrary x/y positioning.
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
      stderr.writeln('Expected image helper insertion point was not found; refusing unsafe image-drag patch.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(methodAnchor, moveMethod);
  }

  await imageFile.writeAsString(source);
  stdout.writeln('Applied image-body drag/reorder patch; resize handles remain independent.');
}

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
  await patchImageFloating(rootUri);
  await patchCaretLineResolution(rootUri);
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

/// Tracks whether a virtualized''';
    const closingReplacement = '''          },
        ),
      ),
      ),
    );
  }
}

/// Tracks whether a virtualized''';
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

Future<void> patchImageFloating(Uri rootUri) async {
  final modelUri = rootUri.resolve('lib/factories.dart');
  final modelFile = File.fromUri(modelUri);
  if (!await modelFile.exists()) {
    stderr.writeln('Fluent Editor factories source was not found: $modelUri');
    exitCode = 1;
    return;
  }

  var model = await modelFile.readAsString();
  const modelAnchor = "  String textAlign = 'left';";
  const modelReplacement = """  String textAlign = 'left';

  /// When true, the image is painted over document text rather than occupying
  /// a normal block position. Offsets are persisted in document coordinates.
  bool isFloating = false;
  double offsetX = 0;
  double offsetY = 0;""";
  if (!model.contains(modelReplacement)) {
    if (!model.contains(modelAnchor)) {
      stderr.writeln('FluentImage model insertion point was not found.');
      exitCode = 1;
      return;
    }
    model = model.replaceFirst(modelAnchor, modelReplacement);
  }

  const fromJsonAnchor = "    img.textAlign = (json['textAlign'] as String?) ?? 'left';";
  const fromJsonReplacement = """    img.textAlign = (json['textAlign'] as String?) ?? 'left';
    img.isFloating = json['isFloating'] as bool? ?? false;
    img.offsetX = (json['offsetX'] as num?)?.toDouble() ?? 0;
    img.offsetY = (json['offsetY'] as num?)?.toDouble() ?? 0;""";
  if (!model.contains(fromJsonReplacement)) {
    if (!model.contains(fromJsonAnchor)) {
      stderr.writeln('FluentImage JSON decoder insertion point was not found.');
      exitCode = 1;
      return;
    }
    model = model.replaceFirst(fromJsonAnchor, fromJsonReplacement);
  }

  const toJsonAnchor = "    if (height != null) json['height'] = height;";
  const toJsonReplacement = """    if (height != null) json['height'] = height;
    if (isFloating) {
      json['isFloating'] = true;
      json['offsetX'] = offsetX;
      json['offsetY'] = offsetY;
    }""";
  if (!model.contains(toJsonReplacement)) {
    if (!model.contains(toJsonAnchor)) {
      stderr.writeln('FluentImage JSON encoder insertion point was not found.');
      exitCode = 1;
      return;
    }
    model = model.replaceFirst(toJsonAnchor, toJsonReplacement);
  }
  await modelFile.writeAsString(model);

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
          // Drag the image body freely in front of the text. Child resize
          // handles keep their own pan recognizers and remain independent.
          onPanStart: (_) {
            if (_isResizeMode || widget.document.isResizingImage) return;
            widget.document.saveState(description: 'Move floating image', forceNewAction: true);
            _isDragging = true;
            widget.node.isFloating = true;
          },
          onPanUpdate: (details) {
            if (!_isDragging || _isResizeMode || widget.document.isResizingImage) return;
            widget.node.offsetX += details.delta.dx;
            widget.node.offsetY += details.delta.dy;
            setState(() {});
          },
          onPanEnd: (_) {
            if (!_isDragging || _isResizeMode) return;
            _isDragging = false;
            widget.document.updateContent();
          },
          child: LayoutBuilder(''';
  if (!source.contains(panReplacement)) {
    if (!source.contains(panAnchor)) {
      stderr.writeln('Expected image gesture insertion point was not found.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(panAnchor, panReplacement);
  }

  const contextAnchor = '''      items: [
        FluentContextMenuItem(
          icon: Icons.image,''';
  const contextReplacement = '''      items: [
        FluentContextMenuItem(
          icon: Icons.layers,
          label: widget.node.isFloating ? 'إرجاع الصورة ضمن النص' : 'وضع أمام النص',
          onPressed: () {
            widget.document.saveState(description: 'Change image text wrapping', forceNewAction: true);
            widget.node.isFloating = !widget.node.isFloating;
            if (!widget.node.isFloating) {
              widget.node.offsetX = 0;
              widget.node.offsetY = 0;
            }
            widget.document.updateContent();
          },
        ),
        FluentContextMenuItem(
          icon: Icons.image,''';
  if (!source.contains(contextReplacement)) {
    if (!source.contains(contextAnchor)) {
      stderr.writeln('Image context-menu insertion point was not found.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(contextAnchor, contextReplacement);
  }

  const buildAnchor = '''    return Padding(
      padding: EdgeInsets.symmetric(''';
  const buildReplacement = '''    return Align(
      alignment: Alignment.topLeft,
      heightFactor: image.isFloating ? 1 : 1,
      child: Transform.translate(
        offset: image.isFloating ? Offset(image.offsetX, image.offsetY) : Offset.zero,
        child: Padding(
      padding: EdgeInsets.symmetric(''';
  if (!source.contains(buildReplacement)) {
    if (!source.contains(buildAnchor)) {
      stderr.writeln('Image widget build insertion point was not found.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(buildAnchor, buildReplacement);
    const closingAnchor = '''    ),
    );
  }

  Widget _buildImage(String src) {''';
    const closingReplacement = '''    ),
        ),
      ),
    );
  }

  Widget _buildImage(String src) {''';
    if (!source.contains(closingAnchor)) {
      stderr.writeln('Image widget closing structure was not found.');
      exitCode = 1;
      return;
    }
    source = source.replaceFirst(closingAnchor, closingReplacement);
  }

  await imageFile.writeAsString(source);
  stdout.writeln('Applied persisted free-drag image overlay patch (x/y) with independent resize handles.');
}


/// Uses TextPainter's canonical caret geometry for vertical navigation.
/// Character boxes can have different heights (Arabic marks, superscripts,
/// subscripts and mixed fonts); using their centers makes positions on the
/// same visual line appear to have different Y coordinates.
Future<void> patchCaretLineResolution(Uri rootUri) async {
  final uri = rootUri.resolve('lib/renderers/render_paragraph.dart');
  final file = File.fromUri(uri);
  if (!await file.exists()) {
    stderr.writeln('Fluent Editor paragraph renderer was not found: $uri');
    exitCode = 1;
    return;
  }

  var source = await file.readAsString();
  const oldMethod = '''  double? getCaretY(String fragmentId, int localOffset) {
    final globalOffset = _localToGlobal(fragmentId, localOffset);
    if (globalOffset == null) return null;

    TextBox? charBox;
    final textLength = _painter.text?.toPlainText().length ?? 0;
    if (globalOffset > 0 && globalOffset <= textLength) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: globalOffset - 1, extentOffset: globalOffset),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    } else if (globalOffset == 0 && textLength > 0) {
      final boxes = _painter.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: 1),
      );
      if (boxes.isNotEmpty) charBox = boxes.first;
    }

    if (charBox != null) {
      if (_lineMetricsDirty || _cachedLineMetrics == null) {
        _cachedLineMetrics = _painter.computeLineMetrics();
        _lineMetricsDirty = false;
      }
      final lineMetrics = _cachedLineMetrics!;
      for (final lm in lineMetrics) {
        if (lm.baseline >= charBox.top && lm.baseline <= charBox.bottom) {
          return localToGlobal(Offset(0, lm.baseline)).dy;
        }
      }
      return localToGlobal(Offset(0, (charBox.top + charBox.bottom) / 2)).dy;
    }

    final caretOffset = _painter.getOffsetForCaret(
      TextPosition(offset: globalOffset),
      Rect.zero,
    );
    return localToGlobal(caretOffset).dy;
  }''';

  const patchedMethod = '''  double? getCaretY(String fragmentId, int localOffset) {
    final globalOffset = _localToGlobal(fragmentId, localOffset);
    if (globalOffset == null) return null;

    // Always use the same TextPainter caret geometry for every character.
    // Character selection boxes are glyph-dependent: diacritics, tall Arabic
    // letters and superscript/subscript fragments have different bounds even
    // when they occupy one visual line. Their centers must not be interpreted
    // as separate lines by ArrowUp/ArrowDown navigation.
    final caretOffset = _painter.getOffsetForCaret(
      TextPosition(offset: globalOffset),
      Rect.zero,
    );
    return localToGlobal(Offset(0, caretOffset.dy)).dy;
  }''';

  if (source.contains(patchedMethod)) {
    stdout.writeln('Caret line-resolution patch already applied.');
    return;
  }
  if (!source.contains(oldMethod)) {
    stderr.writeln('Expected getCaretY implementation was not found; refusing unsafe caret patch.');
    exitCode = 1;
    return;
  }

  source = source.replaceFirst(oldMethod, patchedMethod);
  await file.writeAsString(source);
  stdout.writeln('Applied consistent TextPainter caret-line resolution patch.');
}

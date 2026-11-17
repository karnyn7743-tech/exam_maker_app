import 'dart:convert';
import 'dart:io';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:flutter/material.dart';

/// Read-only rendering of the same Fluent document used by the question editor.
class RichQuestionDocumentView extends StatelessWidget {
  final String documentJson;
  final TextDirection direction;
  final TextAlign fallbackAlignment;

  const RichQuestionDocumentView({
    super.key,
    required this.documentJson,
    this.direction = TextDirection.rtl,
    this.fallbackAlignment = TextAlign.right,
  });

  @override
  Widget build(BuildContext context) {
    try {
      final decoded = jsonDecode(documentJson);
      if (decoded is! Map<String, dynamic>) {
        return const SizedBox.shrink();
      }
      final document = FluentDocument.fromJson(decoded);
      return Directionality(
        textDirection: direction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: _buildNodes(document.content.nodes),
        ),
      );
    } catch (_) {
      return const Text(
        'تعذر عرض محتوى المستند؛ افتح السؤال بالمحرر المتقدم ثم أعد حفظه.',
        style: TextStyle(color: Colors.red, fontSize: 11),
      );
    }
  }

  List<Widget> _buildNodes(List<FNode> nodes) {
    final result = <Widget>[];
    for (final node in nodes) {
      if (node is Paragraph) {
        result.add(_buildParagraph(node));
      } else if (node is FluentImage) {
        result.add(_buildImage(node));
      } else if (node is HorizontalRule) {
        result.add(const Divider(height: 12));
      } else if (node is FluentList) {
        result.add(_buildList(node));
      } else if (node is FluentTable) {
        result.add(_buildTable(node));
      }
    }
    return result;
  }

  Widget _buildParagraph(Paragraph paragraph) {
    final style = paragraph.getStyle();
    final spans = <InlineSpan>[];
    for (final fragment in paragraph.fragments) {
      if (fragment is FluentImage) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _buildImage(fragment),
        ));
      } else if (fragment is Fragment) {
        final styles = fragment.styles ?? const <String>[];
        Color? color;
        try {
          if (fragment.color != null) {
            color = Color(int.parse(fragment.color!.replaceFirst('#', '0xFF')));
          }
        } catch (_) {}
        spans.add(TextSpan(
          text: fragment.text,
          style: TextStyle(
            fontFamily: fragment.fontFamily,
            fontSize: fragment.fontSize,
            fontWeight: styles.contains('bold') ? FontWeight.bold : FontWeight.normal,
            fontStyle: styles.contains('italic') ? FontStyle.italic : FontStyle.normal,
            decoration: styles.contains('underline')
                ? TextDecoration.underline
                : styles.contains('strikethrough')
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
            color: color,
            backgroundColor: fragment.highlightColor == null
                ? null
                : _parseColor(fragment.highlightColor),
          ),
        ));
      }
    }

    final alignment = switch (paragraph.textAlign) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'justify' => TextAlign.justify,
      'left' => TextAlign.left,
      _ => fallbackAlignment,
    };
    return Padding(
      padding: EdgeInsets.only(
        top: style.spacingBefore ?? 0,
        bottom: style.spacingAfter ?? 4,
        left: paragraph.indent * 12.0,
      ),
      child: RichText(
        textDirection: direction,
        textAlign: alignment,
        text: TextSpan(
          style: TextStyle(
            fontFamily: style.fontFamily,
            fontSize: style.fontSize ?? 14,
            height: style.lineHeight ?? 1.15,
            fontWeight: (style.styles ?? const []).contains('bold')
                ? FontWeight.bold
                : FontWeight.normal,
          ),
          children: spans,
        ),
      ),
    );
  }

  Color? _parseColor(String? value) {
    if (value == null) return null;
    try {
      return Color(int.parse(value.replaceFirst('#', '0xFF')));
    } catch (_) {
      return null;
    }
  }

  Widget _buildImage(FluentImage image) {
    final width = image.width ?? 180;
    final height = image.height ?? 120;
    Widget child;
    try {
      if (image.src.startsWith('data:')) {
        final comma = image.src.indexOf(',');
        child = comma < 0
            ? const SizedBox.shrink()
            : Image.memory(
                base64Decode(image.src.substring(comma + 1)),
                width: width,
                height: height,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
              );
      } else if (image.src.startsWith('http://') ||
          image.src.startsWith('https://')) {
        child = Image.network(
          image.src,
          width: width,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
        );
      } else if (File(image.src).existsSync()) {
        child = Image.file(
          File(image.src),
          width: width,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
        );
      } else {
        child = Image.asset(
          image.src,
          width: width,
          height: height,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
        );
      }
    } catch (_) {
      child = const Icon(Icons.broken_image);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: image.textAlign == 'center'
            ? Alignment.center
            : image.textAlign == 'right'
                ? Alignment.centerRight
                : Alignment.centerLeft,
        child: child,
      ),
    );
  }

  Widget _buildList(FluentList list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < list.items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    list.listType == 'ordered' ? '${i + 1}.' : '•',
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _buildNodes(list.items[i].children),
                )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTable(FluentTable table) {
    final columns = table.rows.isEmpty
        ? 1
        : table.rows.map((row) => row.cells.length).reduce((a, b) => a > b ? a : b);
    return Table(
      border: TableBorder.all(color: Colors.black54, width: 0.6),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: table.rows.map((row) {
        return TableRow(children: [
          for (final cell in row.cells)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildNodes(cell.children),
              ),
            ),
          for (var i = row.cells.length; i < columns; i++)
            const SizedBox.shrink(),
        ]);
      }).toList(),
    );
  }
}

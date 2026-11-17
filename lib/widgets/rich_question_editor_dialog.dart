import 'dart:convert';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:flutter/material.dart';

import '../models/exam_models.dart';

/// محرر مستند غني تجريبي للأسئلة.
/// يحتفظ ببنية Fluent Editor كاملة بصيغة JSON دون المساس ببيانات الأسئلة القديمة.
class RichQuestionEditorDialog extends StatefulWidget {
  final String? initialDocumentJson;
  final List<TextSpanModel> initialSpans;
  final String? initialText;

  const RichQuestionEditorDialog({
    super.key,
    this.initialDocumentJson,
    required this.initialSpans,
    this.initialText,
  });

  @override
  State<RichQuestionEditorDialog> createState() =>
      _RichQuestionEditorDialogState();
}

class _RichQuestionEditorDialogState extends State<RichQuestionEditorDialog> {
  late final FluentDocument _document;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _document = _createDocument();
    _document.documentLanguage = 'ar';
    _document.pendingLineHeight = 1.15;
    _document.pendingSpacingBefore = 0;
    _document.pendingSpacingAfter = 4;
  }

  FluentDocument _createDocument() {
    final saved = widget.initialDocumentJson;
    if (saved != null && saved.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(saved);
        if (decoded is Map<String, dynamic>) {
          return FluentDocument.fromJson(decoded);
        }
      } catch (_) {
        _loadError = true;
      }
    }

    final fragments = <FNode>[];
    for (final span in widget.initialSpans) {
      if (span.text.isEmpty) continue;
      final styles = <String>[];
      if (span.isBold) styles.add('bold');
      if (span.isUnderline) styles.add('underline');
      fragments.add(
        Fragment(
          span.text,
          styles: styles,
          fontFamily: span.fontFamily,
          fontSize: span.fontSize,
          color: span.colorHex,
        ),
      );
    }

    if (fragments.isEmpty && (widget.initialText ?? '').isNotEmpty) {
      fragments.add(Fragment(widget.initialText!));
    }
    if (fragments.isEmpty) fragments.add(Fragment(''));

    final paragraph = Paragraph()..fragments = fragments;
    return FluentDocument(content: Root(nodes: [paragraph]));
  }

  static const FluentEditorLabels _arabicLabels = FluentEditorLabels(
    file: 'ملف',
    save: 'حفظ المستند',
    open: 'فتح',
    exportAs: 'تصدير بصيغة',
    microsoftWord: 'Microsoft Word',
    pdf: 'PDF',
    html: 'HTML',
    markdown: 'Markdown',
    edit: 'تحرير',
    undo: 'تراجع',
    redo: 'إعادة',
    cut: 'قص',
    copy: 'نسخ',
    paste: 'لصق',
    selectAll: 'تحديد الكل',
    delete: 'حذف',
    wordCount: 'عدد الكلمات',
    characterCount: 'عدد الأحرف',
    insert: 'إدراج',
    link: 'رابط',
    image: 'صورة',
    table: 'جدول',
    horizontalLine: 'خط أفقي',
    settings: 'إعدادات',
    format: 'تنسيق',
    text: 'نص',
    bold: 'عريض',
    italic: 'مائل',
    underline: 'تسطير',
    strikethrough: 'يتوسطه خط',
    styles: 'الأنماط',
    align: 'محاذاة',
    alignLeft: 'محاذاة لليسار',
    alignCenter: 'توسيط',
    alignRight: 'محاذاة لليمين',
    justify: 'ضبط',
    lineSpacing: 'تباعد الأسطر',
    lineSpacingSingle: 'مفرد',
    lineSpacing115: '1.15',
    lineSpacing15: '1.5',
    lineSpacingDouble: 'مزدوج',
    paragraphSpacing: 'تباعد الفقرات',
    textColor: 'لون النص',
    highlightColor: 'تمييز النص',
    insertLink: 'إدراج رابط',
    cancel: 'إلغاء',
    confirmButton: 'تأكيد',
    insertButton: 'إدراج',
    apply: 'تطبيق',
    insertImage: 'إدراج صورة',
    done: 'تم',
    url: 'الرابط',
    linkText: 'نص الرابط',
    lineHeight: 'ارتفاع السطر',
    spacingBefore: 'مسافة قبل الفقرة',
    spacingAfter: 'مسافة بعد الفقرة',
    imageUrl: 'رابط الصورة',
    dragImageHere: 'اسحب الصورة هنا',
    clickToChooseImage: 'اضغط لاختيار صورة',
    replaceImage: 'استبدال الصورة',
    deleteImage: 'حذف الصورة',
    insertRowAbove: 'إضافة صف أعلى',
    insertRowBelow: 'إضافة صف أسفل',
  );

  String _extractPlainText() {
    final paragraphs = <String>[];

    void visit(FNode node) {
      if (node is FluentImage || node is HorizontalRule) return;
      if (node is Paragraph) {
        final text = node.fragments
            .where((fragment) => fragment is! FluentImage)
            .map((fragment) => fragment is Fragment ? fragment.text : '')
            .join()
            .replaceAll('\u200B', '');
        paragraphs.add(text);
        return;
      }
      if (node is FluentList) {
        for (final item in node.items) {
          for (final child in item.children) {
            visit(child);
          }
        }
        return;
      }
      if (node is FluentTable) {
        for (final row in node.rows) {
          for (final cell in row.cells) {
            for (final child in cell.children) {
              visit(child);
            }
          }
        }
      }
    }

    for (final node in _document.content.nodes) {
      visit(node);
    }
    return paragraphs.join('\n').trimRight();
  }

  void _finish() {
    Navigator.of(context).pop(<String, String>{
      'json': _document.toJson(),
      'text': _extractPlainText(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFE9EDF3),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'محرر السؤال المتقدم',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF1E3A8A),
          foregroundColor: Colors.white,
          actions: [
            TextButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.save, color: Colors.white),
              label: const Text(
                'اعتماد',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_loadError)
              const MaterialBanner(
                content: Text(
                  'تعذر فتح النسخة الغنية السابقة؛ تم فتح النص الأساسي بدلاً منها.',
                ),
                actions: [SizedBox.shrink()],
              ),
            Expanded(
              child: FluentEditor(
                document: _document,
                labels: _arabicLabels,
                toolbarMode: FluentToolbarMode.fixed,
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: Colors.white,
                child: const Text(
                  'يمكن إدراج الصور داخل المستند وتحديدها لتغيير حجمها، ثم اعتماد التعديلات.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

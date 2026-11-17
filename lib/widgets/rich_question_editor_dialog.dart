import 'dart:convert';

import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/widgets/fluent_document_widget.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:flutter/material.dart';

import '../models/exam_models.dart';

/// محرر مستند غني تجريبي للأسئلة.
/// Arabic RTL presentation and complete Fluent Editor localization are configured below.
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
      RichQuestionEditorDialogState();
}

class RichQuestionEditorDialogState extends State<RichQuestionEditorDialog> {
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

  static const FluentEditorLabels arabicLabels = FluentEditorLabels(
    libreOffice: 'LibreOffice',
    importHtml: 'استيراد HTML',
    importMarkdown: 'استيراد Markdown',
    importDocx: 'استيراد Word',
    importOdt: 'استيراد ODT',
    fileSaved: 'تم حفظ الملف',
    fileLoaded: 'تم فتح الملف بنجاح',
    fileLoadError: 'تعذر فتح الملف',
    exportSuccess: 'تم التصدير بنجاح',
    exportError: 'تعذر تصدير الملف',
    documentCopied: 'تم نسخ المستند',
    pasteWithoutFormatting: 'لصق دون تنسيق',
    showStats: 'إظهار الإحصاءات',
    documentLanguage: 'لغة المستند',
    superscript: 'مرتفع',
    subscript: 'منخفض',
    smallCaps: 'أحرف صغيرة',
    increaseIndent: 'زيادة المسافة البادئة',
    decreaseIndent: 'تقليل المسافة البادئة',
    alignAndIndent: 'المحاذاة والمسافات البادئة',
    or: 'أو',
    urlHint: 'أدخل عنوان الرابط',
    urlRequired: 'يرجى إدخال الرابط',
    linkTextHint: 'اكتب نص الرابط',
    linkTextRequired: 'يرجى إدخال نص الرابط',
    imageUrlHint: 'أدخل رابط الصورة',
    imageSelected: 'تم اختيار الصورة',
    fileReadError: 'تعذرت قراءة الملف',
    chooseListMarkerType: 'اختر نوع القائمة',
    all: 'الكل',
    bullets: 'نقاط',
    numbers: 'أرقام',
    checkboxes: 'مربعات اختيار',
    replaceLink: 'استبدال الرابط',
    deleteLink: 'حذف الرابط',
    goToLink: 'فتح الرابط',
    addCommentLabel: 'إضافة تعليق',
    commentDialogTitle: 'إضافة تعليق',
    commentHint: 'اكتب تعليقك هنا...',
    commentOverlapWarning: 'تنبيه: يتداخل التعليق مع تعليق آخر',
    sidebarTitle: 'التعليقات والأنشطة',
    emptySidebarMessage: 'لا توجد تعليقات أو اقتراحات في المستند',
    showResolvedLabel: 'إظهار التعليقات المحسومة',
    showCommentsLabel: 'إظهار التعليقات',
    hideCommentsLabel: 'إخفاء التعليقات',
    deletedTextLabel: 'نص محذوف',
    resolvedLabel: 'تمت المعالجة',
    replyHint: 'اكتب رداً...',
    resolveButton: 'حسم التعليق',
    defaultAuthorName: 'مستخدم',
    anonymousLabel: 'مجهول',
    pdfCommentSubject: 'تعليق',
    authorInfoDialogTitle: 'بيانات الكاتب',
    authorNameLabel: 'اسم الكاتب',
    authorNameHint: 'أدخل اسمك...',
    setAuthorLabel: 'تعيين الكاتب',
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
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: FluentEditor(
                  document: _document,
                  labels: arabicLabels,
                ),
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


/// محرر غني مضمّن داخل خلية السؤال في ورقة الاختبار.
/// يحتفظ بالمستند داخل هذه الخلية، ويصدر JSON والنص المجرد عند كل تعديل فعلي.
class RichQuestionInlineEditor extends StatefulWidget {
  final String? initialDocumentJson;
  final List<TextSpanModel> initialSpans;
  final String? initialText;
  final ValueChanged<Map<String, String>> onChanged;
  final ValueChanged<FluentDocument?> onDocumentReady;
  final VoidCallback onClose;

  const RichQuestionInlineEditor({
    super.key,
    this.initialDocumentJson,
    required this.initialSpans,
    this.initialText,
    required this.onChanged,
    required this.onDocumentReady,
    required this.onClose,
  });

  @override
  State<RichQuestionInlineEditor> createState() =>
      _RichQuestionInlineEditorState();
}

class _RichQuestionInlineEditorState extends State<RichQuestionInlineEditor> {
  late final FluentDocument _document;
  bool _loadError = false;
  int _lastContentVersion = -1;

  @override
  void initState() {
    super.initState();
    _document = _createDocument();
    _document.documentLanguage = 'ar';
    _document.pendingLineHeight = 1.15;
    _document.pendingSpacingBefore = 0;
    _document.pendingSpacingAfter = 4;
    _lastContentVersion = _document.contentVersion;
    _document.addListener(_handleDocumentChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onDocumentReady(_document);
    });
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

  void _handleDocumentChanged() {
    final version = _document.contentVersion;
    if (version == _lastContentVersion) return;
    _lastContentVersion = version;
    widget.onChanged({
      'json': _document.toJson(),
      'text': _extractPlainText(),
    });
  }

  @override
  void dispose() {
    _document.removeListener(_handleDocumentChanged);
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFF1E3A8A), width: 1.2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: const Color(0xFFEAF0FA),
            child: Row(
              children: [
                const Icon(Icons.edit_document, size: 17, color: Color(0xFF1E3A8A)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'تحرير السؤال مباشرة',
                    style: TextStyle(
                      color: Color(0xFF1E3A8A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إنهاء التحرير',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.check_circle, color: Color(0xFF0F766E), size: 20),
                ),
              ],
            ),
          ),
          if (_loadError)
            const MaterialBanner(
              content: Text(
                'تعذر فتح النسخة الغنية السابقة؛ تم تحميل النص الأساسي.',
                style: TextStyle(fontSize: 11),
              ),
              actions: [SizedBox.shrink()],
            ),
          Expanded(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: FluentDocumentWidget(
                document: _document,
                maxWidth: 1000,
                labels: RichQuestionEditorDialogState.arabicLabels,
                toolbarMode: FluentToolbarMode.bubble,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


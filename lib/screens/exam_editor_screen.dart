import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/exam_models.dart';
import '../utils/save_dialog_helper.dart';
import '../services/docx_generator_service.dart';
import '../services/exam_storage_service.dart';
import '../services/pdf_export_service.dart';

class ExamEditorScreen extends StatefulWidget {
  final ExamModel initialExam;
  final bool isNewExam;

  const ExamEditorScreen({
    super.key,
    required this.initialExam,
    required this.isNewExam,
  });

  @override
  State<ExamEditorScreen> createState() => _ExamEditorScreenState();
}

class _ExamEditorScreenState extends State<ExamEditorScreen> {
  late ExamModel _exam;
  late bool _isNew;

  // أبعاد الترويسة والأعمدة
  double _sideHeaderWidth = 145.0;
  double _questionColWidth = 38.0;
  double _markColWidth = 38.0;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _exam = widget.initialExam;
    _isNew = widget.isNewExam;
  }

  void _insertTatweel(TextEditingController controller) {
    final pos = controller.selection.start;
    const tatweel = '\u0640';
    if (pos >= 0) {
      controller.text =
          controller.text.replaceRange(pos, controller.selection.end, tatweel);
      controller.selection = TextSelection.collapsed(offset: pos + 1);
    } else {
      controller.text += tatweel;
    }
  }

  Future<void> _pickLogoImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _exam.header.logoImagePath = image.path;
      });
    }
  }

  Future<void> _triggerSave() async {
    final saved = await showSaveChoiceDialog(
      context: context,
      currentExam: _exam,
      isNewExam: _isNew,
      onPerformSave: (ExamModel updated) {
        setState(() {
          _exam = updated;
          _isNew = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الاختبار بنجاح: ${_exam.fileName}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      },
    );

    if (saved && mounted) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _exportAndOpenOffice() async {
    await ExamStorageService.saveOrUpdateExam(_exam);
    await DocxGeneratorService.generateAndOpenDocx(_exam);
  }

  Future<void> _exportPdfToDownloads() async {
    await ExamStorageService.saveOrUpdateExam(_exam);
    try {
      final path = await PdfExportService.exportToDownloadsPdf(_exam);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ PDF بنجاح في مجلد التنزيلات:\n$path'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تصدير PDF: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD6D9E0),
      appBar: AppBar(
        title: Text(_isNew ? 'اختبار جديد' : _exam.fileName,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: 'تصدير PDF وحفظه في مجلد التنزيلات',
            onPressed: _exportPdfToDownloads,
          ),
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            tooltip: 'تصدير وفتح في تطبيق Word',
            onPressed: _exportAndOpenOffice,
          ),
          IconButton(
            icon: const Icon(Icons.view_column, color: Colors.white),
            tooltip: 'أبعاد الترويسة والأعمدة',
            onPressed: _openHeaderFlexSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.white),
            tooltip: 'خيارات التذييل والهوامش',
            onPressed: _openFooterSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white, size: 26),
            tooltip: 'حفظ',
            onPressed: _triggerSave,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // إطار ورقة الامتحان: ينتهي مباشرة عند الفقرة الأخيرة والتذييل دون إلزام كامل الصفحة
              Container(
                constraints: const BoxConstraints(maxWidth: 820),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                padding: EdgeInsets.only(
                  top: _exam.header.topMargin1cm ? 38.0 : 12.0, // هامش 1 سم الفعلي
                  left: 12.0,
                  right: 12.0,
                  bottom: 12.0,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildExamHeader(),
                    const SizedBox(height: 8),
                    _buildQuestionsTable(),
                    const SizedBox(height: 10),
                    _buildFooterPreview(),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('إضافة سؤال جديد'),
                onPressed: () => _openQuestionDialog(),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'المجموع: ${_exam.totalMarks} د',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. الترويسة اليمنى (5 حقول مستقلة)
              SizedBox(
                width: _sideHeaderWidth,
                child: InkWell(
                  onTap: _editAdminHeaderDialog,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _exam.header.country,
                        style: TextStyle(
                          fontFamily: _exam.header.adminFont,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.ministry,
                        style: TextStyle(
                          fontFamily: _exam.header.adminFont,
                          fontSize: _exam.header.adminFontSize,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.governorate,
                        style: TextStyle(
                          fontFamily: _exam.header.adminFont,
                          fontSize: _exam.header.adminFontSize - 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.directorate,
                        style: TextStyle(
                          fontFamily: _exam.header.adminFont,
                          fontSize: _exam.header.adminFontSize - 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.school,
                        style: TextStyle(
                          fontFamily: _exam.header.adminFont,
                          fontWeight: FontWeight.bold,
                          fontSize: _exam.header.adminFontSize,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),

              // 2. الترويسة الوسطى (البسملة والشعار)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: _editBasmalaDialog,
                      child: Text(
                        _exam.header.basmalaText,
                        style: TextStyle(
                          fontFamily: _exam.header.basmalaFont,
                          fontWeight: _exam.header.basmalaBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.basmalaFontSize,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _pickLogoImage,
                      child: _exam.header.logoImagePath != null
                          ? Image.file(File(_exam.header.logoImagePath!),
                              height: 52, fit: BoxFit.contain)
                          : Container(
                              height: 52,
                              width: 52,
                              decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(4)),
                              child: const Icon(Icons.add_photo_alternate,
                                  size: 24, color: Colors.grey),
                            ),
                    ),
                  ],
                ),
              ),

              // 3. الترويسة اليسرى (5 حقول مستقلة)
              SizedBox(
                width: _sideHeaderWidth,
                child: InkWell(
                  onTap: _editExamDetailsDialog,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الصف : ${_exam.header.grade}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'الماده : ${_exam.header.subject}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        'التاريخ: ${_exam.header.examDate}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontSize: _exam.header.detailsFontSize,
                        ),
                      ),
                      Text(
                        'الزمن: ${_exam.header.examTime}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontSize: _exam.header.detailsFontSize - 0.5,
                        ),
                      ),
                      Text(
                        'الفتره: ${_exam.header.period}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontSize: _exam.header.detailsFontSize - 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // عنوان الامتحان
          InkWell(
            onTap: _editExamTitleDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: Colors.grey.shade200,
              child: Text(
                _exam.header.examTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: _exam.header.titleFont,
                  fontWeight: _exam.header.titleBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: _exam.header.titleFontSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- جدول الأسئلة مع دمج صف العناوين كأول صف ---
  Widget _buildQuestionsTable() {
    return Table(
      border: TableBorder.all(color: Colors.black, width: 1),
      columnWidths: {
        0: FixedColumnWidth(_questionColWidth),
        1: const FlexColumnWidth(),
        2: FixedColumnWidth(_markColWidth),
      },
      children: [
        // --- صف العناوين الأول المدمج داخل الجدول ---
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: const Text(
                  'السؤال',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                ),
              ),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: InkWell(
                onTap: _editInstructionDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                  child: Text(
                    _exam.header.instructionText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: const Text(
                  'الدرجة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                ),
              ),
            ),
          ],
        ),

        // --- صفوف الأسئلة والفقرات ---
        ..._exam.questions.asMap().entries.map((entry) {
          final index = entry.key;
          final q = entry.value;

          Widget titleWidget = Text(
            q.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          );

          if (q.titleOrientation == QuestionTitleOrientation.verticalBottomToTop) {
            titleWidget = RotatedBox(quarterTurns: 3, child: titleWidget);
          } else if (q.titleOrientation == QuestionTitleOrientation.verticalTopToBottom) {
            titleWidget = RotatedBox(quarterTurns: 1, child: titleWidget);
          }

          return TableRow(
            children: [
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: InkWell(
                  onTap: () => _openQuestionDialog(questionIndex: index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Center(child: titleWidget),
                  ),
                ),
              ),
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: InkWell(
                  onTap: () => _openQuestionDialog(questionIndex: index),
                  child: Padding(
                    padding: const EdgeInsets.all(6.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          children: q.spans.map((s) {
                            return Text(
                              s.text,
                              style: TextStyle(
                                fontFamily: s.fontFamily,
                                fontWeight: s.isBold ? FontWeight.bold : FontWeight.normal,
                                decoration: s.isUnderline ? TextDecoration.underline : TextDecoration.none,
                                fontSize: s.fontSize,
                              ),
                            );
                          }).toList(),
                        ),
                        if (q.elements.isNotEmpty) const SizedBox(height: 6),
                        ...q.elements.map((el) => _buildRenderedElement(el)),
                      ],
                    ),
                  ),
                ),
              ),
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: InkWell(
                  onTap: () => _openQuestionDialog(questionIndex: index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Center(
                      child: Text(
                        q.mark > 0 ? '${q.mark} د' : '-',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildRenderedElement(InsertableElement el) {
    switch (el.type) {
      case ElementType.image:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Center(
            child: Image.file(
              File(el.content),
              height: el.height,
              width: el.width,
              fit: BoxFit.contain,
            ),
          ),
        );
      case ElementType.textBox:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border.all(color: Colors.black87),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            el.content,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        );
      case ElementType.dottedLine:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            el.content,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, letterSpacing: 1.5),
          ),
        );
    }
  }

  Widget _buildFooterPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text(
            _exam.header.isMultiPage
                ? _exam.header.continuationText
                : _exam.header.singlePageFooterText,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _exam.header.teacherSignature,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  void _openHeaderFlexSettingsDialog() {
    double sideWidth = _sideHeaderWidth;
    double qWidth = _questionColWidth;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('أبعاد خانات الترويسة والأعمدة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('عرض الترويسة اليمنى واليسرى (تمدد نحو الوسط):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Slider(
                  value: sideWidth,
                  min: 100,
                  max: 200,
                  divisions: 20,
                  label: '${sideWidth.toInt()} px',
                  onChanged: (v) => setDlgState(() => sideWidth = v),
                ),
                const Divider(),
                const Text('عرض عمودي (السؤال) و(الدرجة):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Slider(
                  value: qWidth,
                  min: 28,
                  max: 55,
                  divisions: 27,
                  label: '${qWidth.toInt()} px',
                  onChanged: (v) => setDlgState(() => qWidth = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _sideHeaderWidth = sideWidth;
                  _questionColWidth = qWidth;
                  _markColWidth = qWidth;
                });
                Navigator.pop(ctx);
              },
              child: const Text('تطبيق الأبعاد'),
            ),
          ],
        ),
      ),
    );
  }

  // --- نافذة كتابة وتنسيق السؤال المزودة بالشريط المتحرك الاحترافي ---
  void _openQuestionDialog({int? questionIndex}) {
    final bool isEdit = questionIndex != null;
    final q = isEdit
        ? _exam.questions[questionIndex]
        : QuestionModel(
            id: const Uuid().v4(),
            title: 'السؤال ${_exam.questions.length + 1}',
            spans: [],
            elements: [],
          );

    final titleCtrl = TextEditingController(text: q.title);
    final textCtrl =
        TextEditingController(text: q.spans.map((e) => e.text).join(''));
    final markCtrl =
        TextEditingController(text: q.mark > 0 ? q.mark.toString() : '5');
    QuestionTitleOrientation orientation = q.titleOrientation;
    List<InsertableElement> currentElements = List.from(q.elements);

    List<TextSpanModel> workingSpans = q.spans.isNotEmpty
        ? q.spans.map((s) => TextSpanModel(
              text: s.text,
              isBold: s.isBold,
              isUnderline: s.isUnderline,
              fontSize: s.fontSize,
              fontFamily: s.fontFamily,
            )).toList()
        : [
            TextSpanModel(
              text: textCtrl.text,
              fontSize: 14.0,
              fontFamily: 'Amiri',
            )
          ];

    String currentFont = q.spans.isNotEmpty ? q.spans.first.fontFamily : 'Amiri';
    double currentFontSize = 14.0;
    bool isBoldActive = false;
    bool isUnderlineActive = false;

    // دالة إدراج رمز عند موضع المؤشر
    void insertAtCursor(String symbol) {
      final pos = textCtrl.selection.start;
      if (pos >= 0) {
        textCtrl.text =
            textCtrl.text.replaceRange(pos, textCtrl.selection.end, symbol);
        textCtrl.selection =
            TextSelection.collapsed(offset: pos + symbol.length);
      } else {
        textCtrl.text += symbol;
      }
    }

    // دالة تطبيق التنسيق على النص المحدد فقط
    void applyFormatToSelection({
      bool? bold,
      bool? underline,
      String? font,
      double? size,
    }) {
      final sel = textCtrl.selection;
      if (!sel.isValid || sel.isCollapsed) return;

      final fullText = textCtrl.text;
      final selStart = sel.start;
      final selEnd = sel.end;

      List<TextSpanModel> newSpans = [];
      int currentPos = 0;

      for (var span in workingSpans) {
        int spanStart = currentPos;
        int spanEnd = currentPos + span.text.length;

        if (spanEnd <= selStart || spanStart >= selEnd) {
          newSpans.add(span);
        } else {
          if (spanStart < selStart) {
            newSpans.add(TextSpanModel(
              text: fullText.substring(spanStart, selStart),
              isBold: span.isBold,
              isUnderline: span.isUnderline,
              fontSize: span.fontSize,
              fontFamily: span.fontFamily,
            ));
          }

          int overlapStart = spanStart > selStart ? spanStart : selStart;
          int overlapEnd = spanEnd < selEnd ? spanEnd : selEnd;

          newSpans.add(TextSpanModel(
            text: fullText.substring(overlapStart, overlapEnd),
            isBold: bold ?? span.isBold,
            isUnderline: underline ?? span.isUnderline,
            fontSize: size ?? span.fontSize,
            fontFamily: font ?? span.fontFamily,
          ));

          if (spanEnd > selEnd) {
            newSpans.add(TextSpanModel(
              text: fullText.substring(selEnd, spanEnd),
              isBold: span.isBold,
              isUnderline: span.isUnderline,
              fontSize: span.fontSize,
              fontFamily: span.fontFamily,
            ));
          }
        }
        currentPos = spanEnd;
      }

      workingSpans = newSpans.where((s) => s.text.isNotEmpty).toList();
    }

    // لوحة الرموز الشاملة
    void showSymbolsModal(void Function(void Function()) setParentState) {
      final Map<String, List<String>> categories = {
        'تقييم وأقواس': ['✔', '✘', '✓', '✗', '(   )', '[   ]', '○', '●', '□', '■', '« »'],
        'أسس علوية (س²)': ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹', '⁺', '⁻', 'ⁿ', 'ˣ', 'ʸ'],
        'صيغ كيميائية (H₂O)': ['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉', '₊', '₋', 'ₐ', 'ₑ', 'ₒ', 'ₓ'],
        'عمليات ومقارنات': ['×', '÷', '+', '-', '=', '≠', '≈', '<', '>', '≤', '≥', '±'],
        'دوال ورياضيات': ['√', '∛', 'π', '∞', '%', '°', '½', '¼', '¾', '∆', '∑', '∫'],
        'أسهم': ['←', '→', '↑', '↓', '↔', '⇐', '⇒', '⇔'],
      };

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (bCtx) => DefaultTabController(
          length: categories.keys.length,
          child: SizedBox(
            height: 340,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  labelColor: const Color(0xFF1E3A8A),
                  indicatorColor: const Color(0xFF1E3A8A),
                  tabs: categories.keys.map((c) => Tab(text: c)).toList(),
                ),
                Expanded(
                  child: TabBarView(
                    children: categories.values.map((symbols) {
                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: symbols.length,
                        itemBuilder: (context, i) {
                          final sym = symbols[i];
                          return InkWell(
                            onTap: () {
                              setParentState(() => insertAtCursor(sym));
                              Navigator.pop(bCtx);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade300),
                                borderRadius: BorderRadius.circular(6),
                                color: Colors.grey.shade50,
                              ),
                              child: Center(
                                child: Text(sym,
                                    style: const TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 12,
            right: 12,
            top: 12,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                          controller: titleCtrl,
                          decoration: const InputDecoration(labelText: 'اسم السؤال (س١)')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                          controller: markCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'الدرجة')),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // اتجاه كتابة السؤال
                Row(
                  children: [
                    const Text('الاتجاه: ',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ChoiceChip(
                      label: const Text('أفقي', style: TextStyle(fontSize: 11)),
                      selected: orientation == QuestionTitleOrientation.horizontal,
                      onSelected: (val) => setModalState(
                          () => orientation = QuestionTitleOrientation.horizontal),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('رأسي ◄', style: TextStyle(fontSize: 11)),
                      selected: orientation == QuestionTitleOrientation.verticalBottomToTop,
                      onSelected: (val) => setModalState(() =>
                          orientation = QuestionTitleOrientation.verticalBottomToTop),
                    ),
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: const Text('رأسي ►', style: TextStyle(fontSize: 11)),
                      selected: orientation == QuestionTitleOrientation.verticalTopToBottom,
                      onSelected: (val) => setModalState(() =>
                          orientation = QuestionTitleOrientation.verticalTopToBottom),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // ==========================================
                // شريط الأوامر والوظائف الأفقي المتحرك
                // ==========================================
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        // 1. زر إدراج صورة
                        _buildBarBtn(
                          icon: Icons.image_outlined,
                          color: Colors.blueGrey.shade700,
                          tooltip: 'إدراج صورة',
                          onTap: () async {
                            final img = await _picker.pickImage(source: ImageSource.gallery);
                            if (img != null) {
                              setModalState(() {
                                currentElements.add(InsertableElement(
                                  id: const Uuid().v4(),
                                  type: ElementType.image,
                                  content: img.path,
                                  width: 90,
                                  height: 90,
                                ));
                              });
                            }
                          },
                        ),
                        // 2. زر سطر إجابة
                        _buildBarBtn(
                          icon: Icons.border_horizontal,
                          color: Colors.blueGrey.shade700,
                          tooltip: 'سطر إجابة',
                          onTap: () {
                            setModalState(() {
                              currentElements.add(InsertableElement(
                                id: const Uuid().v4(),
                                type: ElementType.dottedLine,
                                content: '......................................................................',
                              ));
                            });
                          },
                        ),
                        // 3. زر إدراج قوسين (   )
                        _buildBarBtn(
                          text: '( )',
                          color: Colors.blueGrey.shade700,
                          tooltip: 'أقواس خالية',
                          onTap: () => setModalState(() => insertAtCursor('(   )')),
                        ),
                        // 4. زر علامة صح ✔️
                        _buildBarBtn(
                          icon: Icons.check,
                          color: const Color(0xFF0F766E),
                          tooltip: 'علامة صح',
                          onTap: () => setModalState(() => insertAtCursor('✔')),
                        ),
                        // 5. زر علامة خطأ ✖️
                        _buildBarBtn(
                          icon: Icons.close,
                          color: const Color(0xFFB91C1C),
                          tooltip: 'علامة خطأ',
                          onTap: () => setModalState(() => insertAtCursor('✘')),
                        ),
                        // 6. مربع إرشاد
                        _buildBarBtn(
                          icon: Icons.edit_note,
                          color: const Color(0xFFD97706),
                          tooltip: 'مربع إرشاد',
                          onTap: () {
                            _showTextBoxEntryDialog(context, (txt) {
                              setModalState(() {
                                currentElements.add(InsertableElement(
                                  id: const Uuid().v4(),
                                  type: ElementType.textBox,
                                  content: txt,
                                ));
                              });
                            });
                          },
                        ),
                        // 7. خط عريض B للمنطقة المحددة
                        _buildBarBtn(
                          text: 'B',
                          color: isBoldActive ? Colors.blue : Colors.blueGrey.shade800,
                          tooltip: 'خط عريض للمحدد',
                          onTap: () {
                            setModalState(() {
                              isBoldActive = !isBoldActive;
                              applyFormatToSelection(bold: isBoldActive);
                            });
                          },
                        ),
                        // 8. تسطير U للمنطقة المحددة
                        _buildBarBtn(
                          text: 'U',
                          color: isUnderlineActive ? Colors.blue : Colors.blueGrey.shade800,
                          tooltip: 'تسطير للمحدد',
                          onTap: () {
                            setModalState(() {
                              isUnderlineActive = !isUnderlineActive;
                              applyFormatToSelection(underline: isUnderlineActive);
                            });
                          },
                        ),
                        // 9. أس علوي x²
                        _buildBarBtn(
                          text: 'x²',
                          color: const Color(0xFF0284C7),
                          tooltip: 'أس علوي',
                          onTap: () => setModalState(() => insertAtCursor('²')),
                        ),
                        // 10. رقم سفلي كيميائي x₂
                        _buildBarBtn(
                          text: 'x₂',
                          color: const Color(0xFF0284C7),
                          tooltip: 'صيغة كيميائية',
                          onTap: () => setModalState(() => insertAtCursor('₂')),
                        ),
                        // 11. كشيدة
                        _buildBarBtn(
                          text: 'ـ',
                          color: Colors.blueGrey.shade800,
                          tooltip: 'كشيدة تمديد',
                          onTap: () => _insertTatweel(textCtrl),
                        ),
                        // 12. اختيار نوع الخط
                        PopupMenuButton<String>(
                          tooltip: 'نوع الخط للمحدد',
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Center(
                              child: Text('خط',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                          ),
                          onSelected: (val) {
                            setModalState(() {
                              currentFont = val;
                              applyFormatToSelection(font: val);
                            });
                          },
                          itemBuilder: (ctx) => [
                            'Amiri',
                            'Sultan',
                            'Thuluth',
                            'Traditional Arabic',
                            'Arial'
                          ].map((f) => PopupMenuItem(value: f, child: Text(f))).toList(),
                        ),
                        // 13. اختيار حجم الخط
                        PopupMenuButton<double>(
                          tooltip: 'حجم الخط للمحدد',
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Center(
                              child: Text('حجم',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)),
                            ),
                          ),
                          onSelected: (val) {
                            setModalState(() {
                              currentFontSize = val;
                              applyFormatToSelection(size: val);
                            });
                          },
                          itemBuilder: (ctx) => [12.0, 14.0, 16.0, 18.0, 20.0, 22.0]
                              .map((s) => PopupMenuItem(
                                  value: s, child: Text('${s.toInt()} نقطة')))
                              .toList(),
                        ),
                        // 14. لوحة الرموز الشاملة
                        _buildBarBtn(
                          text: 'رموز',
                          color: const Color(0xFF0D9488),
                          tooltip: 'لوحة الرموز والدوال',
                          onTap: () => showSymbolsModal(setModalState),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // حقل كتابة وتحرير السؤال
                TextField(
                  controller: textCtrl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'محتوى نص السؤال (حدد جزءاً ثم اضغط على زر التنسيق أعلاه)',
                    border: OutlineInputBorder(),
                  ),
                ),

                if (currentElements.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: currentElements.asMap().entries.map((entry) {
                      final i = entry.key;
                      final el = entry.value;
                      return Chip(
                        label: Text(el.type == ElementType.image
                            ? 'صورة مدرجة'
                            : el.type == ElementType.textBox
                                ? 'مربع إرشاد'
                                : 'سطر إجابة'),
                        onDeleted: () =>
                            setModalState(() => currentElements.removeAt(i)),
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 12),

                ElevatedButton(
                  onPressed: () {
                    final spansToSave = workingSpans.isNotEmpty &&
                            workingSpans.map((s) => s.text).join('') == textCtrl.text
                        ? workingSpans
                        : [
                            TextSpanModel(
                              text: textCtrl.text,
                              isBold: isBoldActive,
                              isUnderline: isUnderlineActive,
                              fontSize: currentFontSize,
                              fontFamily: currentFont,
                            )
                          ];

                    final newQ = QuestionModel(
                      id: q.id,
                      title: titleCtrl.text,
                      titleOrientation: orientation,
                      mark: double.tryParse(markCtrl.text) ?? 0.0,
                      spans: spansToSave,
                      elements: currentElements,
                    );

                    setState(() {
                      if (isEdit) {
                        _exam.questions[questionIndex] = newQ;
                      } else {
                        _exam.questions.add(newQ);
                      }
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('تأكيد السؤال وحفظ التنسيق'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // أزرار شريط الأدوات المصغرة
  Widget _buildBarBtn({
    IconData? icon,
    String? text,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 38,
          minWidth: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 18)
                : Text(
                    text ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _showTextBoxEntryDialog(BuildContext context, Function(String) onConfirm) {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدراج مربع نص / إرشاد'),
        content: TextField(
          controller: textCtrl,
          decoration: const InputDecoration(
            hintText: 'اكتب نص المربع هنا...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (textCtrl.text.trim().isNotEmpty) {
                onConfirm(textCtrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('إدراج'),
          ),
        ],
      ),
    );
  }

  void _openFooterSettingsDialog() {
    final singleCtrl = TextEditingController(text: _exam.header.singlePageFooterText);
    final multiCtrl = TextEditingController(text: _exam.header.continuationText);
    final signCtrl = TextEditingController(text: _exam.header.teacherSignature);
    bool isMulti = _exam.header.isMultiPage;
    bool topMargin = _exam.header.topMargin1cm;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('خيارات التذييل والهامش'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('فراغ رأس الصفحة 1 سم'),
                  value: topMargin,
                  onChanged: (val) => setDlgState(() => topMargin = val),
                ),
                const Divider(),
                SwitchListTile(
                  title: const Text('الاختبار أكثر من ورقة'),
                  subtitle: const Text('إظهار عبارة (يتبع / اقلب الصفحة)'),
                  value: isMulti,
                  onChanged: (val) => setDlgState(() => isMulti = val),
                ),
                if (isMulti)
                  TextField(
                    controller: multiCtrl,
                    decoration: const InputDecoration(labelText: 'عبارة المتابعة للورقة التالية'),
                  )
                else
                  TextField(
                    controller: singleCtrl,
                    decoration: const InputDecoration(labelText: 'عبارة ختام الامتحان'),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: signCtrl,
                  decoration: const InputDecoration(labelText: 'توقيع المعلم'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _exam.header.topMargin1cm = topMargin;
                  _exam.header.isMultiPage = isMulti;
                  _exam.header.singlePageFooterText = singleCtrl.text;
                  _exam.header.continuationText = multiCtrl.text;
                  _exam.header.teacherSignature = signCtrl.text;
                });
                Navigator.pop(ctx);
              },
              child: const Text('حفظ الإعدادات'),
            ),
          ],
        ),
      ),
    );
  }

  void _editAdminHeaderDialog() {
    final cCountry = TextEditingController(text: _exam.header.country);
    final cGov = TextEditingController(text: _exam.header.governorate);
    final cDir = TextEditingController(text: _exam.header.directorate);
    final cSchool = TextEditingController(text: _exam.header.school);
    final cMinistry = TextEditingController(text: _exam.header.ministry);
    String font = _exam.header.adminFont;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('تعديل الحقول الإدارية (اليمين)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: font,
                  isExpanded: true,
                  items: ['Amiri', 'Sultan', 'Thuluth', 'Traditional Arabic']
                      .map((f) => DropdownMenuItem(value: f, child: Text('الخط: $f')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => font = v);
                  },
                ),
                TextField(controller: cCountry, decoration: const InputDecoration(labelText: 'اسم الدولة')),
                TextField(controller: cMinistry, decoration: const InputDecoration(labelText: 'اسم الوزارة')),
                TextField(controller: cGov, decoration: const InputDecoration(labelText: 'اسم مكتب المحافظة')),
                TextField(controller: cDir, decoration: const InputDecoration(labelText: 'اسم إدارة المديرية')),
                TextField(controller: cSchool, decoration: const InputDecoration(labelText: 'اسم المدرسة')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _exam.header.country = cCountry.text;
                  _exam.header.ministry = cMinistry.text;
                  _exam.header.governorate = cGov.text;
                  _exam.header.directorate = cDir.text;
                  _exam.header.school = cSchool.text;
                  _exam.header.adminFont = font;
                });
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _editExamDetailsDialog() {
    final cGrade = TextEditingController(text: _exam.header.grade);
    final cSub = TextEditingController(text: _exam.header.subject);
    final cDate = TextEditingController(text: _exam.header.examDate);
    final cTime = TextEditingController(text: _exam.header.examTime);
    final cPeriod = TextEditingController(text: _exam.header.period);
    String font = _exam.header.detailsFont;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('تعديل بيانات الامتحان (اليسار)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: font,
                  isExpanded: true,
                  items: ['Amiri', 'Sultan', 'Thuluth', 'Traditional Arabic']
                      .map((f) => DropdownMenuItem(value: f, child: Text('الخط: $f')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => font = v);
                  },
                ),
                TextField(controller: cGrade, decoration: const InputDecoration(labelText: 'اسم الصف')),
                TextField(controller: cSub, decoration: const InputDecoration(labelText: 'اسم المادة')),
                TextField(controller: cDate, decoration: const InputDecoration(labelText: 'التاريخ')),
                TextField(controller: cTime, decoration: const InputDecoration(labelText: 'الزمن')),
                TextField(controller: cPeriod, decoration: const InputDecoration(labelText: 'الفترة')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _exam.header.grade = cGrade.text;
                  _exam.header.subject = cSub.text;
                  _exam.header.examDate = cDate.text;
                  _exam.header.examTime = cTime.text;
                  _exam.header.period = cPeriod.text;
                  _exam.header.detailsFont = font;
                });
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _editExamTitleDialog() {
    final cTitle = TextEditingController(text: _exam.header.examTitle);
    String font = _exam.header.titleFont;
    double size = _exam.header.titleFontSize;
    bool bold = _exam.header.titleBold;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('تعديل عنوان الاختبار الرئيسي'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cTitle,
                style: TextStyle(fontFamily: font, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButton<String>(
                    value: font,
                    items: ['Amiri', 'Sultan', 'Thuluth', 'Traditional Arabic']
                        .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => font = v);
                    },
                  ),
                  DropdownButton<double>(
                    value: size,
                    items: [11.0, 12.0, 14.0, 16.0, 18.0]
                        .map((s) => DropdownMenuItem(value: s, child: Text('${s.toInt()} pt')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => size = v);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.format_bold, color: bold ? Colors.blue : Colors.grey),
                    onPressed: () => setDlgState(() => bold = !bold),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _exam.header.examTitle = cTitle.text;
                  _exam.header.titleFont = font;
                  _exam.header.titleFontSize = size;
                  _exam.header.titleBold = bold;
                });
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _editBasmalaDialog() {
    final cBasmala = TextEditingController(text: _exam.header.basmalaText);
    String font = _exam.header.basmalaFont;
    double size = _exam.header.basmalaFontSize;
    bool bold = _exam.header.basmalaBold;
    final List<String> fonts = ['Amiri', 'Sultan', 'Thuluth', 'ZagharefBesm'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('تنسيق وتحرير البسملة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cBasmala,
                style: TextStyle(
                  fontFamily: font,
                  fontSize: size,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                ),
                decoration: const InputDecoration(
                  labelText: 'نص البسملة / العبارة الافتتاحية',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButton<String>(
                    value: font,
                    items: fonts.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => font = v);
                    },
                  ),
                  DropdownButton<double>(
                    value: size,
                    items: [10.0, 11.0, 12.0, 14.0, 16.0, 18.0, 22.0]
                        .map((s) => DropdownMenuItem(value: s, child: Text('${s.toInt()} pt')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDlgState(() => size = v);
                    },
                  ),
                  IconButton(
                    icon: Icon(Icons.format_bold, color: bold ? Colors.blue : Colors.grey),
                    onPressed: () => setDlgState(() => bold = !bold),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _exam.header.basmalaText = cBasmala.text;
                  _exam.header.basmalaFont = font;
                  _exam.header.basmalaFontSize = size;
                  _exam.header.basmalaBold = bold;
                });
                Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _editInstructionDialog() {
    final cInst = TextEditingController(text: _exam.header.instructionText);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل عبارة التوجيه'),
        content: TextField(
          controller: cInst,
          decoration: const InputDecoration(
            labelText: 'عبارة التوجيه أعلى الأسئلة',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              setState(() => _exam.header.instructionText = cInst.text);
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

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

  // عرض خانتي الترويسة اليمنى واليسرى (المرتكز ثابت على الحافة والتمدد نحو الوسط)
  double _sideHeaderWidth = 145.0;

  // عرض أعمدة السؤال والدرجة
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
            children: [
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
                padding: const EdgeInsets.all(12),
                child: Column(
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
              const SizedBox(height: 60),
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
              // 1. الترويسة اليمنى (5 حقول فقط وقابلة للتعديل)
              SizedBox(
                width: _sideHeaderWidth,
                child: InkWell(
                  onTap: _editAdminHeaderDialog,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _exam.header.country,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.ministry,
                        style: const TextStyle(fontSize: 9.5),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.governorate,
                        style: const TextStyle(fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.directorate,
                        style: const TextStyle(fontSize: 9),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.school,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9.5),
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
                    Text(
                      _exam.header.basmalaText,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      textAlign: TextAlign.center,
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

              // 3. الترويسة اليسرى (5 حقول مستقلة وقابلة للتعديل)
              SizedBox(
                width: _sideHeaderWidth,
                child: InkWell(
                  onTap: _editExamDetailsDialog,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الصف : ${_exam.header.grade}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      Text(
                        'الماده : ${_exam.header.subject}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      Text(
                        'التاريخ: ${_exam.header.examDate}',
                        style: const TextStyle(fontSize: 10),
                      ),
                      Text(
                        'الزمن: ${_exam.header.examTime}',
                        style: const TextStyle(fontSize: 9.5),
                      ),
                      Text(
                        'الفتره: ${_exam.header.period}',
                        style: const TextStyle(fontSize: 9.5),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 2),

          // شريط التوجيه
          Row(
            children: [
              SizedBox(
                width: _questionColWidth,
                child: const Text('السؤال',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              Expanded(
                child: Text(
                  _exam.header.instructionText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 11),
                ),
              ),
              SizedBox(
                width: _markColWidth,
                child: const Text('الدرجه',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsTable() {
    if (_exam.questions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: const Text('لا توجد أسئلة، اضغط على زر إضافة سؤال بالأسفل'),
      );
    }

    return Table(
      border: TableBorder.all(color: Colors.black, width: 1),
      columnWidths: {
        0: FixedColumnWidth(_questionColWidth),
        1: const FlexColumnWidth(),
        2: FixedColumnWidth(_markColWidth),
      },
      children: _exam.questions.asMap().entries.map((entry) {
        final index = entry.key;
        final q = entry.value;

        Widget titleWidget = Text(
          q.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        );

        if (q.titleOrientation == QuestionTitleOrientation.verticalBottomToTop) {
          titleWidget = RotatedBox(quarterTurns: 3, child: titleWidget);
        } else if (q.titleOrientation ==
            QuestionTitleOrientation.verticalTopToBottom) {
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
                              fontFamily: s.fontFamily == 'Amiri' ? 'Amiri' : null,
                              fontWeight:
                                  s.isBold ? FontWeight.bold : FontWeight.normal,
                              decoration: s.isUnderline
                                  ? TextDecoration.underline
                                  : TextDecoration.none,
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
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }).toList(),
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

    String selectedFont = 'Amiri';
    double selectedFontSize = 14.0;
    bool isBold = false;
    bool isUnderline = false;

    final List<String> availableFonts = ['Amiri', 'Traditional Arabic', 'Arial'];
    final List<double> availableSizes = [12.0, 14.0, 16.0, 18.0, 20.0, 22.0];

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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 14,
            right: 14,
            top: 14,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(isEdit ? 'تعديل السؤال' : 'إضافة سؤال جديد',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                          controller: titleCtrl,
                          decoration:
                              const InputDecoration(labelText: 'اسم السؤال (س١)')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                          controller: markCtrl,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'الدرجة')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('اتجاه كتابة اسم السؤال:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('أفقي'),
                      selected:
                          orientation == QuestionTitleOrientation.horizontal,
                      onSelected: (val) => setModalState(
                          () => orientation = QuestionTitleOrientation.horizontal),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('رأسي (يمين ◄)'),
                      selected: orientation ==
                          QuestionTitleOrientation.verticalBottomToTop,
                      onSelected: (val) => setModalState(() => orientation =
                          QuestionTitleOrientation.verticalBottomToTop),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('رأسي (يسار ►)'),
                      selected: orientation ==
                          QuestionTitleOrientation.verticalTopToBottom,
                      onSelected: (val) => setModalState(() => orientation =
                          QuestionTitleOrientation.verticalTopToBottom),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      DropdownButton<String>(
                        value: selectedFont,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.font_download_outlined, size: 18),
                        items: availableFonts.map((f) {
                          return DropdownMenuItem(
                            value: f,
                            child: Text(f,
                                style: TextStyle(
                                    fontFamily: f == 'Amiri' ? 'Amiri' : null,
                                    fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedFont = val;
                              applyFormatToSelection(font: val);
                            });
                          }
                        },
                      ),
                      DropdownButton<double>(
                        value: selectedFontSize,
                        underline: const SizedBox(),
                        icon: const Icon(Icons.format_size, size: 18),
                        items: availableSizes.map((s) {
                          return DropdownMenuItem(
                            value: s,
                            child: Text('${s.toInt()} نقطة',
                                style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() {
                              selectedFontSize = val;
                              applyFormatToSelection(size: val);
                            });
                          }
                        },
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.format_bold,
                                color: isBold ? Colors.blue : Colors.black87),
                            tooltip: 'تطبيق خط عريض على المحدد',
                            onPressed: () {
                              setModalState(() {
                                isBold = !isBold;
                                applyFormatToSelection(bold: isBold);
                              });
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.format_underlined,
                                color: isUnderline ? Colors.blue : Colors.black87),
                            tooltip: 'تطبيق تسطير على المحدد',
                            onPressed: () {
                              setModalState(() {
                                isUnderline = !isUnderline;
                                applyFormatToSelection(underline: isUnderline);
                              });
                            },
                          ),
                          ElevatedButton(
                            onPressed: () => _insertTatweel(textCtrl),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(40, 32),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            child: const Text('ـ كشيدة'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                TextField(
                  controller: textCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'محتوى نص السؤال (حدد جزءاً لتنسيقه مستقلاً)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.add_photo_alternate, size: 18),
                        label: const Text('إدراج صورة',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                          final img = await _picker.pickImage(
                              source: ImageSource.gallery);
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
                      TextButton.icon(
                        icon: const Icon(Icons.text_fields, size: 18),
                        label: const Text('مربع إرشاد',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () {
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
                      TextButton.icon(
                        icon: const Icon(Icons.more_horiz, size: 18),
                        label: const Text('سطر إجابة',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () {
                          setModalState(() {
                            currentElements.add(InsertableElement(
                              id: const Uuid().v4(),
                              type: ElementType.dottedLine,
                              content:
                                  '......................................................................',
                            ));
                          });
                        },
                      ),
                    ],
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
                            workingSpans.map((s) => s.text).join('') ==
                                textCtrl.text
                        ? workingSpans
                        : [
                            TextSpanModel(
                              text: textCtrl.text,
                              isBold: isBold,
                              isUnderline: isUnderline,
                              fontSize: selectedFontSize,
                              fontFamily: selectedFont,
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

  void _showTextBoxEntryDialog(
      BuildContext context, Function(String) onConfirm) {
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
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
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
    final singleCtrl =
        TextEditingController(text: _exam.header.singlePageFooterText);
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
                    decoration: const InputDecoration(
                        labelText: 'عبارة المتابعة للورقة التالية'),
                  )
                else
                  TextField(
                    controller: singleCtrl,
                    decoration:
                        const InputDecoration(labelText: 'عبارة ختام الامتحان'),
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
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل الحقول الإدارية (اليمين)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cCountry,
                decoration: const InputDecoration(labelText: 'اسم الدولة'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cMinistry,
                decoration: const InputDecoration(labelText: 'اسم الوزارة'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cGov,
                decoration: const InputDecoration(labelText: 'اسم مكتب المحافظة'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cDir,
                decoration: const InputDecoration(labelText: 'اسم إدارة المديرية'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cSchool,
                decoration: const InputDecoration(labelText: 'اسم المدرسة'),
              ),
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
              });
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _editExamDetailsDialog() {
    final cGrade = TextEditingController(text: _exam.header.grade);
    final cSub = TextEditingController(text: _exam.header.subject);
    final cDate = TextEditingController(text: _exam.header.examDate);
    final cTime = TextEditingController(text: _exam.header.examTime);
    final cPeriod = TextEditingController(text: _exam.header.period);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات الامتحان (اليسار)'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cGrade,
                decoration: const InputDecoration(labelText: 'اسم الصف'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cSub,
                decoration: const InputDecoration(labelText: 'اسم المادة'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cDate,
                decoration: const InputDecoration(labelText: 'التاريخ'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cTime,
                decoration: const InputDecoration(labelText: 'الزمن'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: cPeriod,
                decoration: const InputDecoration(labelText: 'الفترة'),
              ),
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
              });
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _editExamTitleDialog() {
    final cTitle = TextEditingController(text: _exam.header.examTitle);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل عنوان الاختبار الرئيسي'),
        content: TextField(controller: cTitle),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              setState(() => _exam.header.examTitle = cTitle.text);
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

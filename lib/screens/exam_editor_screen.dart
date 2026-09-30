import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/exam_models.dart';
import '../utils/save_dialog_helper.dart';
import '../services/docx_generator_service.dart';
import '../services/exam_storage_service.dart';

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

  // نسب عرض خانات الترويسة الثلاث (يمين، وسط، يسار) مع حرية التحكم بها
  int _rightHeaderFlex = 4;
  int _centerHeaderFlex = 3;
  int _leftHeaderFlex = 4;

  // عرض أعمدة السؤال والدرجة
  double _questionColWidth = 40.0;
  double _markColWidth = 40.0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD6D9E0), // خلفية مكتبية تبرز حدود ورقة A4
      appBar: AppBar(
        title: Text(_isNew ? 'اختبار جديد' : _exam.fileName,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            tooltip: 'تصدير وفتح في تطبيق Office',
            onPressed: _exportAndOpenOffice,
          ),
          IconButton(
            icon: const Icon(Icons.view_column, color: Colors.white),
            tooltip: 'توزيع عرض خانات الترويسة والأعمدة',
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
              // حاوية ورقة A4 الحقيقية
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

  // --- واجهة الترويسة المعدلة مع الصف الناقص والنسب القابلة للتحرير ---
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
              // 1. الترويسة اليمنى (بـ 6 صفوف مكتملة)
              Expanded(
                flex: _rightHeaderFlex,
                child: InkWell(
                  onTap: _editAdminHeaderDialog,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(_exam.header.country,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11)),
                      Text(_exam.header.ministry,
                          style: const TextStyle(fontSize: 9.5)),
                      // الصف المضاف لوزارة التربية أو قطاع التعليم
                      Text(
                          _exam.header.directorate.isNotEmpty
                              ? 'قطاع المناهج والتوجيه'
                              : 'وزارة التربية والتعليم والبحث العلمي',
                          style: const TextStyle(fontSize: 9)),
                      Text('مكتب التربية والتعليم بمحافظة ${_exam.header.governorate}',
                          style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                      Text('إدارة التربية والتعليم بمديرية ${_exam.header.directorate}',
                          style: const TextStyle(fontSize: 9), textAlign: TextAlign.center),
                      Text('مدرسة: ${_exam.header.school}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 9.5),
                          textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),

              // 2. الترويسة الوسطى (البسملة والشعار مع ضبط التوسيط الفاصل)
              Expanded(
                flex: _centerHeaderFlex,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_exam.header.basmalaText,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 11),
                        textAlign: TextAlign.center),
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

              // 3. الترويسة اليسرى
              Expanded(
                flex: _leftHeaderFlex,
                child: InkWell(
                  onTap: _editExamDetailsDialog,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الصف : ${_exam.header.grade}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11)),
                      Text('الماده : ${_exam.header.subject}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 11)),
                      Text('التاريخ: ${_exam.header.examDate}',
                          style: const TextStyle(fontSize: 10)),
                      Text(
                          'الزمن: ${_exam.header.examTime}  الفتره (${_exam.header.period})',
                          style: const TextStyle(fontSize: 9)),
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

          // شريط التوجيه الثلاثي بمقاسات الأعمدة المصغرة الجديدة
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

  // --- جدول الأسئلة مع تصغير الأعمدة الجانبية ---
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
        0: FixedColumnWidth(_questionColWidth), // عمود السؤال المصغر
        1: const FlexColumnWidth(),            // عمود المحتوى المتسع
        2: FixedColumnWidth(_markColWidth),     // عمود الدرجة المصغر
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
            // 1. عمود اسم السؤال
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

            // 2. عمود محتوى السؤال المتسع
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

            // 3. عمود الدرجة
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

  // --- نافذة ضبط نسب الترويسة وأبعاد الأعمدة الحرة ---
  void _openHeaderFlexSettingsDialog() {
    int rFlex = _rightHeaderFlex;
    int cFlex = _centerHeaderFlex;
    int lFlex = _leftHeaderFlex;
    double qWidth = _questionColWidth;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('أبعاد خانات الترويسة والجدول'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('نسب توزيع مساحة الترويسة (يمين - وسط - يسار):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('اليمين', style: TextStyle(fontSize: 11)),
                          Slider(
                            value: rFlex.toDouble(),
                            min: 2,
                            max: 6,
                            divisions: 4,
                            label: '$rFlex',
                            onChanged: (v) => setDlgState(() => rFlex = v.toInt()),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('الوسط', style: TextStyle(fontSize: 11)),
                          Slider(
                            value: cFlex.toDouble(),
                            min: 2,
                            max: 5,
                            divisions: 3,
                            label: '$cFlex',
                            onChanged: (v) => setDlgState(() => cFlex = v.toInt()),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('اليسار', style: TextStyle(fontSize: 11)),
                          Slider(
                            value: lFlex.toDouble(),
                            min: 2,
                            max: 6,
                            divisions: 4,
                            label: '$lFlex',
                            onChanged: (v) => setDlgState(() => lFlex = v.toInt()),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(),
                const Text('عرض عمودي (السؤال) و(الدرجة):',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Slider(
                  value: qWidth,
                  min: 30,
                  max: 60,
                  divisions: 6,
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
                  _rightHeaderFlex = rFlex;
                  _centerHeaderFlex = cFlex;
                  _leftHeaderFlex = lFlex;
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

    String selectedFont = q.spans.isNotEmpty ? q.spans.first.fontFamily : 'Amiri';
    double selectedFontSize = q.spans.isNotEmpty ? q.spans.first.fontSize : 14.0;
    bool isBold = q.spans.isNotEmpty ? q.spans.first.isBold : false;
    bool isUnderline = q.spans.isNotEmpty ? q.spans.first.isUnderline : false;

    final List<String> availableFonts = ['Amiri', 'Traditional Arabic', 'Arial'];
    final List<double> availableSizes = [12.0, 14.0, 16.0, 18.0, 20.0, 22.0];

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
                          if (val != null) setModalState(() => selectedFont = val);
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
                          if (val != null) setModalState(() => selectedFontSize = val);
                        },
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.format_bold,
                                color: isBold ? Colors.blue : Colors.black87),
                            tooltip: 'خط عريض',
                            onPressed: () => setModalState(() => isBold = !isBold),
                          ),
                          IconButton(
                            icon: Icon(Icons.format_underlined,
                                color: isUnderline ? Colors.blue : Colors.black87),
                            tooltip: 'تسطير',
                            onPressed: () =>
                                setModalState(() => isUnderline = !isUnderline),
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
                  style: TextStyle(
                    fontFamily: selectedFont == 'Amiri' ? 'Amiri' : null,
                    fontSize: selectedFontSize,
                    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                    decoration: isUnderline
                        ? TextDecoration.underline
                        : TextDecoration.none,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'محتوى نص السؤال (معاينة حية للتنسيق)',
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
                    final newSpans = [
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
                      spans: newSpans,
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

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات المدرسة والإدارة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: cCountry, decoration: const InputDecoration(labelText: 'الدولة')),
            TextField(controller: cGov, decoration: const InputDecoration(labelText: 'المحافظة')),
            TextField(controller: cDir, decoration: const InputDecoration(labelText: 'المديرية')),
            TextField(controller: cSchool, decoration: const InputDecoration(labelText: 'المدرسة')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _exam.header.country = cCountry.text;
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
        title: const Text('تعديل بيانات المادة والزمن'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: cGrade, decoration: const InputDecoration(labelText: 'الصف')),
            TextField(controller: cSub, decoration: const InputDecoration(labelText: 'المادة')),
            TextField(controller: cDate, decoration: const InputDecoration(labelText: 'التاريخ')),
            TextField(controller: cTime, decoration: const InputDecoration(labelText: 'الزمن')),
            TextField(controller: cPeriod, decoration: const InputDecoration(labelText: 'الفترة')),
          ],
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

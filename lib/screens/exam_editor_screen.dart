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

  // أدوات التنسيق النشطة
  bool _isBoldActive = false;
  bool _isUnderlineActive = false;
  double _currentFontSize = 14.0;
  String _currentFontFamily = 'Traditional Arabic';

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _exam = widget.initialExam;
    _isNew = widget.isNewExam;
  }

  // مد الحرف (الكشيدة)
  void _insertTatweel(TextEditingController controller) {
    final pos = controller.selection.start;
    const tatweel = '\u0640';
    if (pos >= 0) {
      controller.text = controller.text.replaceRange(pos, controller.selection.end, tatweel);
      controller.selection = TextSelection.collapsed(offset: pos + 1);
    } else {
      controller.text += tatweel;
    }
  }

  // اختيار شعار المدرسة
  Future<void> _pickLogoImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _exam.header.logoImagePath = image.path;
      });
    }
  }

  // حفظ الاختبار
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

  // تصدير وفتح ملف Word مباشرة
  Future<void> _exportAndOpenOffice() async {
    await ExamStorageService.saveOrUpdateExam(_exam);
    await DocxGeneratorService.generateAndOpenDocx(_exam);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'اختبار جديد' : _exam.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.print, color: Colors.blueGrey),
            tooltip: 'تصدير وفتح في تطبيق Office',
            onPressed: _exportAndOpenOffice,
          ),
          IconButton(
            icon: const Icon(Icons.tune, color: Colors.orange),
            tooltip: 'خيارات التذييل والهوامش',
            onPressed: _openFooterSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.save, color: Colors.blueAccent, size: 28),
            tooltip: 'حفظ',
            onPressed: _triggerSave,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            // الترويسة المعتمدة
            _buildExamHeader(),
            const SizedBox(height: 12),

            // قائمة الأسئلة بالتقسيم الثلاثي
            _buildQuestionsTable(),
            const SizedBox(height: 12),

            // التذييل الملتصق بآخر سؤال
            _buildFooterPreview(),
          ],
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

  // --- واجهة الترويسة ---
  Widget _buildExamHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // اليمين
              Expanded(
                flex: 4,
                child: InkWell(
                  onTap: _editAdminHeaderDialog,
                  child: Column(
                    children: [
                      Text(_exam.header.country, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(_exam.header.ministry, style: const TextStyle(fontSize: 10)),
                      Text(_exam.header.governorate, style: const TextStyle(fontSize: 10)),
                      Text(_exam.header.directorate, style: const TextStyle(fontSize: 10)),
                      Text(_exam.header.school, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
                    ],
                  ),
                ),
              ),
              // الوسط
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    Text(_exam.header.basmalaText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), textAlign: TextAlign.center),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _pickLogoImage,
                      child: _exam.header.logoImagePath != null
                          ? Image.file(File(_exam.header.logoImagePath!), height: 48, fit: BoxFit.contain)
                          : Container(
                              height: 48,
                              width: 48,
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                              child: const Icon(Icons.add_photo_alternate, size: 24, color: Colors.grey),
                            ),
                    ),
                  ],
                ),
              ),
              // اليسار
              Expanded(
                flex: 4,
                child: InkWell(
                  onTap: _editExamDetailsDialog,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الصف : ${_exam.header.grade}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      Text('الماده : ${_exam.header.subject}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                      Text('التاريخ: ${_exam.header.examDate}', style: const TextStyle(fontSize: 10)),
                      Text('الزمن: ${_exam.header.examTime}  الفتره (${_exam.header.period})', style: const TextStyle(fontSize: 9)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // عنوان الامتحان
          InkWell(
            onTap: _editExamTitleDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: Colors.grey.shade200,
              child: Text(
                _exam.header.examTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // شريط التوجيه الثلاثي
          Row(
            children: [
              Container(
                width: 60,
                alignment: Alignment.center,
                child: const Text('السؤال', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
              Expanded(
                child: Text(
                  _exam.header.instructionText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
              Container(
                width: 60,
                alignment: Alignment.center,
                child: const Text('الدرجه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- جدول الأسئلة بالتقسيم الثلاثي الدقيق وتدوير الاسم ---
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
      columnWidths: const {
        0: FixedColumnWidth(60), // خانة اسم السؤال
        1: FlexColumnWidth(),    // خانة محتوى السؤال
        2: FixedColumnWidth(60), // خانة الدرجة
      },
      children: _exam.questions.asMap().entries.map((entry) {
        final index = entry.key;
        final q = entry.value;

        // تدوير اسم السؤال بحسب الخيار المحدد
        Widget titleWidget = Text(
          q.title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        );

        if (q.titleOrientation == QuestionTitleOrientation.verticalBottomToTop) {
          titleWidget = RotatedBox(quarterTurns: 3, child: titleWidget);
        } else if (q.titleOrientation == QuestionTitleOrientation.verticalTopToBottom) {
          titleWidget = RotatedBox(quarterTurns: 1, child: titleWidget);
        }

        return TableRow(
          children: [
            // 1. خانة اسم السؤال وتدويره
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: InkWell(
                onTap: () => _openQuestionDialog(questionIndex: index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: titleWidget),
                ),
              ),
            ),

            // 2. خانة محتوى السؤال
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: InkWell(
                onTap: () => _openQuestionDialog(questionIndex: index),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    children: q.spans.map((s) {
                      return Text(
                        s.text,
                        style: TextStyle(
                          fontWeight: s.isBold ? FontWeight.bold : FontWeight.normal,
                          decoration: s.isUnderline ? TextDecoration.underline : TextDecoration.none,
                          fontSize: s.fontSize,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),

            // 3. خانة الدرجة
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: InkWell(
                onTap: () => _openQuestionDialog(questionIndex: index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Text(
                      q.mark > 0 ? '${q.mark} د' : '-',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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

  // --- تذييل الورقة الملتصق بالأسئلة ---
  Widget _buildFooterPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          Text(
            _exam.header.isMultiPage
                ? _exam.header.continuationText
                : _exam.header.singlePageFooterText,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              _exam.header.teacherSignature,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // --- نافذة كتابة وتنسيق وتدوير السؤال ---
  void _openQuestionDialog({int? questionIndex}) {
    final bool isEdit = questionIndex != null;
    final q = isEdit
        ? _exam.questions[questionIndex]
        : QuestionModel(
            id: const Uuid().v4(),
            title: 'السؤال ${_exam.questions.length + 1}',
            spans: [],
          );

    final titleCtrl = TextEditingController(text: q.title);
    final textCtrl = TextEditingController(text: q.spans.map((e) => e.text).join(''));
    final markCtrl = TextEditingController(text: q.mark > 0 ? q.mark.toString() : '5');
    QuestionTitleOrientation orientation = q.titleOrientation;

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
                Text(isEdit ? 'تعديل السؤال' : 'إضافة سؤال جديد', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'اسم السؤال (س١)')),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(controller: markCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الدرجة')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // أزرار تدوير اسم السؤال
                const Text('اتجاه كتابة اسم السؤال:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('أفقي'),
                      selected: orientation == QuestionTitleOrientation.horizontal,
                      onSelected: (val) => setModalState(() => orientation = QuestionTitleOrientation.horizontal),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('رأسي (يمين ◄)'),
                      selected: orientation == QuestionTitleOrientation.verticalBottomToTop,
                      onSelected: (val) => setModalState(() => orientation = QuestionTitleOrientation.verticalBottomToTop),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('رأسي (يسار ►)'),
                      selected: orientation == QuestionTitleOrientation.verticalTopToBottom,
                      onSelected: (val) => setModalState(() => orientation = QuestionTitleOrientation.verticalTopToBottom),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // شريط التنسيق (كشيدة، تسطير، تفخيم)
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () => _insertTatweel(textCtrl),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(44, 36)),
                      child: const Text('ـ كشيدة'),
                    ),
                    IconButton(
                      icon: Icon(Icons.format_bold, color: _isBoldActive ? Colors.blue : Colors.black),
                      onPressed: () => setModalState(() => _isBoldActive = !_isBoldActive),
                    ),
                    IconButton(
                      icon: Icon(Icons.format_underlined, color: _isUnderlineActive ? Colors.blue : Colors.black),
                      onPressed: () => setModalState(() => _isUnderlineActive = !_isUnderlineActive),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                TextField(
                  controller: textCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'محتوى السؤال',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),

                ElevatedButton(
                  onPressed: () {
                    final newSpans = [
                      TextSpanModel(
                        text: textCtrl.text,
                        isBold: _isBoldActive,
                        isUnderline: _isUnderlineActive,
                        fontSize: _currentFontSize,
                        fontFamily: _currentFontFamily,
                      )
                    ];

                    final newQ = QuestionModel(
                      id: q.id,
                      title: titleCtrl.text,
                      titleOrientation: orientation,
                      mark: double.tryParse(markCtrl.text) ?? 0.0,
                      spans: newSpans,
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
                  child: const Text('تأكيد السؤال'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- نافذة إعدادات التذييل والهوامش ---
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

  // نوافذ التعديل السريع للترويسة
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

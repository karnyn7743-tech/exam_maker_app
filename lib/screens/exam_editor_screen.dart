import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/exam_models.dart';
import '../utils/save_dialog_helper.dart';

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

  // للتحكم في السؤال الجاري تحريره حالياً
  final TextEditingController _questionTextController = TextEditingController();
  final FocusNode _questionFocusNode = FocusNode();
  int? _editingQuestionIndex;

  // خيارات التنسيق للكلمة أو المقطع المحدد
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

  @override
  void dispose() {
    _questionTextController.dispose();
    _questionFocusNode.dispose();
    super.dispose();
  }

  // --- دالة إضافة الكشيدة (مد الحرف) مثل الحاسوب ---
  void _insertTatweel() {
    final text = _questionTextController.text;
    final selection = _questionTextController.selection;
    const tatweelChar = '\u0640'; // المحرف المعتمد للمد العربي

    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, tatweelChar);
      _questionTextController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + tatweelChar.length),
      );
    } else {
      _questionTextController.text += tatweelChar;
    }
  }

  // --- حفظ أو تعديل مقطع في السؤال الحالي ---
  void _applyFormattingToSelection({bool? toggleBold, bool? toggleUnderline, double? fontSizeDelta, String? fontFamily}) {
    setState(() {
      if (toggleBold != null) _isBoldActive = !_isBoldActive;
      if (toggleUnderline != null) _isUnderlineActive = !_isUnderlineActive;
      if (fontSizeDelta != null) {
        _currentFontSize = (_currentFontSize + fontSizeDelta).clamp(10.0, 26.0);
      }
      if (fontFamily != null) _currentFontFamily = fontFamily;
    });
  }

  // اختيار صورة الشعار من المعرض
  Future<void> _pickLogoImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _exam.header.logoImagePath = image.path;
      });
    }
  }

  // حفظ الاختبار باستخدام مساعد الحفظ الذكي
  Future<void> _triggerSave() async {
    final saved = await showSaveChoiceDialog(
      context: context,
      currentExam: _exam,
      isNewExam: _isNew,
      onPerformSave: (updated) {
        setState(() {
          _exam = updated;
          _isNew = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ الملف بنجاح: ${_exam.fileName}'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      },
    );

    if (saved && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'اختبار جديد' : _exam.fileName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.save, color: Colors.blueAccent, size: 28),
            tooltip: 'حفظ الاختبار',
            onPressed: _triggerSave,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // 1. الترويسة المعتمدة المطابقة للنموذج
                  _buildExamHeader(),
                  const SizedBox(height: 16),

                  // 2. قائمة الأسئلة الحالية
                  _buildQuestionsList(),
                ],
              ),
            ),
          ),

          // 3. شريط التنسيق العائم وأداة مد الحروف الملتحقة بالكيبورد
          if (_editingQuestionIndex != null || _questionFocusNode.hasFocus)
            _buildFormattingToolbar(),
        ],
      ),
      bottomNavigationBar: _buildBottomActionBar(),
    );
  }

  // --- بناء واجهة الترويسة المطابقة للصورة ---
  Widget _buildExamHeader() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2), // إطار خارجي مزدوج النمط
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 1),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            // الصف العلوي (3 أقسام: إدارة، شعار وبسملة، معلومات مادة)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الجانب الأيمن: الجهة الإدارية
                Expanded(
                  flex: 4,
                  child: InkWell(
                    onTap: () => _editAdminHeaderDialog(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(_exam.header.country, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(_exam.header.ministry, style: const TextStyle(fontSize: 11)),
                        Text(_exam.header.governorate, style: const TextStyle(fontSize: 11)),
                        Text(_exam.header.directorate, style: const TextStyle(fontSize: 11)),
                        Text(_exam.header.school, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11)),
                      ],
                    ),
                  ),
                ),

                // الجانب الأوسط: البسملة والشعار
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Text(
                        _exam.header.basmalaText,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _pickLogoImage,
                        child: _exam.header.logoImagePath != null
                            ? Image.file(
                                File(_exam.header.logoImagePath!),
                                height: 50,
                                fit: BoxFit.contain,
                              )
                            : Container(
                                height: 50,
                                width: 50,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade400),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_photo_alternate, size: 24, color: Colors.grey),
                                    Text('الشعار', style: TextStyle(fontSize: 9, color: Colors.grey)),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

                // الجانب الأيسر: بيانات الاختبار
                Expanded(
                  flex: 4,
                  child: InkWell(
                    onTap: () => _editExamDetailsDialog(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الصف : ${_exam.header.grade}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text('الماده : ${_exam.header.subject}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        Text('التاريخ : ${_exam.header.examDate}', style: const TextStyle(fontSize: 11)),
                        Text('الزمن: ${_exam.header.examTime}  الفتره (${_exam.header.period})', style: const TextStyle(fontSize: 10)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // الشريط الأوسط العريض: عنوان الاختبار
            InkWell(
              onTap: () => _editExamTitleDialog(),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black, width: 1.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _exam.header.examTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 4),

            // شريط التوجيه (السؤال | أجب مستعيناً بالله | الدرجة)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 50,
                    child: Text('السؤال', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                  Container(width: 1, height: 24, color: Colors.black),
                  Expanded(
                    child: Text(
                      _exam.header.instructionText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  Container(width: 1, height: 24, color: Colors.black),
                  const SizedBox(
                    width: 50,
                    child: Text('الدرجه', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- شريط الأدوات العائم فوق الكيبورد (الكشيدة والتنسيقات) ---
  Widget _buildFormattingToolbar() {
    return Container(
      color: Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // زر مد الحرف (الكشيدة مثل الحاسوب)
            ElevatedButton(
              onPressed: _insertTatweel,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                minimumSize: const Size(48, 38),
                padding: EdgeInsets.zero,
              ),
              child: const Text('ـ مد', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 6),

            // زر التفخيم B
            IconButton(
              icon: Icon(Icons.format_bold, color: _isBoldActive ? Colors.blue : Colors.black),
              onPressed: () => _applyFormattingToSelection(toggleBold: true),
            ),

            // زر التسطير U
            IconButton(
              icon: Icon(Icons.format_underlined, color: _isUnderlineActive ? Colors.blue : Colors.black),
              onPressed: () => _applyFormattingToSelection(toggleUnderline: true),
            ),

            const VerticalDivider(width: 16, color: Colors.grey),

            // تكبير الخط A+
            IconButton(
              icon: const Icon(Icons.text_increase),
              onPressed: () => _applyFormattingToSelection(fontSizeDelta: 1.0),
            ),

            // تصغير الخط A-
            IconButton(
              icon: const Icon(Icons.text_decrease),
              onPressed: () => _applyFormattingToSelection(fontSizeDelta: -1.0),
            ),

            Text('${_currentFontSize.toInt()} pt', style: const TextStyle(fontSize: 12)),

            const VerticalDivider(width: 16, color: Colors.grey),

            // نوع الخط
            DropdownButton<String>(
              value: _currentFontFamily,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'Traditional Arabic', child: Text('Traditional Arabic')),
                DropdownMenuItem(value: 'Amiri', child: Text('Amiri')),
                DropdownMenuItem(value: 'Simplified Arabic', child: Text('Simplified Arabic')),
              ],
              onChanged: (val) {
                if (val != null) _applyFormattingToSelection(fontFamily: val);
              },
            ),
          ],
        ),
      ),
    );
  }

  // --- قائمة الأسئلة الحالية ---
  Widget _buildQuestionsList() {
    if (_exam.questions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'لم يتم إضافة أي أسئلة بعد.\nاضغط على (+ إضافة سؤال) بالأسفل.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _exam.questions.length,
      itemBuilder: (context, index) {
        final q = _exam.questions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          elevation: 1,
          child: ListTile(
            title: Text(
              q.title.isNotEmpty ? q.title : 'سؤال ${index + 1}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Wrap(
              children: q.spans.map((span) {
                return Text(
                  span.text,
                  style: TextStyle(
                    fontWeight: span.isBold ? FontWeight.bold : FontWeight.normal,
                    decoration: span.isUnderline ? TextDecoration.underline : TextDecoration.none,
                    fontSize: span.fontSize,
                  ),
                );
              }).toList(),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${q.mark} درجات', style: const TextStyle(color: Colors.blueGrey)),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 20),
                  onPressed: () {
                    setState(() {
                      _exam.questions.removeAt(index);
                    });
                  },
                ),
              ],
            ),
            onTap: () => _openQuestionEditorDialog(questionIndex: index),
          ),
        );
      },
    );
  }

  // --- شريط الإجراءات السفلي ---
  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('إضافة سؤال جديد'),
              onPressed: () => _openQuestionEditorDialog(),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'المجموع: ${_exam.totalMarks} د',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  // --- مربعات الحوار لتعديل نصوص الترويسة بنقرة واحدة ---
  void _editAdminHeaderDialog() {
    final cCountry = TextEditingController(text: _exam.header.country);
    final cMinistry = TextEditingController(text: _exam.header.ministry);
    final cGov = TextEditingController(text: _exam.header.governorate);
    final cDir = TextEditingController(text: _exam.header.directorate);
    final cSchool = TextEditingController(text: _exam.header.school);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات الجهة الإدارية'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: cCountry, decoration: const InputDecoration(labelText: 'الدولة')),
              TextField(controller: cMinistry, decoration: const InputDecoration(labelText: 'الوزارة')),
              TextField(controller: cGov, decoration: const InputDecoration(labelText: 'المحافظة')),
              TextField(controller: cDir, decoration: const InputDecoration(labelText: 'المديرية')),
              TextField(controller: cSchool, decoration: const InputDecoration(labelText: 'المدرسة')),
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
        title: const Text('تعديل تفاصيل المادة والزمن'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: cGrade, decoration: const InputDecoration(labelText: 'الصف')),
              TextField(controller: cSub, decoration: const InputDecoration(labelText: 'المادة')),
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
        content: TextField(controller: cTitle, decoration: const InputDecoration(labelText: 'العنوان')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _exam.header.examTitle = cTitle.text;
              });
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  // --- نافذة كتابة وتنسيق السؤال الجديد ---
  void _openQuestionEditorDialog({int? questionIndex}) {
    final bool isEdit = questionIndex != null;
    QuestionModel q = isEdit
        ? _exam.questions[questionIndex]
        : QuestionModel(
            id: const Uuid().v4(),
            title: 'السؤال ${_exam.questions.length + 1}',
            spans: [],
          );

    final titleCtrl = TextEditingController(text: q.title);
    final textCtrl = TextEditingController(text: q.spans.map((e) => e.text).join(''));
    final markCtrl = TextEditingController(text: q.mark > 0 ? q.mark.toString() : '5');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isEdit ? 'تعديل السؤال' : 'إضافة سؤال جديد', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'عنوان السؤال (مثل: السؤال الأول)')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(controller: markCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'الدرجة')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: textCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'نص السؤال',
                hintText: 'اكتب نص السؤال هنا واستخدم الكشيدة إن أردت...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // زر مد الحرف داخل المودال أيضاً
                OutlinedButton.icon(
                  icon: const Icon(Icons.text_fields),
                  label: const Text('ـ كشيدة'),
                  onPressed: () {
                    final pos = textCtrl.selection.start;
                    if (pos >= 0) {
                      textCtrl.text = textCtrl.text.replaceRange(pos, textCtrl.selection.end, '\u0640');
                    } else {
                      textCtrl.text += '\u0640';
                    }
                  },
                ),
                ElevatedButton(
                  onPressed: () {
                    final spans = [
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
                      mark: double.tryParse(markCtrl.text) ?? 0.0,
                      spans: spans,
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
                  child: const Text('حفظ السؤال'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

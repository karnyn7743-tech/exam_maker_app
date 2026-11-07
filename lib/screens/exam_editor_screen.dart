import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../models/exam_models.dart';
import '../utils/save_dialog_helper.dart';
import '../services/exam_storage_service.dart';
import '../services/pdf_export_service.dart';
import '../services/exam_share_service.dart';
import '../services/student_excel_service.dart';
import '../services/omr_sheet_service.dart';
import '../services/question_bank_service.dart';
import '../services/direct_print_service.dart';
import 'omr_scanner_screen.dart';
import '../widgets/exam_custom_keyboard.dart';
import '../widgets/exam_ribbon_toolbar.dart';

typedef FontItem = Map<String, String>;

const List<FontItem> appFontsList = [
  {'id': 'Amiri', 'name': 'خط الأميري (الافتراضي)'},
  {'id': 'Hafs', 'name': 'مصحف حفص (عثماني)'},
  {'id': 'Thuluth', 'name': 'خط الثلث'},
  {'id': 'Almarai', 'name': 'المراعي'},
  {'id': 'Changa', 'name': 'تشانجا'},
  {'id': 'Kufam', 'name': 'كوفام'},
  {'id': 'Rubik', 'name': 'روبيك'},
  {'id': 'Arial', 'name': 'أريال (Arial)'},
];

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

  bool _showAnswerKeyMode = false;
  double _sideHeaderWidth = 145.0;
  double _questionColWidth = 38.0;
  double _markColWidth = 38.0;

  final ImagePicker _picker = ImagePicker();
  InsertableElement? _copiedElement;
  String? _selectedElementId;

  // الحالات النشطة للتنسيق والكتابة
  bool _isBold = false;
  bool _isUnderline = false;
  TextAlign _activeAlignment = TextAlign.right;
  String _activeColor = '#000000';
  String _activeFont = 'Amiri';
  double _activeFontSize = 14.0;
  bool _isArabicInput = true;

  @override
  void initState() {
    super.initState();
    _exam = widget.initialExam;
    _isNew = widget.isNewExam;
    _isArabicInput = _exam.isArabic;
    _activeAlignment = _exam.isArabic ? TextAlign.right : TextAlign.left;
    _activeFont = _exam.isArabic ? 'Amiri' : 'Arial';
  }

  bool get _isArabicExam => _exam.isArabic;

  void _toggleExamLanguage() {
    setState(() {
      _exam.isArabic = !_exam.isArabic;
      _isArabicInput = _exam.isArabic;
      _activeAlignment = _exam.isArabic ? TextAlign.right : TextAlign.left;
      _activeFont = _exam.isArabic ? 'Amiri' : 'Arial';
      if (!_exam.isArabic && _exam.header.examTitle == 'اختبار نهائي') {
        _exam.header.examTitle = 'Final Examination';
      } else if (_exam.isArabic && _exam.header.examTitle == 'Final Examination') {
        _exam.header.examTitle = 'اختبار نهائي';
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _exam.isArabic
              ? 'تم تحويل اتجاه ولغة الاختبار إلى العربية (RTL)'
              : 'Exam layout and language switched to English (LTR)',
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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

  Future<void> _pickLogoImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _exam.header.logoImagePath = image.path;
      });
    }
  }

  Future<void> _triggerSave() async {
    final gradeName = _exam.header.grade.trim().isNotEmpty ? _exam.header.grade.trim() : 'عام';
    final subjectName = _exam.header.subject.trim().isNotEmpty ? _exam.header.subject.trim() : 'مادة';
    final typeName = _exam.examType == ExamType.automated ? 'مؤتمت' : 'شامل';
    final langSuffix = _isArabicExam ? 'عربي' : 'En';
    final generatedName = '$gradeName _ $subjectName _ $typeName _ $langSuffix';

    if (_isNew || _exam.fileName.isEmpty || _exam.fileName.startsWith('اختبار_') || _exam.fileName == 'اختبار جديد') {
      _exam.fileName = generatedName;
    }

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

  Future<void> _exportExamProjectFile() async {
    await ExamStorageService.saveOrUpdateExam(_exam);
    try {
      final path = await ExamShareService.exportExamFile(_exam);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير ملف المشروع (.exam) بنجاح:\n$path'),
            backgroundColor: Colors.green.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تصدير ملف المشروع: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _exportPdfToDownloads() async {
    await ExamStorageService.saveOrUpdateExam(_exam);
    final isAnswerKey = await _showExportChoiceDialog('تصدير إلى PDF');
    if (isAnswerKey == null) return;

    try {
      final examToExport = isAnswerKey ? _buildAnswerKeyExam() : _exam;
      final path = await PdfExportService.exportToDownloadsPdf(examToExport);
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

  Future<void> _exportOmrSheetToDownloads() async {
    await ExamStorageService.saveOrUpdateExam(_exam);
    try {
      final path = await OmrSheetService.generateOmrPdf(_exam);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ ورقة التظليل (OMR) بنجاح في التنزيلات:\n$path'),
            backgroundColor: const Color(0xFF0F766E),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تصدير ورقة التظليل: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<bool?> _showExportChoiceDialog(String title) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text('يرجى تحديد نوع الوثيقة:'),
        actions: [
          OutlinedButton.icon(
            icon: const Icon(Icons.school_outlined),
            label: const Text('ورقة الاختبار (للطلاب)'),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
            icon: const Icon(Icons.verified, color: Colors.white),
            label: const Text('نموذج الإجابة (محلول)', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
  }

  ExamModel _buildAnswerKeyExam() {
    final keyExam = _exam.copyWith();
    final isAr = _isArabicExam;
    keyExam.header.examTitle = isAr
        ? '${_exam.header.examTitle} (نموذج الإجابة وتوزيع الدرجات)'
        : '${_exam.header.examTitle} (Model Answer Key)';
    keyExam.header.singlePageFooterText = isAr
        ? 'تم إعداد ومراجعة نموذج الإجابة من قبل لجنة الكنترول والتصحيح'
        : 'Exam Answer Key prepared and audited by Examination Control Committee';
    keyExam.header.teacherSignature = isAr
        ? 'المصحح / المراجع: ......................'
        : 'Examiner / Auditor: ......................';

    keyExam.questions = _exam.questions.map((q) {
      final newQ = QuestionModel.fromMap(q.toMap());
      if (newQ.answerKey.trim().isNotEmpty) {
        newQ.spans.add(TextSpanModel(
          text: isAr
              ? '\n[ الإجابة النموذجية: ${newQ.answerKey} ]'
              : '\n[ Model Answer: ${newQ.answerKey} ]',
          fontSize: 13.0,
          isBold: true,
          fontFamily: isAr ? 'Amiri' : 'Arial',
        ));
      }
      return newQ;
    }).toList();

    return keyExam;
  }

  void _generateAlternativeExamModel() {
    final gradeName = _exam.header.grade.trim().isNotEmpty ? _exam.header.grade.trim() : 'عام';
    final subjectName = _exam.header.subject.trim().isNotEmpty ? _exam.header.subject.trim() : 'مادة';
    final typeName = _exam.examType == ExamType.automated ? 'مؤتمت' : 'شامل';
    final suffix = _isArabicExam ? '(نموذج ب)' : '(Form B)';
    final defaultAltName = '$gradeName _ $subjectName _ $typeName $suffix';

    final ctrl = TextEditingController(text: defaultAltName);
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.alt_route, color: Color(0xFF1E3A8A)),
            SizedBox(width: 8),
            Text('توليد نموذج اختباري بديل (خلط آلي)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'سيقوم النظام بإنشاء نسخة جديدة من الاختبار مع خلط ترتيب فقرات الأسئلة تلقائياً لمنع الغش، مع الحفاظ التام على الدرجات ونموذج الإجابة.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                labelText: 'اسم ملف النموذج الجديد',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
            onPressed: () {
              final newExam = _exam.copyWith(
                newId: const Uuid().v4(),
                newFileName: ctrl.text.trim(),
              );
              newExam.header.examTitle = '${_exam.header.examTitle} - ' + (_isArabicExam ? '(ب)' : '(B)');

              newExam.questions = _exam.questions.map((q) {
                final copiedQ = QuestionModel.fromMap(q.toMap());
                final fullText = copiedQ.spans.map((s) => s.text).join('');
                final lines = fullText.split('\n');
                if (lines.length > 2) {
                  final headerLine = lines.first;
                  final bodyLines = lines.sublist(1)..shuffle();
                  copiedQ.spans = [
                    TextSpanModel(
                      text: '$headerLine\n${bodyLines.join('\n')}',
                      fontFamily: copiedQ.spans.isNotEmpty ? copiedQ.spans.first.fontFamily : (_isArabicExam ? 'Amiri' : 'Arial'),
                      fontSize: copiedQ.spans.isNotEmpty ? copiedQ.spans.first.fontSize : 14.0,
                    )
                  ];
                }
                return copiedQ;
              }).toList();

              setState(() {
                _exam = newExam;
                _isNew = true;
              });
              Navigator.pop(dCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('تم توليد (${ctrl.text.trim()}) بنجاح مع خلط الفقرات!'),
                  backgroundColor: Colors.green.shade800,
                ),
              );
            },
            child: const Text('توليد النموذج الآن', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMarkBalancingDialog() {
    final targetCtrl = TextEditingController(text: _exam.targetTotalMarks.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.scale, color: Color(0xFF1E3A8A)),
            SizedBox(width: 8),
            Text('ميزان الدرجات وتوزيعها الذكي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('مجموع درجات الأسئلة الحالية: ${_exam.totalMarks.toStringAsFixed(1)} د',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: targetCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الدرجة الكلية المعتمدة (المستهدفة)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
              icon: const Icon(Icons.auto_fix_high, color: Colors.white, size: 18),
              label: const Text('توزيع الدرجة الكلية بالتساوي على الأسئلة', style: TextStyle(color: Colors.white)),
              onPressed: () {
                final target = double.tryParse(targetCtrl.text) ?? _exam.targetTotalMarks;
                if (_exam.questions.isNotEmpty) {
                  final markPerQ = double.parse((target / _exam.questions.length).toStringAsFixed(2));
                  setState(() {
                    _exam.targetTotalMarks = target;
                    for (var q in _exam.questions) {
                      q.mark = markPerQ;
                    }
                  });
                  Navigator.pop(dCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('تم توزيع الدرجات بالتساوي: $markPerQ د لكل سؤال'), backgroundColor: Colors.teal.shade800),
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _exam.targetTotalMarks = double.tryParse(targetCtrl.text) ?? _exam.targetTotalMarks;
              });
              Navigator.pop(dCtx);
            },
            child: const Text('حفظ الميزان'),
          ),
        ],
      ),
    );
  }

  void _showQuestionBankImportDialog() async {
    final bankQuestions = await QuestionBankService.getAllQuestions();
    if (!mounted) return;

    if (bankQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('بنك الأسئلة فارغ حالياً. يمكنك حفظ أي سؤال في البنك من خلال نافذة تعديل السؤال.')),
      );
      return;
    }

    String filterSubject = 'الكل';
    final subjects = {'الكل', ...bankQuestions.map((e) => e.subject)};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (bCtx) => StatefulBuilder(
        builder: (context, setBState) {
          final filtered = filterSubject == 'الكل'
              ? bankQuestions
              : bankQuestions.where((e) => e.subject == filterSubject).toList();

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.85,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance, color: Color(0xFF1E3A8A)),
                      const SizedBox(width: 8),
                      const Text('بنك الأسئلة الشخصي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Spacer(),
                      DropdownButton<String>(
                        value: filterSubject,
                        items: subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (v) => setBState(() => filterSubject = v!),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = filtered[i];
                      final preview = item.question.spans.map((s) => s.text).join('').split('\n').first;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade50,
                          child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                        ),
                        title: Text(item.question.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(
                          '$preview\n[ ${item.subject} - ${item.grade} ] (الدرجة: ${item.question.mark} د)',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () async {
                            await QuestionBankService.deleteQuestion(item.id);
                            setBState(() => bankQuestions.removeWhere((q) => q.id == item.id));
                          },
                        ),
                        onTap: () {
                          final imported = QuestionModel.fromMap(item.question.toMap());
                          imported.title = _isArabicExam
                              ? 'السؤال ${_exam.questions.length + 1}'
                              : 'Question ${_exam.questions.length + 1}';
                          setState(() => _exam.questions.add(imported));
                          Navigator.pop(bCtx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم إدراج (${item.question.title}) بنجاح.'), backgroundColor: Colors.green.shade800),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openAutomatedAnswerKeyDialog() {
    final int tfCount = _exam.automatedConfig.trueFalseCount;
    final int mcqCount = _exam.automatedConfig.mcqCount;
    final int totalItems = tfCount + mcqCount;
    final bool isAr = _isArabicExam;

    if (totalItems <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى تحديد عدد فقرات الاختبار المؤتمت أولاً.')),
      );
      return;
    }

    final List<String> mcqOptions = isAr
        ? (_exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.arabicLetters
            ? ['أ', 'ب', 'جـ', 'د']
            : ['١', '٢', '٣', '٤'])
        : ['A', 'B', 'C', 'D'];

    final List<String> tfOptions = isAr ? ['ص', 'خ'] : ['T', 'F'];

    while (_exam.questions.length < totalItems) {
      final int idx = _exam.questions.length + 1;
      final bool isTf = idx <= tfCount;
      _exam.questions.add(QuestionModel(
        id: const Uuid().v4(),
        title: isTf
            ? (isAr ? 'صح/خطأ $idx' : 'T/F $idx')
            : (isAr ? 'اختيار $idx' : 'MCQ $idx'),
        mark: 1.0,
        spans: [TextSpanModel(text: '')],
        answerKey: '',
      ));
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.key, color: Color(0xFF1B5E20)),
              const SizedBox(width: 8),
              Text(
                isAr ? 'مفتاح إجابة الاختبار المؤتمت' : 'Automated Exam Answer Key',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.70,
            child: ListView(
              children: [
                if (tfCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isAr
                          ? 'أولاً: فقرات الصح والخطأ (إجمالي $tfCount فقرة)'
                          : 'Part 1: True / False Items (Total: $tfCount)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (int i = 0; i < tfCount; i++) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(
                              isAr ? 'فقرة ${i + 1}:' : 'Item ${i + 1}:',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            children: tfOptions.map((opt) {
                              final isSelected = _exam.questions[i].answerKey.trim() == opt;
                              return ChoiceChip(
                                label: Text(
                                  opt,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: const Color(0xFF1B5E20),
                                onSelected: (val) {
                                  setDlgState(() {
                                    _exam.questions[i].answerKey = val ? opt : '';
                                  });
                                  setState(() {});
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 6),
                  ],
                  const SizedBox(height: 12),
                ],

                if (mcqCount > 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isAr
                          ? 'ثانياً: فقرات الاختيار من متعدد (إجمالي $mcqCount فقرة)'
                          : 'Part 2: Multiple Choice Items (Total: $mcqCount)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (int j = 0; j < mcqCount; j++) ...[
                    Builder(
                      builder: (context) {
                        final int itemIndex = tfCount + j;
                        final qItem = _exam.questions[itemIndex];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 70,
                                child: Text(
                                  isAr ? 'فقرة ${itemIndex + 1}:' : 'Item ${itemIndex + 1}:',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              Wrap(
                                spacing: 6,
                                children: mcqOptions.map((opt) {
                                  final isSelected = qItem.answerKey.trim() == opt;
                                  return ChoiceChip(
                                    label: Text(
                                      opt,
                                      style: TextStyle(
                                        color: isSelected ? Colors.white : Colors.black87,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    selected: isSelected,
                                    selectedColor: const Color(0xFF1B5E20),
                                    onSelected: (val) {
                                      setDlgState(() {
                                        qItem.answerKey = val ? opt : '';
                                      });
                                      setState(() {});
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(height: 6),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1B5E20)),
              onPressed: () {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(isAr ? 'تم حفظ مفاتيح إجابات الاختبار بنجاح.' : 'Answer keys saved successfully.'),
                    backgroundColor: const Color(0xFF1B5E20),
                  ),
                );
              },
              child: Text(isAr ? 'تم الحفظ' : 'Done', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedBottomBar() {
    final bool isAutomated = _exam.examType == ExamType.automated;
    final double diff = _exam.totalMarks - _exam.targetTotalMarks;
    final bool isBalanced = diff.abs() < 0.05;
    final bool isAr = _isArabicExam;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B5E20),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 1,
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: Text(
                    isAutomated
                        ? (isAr ? 'إضافة فقرة مؤتمتة' : 'Add MCQ Item')
                        : (isAr ? 'إضافة سؤال جديد' : 'Add Question'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () => _openQuestionDialog(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1B5E20),
                    side: const BorderSide(color: Color(0xFF1B5E20)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(isAutomated ? Icons.key : Icons.account_balance, size: 18),
                  label: Text(
                    isAutomated
                        ? (isAr ? 'مفتاح الإجابة' : 'Answer Key')
                        : (isAr ? 'بنك الأسئلة' : 'Question Bank'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: isAutomated ? _openAutomatedAnswerKeyDialog : _showQuestionBankImportDialog,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF5B3E96),
                    side: const BorderSide(color: Color(0xFF5B3E96)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(isAutomated ? Icons.fact_check_outlined : Icons.auto_awesome, size: 18),
                  label: Text(
                    isAutomated
                        ? (isAr ? 'ورقة التظليل (OMR)' : 'OMR Sheet')
                        : (isAr ? 'قوالب جاهزة' : 'Templates'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: isAutomated ? _exportOmrSheetToDownloads : _showQuestionTemplatesDialog,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _showMarkBalancingDialog,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: isBalanced ? Colors.green.shade50 : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isBalanced ? Colors.green.shade400 : Colors.amber.shade600,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_exam.totalMarks.toStringAsFixed(1)} / ${_exam.targetTotalMarks.toStringAsFixed(0)} ${isAr ? 'د' : 'M'}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isBalanced ? Colors.green.shade900 : Colors.amber.shade900,
                        ),
                      ),
                      Text(
                        isAutomated
                            ? (isAr ? '${_exam.questions.length} فقرة مضافة' : '${_exam.questions.length} items')
                            : (isBalanced ? (isAr ? 'الميزان مضبوط ✓' : 'Balanced ✓') : (diff > 0 ? '+${diff.toStringAsFixed(1)}' : '${diff.toStringAsFixed(1)}')),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isBalanced ? Colors.green.shade800 : (diff > 0 ? Colors.blue.shade800 : Colors.red.shade800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextDirection examDir = _isArabicExam ? TextDirection.rtl : TextDirection.ltr;

    return GestureDetector(
      onTap: () {
        if (_selectedElementId != null) {
          setState(() => _selectedElementId = null);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFD6D9E0),
        appBar: AppBar(
          title: Text(
            _showAnswerKeyMode
                ? (_isArabicExam ? 'نموذج الإجابة: ${_exam.fileName}' : 'Answer Key: ${_exam.fileName}')
                : (_isNew ? (_isArabicExam ? 'اختبار جديد' : 'New Exam') : _exam.fileName),
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          backgroundColor: _showAnswerKeyMode ? const Color(0xFF0F766E) : const Color(0xFF1E3A8A),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isArabicExam ? const Color(0xFFD97706) : const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.language, size: 16),
                label: Text(
                  _isArabicExam ? 'عربي (RTL)' : 'English (LTR)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: _toggleExamLanguage,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.print_outlined, color: Colors.white),
              tooltip: 'طباعة مباشرة عبر الشبكة (Wi-Fi)',
              onPressed: () async {
                final isAnswerKey = await _showExportChoiceDialog('طباعة مباشرة للطابعة');
                if (isAnswerKey != null && mounted) {
                  await DirectPrintService.printExamDocument(
                    context: context,
                    exam: isAnswerKey ? _buildAnswerKeyExam() : _exam,
                    isAnswerKey: isAnswerKey,
                  );
                }
              },
            ),
            if (_exam.examType == ExamType.automated)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: Colors.tealAccent),
                tooltip: 'المصحح الآلي بالكاميرا (OMR Scanner)',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => OmrScannerScreen(exam: _exam)),
                  );
                },
              ),
            IconButton(
              icon: const Icon(Icons.alt_route, color: Colors.white),
              tooltip: 'توليد نموذج بديل (أ / ب / جـ)',
              onPressed: _generateAlternativeExamModel,
            ),
            IconButton(
              icon: Icon(
                _showAnswerKeyMode ? Icons.visibility : Icons.visibility_off,
                color: Colors.white,
              ),
              tooltip: _showAnswerKeyMode ? 'العودة لورقة الأسئلة' : 'معاينة نموذج الإجابة',
              onPressed: () {
                setState(() {
                  _showAnswerKeyMode = !_showAnswerKeyMode;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined, color: Colors.white),
              tooltip: 'مشاركة ملف المشروع (.exam)',
              onPressed: _exportExamProjectFile,
            ),
            if (_exam.examType == ExamType.automated)
              IconButton(
                icon: const Icon(Icons.fact_check_outlined, color: Colors.white),
                tooltip: 'تصدير ورقة التظليل (OMR Sheet)',
                onPressed: _exportOmrSheetToDownloads,
              ),
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
              tooltip: 'تصدير PDF',
              onPressed: _exportPdfToDownloads,
            ),
            IconButton(
              icon: const Icon(Icons.view_column, color: Colors.white),
              tooltip: 'أبعاد الترويسة والأعمدة',
              onPressed: _openHeaderFlexSettingsDialog,
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: Colors.white),
              tooltip: 'خيارات التذييل والهوامش وكشف الطلاب',
              onPressed: _openFooterSettingsDialog,
            ),
            IconButton(
              icon: const Icon(Icons.save, color: Colors.white, size: 26),
              tooltip: 'حفظ',
              onPressed: _triggerSave,
            ),
          ],
        ),
        body: Column(
          children: [
            // شريط أدوات Office Ribbon المبوب المستوحى من Word
            ExamRibbonToolbar(
              isBold: _isBold,
              isUnderline: _isUnderline,
              currentAlignment: _activeAlignment,
              currentColor: _activeColor,
              currentFont: _activeFont,
              currentFontSize: _activeFontSize,
              isArabicInput: _isArabicInput,
              onToggleBold: () => setState(() => _isBold = !_isBold),
              onToggleUnderline: () => setState(() => _isUnderline = !_isUnderline),
              onAlignmentChanged: (align) => setState(() => _activeAlignment = align),
              onColorChanged: (c) => setState(() => _activeColor = c),
              onFontChanged: (f) => setState(() => _activeFont = f),
              onFontSizeChanged: (s) => setState(() => _activeFontSize = s),
              onToggleInputLanguage: () {
                setState(() {
                  _isArabicInput = !_isArabicInput;
                  _activeAlignment = _isArabicInput ? TextAlign.right : TextAlign.left;
                  _activeFont = _isArabicInput ? 'Amiri' : 'Arial';
                });
              },
              onCopy: () {},
              onPaste: () {},
              onCut: () {},
              onSelectAll: () {},
              onDeleteSelected: () {},
              onOpenQuestionBank: _showQuestionBankImportDialog,
              onInsertImage: () async {
                final img = await _picker.pickImage(source: ImageSource.gallery);
                if (img != null && _exam.questions.isNotEmpty) {
                  setState(() {
                    _exam.questions.last.elements.add(InsertableElement(
                      id: const Uuid().v4(),
                      type: ElementType.image,
                      content: img.path,
                      width: 90,
                      height: 90,
                    ));
                  });
                }
              },
              onInsertDottedLine: () {
                if (_exam.questions.isNotEmpty) {
                  setState(() {
                    _exam.questions.last.elements.add(InsertableElement(
                      id: const Uuid().v4(),
                      type: ElementType.dottedLine,
                      content: '......................................................................',
                    ));
                  });
                }
              },
              onInsertPageBreak: () {
                if (_exam.questions.isNotEmpty) {
                  setState(() {
                    _exam.questions.last.spans.add(TextSpanModel(text: ' [فاصل_صفحة] '));
                  });
                }
              },
              onInsertTextBox: () {
                _showTextBoxEntryDialog(context, (txt) {
                  if (_exam.questions.isNotEmpty) {
                    setState(() {
                      _exam.questions.last.elements.add(InsertableElement(
                        id: const Uuid().v4(),
                        type: ElementType.textBox,
                        content: txt,
                      ));
                    });
                  }
                });
              },
              onInsertFraction: () => _openQuestionDialog(),
              onInsertRadical: () => _openQuestionDialog(),
              onInsertEquation: () => _openQuestionDialog(),
              onInsertVerticalMath: () => _openQuestionDialog(),
              onInsertLongDivision: () => _openQuestionDialog(),
              onOpenSymbolsModal: () => _openQuestionDialog(),
              onOpenTableDesigner: () => _openQuestionDialog(),
              onInsertShape: (kind) {
                if (_exam.questions.isNotEmpty) {
                  final jsonPayload = jsonEncode({
                    'kind': kind,
                    'width': 120.0,
                    'height': 70.0,
                    'label': '',
                    'strokeColor': '#000000',
                    'fillColor': 'transparent',
                  });
                  setState(() {
                    _exam.questions.last.elements.add(InsertableElement(
                      id: const Uuid().v4(),
                      type: ElementType.shape,
                      content: jsonPayload,
                      width: 120.0,
                      height: 70.0,
                    ));
                  });
                }
              },
              onQuickAction: (action) {
                if (_exam.questions.isNotEmpty) {
                  setState(() {
                    if (action == 'numbering') _exam.questions.last.spans.add(TextSpanModel(text: '١ - '));
                    if (action == 'bullets') _exam.questions.last.spans.add(TextSpanModel(text: '• '));
                    if (action == 'end_paragraph') _exam.questions.last.spans.add(TextSpanModel(text: ' .\n'));
                    if (action == 'end_question') _exam.questions.last.spans.add(TextSpanModel(text: ' ؟\n'));
                  });
                }
              },
            ),

            // ورقة العمل
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Directionality(
                  textDirection: examDir,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                        padding: EdgeInsets.only(
                          top: _exam.header.topMargin1cm ? 8.5 : 12.0,
                          left: 12.0,
                          right: 12.0,
                          bottom: 12.0,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_exam.header.topMargin1cm) ...[
                              InkWell(
                                onTap: _openFooterSettingsDialog,
                                borderRadius: BorderRadius.circular(4),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
                                  margin: const EdgeInsets.only(bottom: 6.0),
                                  decoration: BoxDecoration(
                                    color: _exam.header.studentDataMode != 'none'
                                        ? Colors.green.shade50
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                    border: _exam.header.studentDataMode != 'none'
                                        ? Border.all(color: Colors.green.shade200, width: 0.8)
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          if (_exam.header.studentDataMode != 'none')
                                            const Icon(Icons.how_to_reg, size: 14, color: Colors.green),
                                          const SizedBox(width: 4),
                                          Text(
                                            _exam.header.studentDataMode != 'none'
                                                ? (_isArabicExam ? 'اسم الطالب: [ كشف إكسيل مفعّل ]' : 'Student Name: [ Excel Enabled ]')
                                                : (_isArabicExam ? 'اسم الطالب: .................................................' : 'Student Name: .................................................'),
                                            style: TextStyle(
                                              fontFamily: _exam.header.adminFont,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: _exam.header.studentDataMode != 'none'
                                                  ? Colors.green.shade900
                                                  : Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            _exam.header.studentDataMode != 'none'
                                                ? (_isArabicExam ? 'رقم الجلوس: [ آلي ]' : 'Seat No: [ Auto ]')
                                                : (_isArabicExam ? 'رقم الجلوس: [ ........... ]' : 'Seat No: [ ........... ]'),
                                            style: TextStyle(
                                              fontFamily: _exam.header.detailsFont,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                              color: _exam.header.studentDataMode != 'none'
                                                  ? Colors.green.shade900
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const Icon(Icons.settings, size: 13, color: Colors.grey),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
            ),
          ],
        ),
        bottomNavigationBar: _buildUnifiedBottomBar(),
      ),
    );
  }

  Widget _buildExamHeader() {
    final titleText = _showAnswerKeyMode
        ? '${_exam.header.examTitle} (${_isArabicExam ? "نموذج الإجابة" : "Answer Key"})'
        : _exam.header.examTitle;

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
                          fontWeight: _exam.header.adminBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.adminFontSize + 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.ministry,
                        style: TextStyle(
                          fontFamily: _exam.header.adminFont,
                          fontWeight: _exam.header.adminBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.adminFontSize,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.governorate,
                        style: TextStyle(
                          fontFamily: _exam.header.adminFont,
                          fontWeight: _exam.header.adminBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.adminFontSize - 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        _exam.header.directorate,
                        style: TextStyle(
                          fontFamily: _exam.header.adminFont,
                          fontWeight: _exam.header.adminBold ? FontWeight.bold : FontWeight.normal,
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
              SizedBox(
                width: _sideHeaderWidth,
                child: InkWell(
                  onTap: _editExamDetailsDialog,
                  child: Column(
                    crossAxisAlignment: _isArabicExam ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                    children: [
                      Text(
                        _isArabicExam ? 'الصف : ${_exam.header.grade}' : 'Grade: ${_exam.header.grade}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.detailsFontSize + 1,
                        ),
                      ),
                      Text(
                        _isArabicExam ? 'الماده : ${_exam.header.subject}' : 'Subject: ${_exam.header.subject}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.detailsFontSize + 1,
                        ),
                      ),
                      Text(
                        _isArabicExam ? 'التاريخ: ${_exam.header.examDate}' : 'Date: ${_exam.header.examDate}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.detailsFontSize,
                        ),
                      ),
                      Text(
                        _isArabicExam ? 'الزمن: ${_exam.header.examTime}' : 'Time: ${_exam.header.examTime}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.detailsFontSize - 0.5,
                        ),
                      ),
                      Text(
                        _isArabicExam ? 'الفتره: ${_exam.header.period}' : 'Period: ${_exam.header.period}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
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
          InkWell(
            onTap: _editExamTitleDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 3),
              color: _showAnswerKeyMode ? Colors.teal.shade50 : Colors.grey.shade200,
              child: Text(
                titleText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: _exam.header.titleFont,
                  fontWeight: _exam.header.titleBold ? FontWeight.bold : FontWeight.normal,
                  fontSize: _exam.header.titleFontSize,
                  color: _showAnswerKeyMode ? const Color(0xFF0F766E) : Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsTable() {
    final isAr = _isArabicExam;

    return Table(
      border: TableBorder.all(color: Colors.black, width: 1),
      columnWidths: {
        0: FixedColumnWidth(_questionColWidth),
        1: const FlexColumnWidth(),
        2: FixedColumnWidth(_markColWidth),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: [
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(
                  isAr ? 'السؤال' : 'Q',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
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
                    _exam.header.instructionText.isNotEmpty
                        ? _exam.header.instructionText
                        : (isAr ? 'أجب عن جميع الأسئلة الآتية' : 'Answer all the following questions'),
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
                child: Text(
                  isAr ? 'الدرجة' : 'Mark',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5),
                ),
              ),
            ),
          ],
        ),
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

          final markUnit = isAr ? 'د' : 'm';
          final markText = q.mark > 0
              ? (q.mark % 1 == 0 ? '${q.mark.toInt()} $markUnit' : '${q.mark} $markUnit')
              : '-';

          Widget markWidget = Text(
            markText,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          );

          if (q.gradeOrientation == GradeTextOrientation.verticalBottomToTop) {
            markWidget = RotatedBox(quarterTurns: 3, child: markWidget);
          } else if (q.gradeOrientation == GradeTextOrientation.verticalTopToBottom) {
            markWidget = RotatedBox(quarterTurns: 1, child: markWidget);
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
                        _buildQuestionContent(q),
                        if (q.elements.isNotEmpty) const SizedBox(height: 6),
                        ...q.elements.map((el) => _buildRenderedElement(el)),
                        if (_showAnswerKeyMode && q.answerKey.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              border: Border.all(color: Colors.blue.shade300),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.check_circle_outline, size: 16, color: Colors.blue),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    isAr ? 'الإجابة النموذجية: ${q.answerKey}' : 'Model Answer: ${q.answerKey}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: Colors.blue.shade900,
                                      fontFamily: isAr ? 'Amiri' : 'Arial',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                    child: Center(child: markWidget),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  InlineSpan _buildInlineSpanWithFractions(String text, TextStyle baseStyle) {
    final regExp = RegExp(r'(\[فاصل_صفحة\]|\[(كسر|جذر|sqrt|عمودي|قسمة|div|نها|تباديل|توافيق|مجموع|تكامل|متجه|بار|محدد|مصفوفة):(.*?)\])');
    final matches = regExp.allMatches(text);

    if (matches.isEmpty) {
      return TextSpan(text: text, style: baseStyle);
    }

    List<InlineSpan> children = [];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        children.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: baseStyle,
        ));
      }

      final fullMatched = match.group(0) ?? '';

      if (fullMatched == '[فاصل_صفحة]') {
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.blueGrey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blueGrey.shade300, style: BorderStyle.solid),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_page_break_outlined, size: 16, color: Color(0xFF1E3A8A)),
                  const SizedBox(width: 6),
                  Text(
                    _isArabicExam
                        ? '--- فاصل صفحة جديدة (يبدأ ما بعده في صفحة جديدة) ---'
                        : '--- Page Break (Content follows on next page) ---',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        final type = match.group(2);
        final rawContent = match.group(3) ?? '';
        final parts = rawContent.split(':');

        if (type == 'كسر') {
          final p = rawContent.split('/');
          final numVal = p.isNotEmpty ? p[0] : '';
          final denVal = p.length > 1 ? p[1] : '';

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: IntrinsicWidth(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        numVal,
                        textAlign: TextAlign.center,
                        style: baseStyle.copyWith(
                          fontSize: (baseStyle.fontSize ?? 14) * 0.85,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        height: 1.2,
                        color: baseStyle.color ?? Colors.black87,
                        margin: const EdgeInsets.symmetric(vertical: 1.0),
                      ),
                      Text(
                        denVal,
                        textAlign: TextAlign.center,
                        style: baseStyle.copyWith(
                          fontSize: (baseStyle.fontSize ?? 14) * 0.85,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        } else if (type == 'جذر' || type == 'sqrt') {
          final String degree = parts.length > 1 ? parts[0] : '';
          final String radicand = parts.length > 1 ? parts.sublist(1).join(':') : parts[0];
          final bool isArRadical = (type == 'جذر') && _isArabicExam;

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Directionality(
                textDirection: isArRadical ? TextDirection.rtl : TextDirection.ltr,
                child: IntrinsicWidth(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (degree.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                            top: 0.0,
                            left: isArRadical ? 1.5 : 0.0,
                            right: !isArRadical ? 1.5 : 0.0,
                          ),
                          child: Text(
                            degree,
                            style: baseStyle.copyWith(
                              fontSize: (baseStyle.fontSize ?? 14) * 0.70,
                              fontWeight: FontWeight.bold,
                              height: 0.9,
                            ),
                          ),
                        ),
                      CustomPaint(
                        painter: isArRadical
                            ? _ArabicRadicalPainter(color: baseStyle.color ?? Colors.black87)
                            : _EnglishRadicalPainter(color: baseStyle.color ?? Colors.black87),
                        child: Padding(
                          padding: EdgeInsets.only(
                            top: 4.0,
                            right: isArRadical ? 10.0 : 4.0,
                            left: isArRadical ? 4.0 : 10.0,
                            bottom: 2.0,
                          ),
                          child: Text(
                            radicand,
                            style: baseStyle.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: (baseStyle.fontSize ?? 14) * 0.95,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      children.add(TextSpan(
        text: text.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return TextSpan(children: children);
  }

  Widget _buildQuestionContent(QuestionModel q) {
    final fullText = q.spans.map((s) => s.text).join('');
    final bool isAutomatedMcq = _exam.examType == ExamType.automated &&
        (fullText.contains('[') && (fullText.contains('أ-') || fullText.contains('١-') || fullText.contains('1-') || fullText.contains('A-') || fullText.contains('a-')));

    if (isAutomatedMcq) {
      return _buildAutomatedEditorMcqGrid(q);
    }

    final TextAlign chosenAlign = q.alignment ?? (_isArabicExam ? TextAlign.right : TextAlign.left);

    return Text.rich(
      TextSpan(
        children: q.spans.map((s) {
          Color spanColor = Colors.black87;
          try {
            spanColor = Color(int.parse(s.colorHex.replaceFirst('#', '0xFF')));
          } catch (_) {}

          final style = TextStyle(
            fontFamily: s.fontFamily,
            fontWeight: s.isBold ? FontWeight.bold : FontWeight.normal,
            decoration: s.isUnderline ? TextDecoration.underline : TextDecoration.none,
            fontSize: s.fontSize,
            color: spanColor,
            height: 1.5,
          );
          return _buildInlineSpanWithFractions(s.text, style);
        }).toList(),
      ),
      textAlign: chosenAlign,
    );
  }

  Widget _buildAutomatedEditorMcqGrid(QuestionModel q) {
    final fullText = q.spans.map((s) => s.text).join('');
    final lines = fullText.split('\n').where((l) => l.trim().isNotEmpty).toList();

    final String intro = lines.isNotEmpty ? lines.first : '';
    final List<String> itemLines = lines.length > 1 ? lines.sublist(1) : [];

    final bool isAr = _isArabicExam;
    final List<String> defaultSymbols = isAr
        ? (_exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.arabicLetters ? ['أ', 'ب', 'جـ', 'د'] : ['١', '٢', '٣', '٤'])
        : ['A', 'B', 'C', 'D'];

    final TextAlign align = q.alignment ?? (isAr ? TextAlign.right : TextAlign.left);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (intro.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              intro,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
              textAlign: align,
            ),
          ),
        ...itemLines.map((line) {
          int itemNum = 1;
          String qBody = line;

          final match = RegExp(r'^(\d+)\s*[-–]\s*(.*)').firstMatch(line);
          if (match != null) {
            itemNum = int.tryParse(match.group(1) ?? '1') ?? 1;
            qBody = match.group(2) ?? '';
          }

          List<String> parsedChoices = ['', '', '', ''];
          if (qBody.contains('[') && qBody.contains(']')) {
            final startIdx = qBody.lastIndexOf('[');
            final endIdx = qBody.lastIndexOf(']');
            final bracketContent = qBody.substring(startIdx + 1, endIdx);
            qBody = qBody.substring(0, startIdx).trim();

            final rawParts = bracketContent.split(RegExp(r'[|،,]'));
            for (int i = 0; i < rawParts.length && i < 4; i++) {
              parsedChoices[i] = rawParts[i].replaceAll(RegExp(r'^[A-Za-zأ-ي0-9١-٩]\s*[-–]\s*'), '').trim();
            }
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 6.0),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black87, width: 1.0),
              color: Colors.white,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 34,
                  decoration: BoxDecoration(
                    border: Border(
                      left: isAr ? const BorderSide(color: Colors.black87, width: 1.0) : BorderSide.none,
                      right: !isAr ? const BorderSide(color: Colors.black87, width: 1.0) : BorderSide.none,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$itemNum',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.black87, width: 0.8)),
                        ),
                        child: Text(
                          qBody.isNotEmpty ? qBody : '....................................................................',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          textAlign: align,
                        ),
                      ),
                      SizedBox(
                        height: 24,
                        child: Row(
                          children: List.generate(4, (idx) {
                            final sym = defaultSymbols[idx];
                            final choiceText = parsedChoices[idx];

                            return Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    left: (isAr && idx > 0) ? const BorderSide(color: Colors.black87, width: 0.8) : BorderSide.none,
                                    right: (!isAr && idx > 0) ? const BorderSide(color: Colors.black87, width: 0.8) : BorderSide.none,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border(
                                          left: isAr ? const BorderSide(color: Colors.black87, width: 0.8) : BorderSide.none,
                                          right: !isAr ? const BorderSide(color: Colors.black87, width: 0.8) : BorderSide.none,
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          sym,
                                          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Center(
                                        child: Text(
                                          choiceText,
                                          style: const TextStyle(fontSize: 10),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildRenderedElement(InsertableElement el) {
    Widget coreWidget;
    switch (el.type) {
      case ElementType.image:
        coreWidget = Center(
          child: Image.file(
            File(el.content),
            height: el.height,
            width: el.width,
            fit: BoxFit.contain,
          ),
        );
        break;
      case ElementType.textBox:
        coreWidget = Container(
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
        break;
      case ElementType.dottedLine:
        coreWidget = Text(
          el.content,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, letterSpacing: 1.5),
        );
        break;
      case ElementType.mathOperation:
        coreWidget = const SizedBox.shrink();
        break;
      case ElementType.table:
        coreWidget = const SizedBox.shrink();
        break;
      case ElementType.shape:
        coreWidget = _renderCustomShape(el.content, el.width, el.height);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: coreWidget,
    );
  }

  Widget _renderCustomShape(String jsonStr, [double? customWidth, double? customHeight]) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final String kind = data['kind'] ?? 'rectangle';
      final double w = customWidth ?? ((data['width'] as num?)?.toDouble() ?? 120.0);
      final double h = customHeight ?? ((data['height'] as num?)?.toDouble() ?? 70.0);
      final String label = data['label'] ?? '';
      final Color strokeColor = Color(int.parse((data['strokeColor'] ?? '#000000').replaceFirst('#', '0xFF')));
      final Color fillColor = (data['fillColor'] == null || data['fillColor'] == 'transparent')
          ? Colors.transparent
          : Color(int.parse((data['fillColor'] as String).replaceFirst('#', '0xFF')));

      return CustomPaint(
        size: Size(w, h),
        painter: _ExamShapePainter(
          kind: kind,
          strokeColor: strokeColor,
          fillColor: fillColor,
        ),
        child: SizedBox(
          width: w,
          height: h,
          child: Center(
            child: label.isNotEmpty
                ? Text(
                    label,
                    style: TextStyle(
                      fontFamily: _isArabicExam ? 'Amiri' : 'Arial',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: strokeColor,
                    ),
                    textAlign: TextAlign.center,
                  )
                : null,
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildFooterPreview() {
    final isAr = _isArabicExam;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text(
            _showAnswerKeyMode
                ? (isAr ? 'نموذج الإجابة الرسمي - لجنة الكنترول والتصحيح' : 'Official Answer Key - Exam Control Committee')
                : (_exam.header.isMultiPage
                    ? (_exam.header.continuationText.isNotEmpty ? _exam.header.continuationText : (isAr ? 'يتبع في الصفحة التالية...' : 'To be continued on next page...'))
                    : (_exam.header.singlePageFooterText.isNotEmpty ? _exam.header.singlePageFooterText : (isAr ? 'انتهت الأسئلة مع تمنياتنا بالتوفيق' : 'End of Questions - Good Luck'))),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Align(
            alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              _showAnswerKeyMode
                  ? (isAr ? 'المصحح / المراجع: ......................' : 'Examiner: ......................')
                  : _exam.header.teacherSignature,
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

  void _showQuestionTemplatesDialog() {}

  void _openQuestionDialog({int? questionIndex}) {
    final bool isEdit = questionIndex != null;
    final bool isAr = _isArabicExam;

    final q = isEdit
        ? _exam.questions[questionIndex]
        : QuestionModel(
            id: const Uuid().v4(),
            title: isAr ? 'السؤال ${_exam.questions.length + 1}' : 'Question ${_exam.questions.length + 1}',
            spans: [],
            elements: [],
            answerKey: '',
            isTwoColumns: false,
            alignment: isAr ? TextAlign.right : TextAlign.left,
          );

    final titleCtrl = TextEditingController(text: q.title);
    final textCtrl = TextEditingController(text: q.spans.map((e) => e.text).join(''));
    final markCtrl = TextEditingController(text: q.mark > 0 ? (q.mark % 1 == 0 ? q.mark.toInt().toString() : q.mark.toString()) : '5');
    final answerCtrl = TextEditingController(text: q.answerKey);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, left: 16, right: 16, top: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'عنوان السؤال')),
            TextField(controller: markCtrl, decoration: const InputDecoration(labelText: 'الدرجة')),
            TextField(controller: textCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'نص السؤال')),
            TextField(controller: answerCtrl, decoration: const InputDecoration(labelText: 'الإجابة النموذجية')),
            const SizedBox(height: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
              onPressed: () {
                final newQ = QuestionModel(
                  id: q.id,
                  title: titleCtrl.text,
                  mark: double.tryParse(markCtrl.text) ?? 5.0,
                  spans: [
                    TextSpanModel(
                      text: textCtrl.text,
                      fontFamily: _activeFont,
                      fontSize: _activeFontSize,
                      isBold: _isBold,
                      isUnderline: _isUnderline,
                      colorHex: _activeColor,
                    )
                  ],
                  elements: q.elements,
                  answerKey: answerCtrl.text.trim(),
                  alignment: _activeAlignment,
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
              child: const Text('حفظ في ورقة الاختبار', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 12),
          ],
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
        content: TextField(controller: textCtrl, decoration: const InputDecoration(hintText: 'اكتب النص هنا...')),
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

  Future<void> _handleTopMarginToggle(bool val, StateSetter setDlgState) async {
    if (!val) {
      setDlgState(() {
        _exam.header.topMargin1cm = false;
        _exam.header.studentDataMode = 'none';
        _exam.header.excelFilePath = null;
      });
      return;
    }
  }

  void _openFooterSettingsDialog() {}
  void _editAdminHeaderDialog() {}
  void _editExamDetailsDialog() {}
  void _editExamTitleDialog() {}
  void _editBasmalaDialog() {}
  void _editInstructionDialog() {}
}

class _ArabicRadicalPainter extends CustomPainter {
  final Color color;
  _ArabicRadicalPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final path = Path();
    final startX = size.width;
    final bottomY = size.height - 2;
    path.moveTo(startX, bottomY - 6);
    path.lineTo(startX - 3, bottomY);
    path.lineTo(startX - 7, 2);
    path.lineTo(0, 2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EnglishRadicalPainter extends CustomPainter {
  final Color color;
  _EnglishRadicalPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final path = Path();
    final bottomY = size.height - 2;
    path.moveTo(0, bottomY - 6);
    path.lineTo(3, bottomY);
    path.lineTo(7, 2);
    path.lineTo(size.width, 2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ExamShapePainter extends CustomPainter {
  final String kind;
  final Color strokeColor;
  final Color fillColor;

  _ExamShapePainter({required this.kind, required this.strokeColor, required this.fillColor});

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;

    switch (kind) {
      case 'circle':
        canvas.drawOval(Rect.fromLTWH(2, 2, w - 4, h - 4), strokePaint);
        break;
      case 'triangle':
        final path = Path()..moveTo(w / 2, 2)..lineTo(w - 2, h - 2)..lineTo(2, h - 2)..close();
        canvas.drawPath(path, strokePaint);
        break;
      default:
        canvas.drawRect(Rect.fromLTWH(2, 2, w - 4, h - 4), strokePaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ExamShapePainter oldDelegate) => true;
}

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// أبعاد ورقة A4 القياسية للشاشات والطباعة (بكسل منطقي 96 DPI)
const double kA4PaperWidth = 794.0;
const double kA4PaperHeight = 1123.0;

// قائمة الخطوط الرسمية المعتمدة
const List<FontItem> appFontsList = [
  {'id': 'Amiri', 'name': 'خط الأميري (الافتراضي)'},
  {'id': 'Hafs', 'name': 'مصحف حفص (عثماني)'},
  {'id': 'Thuluth', 'name': 'خط الثلث'},
  {'id': 'Almarai', 'name': 'المراعي'},
  {'id': 'Changa', 'name': 'تشانجا'},
  {'id': 'Kufam', 'name': 'كوفام'},
  {'id': 'Rubik', 'name': 'روبيك'},
  {'id': 'Arial', 'name': 'أريال (Arial)'},
  {'id': 'ElHijaz', 'name': 'الحجاز عادي'},
  {'id': 'ElSHijazAdorn', 'name': 'زخارف الحجاز (ElS-Hijaz Adorn)'},
  {'id': 'ElourQuraaKufi', 'name': 'قراء كوفي'},
  {'id': 'ElghAnSrame', 'name': 'الغصن الصارم'},
  {'id': 'ElAfrica', 'name': 'إفريقيا (ElAfrica)'},
  {'id': 'SultanCtangle', 'name': 'سلطان (Sultan)'},
  {'id': 'Tahrir', 'name': 'تحرير'},
  {'id': 'DTUTH', 'name': 'ديتوث (DTUTH)'},
  {'id': 'Lishposter', 'name': 'ليش بوستر'},
  {'id': 'Axdf', 'name': 'أكسدف (Axdf)'},
  {'id': 'Banyeh', 'name': 'بنية (Banyeh)'},
  {'id': 'Meshref', 'name': 'مشرف'},
  {'id': 'Minder', 'name': 'ميندر'},
  {'id': 'Mobv2', 'name': 'موب V2'},
  {'id': 'GSoon', 'name': 'غصون'},
  {'id': 'DeApple', 'name': 'دي آبل'},
  {'id': 'JsMath', 'name': 'رموز الرياضيات (JsMath)'},
  {'id': 'Satisfy', 'name': 'Satisfy'},
  {'id': 'Schoolbell', 'name': 'Schoolbell'},
  {'id': 'Caps', 'name': 'Caps Regular'},
  {'id': 'Chewy', 'name': 'Chewy'},
  {'id': 'Crushed', 'name': 'Crushed'},
  {'id': 'Girls', 'name': 'Girls'},
  {'id': 'Grover', 'name': 'Grover'},
  {'id': 'RSwanky', 'name': 'R-Swanky'},
  {'id': 'SMono', 'name': 'خط أحادي (SMono)'},
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
  // متغير التكبير والتحكم به
  double _zoomLevel = 1.0;
  final TransformationController _transformationController = TransformationController();

  // تتبع استهلاك مساحة ورقة A4 لكل صفحة
  final Map<int, double> _pageHeights = {};

  late ExamModel _exam;
  late bool _isNew;

  bool _showAnswerKeyMode = false;

  double _sideHeaderWidth = 145.0;
  double _questionColWidth = 38.0;
  double _markColWidth = 38.0;

  final ImagePicker _picker = ImagePicker();

  InsertableElement? _copiedElement;
  String? _selectedElementId;

  // الحالات النشطة لتنسيق الشريط المبوب الرئيسي
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
    _transformationController.value = Matrix4.identity()..scale(_zoomLevel);

    // ملاءمة حجم صفحة A4 تلقائياً مع حجم الشاشة عند فتح المحرر
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScreenToA4();
    });
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  // حساب التكبير ليلائم عرض A4 تلقائياً مع عرض الجهاز
  void _fitScreenToA4() {
    if (!mounted) return;
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 0) {
      final double targetScale = ((screenWidth - 20) / kA4PaperWidth).clamp(0.4, 1.0);
      setState(() {
        _zoomLevel = targetScale;
        _transformationController.value = Matrix4.identity()..scale(targetScale);
      });
      _measurePagesHeight();
    }
  }

  // قياس الارتفاع الفعلي لمحتوى كل صفحة لحساب نسبة الاستهلاك بدقة
  void _measurePagesHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  // دوال التكبير والتصغير والملاءمة المساعدة
  void _zoomIn() {
    setState(() {
      _zoomLevel = math.min(_zoomLevel + 0.15, 3.0);
      _transformationController.value = Matrix4.identity()..scale(_zoomLevel);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomLevel = math.max(_zoomLevel - 0.15, 0.4);
      _transformationController.value = Matrix4.identity()..scale(_zoomLevel);
    });
  }

  void _fitScreen() {
    _fitScreenToA4();
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
      _measurePagesHeight();
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
              _measurePagesHeight();
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
                          _measurePagesHeight();
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
    : (_exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.arabicLetters
        ? ['A', 'B', 'C', 'D']
        : ['1', '2', '3', '4']);

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
            // شريط أوفيس Ribbon المبوب أعلى ورقة الاختبار
            ExamRibbonToolbar(
              isBold: _isBold,
              isUnderline: _isUnderline,
              currentAlignment: _activeAlignment,
              currentColor: _activeColor,
              currentFont: _activeFont,
              currentFontSize: _activeFontSize,
              isArabicInput: _isArabicInput,
              showQuestionSettings: true,
              onToggleQuestionSettings: () {},
              isTextSelected: false,
              hasClipboardContent: _copiedElement != null,
              currentLineSpacing: 1.5,
              currentZoom: _zoomLevel,
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
              onCopy: () {
                if (_exam.questions.isNotEmpty && _exam.questions.last.elements.isNotEmpty) {
                  final el = _exam.questions.last.elements.last;
                  setState(() {
                    _copiedElement = InsertableElement(
                      id: const Uuid().v4(),
                      type: el.type,
                      content: el.content,
                      width: el.width,
                      height: el.height,
                      dx: el.dx,
                      dy: el.dy,
                    );
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ العنصر الأخير للحافظة.')),
                  );
                }
              },
              onPaste: () {
                if (_copiedElement != null && _exam.questions.isNotEmpty) {
                  setState(() {
                    _exam.questions.last.elements.add(InsertableElement(
                      id: const Uuid().v4(),
                      type: _copiedElement!.type,
                      content: _copiedElement!.content,
                      width: _copiedElement!.width,
                      height: _copiedElement!.height,
                      dx: _copiedElement!.dx + 10,
                      dy: _copiedElement!.dy + 10,
                    ));
                  });
                  _measurePagesHeight();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم لصق العنصر في السؤال الأخير.')),
                  );
                }
              },
              onCut: () {
                if (_exam.questions.isNotEmpty && _exam.questions.last.elements.isNotEmpty) {
                  final el = _exam.questions.last.elements.removeLast();
                  setState(() {
                    _copiedElement = InsertableElement(
                      id: const Uuid().v4(),
                      type: el.type,
                      content: el.content,
                      width: el.width,
                      height: el.height,
                      dx: el.dx,
                      dy: el.dy,
                    );
                  });
                  _measurePagesHeight();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم قص العنصر إلى الحافظة.')),
                  );
                }
              },
              onShare: null,
              onSelectAll: () {},
              onDeleteSelected: () {
                if (_selectedElementId != null) {
                  setState(() {
                    for (var q in _exam.questions) {
                      q.elements.removeWhere((e) => e.id == _selectedElementId);
                    }
                    _selectedElementId = null;
                  });
                  _measurePagesHeight();
                }
              },
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
                  _measurePagesHeight();
                } else if (_exam.questions.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى إضافة سؤال أولاً لإدراج الصورة بداخله.')),
                  );
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
                  _measurePagesHeight();
                }
              },
              onInsertPageBreak: () {
                setState(() {
                  _exam.questions.add(
                    QuestionModel(
                      id: 'page_break_${const Uuid().v4()}',
                      title: '---',
                      mark: 0,
                      spans: [],
                    ),
                  );
                });
                _measurePagesHeight();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تمت إضافة صفحة جديدة')),
                );
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
                    _measurePagesHeight();
                  }
                });
              },
              onInsertFraction: () => _openQuestionDialog(),
              onInsertRadical: () {
                if (_exam.questions.isNotEmpty) {
                  setState(() {
                    _exam.questions.last.spans.add(TextSpanModel(
                      text: _isArabicExam ? ' [جذر:٢٥] ' : ' [sqrt:25] ',
                      fontFamily: _activeFont,
                      fontSize: _activeFontSize,
                    ));
                  });
                  _measurePagesHeight();
                } else {
                  _openQuestionDialog();
                }
              },
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
                  _measurePagesHeight();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى إضافة سؤال أولاً لإدراج الشكل بداخله.')),
                  );
                }
              },
              onLineSpacingChanged: null,
              onZoomIn: _zoomIn,
              onZoomOut: _zoomOut,
              onFitScreen: _fitScreen,
            ),

            // تغليف عرض الورقة البيضاء بـ InteractiveViewer وتثبيت أبعاد A4
            Expanded(
              child: InteractiveViewer(
                transformationController: _transformationController,
                minScale: 0.35,
                maxScale: 3.0,
                boundaryMargin: const EdgeInsets.all(120),
                onInteractionUpdate: (details) {
                  final scale = _transformationController.value.getMaxScaleOnAxis();
                  if ((scale - _zoomLevel).abs() > 0.03) {
                    setState(() {
                      _zoomLevel = scale;
                    });
                  }
                },
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // عرض الصفحات بتنسيق ومقاييس A4
                      ..._buildAllPages(),
                      const SizedBox(height: 50),
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

  // دالة بناء كافة الصفحات وتقسيمها عند page_break_ مع تطبيق أبعاد A4 ومؤشر استهلاك المساحة
  List<Widget> _buildAllPages() {
    List<List<QuestionModel>> pages = [[]];
    for (var q in _exam.questions) {
      if (q.id.startsWith('page_break_')) {
        pages.add([]);
      } else {
        pages.last.add(q);
      }
    }

    final TextDirection examDir = _isArabicExam ? TextDirection.rtl : TextDirection.ltr;

    return pages.asMap().entries.map((entry) {
      final int pageIndex = entry.key;
      final List<QuestionModel> pageQuestions = entry.value;

      // حساب الارتفاع المستهلك الفعلي
      final double consumedHeight = _pageHeights[pageIndex] ?? 0.0;
      final double fillPercentage = (consumedHeight / kA4PaperHeight).clamp(0.0, 1.5);
      final int displayPercent = (fillPercentage * 100).toInt();
      final bool isOverflown = consumedHeight > kA4PaperHeight;

      return Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 28.0),
          width: kA4PaperWidth,
          constraints: const BoxConstraints(
            minWidth: kA4PaperWidth,
            maxWidth: kA4PaperWidth,
            minHeight: kA4PaperHeight,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                spreadRadius: 1,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              // قياس مساحة المحتوى الفعلية عبر NotificationListener
              NotificationListener<SizeChangedLayoutNotification>(
                onNotification: (_) {
                  _measurePagesHeight();
                  return true;
                },
                child: SizeChangedLayoutNotifier(
                  child: Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        final RenderBox? box = context.findRenderObject() as RenderBox?;
                        if (box != null && box.hasSize) {
                          if (_pageHeights[pageIndex] != box.size.height) {
                            setState(() {
                              _pageHeights[pageIndex] = box.size.height;
                            });
                          }
                        }
                      });

                      return Padding(
                        padding: EdgeInsets.only(
                          top: _exam.header.topMargin1cm ? 8.5 : 12.0,
                          left: 12.0,
                          right: 12.0,
                          bottom: 34.0, // هامش لتجنب تداخل مؤشر المساحة السفلي
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (pageIndex == 0) ...[
                              if (_exam.header.topMargin1cm) ...[
                                Directionality(
                                  textDirection: TextDirection.rtl,
                                  child: InkWell(
                                    onTap: _openFooterSettingsDialog,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 3.0),
                                      margin: const EdgeInsets.only(bottom: 6.0),
                                      decoration: BoxDecoration(
                                        color: _exam.header.studentDataMode != 'none' ? Colors.green.shade50 : Colors.transparent,
                                        borderRadius: BorderRadius.circular(4),
                                        border: _exam.header.studentDataMode != 'none' ? Border.all(color: Colors.green.shade200, width: 0.8) : null,
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              if (_exam.header.studentDataMode != 'none') const Icon(Icons.how_to_reg, size: 14, color: Colors.green),
                                              const SizedBox(width: 4),
                                              Text(
                                                _exam.header.studentDataMode != 'none' ? 'اسم الطالب: [ كشف إكسيل مفعّل ]' : 'اسم الطالب: .................................................',
                                                style: TextStyle(fontFamily: _exam.header.adminFont, fontWeight: FontWeight.bold, fontSize: 11, color: _exam.header.studentDataMode != 'none' ? Colors.green.shade900 : Colors.black87),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              Text(
                                                _exam.header.studentDataMode != 'none' ? 'رقم الجلوس: [ آلي ]' : 'رقم الجلوس: [ ........... ]',
                                                style: TextStyle(fontFamily: _exam.header.detailsFont, fontWeight: FontWeight.bold, fontSize: 11, color: _exam.header.studentDataMode != 'none' ? Colors.green.shade900 : Colors.black87),
                                              ),
                                              const SizedBox(width: 6),
                                              const Icon(Icons.settings, size: 13, color: Colors.grey),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              Directionality(textDirection: TextDirection.rtl, child: _buildExamHeader()),
                            ] else ...[
                              Directionality(
                                textDirection: TextDirection.rtl,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Colors.black, width: 1.5)),
                                  ),
                                  child: Text(
                                    'تابع اختبار مادة ${_exam.header.subject} للصف ${_exam.header.grade}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A)),
                                  ),
                                ),
                              ),
                            ],
                            
                            const SizedBox(height: 8),

                            Directionality(
                              textDirection: examDir,
                              child: _buildQuestionsTableForPage(pageQuestions),
                            ),
                            const SizedBox(height: 10),

                            Directionality(textDirection: TextDirection.rtl, child: _buildFooterPreview()),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              // مؤشر قياس استهلاك مساحة ورقة A4 أسفل كل صفحة
              Positioned(
                bottom: 6,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isOverflown ? Colors.red.shade400 : Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOverflown ? Colors.red.shade700 : const Color(0xFF1E3A8A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'A4 - صفحة ${pageIndex + 1} من ${pages.length}',
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: fillPercentage.clamp(0.0, 1.0),
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isOverflown
                                  ? Colors.red
                                  : (fillPercentage > 0.85 ? Colors.orange : Colors.green),
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isOverflown
                            ? 'فاضت الصفحة ($displayPercent%) ⚠️'
                            : 'استهلاك: $displayPercent%',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isOverflown
                              ? Colors.red.shade800
                              : (fillPercentage > 0.85 ? Colors.orange.shade900 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // دالة بناء جدول الأسئلة لصفحة محددة مع الحفاظ على الفهرس العام
  Widget _buildQuestionsTableForPage(List<QuestionModel> questions) {
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
                child: Text(isAr ? 'السؤال' : 'Q', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
              ),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: InkWell(
                onTap: _editInstructionDialog,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                  child: Text(
                    _exam.header.instructionText.isNotEmpty ? _exam.header.instructionText : (isAr ? 'أجب عن جميع الأسئلة الآتية' : 'Answer all the following questions'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ),
            ),
            TableCell(
              verticalAlignment: TableCellVerticalAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Text(isAr ? 'الدرجة' : 'Mark', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5)),
              ),
            ),
          ],
        ),
        ...questions.map((q) {
          final indexInMainList = _exam.questions.indexOf(q);
          
          Widget titleWidget = Text(q.title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11));
          if (q.titleOrientation == QuestionTitleOrientation.verticalBottomToTop) titleWidget = RotatedBox(quarterTurns: 3, child: titleWidget);
          else if (q.titleOrientation == QuestionTitleOrientation.verticalTopToBottom) titleWidget = RotatedBox(quarterTurns: 1, child: titleWidget);

          final markUnit = isAr ? 'د' : 'm';
          final markText = q.mark > 0 ? (q.mark % 1 == 0 ? '${q.mark.toInt()} $markUnit' : '${q.mark} $markUnit') : '-';
          Widget markWidget = Text(markText, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11));
          if (q.gradeOrientation == GradeTextOrientation.verticalBottomToTop) markWidget = RotatedBox(quarterTurns: 3, child: markWidget);
          else if (q.gradeOrientation == GradeTextOrientation.verticalTopToBottom) markWidget = RotatedBox(quarterTurns: 1, child: markWidget);

          return TableRow(
            children: [
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: InkWell(
                  onTap: () => _openQuestionDialog(questionIndex: indexInMainList),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Center(child: titleWidget)),
                ),
              ),
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: InkWell(
                  onTap: () => _openQuestionDialog(questionIndex: indexInMainList),
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
                            decoration: BoxDecoration(color: Colors.blue.shade50, border: Border.all(color: Colors.blue.shade300), borderRadius: BorderRadius.circular(4)),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.check_circle_outline, size: 16, color: Colors.blue),
                                const SizedBox(width: 4),
                                Expanded(child: Text(isAr ? 'الإجابة النموذجية: ${q.answerKey}' : 'Model Answer: ${q.answerKey}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade900, fontFamily: isAr ? 'Amiri' : 'Arial'))),
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
                  onTap: () => _openQuestionDialog(questionIndex: indexInMainList),
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Center(child: markWidget)),
                ),
              ),
            ],
          );
        }),
      ],
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'الصف : ${_exam.header.grade}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.detailsFontSize + 1,
                        ),
                      ),
                      Text(
                        'الماده : ${_exam.header.subject}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.detailsFontSize + 1,
                        ),
                      ),
                      Text(
                        'التاريخ: ${_exam.header.examDate}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.detailsFontSize,
                        ),
                      ),
                      Text(
                        'الزمن: ${_exam.header.examTime}',
                        style: TextStyle(
                          fontFamily: _exam.header.detailsFont,
                          fontWeight: _exam.header.detailsBold ? FontWeight.bold : FontWeight.normal,
                          fontSize: _exam.header.detailsFontSize - 0.5,
                        ),
                      ),
                      Text(
                        'الفتره: ${_exam.header.period}',
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
        } else if (type == 'نها') {
          final v = parts.isNotEmpty ? parts[0] : (_isArabicExam ? 'س' : 'x');
          final t = parts.length > 1 ? parts[1] : (_isArabicExam ? '٠' : '0');
          final fn = parts.length > 2 ? parts[2] : '';
          final label = _isArabicExam ? 'نهـا' : 'lim';

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: baseStyle.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: (baseStyle.fontSize ?? 14) * 1.05,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              v,
                              style: baseStyle.copyWith(
                                fontSize: (baseStyle.fontSize ?? 14) * 0.7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.0),
                              child: CustomPaint(
                                size: const Size(8, 6),
                                painter: _LimitArrowPainter(color: baseStyle.color ?? Colors.black87),
                              ),
                            ),
                            Text(
                              t,
                              style: baseStyle.copyWith(
                                fontSize: (baseStyle.fontSize ?? 14) * 0.7,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (fn.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(
                        fn,
                        style: baseStyle.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'تباديل' || type == 'توافيق') {
          final n = parts.isNotEmpty ? parts[0] : (_isArabicExam ? 'ن' : 'n');
          final r = parts.length > 1 ? parts[1] : (_isArabicExam ? 'ر' : 'r');
          final sym = type == 'تباديل'
              ? (_isArabicExam ? 'ل' : 'P')
              : (_isArabicExam ? 'ق' : 'C');

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(n, style: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 14) * 0.75, fontWeight: FontWeight.bold)),
                    ),
                    Text(sym, style: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 14) * 1.25, fontWeight: FontWeight.bold)),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(r, style: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 14) * 0.75, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'مجموع' || type == 'تكامل') {
          final from = parts.isNotEmpty ? parts[0] : '';
          final to = parts.length > 1 ? parts[1] : '';
          final body = parts.length > 2 ? parts[2] : '';
          final sym = type == 'مجموع' ? (_isArabicExam ? 'مجـ' : '∑') : '∫';

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(to, style: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 14) * 0.65, fontWeight: FontWeight.bold)),
                        Text(sym, style: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 14) * 1.2, fontWeight: FontWeight.bold)),
                        Text(from, style: baseStyle.copyWith(fontSize: (baseStyle.fontSize ?? 14) * 0.65, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text(body, style: baseStyle.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'متجه') {
          final symbol = parts.isNotEmpty ? parts[0] : (_isArabicExam ? 'ق' : 'v');
          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('→', style: TextStyle(fontSize: 10, height: 0.8, fontWeight: FontWeight.bold)),
                  Text(symbol, style: baseStyle.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        } else if (type == 'بار') {
          final symbol = parts.isNotEmpty ? parts[0] : (_isArabicExam ? 'س' : 'x');
          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 1.2, color: baseStyle.color ?? Colors.black87),
                  Text(symbol, style: baseStyle.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        } else if (type == 'محدد' || type == 'مصفوفة') {
          final isMatrix = type == 'مصفوفة';
          final a = parts.isNotEmpty ? parts[0] : '';
          final b = parts.length > 1 ? parts[1] : '';
          final c = parts.length > 2 ? parts[2] : '';
          final d = parts.length > 3 ? parts[3] : '';

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  border: isMatrix
                      ? Border(
                          left: BorderSide(color: baseStyle.color ?? Colors.black87, width: 1.5),
                          right: BorderSide(color: baseStyle.color ?? Colors.black87, width: 1.5),
                        )
                      : Border(
                          left: BorderSide(color: baseStyle.color ?? Colors.black87, width: 1.2),
                          right: BorderSide(color: baseStyle.color ?? Colors.black87, width: 1.2),
                        ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [Text(a, style: baseStyle), const SizedBox(width: 8), Text(b, style: baseStyle)]),
                    Row(mainAxisSize: MainAxisSize.min, children: [Text(c, style: baseStyle), const SizedBox(width: 8), Text(d, style: baseStyle)]),
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'عمودي') {
          final op = parts.isNotEmpty ? parts[0] : '+';
          final numbers = parts.length > 1 ? parts.sublist(1) : <String>[];

          int maxDigits = 0;
          for (final num in numbers) {
            if (num.length > maxDigits) maxDigits = num.length;
          }
          final double lineWidth = (maxDigits * 8.0) + 20.0;
          final bool isRtlVert = _isArabicExam;

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
                child: Directionality(
                  textDirection: isRtlVert ? TextDirection.rtl : TextDirection.ltr,
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...numbers.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final val = entry.value;
                          final isLast = idx == numbers.length - 1;

                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                child: isLast
                                    ? Text(
                                        op,
                                        textAlign: TextAlign.center,
                                        style: baseStyle.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: (baseStyle.fontSize ?? 14) * 1.15,
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  val,
                                  textAlign: isRtlVert ? TextAlign.right : TextAlign.left,
                                  style: baseStyle.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: (baseStyle.fontSize ?? 14) * 1.1,
                                    letterSpacing: 2.0,
                                    fontFamily: isRtlVert ? 'Amiri' : 'Arial',
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                        Container(
                          margin: const EdgeInsets.only(top: 3.0, bottom: 6.0),
                          width: lineWidth,
                          height: 1.5,
                          color: baseStyle.color ?? Colors.black87,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        } else if (type == 'قسمة' || type == 'div') {
          final bool isRtl = (type == 'قسمة') && _isArabicExam;
          final String dividend = parts.isNotEmpty ? parts[0] : '';
          final String divisor = parts.length > 1 ? parts[1] : '';
          final String quotient = parts.length > 2 ? parts[2] : '';

          children.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                child: Directionality(
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (quotient.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                            right: isRtl ? 22.0 : 0.0,
                            left: !isRtl ? 22.0 : 0.0,
                          ),
                          child: Text(
                            quotient,
                            style: baseStyle.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: (baseStyle.fontSize ?? 14) * 0.9,
                            ),
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            divisor,
                            style: baseStyle.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: baseStyle.fontSize,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: const BorderSide(color: Colors.black87, width: 1.5),
                                right: isRtl ? const BorderSide(color: Colors.black87, width: 1.5) : BorderSide.none,
                                left: !isRtl ? const BorderSide(color: Colors.black87, width: 1.5) : BorderSide.none,
                              ),
                            ),
                            padding: const EdgeInsets.only(top: 2.0, left: 6.0, right: 6.0, bottom: 2.0),
                            child: Text(
                              dividend,
                              style: baseStyle.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: baseStyle.fontSize,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ],
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
    final TextDirection contentDirection = (chosenAlign == TextAlign.left || !_isArabicExam)
        ? TextDirection.ltr
        : TextDirection.rtl;

    if (!q.isTwoColumns) {
      return Directionality(
        textDirection: contentDirection,
        child: Text.rich(
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
        ),
      );
    }

    final lines = fullText.split('\n').where((l) => l.trim().isNotEmpty).toList();

    if (lines.length <= 1) {
      return Directionality(
        textDirection: contentDirection,
        child: Text.rich(
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
        ),
      );
    }

    final intro = lines.first;
    final items = lines.sublist(1);
    final int half = (items.length / 2).ceil();
    final col1 = items.sublist(0, half);
    final col2 = items.sublist(half);

    final defaultFont = _isArabicExam ? 'Amiri' : 'Arial';
    final introStyle = TextStyle(
      fontFamily: q.spans.isNotEmpty ? q.spans.first.fontFamily : defaultFont,
      fontWeight: FontWeight.bold,
      fontSize: q.spans.isNotEmpty ? q.spans.first.fontSize : 14.0,
      height: 1.5,
    );

    final itemStyle = TextStyle(
      fontFamily: q.spans.isNotEmpty ? q.spans.first.fontFamily : defaultFont,
      fontSize: q.spans.isNotEmpty ? q.spans.first.fontSize : 13.0,
      height: 1.4,
    );

    return Directionality(
      textDirection: contentDirection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text.rich(
            _buildInlineSpanWithFractions(intro, introStyle),
            textAlign: chosenAlign,
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: col1.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text.rich(
                      _buildInlineSpanWithFractions(item, itemStyle),
                      textAlign: chosenAlign,
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: col2.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text.rich(
                      _buildInlineSpanWithFractions(item, itemStyle),
                      textAlign: chosenAlign,
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
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
                                    left: (isAr && idx > 0)
                                        ? const BorderSide(color: Colors.black87, width: 0.8)
                                        : BorderSide.none,
                                    right: (!isAr && idx > 0)
                                        ? const BorderSide(color: Colors.black87, width: 0.8)
                                        : BorderSide.none,
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
                                          style: const TextStyle(
                                            color: Colors.black87,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
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
    final bool isSelected = _selectedElementId == el.id;

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
        coreWidget = _renderMathOperation(el.content);
        break;
      case ElementType.table:
        coreWidget = _renderCustomTable(el.content);
        break;
      case ElementType.shape:
        coreWidget = _renderCustomShape(el.content, el.width, el.height);
        break;
    }

    if (el.type == ElementType.shape || el.type == ElementType.table) {
      return Transform.translate(
        offset: Offset(el.dx, el.dy),
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedElementId = isSelected ? null : el.id;
            });
          },
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: el.width,
                height: el.type == ElementType.shape ? el.height : null,
                decoration: BoxDecoration(
                  border: isSelected
                      ? Border.all(color: const Color(0xFF1976D2), width: 1.5)
                      : null,
                ),
                child: coreWidget,
              ),

              if (isSelected) ...[
                Positioned(
                  top: -34,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        el.dx += details.delta.dx;
                        el.dy += details.delta.dy;
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1976D2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                        ],
                      ),
                      child: const Icon(Icons.open_with, color: Colors.white, size: 18),
                    ),
                  ),
                ),

                _buildWordResizeHandle(
                  top: -6,
                  left: -6,
                  onPan: (delta) {
                    setState(() {
                      el.width = (el.width - delta.dx).clamp(50.0, 500.0);
                      el.height = (el.height - delta.dy).clamp(30.0, 400.0);
                      el.dx += delta.dx;
                      el.dy += delta.dy;
                    });
                  },
                ),
                _buildWordResizeHandle(
                  top: -6,
                  right: -6,
                  onPan: (delta) {
                    setState(() {
                      el.width = (el.width + delta.dx).clamp(50.0, 500.0);
                      el.height = (el.height - delta.dy).clamp(30.0, 400.0);
                      el.dy += delta.dy;
                    });
                  },
                ),
                _buildWordResizeHandle(
                  bottom: -6,
                  left: -6,
                  onPan: (delta) {
                    setState(() {
                      el.width = (el.width - delta.dx).clamp(50.0, 500.0);
                      el.height = (el.height + delta.dy).clamp(30.0, 400.0);
                      el.dx += delta.dx;
                    });
                  },
                ),
                _buildWordResizeHandle(
                  bottom: -6,
                  right: -6,
                  onPan: (delta) {
                    setState(() {
                      el.width = (el.width + delta.dx).clamp(50.0, 500.0);
                      el.height = (el.height + delta.dy).clamp(30.0, 400.0);
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: coreWidget,
    );
  }

  Widget _buildWordResizeHandle({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required Function(Offset delta) onPan,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: GestureDetector(
        onPanUpdate: (details) => onPan(details.delta),
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFF1976D2), width: 1.8),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _renderCustomTable(String jsonStr) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final int rows = (data['rows'] as num?)?.toInt() ?? 2;
      final int cols = (data['cols'] as num?)?.toInt() ?? 2;
      final bool hasHeader = data['hasHeader'] ?? true;
      final List<dynamic> rawGrid = data['data'] ?? [];

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Table(
          border: TableBorder.all(color: Colors.black87, width: 1.0),
          children: List.generate(rows, (r) {
            final isHeaderRow = (r == 0 && hasHeader);
            return TableRow(
              decoration: BoxDecoration(
                color: isHeaderRow ? Colors.grey.shade200 : Colors.white,
              ),
              children: List.generate(cols, (c) {
                String text = '';
                if (r < rawGrid.length && c < (rawGrid[r] as List).length) {
                  text = rawGrid[r][c]?.toString() ?? '';
                }
                return TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                    child: Text(
                      text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: isHeaderRow ? FontWeight.bold : FontWeight.normal,
                        fontSize: isHeaderRow ? 12 : 11,
                        fontFamily: _isArabicExam ? 'Amiri' : 'Arial',
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
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

  Widget _renderMathOperation(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      final kind = data['kind'] ?? 'vertical';

      if (kind == 'vertical') {
        final List<dynamic> rows = data['rows'] ?? [];
        final String op = data['operator'] ?? '+';
        final bool opOnRight = data['opOnRight'] ?? _isArabicExam;

        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...rows.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final val = entry.value.toString();
                  final isLastRow = idx == rows.length - 1;

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!opOnRight && isLastRow)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(op, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      Text(
                        val,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          fontFamily: _isArabicExam ? 'Amiri' : 'Arial',
                        ),
                        textAlign: TextAlign.left,
                      ),
                      if (opOnRight && isLastRow)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(op, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  );
                }),
                const SizedBox(height: 2),
                Container(
                  width: 90,
                  height: 1.5,
                  color: Colors.black87,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      } else if (kind == 'fraction') {
        final numVal = data['num'] ?? '';
        final denVal = data['den'] ?? '';
        return Center(
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    numVal,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  height: 1.5,
                  color: Colors.black,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    denVal,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (_) {}
    return const SizedBox.shrink();
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
                _measurePagesHeight();
              },
              child: const Text('تطبيق الأبعاد'),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuestionTemplatesDialog() {
    final isAr = _isArabicExam;

    final templates = isAr
        ? [
            {
              'title': 'ضع علامة (✔) أو (✘)',
              'subtitle': 'توجيه صح وخطأ مع ٤ فقرات وأقواس في البداية',
              'qTitle': 'السؤال ${_exam.questions.length + 1}',
              'content':
                  'ضع علامة (✔) أمام العبارة الصحيحة وعلامة (✘) أمام العبارة الخطأ فيما يأتي:\n'
                  '١ - (   ) .\n'
                  '٢ - (   ) .\n'
                  '٣ - (   ) .\n'
                  '٤ - (   ) .',
              'mark': 8.0,
              'answer': '١- (✔)   ٢- (✘)   ٣- (✔)   ٤- (✔)',
              'twoCols': false,
            },
            {
              'title': 'اختر الإجابة الصحيحة (عمودان)',
              'subtitle': 'توجيه اختيارات في عمودين متجاورين لتوفير الورق',
              'qTitle': 'السؤال ${_exam.questions.length + 1}',
              'content':
                  'اختر الإجابة الصحيحة من بين الأقواس لما يأتي:\n'
                  '١ - ............ [ أ- .. ، ب- .. ]\n'
                  '٢ - ............ [ أ- .. ، ب- .. ]\n'
                  '٣ - ............ [ أ- .. ]\n'
                  '٤ - ............ [ أ- .. ، ب- .. ]',
              'mark': 8.0,
              'answer': '١- أ   ٢- ب   ٣- أ   ٤- ب',
              'twoCols': true,
            },
            {
              'title': 'علل لما يأتي / اذكر السبب',
              'subtitle': 'فقرات تعليل مع أسطر إجابة',
              'qTitle': 'السؤال ${_exam.questions.length + 1}',
              'content':
                  'علل لما يأتي (اذكر السبب):\n'
                  '١ - ....\n'
                  'جـ/ ....\n'
                  '٢ - ....\n'
                  'جـ/ ....',
              'mark': 6.0,
              'answer': '١- بسبب ...................   ٢- نتيجة لـ ...................',
              'twoCols': false,
            },
            {
              'title': 'أكمل الفراغات الآتية',
              'subtitle': 'جمل بكلمات ناقصة وأسطر منقطة',
              'qTitle': 'السؤال ${_exam.questions.length + 1}',
              'content':
                  'أكمل الفراغات الآتية بما يناسبها:\n'
                  '١ - ....\n'
                  '٢ - ....\n'
                  '٣ - ....',
              'mark': 6.0,
              'answer': '١- ...........   ٢- ...........   ٣- ...........',
              'twoCols': false,
            },
          ]
        : [
            {
              'title': 'Mark True (✔) or False (✘)',
              'subtitle': 'True/False items with leading brackets',
              'qTitle': 'Question ${_exam.questions.length + 1}',
              'content':
                  'Write (✔) for true statements and (✘) for false statements:\n'
                  '1 - (   ) .\n'
                  '2 - (   ) .\n'
                  '3 - (   ) .\n'
                  '4 - (   ) .',
              'mark': 8.0,
              'answer': '1- (✔)   2- (✘)   3- (✔)   4- (✔)',
              'twoCols': false,
            },
            {
              'title': 'Choose the Correct Answer (Two Columns)',
              'subtitle': 'Multiple choices formatted into 2 columns',
              'qTitle': 'Question ${_exam.questions.length + 1}',
              'content':
                  'Choose the correct answer between brackets:\n'
                  '1 - ............ [ A- .. , B- .. ]\n'
                  '2 - ............ [ A- .. , B- .. ]\n'
                  '3 - ............ [ A- .. , B- .. ]\n'
                  '4 - ............ [ A- .. , B- .. ]\n',
              'mark': 8.0,
              'answer': '1- A   2- B   3- A   4- B',
              'twoCols': true,
            },
            {
              'title': 'Give reasons for the following',
              'subtitle': 'Reasoning questions with response lines',
              'qTitle': 'Question ${_exam.questions.length + 1}',
              'content':
                  'Give clear reasons for each of the following:\n'
                  '1 - ....\n'
                  'Ans/ ....\n'
                  '2 - ....\n'
                  'Ans/ ....',
              'mark': 6.0,
              'answer': '1- Because ...................   2- Due to ...................',
              'twoCols': false,
            },
            {
              'title': 'Complete the sentences',
              'subtitle': 'Fill-in-the-blank sentences',
              'qTitle': 'Question ${_exam.questions.length + 1}',
              'content':
                  'Complete each sentence with the suitable word:\n'
                  '1 - ....\n'
                  '2 - ....\n'
                  '3 - ....',
              'mark': 6.0,
              'answer': '1- ...........   2- ...........   3- ...........',
              'twoCols': false,
            },
          ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF1E3A8A)),
                const SizedBox(width: 8),
                Text(
                  isAr ? 'قوالب الأسئلة الجاهزة' : 'Question Templates',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: templates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final t = templates[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
                    ),
                    title: Text(t['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text(t['subtitle'] as String, style: const TextStyle(fontSize: 11)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                    onTap: () {
                      final newQ = QuestionModel(
                        id: const Uuid().v4(),
                        title: t['qTitle'] as String,
                        titleOrientation: QuestionTitleOrientation.horizontal,
                        gradeOrientation: GradeTextOrientation.horizontal,
                        mark: (t['mark'] as num).toDouble(),
                        spans: [
                          TextSpanModel(
                            text: t['content'] as String,
                            fontSize: 14.0,
                            fontFamily: isAr ? 'Amiri' : 'Arial',
                          )
                        ],
                        answerKey: t['answer'] as String,
                        isTwoColumns: t['twoCols'] as bool,
                        alignment: isAr ? TextAlign.right : TextAlign.left,
                      );
                      setState(() {
                        _exam.questions.add(newQ);
                      });
                      Navigator.pop(ctx);
                      _measurePagesHeight();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تمت إضافة ${t['title']} بنجاح'),
                          backgroundColor: Colors.green.shade700,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // نافذة إدخال وتعديل السؤال مع تتبع التحديد والحافظة وتباعد الأسطر
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

    TextSelection? lastSelection;
    bool isTextSelected = false;
    bool hasClipboardContent = false;
    double currentLineSpacing = 1.5;

    Clipboard.hasStrings().then((hasVal) {
      hasClipboardContent = hasVal;
    });

    final titleCtrl = TextEditingController(text: q.title);
    final textCtrl =
        TextEditingController(text: q.spans.map((e) => e.text).join(''));
    final markCtrl =
        TextEditingController(text: q.mark > 0 ? (q.mark % 1 == 0 ? q.mark.toInt().toString() : q.mark.toString()) : '5');
    final answerCtrl = TextEditingController(text: q.answerKey);
    QuestionTitleOrientation orientation = q.titleOrientation;
    GradeTextOrientation gradeOrient = q.gradeOrientation;
    bool isTwoCols = q.isTwoColumns;
    List<InsertableElement> currentElements = List.from(q.elements);

    TextAlign selectedAlignment = q.alignment ?? (isAr ? TextAlign.right : TextAlign.left);
    bool isInputArabic = isAr;

    bool showCustomKeyboard = true;
    bool useSystemKeyboard = false;
    TextEditingController activeFieldController = textCtrl;
    bool showQuestionSettings = true;

    final defaultFont = isAr ? 'Amiri' : 'Arial';
    List<TextSpanModel> workingSpans = q.spans.isNotEmpty
        ? q.spans.map((s) => TextSpanModel(
              text: s.text,
              isBold: s.isBold,
              isUnderline: s.isUnderline,
              fontSize: s.fontSize,
              fontFamily: s.fontFamily,
              colorHex: s.colorHex,
            )).toList()
        : [
            TextSpanModel(
              text: textCtrl.text,
              fontSize: 14.0,
              fontFamily: defaultFont,
              colorHex: '#000000',
            )
          ];

    String currentFont = q.spans.isNotEmpty ? q.spans.first.fontFamily : defaultFont;
    double currentFontSize = 14.0;
    bool isBoldActive = false;
    bool isUnderlineActive = false;
    String currentColor = '#000000';

    void _rebuildSpansWithInsertedText(int offset, String inserted, TextSpanModel template) {
      if (textCtrl.text.isEmpty) {
        workingSpans = [
          TextSpanModel(
            text: inserted,
            colorHex: template.colorHex,
            fontFamily: template.fontFamily,
            fontSize: template.fontSize,
            isBold: template.isBold,
            isUnderline: template.isUnderline,
          )
        ];
        return;
      }
      List<TextSpanModel> nextSpans = [];
      int currentOffset = 0;
      bool handled = false;

      for (final span in workingSpans) {
        final String spanText = span.text;
        final int spanLen = spanText.length;
        final int spanEnd = (currentOffset + spanLen).toInt();

        if (!handled && offset >= currentOffset && offset <= spanEnd) {
          final int rel = (offset - currentOffset).toInt();
          final String before = spanText.substring(0, rel);
          final String after = spanText.substring(rel);

          if (before.isNotEmpty) {
            nextSpans.add(TextSpanModel(
              text: before,
              colorHex: span.colorHex,
              fontFamily: span.fontFamily,
              fontSize: span.fontSize,
              isBold: span.isBold,
              isUnderline: span.isUnderline,
            ));
          }
          nextSpans.add(TextSpanModel(
            text: inserted,
            colorHex: template.colorHex,
            fontFamily: template.fontFamily,
            fontSize: template.fontSize,
            isBold: template.isBold,
            isUnderline: template.isUnderline,
          ));
          if (after.isNotEmpty) {
            nextSpans.add(TextSpanModel(
              text: after,
              colorHex: span.colorHex,
              fontFamily: span.fontFamily,
              fontSize: span.fontSize,
              isBold: span.isBold,
              isUnderline: span.isUnderline,
            ));
          }
          handled = true;
        } else {
          nextSpans.add(span);
        }
        currentOffset = spanEnd.toInt();
      }

      if (!handled) {
        nextSpans.add(TextSpanModel(
          text: inserted,
          colorHex: template.colorHex,
          fontFamily: template.fontFamily,
          fontSize: template.fontSize,
          isBold: template.isBold,
          isUnderline: template.isUnderline,
        ));
      }
      workingSpans = nextSpans.where((s) => s.text.isNotEmpty).toList();
    }

    void insertAtCursor(String symbol) {
      final target = activeFieldController;
      final pos = target.selection.start;
      final end = target.selection.end;

      if (target == textCtrl) {
        final activeSpan = TextSpanModel(
          text: symbol,
          colorHex: currentColor,
          fontFamily: currentFont,
          fontSize: currentFontSize,
          isBold: isBoldActive,
          isUnderline: isUnderlineActive,
        );

        if (pos >= 0) {
          target.text = target.text.replaceRange(pos, end, symbol);
          target.selection = TextSelection.collapsed(offset: pos + symbol.length);
          _rebuildSpansWithInsertedText(pos, symbol, activeSpan);
        } else {
          final insertPos = target.text.length;
          target.text += symbol;
          target.selection = TextSelection.collapsed(offset: target.text.length);
          _rebuildSpansWithInsertedText(insertPos, symbol, activeSpan);
        }
      } else {
        if (pos >= 0) {
          target.text = target.text.replaceRange(pos, end, symbol);
          target.selection = TextSelection.collapsed(offset: pos + symbol.length);
        } else {
          target.text += symbol;
        }
      }
    }

    void applyFormatToSelection({
      bool? bold,
      bool? underline,
      String? font,
      double? size,
      String? color,
    }) {
      if (bold != null) isBoldActive = bold;
      if (underline != null) isUnderlineActive = underline;
      if (font != null) currentFont = font;
      if (size != null) currentFontSize = size;
      if (color != null) currentColor = color;

      final sel = lastSelection ?? textCtrl.selection;
      if (!sel.isValid || sel.isCollapsed || sel.start == sel.end) {
        return;
      }

      final fullText = textCtrl.text;
      final int selStart = sel.start < sel.end ? sel.start : sel.end;
      final int selEnd = sel.start < sel.end ? sel.end : sel.start;

      List<TextSpanModel> newSpans = [];
      int currentPos = 0;

      for (var span in workingSpans) {
        final String spanText = span.text;
        final int spanLen = spanText.length;
        final int spanStart = currentPos;
        final int spanEnd = (currentPos + spanLen).toInt();

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
              colorHex: span.colorHex,
            ));
          }

          final int overlapStart = spanStart > selStart ? spanStart : selStart;
          final int overlapEnd = spanEnd < selEnd ? spanEnd : selEnd;

          newSpans.add(TextSpanModel(
            text: fullText.substring(overlapStart, overlapEnd),
            isBold: bold ?? span.isBold,
            isUnderline: underline ?? span.isUnderline,
            fontSize: size ?? span.fontSize,
            fontFamily: font ?? span.fontFamily,
            colorHex: color ?? span.colorHex,
          ));

          if (spanEnd > selEnd) {
            newSpans.add(TextSpanModel(
              text: fullText.substring(selEnd, spanEnd),
              isBold: span.isBold,
              isUnderline: span.isUnderline,
              fontSize: span.fontSize,
              fontFamily: span.fontFamily,
              colorHex: span.colorHex,
            ));
          }
        }
        currentPos = spanEnd.toInt();
      }

      workingSpans = newSpans.where((s) => s.text.isNotEmpty).toList();
    }

    void showAdvancedEquationDialog(void Function(void Function()) setParentState) {
      String eqType = isAr ? 'نها' : 'نها';
      final f1Ctrl = TextEditingController(text: isAr ? 'س' : 'x');
      final f2Ctrl = TextEditingController(text: isAr ? '٠' : '0');
      final f3Ctrl = TextEditingController(text: isAr ? '٢س' : '2x');
      final f4Ctrl = TextEditingController(text: '');

      showDialog(
        context: context,
        builder: (dCtx) => StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.functions, color: Color(0xFF1E3A8A)),
                SizedBox(width: 8),
                Text('إدراج معادلة رياضية / فيزيائية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: eqType,
                    decoration: const InputDecoration(labelText: 'نوع الصيغة أو العملية', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'نها', child: Text('نهاية دالة (نهـا / lim)')),
                      DropdownMenuItem(value: 'تباديل', child: Text('تباديل (ن ل ر / nPr)')),
                      DropdownMenuItem(value: 'توافيق', child: Text('توافيق (ن ق ر / nCr)')),
                      DropdownMenuItem(value: 'مجموع', child: Text('رمز المجموع (مجـ / Σ)')),
                      DropdownMenuItem(value: 'تكامل', child: Text('تكامل محدود (∫)')),
                      DropdownMenuItem(value: 'متجه', child: Text('متجه فيزيائي (← علوي)')),
                      DropdownMenuItem(value: 'بار', child: Text('متوسط حسابي (شَرطة علوية ¯)')),
                      DropdownMenuItem(value: 'محدد', child: Text('محدد ثنائي 2×2 (| |)')),
                      DropdownMenuItem(value: 'مصفوفة', child: Text('مصفوفة ثنائية 2×2 ([ ])')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setDState(() {
                          eqType = v;
                          if (v == 'نها') { f1Ctrl.text = isAr ? 'س' : 'x'; f2Ctrl.text = isAr ? '٠' : '0'; f3Ctrl.text = isAr ? '٢س' : '2x'; }
                          if (v == 'تباديل') { f1Ctrl.text = isAr ? '٧' : '7'; f2Ctrl.text = isAr ? '٣' : '3'; }
                          if (v == 'توافيق') { f1Ctrl.text = isAr ? '١٠' : '10'; f2Ctrl.text = isAr ? '٤' : '4'; }
                          if (v == 'مجموع') { f1Ctrl.text = isAr ? 'ر=١' : 'r=1'; f2Ctrl.text = isAr ? '٥' : '5'; f3Ctrl.text = isAr ? 'ر²' : 'r²'; }
                          if (v == 'تكامل') { f1Ctrl.text = isAr ? '٠' : '0'; f2Ctrl.text = isAr ? '٣' : '3'; f3Ctrl.text = isAr ? 'س² د(س)' : 'x² dx'; }
                          if (v == 'متجه') { f1Ctrl.text = isAr ? 'ق' : 'v'; }
                          if (v == 'بار') { f1Ctrl.text = isAr ? 'س' : 'x'; }
                          if (v == 'محدد' || v == 'مصفوفة') { f1Ctrl.text = '2'; f2Ctrl.text = '3'; f3Ctrl.text = '1'; f4Ctrl.text = '4'; }
                        });
                      }
                    },
                  ),
                  const Divider(height: 20),
                  if (eqType == 'نها') ...[
                    TextField(controller: f1Ctrl, decoration: const InputDecoration(labelText: 'المتغير')),
                    const SizedBox(height: 6),
                    TextField(controller: f2Ctrl, decoration: const InputDecoration(labelText: 'يؤول إلى')),
                    const SizedBox(height: 6),
                    TextField(controller: f3Ctrl, decoration: const InputDecoration(labelText: 'الدالة')),
                  ] else if (eqType == 'تباديل' || eqType == 'توافيق') ...[
                    TextField(controller: f1Ctrl, decoration: const InputDecoration(labelText: 'العدد الكلي / العلم (ن)')),
                    const SizedBox(height: 6),
                    TextField(controller: f2Ctrl, decoration: const InputDecoration(labelText: 'المأخوذ / الدليل (ر)')),
                  ] else if (eqType == 'مجموع' || eqType == 'تكامل') ...[
                    TextField(controller: f1Ctrl, decoration: const InputDecoration(labelText: 'حد البداية / الأدنى (بالأسفل)')),
                    const SizedBox(height: 6),
                    TextField(controller: f2Ctrl, decoration: const InputDecoration(labelText: 'حد النهاية / الأعلى (بالأعلى)')),
                    const SizedBox(height: 6),
                    TextField(controller: f3Ctrl, decoration: const InputDecoration(labelText: 'المقدار المراد حسابه')),
                  ] else if (eqType == 'متجه' || eqType == 'بار') ...[
                    TextField(controller: f1Ctrl, decoration: const InputDecoration(labelText: 'اسم الرمز أو الكمية')),
                  ] else if (eqType == 'محدد' || eqType == 'مصفوفة') ...[
                    Row(children: [
                      Expanded(child: TextField(controller: f1Ctrl, decoration: const InputDecoration(labelText: 'صف١ عمود١'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: f2Ctrl, decoration: const InputDecoration(labelText: 'صف١ عمود٢'))),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: TextField(controller: f3Ctrl, decoration: const InputDecoration(labelText: 'صف٢ عمود١'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: f4Ctrl, decoration: const InputDecoration(labelText: 'صف٢ عمود٢'))),
                    ]),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () {
                  String tag = '';
                  if (eqType == 'تباديل' || eqType == 'توافيق') {
                    tag = '[$eqType:${f1Ctrl.text.trim()}:${f2Ctrl.text.trim()}]';
                  } else if (eqType == 'متجه' || eqType == 'بار') {
                    tag = '[$eqType:${f1Ctrl.text.trim()}]';
                  } else if (eqType == 'محدد' || eqType == 'مصفوفة') {
                    tag = '[$eqType:${f1Ctrl.text.trim()}:${f2Ctrl.text.trim()}:${f3Ctrl.text.trim()}:${f4Ctrl.text.trim()}]';
                  } else {
                    tag = '[$eqType:${f1Ctrl.text.trim()}:${f2Ctrl.text.trim()}:${f3Ctrl.text.trim()}]';
                  }
                  setParentState(() => insertAtCursor(' $tag '));
                  Navigator.pop(dCtx);
                },
                child: const Text('إدراج عند المؤشر'),
              ),
            ],
          ),
        ),
      );
    }

    void showVerticalMathDialog(void Function(void Function()) setParentState) {
      int rowCount = 2;
      String op = '×';
      final r1Ctrl = TextEditingController(text: isAr ? '٥٣٤' : '534');
      final r2Ctrl = TextEditingController(text: isAr ? '٢٦' : '26');
      final r3Ctrl = TextEditingController(text: '');
      final r4Ctrl = TextEditingController(text: '');

      showDialog(
        context: context,
        builder: (dCtx) => StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: const Text('إدراج جمع / طرح / ضرب عمودي عند المؤشر'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('عدد الصفوف: '),
                      DropdownButton<int>(
                        value: rowCount,
                        items: [2, 3, 4]
                            .map((n) => DropdownMenuItem(value: n, child: Text('$n صفوف')))
                            .toList(),
                        onChanged: (v) => setDState(() => rowCount = v!),
                      ),
                      const Spacer(),
                      const Text('العملية: '),
                      DropdownButton<String>(
                        value: op,
                        items: ['+', '-', '×']
                            .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))))
                            .toList(),
                        onChanged: (v) => setDState(() => op = v!),
                      ),
                    ],
                  ),
                  const Divider(),
                  TextField(controller: r1Ctrl, decoration: const InputDecoration(labelText: 'العدد الأول (الصف الأعلى)')),
                  TextField(controller: r2Ctrl, decoration: const InputDecoration(labelText: 'العدد الثاني')),
                  if (rowCount >= 3)
                    TextField(controller: r3Ctrl, decoration: const InputDecoration(labelText: 'العدد الثالث')),
                  if (rowCount >= 4)
                    TextField(controller: r4Ctrl, decoration: const InputDecoration(labelText: 'العدد الرابع')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () {
                  final List<String> list = [r1Ctrl.text.trim(), r2Ctrl.text.trim()];
                  if (rowCount >= 3 && r3Ctrl.text.trim().isNotEmpty) list.add(r3Ctrl.text.trim());
                  if (rowCount >= 4 && r4Ctrl.text.trim().isNotEmpty) list.add(r4Ctrl.text.trim());

                  final tag = '[عمودي:$op:${list.join(':')}]';
                  setParentState(() {
                    insertAtCursor(' $tag ');
                  });
                  Navigator.pop(dCtx);
                },
                child: const Text('إدراج عند المؤشر'),
              ),
            ],
          ),
        ),
      );
    }

    void showLongDivisionDialog(void Function(void Function()) setParentState) {
      final dividendCtrl = TextEditingController(text: isAr ? '٨٤٦' : '846');
      final divisorCtrl = TextEditingController(text: isAr ? '٢' : '2');
      final quotientCtrl = TextEditingController(text: '');
      bool divIsArabic = isAr;

      showDialog(
        context: context,
        builder: (dCtx) => StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: const Text('إدراج كرسي قسمة مطولة عند المؤشر'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('الاتجاه: '),
                    ChoiceChip(
                      label: const Text('عربي (يمين)'),
                      selected: divIsArabic,
                      onSelected: (v) => setDState(() => divIsArabic = true),
                    ),
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: const Text('إنجليزي (يسار)'),
                      selected: !divIsArabic,
                      onSelected: (v) => setDState(() => divIsArabic = false),
                    ),
                  ],
                ),
                const Divider(),
                TextField(
                  controller: dividendCtrl,
                  decoration: const InputDecoration(labelText: 'المقسوم (داخل الكرسي)'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: divisorCtrl,
                  decoration: const InputDecoration(labelText: 'المقسوم عليه (خارج الكرسي)'),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: quotientCtrl,
                  decoration: const InputDecoration(labelText: 'ناتج القسمة فوق الكرسي (اختياري)'),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () {
                  final dividend = dividendCtrl.text.trim();
                  final divisor = divisorCtrl.text.trim();
                  final quotient = quotientCtrl.text.trim();
                  final type = divIsArabic ? 'قسمة' : 'div';
                  final tag = quotient.isNotEmpty
                      ? '[$type:$dividend:$divisor:$quotient]'
                      : '[$type:$dividend:$divisor]';

                  setParentState(() {
                    insertAtCursor(' $tag ');
                  });
                  Navigator.pop(dCtx);
                },
                child: const Text('إدراج عند المؤشر'),
              ),
            ],
          ),
        ),
      );
    }

    void showTableDesignerDialog(void Function(void Function()) setParentState, {InsertableElement? existingElement}) {
      int rowCount = 3;
      int colCount = 3;
      bool hasHeader = true;
      List<List<TextEditingController>> controllers = [];

      if (existingElement != null && existingElement.type == ElementType.table) {
        try {
          final Map<String, dynamic> data = jsonDecode(existingElement.content);
          rowCount = (data['rows'] as num?)?.toInt() ?? 3;
          colCount = (data['cols'] as num?)?.toInt() ?? 3;
          hasHeader = data['hasHeader'] ?? true;
          final List<dynamic> gridData = data['data'] ?? [];

          controllers = List.generate(rowCount, (r) {
            return List.generate(colCount, (c) {
              String val = '';
              if (r < gridData.length && c < (gridData[r] as List).length) {
                val = gridData[r][c]?.toString() ?? '';
              }
              return TextEditingController(text: val);
            });
          });
        } catch (_) {}
      }

      if (controllers.isEmpty) {
        controllers = List.generate(rowCount, (_) => List.generate(colCount, (_) => TextEditingController()));
      }

      void resizeControllers(int newRows, int newCols) {
        List<List<TextEditingController>> newGrid = [];
        for (int r = 0; r < newRows; r++) {
          List<TextEditingController> row = [];
          for (int c = 0; c < newCols; c++) {
            if (r < controllers.length && c < controllers[r].length) {
              row.add(controllers[r][c]);
            } else {
              row.add(TextEditingController());
            }
          }
          newGrid.add(row);
        }
        controllers = newGrid;
        rowCount = newRows;
        colCount = newCols;
      }

      showDialog(
        context: context,
        builder: (dCtx) => StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.table_chart, color: Color(0xFF1E3A8A)),
                SizedBox(width: 8),
                Text('تصميم وإعداد أبعاد الجدول', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text('الصفوف: '),
                        DropdownButton<int>(
                          value: rowCount,
                          items: List.generate(8, (i) => i + 1)
                              .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDState(() => resizeControllers(v, colCount));
                          },
                        ),
                        const SizedBox(width: 14),
                        const Text('الأعمدة: '),
                        DropdownButton<int>(
                          value: colCount,
                          items: List.generate(5, (i) => i + 1)
                              .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setDState(() => resizeControllers(rowCount, v));
                          },
                        ),
                        const Spacer(),
                        FilterChip(
                          label: const Text('صف ترويسة', style: TextStyle(fontSize: 11)),
                          selected: hasHeader,
                          onSelected: (v) => setDState(() => hasHeader = v),
                        ),
                      ],
                    ),
                    const Divider(),
                    const Text('ملاحظة: يمكنك إدخال وتعديل نصوص الجدول مباشرة من شاشة تحرير السؤال دون الحاجة لفتح هذا الحوار.',
                        style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                icon: const Icon(Icons.check, color: Colors.white, size: 18),
                label: const Text('تأكيد وإدراج الجدول', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  final List<List<String>> tableData = List.generate(rowCount, (r) {
                    return List.generate(colCount, (c) => controllers[r][c].text.trim());
                  });

                  final jsonPayload = jsonEncode({
                    'rows': rowCount,
                    'cols': colCount,
                    'hasHeader': hasHeader,
                    'data': tableData,
                  });

                  setParentState(() {
                    if (existingElement != null) {
                      existingElement.content = jsonPayload;
                    } else {
                      currentElements.add(InsertableElement(
                        id: const Uuid().v4(),
                        type: ElementType.table,
                        content: jsonPayload,
                        width: 320,
                        height: 120,
                      ));
                    }
                  });
                  Navigator.pop(dCtx);
                },
              ),
            ],
          ),
        ),
      );
    }

    void showShapeDesignerDialog(void Function(void Function()) setParentState, {InsertableElement? existingElement}) {
      String shapeKind = 'rectangle';
      double width = 120.0;
      double height = 70.0;
      String strokeColor = '#000000';
      String fillColor = 'transparent';
      final labelCtrl = TextEditingController();

      if (existingElement != null && existingElement.type == ElementType.shape) {
        try {
          final Map<String, dynamic> data = jsonDecode(existingElement.content);
          shapeKind = data['kind'] ?? 'rectangle';
          width = (data['width'] as num?)?.toDouble() ?? 120.0;
          height = (data['height'] as num?)?.toDouble() ?? 70.0;
          strokeColor = data['strokeColor'] ?? '#000000';
          fillColor = data['fillColor'] ?? 'transparent';
          labelCtrl.text = data['label'] ?? '';
        } catch (_) {}
      }

      final Map<String, String> shapeNames = {
        'rectangle': 'مستطيل / مربع',
        'circle': 'دائرة / بيضاوي',
        'triangle': 'مثلث متساوي الساقين',
        'rightTriangle': 'مثلث قائم الزاوية',
        'parallelogram': 'متوازي أضلاع',
        'pentagon': 'شكل خماسي منتظم',
        'hexagon': 'شكل سداسي منتظم',
        'callout': 'شكل تعليق / سحابة كلام',
        'line': 'خط مستقيم',
        'arrow': 'سهم توجيهي',
      };

      showDialog(
        context: context,
        builder: (dCtx) => StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.category, color: Color(0xFF1E3A8A)),
                SizedBox(width: 8),
                Text('إدراج شكل تلقائي وهندسي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: shapeNames.containsKey(shapeKind) ? shapeKind : 'rectangle',
                    decoration: const InputDecoration(labelText: 'نوع الشكل الهندسي', border: OutlineInputBorder()),
                    items: shapeNames.entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDState(() => shapeKind = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: labelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'نص أو رمز داخل الشكل (اختياري)',
                      hintText: 'مثال: 5 cm أو ٥ سم',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('العرض: ${width.toInt()} px', style: const TextStyle(fontSize: 12)),
                            Slider(
                              value: width,
                              min: 50,
                              max: 260,
                              divisions: 21,
                              onChanged: (v) => setDState(() => width = v),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('الارتفاع: ${height.toInt()} px', style: const TextStyle(fontSize: 12)),
                            Slider(
                              value: height,
                              min: 30,
                              max: 180,
                              divisions: 15,
                              onChanged: (v) => setDState(() => height = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('لون الإطار: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      DropdownButton<String>(
                        value: strokeColor,
                        items: [
                          {'name': 'أسود', 'hex': '#000000'},
                          {'name': 'أزرق', 'hex': '#1D4ED8'},
                          {'name': 'أحمر', 'hex': '#B91C1C'},
                          {'name': 'أخضر', 'hex': '#047857'},
                        ].map((c) => DropdownMenuItem(
                          value: c['hex'],
                          child: Row(
                            children: [
                              Container(width: 14, height: 14, color: Color(int.parse(c['hex']!.replaceFirst('#', '0xFF')))),
                              const SizedBox(width: 6),
                              Text(c['name']!),
                            ],
                          ),
                        )).toList(),
                        onChanged: (v) => setDState(() => strokeColor = v!),
                      ),
                      const Text('التعبئة: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      DropdownButton<String>(
                        value: fillColor,
                        items: [
                          {'name': 'شفاف', 'hex': 'transparent'},
                          {'name': 'رمادي', 'hex': '#F1F5F9'},
                          {'name': 'أزرق فاتح', 'hex': '#EFF6FF'},
                          {'name': 'أصفر خفيف', 'hex': '#FEF9C3'},
                        ].map((c) => DropdownMenuItem(
                          value: c['hex'],
                          child: Text(c['name']!),
                        )).toList(),
                        onChanged: (v) => setDState(() => fillColor = v!),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                icon: const Icon(Icons.check, color: Colors.white, size: 18),
                label: const Text('إدراج الشكل', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  final jsonPayload = jsonEncode({
                    'kind': shapeKind,
                    'width': width,
                    'height': height,
                    'label': labelCtrl.text.trim(),
                    'strokeColor': strokeColor,
                    'fillColor': fillColor,
                  });

                  setParentState(() {
                    if (existingElement != null) {
                      existingElement.content = jsonPayload;
                      existingElement.width = width;
                      existingElement.height = height;
                    } else {
                      currentElements.add(InsertableElement(
                        id: const Uuid().v4(),
                        type: ElementType.shape,
                        content: jsonPayload,
                        width: width,
                        height: height,
                      ));
                    }
                  });
                  Navigator.pop(dCtx);
                },
              ),
            ],
          ),
        ),
      );
    }

    void showArabicMathTemplates(void Function(void Function()) setParentState) {
      final numCtrl = TextEditingController(text: isAr ? '١' : '1');
      final denCtrl = TextEditingController(text: isAr ? '٣' : '3');

      showDialog(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: const Text('إدراج كسر اعتيادي في موضع المؤشر'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: numCtrl, decoration: const InputDecoration(labelText: 'البسط')),
              const SizedBox(height: 6),
              TextField(controller: denCtrl, decoration: const InputDecoration(labelText: 'المقام')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () {
                final tag = '[كسر:${numCtrl.text}/${denCtrl.text}]';
                setParentState(() {
                  insertAtCursor(' $tag ');
                });
                Navigator.pop(dCtx);
              },
              child: const Text('إدراج عند المؤشر'),
            ),
          ],
        ),
      );
    }

    void showSymbolsModal(void Function(void Function()) setParentState) {
      final categories = <String, Iterable<String>>{
        'زخارف وفواصل': const [
          '﴾   ﴿', '«   »', '۞', '۩', '۝', '✦ ✦ ✦', '❖ ❖ ❖', '~*~*~*~*~',
          '— — ❖ — —', '•┈┈┈┈•✿•┈┈┈┈•', '━━━ ❀ ━━━', '■ □ ■', '● ○ ●', '※ ※ ※',
        ],
        'رياضيات عربية RTL': const ['[جذر:س]', '[جذر:٢٥]', '[جذر:٣:٢٧]', 'نهـا', 'مجـ', 'تـ', 'ط', 'هـ', '∆', 'س', 'ص', 'ع', 'د', 'ل', 'ك', 'ن', 'ق'],
        'Mathematics & Physics LTR': const ['[sqrt:x]', '[sqrt:25]', '[sqrt:3:27]', 'lim', '∑', '∫', 'dx', 'dy', 'f(x)', 'kg', 'N', 'J', 'm/s', 'Ω', 'V', 'A', 'cm³', 'm²'],
        'تقييم وأقواس': const ['✔', '✘', '✓', '✗', '(   )', '[   ]', '○', '●', '□', '■', '« »'],
        'أسس علوية': const ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹', '⁺', '⁻', 'ⁿ', 'ˣ', 'ʸ'],
        'صيغ كيميائية': const ['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉', '₊', '₋', 'ₐ', 'ₑ', 'ₒ', 'ₓ'],
        'عمليات ومقارنات': const ['×', '÷', '+', '-', '=', '≠', '≈', '<', '>', '≤', '≥', '±'],
        'أسهم وتوجيه': const ['←', '→', '↑', '↓', '↔', '⇐', '⇒', '⇔'],
      };

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (bCtx) => DefaultTabController(
          length: categories.keys.length,
          child: SizedBox(
            height: 350,
            child: Column(
              children: [
                TabBar(
                  isScrollable: true,
                  labelColor: const Color(0xFF1E3A8A),
                  indicatorColor: const Color(0xFF1E3A8A),
                  tabs: [
                    for (final name in categories.keys) Tab(text: name),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      for (final symbolsGroup in categories.values)
                        GridView.count(
                          padding: const EdgeInsets.all(12),
                          crossAxisCount: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          children: [
                            for (final sym in symbolsGroup)
                              InkWell(
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
                                    child: Text(
                                      sym,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildInteractiveEditorElement(InsertableElement el, int elementIndex, StateSetter setModalState) {
      void moveElementUp() {
        if (elementIndex > 0) {
          setModalState(() {
            final item = currentElements.removeAt(elementIndex);
            currentElements.insert(elementIndex - 1, item);
          });
        }
      }

      void moveElementDown() {
        if (elementIndex < currentElements.length - 1) {
          setModalState(() {
            final item = currentElements.removeAt(elementIndex);
            currentElements.insert(elementIndex + 1, item);
          });
        }
      }

      void copyElementToClipboard() {
        setState(() {
          _copiedElement = InsertableElement(
            id: const Uuid().v4(),
            type: el.type,
            content: el.content,
            width: el.width,
            height: el.height,
            dx: el.dx,
            dy: el.dy,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم نسخ العنصر إلى الحافظة. يمكنك لصقه في هذا السؤال أو أي سؤال آخر.'),
            duration: Duration(seconds: 2),
            backgroundColor: Color(0xFF1E3A8A),
          ),
        );
      }

      void duplicateElementDirectly() {
        setModalState(() {
          currentElements.insert(
            elementIndex + 1,
            InsertableElement(
              id: const Uuid().v4(),
              type: el.type,
              content: el.content,
              width: el.width,
              height: el.height,
              dx: el.dx + 10,
              dy: el.dy + 10,
            ),
          );
        });
      }

      Widget buildElementActionToolbar({required String title, required IconData icon, required Color color, VoidCallback? onEdit}) {
        return Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18, color: Colors.blueGrey),
              tooltip: 'تحريك لأعلى',
              onPressed: elementIndex > 0 ? moveElementUp : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18, color: Colors.blueGrey),
              tooltip: 'تحريك لأسفل',
              onPressed: elementIndex < currentElements.length - 1 ? moveElementDown : null,
            ),
            IconButton(
              icon: const Icon(Icons.copy_outlined, size: 17, color: Color(0xFF1E3A8A)),
              tooltip: 'نسخ للحافظة',
              onPressed: copyElementToClipboard,
            ),
            IconButton(
              icon: const Icon(Icons.control_point_duplicate, size: 18, color: Color(0xFF0F766E)),
              tooltip: 'تكرار فوري في نفس السؤال',
              onPressed: duplicateElementDirectly,
            ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.tune, size: 18, color: Colors.indigo),
                tooltip: 'تعديل الأبعاد والإعدادات',
                onPressed: onEdit,
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
              tooltip: 'حذف العنصر',
              onPressed: () => setModalState(() => currentElements.removeAt(elementIndex)),
            ),
          ],
        );
      }

      if (el.type == ElementType.table) {
        try {
          final Map<String, dynamic> data = jsonDecode(el.content);
          final int rows = (data['rows'] as num?)?.toInt() ?? 2;
          final int cols = (data['cols'] as num?)?.toInt() ?? 2;
          final bool hasHeader = data['hasHeader'] ?? true;
          final List<dynamic> rawGrid = data['data'] ?? [];

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50.withOpacity(0.4),
              border: Border.all(color: Colors.indigo.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildElementActionToolbar(
                  title: 'جدول مدرج (اكتب مباشرة داخل الخلايا):',
                  icon: Icons.table_chart,
                  color: const Color(0xFF1E3A8A),
                  onEdit: () => showTableDesignerDialog(setModalState, existingElement: el),
                ),
                const SizedBox(height: 4),
                Table(
                  border: TableBorder.all(color: Colors.black87, width: 1.0),
                  children: List.generate(rows, (r) {
                    final isHeader = (r == 0 && hasHeader);
                    return TableRow(
                      decoration: BoxDecoration(color: isHeader ? Colors.grey.shade200 : Colors.white),
                      children: List.generate(cols, (c) {
                        String cellVal = '';
                        if (r < rawGrid.length && c < (rawGrid[r] as List).length) {
                          cellVal = rawGrid[r][c]?.toString() ?? '';
                        }
                        return TableCell(
                          verticalAlignment: TableCellVerticalAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.all(2.0),
                            child: TextFormField(
                              initialValue: cellVal,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: isAr ? 'Amiri' : 'Arial',
                                fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
                                fontSize: isHeader ? 12.5 : 11.5,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                              ),
                              onChanged: (newText) {
                                while (rawGrid.length <= r) {
                                  rawGrid.add(List.generate(cols, (_) => ''));
                                }
                                while ((rawGrid[r] as List).length <= c) {
                                  (rawGrid[r] as List).add('');
                                }
                                rawGrid[r][c] = newText;
                                el.content = jsonEncode({
                                  'rows': rows,
                                  'cols': cols,
                                  'hasHeader': hasHeader,
                                  'data': rawGrid,
                                });
                              },
                            ),
                          ),
                        );
                      }),
                    );
                  }),
                ),
              ],
            ),
          );
        } catch (_) {
          return const SizedBox.shrink();
        }
      }

      if (el.type == ElementType.shape) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.amber.shade50.withOpacity(0.4),
            border: Border.all(color: Colors.amber.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildElementActionToolbar(
                title: 'شكل هندسي مدرج:',
                icon: Icons.category,
                color: const Color(0xFFD97706),
                onEdit: () => showShapeDesignerDialog(setModalState, existingElement: el),
              ),
              _renderCustomShape(el.content, el.width, el.height),
            ],
          ),
        );
      }

      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildElementActionToolbar(
              title: 'عنصر مدرج:',
              icon: Icons.widgets_outlined,
              color: Colors.blueGrey.shade800,
            ),
            _buildRenderedElement(el),
          ],
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.94,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // إخفاء وإظهار إعدادات السؤال (العنوان والدرجة والاتجاه)
                      if (showQuestionSettings) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: titleCtrl,
                                decoration: InputDecoration(
                                  labelText: isAr ? 'اسم السؤال (س١)' : 'Question Title (Q1)',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 1,
                              child: TextField(
                                controller: markCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(labelText: isAr ? 'الدرجة' : 'Mark'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: [
                            Text(isAr ? 'عنوان السؤال: ' : 'Title Orient: ',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ChoiceChip(
                              label: const Text('أفقي', style: TextStyle(fontSize: 11)),
                              selected: orientation == QuestionTitleOrientation.horizontal,
                              onSelected: (val) => setModalState(
                                  () => orientation = QuestionTitleOrientation.horizontal),
                            ),
                            ChoiceChip(
                              label: const Text('رأسي ◄', style: TextStyle(fontSize: 11)),
                              selected: orientation == QuestionTitleOrientation.verticalBottomToTop,
                              onSelected: (val) => setModalState(() =>
                                  orientation = QuestionTitleOrientation.verticalBottomToTop),
                            ),
                            ChoiceChip(
                              label: const Text('رأسي ►', style: TextStyle(fontSize: 11)),
                              selected: orientation == QuestionTitleOrientation.verticalTopToBottom,
                              onSelected: (val) => setModalState(() =>
                                  orientation = QuestionTitleOrientation.verticalTopToBottom),
                            ),
                            const SizedBox(width: 8),
                            Text(isAr ? 'عمود الدرجة: ' : 'Mark Col: ',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ChoiceChip(
                              label: const Text('أفقي', style: TextStyle(fontSize: 11)),
                              selected: gradeOrient == GradeTextOrientation.horizontal,
                              onSelected: (val) => setModalState(
                                  () => gradeOrient = GradeTextOrientation.horizontal),
                            ),
                            ChoiceChip(
                              label: const Text('رأسي ◄', style: TextStyle(fontSize: 11)),
                              selected: gradeOrient == GradeTextOrientation.verticalBottomToTop,
                              onSelected: (val) => setModalState(() =>
                                  gradeOrient = GradeTextOrientation.verticalBottomToTop),
                            ),
                            ChoiceChip(
                              label: const Text('رأسي ►', style: TextStyle(fontSize: 11)),
                              selected: gradeOrient == GradeTextOrientation.verticalTopToBottom,
                              onSelected: (val) => setModalState(() =>
                                  gradeOrient = GradeTextOrientation.verticalTopToBottom),
                            ),
                            const SizedBox(width: 6),
                            FilterChip(
                              avatar: Icon(Icons.view_column, size: 14, color: isTwoCols ? Colors.white : Colors.black87),
                              label: Text(isAr ? 'عمودان' : '2 Columns', style: TextStyle(fontSize: 11, color: isTwoCols ? Colors.white : Colors.black87)),
                              selected: isTwoCols,
                              selectedColor: const Color(0xFF0F766E),
                              onSelected: (v) => setModalState(() => isTwoCols = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      // شريط الأدوات المبوب وتمرير المتغيرات المطلوبة
                      ExamRibbonToolbar(
                        showQuestionSettings: showQuestionSettings,
                        onToggleQuestionSettings: () => setModalState(() => showQuestionSettings = !showQuestionSettings),
                        isBold: isBoldActive,
                        isUnderline: isUnderlineActive,
                        currentAlignment: selectedAlignment,
                        currentColor: currentColor,
                        currentFont: currentFont,
                        currentFontSize: currentFontSize,
                        isArabicInput: isInputArabic,
                        isTextSelected: isTextSelected,
                        hasClipboardContent: hasClipboardContent,
                        currentLineSpacing: currentLineSpacing,
                        currentZoom: _zoomLevel,
                        onToggleBold: () { setModalState(() { isBoldActive = !isBoldActive; applyFormatToSelection(bold: isBoldActive); }); },
                        onToggleUnderline: () { setModalState(() { isUnderlineActive = !isUnderlineActive; applyFormatToSelection(underline: isUnderlineActive); }); },
                        onAlignmentChanged: (align) => setModalState(() => selectedAlignment = align),
                        onColorChanged: (c) { setModalState(() { currentColor = c; applyFormatToSelection(color: c); }); },
                        onFontChanged: (f) { setModalState(() { currentFont = f; applyFormatToSelection(font: f); }); },
                        onFontSizeChanged: (s) { setModalState(() { currentFontSize = s; applyFormatToSelection(size: s); }); },
                        onToggleInputLanguage: () {
                          setModalState(() {
                            isInputArabic = !isInputArabic;
                            selectedAlignment = isInputArabic ? TextAlign.right : TextAlign.left;
                            currentFont = isInputArabic ? 'Amiri' : 'Arial';
                          });
                        },
                        onCopy: () async {
                          final sel = lastSelection ?? textCtrl.selection;
                          if (sel.isValid && !sel.isCollapsed) {
                            final start = math.min(sel.start, sel.end);
                            final end = math.max(sel.start, sel.end);
                            final selectedText = textCtrl.text.substring(start, end);
                            await Clipboard.setData(ClipboardData(text: selectedText));
                            setModalState(() {
                              hasClipboardContent = true;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم نسخ النص المحدد إلى الحافظة.')),
                              );
                            }
                          }
                        },
                        onCut: () async {
                          final sel = lastSelection ?? textCtrl.selection;
                          if (sel.isValid && !sel.isCollapsed) {
                            final start = math.min(sel.start, sel.end);
                            final end = math.max(sel.start, sel.end);
                            final selectedText = textCtrl.text.substring(start, end);
                            await Clipboard.setData(ClipboardData(text: selectedText));
                            textCtrl.text = textCtrl.text.replaceRange(start, end, '');
                            textCtrl.selection = TextSelection.collapsed(offset: start);
                            lastSelection = textCtrl.selection;
                            setModalState(() {
                              isTextSelected = false;
                              hasClipboardContent = true;
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم قص النص إلى الحافظة.')),
                              );
                            }
                          }
                        },
                        onPaste: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data != null && data.text != null && data.text!.isNotEmpty) {
                            final clipText = data.text!;
                            final sel = lastSelection ?? textCtrl.selection;
                            final pos = sel.isValid ? math.min(sel.start, sel.end) : textCtrl.text.length;
                            final end = sel.isValid ? math.max(sel.start, sel.end) : textCtrl.text.length;
                            setModalState(() {
                              textCtrl.text = textCtrl.text.replaceRange(pos, end, clipText);
                              textCtrl.selection = TextSelection.collapsed(offset: pos + clipText.length);
                              lastSelection = textCtrl.selection;
                              isTextSelected = false;
                            });
                          }
                        },
                        onShare: () {
                          final sel = lastSelection ?? textCtrl.selection;
                          if (sel.isValid && !sel.isCollapsed) {
                            final start = math.min(sel.start, sel.end);
                            final end = math.max(sel.start, sel.end);
                            final selectedText = textCtrl.text.substring(start, end);
                            Clipboard.setData(ClipboardData(text: selectedText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم نسخ النص للمشاركة.')),
                            );
                          }
                        },
                        onSelectAll: () {
                          setModalState(() {
                            textCtrl.selection = TextSelection(baseOffset: 0, extentOffset: textCtrl.text.length);
                            lastSelection = textCtrl.selection;
                            isTextSelected = textCtrl.text.isNotEmpty;
                          });
                        },
                        onDeleteSelected: () {
                          final sel = lastSelection ?? textCtrl.selection;
                          if (sel.isValid && !sel.isCollapsed) {
                            final start = math.min(sel.start, sel.end);
                            final end = math.max(sel.start, sel.end);
                            setModalState(() {
                              textCtrl.text = textCtrl.text.replaceRange(start, end, '');
                              textCtrl.selection = TextSelection.collapsed(offset: start);
                              lastSelection = textCtrl.selection;
                              isTextSelected = false;
                            });
                          }
                        },
                        onOpenQuestionBank: _showQuestionBankImportDialog,
                        onInsertImage: () async {
                          final img = await _picker.pickImage(source: ImageSource.gallery);
                          if (img != null) {
                            setModalState(() {
                              currentElements.add(InsertableElement(id: const Uuid().v4(), type: ElementType.image, content: img.path, width: 90, height: 90));
                            });
                          }
                        },
                        onInsertDottedLine: () {
                          setModalState(() {
                            currentElements.add(InsertableElement(id: const Uuid().v4(), type: ElementType.dottedLine, content: '......................................................................'));
                          });
                        },
                        onInsertPageBreak: () {
                          setModalState(() => insertAtCursor(' [فاصل_صفحة] '));
                        },
                        onInsertTextBox: () {
                          _showTextBoxEntryDialog(context, (txt) {
                            setModalState(() {
                              currentElements.add(InsertableElement(id: const Uuid().v4(), type: ElementType.textBox, content: txt));
                            });
                          });
                        },
                        onInsertFraction: () => showArabicMathTemplates(setModalState),
                        onInsertRadical: () => setModalState(() => insertAtCursor(isInputArabic ? '[جذر:٢٥]' : '[sqrt:25]')),
                        onInsertEquation: () => showAdvancedEquationDialog(setModalState),
                        onInsertVerticalMath: () => showVerticalMathDialog(setModalState),
                        onInsertLongDivision: () => showLongDivisionDialog(setModalState),
                        onOpenSymbolsModal: () => showSymbolsModal(setModalState),
                        onOpenTableDesigner: () => showTableDesignerDialog(setModalState),
                        onInsertShape: (kind) {
                          final jsonPayload = jsonEncode({'kind': kind, 'width': 120.0, 'height': 70.0, 'label': '', 'strokeColor': '#000000', 'fillColor': 'transparent'});
                          setModalState(() {
                            currentElements.add(InsertableElement(id: const Uuid().v4(), type: ElementType.shape, content: jsonPayload, width: 120.0, height: 70.0));
                          });
                        },
                        onLineSpacingChanged: (spacing) {
                          setModalState(() {
                            currentLineSpacing = spacing;
                          });
                        },
                        onZoomIn: _zoomIn,
                        onZoomOut: _zoomOut,
                        onFitScreen: _fitScreen,
                      ),
                      const SizedBox(height: 8),

                      Directionality(
                        textDirection: isInputArabic ? TextDirection.rtl : TextDirection.ltr,
                        child: TextField(
                          controller: textCtrl,
                          textAlign: selectedAlignment,
                          readOnly: false,
                          showCursor: true,
                          enableInteractiveSelection: true,
                          keyboardType: useSystemKeyboard ? TextInputType.multiline : TextInputType.none,
                          maxLines: 4,
                          style: TextStyle(height: currentLineSpacing),
                          onChanged: (val) {
                            setModalState(() {
                              lastSelection = textCtrl.selection;
                              isTextSelected = textCtrl.selection.isValid && !textCtrl.selection.isCollapsed;
                            });
                            Clipboard.hasStrings().then((hasVal) {
                              if (hasVal != hasClipboardContent) {
                                setModalState(() => hasClipboardContent = hasVal);
                              }
                            });
                          },
                          onTap: () {
                            setModalState(() {
                              activeFieldController = textCtrl;
                              lastSelection = textCtrl.selection;
                              isTextSelected = textCtrl.selection.isValid && !textCtrl.selection.isCollapsed;
                              if (!useSystemKeyboard) {
                                showCustomKeyboard = true;
                              }
                              showQuestionSettings = false;
                            });
                            Clipboard.hasStrings().then((hasVal) {
                              if (hasVal != hasClipboardContent) {
                                setModalState(() => hasClipboardContent = hasVal);
                              }
                            });
                          },
                          decoration: InputDecoration(
                            labelText: isInputArabic
                                ? 'محتوى نص السؤال (مكان الإدخال محدد: ${selectedAlignment == TextAlign.right ? "يمين" : (selectedAlignment == TextAlign.center ? "وسط" : "يسار")})'
                                : 'Question Text (Alignment: ${selectedAlignment == TextAlign.left ? "Left" : (selectedAlignment == TextAlign.center ? "Center" : "Right")})',
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: activeFieldController == textCtrl ? const Color(0xFF1E3A8A) : Colors.grey,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      if (currentElements.isNotEmpty) ...[
                        const Text(
                          'العناصر والجداول المدرجة في هذا السؤال (انقر على العنصر لتحديده وتحريكه كـ Word):',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                        ),
                        const SizedBox(height: 4),
                        ...currentElements.asMap().entries.map((entry) {
                          return buildInteractiveEditorElement(entry.value, entry.key, setModalState);
                        }),
                        const SizedBox(height: 8),
                      ],

                      Directionality(
                        textDirection: isInputArabic ? TextDirection.rtl : TextDirection.ltr,
                        child: TextField(
                          controller: answerCtrl,
                          textAlign: selectedAlignment,
                          readOnly: false,
                          showCursor: true,
                          enableInteractiveSelection: true,
                          keyboardType: useSystemKeyboard ? TextInputType.multiline : TextInputType.none,
                          maxLines: 2,
                          onTap: () {
                            setModalState(() {
                              activeFieldController = answerCtrl;
                              if (!useSystemKeyboard) {
                                showCustomKeyboard = true;
                              }
                              showQuestionSettings = false;
                            });
                          },
                          decoration: InputDecoration(
                            labelText: isInputArabic ? 'الإجابة النموذجية / مفتاح التصحيح (اختياري)' : 'Model Answer Key (Optional)',
                            hintText: isInputArabic ? 'اضغط هنا للكتابة...' : 'Type answer key here...',
                            prefixIcon: const Icon(Icons.verified, color: Color(0xFF0F766E)),
                            filled: true,
                            fillColor: Colors.teal.shade50.withOpacity(0.5),
                            border: const OutlineInputBorder(),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: activeFieldController == answerCtrl ? const Color(0xFF0F766E) : Colors.grey,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      Row(
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.bookmark_add, color: Color(0xFF1E3A8A)),
                            label: const Text('حفظ لبنك الأسئلة'),
                            onPressed: () async {
                              final qToSave = QuestionModel(
                                id: const Uuid().v4(),
                                title: titleCtrl.text.trim(),
                                titleOrientation: orientation,
                                gradeOrientation: gradeOrient,
                                mark: double.tryParse(markCtrl.text) ?? 5.0,
                                spans: [TextSpanModel(text: textCtrl.text)],
                                elements: currentElements,
                                answerKey: answerCtrl.text.trim(),
                                alignment: selectedAlignment,
                              );
                              await QuestionBankService.saveQuestion(
                                question: qToSave,
                                subject: _exam.header.subject,
                                grade: _exam.header.grade,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('تم حفظ السؤال بنجاح في بنك الأسئلة الشخصي.'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          if (isEdit) ...[
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                side: BorderSide(color: Colors.red.shade700),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              icon: const Icon(Icons.delete_outline, size: 20),
                              label: const Text('حذف'),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (dCtx) => AlertDialog(
                                    title: const Text('تأكيد حذف السؤال'),
                                    content: Text('هل أنت متأكد من حذف (${q.title}) نهائياً؟'),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(dCtx),
                                        child: const Text('إلغاء'),
                                      ),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
                                        onPressed: () {
                                          setState(() {
                                            _exam.questions.removeAt(questionIndex);
                                          });
                                          Navigator.pop(dCtx);
                                          Navigator.pop(ctx);
                                          _measurePagesHeight();
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('تم حذف السؤال بنجاح'),
                                              backgroundColor: Colors.red,
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        },
                                        child: const Text('نعم، احذف', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E3A8A),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
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
                                          colorHex: currentColor,
                                        )
                                      ];

                                final newQ = QuestionModel(
                                  id: q.id,
                                  title: titleCtrl.text,
                                  titleOrientation: orientation,
                                  gradeOrientation: gradeOrient,
                                  mark: double.tryParse(markCtrl.text) ?? 0.0,
                                  spans: spansToSave,
                                  elements: currentElements,
                                  answerKey: answerCtrl.text.trim(),
                                  isTwoColumns: isTwoCols,
                                  alignment: selectedAlignment,
                                );

                                setState(() {
                                  if (isEdit) {
                                    _exam.questions[questionIndex] = newQ;
                                  } else {
                                    _exam.questions.add(newQ);
                                  }
                                });
                                Navigator.pop(ctx);
                                _measurePagesHeight();
                              },
                              child: Text(
                                isAr ? 'تأكيد وحفظ السؤال' : 'Save Question',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),

              if (showCustomKeyboard && !useSystemKeyboard)
                ExamCustomKeyboard(
                  controller: activeFieldController,
                  onClose: () => setModalState(() => showCustomKeyboard = false),
                  onSwitchToSystemKeyboard: () {
                    setModalState(() {
                      useSystemKeyboard = true;
                      showCustomKeyboard = false;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

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
          constraints: const BoxConstraints(minWidth: 38),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon, color: Colors.white, size: 18),
                if (icon != null && text != null) const SizedBox(width: 4),
                if (text != null)
                  Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
              ],
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

  Future<void> _pickExcelFileForStudents(StateSetter setDlgState) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'xlsm', 'xlsb'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final excelRes = await StudentExcelService.parseExcelFile(
          path,
          expectedSubject: _exam.header.subject,
          targetGrade: _exam.header.grade,
          examTitle: _exam.header.examTitle,
        );

        setDlgState(() {
          _exam.header.excelFilePath = path;
          _exam.header.subjectCode = excelRes.subjectCode;
          if (_exam.header.studentDataMode == 'none') {
            _exam.header.studentDataMode = 'namesOnly';
          }
        });
        setState(() {});
        _measurePagesHeight();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم تنشيط ورقة [${excelRes.matchedSubjectName}] لمادة (${_exam.header.subject})\nتم تحميل ${excelRes.students.length} طالباً لصف (${_exam.header.grade}).',
              ),
              backgroundColor: Colors.green.shade800,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر قراءة ملف الإكسيل: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
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
          title: const Text('خيارات الترويسة والتذييل وكشف الطلاب',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('فراغ رأس الصفحة لبيانات الطلاب'),
                  subtitle: const Text('إظهار سطر اسم الطالب ورقم الجلوس أعلى الامتحان'),
                  value: topMargin,
                  onChanged: (val) {
                    setDlgState(() {
                      topMargin = val;
                      _exam.header.topMargin1cm = val;
                      if (!val) {
                        _exam.header.studentDataMode = 'none';
                      } else if (_exam.header.studentDataMode == 'none') {
                        _exam.header.studentDataMode = 'namesOnly';
                      }
                    });
                  },
                ),
                if (topMargin) ...[
                  const Divider(),
                  const Text(
                    'كشف الطلاب من ملف Excel:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF1E3A8A)),
                  ),
                  const SizedBox(height: 6),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.file_upload_outlined, color: Colors.white, size: 18),
                    label: Text(
                      _exam.header.excelFilePath != null ? 'تغيير ملف Excel' : 'اختيار ملف كشف الطلاب (Excel)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _pickExcelFileForStudents(setDlgState),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _exam.header.excelFilePath != null
                              ? 'الملف المختار: ${_exam.header.excelFilePath!.split(Platform.pathSeparator).last}'
                              : 'لم يتم اختيار ملف بعد (سيتم توليد ورق عادي بالنقط)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _exam.header.excelFilePath != null ? Colors.green.shade900 : Colors.black54,
                          ),
                        ),
                        if (_exam.header.excelFilePath != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'المادة المربوطة: ${_exam.header.subject} | الصف: ${_exam.header.grade}',
                            style: const TextStyle(fontSize: 10.5, color: Color(0xFF1E3A8A)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('نوع البيانات المستخرجة:', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('الاسم والجلوس فقط', style: TextStyle(fontSize: 11)),
                        selected: _exam.header.studentDataMode == 'namesOnly',
                        onSelected: (v) {
                          if (v) setDlgState(() => _exam.header.studentDataMode = 'namesOnly');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('الاسم + الجلوس + QR', style: TextStyle(fontSize: 11)),
                        selected: _exam.header.studentDataMode == 'namesAndQr',
                        onSelected: (v) {
                          if (v) setDlgState(() => _exam.header.studentDataMode = 'namesAndQr');
                        },
                      ),
                      ChoiceChip(
                        label: const Text('ورق عادي (فارغ)', style: TextStyle(fontSize: 11)),
                        selected: _exam.header.studentDataMode == 'none',
                        onSelected: (v) {
                          if (v) setDlgState(() => _exam.header.studentDataMode = 'none');
                        },
                      ),
                    ],
                  ),
                ],
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
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
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
              onPressed: () {
                setState(() {
                  _exam.header.topMargin1cm = topMargin;
                  _exam.header.isMultiPage = isMulti;
                  _exam.header.singlePageFooterText = singleCtrl.text;
                  _exam.header.continuationText = multiCtrl.text;
                  _exam.header.teacherSignature = signCtrl.text;
                });
                Navigator.pop(ctx);
                _measurePagesHeight();
              },
              child: const Text('حفظ الإعدادات', style: TextStyle(color: Colors.white)),
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
    double size = _exam.header.adminFontSize;
    bool bold = _exam.header.adminBold;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('تعديل الحقول الإدارية'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    DropdownButton<String>(
                      value: appFontsList.any((e) => e['id'] == font) ? font : 'Amiri',
                      items: appFontsList.map((f) => DropdownMenuItem<String>(
                        value: f['id']!,
                        child: Text(f['name']!, style: TextStyle(fontFamily: f['id']!, fontSize: 13)),
                      )).toList(),
                      onChanged: (v) {
                        if (v != null) setDlgState(() => font = v);
                      },
                    ),
                    DropdownButton<double>(
                      value: size,
                      items: [8.5, 9.0, 9.5, 10.0, 11.0, 12.0]
                          .map((s) => DropdownMenuItem(value: s, child: Text('$s pt')))
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
                const Divider(),
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
                  _exam.header.adminFontSize = size;
                  _exam.header.adminBold = bold;
                });
                Navigator.pop(ctx);
                _measurePagesHeight();
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
    double size = _exam.header.detailsFontSize;
    bool bold = _exam.header.detailsBold;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('تعديل بيانات الامتحان'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    DropdownButton<String>(
                      value: appFontsList.any((e) => e['id'] == font) ? font : 'Amiri',
                      items: appFontsList.map((f) => DropdownMenuItem<String>(
                        value: f['id']!,
                        child: Text(f['name']!, style: TextStyle(fontFamily: f['id']!, fontSize: 13)),
                      )).toList(),
                      onChanged: (v) {
                        if (v != null) setDlgState(() => font = v);
                      },
                    ),
                    DropdownButton<double>(
                      value: size,
                      items: [9.0, 9.5, 10.0, 10.5, 11.0, 12.0]
                          .map((s) => DropdownMenuItem(value: s, child: Text('$s pt')))
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
                const Divider(),
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
                  _exam.header.detailsFontSize = size;
                  _exam.header.detailsBold = bold;
                });
                Navigator.pop(ctx);
                _measurePagesHeight();
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
                    value: appFontsList.any((e) => e['id'] == font) ? font : 'Amiri',
                    items: appFontsList.map((f) => DropdownMenuItem<String>(
                      value: f['id']!,
                      child: Text(f['name']!, style: TextStyle(fontFamily: f['id']!, fontSize: 13)),
                    )).toList(),
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
                _measurePagesHeight();
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('تنسيق وتحرير البسملة / الترويسة'),
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
                  labelText: 'نص البسملة أو العبارة الافتتاحية',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  DropdownButton<String>(
                    value: appFontsList.any((e) => e['id'] == font) ? font : 'Amiri',
                    items: appFontsList.map((f) => DropdownMenuItem<String>(
                      value: f['id']!,
                      child: Text(f['name']!, style: TextStyle(fontFamily: f['id']!, fontSize: 13)),
                    )).toList(),
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
                _measurePagesHeight();
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
              _measurePagesHeight();
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}

class _LimitArrowPainter extends CustomPainter {
  final Color color;
  _LimitArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width, size.height / 2)
      ..lineTo(0, size.height / 2)
      ..moveTo(2.5, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(2.5, size.height);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// تعديل _ExamShapePainter لإضافة الأشكال الهندسية الجديدة
class _ExamShapePainter extends CustomPainter {
  final String kind;
  final Color strokeColor;
  final Color fillColor;

  _ExamShapePainter({
    required this.kind,
    required this.strokeColor,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    switch (kind) {
      case 'circle':
        final rect = Rect.fromLTWH(2, 2, w - 4, h - 4);
        if (fillColor != Colors.transparent) canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, strokePaint);
        break;

      case 'triangle':
        final path = Path()
          ..moveTo(w / 2, 2)
          ..lineTo(w - 2, h - 2)
          ..lineTo(2, h - 2)
          ..close();
        if (fillColor != Colors.transparent) canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
        break;

      case 'rightTriangle':
        final path = Path()
          ..moveTo(2, 2)
          ..lineTo(2, h - 2)
          ..lineTo(w - 2, h - 2)
          ..close();
        if (fillColor != Colors.transparent) canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
        final sqPath = Path()
          ..moveTo(2, h - 14)
          ..lineTo(14, h - 14)
          ..lineTo(14, h - 2);
        canvas.drawPath(sqPath, strokePaint..strokeWidth = 1.0);
        break;

      case 'parallelogram':
        final offset = w * 0.22;
        final path = Path()
          ..moveTo(offset, 2)
          ..lineTo(w - 2, 2)
          ..lineTo(w - offset, h - 2)
          ..lineTo(2, h - 2)
          ..close();
        if (fillColor != Colors.transparent) canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
        break;

      // شكل خماسي منتظم (Pentagon) باستخدام cos و sin
      case 'pentagon':
        final cx = w / 2;
        final cy = h / 2;
        final rx = (w - 4) / 2;
        final ry = (h - 4) / 2;
        const sides = 5;
        final path = Path();
        for (int i = 0; i < sides; i++) {
          final angle = (i * 2 * math.pi / sides) - (math.pi / 2);
          final px = cx + rx * math.cos(angle);
          final py = cy + ry * math.sin(angle);
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        if (fillColor != Colors.transparent) canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
        break;

      // شكل سداسي منتظم (Hexagon) باستخدام cos و sin
      case 'hexagon':
        final cx = w / 2;
        final cy = h / 2;
        final rx = (w - 4) / 2;
        final ry = (h - 4) / 2;
        const sides = 6;
        final path = Path();
        for (int i = 0; i < sides; i++) {
          final angle = (i * 2 * math.pi / sides) - (math.pi / 6);
          final px = cx + rx * math.cos(angle);
          final py = cy + ry * math.sin(angle);
          if (i == 0) {
            path.moveTo(px, py);
          } else {
            path.lineTo(px, py);
          }
        }
        path.close();
        if (fillColor != Colors.transparent) canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
        break;

      // شكل تعليق / سحابة كلام (Callout)
      case 'callout':
        final bubbleH = h * 0.75;
        final path = Path()
          ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(2, 2, w - 4, bubbleH - 2), const Radius.circular(8)))
          ..moveTo(w * 0.35, bubbleH)
          ..lineTo(w * 0.20, h - 2)
          ..lineTo(w * 0.45, bubbleH);
        if (fillColor != Colors.transparent) canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
        break;

      case 'line':
        canvas.drawLine(Offset(2, h / 2), Offset(w - 2, h / 2), strokePaint);
        break;

      case 'arrow':
        final y = h / 2;
        canvas.drawLine(Offset(2, y), Offset(w - 2, y), strokePaint);
        final arrowPath = Path()
          ..moveTo(12, y - 6)
          ..lineTo(2, y)
          ..lineTo(12, y + 6);
        canvas.drawPath(arrowPath, strokePaint);
        break;

      case 'rectangle':
      default:
        final rRect = RRect.fromRectAndRadius(Rect.fromLTWH(2, 2, w - 4, h - 4), const Radius.circular(3));
        if (fillColor != Colors.transparent) canvas.drawRRect(rRect, fillPaint);
        canvas.drawRRect(rRect, strokePaint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ExamShapePainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.strokeColor != strokeColor ||
      oldDelegate.fillColor != fillColor;
}

class _ArabicRadicalPainter extends CustomPainter {
  final Color color;
  final double radicalStrokeWidth;

  _ArabicRadicalPainter({
    this.color = Colors.black87,
    this.radicalStrokeWidth = 1.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = radicalStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

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
  final double radicalStrokeWidth;

  _EnglishRadicalPainter({
    this.color = Colors.black87,
    this.radicalStrokeWidth = 1.6,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = radicalStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

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

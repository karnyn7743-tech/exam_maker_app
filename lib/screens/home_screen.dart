import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/exam_models.dart';
import '../services/activation_service.dart';
import '../services/exam_share_service.dart';
import '../services/exam_storage_service.dart';
import '../services/file_manager.dart';
import 'activation_screen.dart';
import 'exam_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ExamModel> _exams = [];
  bool _isLoading = true;
  bool _isActivated = false;
  int _remainingDays = 0;

  @override
  void initState() {
    super.initState();
    _loadExams();
    _checkActivationStatus();
  }

  Future<void> _checkActivationStatus() async {
    final status = await ActivationService.getLicenseStatus();
    final remaining = await ActivationService.getRemainingTrialDays();
    if (mounted) {
      setState(() {
        _isActivated = (status == LicenseStatus.full);
        _remainingDays = remaining;
      });
    }
  }

  // تحميل قائمة الاختبارات من الذاكرة المحلية
  Future<void> _loadExams() async {
    setState(() => _isLoading = true);
    final list = await ExamStorageService.getAllExams();
    if (mounted) {
      setState(() {
        _exams = list;
        _isLoading = false;
      });
    }
  }

  /// فحص هل يُسمح له بإنشاء اختبار جديد أو استيراده بناءً على صلاحية الـ 30 يوماً
  Future<bool> _verifyTrialOrActivated() async {
    final status = await ActivationService.getLicenseStatus();
    if (status == LicenseStatus.full || status == LicenseStatus.trial) {
      return true;
    }

    if (!mounted) return false;

    // توجيهه لشاشة التنشيط عند انتهاء مدة الـ 30 يوماً
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.lock_clock, color: Colors.amber),
            SizedBox(width: 8),
            Text('انتهت الفترة التجريبية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: const Text(
          'انتهت فترة الـ 30 يوماً المتاحة لتجربة التطبيق.\n'
          'لإنشاء المزيد من الاختبارات المفتوحة والوصول لجميع الميزات، يرجى تفعيل النسخة الكاملة عبر التواصل مع المطور.',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ActivationScreen()),
              ).then((_) {
                _checkActivationStatus();
                _loadExams();
              });
            },
            child: const Text('إدخال مفتاح التنشيط', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    return false;
  }

  // نافذة تعريف المطور وبيانات التواصل
  void _showDeveloperInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.workspace_premium, color: Color(0xFFD97706), size: 24),
            SizedBox(width: 8),
            Text(
              'عن مطور النظام',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'نظام صانع الاختبارات المدرسية والأتمتة الذكية',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F766E)),
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'الأستاذ / فواز سنان البعيثي',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A)),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.phone_forwarded, color: Color(0xFF0F766E)),
              title: const Text('اتصال وواتساب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: const Text('00967778064679', textDirection: TextDirection.ltr),
              trailing: const Icon(Icons.copy, size: 16),
              onTap: () {
                Clipboard.setData(const ClipboardData(text: '00967778064679'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ الرقم: 00967778064679'), duration: Duration(seconds: 2)),
                );
              },
            ),
            ListTile(
              dense: true,
              leading: const Icon(Icons.send_rounded, color: Color(0xFF0284C7)),
              title: const Text('قناة التليجرام التعليمية', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              subtitle: const Text('https://t.me/fawaz132', textDirection: TextDirection.ltr),
              trailing: const Icon(Icons.copy, size: 16),
              onTap: () {
                Clipboard.setData(const ClipboardData(text: 'https://t.me/fawaz132'));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نسخ رابط التليجرام: https://t.me/fawaz132'), duration: Duration(seconds: 2)),
                );
              },
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // 1. الشروع في الاختبارات الشاملة (التحريرية التقليدية)
  Future<void> _createTraditionalExam() async {
    if (!await _verifyTrialOrActivated()) return;

    if (!_isActivated) {
      await ActivationService.incrementTrialCount();
    }

    final newExam = ExamModel(
      id: const Uuid().v4(),
      fileName: 'اختبار_شامل_${DateTime.now().millisecondsSinceEpoch}',
      examType: ExamType.traditional,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      header: HeaderModel(),
      questions: [],
    );

    _openEditor(newExam, isNew: true);
  }

  // 2. إنشاء اختبار مؤتمت (تظليل OMR)
  Future<void> _showCreateAutomatedExamDialog() async {
    if (!await _verifyTrialOrActivated()) return;

    final tfCountCtrl = TextEditingController(text: '10');
    final mcqCountCtrl = TextEditingController(text: '10');
    ChoiceSymbolType symbolType = ChoiceSymbolType.arabicLetters;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.checklist_rtl, color: Color(0xFF0F766E)),
              SizedBox(width: 8),
              Text(
                'إعدادات الاختبار المؤتمت (OMR)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'حدد عدد الفقرات لكل نمط سؤال ليتم توليد الأسئلة وشبكة دوائر التظليل آلياً:',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tfCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'عدد فقرات الصح والخطأ (ص / خ)',
                    hintText: 'مثال: 10',
                    prefixIcon: Icon(Icons.check_circle_outline, color: Colors.teal),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mcqCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'عدد فقرات الاختيار من متعدد',
                    hintText: 'مثال: 10 أو 20',
                    prefixIcon: Icon(Icons.format_list_numbered, color: Colors.teal),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'نوع رموز البدائل في الاختيارات:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(
                          child: Text('أ ، ب ، جـ ، د', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        selected: symbolType == ChoiceSymbolType.arabicLetters,
                        selectedColor: const Color(0xFF0F766E),
                        labelStyle: TextStyle(
                          color: symbolType == ChoiceSymbolType.arabicLetters ? Colors.white : Colors.black87,
                        ),
                        onSelected: (val) {
                          if (val) setDlgState(() => symbolType = ChoiceSymbolType.arabicLetters);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(
                          child: Text('١ ، ٢ ، ٣ ، ٤', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        selected: symbolType == ChoiceSymbolType.numbers,
                        selectedColor: const Color(0xFF0F766E),
                        labelStyle: TextStyle(
                          color: symbolType == ChoiceSymbolType.numbers ? Colors.white : Colors.black87,
                        ),
                        onSelected: (val) {
                          if (val) setDlgState(() => symbolType = ChoiceSymbolType.numbers);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              label: const Text(
                'توليد الاختبار',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              onPressed: () async {
                final int tfCount = int.tryParse(tfCountCtrl.text.trim()) ?? 10;
                final int mcqCount = int.tryParse(mcqCountCtrl.text.trim()) ?? 10;
                Navigator.pop(ctx);

                if (!_isActivated) {
                  await ActivationService.incrementTrialCount();
                }

                _generateAutomatedExam(
                  tfCount: tfCount,
                  mcqCount: mcqCount,
                  symbolType: symbolType,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // توليد كائن الاختبار المؤتمت بحسب الإعدادات المدخلة
  void _generateAutomatedExam({
    required int tfCount,
    required int mcqCount,
    required ChoiceSymbolType symbolType,
  }) {
    final List<QuestionModel> generatedQuestions = [];

    if (tfCount > 0) {
      final buffer = StringBuffer();
      buffer.writeln('ظلل الدائرة (ص) إذا كانت العبارة صحيحة، والدائرة (خ) إذا كانت العبارة خاطئة:');
      for (int i = 1; i <= tfCount; i++) {
        buffer.writeln('$i - (   ) ................................................................');
      }

      generatedQuestions.add(
        QuestionModel(
          id: const Uuid().v4(),
          title: 'س ١',
          titleOrientation: QuestionTitleOrientation.horizontal,
          mark: tfCount.toDouble(),
          spans: [
            TextSpanModel(
              text: buffer.toString().trim(),
              fontSize: 13.0,
              fontFamily: 'Amiri',
            ),
          ],
          answerKey: '',
          isTwoColumns: false,
        ),
      );
    }

    if (mcqCount > 0) {
      final buffer = StringBuffer();
      final bool isLetters = symbolType == ChoiceSymbolType.arabicLetters;
      final choicesStr = isLetters
          ? '[ أ- .. | ب- .. | جـ- .. | د- .. ]'
          : '[ ١- .. | ٢- .. | ٣- .. | ٤- .. ]';

      buffer.writeln('ظلل الدائرة التي تمثل الإجابة الصحيحة لكل فقرة من الفقرات الآتية:');
      for (int i = 1; i <= mcqCount; i++) {
        buffer.writeln('$i - ........................................ $choicesStr');
      }

      generatedQuestions.add(
        QuestionModel(
          id: const Uuid().v4(),
          title: tfCount > 0 ? 'س ٢' : 'س ١',
          titleOrientation: QuestionTitleOrientation.horizontal,
          mark: mcqCount.toDouble(),
          spans: [
            TextSpanModel(
              text: buffer.toString().trim(),
              fontSize: 13.0,
              fontFamily: 'Amiri',
            ),
          ],
          answerKey: '',
          isTwoColumns: true,
        ),
      );
    }

    final newExam = ExamModel(
      id: const Uuid().v4(),
      fileName: 'اختبار_مؤتمت_${DateTime.now().millisecondsSinceEpoch}',
      examType: ExamType.automated,
      automatedConfig: AutomatedExamConfig(
        trueFalseCount: tfCount,
        mcqCount: mcqCount,
        choiceSymbolType: symbolType,
      ),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      header: HeaderModel(
        examTitle: 'اختبار مؤتمت (نماذج التظليل الذكية)',
        instructionText: 'أجب بتظليل الدائرة المناسبة في ورقة الإجابة المخصصة',
      ),
      questions: generatedQuestions,
    );

    _openEditor(newExam, isNew: true);
  }

  // فتح المحرر لتعديل الاختبار
  void _openEditor(ExamModel exam, {bool isNew = false}) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExamEditorScreen(
          initialExam: exam,
          isNewExam: isNew,
        ),
      ),
    );

    if (result == true) {
      _loadExams();
      _checkActivationStatus();
    }
  }

  // استيراد ملف مشروع .exam
  Future<void> _importExamProjectDialog() async {
    if (!await _verifyTrialOrActivated()) return;

    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
      if (!downloadsDir.existsSync()) {
        downloadsDir = await getExternalStorageDirectory();
      }
    } else {
      downloadsDir = await getApplicationDocumentsDirectory();
    }

    List<FileSystemEntity> examFiles = [];
    if (downloadsDir != null && downloadsDir.existsSync()) {
      examFiles = downloadsDir
          .listSync()
          .where((f) => f.path.endsWith('.exam'))
          .toList();
    }

    if (!mounted) return;

    if (examFiles.isEmpty) {
      final pathCtrl = TextEditingController();
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('استيراد ملف اختبار (.exam)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'لم يتم العثور على ملفات .exam في مجلد التنزيلات.\nيمكنك كتابة مسار الملف مباشرة:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pathCtrl,
                decoration: const InputDecoration(
                  labelText: 'مسار الملف الكامل',
                  hintText: '/storage/emulated/0/Download/exam.exam',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                final path = pathCtrl.text.trim();
                if (path.isNotEmpty) {
                  Navigator.pop(ctx);
                  if (!_isActivated) await ActivationService.incrementTrialCount();
                  await _processImportedFile(path);
                }
              },
              child: const Text('فتح واستيراد'),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر ملف الاختبار (.exam)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: examFiles.length,
            itemBuilder: (context, i) {
              final file = examFiles[i];
              final name = file.path.split('/').last;
              return ListTile(
                leading: const Icon(Icons.file_present, color: Color(0xFF1E3A8A)),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onTap: () async {
                  Navigator.pop(ctx);
                  if (!_isActivated) await ActivationService.incrementTrialCount();
                  await _processImportedFile(file.path);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  // معالجة الملف المستورد وفتحه
  Future<void> _processImportedFile(String path) async {
    final imported = await ExamShareService.importExamFile(path);
    if (!mounted) return;

    if (imported != null) {
      await ExamStorageService.saveOrUpdateExam(imported);
      _loadExams();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم استيراد اختبار "${imported.header.subject}" بنجاح'),
          backgroundColor: Colors.green.shade800,
        ),
      );
      _openEditor(imported);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('تعذر قراءة ملف الاختبار أو أن الملف تالف'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // حذف اختبار بعد التأكيد
  Future<void> _confirmDelete(ExamModel exam) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف اختبار "${exam.header.subject}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ExamStorageService.deleteExam(exam.id);
      _loadExams();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'محرر الاختبارات المدرسية والأتمتة',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'عن مطور النظام',
            onPressed: _showDeveloperInfoDialog,
          ),
          IconButton(
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'استيراد اختبار (.exam)',
            onPressed: _importExamProjectDialog,
          ),
          if (!_isActivated)
            IconButton(
              icon: const Icon(Icons.key, color: Colors.amberAccent),
              tooltip: 'تنشيط النسخة الكاملة',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ActivationScreen()),
                ).then((_) {
                  _checkActivationStatus();
                  _loadExams();
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث القائمة',
            onPressed: _loadExams,
          ),
        ],
      ),
      body: Column(
        children: [
          // شريط إشعار النسخة التجريبية بالأيام المتبقية
          if (!_isActivated)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Colors.brown, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _remainingDays > 0
                          ? 'أنت في الفترة التجريبية: متبقي لديك $_remainingDays يوماً لتجربة كافة الميزات.'
                          : 'انتهت الفترة التجريبية للاختبار المجاني على هذا الجهاز.',
                      style: const TextStyle(color: Colors.brown, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ActivationScreen()),
                      ).then((_) {
                        _checkActivationStatus();
                        _loadExams();
                      });
                    },
                    child: const Text('تنشيط الآن', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _exams.isEmpty
                    ? _buildEmptyState()
                    : _buildExamsList(),
          ),

          // شريط توقيع وبصمة المطور الدائم أسفل الشاشة الرئيسية
          InkWell(
            onTap: _showDeveloperInfoDialog,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.workspace_premium, size: 14, color: Color(0xFFD97706)),
                  SizedBox(width: 6),
                  Text(
                    'إعداد وتطوير: أ. فواز سنان البعيثي © 2026',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.edit_document, color: Colors.white, size: 20),
                  label: const Text(
                    'الاختبارات الشاملة',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _createTraditionalExam,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.checklist_rtl, color: Colors.white, size: 20),
                  label: const Text(
                    'اختبار مؤتمت (OMR)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _showCreateAutomatedExamDialog,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 85, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'لا توجد اختبارات محفوظة بعد',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'اختر أحد الزرين بالأسفل لإنشاء اختبار شامل أو مؤتمت',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildExamsList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      itemCount: _exams.length,
      itemBuilder: (context, index) {
        final exam = _exams[index];
        final bool isAutomated = exam.examType == ExamType.automated;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openEditor(exam),
            child: Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          exam.header.subject.isNotEmpty ? exam.header.subject : 'مادة غير محددة',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isAutomated ? Colors.teal.shade50 : Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isAutomated ? Colors.teal.shade300 : Colors.blue.shade300,
                              ),
                            ),
                            child: Text(
                              isAutomated ? 'مؤتمت OMR' : 'شامل / تحريري',
                              style: TextStyle(
                                color: isAutomated ? const Color(0xFF0F766E) : const Color(0xFF1E3A8A),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Text(
                              exam.header.grade,
                              style: TextStyle(color: Colors.grey.shade800, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    exam.header.examTitle,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Divider(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            FileManager.sanitizeFileName(exam.fileName),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            'الدرجة: ${exam.totalMarks}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            onPressed: () => _confirmDelete(exam),
                          ),
                        ],
                      )
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

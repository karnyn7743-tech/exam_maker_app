import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/exam_models.dart';
import '../services/exam_share_service.dart';
import '../services/exam_storage_service.dart';
import '../services/file_manager.dart';
import 'exam_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ExamModel> _exams = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadExams();
  }

  // تحميل قائمة الاختبارات من الذاكرة المحلية
  Future<void> _loadExams() async {
    setState(() => _isLoading = true);
    final list = await ExamStorageService.getAllExams();
    setState(() {
      _exams = list;
      _isLoading = false;
    });
  }

  // 1. الشروع في الاختبارات الشاملة (التحريرية التقليدية)
  void _createTraditionalExam() {
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

  // 2. إنشاء اختبار مؤتمت (تظليل OMR) مع حوار تحديد الفقرات والرموز
  void _showCreateAutomatedExamDialog() {
    final tfCountCtrl = TextEditingController(text: '10');
    final mcqCountCtrl = TextEditingController(text: '10');
    ChoiceSymbolType symbolType = ChoiceSymbolType.arabicLetters;

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
              onPressed: () {
                final int tfCount = int.tryParse(tfCountCtrl.text.trim()) ?? 10;
                final int mcqCount = int.tryParse(mcqCountCtrl.text.trim()) ?? 10;
                Navigator.pop(ctx);
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

    // 1. توليد سؤال الصح والخطأ بحسب العدد المدخل
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

    // 2. توليد سؤال الاختيار من متعدد بحسب العدد ونوع الرموز المختار
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
    }
  }

  // استيراد ملف مشروع .exam
  Future<void> _importExamProjectDialog() async {
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

    // عرض قائمة الملفات المتوفرة في مجلد التنزيلات
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
            icon: const Icon(Icons.file_open_outlined),
            tooltip: 'استيراد اختبار (.exam)',
            onPressed: _importExamProjectDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث القائمة',
            onPressed: _loadExams,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _exams.isEmpty
              ? _buildEmptyState()
              : _buildExamsList(),
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
              // الزر الأول: الشروع في الاختبارات الشاملة (التحريرية التقليدية)
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
              // الزر الثاني: إنشاء اختبار مؤتمت (تظليل OMR)
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

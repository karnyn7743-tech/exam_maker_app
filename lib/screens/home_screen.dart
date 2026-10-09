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

  // إنشاء اختبار جديد بالقيم الافتراضية
  void _createNewExam() {
    final newExam = ExamModel(
      id: const Uuid().v4(),
      fileName: 'اختبار_جديد_${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      header: HeaderModel(),
      questions: [],
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
          'أرشيف الاختبارات المدرسية',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNewExam,
        icon: const Icon(Icons.add),
        label: const Text('إنشاء اختبار جديد', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 90, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'لا توجد اختبارات محفوظة بعد',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'اضغط على زر (إنشاء اختبار جديد) للبدء أو استورد ملف (.exam)',
            style: TextStyle(color: Colors.grey),
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
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          exam.header.grade,
                          style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                        ),
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

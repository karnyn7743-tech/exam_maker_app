
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:uuid/uuid.dart';

import '../models/exam_models.dart';
import '../services/activation_service.dart';
import '../services/exam_storage_service.dart';
import '../services/pdf_import_service.dart';

import 'activation_screen.dart';
import 'exam_editor_screen.dart';
import 'grade_scanner_screen.dart';
import 'manual_grade_entry_screen.dart';
import 'fetch_grades_screen.dart';
import 'document_hub_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isActivated = false;
  int _remainingDays = 0;

  StreamSubscription? _intentDataStreamSubscription;

  // منع فتح الملف نفسه أكثر من مرة في الوقت نفسه.
  final Set<String> _openingFilePaths = {};

  // ============================================================
  // دورة حياة الشاشة
  // ============================================================

  @override
  void initState() {
    super.initState();

    _checkActivationStatus();
    _initFolderAndIncomingFiles();
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    super.dispose();
  }

  // ============================================================
  // تهيئة مجلد التطبيق واستقبال الملفات الخارجية
  // ============================================================

  /// تجهيز مجلد [المحرر البسيط] ومزامنة الملفات،
  /// والاستماع إلى ملفات .exam القادمة من التطبيقات الأخرى.
  Future<void> _initFolderAndIncomingFiles() async {
    try {
      await ExamStorageService.ensureAppFolderExists();

      await ExamStorageService.syncFolderExamsToApp();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر تجهيز مجلد الاختبارات: $e'),
            backgroundColor: Colors.orange.shade800,
          ),
        );
      }
    }

    if (!mounted) return;

    // استقبال الملفات أثناء عمل التطبيق.
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
      (List<SharedMediaFile> files) {
        final examFile = _findExamFile(files);

        if (examFile != null) {
          _openIncomingExamFile(examFile.path);
        }
      },
      onError: (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تعذر استقبال الملف: $error'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
      },
    );

    // استقبال الملف الذي تسبب في تشغيل التطبيق.
    try {
      final initialFiles =
          await ReceiveSharingIntent.instance.getInitialMedia();

      if (!mounted) return;

      final examFile = _findExamFile(initialFiles);

      if (examFile != null) {
        await _openIncomingExamFile(examFile.path);
      }

      ReceiveSharingIntent.instance.reset();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر استقبال ملف الاختبار الأولي: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// البحث عن ملف .exam ضمن الملفات المستلمة.
  ///
  /// قد ترسل التطبيقات الأخرى أكثر من ملف،
  /// لذلك لا نفترض أن الملف الأول هو المطلوب.
  SharedMediaFile? _findExamFile(
    List<SharedMediaFile> files,
  ) {
    for (final file in files) {
      if (file.path.toLowerCase().endsWith('.exam')) {
        return file;
      }
    }

    return null;
  }

  // ============================================================
  // فتح ملفات الاختبارات
  // ============================================================

  /// قراءة ملف الاختبار وفتحه مباشرة في المحرر.
  ///
  /// تحتفظ خدمة التخزين بمسار الملف الأصلي في filePath،
  /// حتى يمكن حفظ التعديلات في الملف نفسه.
  Future<void> _openIncomingExamFile(String filePath) async {
    final normalizedPath = filePath.trim();

    if (normalizedPath.isEmpty) return;

    if (!normalizedPath.toLowerCase().endsWith('.exam')) {
      return;
    }

    // منع فتح الملف نفسه مرتين في الوقت نفسه.
    if (_openingFilePaths.contains(normalizedPath)) {
      return;
    }

    _openingFilePaths.add(normalizedPath);

    try {
      final importedExam =
          await ExamStorageService.loadExamFromFile(normalizedPath);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم فتح الاختبار: ${importedExam.fileName}',
          ),
          backgroundColor: const Color(0xFF1B5E20),
          duration: const Duration(seconds: 2),
        ),
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExamEditorScreen(
            initialExam: importedExam,
            isNewExam: false,
          ),
        ),
      );

      if (mounted) {
        await _checkActivationStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر فتح الملف؛ تأكد من أنه ملف اختبار صالح بصيغة (.exam)\n$e',
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      _openingFilePaths.remove(normalizedPath);
    }
  }

  /// اختيار ملف .exam يدوياً من مدير الملفات.
  Future<void> _pickAndOpenExamFileManually() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      final selectedFile = result.files.single;

      final path = selectedFile.path;

      if (path == null || path.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'تعذر الوصول إلى مسار الملف المحدد.',
              ),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
        return;
      }

      if (!path.toLowerCase().endsWith('.exam')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'يرجى اختيار ملف ينتهي بالامتداد (.exam)',
              ),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
        return;
      }

      await _openIncomingExamFile(path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر استعراض الملف: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// استيراد صفحة أو أكثر من ملف PDF إلى صفحات ثابتة داخل محرر الاختبارات.
  Future<void> _pickAndImportPdf() async {
    if (!await _verifyTrialOrActivated()) return;

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: false,
      );

      if (picked == null || picked.files.isEmpty) return;
      final pdfPath = picked.files.single.path;
      if (pdfPath == null || pdfPath.trim().isEmpty) {
        throw Exception('تعذر الوصول إلى ملف PDF المحدد.');
      }

      final totalPages = await PdfImportService.getPageCount(pdfPath);
      if (totalPages < 1) {
        throw Exception('ملف PDF لا يحتوي على صفحات قابلة للاستيراد.');
      }

      final options = await showDialog<Map<String, double>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _PdfCropDialog(
          pdfPath: pdfPath,
          totalPages: totalPages,
        ),
      );

      if (options == null || !mounted) return;

      final firstPage = options['first']!.toInt();
      final pageCount = options['count']!.toInt();
      if (firstPage + pageCount - 1 > totalPages) {
        throw Exception('نطاق الصفحات يتجاوز عدد صفحات ملف PDF.');
      }

      final examId = const Uuid().v4();
      final imagePaths = await PdfImportService.importPages(
        pdfPath: pdfPath,
        examId: examId,
        firstPage: firstPage,
        pageCount: pageCount,
        cropTopMm: options['top']!,
        cropBottomMm: options['bottom']!,
      );

      final now = DateTime.now();
      final pageBreaks = List<QuestionModel>.generate(
        pageCount - 1,
        (index) => QuestionModel(
          id: 'page_break_${const Uuid().v4()}',
          title: '',
          spans: [],
        ),
      );

      final selectedName = picked.files.single.name;
      final rawName = selectedName.toLowerCase().endsWith('.pdf')
          ? selectedName.substring(0, selectedName.length - 4)
          : selectedName;

      final importedExam = ExamModel(
        id: examId,
        fileName: rawName.trim().isEmpty ? 'مستند_PDF_مستورد' : rawName,
        examType: ExamType.traditional,
        isArabic: true,
        createdAt: now,
        updatedAt: now,
        header: HeaderModel(),
        questions: pageBreaks,
        importedPdfPagePaths: imagePaths,
      );

      if (!_isActivated) {
        await ActivationService.incrementTrialCount();
      }
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم استيراد $pageCount صفحة من ملف PDF.')),
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExamEditorScreen(
            initialExam: importedExam,
            isNewExam: true,
          ),
        ),
      );

      if (mounted) await _checkActivationStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر استيراد ملف PDF: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  // ============================================================
  // حالة التفعيل
  // ============================================================

  Future<void> _checkActivationStatus() async {
    try {
      final status = await ActivationService.getLicenseStatus();

      final remaining =
          await ActivationService.getRemainingTrialDays();

      if (!mounted) return;

      setState(() {
        _isActivated = status == LicenseStatus.full;
        _remainingDays = remaining;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر التحقق من حالة التفعيل: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<bool> _verifyTrialOrActivated() async {
    final status = await ActivationService.getLicenseStatus();

    if (status == LicenseStatus.full ||
        status == LicenseStatus.trial) {
      return true;
    }

    if (!mounted) return false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(
              Icons.lock_clock,
              color: Colors.amber,
            ),
            SizedBox(width: 8),
            Text(
              'انتهت الفترة التجريبية',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: const Text(
          'انتهت فترة الـ 30 يوماً المتاحة لتجربة التطبيق.\n'
          'لإنشاء المزيد من الاختبارات والوصول لجميع الميزات، يرجى تفعيل النسخة الكاملة.',
          style: TextStyle(
            fontSize: 13,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
            ),
            onPressed: () {
              Navigator.pop(ctx);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ActivationScreen(),
                ),
              ).then((_) => _checkActivationStatus());
            },
            child: const Text(
              'إدخال مفتاح التنشيط',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    return false;
  }

  // ============================================================
  // تصميم اختبار شامل
  // ============================================================

  Future<void> _designTraditionalExam() async {
    if (!await _verifyTrialOrActivated()) return;

    if (!_isActivated) {
      await ActivationService.incrementTrialCount();
    }

    final newExam = ExamModel(
      id: const Uuid().v4(),
      fileName:
          'اختبار_شامل_${DateTime.now().millisecondsSinceEpoch}',
      examType: ExamType.traditional,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      header: HeaderModel(),
      questions: [],
    );

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamEditorScreen(
          initialExam: newExam,
          isNewExam: true,
        ),
      ),
    ).then((_) => _checkActivationStatus());
  }

  // ============================================================
  // تصميم اختبار مؤتمت
  // ============================================================

  Future<void> _designAutomatedExam() async {
    if (!await _verifyTrialOrActivated()) return;

    final tfCountCtrl = TextEditingController(text: '10');

    final mcqCountCtrl = TextEditingController(text: '10');

    ChoiceSymbolType symbolType =
        ChoiceSymbolType.arabicLetters;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: Row(
            children: const [
              Icon(
                Icons.checklist_rtl,
                color: Color(0xFF1B5E20),
              ),
              SizedBox(width: 8),
              Text(
                'إعدادات الاختبار المؤتمت (OMR)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'حدد عدد الفقرات لكل نمط سؤال:',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tfCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'عدد فقرات الصح والخطأ (ص / خ)',
                    prefixIcon: Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF1B5E20),
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: mcqCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'عدد فقرات الاختيار من متعدد',
                    prefixIcon: Icon(
                      Icons.format_list_numbered,
                      color: Color(0xFF1B5E20),
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'نوع رموز البدائل:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(
                          child: Text('أ ، ب ، جـ ، د'),
                        ),
                        selected: symbolType ==
                            ChoiceSymbolType.arabicLetters,
                        selectedColor:
                            const Color(0xFF1B5E20),
                        labelStyle: TextStyle(
                          color: symbolType ==
                                  ChoiceSymbolType.arabicLetters
                              ? Colors.white
                              : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setDlgState(() {
                              symbolType =
                                  ChoiceSymbolType.arabicLetters;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Center(
                          child: Text('١ ، ٢ ، ٣ ، ٤'),
                        ),
                        selected: symbolType ==
                            ChoiceSymbolType.numbers,
                        selectedColor:
                            const Color(0xFF1B5E20),
                        labelStyle: TextStyle(
                          color: symbolType ==
                                  ChoiceSymbolType.numbers
                              ? Colors.white
                              : Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                        onSelected: (val) {
                          if (val) {
                            setDlgState(() {
                              symbolType =
                                  ChoiceSymbolType.numbers;
                            });
                          }
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
              ),
              onPressed: () {
                final tf =
                    int.tryParse(tfCountCtrl.text.trim()) ?? 10;

                final mcq =
                    int.tryParse(mcqCountCtrl.text.trim()) ?? 10;

                Navigator.pop(ctx);

                _generateAutomatedExam(
                  tfCount: tf,
                  mcqCount: mcq,
                  symbolType: symbolType,
                );
              },
              child: const Text(
                'توليد الاختبار',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      tfCountCtrl.dispose();
      mcqCountCtrl.dispose();
    });
  }

  void _generateAutomatedExam({
    required int tfCount,
    required int mcqCount,
    required ChoiceSymbolType symbolType,
  }) {
    final List<QuestionModel> generatedQuestions = [];

    if (tfCount > 0) {
      final buffer = StringBuffer();

      buffer.writeln(
        'ظلل الدائرة (ص) إذا كانت العبارة صحيحة، والدائرة (خ) إذا كانت العبارة خاطئة:',
      );

      for (int i = 1; i <= tfCount; i++) {
        buffer.writeln(
          '$i - (   ) ................................................................',
        );
      }

      generatedQuestions.add(
        QuestionModel(
          id: const Uuid().v4(),
          title: 'س ١',
          titleOrientation:
              QuestionTitleOrientation.horizontal,
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

      final bool isLetters =
          symbolType == ChoiceSymbolType.arabicLetters;

      final choicesStr = isLetters
          ? '[ أ- .. | ب- .. | جـ- .. | د- .. ]'
          : '[ ١- .. | ٢- .. | ٣- .. | ٤- .. ]';

      buffer.writeln(
        'ظلل الدائرة التي تمثل الإجابة الصحيحة لكل فقرة من الفقرات الآتية:',
      );

      for (int i = 1; i <= mcqCount; i++) {
        buffer.writeln(
          '$i - ........................................ $choicesStr',
        );
      }

      generatedQuestions.add(
        QuestionModel(
          id: const Uuid().v4(),
          title: tfCount > 0 ? 'س ٢' : 'س ١',
          titleOrientation:
              QuestionTitleOrientation.horizontal,
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
      fileName:
          'اختبار_مؤتمت_${DateTime.now().millisecondsSinceEpoch}',
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
        instructionText:
            'أجب بتظليل الدائرة المناسبة في ورقة الإجابة المخصصة',
      ),
      questions: generatedQuestions,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamEditorScreen(
          initialExam: newExam,
          isNewExam: true,
        ),
      ),
    ).then((_) => _checkActivationStatus());
  }

  // ============================================================
  // شاشات إدخال الدرجات
  // ============================================================

  // إدخال درجات الطلاب من أوراق الاختبار.
  void _openGradeScanner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const GradeScannerScreen(),
      ),
    );
  }

  // إدخال بقية درجات أعمال السنة.
  void _openManualGradeEntry() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ManualGradeEntryScreen(),
      ),
    );
  }

  // جلب درجات المحصلات.
  void _openFetchGradesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FetchGradesScreen(),
      ),
    );
  }

  // ============================================================
  // الاختبارات المحفوظة
  // ============================================================

  /// عرض قائمة الاختبارات المحفوظة.
  Future<void> _showSavedExamsModal() async {
    try {
      final exams = await ExamStorageService.getAllExams();

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(20),
          ),
        ),
        builder: (ctx) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'الاختبارات المحفوظة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'مجلد الحفظ: Download/المحرر البسيط',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${exams.length} اختبار',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: exams.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد اختبارات محفوظة بعد',
                          style: TextStyle(
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: exams.length,
                        itemBuilder: (context, i) {
                          final e = exams[i];

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  const Color(0xFF1B5E20),
                              child: Icon(
                                e.examType ==
                                        ExamType.automated
                                    ? Icons.checklist_rtl
                                    : Icons.description,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              e.fileName.isNotEmpty
                                  ? e.fileName
                                  : (e.header.subject.isNotEmpty
                                      ? e.header.subject
                                      : 'مادة غير محددة'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${e.header.grade} - ${e.header.subject} | ${e.header.examTitle}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () async {
                                await _deleteSavedExam(
                                  context: ctx,
                                  exam: e,
                                );
                              },
                            ),
                            onTap: () {
                              Navigator.pop(ctx);

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ExamEditorScreen(
                                    initialExam: e,
                                    isNewExam: false,
                                  ),
                                ),
                              ).then(
                                (_) => _checkActivationStatus(),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تعذر استرجاع الاختبارات المحفوظة: $e',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// حذف اختبار من القائمة ومن ملفه المرتبط.
  Future<void> _deleteSavedExam({
    required BuildContext context,
    required ExamModel exam,
  }) async {
    try {
      await ExamStorageService.deleteExam(exam.id);

      if (!mounted || !context.mounted) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الاختبار بنجاح'),
          backgroundColor: Color(0xFF1B5E20),
        ),
      );

      _showSavedExamsModal();
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حذف الاختبار: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _openDocumentHub() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DocumentHubScreen()),
    );
    if (mounted) await _checkActivationStatus();
  }

  Future<void> _showActionGroupDialog({
    required String title,
    required String subtitle,
    required List<_ActionChoice> options,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          decoration: const BoxDecoration(
            color: Color(0xFFFAF8F1),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4D0C5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF344E41),
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF777568), fontSize: 12),
              ),
              const SizedBox(height: 16),
              for (final option in options) ...[
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(17),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      option.onTap();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: const Color(0xFFE4E0D5)),
                      ),
                      child: Row(
                        children: [
                          Icon(option.icon, color: const Color(0xFF52796F), size: 27),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  option.title,
                                  style: const TextStyle(
                                    color: Color(0xFF344E41),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  option.subtitle,
                                  style: const TextStyle(
                                    color: Color(0xFF777568),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_left, color: Color(0xFF9A9A8D)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // بناء الواجهة
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F0E7),
      appBar: AppBar(
        title: const Text(
          'المحرر البسيط للإختبارات والأتمتة',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF52796F),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.file_open_outlined,
              color: Colors.white,
            ),
            tooltip: 'استيراد وفتح ملف (.exam)',
            onPressed: _pickAndOpenExamFileManually,
          ),
          IconButton(
            icon: const Icon(
              Icons.folder_open,
              color: Colors.white,
            ),
            tooltip: 'الاختبارات المحفوظة',
            onPressed: _showSavedExamsModal,
          ),
          if (!_isActivated)
            IconButton(
              icon: const Icon(
                Icons.key,
                color: Colors.amberAccent,
              ),
              tooltip: 'تنشيط النسخة الكاملة',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ActivationScreen(),
                  ),
                ).then((_) => _checkActivationStatus());
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isActivated)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              color: Colors.amber.shade100,
              child: Row(
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color: Colors.brown,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _remainingDays > 0
                          ? 'الفترة التجريبية: متبقي لديك $_remainingDays يوماً.'
                          : 'انتهت الفترة التجريبية للاختبار المجاني.',
                      style: const TextStyle(
                        color: Colors.brown,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              const ActivationScreen(),
                        ),
                      ).then((_) => _checkActivationStatus());
                    },
                    child: const Text(
                      'تنشيط الآن',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildMainActionButton(
                      title: 'الاختبارات المحررة باليد',
                      icon: Icons.edit_document,
                      onTap: () => _showActionGroupDialog(
                        title: 'الاختبارات المحررة باليد',
                        subtitle: 'اختر نوع الاختبار الذي تريد تصميمه',
                        options: [
                          _ActionChoice(
                            title: 'اختبارات شاملة',
                            subtitle: 'تصميم اختبار تحريري تقليدي',
                            icon: Icons.description_outlined,
                            onTap: _designTraditionalExam,
                          ),
                          _ActionChoice(
                            title: 'اختبارات مؤتمتة',
                            subtitle: 'تصميم اختبار التظليل والتصحيح الآلي',
                            icon: Icons.fact_check_outlined,
                            onTap: _designAutomatedExam,
                          ),
                          _ActionChoice(
                            title: 'استيراد صفحات من ملف PDF',
                            subtitle: 'معاينة صفحات PDF وقص الجزء المطلوب قبل إضافته إلى الاختبار',
                            icon: Icons.picture_as_pdf_outlined,
                            onTap: _pickAndImportPdf,
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF718B79),
                    ),
                    const SizedBox(height: 15),
                    _buildMainActionButton(
                      title: 'إدخال الدرجات',
                      icon: Icons.assignment_turned_in_outlined,
                      onTap: () => _showActionGroupDialog(
                        title: 'إدخال الدرجات',
                        subtitle: 'اختر طريقة إدخال درجات الطلاب',
                        options: [
                          _ActionChoice(
                            title: 'إدخال الدرجات من أوراق الاختبارات',
                            subtitle: 'قراءة الأكواد وإدخال درجات أوراق الإجابة',
                            icon: Icons.qr_code_scanner,
                            onTap: _openGradeScanner,
                          ),
                          _ActionChoice(
                            title: 'إدخال بقية أعمال السنة',
                            subtitle: 'إدخال درجات الأنشطة والأعمال الأخرى',
                            icon: Icons.playlist_add_check,
                            onTap: _openManualGradeEntry,
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF6F9290),
                    ),
                    const SizedBox(height: 15),
                    _buildMainActionButton(
                      title: 'جلب درجات أعمال السنة إلى كشوفات الرصد',
                      icon: Icons.sync_alt,
                      onTap: _openFetchGradesScreen,
                      backgroundColor: const Color(0xFFB18A62),
                    ),
                    const SizedBox(height: 15),
                    _buildMainActionButton(
                      title: 'فتح وتحرير ملفات PDF وWord',
                      icon: Icons.article_outlined,
                      onTap: _openDocumentHub,
                      backgroundColor: const Color(0xFF7C829A),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // تفاصيل المطور وروابط التواصل الثابتة في الأسفل.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 16,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFEBE8DD),
              border: Border(
                top: BorderSide(
                  color: Colors.green.shade200,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إعداد وتطوير: أ. فواز سنان البعيثي',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          const ClipboardData(
                            text: '00967778064679',
                          ),
                        );

                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'تم نسخ رقم الواتساب: 00967778064679',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.phone_android,
                            size: 14,
                            color: Color(0xFF1B5E20),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'واتساب: 778064679',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          const ClipboardData(
                            text: 'https://t.me/fawaz132',
                          ),
                        );

                        ScaffoldMessenger.of(context)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'تم نسخ رابط قناة التليجرام',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.send_rounded,
                            size: 14,
                            color: Color(0xFF0284C7),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'تليجرام: @fawaz132',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // زر رئيسي موحد
  // ============================================================

  Widget _buildMainActionButton({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Color backgroundColor = const Color(0xFF718B79),
  }) {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(backgroundColor, Colors.white, 0.18)!,
            backgroundColor,
          ],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withOpacity(0.65), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: CustomPaint(
          painter: _SoftGeometricPatternPainter(),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(19),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 19),
                child: Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 29),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Color(0xFFECE9DF), size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// نافذة معاينة وقص صفحات PDF بالسحب قبل إدراجها في الاختبار.
class _PdfCropDialog extends StatefulWidget {
  final String pdfPath;
  final int totalPages;

  const _PdfCropDialog({
    required this.pdfPath,
    required this.totalPages,
  });

  @override
  State<_PdfCropDialog> createState() => _PdfCropDialogState();
}

class _PdfCropDialogState extends State<_PdfCropDialog> {
  static const double _pointsPerMm = 72.0 / 25.4;
  static const double _minimumContentMm = 25.0;

  final TextEditingController _firstPageController =
      TextEditingController(text: '1');
  late final TextEditingController _countController =
      TextEditingController(text: (widget.totalPages < 3 ? widget.totalPages : 3).toString());

  Uint8List? _previewBytes;
  double _pageHeightMm = 297.0;
  double _pageAspectRatio = 210.0 / 297.0;
  double _topCropMm = 110.0;
  double _bottomCropMm = 40.0;
  bool _loadingPreview = true;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  @override
  void dispose() {
    _firstPageController.dispose();
    _countController.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    final pageNumber = int.tryParse(_firstPageController.text.trim());
    if (pageNumber == null || pageNumber < 1 || pageNumber > widget.totalPages) {
      setState(() {
        _previewError = 'أدخل رقم صفحة صحيحًا لمعاينتها.';
        _loadingPreview = false;
      });
      return;
    }

    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });

    PdfDocument? document;
    PdfPage? page;
    try {
      document = await PdfDocument.openFile(widget.pdfPath);
      page = await document.getPage(pageNumber);
      final aspect = page.width / page.height;
      final rendered = await page.render(
        width: 1000,
        height: 1000 / aspect,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      if (rendered == null || rendered.bytes.isEmpty) {
        throw Exception('تعذرت معاينة الصفحة المحددة.');
      }
      final bytes = rendered.bytes;
      final pageHeightMm = page.height / _pointsPerMm;
      await page.close();
      page = null;
      await document.close();
      document = null;

      if (!mounted) return;
      setState(() {
        _previewBytes = bytes;
        _pageHeightMm = pageHeightMm;
        _pageAspectRatio = aspect;
        _topCropMm = _topCropMm.clamp(0.0, pageHeightMm - _bottomCropMm - _minimumContentMm).toDouble();
        _bottomCropMm = _bottomCropMm.clamp(0.0, pageHeightMm - _topCropMm - _minimumContentMm).toDouble();
        _loadingPreview = false;
      });
    } catch (e) {
      if (page != null && !page.isClosed) await page.close();
      if (document != null) await document.close();
      if (!mounted) return;
      setState(() {
        _previewError = 'تعذرت معاينة الصفحة: $e';
        _loadingPreview = false;
      });
    }
  }

  void _confirm() {
    final first = int.tryParse(_firstPageController.text.trim());
    final count = int.tryParse(_countController.text.trim());
    if (first == null || count == null || first < 1 || count < 1 ||
        count > 3 || first + count - 1 > widget.totalPages) {
      setState(() => _previewError = 'تحقق من رقم الصفحة وعدد الصفحات (من 1 إلى 3).');
      return;
    }
    if (_topCropMm + _bottomCropMm + _minimumContentMm > _pageHeightMm) {
      setState(() => _previewError = 'مساحة القص كبيرة جدًا؛ اترك جزءًا كافيًا من الورقة.');
      return;
    }
    Navigator.pop(context, {
      'first': first.toDouble(),
      'count': count.toDouble(),
      'top': _topCropMm,
      'bottom': _bottomCropMm,
    });
  }

  void _moveTop(double deltaY, double previewHeight) {
    if (previewHeight <= 0) return;
    setState(() {
      _topCropMm = (_topCropMm + deltaY / previewHeight * _pageHeightMm)
          .clamp(0.0, _pageHeightMm - _bottomCropMm - _minimumContentMm)
          .toDouble();
    });
  }

  void _moveBottom(double deltaY, double previewHeight) {
    if (previewHeight <= 0) return;
    setState(() {
      _bottomCropMm = (_bottomCropMm - deltaY / previewHeight * _pageHeightMm)
          .clamp(0.0, _pageHeightMm - _topCropMm - _minimumContentMm)
          .toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('معاينة وقص صفحات PDF'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('عدد صفحات الملف: ${widget.totalPages}'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _firstPageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'أول صفحة',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _loadPreview(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'معاينة الصفحة المحددة',
                    onPressed: _loadPreview,
                    icon: const Icon(Icons.refresh),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _countController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عدد الصفحات (1–3)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'اسحب الشريط العلوي والسفلي لتحديد الجزء الذي تريد الاحتفاظ به من الورقة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _loadingPreview
                    ? const SizedBox(
                        height: 260,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _previewError != null && _previewBytes == null
                        ? SizedBox(
                            height: 260,
                            child: Center(
                              child: Text(_previewError!, textAlign: TextAlign.center),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              return Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxHeight: 390),
                                  child: AspectRatio(
                                    aspectRatio: _pageAspectRatio,
                                    child: LayoutBuilder(
                                      builder: (context, box) {
                                        final height = box.maxHeight;
                                        final topY = height * _topCropMm / _pageHeightMm;
                                        final bottomY = height * (1 - _bottomCropMm / _pageHeightMm);
                                        return ClipRect(
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.memory(_previewBytes!, fit: BoxFit.fill),
                                              Positioned(
                                                left: 0, right: 0, top: 0,
                                                height: topY,
                                                child: IgnorePointer(
                                                  child: Container(color: Colors.black.withOpacity(0.48)),
                                                ),
                                              ),
                                              Positioned(
                                                left: 0, right: 0, top: bottomY,
                                                bottom: 0,
                                                child: IgnorePointer(
                                                  child: Container(color: Colors.black.withOpacity(0.48)),
                                                ),
                                              ),
                                              Positioned(
                                                left: 0, right: 0,
                                                top: (topY - 15).clamp(0.0, height - 30),
                                                height: 30,
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onVerticalDragUpdate: (d) => _moveTop(d.delta.dy, height),
                                                  child: Center(
                                                    child: Container(
                                                      height: 25,
                                                      width: double.infinity,
                                                      alignment: Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue.withOpacity(0.92),
                                                        border: const Border(
                                                          top: BorderSide(color: Colors.white, width: 1),
                                                          bottom: BorderSide(color: Colors.white, width: 1),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        'حد القص العلوي • ${_topCropMm.toStringAsFixed(1)} مم',
                                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              Positioned(
                                                left: 0, right: 0,
                                                top: (bottomY - 15).clamp(0.0, height - 30),
                                                height: 30,
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior.opaque,
                                                  onVerticalDragUpdate: (d) => _moveBottom(d.delta.dy, height),
                                                  child: Center(
                                                    child: Container(
                                                      height: 25,
                                                      width: double.infinity,
                                                      alignment: Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: Colors.deepOrange.withOpacity(0.94),
                                                        border: const Border(
                                                          top: BorderSide(color: Colors.white, width: 1),
                                                          bottom: BorderSide(color: Colors.white, width: 1),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        'حد القص السفلي • ${_bottomCropMm.toStringAsFixed(1)} مم',
                                                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text('المقصوص من الأعلى: ${_topCropMm.toStringAsFixed(1)} مم'),
                  Text('المقصوص من الأسفل: ${_bottomCropMm.toStringAsFixed(1)} مم'),
                ],
              ),
              if (_previewError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_previewError!, style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _loadingPreview || _previewBytes == null ? null : _confirm,
          child: const Text('اعتماد القص ومتابعة'),
        ),
      ],
    );
  }
}

class _ActionChoice {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionChoice({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
}

class _SoftGeometricPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    for (var i = -1; i < 5; i++) {
      final x = size.width - 18.0 - (i * 25.0);
      canvas.drawCircle(Offset(x, 10), 16, paint);
      canvas.drawCircle(Offset(x, 10), 8, paint);
    }

    final path = Path()
      ..moveTo(size.width * 0.52, 0)
      ..lineTo(size.width * 0.72, size.height)
      ..moveTo(size.width * 0.64, 0)
      ..lineTo(size.width * 0.84, size.height)
      ..moveTo(0, size.height * 0.78)
      ..lineTo(size.width * 0.20, size.height)
      ..moveTo(size.width * 0.80, 0)
      ..lineTo(size.width, size.height * 0.20);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

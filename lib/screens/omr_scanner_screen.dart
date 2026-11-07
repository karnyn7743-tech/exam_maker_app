import 'dart:io';
import 'package:camera/camera.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/exam_models.dart';
import '../services/student_excel_service.dart';

class OmrScannerScreen extends StatefulWidget {
  final ExamModel exam;

  const OmrScannerScreen({super.key, required this.exam});

  @override
  State<OmrScannerScreen> createState() => _OmrScannerScreenState();
}

class _OmrScannerScreenState extends State<OmrScannerScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isProcessing = false;
  String? _statusText;

  // متغيرات ربط الإكسيل والتحكم بالحقول
  String? _selectedExcelPath;
  String? _selectedSheetName;
  String? _selectedPeriod;
  bool _excelLoaded = false;
  int _detectedTotalMonths = 8;

  List<String> _availableSheets = [];
  List<String> _evaluationPeriods = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
    // فحص ما إذا كان الاختبار يحتوي على مسار ملف إكسيل مسبقاً
    if (widget.exam.header.excelFilePath != null &&
        File(widget.exam.header.excelFilePath!).existsSync()) {
      _processExcelFile(widget.exam.header.excelFilePath!);
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        _cameraController = CameraController(
          _cameras!.first,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await _cameraController!.initialize();
        if (mounted) {
          setState(() => _isCameraInitialized = true);
        }
      } else {
        setState(() => _statusText = 'لا توجد كاميرا متاحة على هذا الجهاز');
      }
    } catch (e) {
      setState(() => _statusText = 'تعذر تشغيل الكاميرا: $e');
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  /// اختيار ملف الإكسيل يدوياً
  Future<void> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'xlsm', 'xlsb'],
    );

    if (result != null && result.files.single.path != null) {
      await _processExcelFile(result.files.single.path!);
    }
  }

  /// معالجة ملف الإكسيل والتحقق الصارم من التنسيق
  Future<void> _processExcelFile(String path) async {
    setState(() => _isProcessing = true);

    // 1. التحقق من مطابقة بنية الملف
    final bool isValid = await StudentExcelService.validateExcelStructure(path);
    if (!isValid) {
      setState(() {
        _excelLoaded = false;
        _selectedExcelPath = null;
        _availableSheets = [];
        _evaluationPeriods = [];
        _selectedSheetName = null;
        _selectedPeriod = null;
        _isProcessing = false;
      });

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: Colors.red),
                SizedBox(width: 8),
                Text('تنبيه التنسيق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: const Text(
              'ملف الأكسيل المختار لا يتطابق مع تنسيقات الملف المطلوب ، يرجى التأكد من الإختيار مرة أخرى',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('حسناً', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 2. استخراج أوراق المواد والشهور ونظام العام الدراسي (8 أم 6 أشهر)
    try {
      final bytes = await File(path).readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      final sheets = excel.tables.keys.toList();
      final firstSheet = excel.tables.values.first;
      final int totalMonths = StudentExcelService.detectTotalMonths(firstSheet);

      // استخراج أسماء الشهور الفعلية من الصف 2
      final monthNames = StudentExcelService.extractMonthsFromSheet(firstSheet, totalMonths: totalMonths);

      List<String> periods = [];
      for (final m in monthNames) {
        periods.add(m);
      }
      // إضافة خيارات اختبارات نهاية الفصول
      periods.add('ف١');
      periods.add('ف٢');

      // تحديد ورقة المادة الافتراضية بمطابقتها مع مادة الاختبار
      String? matchedSheet;
      for (final s in sheets) {
        if (s.trim() == widget.exam.header.subject.trim() ||
            s.contains(widget.exam.header.subject.trim()) ||
            widget.exam.header.subject.trim().contains(s)) {
          matchedSheet = s;
          break;
        }
      }
      matchedSheet ??= sheets.isNotEmpty ? sheets.first : null;

      setState(() {
        _selectedExcelPath = path;
        _excelLoaded = true;
        _detectedTotalMonths = totalMonths;
        _availableSheets = sheets;
        _selectedSheetName = matchedSheet;
        _evaluationPeriods = periods;
        _selectedPeriod = periods.isNotEmpty ? periods.first : null;
        _isProcessing = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تنشيط ملف الإكسيل بنجاح (نظام $totalMonths أشهر - ${sheets.length} مادة)'),
            backgroundColor: Colors.green.shade800,
          ),
        );
      }
    } catch (_) {
      setState(() {
        _excelLoaded = false;
        _isProcessing = false;
      });
    }
  }

  Future<void> _captureAndScan() async {
    if (!_excelLoaded || _cameraController == null || !_cameraController!.value.isInitialized || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = 'جاري تحليل ورقة الإجابة ورصد الدرجة...';
    });

    try {
      final XFile photo = await _cameraController!.takePicture();
      final bytes = await File(photo.path).readAsBytes();
      final img.Image? capturedImage = img.decodeImage(bytes);

      if (capturedImage == null) {
        throw Exception('فشل في معالجة بيانات الصورة.');
      }

      final scanResult = _processOmrData(capturedImage);
      _showResultDialog(scanResult);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء المسح: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusText = null;
        });
      }
    }
  }

  Map<String, dynamic> _processOmrData(img.Image image) {
    final int totalQuestions = widget.exam.questions.length;
    int correctCount = 0;
    double totalEarnedMark = 0.0;
    final detailedAnswers = List<dynamic>.empty(growable: true);

    for (int i = 0; i < totalQuestions; i++) {
      final q = widget.exam.questions[i];
      final String expected = q.answerKey.trim();

      final bool isCorrect = expected.isNotEmpty;
      if (isCorrect) {
        correctCount++;
        totalEarnedMark += q.mark;
      }

      detailedAnswers.add({
        'qNum': i + 1,
        'title': q.title,
        'expected': expected.isEmpty ? '-' : expected,
        'mark': q.mark,
        'isCorrect': isCorrect,
      });
    }

    return {
      'total': totalQuestions,
      'correct': correctCount,
      'score': totalEarnedMark,
      'maxScore': widget.exam.totalMarks,
      'details': detailedAnswers,
    };
  }

  void _showResultDialog(Map<String, dynamic> res) {
    // حساب موقع العمود المستهدف بدقة مع مراعاة إزاحة الأعمدة لنظام 8 أو 6 أشهر
    final int targetColIndex = StudentExcelService.resolveTargetExamColumnIndex(
      selectedPeriod: _selectedPeriod ?? 'شهر 1',
      totalMonths: _detectedTotalMonths,
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.verified, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('نتيجة التصحيح الآلي والرصد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Column(
                  children: [
                    Text(
                      'الدرجة المستحقة: ${res['score']} من ${res['maxScore']} د',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal.shade900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'المادة: [$_selectedSheetName] | الفترة: [$_selectedPeriod] (عمود فهرس $targetColIndex)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text('تفاصيل إجابات الفقرات:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: (res['details'] as List).length,
                  itemBuilder: (context, idx) {
                    final d = res['details'][idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Text('فقرة ${d['qNum']}: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          Text('الحل: ${d['expected']}', style: const TextStyle(fontSize: 11)),
                          const Spacer(),
                          Icon(
                            d['isCorrect'] ? Icons.check_circle : Icons.cancel,
                            size: 16,
                            color: d['isCorrect'] ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 4),
                          Text('${d['mark']} د', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('تم / مسح ورقة أخرى', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// نافذة منبثقة للتحكم بإعدادات الربط وملف الإكسيل
  void _openSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bCtx) => StatefulBuilder(
        builder: (context, setBState) => Padding(
          padding: EdgeInsets.only(
            top: 16,
            left: 16,
            right: 16,
            bottom: MediaQuery.of(bCtx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: const [
                  Icon(Icons.tune, color: Color(0xFF0F766E)),
                  SizedBox(width: 8),
                  Text('إعدادات ملف الإكسيل وفترة الرصد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const Divider(height: 20),

              // بطاقة الملف
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _excelLoaded ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _excelLoaded ? Colors.green.shade300 : Colors.red.shade300),
                ),
                child: Row(
                  children: [
                    Icon(_excelLoaded ? Icons.check_circle : Icons.error, color: _excelLoaded ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _selectedExcelPath != null
                            ? _selectedExcelPath!.split(Platform.pathSeparator).last
                            : 'لم يتم اختيار ملف إكسيل بعد',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _excelLoaded ? Colors.green.shade900 : Colors.red.shade900,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F766E)),
                      onPressed: () async {
                        Navigator.pop(bCtx);
                        await _pickExcelFile();
                      },
                      child: const Text('اختيار', style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // 1. حقل المادة (أوراق العمل)
              DropdownButtonFormField<String>(
                value: _selectedSheetName,
                decoration: InputDecoration(
                  labelText: 'المادة (ورقة العمل في الإكسيل)',
                  prefixIcon: const Icon(Icons.menu_book),
                  border: const OutlineInputBorder(),
                  enabled: _excelLoaded,
                  filled: !_excelLoaded,
                  fillColor: Colors.grey.shade200,
                ),
                items: _availableSheets.map((sheet) {
                  return DropdownMenuItem(
                    value: sheet,
                    child: Text(sheet, style: const TextStyle(fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: _excelLoaded
                    ? (val) {
                        setState(() => _selectedSheetName = val);
                        setBState(() => _selectedSheetName = val);
                      }
                    : null,
              ),

              const SizedBox(height: 12),

              // 2. حقل فترات الرصد (الشهور + ف١ + ف٢)
              DropdownButtonFormField<String>(
                value: _selectedPeriod,
                decoration: InputDecoration(
                  labelText: 'فترة الرصد (الشهر / نهاية الفصل ف١ - ف٢)',
                  prefixIcon: const Icon(Icons.calendar_month),
                  border: const OutlineInputBorder(),
                  enabled: _excelLoaded,
                  filled: !_excelLoaded,
                  fillColor: Colors.grey.shade200,
                ),
                items: _evaluationPeriods.map((period) {
                  final isTerm = period == 'ف١' || period == 'ف٢';
                  return DropdownMenuItem(
                    value: period,
                    child: Text(
                      period,
                      style: TextStyle(
                        fontWeight: isTerm ? FontWeight.bold : FontWeight.normal,
                        color: isTerm ? const Color(0xFF0F766E) : Colors.black87,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: _excelLoaded
                    ? (val) {
                        setState(() => _selectedPeriod = val);
                        setBState(() => _selectedPeriod = val);
                      }
                    : null,
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                onPressed: () => Navigator.pop(bCtx),
                child: const Text('حفظ وإغلاق', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('المصحح الآلي لأوراق التظليل (OMR)', style: TextStyle(fontSize: 15, color: Colors.white)),
        backgroundColor: const Color(0xFF0F766E),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              Icons.tune,
              color: _excelLoaded ? Colors.tealAccent : Colors.white,
            ),
            tooltip: 'إعدادات الإكسيل وفترة الرصد',
            onPressed: _openSettingsBottomSheet,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_isCameraInitialized && _cameraController != null)
            SizedBox.expand(
              child: CameraPreview(_cameraController!),
            )
          else
            Center(
              child: Text(
                _statusText ?? 'جاري تهيئة الكاميرا...',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),

          // شريط علوي يوضح حالة الربط بالمادة والشهر داخل شاشة الكاميرا
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: InkWell(
              onTap: _openSettingsBottomSheet,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _excelLoaded ? Colors.black.withOpacity(0.75) : Colors.red.shade900.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _excelLoaded ? Colors.tealAccent : Colors.redAccent,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _excelLoaded ? Icons.verified : Icons.error_outline,
                      color: _excelLoaded ? Colors.tealAccent : Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _excelLoaded
                            ? 'المادة: [$_selectedSheetName] | الفترة: [$_selectedPeriod]'
                            : 'انقر هنا لاختيار ملف الإكسيل لتنشيط المسح',
                        style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),

          // إطار توجيه ورقة التظليل
          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                border: Border.all(
                  color: _excelLoaded ? Colors.tealAccent : Colors.grey,
                  width: 2.0,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      _excelLoaded
                          ? 'اضبط حدود ورقة إجابة الطالب داخل هذا الإطار'
                          : 'يجب اختيار ملف الإكسيل أولاً لتفعيل المسح',
                      style: const TextStyle(color: Colors.white, fontSize: 11, backgroundColor: Colors.black54),
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.tealAccent),
                    const SizedBox(height: 12),
                    Text(_statusText ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        color: const Color(0xFF0F172A),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: _excelLoaded ? const Color(0xFF0F766E) : Colors.grey.shade700,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: _excelLoaded ? 3 : 0,
          ),
          icon: const Icon(Icons.document_scanner, color: Colors.white, size: 24),
          label: Text(
            _excelLoaded ? 'التقاط وتصحيح ورصد فوري' : 'اختر ملف الإكسيل لتفعيل المسح',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          onPressed: (!_excelLoaded || _isProcessing || !_isCameraInitialized) ? null : _captureAndScan,
        ),
      ),
    );
  }
}

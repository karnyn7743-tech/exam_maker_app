import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/exam_models.dart';

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

  @override
  void initState() {
    super.initState();
    _initCamera();
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

  Future<void> _captureAndScan() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = 'جاري تحليل ورقة الإجابة بدقة...';
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.verified, color: Color(0xFF0F766E)),
            SizedBox(width: 8),
            Text('نتيجة التصحيح الآلي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      'الإجابات الصحيحة: ${res['correct']} من إجمالي ${res['total']}',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('المصحح الآلي لأوراق التظليل (OMR)', style: TextStyle(fontSize: 15, color: Colors.white)),
        backgroundColor: const Color(0xFF0F766E),
        iconTheme: const IconThemeData(color: Colors.white),
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

          Center(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.tealAccent, width: 2.0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text(
                      'اضبط حدود ورقة إجابة الطالب داخل هذا الإطار',
                      style: TextStyle(color: Colors.white, fontSize: 11, backgroundColor: Colors.black54),
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
            backgroundColor: const Color(0xFF0F766E),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.document_scanner, color: Colors.white, size: 24),
          label: const Text('التقاط وتصحيح فوري', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          onPressed: _isProcessing || !_isCameraInitialized ? null : _captureAndScan,
        ),
      ),
    );
  }
}

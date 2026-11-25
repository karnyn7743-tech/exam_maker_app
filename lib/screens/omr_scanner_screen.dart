import 'dart:io';
import 'package:camera/camera.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/exam_models.dart';
import '../services/student_excel_service.dart';
import '../services/excel_file_access_service.dart';
import '../services/omr_registration_detector.dart';
import '../services/omr_perspective_rectifier.dart';
import '../services/omr_template_geometry.dart';
import '../services/omr_bubble_detector.dart';
import '../services/omr_scoring_service.dart';
import '../services/omr_result_commit_service.dart';

class OmrScannerScreen extends StatefulWidget {
  final ExamModel exam;

  const OmrScannerScreen({super.key, required this.exam});

  @override
  State<OmrScannerScreen> createState() => _OmrScannerScreenState();
}

class _OmrScannerScreenState extends State<OmrScannerScreen> {
  CameraController? _cameraController;
  final MobileScannerController _qrAnalyzer = MobileScannerController(
    autoStart: false,
    formats: const [BarcodeFormat.qrCode],
  );
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
        widget.exam.header.excelFilePath!.trim().isNotEmpty) {
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
    _qrAnalyzer.dispose();
    super.dispose();
  }

  /// اختيار ملف الإكسيل يدوياً
  Future<void> _pickExcelFile() async {
    try {
      final selected = await ExcelFileAccessService.pickExcelDocument();
      if (selected != null) await _processExcelFile(selected.reference);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذر اختيار ملف Excel الأصلي: $e'),
          backgroundColor: Colors.red.shade800,
        ));
      }
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
      final bytes = await ExcelFileAccessService.readBytes(path);
      final excel = Excel.decodeBytes(bytes);

      // نقتصر على أوراق المواد الصحيحة ولا نعامل أوراق الإعدادات كمواد.
      final sheets = await StudentExcelService.getSubjectSheetNames(path);
      if (sheets.isEmpty) throw Exception('لم يتم العثور على أوراق مواد صالحة.');
      String? matchedSheet;
      for (final sheetName in sheets) {
        if (sheetName.trim() == widget.exam.header.subject.trim() ||
            sheetName.contains(widget.exam.header.subject.trim()) ||
            widget.exam.header.subject.trim().contains(sheetName)) {
          matchedSheet = sheetName;
          break;
        }
      }
      matchedSheet ??= sheets.first;
      final selectedSheet = excel.tables[matchedSheet];
      if (selectedSheet == null) throw Exception('تعذر فتح ورقة المادة المحددة.');
      final int totalMonths = StudentExcelService.detectTotalMonths(selectedSheet);
      final monthNames = StudentExcelService.extractMonthsFromSheet(selectedSheet, totalMonths: totalMonths);

      List<String> periods = [];
      for (final m in monthNames) {
        periods.add(m);
      }
      // إضافة خيارات اختبارات نهاية الفصول
      periods.add('ف١');
      periods.add('ف٢');

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
    } catch (e) {
      if (mounted) {
        setState(() {
          _excelLoaded = false;
          _selectedExcelPath = null;
          _isProcessing = false;
          _statusText = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('تعذر قراءة ملف Excel الأصلي: $e'),
          backgroundColor: Colors.red.shade800,
        ));
      }
    }
  }

  Future<void> _captureAndScan() async {
    if (!_excelLoaded || _cameraController == null ||
        !_cameraController!.value.isInitialized || _isProcessing) return;
    setState(() { _isProcessing = true; _statusText = 'جاري تصوير الورقة ومعايرة حدودها...'; });
    try {
      final photo = await _cameraController!.takePicture();
      final bytes = await File(photo.path).readAsBytes();
      final captured = img.decodeImage(bytes);
      if (captured == null) throw Exception('فشل في معالجة بيانات الصورة.');
      final registration = OmrRegistrationDetector.detect(captured);
      if (!registration.success) throw Exception(registration.message);
      final rectified = OmrPerspectiveRectifier.rectify(captured, registration);

      if (mounted) setState(() => _statusText = 'جاري قراءة رمز الطالب ودوائر الإجابة...');
      final barcodeCapture = await _qrAnalyzer.analyzeImage(photo.path);
      final qrValues = (barcodeCapture?.barcodes ?? const <Barcode>[])
          .map((b) => b.rawValue?.trim() ?? '').where((v) => v.isNotEmpty).toSet();
      if (qrValues.length != 1) {
        throw Exception(qrValues.isEmpty
            ? 'لم يُقرأ رمز QR بوضوح. أعد التصوير.'
            : 'تحتوي الصورة على أكثر من رمز QR؛ تعذر تحديد هوية الطالب.');
      }
      final excelResult = await StudentExcelService.parseExcelFile(
        _selectedExcelPath!, expectedSubject: _selectedSheetName,
        targetGrade: widget.exam.header.grade, examTitle: widget.exam.header.examTitle,
      );
      final matches = excelResult.students
          .where((s) => s.secretCode.trim() == qrValues.single).toList();
      if (matches.length != 1) {
        throw Exception(matches.isEmpty
            ? 'رمز الطالب غير موجود في كشف المادة والصف المحددين.'
            : 'رمز الطالب مكرر في كشف الإكسيل.');
      }
      final student = matches.single;
      final groups = OmrTemplateGeometry.buildQuestionGroups(widget.exam);
      final readings = OmrBubbleDetector.readAll(rectified, groups);
      final selections = readings.map((r) {
        switch (r.status) {
          case OmrBubbleGroupStatus.selected:
          case OmrBubbleGroupStatus.multiple: return r.selectedOptions;
          case OmrBubbleGroupStatus.blank: return <String>[];
          case OmrBubbleGroupStatus.ambiguous:
          case OmrBubbleGroupStatus.invalid: return <String>['?'];
        }
      }).toList();
      final scoring = await _showOmrReviewDialog(
        student: student, selections: selections, groups: groups, readings: readings,
      );
      if (scoring == null || !mounted) return;

      setState(() => _statusText = 'جاري ترحيل الدرجة إلى ملف الإكسيل...');
      var committed = await OmrResultCommitService.commit(
        exam: widget.exam, scoring: scoring, excelPath: _selectedExcelPath!,
        sheetName: _selectedSheetName!, selectedPeriod: _selectedPeriod!,
        qrSecretCode: qrValues.single,
      );
      if (committed.status == OmrCommitStatus.existingMark) {
        final overwrite = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('توجد درجة مسجلة مسبقاً'),
            content: Text('توجد درجة لهذا الطالب في فترة $_selectedPeriod. هل تريد استبدالها بالدرجة الجديدة (${scoring.earnedMark.toStringAsFixed(2)})؟'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استبدال الدرجة')),
            ],
          ),
        );
        if (overwrite == true) {
          committed = await OmrResultCommitService.commit(
            exam: widget.exam, scoring: scoring, excelPath: _selectedExcelPath!,
            sheetName: _selectedSheetName!, selectedPeriod: _selectedPeriod!,
            qrSecretCode: qrValues.single, allowOverwrite: true,
          );
        }
      }
      if (!mounted) return;
      final message = switch (committed.status) {
        OmrCommitStatus.saved => 'تم ترحيل درجة ${scoring.earnedMark.toStringAsFixed(2)} للطالب ${student.name} بنجاح.',
        OmrCommitStatus.existingMark => 'لم تُستبدل الدرجة السابقة.',
        OmrCommitStatus.reviewRequired => 'توجد إجابات تحتاج إلى مراجعة قبل الحفظ.',
        OmrCommitStatus.studentNotFound => 'لم يُعثر على الطالب في كشف الإكسيل.',
        OmrCommitStatus.duplicateStudent => 'رمز الطالب مكرر في كشف الإكسيل.',
        OmrCommitStatus.invalidPeriod => 'تعذر تحديد عمود فترة الرصد.',
        OmrCommitStatus.saveFailed => 'تعذر حفظ الدرجة في ملف الإكسيل.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), duration: const Duration(seconds: 5),
        backgroundColor: committed.status == OmrCommitStatus.saved
            ? Colors.teal.shade800 : Colors.orange.shade900,
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذر إكمال التصحيح: $e'), backgroundColor: Colors.red.shade800,
      ));
    } finally {
      if (mounted) setState(() { _isProcessing = false; _statusText = null; });
    }
  }

  Future<OmrScoringResult?> _showOmrReviewDialog({
    required StudentData student,
    required List<List<String>> selections,
    required List<List<OmrBubbleSpec>> groups,
    required List<OmrBubbleGroupResult> readings,
  }) {
    final edited = selections.map((s) => List<String>.from(s)).toList();
    return showDialog<OmrScoringResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final result = OmrScoringService.score(
            exam: widget.exam, detectedSelections: edited,
          );
          String label(OmrAnswerStatus s) {
            switch (s) {
              case OmrAnswerStatus.correct: return 'صحيحة';
              case OmrAnswerStatus.incorrect: return 'خاطئة';
              case OmrAnswerStatus.blank: return 'فارغة';
              case OmrAnswerStatus.multiple: return 'متعددة';
              case OmrAnswerStatus.invalidKey: return 'مفتاح غير صالح';
              case OmrAnswerStatus.invalidSelection: return 'مراجعة';
            }
          }
          return AlertDialog(
            title: const Text('مراجعة التصحيح الآلي'),
            content: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.62,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الطالب: ${student.name} | رقم الجلوس: ${student.seatNo}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('الدرجة: ${result.earnedMark.toStringAsFixed(2)} / ${result.maximumMark.toStringAsFixed(2)}'
                      ' | صحيحة: ${result.correctCount} | خاطئة: ${result.incorrectCount} | فارغة: ${result.blankCount}',
                      style: const TextStyle(fontSize: 11)),
                  if (result.reviewCount > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text('عدّل الإجابات غير الواضحة من القوائم قبل الاعتماد.',
                          style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                    ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: result.items.length,
                      itemBuilder: (context, i) {
                        final item = result.items[i];
                        final options = groups[i].map((b) => b.option).toList();
                        final value = edited[i].length == 1 && options.contains(edited[i].single)
                            ? edited[i].single : '';
                        final ink = readings[i].samples
                            .map((s) => '${s.option}:${(s.inkRatio * 100).round()}%').join('  ');
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: Padding(
                            padding: const EdgeInsets.all(7),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  Text('فقرة ${item.questionNumber} — ${label(item.status)}',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                                          color: item.requiresReview ? Colors.deepOrange : null)),
                                  const Spacer(),
                                  Text('${item.mark.toStringAsFixed(1)} درجة'),
                                ]),
                                Text(ink, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                DropdownButtonFormField<String>(
                                  value: value, isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'الإجابة المعتمدة', isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: '', child: Text('بدون إجابة')),
                                    ...options.map((o) => DropdownMenuItem(value: o, child: Text(o))),
                                  ],
                                  onChanged: (v) => setDialogState(() {
                                    edited[i] = v == null || v.isEmpty ? <String>[] : <String>[v];
                                  }),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Text(
                    result.canBeAutomaticallyFinalized
                        ? 'النتيجة جاهزة للترحيل إلى $_selectedPeriod.'
                        : 'لن تُرحّل الدرجة حتى تُعالج جميع الحالات غير الواضحة.',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold,
                        color: result.canBeAutomaticallyFinalized ? Colors.teal : Colors.deepOrange),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
              FilledButton.icon(
                onPressed: result.canBeAutomaticallyFinalized
                    ? () => Navigator.pop(dialogContext, result) : null,
                icon: const Icon(Icons.save_alt),
                label: const Text('اعتماد وترحيل الدرجة'),
              ),
            ],
          );
        },
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

          // بطاقة واضحة لملف الإكسيل والمادة وفترة الرصد، مع زر تغيير الملف مباشرة
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xF20B1220),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _excelLoaded ? Colors.tealAccent : Colors.redAccent,
                  width: 1.3,
                ),
                boxShadow: const [
                  BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        _excelLoaded ? Icons.table_view : Icons.error_outline,
                        color: _excelLoaded ? Colors.tealAccent : Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedExcelPath != null
                              ? _selectedExcelPath!.split(Platform.pathSeparator).last
                              : 'لم يتم اختيار ملف الإكسيل',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _excelLoaded ? Icons.check_circle : Icons.warning_amber_rounded,
                        color: _excelLoaded ? Colors.greenAccent : Colors.orangeAccent,
                        size: 18,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _excelLoaded
                        ? 'المادة: $_selectedSheetName     |     فترة الرصد: $_selectedPeriod'
                        : 'اختر ملف الإكسيل أولاً، ثم حدد المادة وفترة الرصد.',
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.tealAccent,
                            side: const BorderSide(color: Colors.tealAccent),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          onPressed: _isProcessing ? null : _pickExcelFile,
                          icon: const Icon(Icons.folder_open, size: 17),
                          label: Text(
                            _excelLoaded ? 'تغيير ملف الإكسيل' : 'اختيار ملف الإكسيل',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'اختيار المادة وفترة الرصد',
                        onPressed: _openSettingsBottomSheet,
                        icon: const Icon(Icons.tune, color: Colors.white),
                      ),
                    ],
                  ),
                ],
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
            _excelLoaded ? 'التقاط والتحقق من هوية الطالب' : 'اختر ملف الإكسيل لتفعيل المسح',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          onPressed: (!_excelLoaded || _isProcessing || !_isCameraInitialized) ? null : _captureAndScan,
        ),
      ),
    );
  }
}

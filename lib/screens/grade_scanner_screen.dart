import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../services/student_excel_service.dart';

class GradeScannerScreen extends StatefulWidget {
  final bool isOmrMode;

  const GradeScannerScreen({super.key, this.isOmrMode = false});

  @override
  State<GradeScannerScreen> createState() => _GradeScannerScreenState();
}

class _GradeScannerScreenState extends State<GradeScannerScreen> {
  String? _excelFilePath;
  String? _excelFileName;
  bool _excelLoaded = false;

  List<String> _sheetNames = [];
  String? _selectedSheet;

  bool _isTerm2 = false; // الفصل الأول أم الثاني
  int _totalYearMonths = 8; // 6 أو 8 أشهر يتم اكتشافها أو تعيينها

  List<String> _monthsList = [];
  String? _selectedMonthOrSubject;

  String _secretCode = '';
  final TextEditingController _gradeController = TextEditingController();
  
  int _totalStudentsCount = 0;
  int _scannedStudentsCount = 0;

  bool _isScanningActive = false;
  final MobileScannerController _scannerController = MobileScannerController();
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void dispose() {
    _scannerController.dispose();
    _textRecognizer.close();
    _gradeController.dispose();
    super.dispose();
  }

  // 1. اختيار ملف الإكسيل وقراءة بياناته مع التحقق الصارم من التنسيق
  Future<void> _pickExcelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'xlsm'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;

        // التحقق من بنية وتنسيق الملف
        final bool isValid = await StudentExcelService.validateExcelStructure(path);
        if (!isValid) {
          setState(() {
            _excelLoaded = false;
            _excelFilePath = null;
            _excelFileName = null;
            _sheetNames = [];
            _selectedSheet = null;
            _monthsList = [];
            _selectedMonthOrSubject = null;
            _totalStudentsCount = 0;
            _isScanningActive = false;
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

        final file = File(path);
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);

        final sheets = excel.tables.keys.toList();
        final initialSheet = sheets.isNotEmpty ? sheets.first : null;

        // الاكتشاف التلقائي لعدد أشهر السنة (8 أم 6 أشهر) من خلايا الصف الثاني
        int detectedMonths = 8;
        if (sheets.isNotEmpty) {
          detectedMonths = StudentExcelService.detectTotalMonths(excel.tables[sheets.first]!);
        }

        setState(() {
          _excelLoaded = true;
          _excelFilePath = path;
          _excelFileName = result.files.single.name;
          _sheetNames = sheets;
          _selectedSheet = initialSheet;
          _totalYearMonths = detectedMonths;
        });

        await _loadMonthsAndStudents();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر قراءة ملف الإكسيل: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // قراءة الطلاب والشهور مع إضافة ف١ وف٢
  Future<void> _loadMonthsAndStudents() async {
    if (_excelFilePath == null || _selectedSheet == null) return;

    try {
      final bytes = await File(_excelFilePath!).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[_selectedSheet!];
      if (sheet == null) return;

      // 1. حساب عدد الطلاب الفعلي في العمود D بدءاً من الصف الرابع (index = 3)
      int students = 0;
      for (int r = 3; r < sheet.maxRows; r++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value;
        if (val != null && val.toString().trim().isNotEmpty) {
          students++;
        }
      }

      // 2. جلب أسماء الشهور المخصصة لهذا الفصل الدراسي
      final int term1Months = (_totalYearMonths == 6) ? 3 : 4;
      final allMonths = StudentExcelService.extractMonthsFromSheet(sheet, totalMonths: _totalYearMonths);

      List<String> termMonths = [];
      if (!_isTerm2) {
        // الفصل الأول: أشهر الفصل الأول + ف١
        termMonths.addAll(allMonths.take(term1Months));
        termMonths.add('ف١');
      } else {
        // الفصل الثاني: أشهر الفصل الثاني + ف٢
        termMonths.addAll(allMonths.skip(term1Months));
        termMonths.add('ف٢');
      }

      setState(() {
        _totalStudentsCount = students;
        _monthsList = termMonths;
        _selectedMonthOrSubject = termMonths.isNotEmpty ? termMonths.first : null;
      });
    } catch (_) {}
  }

  // تبديل الفصل وإعادة ترتيب فترات الرصد المناسبة
  void _switchTerm(bool isSecondTerm) {
    if (!_excelLoaded) return;
    setState(() {
      _isTerm2 = isSecondTerm;
    });
    _loadMonthsAndStudents();
  }

  // 2. تأكيد وحفظ الدرجة في نفس الملف المختار مع حساب موقع العمود بدقة
  Future<void> _saveGradeDirectly() async {
    if (!_excelLoaded || _excelFilePath == null || _selectedSheet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار ملف الإكسيل أولاً لتفعيل الحفظ')),
      );
      return;
    }

    if (_secretCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى مسح رمز الـ QR للطالب أولاً')),
      );
      return;
    }

    final double? gradeVal = double.tryParse(_gradeController.text.trim());
    if (gradeVal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى التحقق من صحة الدرجة المدخلة')),
      );
      return;
    }

    try {
      final file = File(_excelFilePath!);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[_selectedSheet!];

      if (sheet == null) return;

      // البحث عن الرقم السري في العمود D (index = 3)
      int targetRow = -1;
      final cleanSecret = _secretCode.trim();

      for (int r = 3; r < sheet.maxRows; r++) {
        final cellVal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value;
        if (cellVal != null && cellVal.toString().trim() == cleanSecret) {
          targetRow = r;
          break;
        }
      }

      if (targetRow == -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('الرقم السري ($_secretCode) غير موجود في كشف الطلاب!'),
            backgroundColor: Colors.red.shade800,
          ),
        );
        return;
      }

      // حساب العمود المستهدف مع مراعاة إزاحة الأعمدة لنظام 8 أو 6 أشهر
      final int targetCol = StudentExcelService.resolveTargetExamColumnIndex(
        selectedPeriod: _selectedMonthOrSubject ?? 'شهر 1',
        totalMonths: _totalYearMonths,
      );

      final cellTarget = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: targetCol,
        rowIndex: targetRow,
      ));
      cellTarget.value = DoubleCellValue(gradeVal);

      final encodedData = excel.encode();
      if (encodedData != null) {
        await file.writeAsBytes(encodedData, mode: FileMode.write, flush: true);

        setState(() {
          _scannedStudentsCount++;
          _secretCode = '';
          _gradeController.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم رصد الدرجة في عمود ($_selectedMonthOrSubject) للمادة [$_selectedSheet] بنجاح'),
            backgroundColor: const Color(0xFF1B5E20),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text(
          'إدخال الدرجات من أوراق الإجابة',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0288D1),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: 'نظام السنة الدراسية',
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('عدد أشهر السنة الدراسية'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<int>(
                        title: const Text('8 أشهر (4 أشهر لكل فصل)'),
                        value: 8,
                        groupValue: _totalYearMonths,
                        onChanged: (v) {
                          setState(() => _totalYearMonths = v!);
                          Navigator.pop(ctx);
                          if (_excelLoaded) _loadMonthsAndStudents();
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('6 أشهر (3 أشهر لكل فصل - تراجع 5 و 10 أعمدة)'),
                        value: 6,
                        groupValue: _totalYearMonths,
                        onChanged: (v) {
                          setState(() => _totalYearMonths = v!);
                          Navigator.pop(ctx);
                          if (_excelLoaded) _loadMonthsAndStudents();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // زر اختيار ملف الإكسيل
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              icon: const Icon(Icons.folder_open, color: Colors.white),
              onPressed: _pickExcelFile,
              label: Text(
                _excelLoaded ? 'تغيير ملف الأكسيل' : 'اختر ملف الأكسيل (الكشوفات)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 8),

            // اسم الملف المختار وحالة التطابق
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _excelLoaded ? Colors.green.shade400 : Colors.grey.shade300,
                  width: _excelLoaded ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _excelLoaded ? Icons.check_circle : Icons.info_outline,
                    color: _excelLoaded ? Colors.green : Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _excelFileName ?? 'لم يتم تحديد ملف إكسيل بعد (الحقول معطلة)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _excelLoaded ? Colors.black87 : Colors.red.shade700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // قائمة اختيار المادة (أسماء أوراق العمل)
            const Text('المادة المستهدفة (ورقة العمل):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _excelLoaded ? Colors.white : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSheet,
                  isExpanded: true,
                  hint: Text(
                    _excelLoaded ? 'اختر المادة' : 'يرجى اختيار ملف الإكسيل أولاً',
                    style: TextStyle(color: _excelLoaded ? Colors.black54 : Colors.grey),
                  ),
                  items: _excelLoaded
                      ? _sheetNames
                          .map((s) => DropdownMenuItem(
                                value: s,
                                child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)),
                              ))
                          .toList()
                      : null,
                  onChanged: _excelLoaded
                      ? (v) {
                          setState(() => _selectedSheet = v);
                          _loadMonthsAndStudents();
                        }
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // أزرار اختيار الفصل الدراسي
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: (!_isTerm2 && _excelLoaded)
                          ? const Color(0xFF1976D2)
                          : (_excelLoaded ? Colors.white : Colors.grey.shade200),
                      foregroundColor: (!_isTerm2 && _excelLoaded) ? Colors.white : Colors.black87,
                      side: BorderSide(color: _excelLoaded ? const Color(0xFF1976D2) : Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _excelLoaded ? () => _switchTerm(false) : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!_isTerm2 && _excelLoaded) const Icon(Icons.check, size: 16),
                        const SizedBox(width: 4),
                        const Text('اختبار الفصل الأول', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: (_isTerm2 && _excelLoaded)
                          ? const Color(0xFF1976D2)
                          : (_excelLoaded ? Colors.white : Colors.grey.shade200),
                      foregroundColor: (_isTerm2 && _excelLoaded) ? Colors.white : Colors.black87,
                      side: BorderSide(color: _excelLoaded ? const Color(0xFF1976D2) : Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: _excelLoaded ? () => _switchTerm(true) : null,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isTerm2 && _excelLoaded) const Icon(Icons.check, size: 16),
                        const SizedBox(width: 4),
                        const Text('اختبار الفصل الثاني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // قائمة اختيار الشهر / نهاية الفصل (ف١ وف٢)
            const Text('فترة الرصد (الشهر / نهاية الفصل):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _excelLoaded ? Colors.white : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMonthOrSubject,
                  isExpanded: true,
                  hint: const Text('حدد الفترة لإدخال درجات التحريري فيها'),
                  items: _excelLoaded
                      ? _monthsList.map((m) {
                          final isTerm = m == 'ف١' || m == 'ف٢';
                          return DropdownMenuItem(
                            value: m,
                            child: Text(
                              isTerm ? '$m (اختبار نهاية الفصل)' : m,
                              style: TextStyle(
                                fontWeight: isTerm ? FontWeight.bold : FontWeight.normal,
                                color: isTerm ? const Color(0xFF0F766E) : Colors.black87,
                              ),
                            ),
                          );
                        }).toList()
                      : null,
                  onChanged: _excelLoaded ? (v) => setState(() => _selectedMonthOrSubject = v) : null,
                ),
              ),
            ),
            const SizedBox(height: 10),

            // حقل الرقم السري المقروء من الـ QR
            const Text('الرقم السري للطالب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: _excelLoaded ? Colors.white : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Center(
                child: Text(
                  _secretCode.isNotEmpty ? _secretCode : 'سيظهر هنا الرقم السري بعد المسح',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: _secretCode.isNotEmpty ? const Color(0xFF1976D2) : Colors.grey,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // العداد والدرجة في صف واحد
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الدرجة المستحقة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _gradeController,
                        enabled: _excelLoaded,
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: '0.0',
                          filled: true,
                          fillColor: _excelLoaded ? Colors.white : Colors.grey.shade200,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('العداد:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: _excelLoaded ? Colors.white : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Center(
                          child: Text(
                            '$_totalStudentsCount / $_scannedStudentsCount',
                            style: TextStyle(
                              color: _excelLoaded ? const Color(0xFF2E7D32) : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // زر بدء وإيقاف المسح بالكاميرا (معطل إن لم يتم تحميل الملف)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: !_excelLoaded
                    ? Colors.grey
                    : (_isScanningActive ? Colors.red.shade700 : const Color(0xFF4CAF50)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              icon: Icon(_isScanningActive ? Icons.stop : Icons.camera_alt, color: Colors.white),
              label: Text(
                _isScanningActive ? 'إيقاف الكاميرا' : 'ابدأ المسح',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: _excelLoaded
                  ? () {
                      setState(() => _isScanningActive = !_isScanningActive);
                    }
                  : null,
            ),
            const SizedBox(height: 8),

            // زر تأكيد وحفظ الدرجة (معطل إن لم يتم تحميل الملف)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _excelLoaded ? const Color(0xFF0288D1) : const Color(0xFFB0BEC5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              onPressed: _excelLoaded ? _saveGradeDirectly : null,
              child: const Text(
                'تأكيد وحفظ الدرجة',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),

            // نافذة الكاميرا لمسح الـ QR والدرجة
            if (_isScanningActive && _excelLoaded)
              Container(
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400, width: 2),
                ),
                clipBehavior: Clip.antiAlias,
                child: MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.isNotEmpty && raw != _secretCode) {
                        setState(() {
                          _secretCode = raw.trim();
                        });
                        break;
                      }
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

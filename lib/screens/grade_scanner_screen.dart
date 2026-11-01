import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class GradeScannerScreen extends StatefulWidget {
  final bool isOmrMode;

  const GradeScannerScreen({super.key, this.isOmrMode = false});

  @override
  State<GradeScannerScreen> createState() => _GradeScannerScreenState();
}

class _GradeScannerScreenState extends State<GradeScannerScreen> {
  String? _excelFilePath;
  String? _excelFileName;
  List<String> _sheetNames = [];
  String? _selectedSheet;

  bool _isTerm2 = false; // الفصل الأول أم الثاني
  int _totalYearMonths = 8; // 6 أو 8 أشهر

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

  // 1. اختيار ملف الإكسيل وقراءة بياناته
  Future<void> _pickExcelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'xlsm'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);

        final sheets = excel.tables.keys.toList();
        final initialSheet = sheets.isNotEmpty ? sheets.first : null;

        setState(() {
          _excelFilePath = path;
          _excelFileName = result.files.single.name;
          _sheetNames = sheets;
          _selectedSheet = initialSheet;
        });

        _loadMonthsAndStudents();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر قراءة ملف الإكسيل: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // قراءة الشهور والطلاب من الملف المختار
  Future<void> _loadMonthsAndStudents() async {
    if (_excelFilePath == null || _selectedSheet == null) return;

    try {
      final bytes = await File(_excelFilePath!).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[_selectedSheet!];
      if (sheet == null) return;

      // حساب عدد الطلاب الفعلي في العمود D بدءاً من الصف الرابع (index = 3)
      int students = 0;
      for (int r = 3; r < sheet.maxRows; r++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value;
        if (val != null && val.toString().trim().isNotEmpty) {
          students++;
        }
      }

      // جلب أسماء الشهور من الصف الثاني (index = 1) بدءاً من العمود E (index = 4)
      List<String> months = [];
      int currentCol = 4;
      final int monthsInTerm1 = (_totalYearMonths == 6) ? 3 : 4;

      for (int m = 1; m <= _totalYearMonths; m++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: currentCol, rowIndex: 1)).value;
        final name = val != null ? val.toString().trim() : 'شهر $m';
        months.add(name);

        currentCol += 5;
        if (m == monthsInTerm1) {
          currentCol += 2; // تخطي عمودي م1 وف1
        }
      }

      setState(() {
        _totalStudentsCount = students;
        _monthsList = months;
        _selectedMonthOrSubject = months.isNotEmpty ? months.first : null;
      });
    } catch (_) {}
  }

  // 2. حساب العمود المستهدف للتحريري
  int _calculateTargetColumnIndex(int monthIndex) {
    // شهر 1 -> عمود H (index = 7)
    final int monthsInTerm1 = (_totalYearMonths == 6) ? 3 : 4;
    final int monthNumber = monthIndex + 1;

    if (monthNumber <= monthsInTerm1) {
      return 2 + (monthNumber * 5); // شهر 1: 2+5 = 7 (العمود H)
    } else {
      return 2 + (monthNumber * 5) + 2; // إضافة الإزاحة لفاصل الفصلين
    }
  }

  // 3. تأكيد وحفظ الدرجة في نفس الملف المختار دون تكرار
  Future<void> _saveGradeDirectly() async {
    if (_excelFilePath == null || _selectedSheet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى اختيار ملف الإكسيل أولاً')),
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
      for (int r = 3; r < sheet.maxRows; r++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r));
        if (cell.value != null && cell.value.toString().trim() == _secretCode.trim()) {
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

      // تحديد فهرس الشهر المختار
      int selectedMonthIdx = _monthsList.indexOf(_selectedMonthOrSubject ?? '');
      if (selectedMonthIdx == -1) selectedMonthIdx = 0;

      final targetCol = _calculateTargetColumnIndex(selectedMonthIdx);

      // كتابة الدرجة
      final cellTarget = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: targetCol,
        rowIndex: targetRow,
      ));
      cellTarget.value = DoubleCellValue(gradeVal);

      // حفظ مباشر فوق الملف الأصلي
      final encodedData = excel.encode();
      if (encodedData != null) {
        await file.writeAsBytes(encodedData, mode: FileMode.write, flush: true);

        setState(() {
          _scannedStudentsCount++;
          _secretCode = '';
          _gradeController.clear();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ الدرجة في ملف الإكسيل بنجاح'),
            backgroundColor: Color(0xFF1B5E20),
            duration: Duration(seconds: 1),
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
                          _loadMonthsAndStudents();
                        },
                      ),
                      RadioListTile<int>(
                        title: const Text('6 أشهر (3 أشهر لكل فصل)'),
                        value: 6,
                        groupValue: _totalYearMonths,
                        onChanged: (v) {
                          setState(() => _totalYearMonths = v!);
                          Navigator.pop(ctx);
                          _loadMonthsAndStudents();
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
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              onPressed: _pickExcelFile,
              child: const Text(
                'اختر ملف الأكسيل (الكشوفات)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 8),

            // اسم الملف المختار
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                _excelFileName ?? 'لم يتم تحديد ملف إكسيل بعد',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: _excelFileName != null ? Colors.black87 : Colors.grey,
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
                      backgroundColor: !_isTerm2 ? const Color(0xFF1976D2) : Colors.white,
                      foregroundColor: !_isTerm2 ? Colors.white : Colors.black87,
                      side: const BorderSide(color: Color(0xFF1976D2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => setState(() => _isTerm2 = false),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!_isTerm2) const Icon(Icons.check, size: 16),
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
                      backgroundColor: _isTerm2 ? const Color(0xFF1976D2) : Colors.white,
                      foregroundColor: _isTerm2 ? Colors.white : Colors.black87,
                      side: const BorderSide(color: Color(0xFF1976D2)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () => setState(() => _isTerm2 = true),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isTerm2) const Icon(Icons.check, size: 16),
                        const SizedBox(width: 4),
                        const Text('اختبار الفصل الثاني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // قائمة اختيار المادة / الشهر
            const Text('اختر الشهر / المادة المستهدفة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMonthOrSubject,
                  isExpanded: true,
                  hint: const Text('حدد الشهر لإدخال درجات التحريري فيه'),
                  items: _monthsList.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (v) => setState(() => _selectedMonthOrSubject = v),
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
                color: Colors.white,
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
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        decoration: InputDecoration(
                          hintText: '0.0',
                          filled: true,
                          fillColor: Colors.white,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Center(
                          child: Text(
                            '$_totalStudentsCount / $_scannedStudentsCount',
                            style: const TextStyle(
                              color: Color(0xFF2E7D32),
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

            // زر بدء وإيقاف المسح بالكاميرا
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanningActive ? Colors.red.shade700 : const Color(0xFF4CAF50),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              icon: Icon(_isScanningActive ? Icons.stop : Icons.camera_alt, color: Colors.white),
              label: Text(
                _isScanningActive ? 'إيقاف الكاميرا' : 'ابدأ المسح',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: () {
                setState(() => _isScanningActive = !_isScanningActive);
              },
            ),
            const SizedBox(height: 8),

            // زر تأكيد وحفظ الدرجة
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB0BEC5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              onPressed: _saveGradeDirectly,
              child: const Text(
                'تأكيد وحفظ الدرجة',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),

            // نافذة الكاميرا لمسح الـ QR والدرجة
            if (_isScanningActive)
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

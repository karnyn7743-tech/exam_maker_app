import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
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

  bool _isTerm2 = false;

  List<String> _monthsList = [];
  String? _selectedMonthOrSubject;

  String _secretCode = '';
  final TextEditingController _gradeController = TextEditingController();

  int _totalStudentsCount = 0;
  int _scannedStudentsCount = 0;

  bool _isScanningActive = false;
  bool _isProcessingCapture = false; // لمنع تكرار الالتقاط

  // ✅ تفعيل returnImage لقراءة الصورة
  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    torchEnabled: false,
    returnImage: true, 
  );
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void dispose() {
    _scannerController.dispose();
    _textRecognizer.close();
    _gradeController.dispose();
    super.dispose();
  }

  // ✅ نسخ الملف لمكان دائم
  Future<String> _getPermanentExcelPath(String originalFileName, String sourceCachePath) async {
    Directory? externalDir = await getExternalStorageDirectory();
    String basePath = "";
    List<String> paths = externalDir!.path.split("/");
    for (int x = 1; x < paths.length; x++) {
      if (paths[x] != "Android") {
        basePath += "/${paths[x]}";
      } else {
        break;
      }
    }
    Directory targetDir = Directory("$basePath/Download/درجات الطلاب");
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    File destination = File("${targetDir.path}/$originalFileName");
    if (!await destination.exists()) {
      await destination.writeAsBytes(await File(sourceCachePath).readAsBytes(), flush: true);
    }
    return destination.path;
  }

  Future<void> _pickExcelFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'xlsm'],
      );

      if (result != null && result.files.single.path != null) {
        final cachePath = result.files.single.path!;
        final fileName = result.files.single.name;

        // ✅ نسخ الملف إلى مجلد دائم
        final path = await _getPermanentExcelPath(fileName, cachePath);

        final file = File(path);
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);

        final sheets = excel.tables.keys.toList();
        final initialSheet = sheets.isNotEmpty ? sheets.first : null;

        setState(() {
          _excelLoaded = true;
          _excelFilePath = path;
          _excelFileName = fileName;
          _sheetNames = sheets;
          _selectedSheet = initialSheet;
        });

        await _loadMonthsAndStudents();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر قراءة الملف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🧠 المنطق الذكي الجديد: جلب الشهور ديناميكياً بناءً على الفصل
  Future<void> _loadMonthsAndStudents() async {
    if (_excelFilePath == null || _selectedSheet == null) return;

    try {
      final bytes = await File(_excelFilePath!).readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      
      // التأكد من أن الورقة المختارة موجودة
      if (!excel.tables.containsKey(_selectedSheet!)) return;
      final sheet = excel.tables[_selectedSheet!]!;

      // 1. حساب عدد الطلاب في العمود D (index 3) بدءاً من الصف 4 (index 3)
      int students = 0;
      for (int r = 3; r < sheet.maxRows; r++) {
        final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value;
        if (val != null && val.toString().trim().isNotEmpty) students++;
      }

      // 2. استخراج الشهور بناءً على كلمات مفتاحية (م١، ف١، ف٢)
      List<String> term1List = [];
      List<String> term2List = [];
      bool foundF1 = false;
      bool foundF2 = false;

      int col = 4; // نبدأ من العمود E
      while (col < sheet.maxColumns) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1)); // الصف الثاني
        final text = cell.value?.toString().trim() ?? '';
        
        if (text.isNotEmpty) {
          final cleanText = text.replaceAll(RegExp(r'\s+'), ''); // إزالة المسافات
          
          if (cleanText == 'م١' || cleanText == 'م1') {
            // تخطي
            col += 1;
            continue;
          } else if (cleanText == 'ف١' || cleanText == 'ف1') {
            foundF1 = true;
            col += 1;
            continue;
          } else if (cleanText == 'م٢' || cleanText == 'م2') {
            // تخطي
            col += 1;
            continue;
          } else if (cleanText == 'ف٢' || cleanText == 'ف2') {
            foundF2 = true;
            break; // نهاية الفصل الثاني
          } else {
            // هذا اسم شهر
            if (!foundF1) {
              term1List.add(text);
            } else if (!foundF2) {
              term2List.add(text);
            }
            col += 5; // القفز لبداية الشهر التالي (لأن كل شهر 5 أعمدة)
          }
        } else {
          col += 1; // احتياطي إذا كانت الخلية فارغة
        }
      }

      // 3. تجهيز القائمة حسب الفصل المختار
      List<String> activeMonths = [];
      if (!_isTerm2) {
        activeMonths.addAll(term1List);
        if (foundF1) activeMonths.add('ف١');
      } else {
        activeMonths.addAll(term2List);
        if (foundF2) activeMonths.add('ف٢');
      }

      setState(() {
        _totalStudentsCount = students;
        _monthsList = activeMonths;
        _selectedMonthOrSubject = activeMonths.isNotEmpty ? activeMonths.first : null;
      });
    } catch (e) {
      debugPrint("خطأ في استخراج الشهور: $e");
    }
  }

  void _switchTerm(bool isSecondTerm) {
    if (!_excelLoaded) return;
    setState(() => _isTerm2 = isSecondTerm);
    _loadMonthsAndStudents();
  }

  // ═════════ دوال OCR ═════════
  String _convertArabicHindiDigits(String input) {
    const map = {
      '٠':'0','١':'1','٢':'2','٣':'3','٤':'4','٥':'5','٦':'6','٧':'7','٨':'8','٩':'9',
      '۰':'0','۱':'1','۲':'2','۳':'3','۴':'4','۵':'5','۶':'6','۷':'7','۸':'8','۹':'9',
    };
    String out = input;
    map.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  String _extractNumber(String text) {
    final converted = _convertArabicHindiDigits(text);
    final match = RegExp(r'\d+').firstMatch(converted);
    return match?.group(0) ?? '';
  }

  img.Image _preprocessImageForOcr(img.Image src) {
    final processed = img.Image.from(src);
    for (int y = 0; y < processed.height; y++) {
      for (int x = 0; x < processed.width; x++) {
        final pixel = processed.getPixel(x, y);
        final num r = pixel.r, g = pixel.g, b = pixel.b;
        if (r > 90 && (r - g) > 25 && (r - b) > 25) {
          processed.setPixelRgb(x, y, 0, 0, 0);
        }
      }
    }
    return processed;
  }

  Future<Map<String, Uint8List?>?> _cropImageRegions(Uint8List bytes) async {
    try {
      img.Image? full = img.decodeImage(bytes);
      if (full == null) return null;
      full = img.bakeOrientation(full);

      final int w = full.width;
      final int h = full.height;
      final int regionW = w ~/ 3;

      var left  = img.copyCrop(full, x: 0, y: 0, width: regionW, height: h);
      var right = img.copyCrop(full, x: regionW * 2, y: 0, width: regionW, height: h);

      left  = _preprocessImageForOcr(left);
      right = _preprocessImageForOcr(right);

      return {
        'left':  Uint8List.fromList(img.encodePng(left)),
        'right': Uint8List.fromList(img.encodePng(right)),
      };
    } catch (e) {
      return null;
    }
  }

  Future<String> _ocrFromBytes(Uint8List bytes) async {
    try {
      final tempDir = await Directory.systemTemp.createTemp('ocr_');
      final tempFile = File('${tempDir.path}/img.png');
      await tempFile.writeAsBytes(bytes);

      final input = InputImage.fromFile(tempFile);
      final recognized = await _textRecognizer.processImage(input);

      await tempFile.delete();
      await tempDir.delete();
      return recognized.text.trim();
    } catch (e) {
      return '';
    }
  }

  // ═════════ الحفظ مع المنطق الذكي ═════════
  Future<void> _saveGradeDirectly() async {
    if (!_excelLoaded || _excelFilePath == null || _selectedSheet == null) return;
    if (_secretCode.isEmpty || _selectedMonthOrSubject == null) return;

    final double? gradeVal = double.tryParse(_gradeController.text.trim());
    if (gradeVal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الدرجة غير صحيحة')));
      return;
    }

    try {
      final file = File(_excelFilePath!);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[_selectedSheet!];
      if (sheet == null) return;

      // 1. البحث عن الطالب بالرقم السري
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('الرقم السري ($_secretCode) غير موجود!'), backgroundColor: Colors.red.shade800));
        return;
      }

      // 2. البحث عن العمود المستهدف ديناميكياً من الصف الثاني
      int targetCol = -1;
      final cleanSelected = _selectedMonthOrSubject!.replaceAll(RegExp(r'\s+'), '');
      
      int c = 4; // نبدأ من E
      while (c < sheet.maxColumns) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1));
        final text = cell.value?.toString().trim() ?? '';
        
        if (text.isNotEmpty) {
          final cleanText = text.replaceAll(RegExp(r'\s+'), '');
          
          // هل هذه الخلية هي الشهر المختار؟
          bool isMatch = (cleanText == cleanSelected) ||
              (cleanSelected == 'ف١' && cleanText == 'ف1') ||
              (cleanSelected == 'ف٢' && cleanText == 'ف2');

          if (isMatch) {
            if (cleanSelected == 'ف١' || cleanSelected == 'ف٢' || cleanSelected == 'ف1' || cleanSelected == 'ف2') {
              targetCol = c; // الفصل هو العمود نفسه
            } else {
              targetCol = c + 3; // الشهر: العمود الرابع من الكتلة
            }
            break;
          }

          // القفز للمرحلة التالية
          if (cleanText == 'م١' || cleanText == 'ف١' || cleanText == 'م1' || cleanText == 'ف1' ||
              cleanText == 'م٢' || cleanText == 'ف٢' || cleanText == 'م2' || cleanText == 'ف2') {
            c += 1;
          } else {
            c += 5;
          }
        } else {
          c += 1;
        }
      }

      if (targetCol == -1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('❌ تعذر تحديد عمود الدرجة للفترة المختارة!'), backgroundColor: Colors.red));
        return;
      }

      // 3. الحفظ
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: targetCol, rowIndex: targetRow)).value = DoubleCellValue(gradeVal);

      final encodedData = excel.encode();
      if (encodedData != null) {
        await file.writeAsBytes(encodedData, mode: FileMode.write, flush: true);
        setState(() {
          _scannedStudentsCount++;
          _secretCode = '';
          _gradeController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ تم حفظ الدرجة في ($_selectedMonthOrSubject) بنجاح'),
          backgroundColor: const Color(0xFF1B5E20),
        ));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('خطأ أثناء الحفظ: $e'), backgroundColor: Colors.red));
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text('إدخال الدرجات',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        backgroundColor: const Color(0xFF0288D1),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
            icon: const Icon(Icons.folder_open, color: Colors.white),
            onPressed: _pickExcelFile,
            label: Text(_excelLoaded ? 'تغيير الملف' : 'اختر ملف الأكسيل',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _excelLoaded ? Colors.green : Colors.grey)),
            child: Text(_excelFileName ?? 'لم يتم اختيار ملف',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, color: _excelLoaded ? Colors.black87 : Colors.red)),
          ),
          const SizedBox(height: 12),
          const Text('المادة (ورقة العمل):', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSheet, isExpanded: true,
                items: _excelLoaded ? _sheetNames.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList() : null,
                onChanged: _excelLoaded ? (v) { setState(() => _selectedSheet = v); _loadMonthsAndStudents(); } : null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: (!_isTerm2 && _excelLoaded) ? const Color(0xFF1976D2) : Colors.white,
                foregroundColor: (!_isTerm2 && _excelLoaded) ? Colors.white : Colors.black87,
              ),
              onPressed: _excelLoaded ? () => _switchTerm(false) : null,
              child: const Text('الفصل الأول', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: (_isTerm2 && _excelLoaded) ? const Color(0xFF1976D2) : Colors.white,
                foregroundColor: (_isTerm2 && _excelLoaded) ? Colors.white : Colors.black87,
              ),
              onPressed: _excelLoaded ? () => _switchTerm(true) : null,
              child: const Text('الفصل الثاني', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
          ]),
          const SizedBox(height: 10),
          const Text('فترة الرصد:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMonthOrSubject, isExpanded: true,
                items: _excelLoaded ? _monthsList.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList() : null,
                onChanged: _excelLoaded ? (v) => setState(() => _selectedMonthOrSubject = v) : null,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text('الرقم السري:', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Container(
            height: 48,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300)),
            child: Center(child: Text(_secretCode.isNotEmpty ? _secretCode : 'سيظهر بعد المسح',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                    color: _secretCode.isNotEmpty ? const Color(0xFF1976D2) : Colors.grey))),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('الدرجة:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              TextField(
                controller: _gradeController,
                enabled: _excelLoaded,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                decoration: InputDecoration(
                  hintText: '0.0', filled: true, fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('العداد:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                height: 48,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300)),
                child: Center(child: Text('$_totalStudentsCount / $_scannedStudentsCount',
                    style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 16))),
              ),
            ])),
          ]),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: !_excelLoaded ? Colors.grey : (_isScanningActive ? Colors.red.shade700 : const Color(0xFF4CAF50)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
            icon: Icon(_isScanningActive ? Icons.stop : Icons.camera_alt, color: Colors.white),
            label: Text(_isScanningActive ? 'إيقاف' : 'ابدأ المسح',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: _excelLoaded ? () async {
              setState(() => _isScanningActive = !_isScanningActive);
              if (_isScanningActive) { await _scannerController.start(); } else { await _scannerController.stop(); }
            } : null,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _excelLoaded ? const Color(0xFF0288D1) : const Color(0xFFB0BEC5),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
            onPressed: _excelLoaded ? _saveGradeDirectly : null,
            child: const Text('تأكيد وحفظ الدرجة',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 12),
          if (_isScanningActive && _excelLoaded)
            Container(
              height: 220,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400, width: 2)),
              clipBehavior: Clip.antiAlias,
              child: MobileScanner(
                controller: _scannerController,
                onDetect: (capture) async {
                  // منع المعالجة المتكررة
                  if (_isProcessingCapture) return;
                  if (capture.barcodes.isEmpty || capture.barcodes.first.rawValue == null) return;
                  
                  final qrValue = capture.barcodes.first.rawValue!.trim();
                  if (qrValue.isEmpty || qrValue == _secretCode) return;

                  _isProcessingCapture = true;
                  await _scannerController.stop();
                  
                  setState(() { _secretCode = qrValue; _gradeController.clear(); });

                  if (capture.image != null) {
                    final regions = await _cropImageRegions(capture.image!);
                    if (regions != null && regions['left'] != null) {
                      final leftText = await _ocrFromBytes(regions['left']!);
                      final gradeText = _extractNumber(leftText);
                      
                      if (gradeText.isNotEmpty) {
                        setState(() => _gradeController.text = gradeText);
                        _showSnack('✅ درجة مقروءة: $gradeText');
                      } else {
                        _showSnack('ℹ️ لم يتم التعرف على الدرجة، أدخلها يدوياً');
                      }
                    }
                  } else {
                    _showSnack('⚠️ لم يتم التقاط صورة');
                  }

                  _isProcessingCapture = false;
                  if (_isScanningActive) await _scannerController.start();
                },
              ),
            ),
        ]),
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart'; // ✅ مكتبة فتح الملف لمنع "حفظ باسم"

bool _isMahsala1(String t) => t == 'م١' || t == 'م1' || t == 'م۱';
bool _isMahsala2(String t) => t == 'م٢' || t == 'م2' || t == 'م۲';
bool _isFasl1(String t) => t == 'ف١' || t == 'ف1' || t == 'ف۱';
bool _isFasl2(String t) => t == 'ف٢' || t == 'ف2' || t == 'ف۲';

List<String> _extractSheetNamesIsolate(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  return excel.tables.keys.toList();
}

Map<String, dynamic> _getMonthsAndStudentsIsolate(Map<String, dynamic> args) {
  final String filePath = args['filePath'];
  final String sheetName = args['sheetName'];
  final bool isTerm2 = args['isTerm2'];

  final bytes = File(filePath).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables[sheetName];
  if (sheet == null) return {'error': 'Sheet not found'};

  int students = 0;
  for (int r = 3; r < sheet.maxRows; r++) {
    final val = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value;
    if (val != null && val.toString().trim().isNotEmpty) students++;
  }

  List<String> term1List = [];
  List<String> term2List = [];
  bool foundF1 = false;
  bool foundF2 = false;

  int col = 4;
  while (col < sheet.maxColumns) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1));
    final text = cell.value?.toString().trim() ?? '';

    if (text.isNotEmpty) {
      final cleanText = text.replaceAll(RegExp(r'\s+'), '');

      if (_isMahsala1(cleanText)) {
        col += 1; continue;
      } else if (_isFasl1(cleanText)) {
        foundF1 = true; col += 1; continue;
      } else if (_isMahsala2(cleanText)) {
        col += 1; continue;
      } else if (_isFasl2(cleanText)) {
        foundF2 = true; break;
      } else {
        if (!foundF1) {
          term1List.add(text);
        } else if (!foundF2) {
          term2List.add(text);
        }
        col += 5;
      }
    } else {
      col += 1;
    }
  }

  List<String> activeMonths = [];
  if (!isTerm2) {
    activeMonths.addAll(term1List);
    if (foundF1) activeMonths.add('ف١');
  } else {
    activeMonths.addAll(term2List);
    if (foundF2) activeMonths.add('ف٢');
  }

  return {
    'students': students,
    'activeMonths': activeMonths,
  };
}

Map<String, dynamic> _saveGradeIsolate(Map<String, dynamic> args) {
  final String filePath = args['filePath'];
  final String sheetName = args['sheetName'];
  final String secretCode = args['secretCode'];
  final String selectedMonth = args['selectedMonth'];
  final double gradeVal = args['gradeVal'];

  try {
    final file = File(filePath);
    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables[sheetName];
    if (sheet == null) return {'success': false, 'message': 'الورقة غير موجودة'};

    int targetRow = -1;
    final cleanSecret = secretCode.trim();
    for (int r = 3; r < sheet.maxRows; r++) {
      final cellVal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value;
      if (cellVal != null && cellVal.toString().trim() == cleanSecret) {
        targetRow = r;
        break;
      }
    }
    if (targetRow == -1) return {'success': false, 'message': 'الرقم السري ($cleanSecret) غير موجود!'};

    int targetCol = -1;
    final cleanSelected = selectedMonth.replaceAll(RegExp(r'\s+'), '');
    int c = 4;
    while (c < sheet.maxColumns) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 1));
      final text = cell.value?.toString().trim() ?? '';

      if (text.isNotEmpty) {
        final cleanText = text.replaceAll(RegExp(r'\s+'), '');
        bool isMatch = (cleanText == cleanSelected) ||
            (_isFasl1(cleanSelected) && _isFasl1(cleanText)) ||
            (_isFasl2(cleanSelected) && _isFasl2(cleanText));

        if (isMatch) {
          if (_isFasl1(cleanSelected) || _isFasl2(cleanSelected)) {
            targetCol = c;
          } else {
            targetCol = c + 3;
          }
          break;
        }

        if (_isMahsala1(cleanText) || _isFasl1(cleanText) ||
            _isMahsala2(cleanText) || _isFasl2(cleanText)) {
          c += 1;
        } else {
          c += 5;
        }
      } else {
        c += 1;
      }
    }

    if (targetCol == -1) return {'success': false, 'message': 'تعذر تحديد عمود الدرجة!'};

    final existingCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: targetCol, rowIndex: targetRow)).value;
    String existingText = '';
    if (existingCell != null) {
      if (existingCell is TextCellValue) {
        existingText = (existingCell.value.text ?? '').trim();
      } else if (existingCell is IntCellValue) {
        existingText = existingCell.value.toString().trim();
      } else if (existingCell is DoubleCellValue) {
        final d = existingCell.value;
        existingText = (d == d.toInt() ? d.toInt().toString() : d.toString()).trim();
      } else {
        existingText = existingCell.toString().trim();
      }
    }

    if (existingText.isNotEmpty) {
      return {'success': false, 'message': 'رصد مسبق', 'existingText': existingText};
    }

    sheet.cell(CellIndex.indexByColumnRow(columnIndex: targetCol, rowIndex: targetRow)).value = DoubleCellValue(gradeVal);
    final encodedData = excel.encode();
    if (encodedData != null) {
      file.writeAsBytesSync(encodedData, flush: true);
      return {'success': true};
    }
    return {'success': false, 'message': 'فشل ترميز الملف'};
  } catch (e) {
    return {'success': false, 'message': 'خطأ في الحفظ: $e'};
  }
}

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
  bool _isProcessingCapture = false;
  bool _isTorchOn = false;
  bool _isLoading = false;

  final MobileScannerController _scannerController = MobileScannerController(
    autoStart: false,
    torchEnabled: false,
    returnImage: true,
  );

  final TextRecognizer _latinRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadLastExcelFile();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _latinRecognizer.close();
    _gradeController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    if (!await Permission.camera.isGranted) await Permission.camera.request();
    if (!await Permission.storage.isGranted) await Permission.storage.request();
    if (!await Permission.manageExternalStorage.isGranted) {
      final status = await Permission.manageExternalStorage.request();
      if (status.isDenied && mounted) _showManageStorageDialog();
    }
  }

  void _showManageStorageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('صلاحية مطلوبة'),
        content: const Text('لكي يعمل التطبيق، نحتاج صلاحية "إدارة جميع الملفات".\n\nاضغط "فتح الإعدادات" ثم فعّل الخيار للتطبيق.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لاحقاً')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await openAppSettings();
            },
            child: const Text('فتح الإعدادات'),
          ),
        ],
      ),
    );
  }

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

  Future<void> _loadLastExcelFile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? lastFile = prefs.getString('last_excel_file');
      if (lastFile != null && await File(lastFile).exists()) {
        setState(() => _isLoading = true);

        final sheets = await compute(_extractSheetNamesIsolate, lastFile);
        final fileName = lastFile.split('/').last;

        final savedSheet = prefs.getString('last_sheet_$fileName');
        final validSheet = (savedSheet != null && sheets.contains(savedSheet))
            ? savedSheet
            : (sheets.isNotEmpty ? sheets.first : null);

        setState(() {
          _excelFilePath = lastFile;
          _excelFileName = fileName;
          _excelLoaded = true;
          _sheetNames = sheets;
          _selectedSheet = validSheet;
          _isLoading = false;
        });

        if (validSheet != null) await _loadMonthsAndStudents();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('خطأ في تحميل آخر ملف: $e');
    }
  }

  Future<void> _pickExcelFile() async {
    try {
      await _requestPermissions();
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'xlsm'],
      );
      if (result == null || result.files.single.path == null) return;

      setState(() => _isLoading = true);

      final cachePath = result.files.single.path!;
      final fileName = result.files.single.name;
      final path = await _getPermanentExcelPath(fileName, cachePath);

      final sheets = await compute(_extractSheetNamesIsolate, path);

      final prefs = await SharedPreferences.getInstance();
      final savedSheet = prefs.getString('last_sheet_$fileName');
      final validSheet = (savedSheet != null && sheets.contains(savedSheet))
          ? savedSheet
          : (sheets.isNotEmpty ? sheets.first : null);

      setState(() {
        _excelLoaded = true;
        _excelFilePath = path;
        _excelFileName = fileName;
        _sheetNames = sheets;
        _selectedSheet = validSheet;
        _isLoading = false;
      });

      await prefs.setString('last_excel_file', path);

      if (validSheet != null) await _loadMonthsAndStudents();
      _showSnack('✅ تم تحميل: $fileName');
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('❌ تعذر قراءة الملف: $e');
    }
  }

  Future<void> _loadMonthsAndStudents() async {
    if (_excelFilePath == null || _selectedSheet == null) return;

    setState(() => _isLoading = true);

    try {
      final result = await compute(_getMonthsAndStudentsIsolate, {
        'filePath': _excelFilePath!,
        'sheetName': _selectedSheet!,
        'isTerm2': _isTerm2,
      });

      if (result.containsKey('error')) {
        debugPrint(result['error']);
        setState(() => _isLoading = false);
        return;
      }

      final students = result['students'] as int;
      final activeMonths = result['activeMonths'] as List<String>;

      setState(() {
        _totalStudentsCount = students;
        _monthsList = activeMonths;
        _selectedMonthOrSubject = activeMonths.isNotEmpty ? activeMonths.first : null;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('خطأ في استخراج الشهور: $e');
    }
  }

  void _switchTerm(bool isSecondTerm) {
    if (!_excelLoaded) return;
    setState(() => _isTerm2 = isSecondTerm);
    _loadMonthsAndStudents();
  }

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
    final match = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(converted);
    return match?.group(0)?.replaceAll(',', '.') ?? '';
  }

  img.Image _preprocessImageForOcr(img.Image src) {
    final processed = img.Image.from(src);
    for (int y = 0; y < processed.height; y++) {
      for (int x = 0; x < processed.width; x++) {
        final pixel = processed.getPixel(x, y);
        final num r = pixel.r, g = pixel.g, b = pixel.b;
        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        final isRedInk = r > 100 && (r - g) > 50 && (r - b) > 50;
        final isBlueInk = b > 100 && (b - r) > 50 && (b - g) > 50;
        final isBlackInk = luminance < 100;

        if (isRedInk || isBlueInk || isBlackInk) {
          processed.setPixelRgb(x, y, 0, 0, 0);
        }
      }
    }
    return processed;
  }

  Future<Uint8List?> _cropLeftRegion(Uint8List bytes) async {
    try {
      img.Image? full = img.decodeImage(bytes);
      if (full == null) return null;
      full = img.bakeOrientation(full);
      final int w = full.width;
      final int h = full.height;
      final int regionW = w ~/ 3;
      var left = img.copyCrop(full, x: 0, y: 0, width: regionW, height: h);
      left = _preprocessImageForOcr(left);
      return Uint8List.fromList(img.encodePng(left));
    } catch (e) {
      return null;
    }
  }

  Future<String> _ocrFromBytes(Uint8List bytes) async {
    File? tempFile;
    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('ocr_');
      tempFile = File('${tempDir.path}/img.png');
      await tempFile.writeAsBytes(bytes);
      final input = InputImage.fromFile(tempFile);
      final result = await _latinRecognizer.processImage(input);
      return result.text.trim();
    } catch (e) {
      return '';
    } finally {
      try { await tempFile?.delete(); } catch (_) {}
      try { await tempDir?.delete(); } catch (_) {}
    }
  }

  Future<void> _saveGradeDirectly() async {
    if (!_excelLoaded || _excelFilePath == null || _selectedSheet == null) {
      _showSnack('⚠️ اختر ملف الأكسيل أولاً');
      return;
    }
    if (_secretCode.isEmpty) {
      _showSnack('⚠️ امسح رمز QR أولاً');
      return;
    }
    if (_selectedMonthOrSubject == null) {
      _showSnack('⚠️ اختر الشهر/الفترة أولاً');
      return;
    }

    final double? gradeVal = double.tryParse(_gradeController.text.trim());
    if (gradeVal == null) {
      _showSnack('⚠️ الدرجة غير صحيحة');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await compute(_saveGradeIsolate, {
        'filePath': _excelFilePath!,
        'sheetName': _selectedSheet!,
        'secretCode': _secretCode,
        'selectedMonth': _selectedMonthOrSubject!,
        'gradeVal': gradeVal,
      });

      if (result['success'] == true) {
        setState(() {
          _scannedStudentsCount++;
          _secretCode = '';
          _gradeController.clear();
        });
        _showSnack('✅ تم حفظ الدرجة ($gradeVal) في ($_selectedMonthOrSubject)');
      } else if (result['message'] == 'رصد مسبق') {
        _showDialogAlert(
          title: '⚠️ رصد مسبق!',
          message: 'الطالب ($_secretCode) تم رصده مسبقاً في ($_selectedMonthOrSubject) بدرجة (${result['existingText']}).\n\nإذا أردت تعديل الدرجة، امسحها يدوياً.',
        );
      } else {
        _showSnack('❌ ${result['message']}');
      }
    } catch (e) {
      _showSnack('❌ خطأ أثناء الحفظ: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDialogAlert({required String title, required String message}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
        ],
      ),
    );
  }

  Future<void> _processCapture(BarcodeCapture capture) async {
    if (_isProcessingCapture) return;
    if (capture.barcodes.isEmpty || capture.barcodes.first.rawValue == null) return;

    final qrValue = capture.barcodes.first.rawValue!.trim();
    if (qrValue.isEmpty || qrValue == _secretCode) return;

    _isProcessingCapture = true;
    await _scannerController.stop();

    setState(() {
      _secretCode = qrValue;
      _gradeController.clear();
    });

    if (capture.image != null) {
      final leftBytes = await _cropLeftRegion(capture.image!);
      if (leftBytes != null) {
        final leftText = await _ocrFromBytes(leftBytes);
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
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _toggleScanning() async {
    if (!_excelLoaded) {
      _showSnack('⚠️ اختر ملف الأكسيل أولاً');
      return;
    }
    setState(() => _isScanningActive = !_isScanningActive);
    if (_isScanningActive) {
      await _scannerController.start();
      if (_isTorchOn) await _scannerController.toggleTorch();
    } else {
      await _scannerController.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text('إدخال الدرجات من أوراق الإجابة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        backgroundColor: const Color(0xFF0288D1),
        centerTitle: true,
        actions: [
          // ✅ زر فتح الملف بصلاحيات الكتابة
          if (_excelLoaded && _excelFilePath != null)
            IconButton(
              icon: const Icon(Icons.table_chart, color: Colors.white),
              tooltip: 'فتح الملف في تطبيق آخر',
              onPressed: () async {
                final result = await OpenFilex.open(
                  _excelFilePath!,
                  type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                  writePermission: true,
                );
                if (result.type != ResultType.done) {
                  _showSnack('تعذر فتح الملف: ${result.message}');
                }
              },
            ),
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            onPressed: () async {
              setState(() => _isTorchOn = !_isTorchOn);
              if (_isScanningActive) await _scannerController.toggleTorch();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.folder_open, color: Colors.white),
              onPressed: _isLoading ? null : _pickExcelFile,
              label: Text(
                _excelLoaded ? 'تغيير ملف الأكسيل' : 'اختر ملف الأكسيل (الكشوفات)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 8),

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
                  Icon(_excelLoaded ? Icons.check_circle : Icons.info_outline, color: _excelLoaded ? Colors.green : Colors.grey, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _excelFileName ?? 'لم يتم تحديد ملف إكسيل بعد',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _excelLoaded ? Colors.black87 : Colors.red.shade700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            const Text('المادة (ورقة العمل):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: _excelLoaded ? Colors.white : Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSheet,
                  isExpanded: true,
                  hint: Text(_excelLoaded ? 'اختر المادة' : 'يرجى اختيار ملف الأكسيل أولاً', style: TextStyle(color: _excelLoaded ? Colors.black54 : Colors.grey)),
                  items: _excelLoaded
                      ? _sheetNames.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)))).toList()
                      : null,
                  onChanged: (_excelLoaded && !_isLoading)
                      ? (v) async {
                          setState(() => _selectedSheet = v);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('last_sheet_$_excelFileName', v!);
                          _loadMonthsAndStudents();
                        }
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: (!_isTerm2 && _excelLoaded) ? const Color(0xFF1976D2) : Colors.white,
                      foregroundColor: (!_isTerm2 && _excelLoaded) ? Colors.white : Colors.black87,
                      side: BorderSide(color: _excelLoaded ? const Color(0xFF1976D2) : Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: (_excelLoaded && !_isLoading) ? () => _switchTerm(false) : null,
                    child: const Text('اختبار الفصل الأول', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      backgroundColor: (_isTerm2 && _excelLoaded) ? const Color(0xFF1976D2) : Colors.white,
                      foregroundColor: (_isTerm2 && _excelLoaded) ? Colors.white : Colors.black87,
                      side: BorderSide(color: _excelLoaded ? const Color(0xFF1976D2) : Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: (_excelLoaded && !_isLoading) ? () => _switchTerm(true) : null,
                    child: const Text('اختبار الفصل الثاني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            const Text('فترة الرصد (الشهر / نهاية الفصل):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: _excelLoaded ? Colors.white : Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMonthOrSubject,
                  isExpanded: true,
                  hint: const Text('حدد الشهر أو الفترة'),
                  items: _excelLoaded
                      ? _monthsList.map((m) {
                          final isTerm = m == 'ف١' || m == 'ف٢';
                          return DropdownMenuItem(
                            value: m,
                            child: Text(
                              isTerm ? '$m (نهاية الفصل)' : m,
                              style: TextStyle(fontWeight: isTerm ? FontWeight.bold : FontWeight.normal, color: isTerm ? const Color(0xFF0F766E) : Colors.black87),
                            ),
                          );
                        }).toList()
                      : null,
                  onChanged: (_excelLoaded && !_isLoading) ? (v) => setState(() => _selectedMonthOrSubject = v) : null,
                ),
              ),
            ),
            const SizedBox(height: 10),

            const Text('الرقم السري للطالب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              height: 48,
              decoration: BoxDecoration(color: _excelLoaded ? Colors.white : Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
              child: Center(
                child: Text(
                  _secretCode.isNotEmpty ? _secretCode : 'سيظهر بعد المسح',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: _secretCode.isNotEmpty ? const Color(0xFF1976D2) : Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('الدرجة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _gradeController,
                        enabled: _excelLoaded && !_isLoading,
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
                      const Text('العداد:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 4),
                      Container(
                        height: 48,
                        decoration: BoxDecoration(color: _excelLoaded ? Colors.white : Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                        child: Center(
                          child: Text(
                            '$_totalStudentsCount / $_scannedStudentsCount',
                            style: TextStyle(color: _excelLoaded ? const Color(0xFF2E7D32) : Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: !_excelLoaded ? Colors.grey : (_isScanningActive ? Colors.red.shade700 : const Color(0xFF4CAF50)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              icon: Icon(_isScanningActive ? Icons.stop : Icons.camera_alt, color: Colors.white),
              label: Text(
                _isScanningActive ? 'إيقاف الكاميرا' : 'ابدأ المسح',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              onPressed: (_excelLoaded && !_isLoading) ? _toggleScanning : null,
            ),
            const SizedBox(height: 8),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _excelLoaded ? const Color(0xFF0288D1) : const Color(0xFFB0BEC5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              onPressed: (_excelLoaded && !_isLoading) ? _saveGradeDirectly : null,
              child: _isLoading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('تأكيد وحفظ الدرجة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(height: 12),

            if (_isScanningActive && _excelLoaded)
              Container(
                height: 220,
                decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400, width: 2)),
                clipBehavior: Clip.antiAlias,
                child: MobileScanner(controller: _scannerController, onDetect: _processCapture),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio; // ✅ المكتبة الجديدة

bool _isMahsala1(String t) => t == 'م١' || t == 'م1' || t == 'م۱';
bool _isMahsala2(String t) => t == 'م٢' || t == 'م2' || t == 'م۲';
bool _isFasl1(String t) => t == 'ف١' || t == 'ف1' || t == 'ف۱';
bool _isFasl2(String t) => t == 'ف٢' || t == 'ف2' || t == 'ف۲';

// 1. قراءة أسماء الأوراق فقط (سريعة)
List<String> _extractSheetNamesIsolate(String filePath) {
  final bytes = File(filePath).readAsBytesSync();
  final workbook = xlsio.Workbook.fromBytes(bytes);
  final sheets = workbook.worksheets.map((sheet) => sheet.name).toList();
  workbook.dispose();
  return sheets;
}

// 2. قراءة الشهور والطلاب في الخلفية
Map<String, dynamic> _getMonthsAndStudentsIsolate(Map<String, dynamic> args) {
  final String filePath = args['filePath'];
  final String sheetName = args['sheetName'];
  final bool isTerm2 = args['isTerm2'];

  final bytes = File(filePath).readAsBytesSync();
  final workbook = xlsio.Workbook.fromBytes(bytes);

  xlsio.Worksheet? sheet;
  try {
    sheet = workbook.worksheets.firstWhere((s) => s.name == sheetName);
  } catch (e) {
    workbook.dispose();
    return {'error': 'Sheet not found'};
  }

  // استخراج الشهور
  List<String> term1List = [];
  List<String> term2List = [];
  bool foundF1 = false;
  bool foundF2 = false;

  int col = 5; // البدء من العمود E (رقم 5)
  while (col <= sheet.getLastColumn()) {
    final text = sheet.getRangeByIndex(2, col).text.trim(); // الصف الثاني

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

  // استخراج الطلاب والصفوف
  List<Map<String, dynamic>> students = [];
  Set<String> gradesSet = {};

  for (int r = 4; r <= sheet.getLastRow(); r++) {
    final seat = sheet.getRangeByIndex(r, 1).text.trim(); // العمود A
    final name = sheet.getRangeByIndex(r, 2).text.trim(); // العمود B
    final grade = sheet.getRangeByIndex(r, 3).text.trim(); // العمود C

    if (name.isNotEmpty) {
      if (grade.isNotEmpty) gradesSet.add(grade);
      students.add({
        'seat': seat,
        'name': name,
        'grade': grade,
        'row': r - 1, // تحويلها إلى 0-based لتتوافق مع الواجهة
      });
    }
  }

  workbook.dispose();
  return {
    'months': activeMonths,
    'students': students,
    'grades': gradesSet.toList(),
  };
}

// 3. عملية الحفظ في الخلفية
Map<String, dynamic> _saveManualGradesIsolate(Map<String, dynamic> args) {
  final String filePath = args['filePath'];
  final String sheetName = args['sheetName'];
  final int targetRow = args['targetRow']; // 0-based coming from UI
  final String selectedMonth = args['selectedMonth'];
  final double? hw = args['hw'];
  final double? oral = args['oral'];
  final double? att = args['att'];

  try {
    final file = File(filePath);
    final bytes = file.readAsBytesSync();
    final workbook = xlsio.Workbook.fromBytes(bytes);

    xlsio.Worksheet? sheet;
    try {
      sheet = workbook.worksheets.firstWhere((s) => s.name == sheetName);
    } catch (e) {
      workbook.dispose();
      return {'success': false, 'message': 'الورقة غير موجودة'};
    }

    int targetCol = -1;
    final cleanSelected = selectedMonth.replaceAll(RegExp(r'\s+'), '');
    int c = 5;
    while (c <= sheet.getLastColumn()) {
      final text = sheet.getRangeByIndex(2, c).text.trim();

      if (text.isNotEmpty) {
        final cleanText = text.replaceAll(RegExp(r'\s+'), '');
        bool isMatch = (cleanText == cleanSelected);

        if (isMatch) {
          targetCol = c; 
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

    if (targetCol == -1) {
      workbook.dispose();
      return {'success': false, 'message': 'تعذر تحديد عمود الشهر'};
    }

    // تحويل الصف من 0-based إلى 1-based لمكتبة Syncfusion
    final int xlsioRow = targetRow + 1;

    // الواجبات = العمود الأول، الشفهي = الثاني، المواظبة = الثالث
    if (hw != null) sheet.getRangeByIndex(xlsioRow, targetCol).setNumber(hw);
    if (oral != null) sheet.getRangeByIndex(xlsioRow, targetCol + 1).setNumber(oral);
    if (att != null) sheet.getRangeByIndex(xlsioRow, targetCol + 2).setNumber(att);

    final List<int> newBytes = workbook.saveSync();
    file.writeAsBytesSync(newBytes, flush: true);
    
    workbook.dispose();
    return {'success': true};
  } catch (e) {
    return {'success': false, 'message': 'خطأ في الحفظ: $e'};
  }
}

class ManualGradeEntryScreen extends StatefulWidget {
  const ManualGradeEntryScreen({super.key});

  @override
  State<ManualGradeEntryScreen> createState() => _ManualGradeEntryScreenState();
}

class _ManualGradeEntryScreenState extends State<ManualGradeEntryScreen> {
  String? _excelFilePath;
  String? _excelFileName;
  bool _excelLoaded = false;
  List<String> _sheetNames = [];
  String? _selectedSheet;

  bool _isTerm2 = false;
  List<String> _monthsList = [];
  String? _selectedMonthOrSubject;

  List<Map<String, dynamic>> _allStudents = [];
  List<Map<String, dynamic>> _filteredStudents = [];
  List<String> _gradesList = [];
  String? _selectedGrade;
  int? _selectedStudentRow;
  bool _showSuggestions = false;

  final TextEditingController _studentNameController = TextEditingController();
  final TextEditingController _hwController = TextEditingController();
  final TextEditingController _oralController = TextEditingController();
  final TextEditingController _attController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadLastExcelFile();
  }

  @override
  void dispose() {
    _studentNameController.dispose();
    _hwController.dispose();
    _oralController.dispose();
    _attController.dispose();
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
        content: const Text('لكي يعمل التطبيق، نحتاج صلاحية "إدارة جميع الملفات".'),
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
        
        if (validSheet != null) await _loadData();
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
      
      if (validSheet != null) await _loadData();
      _showSnack('✅ تم تحميل: $fileName');
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnack('❌ تعذر قراءة الملف: $e');
    }
  }

  Future<void> _loadData() async {
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

      final months = result['months'] as List<String>;
      final students = result['students'] as List<dynamic>;
      final grades = result['grades'] as List<String>;

      setState(() {
        _monthsList = months;
        _selectedMonthOrSubject = months.isNotEmpty ? months.first : null;
        
        _allStudents = students.cast<Map<String, dynamic>>();
        _filteredStudents = [];
        _gradesList = grades;
        _selectedGrade = null;
        _selectedStudentRow = null;
        _studentNameController.clear();
        _showSuggestions = false;
        
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('خطأ في تحميل البيانات: $e');
    }
  }

  void _switchTerm(bool isSecondTerm) {
    if (!_excelLoaded) return;
    setState(() => _isTerm2 = isSecondTerm);
    _loadData();
  }

  void _onNameChanged(String val) {
    setState(() {
      if (val.trim().isEmpty) {
        _showSuggestions = false;
        _selectedStudentRow = null;
      } else {
        _showSuggestions = true;
        _filteredStudents = _allStudents.where((s) {
          final gradeMatch = _selectedGrade == null || _selectedGrade!.isEmpty || s['grade'] == _selectedGrade;
          final nameMatch = s['name'].toString().contains(val.trim());
          return gradeMatch && nameMatch;
        }).toList();
        _selectedStudentRow = null;
      }
    });
  }

  Future<void> _saveGrades() async {
    if (_selectedStudentRow == null) {
      _showSnack('⚠️ يرجى اختيار طالب من القائمة أولاً');
      return;
    }
    if (_selectedMonthOrSubject == null) {
      _showSnack('⚠️ اختر الشهر أولاً');
      return;
    }

    final hwText = _hwController.text.trim();
    final oralText = _oralController.text.trim();
    final attText = _attController.text.trim();

    if (hwText.isEmpty && oralText.isEmpty && attText.isEmpty) {
      _showSnack('⚠️ أدخل درجة واحدة على الأقل');
      return;
    }

    final hw = hwText.isNotEmpty ? double.tryParse(hwText) : null;
    final oral = oralText.isNotEmpty ? double.tryParse(oralText) : null;
    final att = attText.isNotEmpty ? double.tryParse(attText) : null;

    if ((hwText.isNotEmpty && hw == null) ||
        (oralText.isNotEmpty && oral == null) ||
        (attText.isNotEmpty && att == null)) {
      _showSnack('⚠️ تأكد من إدخال أرقام صحيحة');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await compute(_saveManualGradesIsolate, {
        'filePath': _excelFilePath!,
        'sheetName': _selectedSheet!,
        'targetRow': _selectedStudentRow!,
        'selectedMonth': _selectedMonthOrSubject!,
        'hw': hw,
        'oral': oral,
        'att': att,
      });

      if (result['success'] == true) {
        // ✅ التعديل الجديد: تفريغ حقل الاسم وتصفير الصف المحدد بعد الحفظ مباشرة
        setState(() {
          _studentNameController.clear();
          _hwController.clear();
          _oralController.clear();
          _attController.clear();
          _selectedStudentRow = null;
          _showSuggestions = false;
        });
        _showSnack('✅ تم حفظ درجات أعمال السنة بنجاح');
      } else {
        _showSnack('❌ ${result['message']}');
      }
    } catch (e) {
      _showSnack('❌ خطأ أثناء الحفظ: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text('إدخال بقية درجات أعمال السنة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        backgroundColor: const Color(0xFF00897B),
        centerTitle: true,
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
              label: Text(_excelLoaded ? 'تغيير ملف الأكسيل' : 'اختر ملف الأكسيل (الكشوفات)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _excelLoaded ? Colors.green.shade400 : Colors.grey.shade300, width: _excelLoaded ? 1.5 : 1.0),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_excelLoaded ? Icons.check_circle : Icons.info_outline, color: _excelLoaded ? Colors.green : Colors.grey, size: 18),
                  const SizedBox(width: 8),
                  Flexible(child: Text(_excelFileName ?? 'لم يتم تحديد ملف إكسيل بعد', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: _excelLoaded ? Colors.black87 : Colors.red.shade700), overflow: TextOverflow.ellipsis)),
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
                  items: _excelLoaded ? _sheetNames.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontWeight: FontWeight.bold)))).toList() : null,
                  onChanged: (_excelLoaded && !_isLoading)
                      ? (v) async {
                          setState(() => _selectedSheet = v);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString('last_sheet_$_excelFileName', v!);
                          _loadData();
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
                    child: const Text('الفصل الأول', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
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
                    child: const Text('الفصل الثاني', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            const Text('فترة الرصد (الشهر):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: _excelLoaded ? Colors.white : Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMonthOrSubject,
                  isExpanded: true,
                  hint: const Text('حدد الشهر'),
                  items: _excelLoaded
                      ? _monthsList.map((m) => DropdownMenuItem(value: m, child: Text(m, style: const TextStyle(fontWeight: FontWeight.bold)))).toList()
                      : null,
                  onChanged: (_excelLoaded && !_isLoading) ? (v) => setState(() => _selectedMonthOrSubject = v) : null,
                ),
              ),
            ),
            const SizedBox(height: 12),

            const Text('الصف الدراسي:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: _excelLoaded ? Colors.white : Colors.grey.shade200, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedGrade,
                  isExpanded: true,
                  hint: Text(_excelLoaded ? 'اختر الصف (أو اتركه فارغاً للكل)' : 'يرجى اختيار ملف الأكسيل أولاً', style: TextStyle(color: _excelLoaded ? Colors.black54 : Colors.grey)),
                  items: _excelLoaded ? _gradesList.map((g) => DropdownMenuItem(value: g, child: Text(g, style: const TextStyle(fontWeight: FontWeight.bold)))).toList() : null,
                  onChanged: (_excelLoaded && !_isLoading)
                      ? (v) {
                          setState(() {
                            _selectedGrade = v;
                            _studentNameController.clear();
                            _selectedStudentRow = null;
                            _showSuggestions = false;
                          });
                        }
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 12),

            const Text('اسم الطالب (اكتب الجزء الأول للبحث):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            TextField(
              controller: _studentNameController,
              enabled: _excelLoaded && !_isLoading,
              onChanged: _onNameChanged,
              decoration: InputDecoration(
                hintText: 'اكتب اسم الطالب...',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (_showSuggestions && _filteredStudents.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _filteredStudents.length,
                  itemBuilder: (context, index) {
                    final s = _filteredStudents[index];
                    return ListTile(
                      title: Text('${s['name']} (${s['seat']})'),
                      onTap: () {
                        setState(() {
                          _studentNameController.text = s['name'];
                          _selectedStudentRow = s['row'];
                          _showSuggestions = false;
                        });
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),

            const Text('درجات أعمال السنة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hwController,
                    enabled: _excelLoaded && !_isLoading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(labelText: 'الواجبات', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _oralController,
                    enabled: _excelLoaded && !_isLoading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(labelText: 'الشفهي', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _attController,
                    enabled: _excelLoaded && !_isLoading,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(labelText: 'المواظبة', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _excelLoaded ? const Color(0xFF00897B) : const Color(0xFFB0BEC5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
              ),
              onPressed: (_excelLoaded && !_isLoading) ? _saveGrades : null,
              child: _isLoading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('حفظ درجات أعمال السنة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

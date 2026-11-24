import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart'; // ✅ مكتبة فتح الملف

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

  List<Map<String, dynamic>> students = [];
  Set<String> gradesSet = {};

  for (int r = 3; r < sheet.maxRows; r++) {
    final seatVal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: r)).value;
    final nameVal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value;
    final gradeVal = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r)).value;

    final seat = seatVal?.toString().trim() ?? '';
    final name = nameVal?.toString().trim() ?? '';
    final grade = gradeVal?.toString().trim() ?? '';

    if (name.isNotEmpty) {
      if (grade.isNotEmpty) gradesSet.add(grade);
      students.add({
        'seat': seat,
        'name': name,
        'grade': grade,
        'row': r,
      });
    }
  }

  return {
    'months': activeMonths,
    'students': students,
    'grades': gradesSet.toList(),
  };
}


/// قراءة درجات الطالب المسجلة مسبقاً في أعمدة الواجبات والشفهي والمواظبة.
Map<String, dynamic> _getStudentGradesIsolate(Map<String, dynamic> args) {
  final String filePath = args['filePath'];
  final String sheetName = args['sheetName'];
  final int targetRow = args['targetRow'];
  final String selectedMonth = args['selectedMonth'];

  try {
    final excel = Excel.decodeBytes(File(filePath).readAsBytesSync());
    final sheet = excel.tables[sheetName];
    if (sheet == null) return {'error': 'ورقة العمل غير موجودة.'};

    final wanted = selectedMonth.replaceAll(RegExp(r'\s+'), '');
    var targetCol = -1;
    var col = 4;
    while (col < 500) {
      final value = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1)).value;
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        final clean = text.replaceAll(RegExp(r'\s+'), '');
        if (clean == wanted) {
          targetCol = col;
          break;
        }
        if (_isMahsala1(clean) || _isFasl1(clean) ||
            _isMahsala2(clean) || _isFasl2(clean)) {
          col++;
        } else {
          col += 5;
        }
      } else {
        col++;
      }
    }

    if (targetCol < 0) return {'error': 'تعذر تحديد أعمدة الفترة المختارة.'};

    String readGrade(int column) {
      final value = sheet.cell(CellIndex.indexByColumnRow(
        columnIndex: column,
        rowIndex: targetRow,
      )).value;
      return value?.toString().trim() ?? '';
    }

    return {
      'hw': readGrade(targetCol),
      'oral': readGrade(targetCol + 1),
      'att': readGrade(targetCol + 2),
    };
  } catch (e) {
    return {'error': 'تعذر قراءة درجات الطالب: $e'};
  }
}

const String _manualRelNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

String _manualZipPath(String p) {
  final out=<String>[];
  for(final x in p.replaceAll('\\','/').split('/')) {
    if(x.isEmpty||x=='.') continue;
    if(x=='..'){if(out.isNotEmpty) out.removeLast();} else {out.add(x);}
  }
  return out.join('/');
}
String _manualSheetPath(Archive z,String name) {
  final w=XmlDocument.parse(utf8.decode(z.findFile('xl/workbook.xml')!.content as List<int>));
  final rel=XmlDocument.parse(utf8.decode(z.findFile('xl/_rels/workbook.xml.rels')!.content as List<int>));
  String? id;
  for(final e in w.descendants.whereType<XmlElement>().where((e)=>e.name.local=='sheet')) {
    if((e.getAttribute('name')??'').trim()==name.trim()) {
      for(final at in e.attributes){if(at.name.local=='id'){id=at.value;break;}}
      break;
    }
  }
  if(id==null) throw Exception('لم يتم العثور على ورقة العمل ($name).');
  for(final e in rel.descendants.whereType<XmlElement>().where((e)=>e.name.local=='Relationship')) {
    if(e.getAttribute('Id')==id) {
      final t=e.getAttribute('Target');
      if(t!=null) return _manualZipPath(t.startsWith('/')?t:'xl/'+t);
    }
  }
  throw Exception('تعذر تحديد مسار ورقة العمل.');
}
XmlElement? _manualChild(XmlNode n,String name) {
  for(final c in n.children){if(c is XmlElement&&c.name.local==name)return c;}
  return null;
}
List<XmlElement> _manualDesc(XmlNode n,String name)=>
  n.descendants.whereType<XmlElement>().where((e)=>e.name.local==name).toList();
List<String> _manualStrings(Archive z) {
  final f=z.findFile('xl/sharedStrings.xml'); if(f==null)return [];
  final d=XmlDocument.parse(utf8.decode(f.content as List<int>));
  return _manualDesc(d,'si').map((si)=>_manualDesc(si,'t').map((t)=>t.innerText).join()).toList();
}
String _manualCol(int c) {
  var n=c+1; var out='';
  while(n>0){final r=(n-1)%26;out=String.fromCharCode(65+r)+out;n=(n-1)~/26;}
  return out;
}
String _manualRef(int c,int r)=>_manualCol(c)+(r+1).toString();
Map<int,XmlElement> _manualRows(XmlElement data) {
  final out=<int,XmlElement>{};
  for(final e in data.children.whereType<XmlElement>()){
    if(e.name.local=='row'){final n=int.tryParse(e.getAttribute('r')??'');if(n!=null&&n>0)out[n-1]=e;}
  }
  return out;
}
XmlElement? _manualCell(Map<int,XmlElement> rows,int c,int r) {
  final row=rows[r];if(row==null)return null;
  for(final e in row.children.whereType<XmlElement>()){
    if(e.name.local=='c'&&(e.getAttribute('r')??'').toUpperCase()==_manualRef(c,r))return e;
  }
  return null;
}
dynamic _manualValue(Map<int,XmlElement> rows,int c,int r,List<String> strings) {
  final cell=_manualCell(rows,c,r);if(cell==null)return null;
  final type=cell.getAttribute('t');
  if(type=='inlineStr'){final i=_manualChild(cell,'is');return i==null?null:_manualDesc(i,'t').map((e)=>e.innerText).join();}
  final v=_manualChild(cell,'v');if(v==null||v.innerText.trim().isEmpty)return null;
  final raw=v.innerText.trim();
  if(type=='s'){final i=int.tryParse(raw);return i==null||i<0||i>=strings.length?null:strings[i];}
  if(type=='b')return raw=='1';if(type=='e')return null;
  return num.tryParse(raw)??raw;
}
XmlElement _manualEnsureCell(XmlElement data,Map<int,XmlElement> rows,int c,int r) {
  final old=_manualCell(rows,c,r);if(old!=null)return old;
  var row=rows[r];
  if(row==null){row=XmlElement(XmlName('row'),[XmlAttribute(XmlName('r'),(r+1).toString())]);data.children.add(row);rows[r]=row;}
  final cell=XmlElement(XmlName('c'),[XmlAttribute(XmlName('r'),_manualRef(c,r))]);row.children.add(cell);return cell;
}
void _manualSet(XmlElement data,Map<int,XmlElement> rows,int c,int r,double value) {
  final cell=_manualEnsureCell(data,rows,c,r);
  for(final child in cell.children.toList()){cell.children.remove(child);}
  if(cell.getAttribute('t')!=null)cell.removeAttribute('t');
  final v=value==value.roundToDouble()?value.toInt().toString():value.toString();
  cell.children.add(XmlElement(XmlName('v'),[],[XmlText(v)]));
}
void _manualUpdateSum(Map<int,XmlElement> rows,int base,int r,List<String> strings) {
  final cell=_manualCell(rows,base+4,r);if(cell==null||_manualChild(cell,'f')==null)return;
  var total=0.0;var any=false;
  for(var i=0;i<4;i++){final v=_manualValue(rows,base+i,r,strings);final n=v is num?v:num.tryParse(v?.toString()??'');if(n!=null){total+=n.toDouble();any=true;}}
  if(!any)return;
  final text=total==total.roundToDouble()?total.toInt().toString():total.toString();
  final cached=_manualChild(cell,'v');
  if(cached!=null){cached.children.clear();cached.children.add(XmlText(text));}
  else{cell.children.add(XmlElement(XmlName('v'),[],[XmlText(text)]));}
}
Uint8List _manualRebuild(Archive source,String sheetPath,String sheetXml) {
  final out=Archive();final wanted=_manualZipPath(sheetPath);
  for(final f in source.files){
    if(!f.isFile)continue;final p=_manualZipPath(f.name);if(p=='xl/calcChain.xml')continue;
    if(p==wanted){final b=utf8.encode(sheetXml);out.addFile(ArchiveFile(f.name,b.length,b));continue;}
    if(p=='xl/workbook.xml'){
      var x=utf8.decode(f.content as List<int>);
      if(x.contains('<calcPr')){if(x.contains('fullCalcOnLoad=')){x=x.replaceAll(RegExp(r'fullCalcOnLoad="[^"]*"'),'fullCalcOnLoad="1"');}else{x=x.replaceFirst('<calcPr','<calcPr fullCalcOnLoad="1"');}}
      final b=utf8.encode(x);out.addFile(ArchiveFile(f.name,b.length,b));continue;
    }
    if(p=='[Content_Types].xml'){
      final x=utf8.decode(f.content as List<int>).replaceAll(RegExp(r'<Override[^>]*PartName="/xl/calcChain\.xml"[^>]*/?>'),'');
      final b=utf8.encode(x);out.addFile(ArchiveFile(f.name,b.length,b));continue;
    }
    if(p=='xl/_rels/workbook.xml.rels'){
      final x=utf8.decode(f.content as List<int>).replaceAll(RegExp(r'<Relationship[^>]*Target="calcChain\.xml"[^>]*/?>'),'');
      final b=utf8.encode(x);out.addFile(ArchiveFile(f.name,b.length,b));continue;
    }
    final bytes=f.content as List<int>;out.addFile(ArchiveFile(f.name,bytes.length,bytes));
  }
  final encoded=ZipEncoder().encode(out);if(encoded==null)throw Exception('فشل ترميز ملف Excel.');return Uint8List.fromList(encoded);
}

Map<String, dynamic> _saveManualGradesIsolate(Map<String, dynamic> args) {
  final String filePath=args['filePath'], sheetName=args['sheetName'];
  final int targetRow=args['targetRow'];final String selectedMonth=args['selectedMonth'];
  final double? hw=args['hw'],oral=args['oral'],att=args['att'];
  try {
    final file=File(filePath);if(!file.existsSync())return {'success':false,'message':'ملف Excel غير موجود.'};
    final lower=filePath.toLowerCase();
    if(!lower.endsWith('.xlsx')&&!lower.endsWith('.xlsm'))return {'success':false,'message':'الحفظ الآمن متاح لملفات XLSX وXLSM فقط.'};
    final archive=ZipDecoder().decodeBytes(file.readAsBytesSync());
    final sheetPath=_manualSheetPath(archive,sheetName);
    final sheetFile=archive.findFile(sheetPath);if(sheetFile==null)throw Exception('ورقة العمل غير موجودة داخل الملف.');
    final doc=XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));
    final data=_manualDesc(doc,'sheetData').firstOrNull;if(data==null)throw Exception('بنية ورقة العمل غير مكتملة.');
    final rows=_manualRows(data);final strings=_manualStrings(archive);
    final wanted=selectedMonth.replaceAll(RegExp(r'\s+'),'');
    var targetCol=-1;var c=4;
    while(c<500){
      final value=_manualValue(rows,c,1,strings);final text=value?.toString().trim()??'';
      if(text.isNotEmpty){
        final clean=text.replaceAll(RegExp(r'\s+'),'');
        if(clean==wanted){targetCol=c;break;}
        if(_isMahsala1(clean)||_isFasl1(clean)||_isMahsala2(clean)||_isFasl2(clean)){c++;}else{c+=5;}
      }else{c++;}
    }
    if(targetCol<0)return {'success':false,'message':'تعذر تحديد عمود الشهر.'};
    if(hw!=null)_manualSet(data,rows,targetCol,targetRow,hw);
    if(oral!=null)_manualSet(data,rows,targetCol+1,targetRow,oral);
    if(att!=null)_manualSet(data,rows,targetCol+2,targetRow,att);
    _manualUpdateSum(rows,targetCol,targetRow,strings);
    final bytes=_manualRebuild(archive,sheetPath,doc.toXmlString(pretty:false));
    final check=ZipDecoder().decodeBytes(bytes);
    if(check.findFile(sheetPath)==null||check.findFile('xl/workbook.xml')==null)throw Exception('فشل التحقق من الملف الناتج.');
    final temp=File('$filePath.tmp'),backup=File('$filePath.bak');
    temp.writeAsBytesSync(bytes,flush:true);if(backup.existsSync())backup.deleteSync();
    file.renameSync(backup.path);
    try{temp.renameSync(filePath);if(backup.existsSync())backup.deleteSync();}
    catch(_){if(!file.existsSync()&&backup.existsSync())backup.renameSync(filePath);rethrow;}
    return {'success':true};
  }catch(e){return {'success':false,'message':'خطأ في الحفظ الآمن لملف Excel: $e'};}
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
    // استبدال نسخة العمل عند كل اختيار لتجنب استخدام نسخة قديمة بالاسم نفسه.
    final sourceFile = File(sourceCachePath);
    if (!await sourceFile.exists()) throw Exception('تعذر الوصول إلى الملف المختار.');
    await destination.writeAsBytes(await sourceFile.readAsBytes(), flush: true);
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
        allowedExtensions: ['xlsx', 'xlsm'],
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
    if (_selectedGrade != null) return;
    setState(() {
      _hwController.clear();
      _oralController.clear();
      _attController.clear();
      if (val.trim().isEmpty) {
        _showSuggestions = false;
        _selectedStudentRow = null;
      } else {
        _showSuggestions = true;
        _filteredStudents = _allStudents.where((s) {
          final nameMatch = s['name'].toString().contains(val.trim());
          return nameMatch;
        }).toList();
        _selectedStudentRow = null;
      }
    });
  }

  Future<void> _selectStudent(Map<String, dynamic> student) async {
    final int row = student['row'] as int;
    setState(() {
      _studentNameController.text = student['name'].toString();
      _selectedStudentRow = row;
      _showSuggestions = false;
      _filteredStudents = [];
      _hwController.clear();
      _oralController.clear();
      _attController.clear();
      _isLoading = true;
    });

    try {
      if (_excelFilePath != null &&
          _selectedSheet != null &&
          _selectedMonthOrSubject != null) {
        final result = await compute(_getStudentGradesIsolate, {
          'filePath': _excelFilePath!,
          'sheetName': _selectedSheet!,
          'targetRow': row,
          'selectedMonth': _selectedMonthOrSubject!,
        });
        if (mounted && _selectedStudentRow == row) {
          if (!result.containsKey('error')) {
            setState(() {
              _hwController.text = result['hw']?.toString() ?? '';
              _oralController.text = result['oral']?.toString() ?? '';
              _attController.text = result['att']?.toString() ?? '';
            });
          } else {
            _showSnack('⚠️ ${result['error']}');
          }
        }
      }
    } catch (e) {
      if (mounted) _showSnack('⚠️ تعذر تحميل الدرجات السابقة: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

    Map<String, dynamic>? nextStudent;
    bool completedSequentialEntry = false;
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
        if (_selectedGrade != null) {
          final classStudents = _allStudents
              .where((student) => student['grade'] == _selectedGrade)
              .toList();
          final currentIndex = classStudents.indexWhere(
            (student) => student['row'] == _selectedStudentRow,
          );
          if (currentIndex >= 0 && currentIndex + 1 < classStudents.length) {
            nextStudent = classStudents[currentIndex + 1];
          } else {
            completedSequentialEntry = currentIndex >= 0;
          }
        }

        setState(() {
          _hwController.clear();
          _oralController.clear();
          _attController.clear();
          if (nextStudent == null) {
            _studentNameController.clear();
            _selectedStudentRow = null;
            _showSuggestions = false;
          }
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

    if (!mounted) return;
    if (nextStudent != null) {
      await _selectStudent(nextStudent!);
    } else if (completedSequentialEntry) {
      _showSnack('🎉 اكتمل إدخال درجات جميع طلاب الصف $_selectedGrade');
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
        title: const Text('إدخال درجات تحريري_شفهي_مواظبة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        backgroundColor: const Color(0xFF00897B),
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
                  type: _excelFilePath!.toLowerCase().endsWith('.xlsm')
                      ? 'application/vnd.ms-excel.sheet.macroEnabled.12'
                      : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                );
                if (result.type != ResultType.done) {
                  _showSnack('تعذر فتح الملف: ${result.message}');
                }
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
                  onChanged: (_excelLoaded && !_isLoading)
                      ? (v) async {
                          setState(() => _selectedMonthOrSubject = v);
                          if (v != null && _selectedStudentRow != null) {
                            final student = _allStudents.firstWhere(
                              (s) => s['row'] == _selectedStudentRow,
                              orElse: () => <String, dynamic>{},
                            );
                            if (student.isNotEmpty) await _selectStudent(student);
                          }
                        }
                      : null,
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
                  items: _excelLoaded
                      ? [
                          const DropdownMenuItem<String>(
                            value: '',
                            child: Text('بدون تحديد الصف - البحث اليدوي'),
                          ),
                          ..._gradesList.map((g) => DropdownMenuItem(
                                value: g,
                                child: Text(g, style: const TextStyle(fontWeight: FontWeight.bold)),
                              )),
                        ]
                      : null,
                  onChanged: (_excelLoaded && !_isLoading)
                      ? (v) async {
                          final grade = (v == null || v.isEmpty) ? null : v;
                          setState(() {
                            _selectedGrade = grade;
                            _studentNameController.clear();
                            _selectedStudentRow = null;
                            _showSuggestions = false;
                            _filteredStudents = [];
                            _hwController.clear();
                            _oralController.clear();
                            _attController.clear();
                          });
                          if (grade != null) {
                            final classStudents = _allStudents
                                .where((student) => student['grade'] == grade)
                                .toList();
                            if (classStudents.isNotEmpty) {
                              await _selectStudent(classStudents.first);
                            } else {
                              _showSnack('لا يوجد طلاب مسجلون في الصف المحدد.');
                            }
                          }
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
              readOnly: _selectedGrade != null,
              onChanged: _selectedGrade == null ? _onNameChanged : null,
              decoration: InputDecoration(
                hintText: _selectedGrade != null
                    ? 'يظهر اسم الطالب التالي تلقائياً بعد الحفظ'
                    : 'اكتب اسم الطالب...',
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
                      onTap: () => _selectStudent(s),
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

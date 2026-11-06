import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart'; // ✅ العودة إلى excel
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart'; // ✅ لفتح الملف بصلاحيات الكتابة

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

// ... (باقي كود الواجهة كما هو، مع إضافة زر open_filex في AppBar)

class GradeScannerScreen extends StatefulWidget {
  final bool isOmrMode;
  const GradeScannerScreen({super.key, this.isOmrMode = false});

  @override
  State<GradeScannerScreen> createState() => _GradeScannerScreenState();
}

class _GradeScannerScreenState extends State<GradeScannerScreen> {
  // ... (نفس المتغيرات السابقة)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ...
      appBar: AppBar(
        title: const Text('إدخال الدرجات من أوراق الإجابة', ...),
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
                  writePermission: true, // ✅ يمنح صلاحية الحفظ المباشر
                );
                if (result.type != ResultType.done) {
                  _showSnack('تعذر فتح الملف: ${result.message}');
                }
              },
            ),
          IconButton(
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off, color: Colors.white),
            // ...
          ),
        ],
      ),
      // ... (باقي الواجهة كما هي)
    );
  }
}

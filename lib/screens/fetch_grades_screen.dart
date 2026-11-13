import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

// ═══════════════════════════════════════════════════════════
// أدوات توحيد النصوص والأرقام قبل المطابقة
// ═══════════════════════════════════════════════════════════

String _normalizeArabicText(dynamic value) {
  if (value == null) return '';

  return value
      .toString()
      .trim()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'\s+'), '');
}

String _normalizeHeader(dynamic value) {
  if (value == null) return '';

  return value
      .toString()
      .trim()
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('۳', '3')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4');
}

String _normalizeSeat(dynamic value) {
  if (value == null) return '';

  String text = value
      .toString()
      .trim()
      .replaceAll(',', '')
      .replaceAll('٠', '0')
      .replaceAll('١', '1')
      .replaceAll('٢', '2')
      .replaceAll('٣', '3')
      .replaceAll('٤', '4')
      .replaceAll('٥', '5')
      .replaceAll('٦', '6')
      .replaceAll('٧', '7')
      .replaceAll('٨', '8')
      .replaceAll('٩', '9');

  final numeric = num.tryParse(text);

  if (numeric != null && numeric == numeric.roundToDouble()) {
    return numeric.toInt().toString();
  }

  return text;
}

// ═══════════════════════════════════════════════════════════
// أدوات التعامل مع بنية XLSX الداخلية بأمان
// ═══════════════════════════════════════════════════════════

const String _relationshipNamespace =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

String _normalizeZipPath(String path) {
  final parts = <String>[];

  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;

    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }

  return parts.join('/');
}

String _resolveWorksheetPath(String target) {
  if (target.startsWith('/')) {
    return _normalizeZipPath(target);
  }

  return _normalizeZipPath('xl/$target');
}

String _readRawXmlString(Archive archive, String path) {
  final normalized = _normalizeZipPath(path);
  for (final file in archive.files) {
    if (file.isFile && _normalizeZipPath(file.name) == normalized) {
      final content = file.content;
      if (content is List<int>) {
        return utf8.decode(content);
      }
    }
  }
  throw Exception('تعذر العثور على مكون Excel الداخلي: $path');
}

XmlDocument _readXml(Archive archive, String path) {
  return XmlDocument.parse(_readRawXmlString(archive, path));
}

XmlElement? _firstElement(XmlNode parent, String localName) {
  for (final child in parent.children) {
    if (child is XmlElement && child.name.local == localName) {
      return child;
    }
  }
  return null;
}

List<XmlElement> _elements(XmlNode parent, String localName) {
  return parent.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == localName)
      .toList();
}

String? _attribute(XmlElement element, String name) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == name) {
      return attribute.value;
    }
  }
  return null;
}

String? _relationshipId(XmlElement element) {
  for (final attribute in element.attributes) {
    if (attribute.name.local == 'id' &&
        attribute.name.namespaceUri == _relationshipNamespace) {
      return attribute.value;
    }
  }

  for (final attribute in element.attributes) {
    if (attribute.name.local == 'id') {
      return attribute.value;
    }
  }

  return null;
}

String _getWorksheetPath(Archive archive, String sheetName) {
  final workbook = _readXml(archive, 'xl/workbook.xml');
  final relationships = _readXml(archive, 'xl/_rels/workbook.xml.rels');

  final sheets = _elements(workbook, 'sheet');
  final targetNormalized = _normalizeArabicText(sheetName);

  XmlElement? selectedSheet;

  // 1. مطابقة حرفية أولاً
  for (final sheet in sheets) {
    final name = _attribute(sheet, 'name');
    if (name != null && name.trim() == sheetName.trim()) {
      selectedSheet = sheet;
      break;
    }
  }

  // 2. مطابقة موحدة للنص العربي (لتجاوز المسافات أو الهمزات)
  if (selectedSheet == null) {
    for (final sheet in sheets) {
      final name = _attribute(sheet, 'name');
      if (name != null && _normalizeArabicText(name) == targetNormalized) {
        selectedSheet = sheet;
        break;
      }
    }
  }

  if (selectedSheet == null) {
    throw Exception('لم يتم العثور على ورقة العمل ($sheetName) في ملف أعمال السنة.');
  }

  final relationId = _relationshipId(selectedSheet);

  if (relationId == null) {
    throw Exception('تعذر تحديد مسار ورقة العمل ($sheetName).');
  }

  final relations = _elements(relationships, 'Relationship');

  for (final relation in relations) {
    if (_attribute(relation, 'Id') == relationId) {
      final target = _attribute(relation, 'Target');
      if (target == null) break;
      return _resolveWorksheetPath(target);
    }
  }

  throw Exception('تعذر ربط ورقة العمل ($sheetName) بملفها الداخلي.');
}

// ═══════════════════════════════════════════════════════════
// قراءة النصوص المشتركة في XLSX
// ═══════════════════════════════════════════════════════════

List<String> _readSharedStrings(Archive archive) {
  try {
    final document = _readXml(archive, 'xl/sharedStrings.xml');
    final result = <String>[];

    for (final item in _elements(document, 'si')) {
      final buffer = StringBuffer();
      for (final textElement in _elements(item, 't')) {
        buffer.write(textElement.innerText);
      }
      result.add(buffer.toString());
    }

    return result;
  } catch (_) {
    return [];
  }
}

// ═══════════════════════════════════════════════════════════
// تحويل مرجع الخلية مثل A1 أو AB25 إلى رقم العمود والصف
// ═══════════════════════════════════════════════════════════

String _columnLetters(int column) {
  int number = column + 1;
  String result = '';

  while (number > 0) {
    final remainder = (number - 1) % 26;
    result = String.fromCharCode(65 + remainder) + result;
    number = (number - 1) ~/ 26;
  }

  return result;
}

String _cellReference(int column, int row) {
  return '${_columnLetters(column)}${row + 1}';
}

// ═══════════════════════════════════════════════════════════
// قراءة قيمة الخلية، بما في ذلك نتيجة المعادلة المحفوظة
// ═══════════════════════════════════════════════════════════

dynamic _readCellValue(
  XmlElement? cell,
  List<String> sharedStrings,
) {
  if (cell == null) return null;

  final type = _attribute(cell, 't');

  if (type == 'inlineStr') {
    final inline = _firstElement(cell, 'is');
    if (inline == null) return null;

    final buffer = StringBuffer();
    for (final textElement in _elements(inline, 't')) {
      buffer.write(textElement.innerText);
    }
    return buffer.toString();
  }

  final valueElement = _firstElement(cell, 'v');
  if (valueElement == null) return null;

  final raw = valueElement.innerText.trim();
  if (raw.isEmpty) return null;

  if (type == 's') {
    final index = int.tryParse(raw);
    if (index == null || index < 0 || index >= sharedStrings.length) {
      return null;
    }
    return sharedStrings[index];
  }

  if (type == 'b') {
    return raw == '1';
  }

  if (type == 'str') {
    final number = num.tryParse(raw);
    return number ?? raw;
  }

  if (type == 'e') {
    return null;
  }

  final number = num.tryParse(raw);
  return number ?? raw;
}

// ═══════════════════════════════════════════════════════════
// تجهيز صفوف وخلايا ورقة العمل
// ═══════════════════════════════════════════════════════════

XmlElement _getSheetData(XmlDocument document) {
  final sheetData = _elements(document, 'sheetData').firstOrNull;
  if (sheetData == null) {
    throw Exception('بنية ورقة العمل غير مكتملة: sheetData.');
  }
  return sheetData;
}

Map<int, XmlElement> _getRows(XmlElement sheetData) {
  final rows = <int, XmlElement>{};

  for (final row in sheetData.children.whereType<XmlElement>()) {
    if (row.name.local != 'row') continue;

    final rowNumber = int.tryParse(_attribute(row, 'r') ?? '');
    if (rowNumber != null && rowNumber > 0) {
      rows[rowNumber - 1] = row;
    }
  }

  return rows;
}

Map<String, XmlElement> _getCells(XmlElement row) {
  final cells = <String, XmlElement>{};

  for (final cell in row.children.whereType<XmlElement>()) {
    if (cell.name.local != 'c') continue;

    final reference = _attribute(cell, 'r');
    if (reference != null) {
      cells[reference.toUpperCase()] = cell;
    }
  }

  return cells;
}

XmlElement? _findCell(
  Map<int, XmlElement> rows,
  int column,
  int rowIndex,
) {
  final row = rows[rowIndex];
  if (row == null) return null;

  final cells = _getCells(row);
  return cells[_cellReference(column, rowIndex).toUpperCase()];
}

dynamic _getValueAt(
  Map<int, XmlElement> rows,
  int column,
  int rowIndex,
  List<String> sharedStrings,
) {
  return _readCellValue(
    _findCell(rows, column, rowIndex),
    sharedStrings,
  );
}

// ═══════════════════════════════════════════════════════════
// استخراج المحصلة الصالحة (من 0 إلى 20) مع الاحتساب الاحتياطي
// ═══════════════════════════════════════════════════════════

num? _extractValidMahsalaScore(
  Map<int, XmlElement> sourceRows,
  int sourceGradeCol,
  int rowIndex,
  List<String> sourceSharedStrings,
) {
  // 1. القراءة المباشرة للقيمة المحسوبة المخزنة في خلية المحصلة (Y أو AU)
  final directVal = _getValueAt(
    sourceRows,
    sourceGradeCol,
    rowIndex,
    sourceSharedStrings,
  );

  if (directVal != null) {
    final parsed = directVal is num
        ? directVal
        : num.tryParse(directVal.toString().trim());
    if (parsed != null && parsed >= 0 && parsed <= 20) {
      return parsed;
    }
  }

  // 2. احتساب احتياطي مطابق لمعادلة ملف أعمال السنة إذا كان الملف محفوظاً من الجوال بدون كاش <v>
  final monthsCountVal = _getValueAt(
    sourceRows,
    sourceGradeCol,
    2,
    sourceSharedStrings,
  );

  final int? monthsCount = monthsCountVal is num
      ? monthsCountVal.toInt()
      : int.tryParse(monthsCountVal?.toString().trim() ?? '');

  if (monthsCount == null || monthsCount < 1 || monthsCount > 4) {
    return null;
  }

  final monthTotalCols = [
    sourceGradeCol - 16,
    sourceGradeCol - 11,
    sourceGradeCol - 6,
    sourceGradeCol - 1,
  ];

  double sumMonths = 0;

  for (int m = 0; m < monthsCount; m++) {
    final totalCol = monthTotalCols[m];
    if (totalCol < 4) return null;

    final monthTotalVal = _getValueAt(
      sourceRows,
      totalCol,
      rowIndex,
      sourceSharedStrings,
    );

    num? mScore = monthTotalVal is num
        ? monthTotalVal
        : num.tryParse(monthTotalVal?.toString().trim() ?? '');

    if (mScore == null) {
      bool hasAnyComponent = false;
      double compSum = 0;
      for (int offset = 4; offset >= 1; offset--) {
        final compVal = _getValueAt(
          sourceRows,
          totalCol - offset,
          rowIndex,
          sourceSharedStrings,
        );
        final compNum = compVal is num
            ? compVal
            : num.tryParse(compVal?.toString().trim() ?? '');
        if (compNum != null) {
          hasAnyComponent = true;
          compSum += compNum.toDouble();
        }
      }
      if (!hasAnyComponent) {
        return null;
      }
      mScore = compSum;
    }

    sumMonths += mScore.toDouble();
  }

  final result = (sumMonths / (5.0 * monthsCount)).ceil();
  if (result >= 0 && result <= 20) {
    return result;
  }

  return null;
}

// ═══════════════════════════════════════════════════════════
// تعديل الخلايا المستهدفة في نص XML الأصلي مباشرة (لصق قيم)
// دون المساس ببنية الورقة أو التنسيقات أو المعادلات
// ═══════════════════════════════════════════════════════════

String _patchSheetXmlInPlace(
  String rawSheetXml,
  Map<String, String> cellUpdates, // مرجع الخلية (مثل E6) ← القيمة الرقمية
) {
  if (cellUpdates.isEmpty) return rawSheetXml;

  // تعديل جميع الخلايا الموجودة مسبقاً في XML دفعة واحدة وبمرور واحد سريع
  final cellPattern = RegExp(
    r'<c\b([^>]*\br="([A-Z]+\d+)"[^>]*)/>|<c\b([^>]*\br="([A-Z]+\d+)"[^>]*)>.*?</c>',
    dotAll: true,
  );

  final remainingUpdates = Map<String, String>.from(cellUpdates);

  String patchedXml = rawSheetXml.replaceAllMapped(cellPattern, (match) {
    final attrs = match.group(1) ?? match.group(3) ?? '';
    final ref = (match.group(2) ?? match.group(4) ?? '').toUpperCase();

    if (!remainingUpdates.containsKey(ref)) {
      return match.group(0)!;
    }

    final valStr = remainingUpdates.remove(ref)!;
    // الإبقاء على التنسيق s="..." وإزالة نوع النص t="..." إن وجد
    final cleanAttrs = attrs.replaceAll(RegExp(r'\s*\bt="[^"]*"'), '');
    return '<c$cleanAttrs><v>$valStr</v></c>';
  });

  // في حال وجود أي خلية لم تكن موجودة مسبقاً داخل صفها، ندرجها في صفها
  if (remainingUpdates.isNotEmpty) {
    for (final entry in remainingUpdates.entries) {
      final ref = entry.key;
      final valStr = entry.value;
      final rowMatch = RegExp(r'(\d+)$').firstMatch(ref);
      if (rowMatch == null) continue;
      final rowNum = rowMatch.group(1)!;

      final rowEndPattern = RegExp(
        r'(<row\b[^>]*\br="' + rowNum + r'"[^>]*>.*?)(</row>)',
        dotAll: true,
      );

      if (rowEndPattern.hasMatch(patchedXml)) {
        patchedXml = patchedXml.replaceFirstMapped(rowEndPattern, (m) {
          return '${m.group(1)}<c r="$ref"><v>$valStr</v></c>${m.group(2)}';
        });
      }
    }
  }

  return patchedXml;
}

// ═══════════════════════════════════════════════════════════
// إعادة بناء أرشيف XLSX بشكل نظيف يمنع رسالة الاسترداد والقراءة فقط
// ═══════════════════════════════════════════════════════════

Uint8List _rebuildCleanXlsxArchive(
  Archive originalArchive,
  String updatedSheetPath,
  String updatedSheetXmlString,
) {
  final cleanArchive = Archive();
  final normalizedUpdatedPath = _normalizeZipPath(updatedSheetPath);

  for (final file in originalArchive.files) {
    if (!file.isFile) continue;

    final entryPath = _normalizeZipPath(file.name);

    // حذف calcChain.xml لكي يعيد Excel حساب مجاميع الدرجات تلقائياً بدون تعارض
    if (entryPath == 'xl/calcChain.xml') {
      continue;
    }

    if (entryPath == normalizedUpdatedPath) {
      final bytes = utf8.encode(updatedSheetXmlString);
      cleanArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      continue;
    }

    if (entryPath == '[Content_Types].xml') {
      final rawXml = utf8.decode(file.content as List<int>);
      final cleanedContentTypes = rawXml.replaceAll(
        RegExp(r'<Override[^>]*PartName="/xl/calcChain\.xml"[^>]*/?>'),
        '',
      );
      final bytes = utf8.encode(cleanedContentTypes);
      cleanArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      continue;
    }

    if (entryPath == 'xl/_rels/workbook.xml.rels') {
      final rawXml = utf8.decode(file.content as List<int>);
      final cleanedRels = rawXml.replaceAll(
        RegExp(r'<Relationship[^>]*Target="calcChain\.xml"[^>]*/?>'),
        '',
      );
      final bytes = utf8.encode(cleanedRels);
      cleanArchive.addFile(ArchiveFile(file.name, bytes.length, bytes));
      continue;
    }

    final rawContent = file.content as List<int>;
    cleanArchive.addFile(ArchiveFile(file.name, rawContent.length, rawContent));
  }

  final encoded = ZipEncoder().encode(cleanArchive);
  if (encoded == null) {
    throw Exception('فشل ضغط ملف الأتمتة المحدث.');
  }

  return Uint8List.fromList(encoded);
}

// ═══════════════════════════════════════════════════════════
// جلب الدرجات في معالج منفصل (قراءة فقط للمصدر، لصق قيم للهدف)
// ═══════════════════════════════════════════════════════════

Map<String, dynamic> _fetchGradesIsolate(Map<String, dynamic> args) {
  final String targetPath = args['targetPath'];
  final String sourcePath = args['sourcePath'];
  final String subjectName = args['subjectName'].toString().trim();
  final String mahsalaType = args['mahsalaType'].toString().trim();

  try {
    final targetFile = File(targetPath);
    final sourceFile = File(sourcePath);

    if (!targetFile.existsSync() || !sourceFile.existsSync()) {
      return {
        'success': false,
        'message': 'تعذر العثور على أحد الملفين في مسار التخزين.',
      };
    }

    if (!targetPath.toLowerCase().endsWith('.xlsx') ||
        !sourcePath.toLowerCase().endsWith('.xlsx')) {
      return {
        'success': false,
        'message': 'يجب أن يكون الملفان بصيغة XLSX.',
      };
    }

    // 1. قراءة ملف أعمال السنة في الذاكرة فقط (Read-Only) دون لمس الملف الأصلي
    final sourceBytes = sourceFile.readAsBytesSync();
    final targetBytes = targetFile.readAsBytesSync();

    final sourceArchive = ZipDecoder().decodeBytes(sourceBytes);
    final targetArchive = ZipDecoder().decodeBytes(targetBytes);

    final targetSheetPath = _getWorksheetPath(targetArchive, 'statment');
    final sourceSheetPath = _getWorksheetPath(sourceArchive, subjectName);

    final rawTargetSheetXml = _readRawXmlString(targetArchive, targetSheetPath);
    final targetDocument = XmlDocument.parse(rawTargetSheetXml);
    final sourceDocument = _readXml(sourceArchive, sourceSheetPath);

    final targetSharedStrings = _readSharedStrings(targetArchive);
    final sourceSharedStrings = _readSharedStrings(sourceArchive);

    final targetSheetData = _getSheetData(targetDocument);
    final sourceSheetData = _getSheetData(sourceDocument);

    final targetRows = _getRows(targetSheetData);
    final sourceRows = _getRows(sourceSheetData);

    final targetMaxRow =
        targetRows.keys.isEmpty ? 0 : targetRows.keys.reduce(math.max);

    final sourceMaxRow =
        sourceRows.keys.isEmpty ? 0 : sourceRows.keys.reduce(math.max);

    // 2. البحث عن المادة في الصف الثالث (index 2) من ملف الأتمتة بمطابقة عربية مرنة
    final normalizedSubject = _normalizeArabicText(subjectName);
    int targetBaseCol = -1;

    for (int c = 4; c < 500; c++) {
      final value = _getValueAt(
        targetRows,
        c,
        2,
        targetSharedStrings,
      );

      if (value != null &&
          _normalizeArabicText(value.toString()) == normalizedSubject) {
        targetBaseCol = c;
        break;
      }
    }

    if (targetBaseCol == -1) {
      return {
        'success': false,
        'message':
            'لم يتم العثور على المادة ($subjectName) في الصف الثالث من ورقة statment.',
      };
    }

    final int targetGradeCol =
        _normalizeHeader(mahsalaType) == 'م1' ? targetBaseCol : targetBaseCol + 2;

    final targetSubHeader = _getValueAt(
      targetRows,
      targetGradeCol,
      4,
      targetSharedStrings,
    );

    if (_normalizeHeader(targetSubHeader) != _normalizeHeader(mahsalaType)) {
      return {
        'success': false,
        'message':
            'ترتيب أعمدة المادة في ملف الأتمتة لا يطابق المتوقع: لم يتم العثور على $mahsalaType في موضع اللصق.',
      };
    }

    // 3. البحث عن عمود م١ أو م٢ في الصف الثاني (index 1) من ورقة المصدر
    final String wantedHeader = _normalizeHeader(mahsalaType);
    int sourceGradeCol = -1;

    for (int c = 4; c < 500; c++) {
      final value = _getValueAt(
        sourceRows,
        c,
        1,
        sourceSharedStrings,
      );

      if (_normalizeHeader(value) == wantedHeader) {
        sourceGradeCol = c;
        break;
      }
    }

    if (sourceGradeCol == -1) {
      return {
        'success': false,
        'message':
            'لم يتم العثور على عنوان $mahsalaType في الصف الثاني بدءاً من العمود E بورقة ($subjectName).',
      };
    }

    // 4. مسح جميع صفوف ورقة أعمال السنة (شبيه VLOOKUP) والتقاط كل صف به محصلة صالحة (0 إلى 20)
    final Map<String, num> gradesMap = {};
    int? firstFoundStudentRow;

    for (int r = 3; r <= sourceMaxRow; r++) {
      final seatValue = _getValueAt(
        sourceRows,
        0,
        r,
        sourceSharedStrings,
      );

      final seat = _normalizeSeat(seatValue);
      if (seat.isEmpty) continue;

      final validScore = _extractValidMahsalaScore(
        sourceRows,
        sourceGradeCol,
        r,
        sourceSharedStrings,
      );

      if (validScore == null) continue;

      firstFoundStudentRow ??= (r + 1);
      gradesMap[seat] = validScore;
    }

    if (gradesMap.isEmpty) {
      return {
        'success': true,
        'count': 0,
        'unmatched': 0,
        'message':
            'لم توجد أي محصلات رقمية مرصودة (من 0 إلى 20) في ورقة ($subjectName) لـ ($mahsalaType).',
      };
    }

    // 5. تجهيز قاموس التحديثات للخلايا المطابقة في ملف الأتمتة بدلالة رقم الجلوس
    final Map<String, String> cellUpdates = {};
    int unmatchedCount = 0;

    for (int r = 5; r <= targetMaxRow; r++) {
      final seatValue = _getValueAt(
        targetRows,
        0,
        r,
        targetSharedStrings,
      );

      final seat = _normalizeSeat(seatValue);
      if (seat.isEmpty) continue;

      if (gradesMap.containsKey(seat)) {
        final grade = gradesMap[seat]!;
        final formattedValue = grade == grade.roundToDouble()
            ? grade.toInt().toString()
            : grade.toString();

        final ref = _cellReference(targetGradeCol, r).toUpperCase();
        cellUpdates[ref] = formattedValue;
      } else {
        unmatchedCount++;
      }
    }

    if (cellUpdates.isEmpty) {
      return {
        'success': true,
        'count': 0,
        'unmatched': unmatchedCount,
        'message':
            'تم العثور على (${gradesMap.length}) محصلة في أعمال السنة، لكن أرقام القيد لم تتطابق مع ملف الأتمتة.',
      };
    }

    // 6. تعديل الخلايا المستهدفة موضعياً في نص XML الأصلي دون تغيير بقية الورقة
    final patchedSheetXml = _patchSheetXmlInPlace(
      rawTargetSheetXml,
      cellUpdates,
    );

    final finalXlsxBytes = _rebuildCleanXlsxArchive(
      targetArchive,
      targetSheetPath,
      patchedSheetXml,
    );

    // 7. الكتابة الذرية (Atomic Write) في ملف الأتمتة فقط
    final tempOutput = File('$targetPath.tmp');
    tempOutput.writeAsBytesSync(finalXlsxBytes, flush: true);
    if (targetFile.existsSync()) {
      targetFile.deleteSync();
    }
    tempOutput.renameSync(targetPath);

    // 8. تحقق فوري بعد الحفظ (Post-Write Verification) من الملف الموجود على القرص
    final verifyArchive = ZipDecoder().decodeBytes(
      File(targetPath).readAsBytesSync(),
    );
    final verifyDoc = _readXml(verifyArchive, targetSheetPath);
    final verifyRows = _getRows(_getSheetData(verifyDoc));
    final verifyShared = _readSharedStrings(verifyArchive);

    int verifiedWrittenCount = 0;
    for (int r = 5; r <= targetMaxRow; r++) {
      final ref = _cellReference(targetGradeCol, r).toUpperCase();
      if (cellUpdates.containsKey(ref)) {
        final writtenVal = _getValueAt(
          verifyRows,
          targetGradeCol,
          r,
          verifyShared,
        );
        if (writtenVal != null && writtenVal.toString().trim().isNotEmpty) {
          verifiedWrittenCount++;
        }
      }
    }

    return {
      'success': true,
      'count': verifiedWrittenCount,
      'unmatched': unmatchedCount,
      'firstRow': firstFoundStudentRow,
      'targetColumnLetter': _columnLetters(targetGradeCol),
      'savedPath': targetPath,
    };
  } catch (e) {
    return {
      'success': false,
      'message': 'خطأ تقني أثناء جلب الدرجات: $e',
    };
  }
}

// ═══════════════════════════════════════════════════════════
// واجهة الشاشة
// ═══════════════════════════════════════════════════════════

class FetchGradesScreen extends StatefulWidget {
  const FetchGradesScreen({super.key});

  @override
  State<FetchGradesScreen> createState() => _FetchGradesScreenState();
}

class _FetchGradesScreenState extends State<FetchGradesScreen> {
  String? _targetPath;
  String? _targetName;

  String? _sourcePath;
  String? _sourceName;

  List<String> _subjects = [];
  String? _selectedSubject;
  String _selectedMahsala = 'م١';

  String? _lastOperationSummary;
  bool _isLoading = false;

  // ═════════════════════════════════════════════════════════
  // تحديد مجلد العمل لملف الأتمتة
  // ═════════════════════════════════════════════════════════

  Future<Directory> _getGradesDirectory() async {
    final externalDir = await getExternalStorageDirectory();

    if (externalDir == null) {
      throw Exception('تعذر الوصول إلى التخزين الداخلي.');
    }

    final paths = externalDir.path.split('/');
    final baseParts = <String>[];

    for (final part in paths) {
      if (part == 'Android') break;
      if (part.isNotEmpty) baseParts.add(part);
    }

    final basePath = '/${baseParts.join('/')}';

    final targetDir = Directory(
      '$basePath/Download/درجات الطلاب',
    );

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    return targetDir;
  }

  // ═════════════════════════════════════════════════════════
  // نسخ ملف الأتمتة إلى مجلد العمل مع حماية التعديلات السابقة
  // ═════════════════════════════════════════════════════════

  Future<String> _prepareTargetWorkingCopy(
    String pickedPath,
    String originalName,
  ) async {
    final targetDir = await _getGradesDirectory();
    final destination = File('${targetDir.path}/$originalName');

    // إذا كان الملف المختار هو نفسه الموجود في مجلد العمل، نستخدمه مباشرة
    if (File(pickedPath).parent.path == targetDir.path) {
      return pickedPath;
    }

    // نسخ الملف المختار إلى مجلد العمل الدائم
    await destination.writeAsBytes(
      await File(pickedPath).readAsBytes(),
      flush: true,
    );

    return destination.path;
  }

  // ═════════════════════════════════════════════════════════
  // اختيار ملف الأتمتة والتحقق من هويته واستخراج المواد
  // ═════════════════════════════════════════════════════════

  Future<void> _pickTargetFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result == null || result.files.single.path == null) return;

    setState(() => _isLoading = true);

    try {
      final pickedPath = result.files.single.path!;
      final fileName = result.files.single.name;

      final checkArchive = ZipDecoder().decodeBytes(
        await File(pickedPath).readAsBytes(),
      );

      final String sheetPath;
      try {
        sheetPath = _getWorksheetPath(checkArchive, 'statment');
      } catch (_) {
        throw Exception(
          'الملف المختار ($fileName) ليس ملف أتمتة صالحاً (لا يحتوي على ورقة statment). '
          'تأكد من عدم اختيار ملف أعمال السنة في هذه الخانة.',
        );
      }

      final document = _readXml(checkArchive, sheetPath);
      final sharedStrings = _readSharedStrings(checkArchive);
      final sheetData = _getSheetData(document);
      final rows = _getRows(sheetData);

      final List<String> tempSubjects = [];

      for (int c = 4; c < 500; c += 5) {
        final value = _getValueAt(
          rows,
          c,
          2,
          sharedStrings,
        );

        if (value != null &&
            value.toString().trim().isNotEmpty &&
            !value.toString().contains('المجموع')) {
          tempSubjects.add(value.toString().trim());
        }
      }

      if (tempSubjects.isEmpty) {
        throw Exception('لم يتم العثور على مواد دراسية في الصف الثالث من ملف الأتمتة.');
      }

      final permanentPath = await _prepareTargetWorkingCopy(
        pickedPath,
        fileName,
      );

      if (!mounted) return;

      setState(() {
        _targetPath = permanentPath;
        _targetName = fileName;
        _subjects = tempSubjects;
        _selectedSubject = _subjects.isNotEmpty ? _subjects.first : null;
        _lastOperationSummary = 'مسار حفظ ملف الأتمتة المحدث:\n$permanentPath';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحميل ملف الأتمتة (${tempSubjects.length} مادة) بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ═════════════════════════════════════════════════════════
  // اختيار ملف أعمال السنة (قراءة فقط - دون أي نسخ أو تعديل)
  // ═════════════════════════════════════════════════════════

  Future<void> _pickSourceFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result == null || result.files.single.path == null) return;

    setState(() => _isLoading = true);

    try {
      final pickedPath = result.files.single.path!;
      final fileName = result.files.single.name;

      final checkArchive = ZipDecoder().decodeBytes(
        await File(pickedPath).readAsBytes(),
      );

      final workbook = _readXml(checkArchive, 'xl/workbook.xml');
      final sheets = _elements(workbook, 'sheet');
      final sheetNames = sheets
          .map((s) => _attribute(s, 'name') ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      if (sheetNames.length == 1 &&
          _normalizeArabicText(sheetNames.first) == 'statment') {
        throw Exception(
          'الملف المختار ($fileName) هو ملف الأتمتة وليس ملف أعمال السنة!',
        );
      }

      if (!mounted) return;

      setState(() {
        _sourcePath = pickedPath;
        _sourceName = fileName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم ربط ملف أعمال السنة للقراءة فقط (${sheetNames.length} أوراق مواد)',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ═════════════════════════════════════════════════════════
  // تنفيذ جلب الدرجات
  // ═════════════════════════════════════════════════════════

  Future<void> _executeFetch() async {
    if (_targetPath == null ||
        _sourcePath == null ||
        _selectedSubject == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يرجى اختيار كلا الملفين والمادة أولاً',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_targetPath == _sourcePath) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب اختيار ملفين مختلفين للمصدر والهدف.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await compute(
        _fetchGradesIsolate,
        {
          'targetPath': _targetPath,
          'sourcePath': _sourcePath,
          'subjectName': _selectedSubject,
          'mahsalaType': _selectedMahsala,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final count = result['count'] ?? 0;

        if (count == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ ${result['message']}'),
              backgroundColor: Colors.orange.shade800,
              duration: const Duration(seconds: 6),
            ),
          );
        } else {
          final firstRow = result['firstRow'] ?? '-';
          final colLetter = result['targetColumnLetter'] ?? '';
          final savedPath = result['savedPath'] ?? _targetPath;

          setState(() {
            _lastOperationSummary =
                '✅ تم التحقق من حفظ ($count) محصلة لمادة ($_selectedSubject - $_selectedMahsala) '
                'في العمود ($colLetter).\n'
                'أول صف مرصود في المصدر: صف ($firstRow)\n'
                'افتح الملف من هذا المسار:\n$savedPath';
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ تم لصق والتحقق من ($count) محصلة لمادة ($_selectedSubject - $_selectedMahsala) في العمود ($colLetter).',
              ),
              backgroundColor: Colors.green.shade800,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${result['message']}'),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ أثناء المعالجة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ═════════════════════════════════════════════════════════
  // بناء الشاشة
  // ═════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F8E9),
      appBar: AppBar(
        title: const Text(
          'جلب درجات المحصلات',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF1B5E20),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. ملف الأتمتة (الهدف)
            _buildCard(
              title: '1. ملف الأتمتة (الذي ستُكتب فيه الدرجات)',
              icon: Icons.file_copy_outlined,
              color: Colors.blueAccent,
              fileName: _targetName ?? 'لم يتم اختيار ملف',
              onPressed: _isLoading ? null : _pickTargetFile,
            ),

            const SizedBox(height: 16),

            // 2. ملف أعمال السنة (المصدر - قراءة فقط)
            _buildCard(
              title: '2. ملف أعمال السنة (مصدر للقراءة فقط)',
              icon: Icons.file_open_outlined,
              color: Colors.orangeAccent,
              fileName: _sourceName ?? 'لم يتم اختيار ملف',
              onPressed: _isLoading ? null : _pickSourceFile,
            ),

            const SizedBox(height: 24),

            // 3. اختيار المادة
            const Text(
              '3. المادة (ورقة العمل):',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSubject,
                  isExpanded: true,
                  hint: Text(
                    _targetPath == null
                        ? 'يرجى اختيار ملف الأتمتة أولاً'
                        : 'اختر المادة',
                  ),
                  items: _subjects
                      .map(
                        (subject) => DropdownMenuItem(
                          value: subject,
                          child: Text(
                            subject,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _targetPath == null
                      ? null
                      : (value) {
                          setState(() => _selectedSubject = value);
                        },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 4. اختيار المحصلة
            const Text(
              '4. المحصلة المطلوب جلبها:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text(
                      'محصلة م١',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    value: 'م١',
                    groupValue: _selectedMahsala,
                    activeColor: const Color(0xFF1B5E20),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedMahsala = value);
                      }
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text(
                      'محصلة م٢',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    value: 'م٢',
                    groupValue: _selectedMahsala,
                    activeColor: const Color(0xFF1B5E20),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedMahsala = value);
                      }
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // 5. زر التنفيذ
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B5E20),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.download_done,
                      color: Colors.white,
                    ),
              label: Text(
                _isLoading
                    ? 'جاري المعالجة...'
                    : 'جلب الدرجات ونسخها الآن',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              onPressed: _isLoading ? null : _executeFetch,
            ),

            if (_lastOperationSummary != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade400),
                ),
                child: SelectableText(
                  _lastOperationSummary!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ═════════════════════════════════════════════════════════
  // بطاقة اختيار الملف
  // ═════════════════════════════════════════════════════════

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color color,
    required String fileName,
    VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: color,
            ),
          ),

          const SizedBox(height: 12),

          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            icon: Icon(icon, color: Colors.white),
            label: const Text(
              'اختيار الملف',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: onPressed,
          ),

          const SizedBox(height: 8),

          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.grey.shade300,
              ),
            ),
            child: Text(
              fileName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

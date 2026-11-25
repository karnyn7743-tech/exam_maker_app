import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class ExcelFileSelection {
  final String reference;
  final String name;

  const ExcelFileSelection({required this.reference, required this.name});
}

/// Reads and writes the selected workbook through its original Android document URI.
/// No working copy is created: writes are sent back to the same provider URI.
class ExcelFileAccessService {
  static const MethodChannel _channel =
      MethodChannel('com.fawaz.exam_maker_app/document_pdf');

  static Future<ExcelFileSelection?> pickExcelDocument() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'pickExcelDocument',
    );
    if (result == null) return null;

    final uri = result['uri']?.toString();
    final name = result['name']?.toString() ?? 'workbook.xlsx';
    if (uri == null || uri.isEmpty) {
      throw Exception('لم يُرجع منتقي الملفات مرجعًا صالحًا للملف.');
    }

    final extension = name.toLowerCase().split('.').last;
    if (extension != 'xlsx' && extension != 'xlsm') {
      throw Exception('الصيغة المدعومة هي XLSX أو XLSM للحفاظ على بنية المصنف.');
    }
    return ExcelFileSelection(reference: uri, name: name);
  }

  static bool isDocumentUri(String reference) =>
      reference.startsWith('content://');

  static Future<Uint8List> readBytes(String reference) async {
    if (isDocumentUri(reference)) {
      final bytes = await _channel.invokeMethod<Uint8List>(
        'readExcelDocument',
        <String, dynamic>{'uri': reference},
      );
      if (bytes == null || bytes.isEmpty) {
        throw Exception('ملف Excel الأصلي فارغ أو تعذرت قراءته.');
      }
      return bytes;
    }

    final file = File(reference);
    if (!await file.exists()) {
      throw Exception('ملف Excel المحدد غير موجود أو لم يعد متاحًا.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw Exception('ملف Excel الأصلي فارغ.');
    return bytes;
  }

  static Future<void> writeBytes(String reference, Uint8List bytes) async {
    if (bytes.isEmpty) throw Exception('لا توجد بيانات صالحة لحفظها في Excel.');

    if (isDocumentUri(reference)) {
      final saved = await _channel.invokeMethod<bool>(
        'writeExcelDocument',
        <String, dynamic>{'uri': reference, 'bytes': bytes},
      );
      if (saved != true) {
        throw Exception('لم يؤكد مزود الملفات حفظ التغييرات في الملف الأصلي.');
      }
      return;
    }

    final file = File(reference);
    if (!await file.exists()) {
      throw Exception('ملف Excel الأصلي غير موجود لحفظ التغييرات.');
    }
    await file.writeAsBytes(bytes, flush: true);
  }
}

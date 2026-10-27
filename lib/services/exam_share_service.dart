import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/exam_models.dart';

class ExamShareService {
  /// حفظ الاختبار كملف مشروع قابل للمشاركة والمزامنة
  static Future<String> exportExamFile(ExamModel exam) async {
    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
      if (!downloadsDir.existsSync()) {
        downloadsDir = await getExternalStorageDirectory();
      }
    } else {
      downloadsDir = await getApplicationDocumentsDirectory();
    }

    final safeName = exam.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${downloadsDir!.path}/$safeName.exam';
    final file = File(filePath);

    final jsonContent = exam.toJson();
    await file.writeAsString(jsonContent, encoding: utf8);

    return filePath;
  }

  /// قراءة ملف مشروع .exam وتحويله إلى كائن ExamModel
  static Future<ExamModel?> importExamFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final content = await file.readAsString(encoding: utf8);
        return ExamModel.fromJson(content);
      }
    } catch (_) {}
    return null;
  }
}

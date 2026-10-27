import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

class FileManager {
  static const String appFolderName = "صانع الاختبارات";

  /// طلب وتأكيد أذونات التخزين لجميع إصدارات أندرويد
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }
      // طلب الإذن لأندرويد 11 فما فوق
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) return true;

      // أندرويد 10 وما دون
      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted;
    }
    return true;
  }

  /// الحصول على مسار مجلد التطبيق داخل Download
  static Future<Directory> getAppDownloadDirectory() async {
    await requestStoragePermission();

    // المسار المعياري لمجلد التنزيلات على أندرويد
    final downloadPath = Directory('/storage/emulated/0/Download/$appFolderName');

    if (!await downloadPath.exists()) {
      await downloadPath.create(recursive: true);
    }
    return downloadPath;
  }

  /// تنظيف اسم الملف من الرموز الممنوعة في نظام الملفات
  static String sanitizeFileName(String name) {
    var clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (!clean.endsWith('.docx')) {
      clean = '$clean.docx';
    }
    return clean;
  }

  /// الحصول على المسار الكامل لحفظ ملف معين داخل مجلد التطبيق
  static Future<String> getFullFilePath(String fileName) async {
    final dir = await getAppDownloadDirectory();
    final safeName = sanitizeFileName(fileName);
    return '${dir.path}/$safeName';
  }
}

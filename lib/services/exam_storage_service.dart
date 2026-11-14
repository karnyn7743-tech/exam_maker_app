import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam_models.dart';

class ExamStorageService {
  static const String _storageKey = 'saved_exams_list_v1';
  static const String appFolderName = 'المحرر البسيط';

  /// إنشاء وتجهيز مجلد [المحرر البسيط] في مساحة التخزين العامة عند التثبيت والتشغيل
  static Future<Directory> ensureAppFolderExists() async {
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.isDenied) {
        await Permission.manageExternalStorage.request();
      }
      if (await Permission.storage.isDenied) {
        await Permission.storage.request();
      }
    }

    Directory baseDir;
    if (Platform.isAndroid) {
      final publicDownloads = Directory('/storage/emulated/0/Download');
      if (await publicDownloads.exists()) {
        baseDir = publicDownloads;
      } else {
        baseDir = (await getExternalStorageDirectory()) ??
            await getApplicationDocumentsDirectory();
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final appFolder = Directory('${baseDir.path}/$appFolderName');
    if (!await appFolder.exists()) {
      await appFolder.create(recursive: true);
    }
    return appFolder;
  }

  /// صياغة اسم ملف الاختبار القياسي: (الصف_المادة_الشهر أو الفصل.exam)
  static String buildStandardFileName(ExamModel exam) {
    final grade = exam.header.grade.trim().isNotEmpty
        ? exam.header.grade.trim()
        : 'عام';
    final subject = exam.header.subject.trim().isNotEmpty
        ? exam.header.subject.trim()
        : 'مادة';

    // استخراج الشهر أو الفصل من عنوان الاختبار أو الفترة
    String termOrMonth = exam.header.period.trim();
    if (termOrMonth.isEmpty) {
      termOrMonth = exam.header.examTitle.trim().isNotEmpty
          ? exam.header.examTitle.trim()
          : 'اختبار';
    }

    final rawName = '${grade}_${subject}_$termOrMonth';
    final safeName = rawName
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return '$safeName.exam';
  }

  /// حفظ أو تحديث ملف الاختبار بصيغة .exam داخل مجلد [المحرر البسيط]
  static Future<String> saveExamToPublicFolder(ExamModel exam) async {
    final folder = await ensureAppFolderExists();
    final standardFileName = buildStandardFileName(exam);
    final nameWithoutExt = standardFileName.replaceAll('.exam', '');

    // إذا تغير الاسم القياسي (مثلاً عند تعديل الصف أو المادة)، نحذف الملف القديم لتفادي التكرار
    if (exam.fileName.isNotEmpty &&
        exam.fileName != nameWithoutExt &&
        !exam.fileName.startsWith('اختبار_')) {
      final oldFile = File('${folder.path}/${exam.fileName}.exam');
      if (await oldFile.exists()) {
        try {
          await oldFile.delete();
        } catch (_) {}
      }
    }

    exam.fileName = nameWithoutExt;
    final targetFile = File('${folder.path}/$standardFileName');
    final jsonString = jsonEncode(exam.toJson());
    await targetFile.writeAsString(jsonString, flush: true);

    return targetFile.path;
  }

  /// استيراد وقراءة ملف .exam من أي مسار خارجي (مدير الملفات / واتساب / تيليجرام)
  static Future<ExamModel> loadExamFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ملف الاختبار غير موجود في المسار المحدد.');
    }

    final content = await file.readAsString();
    final Map<String, dynamic> decoded = jsonDecode(content);
    final importedExam = ExamModel.fromJson(decoded);

    // حفظ نسخة في ذاكرة التطبيق وداخل مجلد [المحرر البسيط]
    await saveOrUpdateExam(importedExam);
    return importedExam;
  }

  /// مزامنة أي ملفات .exam موجودة داخل مجلد [المحرر البسيط] مع قائمة التطبيق
  static Future<void> syncFolderExamsToApp() async {
    try {
      final folder = await ensureAppFolderExists();
      if (!await folder.exists()) return;

      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_storageKey) ?? [];
      List<ExamModel> currentExams = [];

      for (var item in rawList) {
        try {
          currentExams.add(ExamModel.fromJson(jsonDecode(item)));
        } catch (_) {}
      }

      bool hasChanges = false;
      final entities = folder.listSync();
      for (var entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.exam')) {
          try {
            final content = await entity.readAsString();
            final fileExam = ExamModel.fromJson(jsonDecode(content));
            final idx = currentExams.indexWhere((e) => e.id == fileExam.id);
            if (idx == -1) {
              currentExams.add(fileExam);
              hasChanges = true;
            }
          } catch (_) {}
        }
      }

      if (hasChanges) {
        currentExams.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        final updatedRaw =
            currentExams.map((e) => jsonEncode(e.toJson())).toList();
        await prefs.setStringList(_storageKey, updatedRaw);
      }
    } catch (_) {}
  }

  /// استرجاع كافة الاختبارات السابقة لترتيبها في شاشة البداية
  static Future<List<ExamModel>> getAllExams() async {
    await syncFolderExamsToApp();
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(_storageKey) ?? [];

    List<ExamModel> exams = [];
    for (var item in rawList) {
      try {
        final decoded = jsonDecode(item);
        exams.add(ExamModel.fromJson(decoded));
      } catch (e) {
        // تجاهل أي سجل تالف
      }
    }

    // ترتيب الاختبارات تنازلياً من الأحدث إلى الأقدم
    exams.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return exams;
  }

  /// حفظ أو تحديث اختبار موجود في نفس الملف وفي مجلد [المحرر البسيط]
  static Future<void> saveOrUpdateExam(ExamModel exam) async {
    final prefs = await SharedPreferences.getInstance();
    List<ExamModel> exams = await getAllExams();

    exam.updatedAt = DateTime.now();

    // الحفظ التلقائي في مجلد [المحرر البسيط] بالاسم القياسي (الصف_المادة_الشهر أو الفصل.exam)
    try {
      await saveExamToPublicFolder(exam);
    } catch (_) {}

    final existingIndex = exams.indexWhere((e) => e.id == exam.id);
    if (existingIndex >= 0) {
      exams[existingIndex] = exam; // تحديث
    } else {
      exams.insert(0, exam); // إضافة جديد
    }

    final rawList = exams.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_storageKey, rawList);
  }

  /// حذف اختبار من الأرشيف ومن مجلد [المحرر البسيط]
  static Future<void> deleteExam(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<ExamModel> exams = await getAllExams();

    final targetIndex = exams.indexWhere((e) => e.id == id);
    if (targetIndex >= 0) {
      final targetExam = exams[targetIndex];
      try {
        final folder = await ensureAppFolderExists();
        final fileToDelete = File('${folder.path}/${targetExam.fileName}.exam');
        if (await fileToDelete.exists()) {
          await fileToDelete.delete();
        }
      } catch (_) {}
    }

    exams.removeWhere((e) => e.id == id);

    final rawList = exams.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_storageKey, rawList);
  }
}

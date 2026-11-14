
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/exam_models.dart';

class ExamStorageService {
  static const String _storageKey = 'saved_exams_list_v1';
  static const String appFolderName = 'المحرر البسيط';

  // ============================================================
  // تجهيز مجلد التخزين
  // ============================================================

  /// إنشاء وتجهيز مجلد [المحرر البسيط] في مساحة التخزين.
  static Future<Directory> ensureAppFolderExists() async {
    if (Platform.isAndroid) {
      final manageStatus = await Permission.manageExternalStorage.status;

      if (manageStatus.isDenied) {
        await Permission.manageExternalStorage.request();
      }

      final storageStatus = await Permission.storage.status;

      if (storageStatus.isDenied) {
        await Permission.storage.request();
      }
    }

    Directory baseDir;

    if (Platform.isAndroid) {
      final publicDownloads =
          Directory('/storage/emulated/0/Download');

      if (await publicDownloads.exists()) {
        baseDir = publicDownloads;
      } else {
        baseDir = (await getExternalStorageDirectory()) ??
            await getApplicationDocumentsDirectory();
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final appFolder =
        Directory('${baseDir.path}/$appFolderName');

    if (!await appFolder.exists()) {
      await appFolder.create(recursive: true);
    }

    return appFolder;
  }

  // ============================================================
  // إعداد أسماء الملفات
  // ============================================================

  /// صياغة اسم ملف الاختبار القياسي:
  /// الصف_المادة_الشهر أو الفصل.exam
  static String buildStandardFileName(ExamModel exam) {
    final grade = exam.header.grade.trim().isNotEmpty
        ? exam.header.grade.trim()
        : 'عام';

    final subject = exam.header.subject.trim().isNotEmpty
        ? exam.header.subject.trim()
        : 'مادة';

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

  /// استخراج اسم الملف دون الامتداد.
  static String _fileNameWithoutExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;

    if (name.toLowerCase().endsWith('.exam')) {
      return name.substring(0, name.length - 5);
    }

    return name;
  }

  /// التأكد من أن المسار يشير إلى ملف موجود.
  static Future<bool> _fileExists(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return false;
    }

    return File(path).exists();
  }

  // ============================================================
  // تحديد مسار الحفظ
  // ============================================================

  /// تحديد ملف الحفظ المناسب.
  ///
  /// - إذا كان الاختبار محفوظاً ولم يتغير اسمه القياسي، يحفظ في
  ///   مساره السابق.
  /// - إذا تغيرت بيانات الاسم القياسي، ينشئ ملفاً جديداً.
  /// - إذا كان الاختبار نسخة جديدة بلا مسار، ينشئ ملفاً جديداً.
  /// - لا يحذف الملف السابق في أي حالة.
  static Future<File> _resolveTargetFile(ExamModel exam) async {
    final standardFileName = buildStandardFileName(exam);
    final standardBaseName =
        _fileNameWithoutExtension(standardFileName);

    final oldPath = exam.filePath;

    if (oldPath != null && oldPath.trim().isNotEmpty) {
      final oldFile = File(oldPath);

      if (await oldFile.exists()) {
        final oldBaseName =
            _fileNameWithoutExtension(oldPath);

        final savedBaseName = exam.fileName.trim();

        // إذا كان اسم الملف القياسي لم يتغير، نحتفظ بالمسار
        // الأصلي حتى لو كان الملف مستورداً من خارج مجلد التطبيق.
        if (savedBaseName.isEmpty ||
            savedBaseName == standardBaseName) {
          return oldFile;
        }

        // إذا تغير الصف أو المادة أو الفترة، ننتقل إلى ملف جديد.
        // الملف القديم يبقى محفوظاً دون حذف.
      }
    }

    final folder = await ensureAppFolderExists();

    File targetFile = File(
      '${folder.path}/$standardFileName',
    );

    // منع استبدال اختبار آخر يحمل الاسم نفسه.
    if (await targetFile.exists()) {
      try {
        final content = await targetFile.readAsString();
        final decoded = jsonDecode(content);

        if (decoded is Map) {
          final existingExam = ExamModel.fromMap(
            Map<String, dynamic>.from(decoded),
          );

          if (existingExam.id != exam.id) {
            final base = _fileNameWithoutExtension(
              standardFileName,
            );

            int counter = 2;

            while (true) {
              final candidate = File(
                '${folder.path}/${base}_$counter.exam',
              );

              if (!await candidate.exists()) {
                targetFile = candidate;
                break;
              }

              final candidateContent =
                  await candidate.readAsString();

              final candidateDecoded =
                  jsonDecode(candidateContent);

              if (candidateDecoded is Map) {
                final candidateExam = ExamModel.fromMap(
                  Map<String, dynamic>.from(candidateDecoded),
                );

                if (candidateExam.id == exam.id) {
                  targetFile = candidate;
                  break;
                }
              }

              counter++;
            }
          }
        }
      } catch (_) {
        // لا نستبدل ملفاً موجوداً إذا تعذر التأكد من هويته.
        final base = _fileNameWithoutExtension(
          standardFileName,
        );

        int counter = 2;

        while (true) {
          final candidate = File(
            '${folder.path}/${base}_$counter.exam',
          );

          if (!await candidate.exists()) {
            targetFile = candidate;
            break;
          }

          counter++;
        }
      }
    }

    return targetFile;
  }

  // ============================================================
  // كتابة ملف الاختبار
  // ============================================================

  /// حفظ الاختبار في ملف .exam.
  ///
  /// عند وجود مسار سابق صالح، تتم الكتابة في الملف نفسه
  /// ما دام الاسم القياسي لم يتغير.
  ///
  /// عند تغيير بيانات الترويسة المؤثرة في الاسم، يتم إنشاء
  /// ملف جديد مع الاحتفاظ بالملف السابق.
  static Future<String> saveExamToPublicFolder(
    ExamModel exam,
  ) async {
    final targetFile = await _resolveTargetFile(exam);

    final parent = targetFile.parent;

    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    // toJson يعيد نص JSON بالفعل، لذلك لا نستخدم jsonEncode معه.
    final jsonString = exam.toJson();

    await targetFile.writeAsString(
      jsonString,
      flush: true,
    );

    // تحديث بيانات الملف داخل النموذج بعد نجاح الكتابة.
    exam.filePath = targetFile.path;
    exam.fileName =
        _fileNameWithoutExtension(targetFile.path);

    return targetFile.path;
  }

  // ============================================================
  // قراءة واستيراد ملفات الاختبارات
  // ============================================================

  /// قراءة ملف .exam من أي مسار خارجي.
  ///
  /// يحتفظ التطبيق بمسار الملف الأصلي، حتى يمكن تعديله
  /// وحفظ التعديلات في الملف نفسه.
  static Future<ExamModel> loadExamFromFile(
    String filePath,
  ) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw Exception(
        'ملف الاختبار غير موجود في المسار المحدد.',
      );
    }

    if (!file.path.toLowerCase().endsWith('.exam')) {
      throw Exception(
        'صيغة الملف غير صحيحة. يجب اختيار ملف بامتداد .exam',
      );
    }

    final content = await file.readAsString();

    final decoded = jsonDecode(content);

    if (decoded is! Map) {
      throw const FormatException(
        'محتوى ملف الاختبار غير صالح.',
      );
    }

    final importedExam = ExamModel.fromMap(
      Map<String, dynamic>.from(decoded),
    );

    // الاحتفاظ بمسار الملف الأصلي.
    importedExam.filePath = file.path;

    // إذا لم يكن الاسم محفوظاً داخل النموذج، نستخرجه من الملف.
    if (importedExam.fileName.trim().isEmpty) {
      importedExam.fileName =
          _fileNameWithoutExtension(file.path);
    }

    // تسجيل الاختبار في قائمة التطبيق دون نقل الملف
    // أو تغيير مساره أو إنشاء نسخة أخرى منه.
    await _saveExamToPreferences(importedExam);

    return importedExam;
  }

  // ============================================================
  // حفظ قائمة الاختبارات في SharedPreferences
  // ============================================================

  /// تحديث سجل الاختبار داخل قائمة التطبيق فقط.
  ///
  /// لا تنفذ هذه الدالة كتابة ملف .exam.
  static Future<void> _saveExamToPreferences(
    ExamModel exam,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final rawList = prefs.getStringList(_storageKey) ?? [];

    final List<ExamModel> exams = [];

    for (final item in rawList) {
      try {
        exams.add(ExamModel.fromJson(item));
      } catch (_) {
        // تجاهل السجلات التالفة فقط.
      }
    }

    final existingIndex =
        exams.indexWhere((element) => element.id == exam.id);

    if (existingIndex >= 0) {
      exams[existingIndex] = exam;
    } else {
      exams.insert(0, exam);
    }

    exams.sort(
      (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );

    final updatedRaw = exams
        .map((element) => element.toJson())
        .toList();

    final success = await prefs.setStringList(
      _storageKey,
      updatedRaw,
    );

    if (!success) {
      throw Exception(
        'تعذر تحديث قائمة الاختبارات المحفوظة.',
      );
    }
  }

  // ============================================================
  // مزامنة مجلد الاختبارات مع التطبيق
  // ============================================================

  /// مزامنة ملفات .exam الموجودة في مجلد التطبيق.
  static Future<void> syncFolderExamsToApp() async {
    final folder = await ensureAppFolderExists();

    if (!await folder.exists()) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final rawList = prefs.getStringList(_storageKey) ?? [];

    final List<ExamModel> currentExams = [];

    for (final item in rawList) {
      try {
        currentExams.add(
          ExamModel.fromJson(item),
        );
      } catch (_) {
        // تجاهل السجل غير الصالح.
      }
    }

    bool hasChanges = false;

    await for (final entity in folder.list()) {
      if (entity is! File ||
          !entity.path.toLowerCase().endsWith('.exam')) {
        continue;
      }

      try {
        final content = await entity.readAsString();

        final decoded = jsonDecode(content);

        if (decoded is! Map) {
          continue;
        }

        final fileExam = ExamModel.fromMap(
          Map<String, dynamic>.from(decoded),
        );

        fileExam.filePath = entity.path;

        if (fileExam.fileName.trim().isEmpty) {
          fileExam.fileName =
              _fileNameWithoutExtension(entity.path);
        }

        final index = currentExams.indexWhere(
          (element) => element.id == fileExam.id,
        );

        if (index == -1) {
          currentExams.add(fileExam);
          hasChanges = true;
        } else {
          // تحديث السجل إذا كان الملف أحدث من النسخة المسجلة.
          if (fileExam.updatedAt.isAfter(
            currentExams[index].updatedAt,
          )) {
            currentExams[index] = fileExam;
            hasChanges = true;
          } else if (currentExams[index].filePath == null ||
              currentExams[index].filePath!.isEmpty) {
            currentExams[index].filePath = entity.path;
            hasChanges = true;
          }
        }
      } catch (_) {
        // تجاهل الملف التالف دون إيقاف مزامنة بقية الملفات.
      }
    }

    if (hasChanges) {
      currentExams.sort(
        (a, b) => b.updatedAt.compareTo(a.updatedAt),
      );

      final updatedRaw = currentExams
          .map((element) => element.toJson())
          .toList();

      final success = await prefs.setStringList(
        _storageKey,
        updatedRaw,
      );

      if (!success) {
        throw Exception(
          'تعذرت مزامنة قائمة الاختبارات المحفوظة.',
        );
      }
    }
  }

  // ============================================================
  // استرجاع الاختبارات
  // ============================================================

  /// استرجاع كافة الاختبارات السابقة.
  static Future<List<ExamModel>> getAllExams() async {
    await syncFolderExamsToApp();

    final prefs = await SharedPreferences.getInstance();

    final rawList = prefs.getStringList(_storageKey) ?? [];

    final List<ExamModel> exams = [];

    for (final item in rawList) {
      try {
        exams.add(
          ExamModel.fromJson(item),
        );
      } catch (_) {
        // تجاهل السجل التالف.
      }
    }

    exams.sort(
      (a, b) => b.updatedAt.compareTo(a.updatedAt),
    );

    return exams;
  }

  // ============================================================
  // الحفظ التلقائي والحفظ العادي
  // ============================================================

  /// حفظ أو تحديث الاختبار.
  ///
  /// هذه الدالة لا تتجاهل أخطاء الكتابة.
  /// إذا فشل حفظ الملف أو تحديث القائمة، ينتقل الخطأ إلى
  /// الشاشة المستدعية حتى لا تظهر رسالة نجاح غير صحيحة.
  static Future<void> saveOrUpdateExam(
    ExamModel exam,
  ) async {
    exam.updatedAt = DateTime.now();

    // أولاً: حفظ ملف الاختبار فعلياً.
    // إذا فشلت الكتابة، لن نعلن نجاح الحفظ.
    await saveExamToPublicFolder(exam);

    // ثانياً: تحديث قائمة الاختبارات داخل التطبيق.
    await _saveExamToPreferences(exam);
  }

  // ============================================================
  // حذف الاختبارات
  // ============================================================

  /// حذف اختبار من الأرشيف ومن ملفه المرتبط.
  static Future<void> deleteExam(String id) async {
    final prefs = await SharedPreferences.getInstance();

    final exams = await getAllExams();

    final targetIndex =
        exams.indexWhere((element) => element.id == id);

    if (targetIndex >= 0) {
      final targetExam = exams[targetIndex];

      // استخدام المسار الفعلي أولاً.
      String? targetPath = targetExam.filePath;

      // التوافق مع السجلات القديمة التي لا تحتوي على filePath.
      if (targetPath == null || targetPath.trim().isEmpty) {
        final folder = await ensureAppFolderExists();

        if (targetExam.fileName.trim().isNotEmpty) {
          targetPath =
              '${folder.path}/${targetExam.fileName}.exam';
        }
      }

      if (targetPath != null && targetPath.trim().isNotEmpty) {
        final fileToDelete = File(targetPath);

        if (await fileToDelete.exists()) {
          await fileToDelete.delete();
        }
      }
    }

    exams.removeWhere(
      (element) => element.id == id,
    );

    final rawList = exams
        .map((element) => element.toJson())
        .toList();

    final success = await prefs.setStringList(
      _storageKey,
      rawList,
    );

    if (!success) {
      throw Exception(
        'تعذر تحديث قائمة الاختبارات بعد الحذف.',
      );
    }
  }
}

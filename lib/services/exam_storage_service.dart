import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/exam_models.dart';

class ExamStorageService {
  static const String _storageKey = 'saved_exams_list_v1';

  /// استرجاع كافة الاختبارات السابقة لترتيبها في شاشة البداية
  static Future<List<ExamModel>> getAllExams() async {
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

  /// حفظ أو تحديث اختبار موجود في نفس الملف
  static Future<void> saveOrUpdateExam(ExamModel exam) async {
    final prefs = await SharedPreferences.getInstance();
    List<ExamModel> exams = await getAllExams();

    exam.updatedAt = DateTime.now();

    final existingIndex = exams.indexWhere((e) => e.id == exam.id);
    if (existingIndex >= 0) {
      exams[existingIndex] = exam; // تحديث
    } else {
      exams.insert(0, exam); // إضافة جديد
    }

    final rawList = exams.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_storageKey, rawList);
  }

  /// حذف اختبار من الأرشيف
  static Future<void> deleteExam(String id) async {
    final prefs = await SharedPreferences.getInstance();
    List<ExamModel> exams = await getAllExams();
    exams.removeWhere((e) => e.id == id);

    final rawList = exams.map((e) => jsonEncode(e.toJson())).toList();
    await prefs.setStringList(_storageKey, rawList);
  }
}

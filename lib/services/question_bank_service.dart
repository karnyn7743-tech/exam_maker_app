import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/exam_models.dart';

class BankQuestionItem {
  final String id;
  final String subject;
  final String grade;
  final QuestionModel question;
  final DateTime addedAt;

  BankQuestionItem({
    required this.id,
    required this.subject,
    required this.grade,
    required this.question,
    required this.addedAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'subject': subject,
    'grade': grade,
    'question': question.toMap(),
    'addedAt': addedAt.toIso8601String(),
  };

  factory BankQuestionItem.fromMap(Map<String, dynamic> map) => BankQuestionItem(
    id: map['id'] ?? '',
    subject: map['subject'] ?? '',
    grade: map['grade'] ?? '',
    question: QuestionModel.fromMap(map['question'] ?? {}),
    addedAt: DateTime.tryParse(map['addedAt'] ?? '') ?? DateTime.now(),
  );
}

class QuestionBankService {
  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/question_bank.json');
    if (!await file.exists()) {
      await file.writeAsString(jsonEncode([]));
    }
    return file;
  }

  static Future<List<BankQuestionItem>> getAllQuestions() async {
    try {
      final file = await _getFile();
      final str = await file.readAsString();
      final List<dynamic> list = jsonDecode(str);
      return list.map((e) => BankQuestionItem.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveQuestion({
    required QuestionModel question,
    required String subject,
    required String grade,
  }) async {
    final list = await getAllQuestions();
    final item = BankQuestionItem(
      id: question.id,
      subject: subject.trim().isEmpty ? 'عام' : subject.trim(),
      grade: grade.trim().isEmpty ? 'عام' : grade.trim(),
      question: QuestionModel.fromMap(question.toMap()),
      addedAt: DateTime.now(),
    );
    list.removeWhere((q) => q.id == item.id);
    list.insert(0, item);

    final file = await _getFile();
    await file.writeAsString(jsonEncode(list.map((e) => e.toMap()).toList()));
  }

  static Future<void> deleteQuestion(String id) async {
    final list = await getAllQuestions();
    list.removeWhere((q) => q.id == id);
    final file = await _getFile();
    await file.writeAsString(jsonEncode(list.map((e) => e.toMap()).toList()));
  }
}

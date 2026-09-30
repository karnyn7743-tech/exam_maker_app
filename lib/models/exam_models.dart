import 'dart:convert';

/// يمثل مقطعاً نصياً منسقاً داخل السؤال (Rich Text Span)
/// يدعم التسطير، التفخيم، حجم الخط، نوع الخط، والمد (الكشيدة)
class TextSpanModel {
  String text;
  bool isBold;
  bool isUnderline;
  double fontSize;
  String fontFamily;

  TextSpanModel({
    required this.text,
    this.isBold = false,
    this.isUnderline = false,
    this.fontSize = 14.0,
    this.fontFamily = 'Traditional Arabic',
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'isBold': isBold,
        'isUnderline': isUnderline,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
      };

  factory TextSpanModel.fromJson(Map<String, dynamic> json) => TextSpanModel(
        text: json['text'] ?? '',
        isBold: json['isBold'] ?? false,
        isUnderline: json['isUnderline'] ?? false,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        fontFamily: json['fontFamily'] ?? 'Traditional Arabic',
      );
}

/// يمثل السؤال الكامل ودرجته ونوعه ومقاطعه المنسقة
class QuestionModel {
  String id;
  String title; // مثل: السؤال الأول
  List<TextSpanModel> spans; // نص السؤال مع تنسيقاته الجزئية
  double mark; // درجة السؤال
  String type; // essay, mcq, true_false, matching
  List<String> options; // الخيارات إن كان اختيار من متعدد

  QuestionModel({
    required this.id,
    this.title = '',
    required this.spans,
    this.mark = 0.0,
    this.type = 'essay',
    this.options = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'spans': spans.map((s) => s.toJson()).toList(),
        'mark': mark,
        'type': type,
        'options': options,
      };

  factory QuestionModel.fromJson(Map<String, dynamic> json) => QuestionModel(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        spans: (json['spans'] as List? ?? [])
            .map((s) => TextSpanModel.fromJson(s))
            .toList(),
        mark: (json['mark'] as num?)?.toDouble() ?? 0.0,
        type: json['type'] ?? 'essay',
        options: (json['options'] as List? ?? []).map((e) => e.toString()).toList(),
      );
}

/// يمثل بيانات الترويسة المعتمدة
class HeaderModel {
  // الجانب الأيمن (الجهة الإدارية)
  String country;
  String ministry;
  String governorate;
  String directorate;
  String school;

  // الجانب الأوسط (الشعار والبسملة)
  String basmalaText;
  String? basmalaImagePath;
  String? logoImagePath; // شعار مخصص أو طير الجمهورية

  // الجانب الأيسر (المعلومات التعليمية والزمن)
  String grade;
  String subject;
  String examDate;
  String examTime;
  String period;

  // الشريط الأوسط العريض (عنوان الاختبار)
  String examTitle;

  // توجيه الامتحان وخيارات الصفحة
  String instructionText;
  bool topMargin1cm; // خيار ترك فراغ 1 سم أعلى الصفحة

  HeaderModel({
    this.country = 'الجمهـــــورية اليمنيـــــة',
    this.ministry = 'وزارة التربية والتعليم والبحث العلمي',
    this.governorate = 'مكتب التربية والتعليم بمحافظة ذمار',
    this.directorate = 'مكتب التربية والتعليم بمديرية عتمة',
    this.school = 'مدرسة هجرة بني عبد الصمد',
    this.basmalaText = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
    this.basmalaImagePath,
    this.logoImagePath,
    this.grade = 'الصف الثاني',
    this.subject = 'لغتي العربية',
    this.examDate = '1 / 10 / 2026 م',
    this.examTime = 'ساعتان',
    this.period = 'واحدة',
    this.examTitle = 'إمتحان نهاية الفصل الدراسي الاول للعام الدراسي 2026/2027 م',
    this.instructionText = 'أجب مستعيناً بالله عن جميع الأسئلة الآتية :-',
    this.topMargin1cm = true,
  });

  Map<String, dynamic> toJson() => {
        'country': country,
        'ministry': ministry,
        'governorate': governorate,
        'directorate': directorate,
        'school': school,
        'basmalaText': basmalaText,
        'basmalaImagePath': basmalaImagePath,
        'logoImagePath': logoImagePath,
        'grade': grade,
        'subject': subject,
        'examDate': examDate,
        'examTime': examTime,
        'period': period,
        'examTitle': examTitle,
        'instructionText': instructionText,
        'topMargin1cm': topMargin1cm,
      };

  factory HeaderModel.fromJson(Map<String, dynamic> json) => HeaderModel(
        country: json['country'] ?? 'الجمهـــــورية اليمنيـــــة',
        ministry: json['ministry'] ?? 'وزارة التربية والتعليم والبحث العلمي',
        governorate: json['governorate'] ?? '',
        directorate: json['directorate'] ?? '',
        school: json['school'] ?? '',
        basmalaText: json['basmalaText'] ?? '',
        basmalaImagePath: json['basmalaImagePath'],
        logoImagePath: json['logoImagePath'],
        grade: json['grade'] ?? '',
        subject: json['subject'] ?? '',
        examDate: json['examDate'] ?? '',
        examTime: json['examTime'] ?? '',
        period: json['period'] ?? '',
        examTitle: json['examTitle'] ?? '',
        instructionText: json['instructionText'] ?? '',
        topMargin1cm: json['topMargin1cm'] ?? true,
      );
}

/// يمثل وثيقة الاختبار الكاملة المحفوظة في التطبيق
class ExamModel {
  String id;
  String fileName; // اسم ملف الـ docx المحفوظ (بدون امتداد أو معه)
  DateTime createdAt;
  DateTime updatedAt;
  HeaderModel header;
  List<QuestionModel> questions;

  ExamModel({
    required this.id,
    required this.fileName,
    required this.createdAt,
    required this.updatedAt,
    required this.header,
    required this.questions,
  });

  double get totalMarks =>
      questions.fold(0.0, (sum, item) => sum + item.mark);

  Map<String, dynamic> toJson() => {
        'id': id,
        'fileName': fileName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'header': header.toJson(),
        'questions': questions.map((q) => q.toJson()).toList(),
      };

  factory ExamModel.fromJson(Map<String, dynamic> json) => ExamModel(
        id: json['id'] ?? '',
        fileName: json['fileName'] ?? 'اختبار_جديد',
        createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
        header: HeaderModel.fromJson(json['header'] ?? {}),
        questions: (json['questions'] as List? ?? [])
            .map((q) => QuestionModel.fromJson(q))
            .toList(),
      );

  /// إنشاء نسخة جديدة مطابقة لأجل خاصية "حفظ باسم"
  ExamModel copyWith({
    String? newId,
    String? newFileName,
  }) {
    final rawJson = jsonDecode(jsonEncode(toJson()));
    rawJson['id'] = newId ?? id;
    rawJson['fileName'] = newFileName ?? fileName;
    rawJson['createdAt'] = DateTime.now().toIso8601String();
    rawJson['updatedAt'] = DateTime.now().toIso8601String();
    return ExamModel.fromJson(rawJson);
  }
}

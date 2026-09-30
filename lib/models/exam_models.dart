import 'dart:convert';

/// اتجاه كتابة اسم السؤال في الخانة الأولى
enum QuestionTitleOrientation {
  horizontal, // أفقي عادي
  verticalBottomToTop, // رأسي من الأسفل للأعلى (باتجاه اليمين)
  verticalTopToBottom, // رأسي من الأعلى للأسفل (باتجاه اليسار)
}

/// مقطع نصي منسق داخل السؤال
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

/// نموذج السؤال المقسم لثلاثة أقسام (الاسم وتدويره | المحتوى والتنسيق | الدرجة)
class QuestionModel {
  String id;
  String title; // اسم السؤال مثل: السؤال الأول / س١
  QuestionTitleOrientation titleOrientation; // اتجاه كتابة الاسم
  List<TextSpanModel> spans; // محتوى السؤال
  double mark; // درجة السؤال

  QuestionModel({
    required this.id,
    this.title = '',
    this.titleOrientation = QuestionTitleOrientation.horizontal,
    required this.spans,
    this.mark = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'titleOrientation': titleOrientation.name,
        'spans': spans.map((s) => s.toJson()).toList(),
        'mark': mark,
      };

  factory QuestionModel.fromJson(Map<String, dynamic> json) => QuestionModel(
        id: json['id'] ?? '',
        title: json['title'] ?? '',
        titleOrientation: QuestionTitleOrientation.values.firstWhere(
          (e) => e.name == json['titleOrientation'],
          orElse: () => QuestionTitleOrientation.horizontal,
        ),
        spans: (json['spans'] as List? ?? [])
            .map((s) => TextSpanModel.fromJson(s))
            .toList(),
        mark: (json['mark'] as num?)?.toDouble() ?? 0.0,
      );
}

/// نموذج الترويسة والتذييل وخيارات الورقة
class HeaderModel {
  // الجهة الإدارية (اليمين)
  String country;
  String ministry;
  String governorate;
  String directorate;
  String school;

  // الوسط
  String basmalaText;
  String? logoImagePath;

  // اليسار
  String grade;
  String subject;
  String examDate;
  String examTime;
  String period;

  // الشريط الأوسط والشريط التوجيهي
  String examTitle;
  String instructionText;
  bool topMargin1cm;

  // --- خيارات التذييل القابلة للتعديل ---
  bool isMultiPage; // هل الاختبار أكثر من ورقة؟
  String singlePageFooterText; // ختام الورقة الواحدة
  String continuationText; // عبارة يتبع إن كان متعدد الصفحات
  String teacherSignature; // توقيع المعلم

  HeaderModel({
    this.country = 'الجمهـــــورية اليمنيـــــة',
    this.ministry = 'وزارة التربية والتعليم والبحث العلمي',
    this.governorate = 'مكتب التربية والتعليم بمحافظة ذمار',
    this.directorate = 'مكتب التربية والتعليم بمديرية عتمة',
    this.school = 'مدرسة هجرة بني عبد الصمد',
    this.basmalaText = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
    this.logoImagePath,
    this.grade = 'الصف الثاني',
    this.subject = 'لغتي العربية',
    this.examDate = '1 / 10 / 2026 م',
    this.examTime = 'ساعتان',
    this.period = 'واحدة',
    this.examTitle = 'إمتحان نهاية الفصل الدراسي الاول للعام الدراسي 2026/2027 م',
    this.instructionText = 'أجب مستعيناً بالله عن جميع الأسئلة الآتية :-',
    this.topMargin1cm = true,
    this.isMultiPage = false,
    this.singlePageFooterText = 'انتهت الأسئلة - مع تمنياتنا لكم بالنجاح والتوفيق',
    this.continuationText = '( انظر بقية الأسئلة في الصفحة التالية ◄ )',
    this.teacherSignature = 'معلم المادة: ....................',
  });

  Map<String, dynamic> toJson() => {
        'country': country,
        'ministry': ministry,
        'governorate': governorate,
        'directorate': directorate,
        'school': school,
        'basmalaText': basmalaText,
        'logoImagePath': logoImagePath,
        'grade': grade,
        'subject': subject,
        'examDate': examDate,
        'examTime': examTime,
        'period': period,
        'examTitle': examTitle,
        'instructionText': instructionText,
        'topMargin1cm': topMargin1cm,
        'isMultiPage': isMultiPage,
        'singlePageFooterText': singlePageFooterText,
        'continuationText': continuationText,
        'teacherSignature': teacherSignature,
      };

  factory HeaderModel.fromJson(Map<String, dynamic> json) => HeaderModel(
        country: json['country'] ?? 'الجمهـــــورية اليمنيـــــة',
        ministry: json['ministry'] ?? 'وزارة التربية والتعليم والبحث العلمي',
        governorate: json['governorate'] ?? '',
        directorate: json['directorate'] ?? '',
        school: json['school'] ?? '',
        basmalaText: json['basmalaText'] ?? '',
        logoImagePath: json['logoImagePath'],
        grade: json['grade'] ?? '',
        subject: json['subject'] ?? '',
        examDate: json['examDate'] ?? '',
        examTime: json['examTime'] ?? '',
        period: json['period'] ?? '',
        examTitle: json['examTitle'] ?? '',
        instructionText: json['instructionText'] ?? '',
        topMargin1cm: json['topMargin1cm'] ?? true,
        isMultiPage: json['isMultiPage'] ?? false,
        singlePageFooterText: json['singlePageFooterText'] ??
            'انتهت الأسئلة - مع تمنياتنا لكم بالنجاح والتوفيق',
        continuationText: json['continuationText'] ??
            '( انظر بقية الأسئلة في الصفحة التالية ◄ )',
        teacherSignature:
            json['teacherSignature'] ?? 'معلم المادة: ....................',
      );
}

/// نموذج وثيقة الامتحان
class ExamModel {
  String id;
  String fileName;
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

  double get totalMarks => questions.fold(0.0, (sum, item) => sum + item.mark);

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

  ExamModel copyWith({String? newId, String? newFileName}) {
    final rawJson = jsonDecode(jsonEncode(toJson()));
    rawJson['id'] = newId ?? id;
    rawJson['fileName'] = newFileName ?? fileName;
    rawJson['createdAt'] = DateTime.now().toIso8601String();
    rawJson['updatedAt'] = DateTime.now().toIso8601String();
    return ExamModel.fromJson(rawJson);
  }
}

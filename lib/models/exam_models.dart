import 'dart:convert';

enum QuestionTitleOrientation {
  horizontal,
  verticalBottomToTop,
  verticalTopToBottom,
}

enum ElementType {
  image,
  textBox,
  dottedLine,
  mathOperation, // النوع المضاف للعمليات الرأسية وقوالب الرياضيات العربية
}

class InsertableElement {
  final String id;
  final ElementType type;
  String content; // مسار الصورة، نص الإرشاد، محتوى السطر، أو بيانات العملية الرياضية (JSON)
  double width;
  double height;
  String alignment;

  InsertableElement({
    required this.id,
    required this.type,
    required this.content,
    this.width = 100,
    this.height = 100,
    this.alignment = 'center',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'content': content,
        'width': width,
        'height': height,
        'alignment': alignment,
      };

  factory InsertableElement.fromMap(Map<String, dynamic> map) =>
      InsertableElement(
        id: map['id'] ?? '',
        type: ElementType.values.byName(map['type'] ?? 'textBox'),
        content: map['content'] ?? '',
        width: (map['width'] as num?)?.toDouble() ?? 100.0,
        height: (map['height'] as num?)?.toDouble() ?? 100.0,
        alignment: map['alignment'] ?? 'center',
      );
}

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

  Map<String, dynamic> toMap() => {
        'text': text,
        'isBold': isBold,
        'isUnderline': isUnderline,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
      };

  factory TextSpanModel.fromMap(Map<String, dynamic> map) => TextSpanModel(
        text: map['text'] ?? '',
        isBold: map['isBold'] ?? false,
        isUnderline: map['isUnderline'] ?? false,
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 14.0,
        fontFamily: map['fontFamily'] ?? 'Traditional Arabic',
      );
}

class QuestionModel {
  final String id;
  String title;
  QuestionTitleOrientation titleOrientation;
  double mark;
  List<TextSpanModel> spans;
  List<InsertableElement> elements;

  QuestionModel({
    required this.id,
    required this.title,
    this.titleOrientation = QuestionTitleOrientation.horizontal,
    this.mark = 0.0,
    required this.spans,
    List<InsertableElement>? elements,
  }) : elements = elements ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'titleOrientation': titleOrientation.name,
        'mark': mark,
        'spans': spans.map((s) => s.toMap()).toList(),
        'elements': elements.map((e) => e.toMap()).toList(),
      };

  factory QuestionModel.fromMap(Map<String, dynamic> map) => QuestionModel(
        id: map['id'] ?? '',
        title: map['title'] ?? '',
        titleOrientation: QuestionTitleOrientation.values.byName(
          map['titleOrientation'] ?? 'horizontal',
        ),
        mark: (map['mark'] as num?)?.toDouble() ?? 0.0,
        spans: (map['spans'] as List<dynamic>?)
                ?.map((item) => TextSpanModel.fromMap(item))
                .toList() ??
            [],
        elements: (map['elements'] as List<dynamic>?)
                ?.map((item) => InsertableElement.fromMap(item))
                .toList() ??
            [],
      );
}

class HeaderModel {
  String country;
  String ministry;
  String governorate;
  String directorate;
  String school;
  String basmalaText;
  String? logoImagePath;
  String grade;
  String subject;
  String examDate;
  String examTime;
  String period;
  String examTitle;
  String instructionText;
  bool isMultiPage;
  String singlePageFooterText;
  String continuationText;
  String teacherSignature;
  bool topMargin1cm;

  // خصائص الخطوط وتنسيقات حقول الترويسة
  String basmalaFont;
  double basmalaFontSize;
  bool basmalaBold;

  String titleFont;
  double titleFontSize;
  bool titleBold;

  String adminFont;
  double adminFontSize;
  bool adminBold;

  String detailsFont;
  double detailsFontSize;
  bool detailsBold;

  HeaderModel({
    this.country = 'الجمهورية اليمنية',
    this.ministry = 'وزارة التربية والتعليم والبحث العلمي',
    this.governorate = 'مكتب التربية والتعليم بمحافظة ذمار',
    this.directorate = 'مكتب التربية والتعليم بمديرية عتمة',
    this.school = 'مدرسة هجرة بني عبد الصمد',
    this.basmalaText = 'بسم الله الرحمن الرحيم',
    this.logoImagePath,
    this.grade = 'التاسع',
    this.subject = 'الرياضيات',
    this.examDate = '1447/08/15 هـ',
    this.examTime = 'ساعتان',
    this.period = 'واحدة',
    this.examTitle = 'اختبار نهاية الفصل الدراسي الأول',
    this.instructionText = 'أجب عن جميع الأسئلة الآتية',
    this.isMultiPage = false,
    this.singlePageFooterText = 'انتهت الأسئلة مع تمنياتنا لكم بالتوفيق والنجاح',
    this.continuationText = 'يتبع الصفحة التالية ◄',
    this.teacherSignature = 'معلم المادة: ......................',
    this.topMargin1cm = true,
    this.basmalaFont = 'Amiri',
    this.basmalaFontSize = 12.0,
    this.basmalaBold = true,
    this.titleFont = 'Amiri',
    this.titleFontSize = 12.0,
    this.titleBold = true,
    this.adminFont = 'Amiri',
    this.adminFontSize = 9.5,
    this.adminBold = false,
    this.detailsFont = 'Amiri',
    this.detailsFontSize = 10.0,
    this.detailsBold = false,
  });

  Map<String, dynamic> toMap() => {
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
        'isMultiPage': isMultiPage,
        'singlePageFooterText': singlePageFooterText,
        'continuationText': continuationText,
        'teacherSignature': teacherSignature,
        'topMargin1cm': topMargin1cm,
        'basmalaFont': basmalaFont,
        'basmalaFontSize': basmalaFontSize,
        'basmalaBold': basmalaBold,
        'titleFont': titleFont,
        'titleFontSize': titleFontSize,
        'titleBold': titleBold,
        'adminFont': adminFont,
        'adminFontSize': adminFontSize,
        'adminBold': adminBold,
        'detailsFont': detailsFont,
        'detailsFontSize': detailsFontSize,
        'detailsBold': detailsBold,
      };

  factory HeaderModel.fromMap(Map<String, dynamic> map) => HeaderModel(
        country: map['country'] ?? 'الجمهورية اليمنية',
        ministry: map['ministry'] ?? 'وزارة التربية والتعليم والبحث العلمي',
        governorate: map['governorate'] ?? '',
        directorate: map['directorate'] ?? '',
        school: map['school'] ?? '',
        basmalaText: map['basmalaText'] ?? 'بسم الله الرحمن الرحيم',
        logoImagePath: map['logoImagePath'],
        grade: map['grade'] ?? '',
        subject: map['subject'] ?? '',
        examDate: map['examDate'] ?? '',
        examTime: map['examTime'] ?? '',
        period: map['period'] ?? '',
        examTitle: map['examTitle'] ?? '',
        instructionText: map['instructionText'] ?? '',
        isMultiPage: map['isMultiPage'] ?? false,
        singlePageFooterText: map['singlePageFooterText'] ?? '',
        continuationText: map['continuationText'] ?? '',
        teacherSignature: map['teacherSignature'] ?? '',
        topMargin1cm: map['topMargin1cm'] ?? true,
        basmalaFont: map['basmalaFont'] ?? 'Amiri',
        basmalaFontSize: (map['basmalaFontSize'] as num?)?.toDouble() ?? 12.0,
        basmalaBold: map['basmalaBold'] ?? true,
        titleFont: map['titleFont'] ?? 'Amiri',
        titleFontSize: (map['titleFontSize'] as num?)?.toDouble() ?? 12.0,
        titleBold: map['titleBold'] ?? true,
        adminFont: map['adminFont'] ?? 'Amiri',
        adminFontSize: (map['adminFontSize'] as num?)?.toDouble() ?? 9.5,
        adminBold: map['adminBold'] ?? false,
        detailsFont: map['detailsFont'] ?? 'Amiri',
        detailsFontSize: (map['detailsFontSize'] as num?)?.toDouble() ?? 10.0,
        detailsBold: map['detailsBold'] ?? false,
      );
}

class ExamModel {
  final String id;
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

  double get totalMarks =>
      questions.fold(0.0, (sum, item) => sum + item.mark);

  ExamModel copyWith({
    String? newId,
    String? newFileName,
  }) {
    return ExamModel(
      id: newId ?? id,
      fileName: newFileName ?? fileName,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      header: HeaderModel.fromMap(header.toMap()),
      questions: questions.map((q) => QuestionModel.fromMap(q.toMap())).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'header': header.toMap(),
        'questions': questions.map((q) => q.toMap()).toList(),
      };

  factory ExamModel.fromMap(Map<String, dynamic> map) => ExamModel(
        id: map['id'] ?? '',
        fileName: map['fileName'] ?? '',
        createdAt: DateTime.parse(map['createdAt']),
        updatedAt: DateTime.parse(map['updatedAt']),
        header: HeaderModel.fromMap(map['header'] ?? {}),
        questions: (map['questions'] as List<dynamic>?)
                ?.map((item) => QuestionModel.fromMap(item))
                .toList() ??
            [],
      );

  String toJson() => jsonEncode(toMap());
  factory ExamModel.fromJson(String source) =>
      ExamModel.fromMap(jsonDecode(source));
}

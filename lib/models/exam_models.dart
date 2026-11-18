
import 'dart:convert';
import 'package:flutter/material.dart';

/// نمط الاختبار العام في التطبيق
enum ExamType {
  traditional, // الاختبارات الشاملة (التحريرية التقليدية)
  automated,   // اختبارات الأتمتة الذكية (نماذج التظليل OMR)
}

/// نمط رموز خيارات أسئلة الاختيار من متعدد
enum ChoiceSymbolType {
  arabicLetters,  // أ ، ب ، جـ ، د
  numbers,        // ١ ، ٢ ، ٣ ، ٤
  englishLetters, // A , B , C , D
}

enum QuestionTitleOrientation {
  horizontal,
  verticalBottomToTop,
  verticalTopToBottom,
}

/// اتجاه كتابة النص في عمود الدرجة
enum GradeTextOrientation {
  horizontal,
  verticalBottomToTop,
  verticalTopToBottom,
}

/// أنواع العناصر القابلة للإدراج داخل الأسئلة
enum ElementType {
  image,
  textBox,
  dottedLine,
  mathOperation,
  table,
  shape,
}

class InsertableElement {
  final String id;
  final ElementType type;
  String content;
  double width;
  double height;
  String alignment;
  double dx;
  double dy;
  bool isFloating;
  String layer;

  InsertableElement({
    required this.id,
    required this.type,
    required this.content,
    this.width = 100,
    this.height = 100,
    this.alignment = 'center',
    this.dx = 0.0,
    this.dy = 0.0,
    this.isFloating = false,
    this.layer = 'inline',
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type.name,
        'content': content,
        'width': width,
        'height': height,
        'alignment': alignment,
        'dx': dx,
        'dy': dy,
        'isFloating': isFloating,
        'layer': layer,
      };

  factory InsertableElement.fromMap(Map<String, dynamic> map) {
    final rawType = map['type']?.toString() ?? 'textBox';

    final parsedType = ElementType.values.firstWhere(
      (e) => e.name == rawType,
      orElse: () => ElementType.textBox,
    );

    return InsertableElement(
      id: map['id']?.toString() ?? '',
      type: parsedType,
      content: map['content']?.toString() ?? '',
      width: (map['width'] as num?)?.toDouble() ?? 100.0,
      height: (map['height'] as num?)?.toDouble() ?? 100.0,
      alignment: map['alignment']?.toString() ?? 'center',
      dx: (map['dx'] as num?)?.toDouble() ?? 0.0,
      dy: (map['dy'] as num?)?.toDouble() ?? 0.0,
      isFloating: map['isFloating'] as bool? ?? false,
      layer: map['layer']?.toString() ?? 'inline',
    );
  }
}

class TextSpanModel {
  String text;
  bool isBold;
  bool isItalic;
  bool isUnderline;
  bool isStrikethrough;
  double fontSize;
  String fontFamily;
  String colorHex;
  String? highlightHex;

  TextSpanModel({
    required this.text,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.isStrikethrough = false,
    this.fontSize = 14.0,
    this.fontFamily = 'Amiri',
    this.colorHex = '#000000',
    this.highlightHex,
  });

  Map<String, dynamic> toMap() => {
        'text': text,
        'isBold': isBold,
        'isItalic': isItalic,
        'isUnderline': isUnderline,
        'isStrikethrough': isStrikethrough,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
        'colorHex': colorHex,
        'highlightHex': highlightHex,
      };

  factory TextSpanModel.fromMap(Map<String, dynamic> map) => TextSpanModel(
        text: map['text']?.toString() ?? '',
        isBold: map['isBold'] as bool? ?? false,
        isItalic: map['isItalic'] as bool? ?? false,
        isUnderline: map['isUnderline'] as bool? ?? false,
        isStrikethrough: map['isStrikethrough'] as bool? ?? false,
        fontSize: (map['fontSize'] as num?)?.toDouble() ?? 14.0,
        fontFamily: map['fontFamily']?.toString() ?? 'Amiri',
        colorHex: map['colorHex']?.toString() ?? '#000000',
        highlightHex: map['highlightHex']?.toString(),
      );
}

class QuestionModel {
  final String id;
  String title;
  QuestionTitleOrientation titleOrientation;
  double mark;
  GradeTextOrientation gradeOrientation;
  List<TextSpanModel> spans;
  List<InsertableElement> elements;

  /// نسخة المستند الغني المحرر بصيغة Fluent Editor.
  /// اختيارية حتى تبقى ملفات .exam القديمة متوافقة.
  String? richDocumentJson;

  String answerKey;
  bool isTwoColumns;
  TextAlign? alignment;
  double lineSpacing;

  QuestionModel({
    required this.id,
    required this.title,
    this.titleOrientation = QuestionTitleOrientation.horizontal,
    this.mark = 0.0,
    this.gradeOrientation = GradeTextOrientation.horizontal,
    required this.spans,
    List<InsertableElement>? elements,
    this.richDocumentJson,
    this.answerKey = '',
    this.isTwoColumns = false,
    this.alignment,
    this.lineSpacing = 1.15,
  }) : elements = elements ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'titleOrientation': titleOrientation.name,
        'mark': mark,
        'gradeOrientation': gradeOrientation.name,
        'spans': spans.map((s) => s.toMap()).toList(),
        'elements': elements.map((e) => e.toMap()).toList(),
        'richDocumentJson': richDocumentJson,
        'answerKey': answerKey,
        'isTwoColumns': isTwoColumns,
        'alignment': alignment?.name,
        'lineSpacing': lineSpacing,
      };

  factory QuestionModel.fromMap(Map<String, dynamic> map) {
    final rawOrientation =
        map['titleOrientation']?.toString() ?? 'horizontal';

    final parsedOrientation =
        QuestionTitleOrientation.values.firstWhere(
      (e) => e.name == rawOrientation,
      orElse: () => QuestionTitleOrientation.horizontal,
    );

    final rawGradeOrient =
        map['gradeOrientation']?.toString() ?? 'horizontal';

    final parsedGradeOrient =
        GradeTextOrientation.values.firstWhere(
      (e) => e.name == rawGradeOrient,
      orElse: () => GradeTextOrientation.horizontal,
    );

    final rawAlign = map['alignment']?.toString();

    final parsedAlign = rawAlign != null
        ? TextAlign.values.firstWhere(
            (e) => e.name == rawAlign,
            orElse: () => TextAlign.start,
          )
        : null;

    final rawSpans = map['spans'];
    final rawElements = map['elements'];

    return QuestionModel(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      titleOrientation: parsedOrientation,
      mark: (map['mark'] as num?)?.toDouble() ?? 0.0,
      gradeOrientation: parsedGradeOrient,
      spans: rawSpans is List
          ? rawSpans
              .whereType<Map>()
              .map((item) => TextSpanModel.fromMap(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : [],
      elements: rawElements is List
          ? rawElements
              .whereType<Map>()
              .map((item) => InsertableElement.fromMap(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : [],
      richDocumentJson: map['richDocumentJson']?.toString(),
      answerKey: map['answerKey']?.toString() ?? '',
      isTwoColumns: map['isTwoColumns'] as bool? ?? false,
      alignment: parsedAlign,
    );
  }
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

  // خصائص استيراد بيانات الطلاب وكود المادة
  String studentDataMode;
  String? excelFilePath;
  int subjectCode;

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
    this.singlePageFooterText =
        'انتهت الأسئلة مع تمنياتنا لكم بالتوفيق والنجاح',
    this.continuationText = 'يتبع الصفحة التالية ◄',
    this.teacherSignature = 'معلم المادة: ......................',
    this.topMargin1cm = true,
    this.studentDataMode = 'none',
    this.excelFilePath,
    this.subjectCode = 1,
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
        'studentDataMode': studentDataMode,
        'excelFilePath': excelFilePath,
        'subjectCode': subjectCode,
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
        country:
            map['country']?.toString() ?? 'الجمهورية اليمنية',
        ministry: map['ministry']?.toString() ??
            'وزارة التربية والتعليم والبحث العلمي',
        governorate: map['governorate']?.toString() ?? '',
        directorate: map['directorate']?.toString() ?? '',
        school: map['school']?.toString() ?? '',
        basmalaText:
            map['basmalaText']?.toString() ?? 'بسم الله الرحمن الرحيم',
        logoImagePath: map['logoImagePath']?.toString(),
        grade: map['grade']?.toString() ?? '',
        subject: map['subject']?.toString() ?? '',
        examDate: map['examDate']?.toString() ?? '',
        examTime: map['examTime']?.toString() ?? '',
        period: map['period']?.toString() ?? '',
        examTitle: map['examTitle']?.toString() ?? '',
        instructionText: map['instructionText']?.toString() ?? '',
        isMultiPage: map['isMultiPage'] as bool? ?? false,
        singlePageFooterText:
            map['singlePageFooterText']?.toString() ?? '',
        continuationText:
            map['continuationText']?.toString() ?? '',
        teacherSignature:
            map['teacherSignature']?.toString() ?? '',
        topMargin1cm: map['topMargin1cm'] as bool? ?? true,
        studentDataMode:
            map['studentDataMode']?.toString() ?? 'none',
        excelFilePath: map['excelFilePath']?.toString(),
        subjectCode: (map['subjectCode'] as num?)?.toInt() ?? 1,
        basmalaFont: map['basmalaFont']?.toString() ?? 'Amiri',
        basmalaFontSize:
            (map['basmalaFontSize'] as num?)?.toDouble() ?? 12.0,
        basmalaBold: map['basmalaBold'] as bool? ?? true,
        titleFont: map['titleFont']?.toString() ?? 'Amiri',
        titleFontSize:
            (map['titleFontSize'] as num?)?.toDouble() ?? 12.0,
        titleBold: map['titleBold'] as bool? ?? true,
        adminFont: map['adminFont']?.toString() ?? 'Amiri',
        adminFontSize:
            (map['adminFontSize'] as num?)?.toDouble() ?? 9.5,
        adminBold: map['adminBold'] as bool? ?? false,
        detailsFont: map['detailsFont']?.toString() ?? 'Amiri',
        detailsFontSize:
            (map['detailsFontSize'] as num?)?.toDouble() ?? 10.0,
        detailsBold: map['detailsBold'] as bool? ?? false,
      );
}

/// إعدادات أسئلة وورقة إجابة الأتمتة الذكية (OMR)
class AutomatedExamConfig {
  int trueFalseCount;
  int mcqCount;
  ChoiceSymbolType choiceSymbolType;

  AutomatedExamConfig({
    this.trueFalseCount = 10,
    this.mcqCount = 10,
    this.choiceSymbolType = ChoiceSymbolType.arabicLetters,
  });

  Map<String, dynamic> toMap() => {
        'trueFalseCount': trueFalseCount,
        'mcqCount': mcqCount,
        'choiceSymbolType': choiceSymbolType.name,
      };

  factory AutomatedExamConfig.fromMap(Map<String, dynamic> map) {
    final rawSymbolType =
        map['choiceSymbolType']?.toString() ?? 'arabicLetters';

    final parsedSymbolType = ChoiceSymbolType.values.firstWhere(
      (e) => e.name == rawSymbolType,
      orElse: () => ChoiceSymbolType.arabicLetters,
    );

    return AutomatedExamConfig(
      trueFalseCount:
          (map['trueFalseCount'] as num?)?.toInt() ?? 10,
      mcqCount: (map['mcqCount'] as num?)?.toInt() ?? 10,
      choiceSymbolType: parsedSymbolType,
    );
  }
}

class ExamModel {
  final String id;

  /// اسم ملف الاختبار، دون المسار الكامل.
  String fileName;

  /// المسار الكامل للملف المحفوظ، إن كان محفوظاً في الجهاز.
  ///
  /// هذا الحقل اختياري للتوافق مع ملفات .exam القديمة.
  /// عند فتح ملف موجود يجب الاحتفاظ بمساره حتى يتم تحديث الملف نفسه.
  String? filePath;

  ExamType examType;
  bool isArabic;
  AutomatedExamConfig automatedConfig;
  DateTime createdAt;
  DateTime updatedAt;
  HeaderModel header;
  List<QuestionModel> questions;
  /// مسارات صور صفحات PDF المستوردة، صفحة مقابل صفحة.
  /// الحقل اختياري للتوافق مع ملفات .exam السابقة.
  List<String> importedPdfPagePaths;
  double targetTotalMarks;

  ExamModel({
    required this.id,
    required this.fileName,
    this.filePath,
    this.examType = ExamType.traditional,
    this.isArabic = true,
    AutomatedExamConfig? automatedConfig,
    required this.createdAt,
    required this.updatedAt,
    required this.header,
    required this.questions,
    List<String>? importedPdfPagePaths,
    this.targetTotalMarks = 50.0,
  }) : importedPdfPagePaths = importedPdfPagePaths ?? <String>[],
       automatedConfig =
            automatedConfig ?? AutomatedExamConfig();

  double get totalMarks =>
      questions.fold(0.0, (sum, item) => sum + item.mark);

  ExamModel copyWith({
    String? newId,
    String? newFileName,
    String? newFilePath,
    bool clearFilePath = false,
    ExamType? newExamType,
    bool? newIsArabic,
    AutomatedExamConfig? newAutomatedConfig,
    HeaderModel? newHeader,
    List<QuestionModel>? newQuestions,
    List<String>? newImportedPdfPagePaths,
    double? newTargetTotalMarks,
  }) {
    return ExamModel(
      id: newId ?? id,
      fileName: newFileName ?? fileName,
      filePath: clearFilePath ? null : (newFilePath ?? filePath),
      examType: newExamType ?? examType,
      isArabic: newIsArabic ?? isArabic,
      automatedConfig: newAutomatedConfig ??
          AutomatedExamConfig.fromMap(automatedConfig.toMap()),
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      header: newHeader ?? HeaderModel.fromMap(header.toMap()),
      questions: newQuestions ??
          questions.map((q) => QuestionModel.fromMap(q.toMap())).toList(),
      importedPdfPagePaths: newImportedPdfPagePaths ?? List<String>.from(importedPdfPagePaths),
      targetTotalMarks:
          newTargetTotalMarks ?? targetTotalMarks,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'fileName': fileName,
        'filePath': filePath,
        'examType': examType.name,
        'isArabic': isArabic,
        'automatedConfig': automatedConfig.toMap(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'header': header.toMap(),
        'questions': questions.map((q) => q.toMap()).toList(),
        'importedPdfPagePaths': importedPdfPagePaths,
        'targetTotalMarks': targetTotalMarks,
      };

  factory ExamModel.fromMap(Map<String, dynamic> map) {
    final rawType =
        map['examType']?.toString() ?? 'traditional';

    final parsedType = ExamType.values.firstWhere(
      (e) => e.name == rawType,
      orElse: () => ExamType.traditional,
    );

    final rawConfig = map['automatedConfig'];
    final rawHeader = map['header'];
    final rawQuestions = map['questions'];
    final rawImportedPdfPages = map['importedPdfPagePaths'];

    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();

      return DateTime.tryParse(value.toString()) ??
          DateTime.now();
    }

    return ExamModel(
      id: map['id']?.toString() ?? '',
      fileName: map['fileName']?.toString() ?? '',
      filePath: map['filePath']?.toString(),
      examType: parsedType,
      isArabic: map['isArabic'] as bool? ?? true,
      automatedConfig: rawConfig is Map
          ? AutomatedExamConfig.fromMap(
              Map<String, dynamic>.from(rawConfig),
            )
          : AutomatedExamConfig(),
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      header: rawHeader is Map
          ? HeaderModel.fromMap(
              Map<String, dynamic>.from(rawHeader),
            )
          : HeaderModel(),
      questions: rawQuestions is List
          ? rawQuestions
              .whereType<Map>()
              .map((item) => QuestionModel.fromMap(
                    Map<String, dynamic>.from(item),
                  ))
              .toList()
          : [],
      importedPdfPagePaths: rawImportedPdfPages is List
          ? rawImportedPdfPages.map((item) => item.toString()).toList()
          : <String>[],
      targetTotalMarks:
          (map['targetTotalMarks'] as num?)?.toDouble() ?? 50.0,
    );
  }

  /// تحويل الاختبار إلى نص JSON واحد صالح للتخزين.
  String toJson() => jsonEncode(toMap());

  /// قراءة ملف JSON قديم أو جديد وإعادة بناء الاختبار.
  factory ExamModel.fromJson(String source) {
    final decoded = jsonDecode(source);

    if (decoded is! Map) {
      throw const FormatException(
        'محتوى ملف الاختبار غير صالح: الجذر ليس كائن JSON.',
      );
    }

    return ExamModel.fromMap(
      Map<String, dynamic>.from(decoded),
    );
  }
}

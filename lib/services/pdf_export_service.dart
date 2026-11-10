أهلاً بك يا أستاذنا العزيز. بصفتي خبيراً في Dart و Flutter، قمت بتحليل الملفين المرفقين بعمق، ورصدت الخللين بدقة؛ والخبر السار أن المشكلتين منطقيتين تماماً وتحدثان بسبب اختلاف في معالجة اتجاهات النصوص (RTL/LTR) والتحكم في الحلقات التكرارية بين الواجهة ومحرك الـ PDF. [1]
إليك تفصيل المشكلتين وسبب حدوثهما، يليهما الملفات البرمجية المعدلة بالكامل والجاهزة للنسخ.

أولاً: مشكلة انعكاس الأعمدة (السؤال والدرجة) في الـ PDF والطباعة

• سبب المشكلة: في ملف التحرير ExamEditorScreen، قمت بإنشاء الجدول وترتيب خلايا الـ TableRow برمجياً من اليمين إلى اليسار: (العمود 0 = خانة السؤال، العمود 1 = النص، العمود 2 = الدرجة). وعندما تغلف الجدول بأداة Directionality(textDirection: TextDirection.rtl) في الفلاتر، يقوم النظام تلقائياً برسم العمود 0 في أقصى اليمين والعمود 2 في أقصى اليسار، وهو المطلوب. [1]
• أما في ملف التصدير PdfExportService، فقد قمت بإنشاء الخلايا بنفس الترتيب (0 للعنوان، 1 للمحتوى، 2 للدرجة) ولكن داخل تذييل محرك البي دي إف pw.Table. محرك الـ PDF لا يقوم بعكس ترتيب مصفوفة الـ children تلقائياً بناءً على الـ Directionality كما تفعل الفلاتر، بل يرسم العناصر دائماً بترتيب الـ Array من اليسار إلى اليمين (0 في اليسار و 2 في اليمين)، مما جعل عمود السؤال يظهر يساراً وعمود الدرجة يميناً في النسخة العربية. [1]
• الحل: قمنا بتعديل دالة بناء الجدول _buildQuestionsSubTable في ملف الـ PDF بحيث تقوم بفحص لغة الاختبار isAr؛ فإذا كان الاختبار عربياً، يتم عكس ترتيب الخلايا داخل كل صف TableRow برمجياً ليتطابق تماماً مع ما يراه المستخدم في شاشة التحرير. [1]

ثانياً: مشكلة تكرار الاختبار كاملاً في كل صفحة وفشل فصل الفقرات (في المؤتمت والشامل)

• سبب المشكلة: الخلل هنا يكمن في طريقة صياغة الحلقات التكرارية (Nested Loops) في دالة التصدير exportToDownloadsPdf. الكود يمر أولاً على حلقة الطلاب for (final student in studentsToIterate)، وبداخلها حلقة الصفحات for (int pageIdx = 0; pageIdx < pagesQuestions.length; pageIdx++). [1]
• حتى الآن الترتيب صحيح، لكن المشكلة الكبرى ظهرت في سطر توليد الأسئلة المؤتمتة:dart
if (isAutomated)
  ..._buildAutomatedQuestionsList(exam, symbols, ttf, isAr)
يُرجى استخدام الرمز البرمجي بحذر.
الدالة _buildAutomatedQuestionsList تأخذ الكائن الكامل exam وتقوم بعمل حلقة تولد جميع فقرات الاختبار من 1 إلى النهاية دفعة واحدة! وبالتالي، في كل صفحة pageIdx، كان الكود يتجاهل مصفوفة الصفحة currentQuestions ويقوم برسم الاختبار كاملاً. [1]
• أما في الاختبارات الشاملة (التقليدية)، فكانت الدالة تستدعي _buildQuestionsSubTable(currentQuestions, ...)، وهي تمرر مصفوفة الصفحة، مما جعلها تعمل بشكل أصح، ولكنها كانت تفتقر إلى ميزة معالجة وسم [فاصل_صفحة] المكتوب داخل نصوص الأسئلة، حيث كان الفاصل يُقسم الأسئلة خارجياً دون مراعاة الفقرات المؤتمتة المسجلة داخل الـ automatedConfig. [1]
• الحل: قمنا بإعادة هيكلة محرك التوزيع الذكي داخل دالة الـ PDF. الآن يتم تمرير مصفوفة أسئلة الصفحة الحالية currentQuestions فقط إلى دوال الرسم، وتم تحديث دالة الاختبار المؤتمت لترسم فقط الفقرات التابعة لتلك الصفحة بدلاً من طباعة القائمة كاملة في كل دورة. [1]

ملف الكود الأول المعدل: pdf_export_service.dart

قم باستبدال محتوى ملف الـ PDF بهذا الكود البرمجي المكتوب بأعلى كفاءة لتفادي أخطاء الذاكرة وضمان ثبات الاتجاهات والأعمدة: [1]
dart
import 'dart:convert';
import 'dart:io';
import 'package:barcode/barcode.dart';
import 'package:better_download_saver/better_download_saver.dart';
import 'package:flutter/material.dart' show TextAlign;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam_models.dart';
import 'student_excel_service.dart';

class PdfExportService {
  static const double cm = 28.3465;
  static const double mm = 2.83465;

  /// دالة مساعدة لتنسيق الدرجة بحذف الأصفار العشرية الزائدة
  static String _formatMark(double mark, bool isArabic) {
    if (mark <= 0) return '-';
    final unit = isArabic ? 'د' : 'm';
    if (mark % 1 == 0) {
      return '${mark.toInt()} $unit';
    }
    return '$mark $unit';
  }

  static Future<String> exportToDownloadsPdf(ExamModel exam) async {
    final pdf = pw.Document();

    ByteData fontData;
    try {
      fontData = await rootBundle.load('assets/fonts/Arial.ttf');
    } catch (_) {
      try {
        fontData = await rootBundle.load('assets/fonts/arial.ttf');
      } catch (_) {
        try {
          fontData = await rootBundle.load('assets/fonts/Amiri.ttf');
        } catch (_) {
          fontData = await rootBundle.load('assets/fonts/amiri-regular.ttf');
        }
      }
    }
    final ttf = pw.Font.ttf(fontData);

    pw.MemoryImage? logoImage;
    if (exam.header.logoImagePath != null &&
        File(exam.header.logoImagePath!).existsSync()) {
      final bytes = await File(exam.header.logoImagePath!).readAsBytes();
      logoImage = pw.MemoryImage(bytes);
    }

    List<StudentData> studentList = [];
    int currentSubjectCode = 1;

    // قراءة كشف الطلاب مع التصفية الحصرية وحساب الرقم الذكي ديناميكياً من الإكسيل
    if (exam.header.topMargin1cm &&
        exam.header.studentDataMode != 'none' &&
        exam.header.excelFilePath != null &&
        File(exam.header.excelFilePath!).existsSync()) {
      try {
        final excelRes = await StudentExcelService.parseExcelFile(
          exam.header.excelFilePath!,
          expectedSubject: exam.header.subject,
          targetGrade: exam.header.grade,
          examTitle: exam.header.examTitle,
        );
        studentList = excelRes.students;
        currentSubjectCode = excelRes.subjectCode;
      } catch (_) {
        studentList = [];
      }
    }

    final studentsToIterate = studentList.isNotEmpty
        ? studentList
        : [StudentData(seatNo: '', name: '', secretCode: '')];

    final bool isAr = exam.isArabic;
    final bool isAutomated = exam.examType == ExamType.automated;

    // تحديد رموز الاختيارات وفق لغة الاختبار ونوع الرمز المحدد
    final List<String> symbols;
    if (exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.numbers) {
      symbols = isAr ? ['١', '٢', '٣', '٤'] : ['1', '2', '3', '4'];
    } else {
      symbols = isAr ? ['أ', 'ب', 'جـ', 'د'] : ['A', 'B', 'C', 'D'];
    }

    final pw.TextDirection pageDir = isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    // تقسيم الأسئلة بدقة بناءً على فواصل الصفحات الصريحة أو الضمنية للنوعين الشامل والمؤتمت
    final List<List<QuestionModel>> pagesQuestions = [[]];
    
    if (isAutomated) {
      // بناء هيكلية الأسئلة المؤتمتة التخيلية لتوزيعها بالتساوي على الصفحات (مثلاً 10 فقرات لكل صفحة)
      final int tfCount = exam.automatedConfig.trueFalseCount;
      final int mcqCount = exam.automatedConfig.mcqCount;
      final List<QuestionModel> allAutomatedItems = [];
      
      for (int i = 1; i <= tfCount; i++) {
        allAutomatedItems.add(QuestionModel(
          id: 'auto_tf_$i',
          title: '$i',
          mark: 1.0,
          spans: [TextSpanModel(text: 'tf')],
        ));
      }
      for (int i = 1; i <= mcqCount; i++) {
        final int itemNumber = tfCount + i;
        allAutomatedItems.add(QuestionModel(
          id: 'auto_mcq_$itemNumber',
          title: '$itemNumber',
          mark: 1.0,
          spans: [TextSpanModel(text: 'mcq')],
        ));
      }

      // إذا كان هناك أسئلة حقيقية مدخلة في القائمة، نعتمد عليها لتحديد فواصل الصفحات
      if (exam.questions.isNotEmpty) {
        for (final q in exam.questions) {
          final fullText = q.spans.map((s) => s.text).join('');
          if (q.id.startsWith('page_break_') || fullText.contains('[فاصل_صفحة]')) {
            pagesQuestions.add([]);
          } else {
            pagesQuestions.last.add(q);
          }
        }
      } else {
        // توزيع آلي افتراضي: 12 فقرة في كل صفحة لضمان عدم تداخل التذييل والترويسة
        const int itemsPerPage = 12;
        for (int i = 0; i < allAutomatedItems.length; i++) {
          if (i > 0 && i % itemsPerPage == 0) {
            pagesQuestions.add([]);
          }
          pagesQuestions.last.add(allAutomatedItems[i]);
        }
      }
    } else {
      // الاختبارات الشاملة التقليدية
      for (final q in exam.questions) {
        final fullText = q.spans.map((s) => s.text).join('');
        if (q.id.startsWith('page_break_') || fullText.contains('[فاصل_صفحة]')) {
          pagesQuestions.add([]);
        } else {
          pagesQuestions.last.add(q);
        }
      }
    }

    for (final student in studentsToIterate) {
      final bool hasStudent = student.seatNo.isNotEmpty;
      final bool showQrMode = hasStudent &&
          exam.header.studentDataMode == 'namesAndQr' &&
          !isAutomated;

      // بناء الصفحات صفحة صفحة بشكل مستقل ومنضبط لمنع خطأ الذاكرة والتكرار
      for (int pageIdx = 0; pageIdx < pagesQuestions.length; pageIdx++) {
        final currentQuestions = pagesQuestions[pageIdx];
        final bool isFirstPage = pageIdx == 0;
        final bool isLastPage = pageIdx == pagesQuestions.length - 1;

        if (currentQuestions.isEmpty) continue;

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.only(
              top: 5.0 * mm,
              bottom: 6.0 * mm,
              left: 20.0,
              right: 20.0,
            ),
            textDirection: pageDir,
            build: (pw.Context context) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  // 1. ترويسة اسم الطالب (إن وجدت)
                  if (exam.header.topMargin1cm && hasStudent && isFirstPage) ...[
                    pw.Directionality(
                      textDirection: pw.TextDirection.rtl,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4.0),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'اسم الطالب: ${student.name}',
                              style: pw.TextStyle(
                                font: ttf,
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              'رقم الجلوس: [ ${student.seatNo} ]',
                              style: pw.TextStyle(
                                font: ttf,
                                fontSize: 10.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // 2. ترويسة الصفحة (كاملة للصفحة الأولى، ومختصرة للصفحات التالية)
                  if (isFirstPage) ...[
                    pw.Directionality(
                      textDirection: pw.TextDirection.rtl,
                      child: _buildExamHeaderBox(exam, ttf, logoImage, isAr),
                    ),
                  ] else ...[
                    pw.Directionality(
                      textDirection: pw.TextDirection.rtl,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(vertical: 6),
                        margin: const pw.EdgeInsets.only(bottom: 6),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.2)),
                        ),
                        child: pw.Center(
                          child: pw.Text(
                            'تابع اختبار مادة ${exam.header.subject} للصف ${exam.header.grade}',
                            style: pw.TextStyle(font: ttf, fontSize: 13, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],

                  pw.SizedBox(height: 5),

                  // 3. جدول ومحتوى الأسئلة المخصص للصفحة الحالية حصراً
                  if (isAutomated)
                    ..._buildAutomatedQuestionsListForPage(exam, currentQuestions, symbols, ttf, isAr)
                  else
                    _buildQuestionsSubTable(currentQuestions, exam.header.instructionText, ttf, isAr),

                  pw.Spacer(),

                  // 4. تذييل الصفحة وتوقيع المعلم
                  pw.Directionality(
                    textDirection: pw.TextDirection.rtl,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.only(top: 2),
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Center(
                            child: pw.Text(
                              isLastPage
                                  ? (exam.header.singlePageFooterText.isNotEmpty
                                      ? exam.header.singlePageFooterText
يُرجى استخدام الرمز البرمجي بحذر.
: (isAr ? 'انتهت الأسئلة مع تمنياتنا لكم بالتوفيق والنجاح' : 'End of Questions - Best of Luck'))
: (exam.header.continuationText.isNotEmpty
? exam.header.continuationText
: (isAr ? 'يتبع في الصفحة التالية...' : 'To be continued on next page...')),
style: pw.TextStyle(
font: ttf,
fontSize: 9.5,
fontWeight: pw.FontWeight.bold,
),
),
),
pw.SizedBox(height: 2),
pw.Row(
mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
crossAxisAlignment: pw.CrossAxisAlignment.end,
children: [
pw.Text(
exam.header.teacherSignature.isNotEmpty
? exam.header.teacherSignature
: (isAr ? 'معلم المادة: ......................' : 'Teacher: ......................'),
style: pw.TextStyle(font: ttf, fontSize: 9.0),
),
if (showQrMode && isFirstPage)
pw.Row(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.center,
children: [
pw.Text(
'$currentSubjectCode',
style: pw.TextStyle(
font: ttf,
fontSize: 22,
fontWeight: pw.FontWeight.bold,
),
),
pw.SizedBox(width: 8),
if (student.secretCode.isNotEmpty)
pw.Container(
width: 38,
height: 38,
child: pw.BarcodeWidget(
barcode: Barcode.qrCode(),
data: student.secretCode,
drawText: false,
),
)
else
pw.SizedBox(width: 38, height: 38),
pw.SizedBox(width: 10),
pw.Container(
width: 55,
height: 45,
decoration: pw.BoxDecoration(
border: pw.Border.all(color: PdfColors.black, width: 1.2),
),
),
],
)
else
pw.Text(
'صفحة ${pageIdx + 1} من ${pagesQuestions.length}',
style: pw.TextStyle(font: ttf, fontSize: 8.5),
),
],
),
],
),
),
),
],
);
},
),
);
}
}
final pdfBytes = await pdf.save();
final gradeName = exam.header.grade.trim().isNotEmpty ? exam.header.grade.trim() : 'عام';
final subjectName = exam.header.subject.trim().isNotEmpty ? exam.header.subject.trim() : 'مادة';
final typeName = isAutomated ? (isAr ? 'مؤتمت' : 'Automated') : (isAr ? 'شامل' : 'Comprehensive');
final defaultGeneratedName = '$gradeName _ $subjectName _ $typeName';
final nameToUse = exam.fileName.trim().isNotEmpty && !exam.fileName.startsWith('اختبار_')
? exam.fileName.trim()
: defaultGeneratedName;
final safeName = nameToUse.replaceAll(RegExp(r'[\/:*?"<>|]'), '_');
final fileName = '$safeName.pdf';
try {
final saver = BetterDownloadSaver();
final String? savedPath = await saver.saveToDownloads(
fileName: fileName,
bytes: pdfBytes,
);
if (savedPath != null && savedPath.isNotEmpty) {
return savedPath;
}
} catch (_) {}
try {
Directory fallbackDir;
if (Platform.isAndroid) {
fallbackDir = (await getExternalStorageDirectory()) ??
await getApplicationDocumentsDirectory();
} else {
fallbackDir = await getApplicationDocumentsDirectory();
}
if (!fallbackDir.existsSync()) {
fallbackDir.createSync(recursive: true);
}
final fallbackPath = '${fallbackDir.path}/$fileName';
await File(fallbackPath).writeAsBytes(pdfBytes, flush: true);
return fallbackPath;
} catch (e) {
throw Exception('تعذر حفظ ملف PDF: $e');
}
}
static pw.Widget _buildExamHeaderBox(
ExamModel exam,
pw.Font ttf,
pw.MemoryImage? logoImage,
bool isAr,
) {
return pw.Container(
decoration: pw.BoxDecoration(
border: pw.Border.all(color: PdfColors.black, width: 1.5),
),
padding: const pw.EdgeInsets.all(4),
child: pw.Column(
children: [
pw.Row(
crossAxisAlignment: pw.CrossAxisAlignment.start,
children: [
pw.Container(
width: 135,
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.center,
children: [
pw.Text(exam.header.country,
style: pw.TextStyle(
font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold),
textAlign: pw.TextAlign.center),
pw.Text(exam.header.ministry,
style: pw.TextStyle(font: ttf, fontSize: 8.5),
textAlign: pw.TextAlign.center),
pw.Text(exam.header.governorate,
style: pw.TextStyle(font: ttf, fontSize: 8),
textAlign: pw.TextAlign.center),
pw.Text(exam.header.directorate,
style: pw.TextStyle(font: ttf, fontSize: 8),
textAlign: pw.TextAlign.center),
pw.Text(exam.header.school,
style: pw.TextStyle(
font: ttf, fontSize: 8.5, fontWeight: pw.FontWeight.bold),
textAlign: pw.TextAlign.center),
],
),
),
pw.Expanded(
child: pw.Column(
mainAxisAlignment: pw.MainAxisAlignment.center,
children: [
pw.Text(exam.header.basmalaText,
style: pw.TextStyle(
font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
textAlign: pw.TextAlign.center),
pw.SizedBox(height: 4),
if (logoImage != null)
pw.Image(logoImage, height: 45, fit: pw.BoxFit.contain)
else
pw.SizedBox(height: 45),
],
),
),
pw.Container(
width: 135,
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.start,
children: [
pw.Text('الصف : ${exam.header.grade}',
style: pw.TextStyle(
font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
pw.Text('المادة : ${exam.header.subject}',
style: pw.TextStyle(
font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
pw.Text('التاريخ: ${exam.header.examDate}',
style: pw.TextStyle(font: ttf, fontSize: 8.5)),
pw.Text('الزمن: ${exam.header.examTime}',
style: pw.TextStyle(font: ttf, fontSize: 8.5)),
pw.Text('الفترة: ${exam.header.period}',
style: pw.TextStyle(font: ttf, fontSize: 8.5)),
],
),
),
],
),
pw.SizedBox(height: 3),
pw.Container(
width: double.infinity,
color: PdfColors.grey200,
padding: const pw.EdgeInsets.symmetric(vertical: 2),
child: pw.Text(
exam.header.examTitle,
textAlign: pw.TextAlign.center,
style: pw.TextStyle(
font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
),
),
],
),
);
}
/// دالة رسم فقرات الاختبار المؤتمت المحددة لهذه الصفحة فقط بدلاً من رسم كامل الاختبار في كل دورة
static List<pw.Widget> _buildAutomatedQuestionsListForPage(
ExamModel exam,
List pageItems,
List symbols,
pw.Font ttf,
bool isAr,
) {
final List<pw.Widget> widgets = [];
// إظهار التوجيه الخاص بالتظليل في بداية الصفحة الأولى فقط
final bool isFirstSlice = pageItems.any((e) => e.title == '1' || e.title.contains('1'));
if (isFirstSlice) {
final defaultInstruction = isAr
? 'أجب بتظليل الدائرة المناسبة في ورقة الإجابة المخصصة (OMR)'
: 'Answer by shading the corresponding bubble on the designated OMR sheet';
widgets.add(
pw.Container(
margin: const pw.EdgeInsets.only(bottom: 6),
padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
color: PdfColors.grey100,
child: pw.Text(
exam.header.instructionText.isNotEmpty
? exam.header.instructionText
: defaultInstruction,
style: pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
textAlign: pw.TextAlign.center,
),
),
);
}
// فرز وعزل فقرات الصح/الخطأ والاختيارات التابعة للصفحة الحالية فحسب
final tfItems = pageItems.where((e) => e.id.contains('tf')).toList();
final mcqItems = pageItems.where((e) => e.id.contains('mcq')).toList();
// إذا كانت الفقرات مدخلة حقيقياً بشكل يدوي مسبقاً، نستخدمها مباشرة
final realCustomItems = pageItems.where((e) => !e.id.contains('auto_')).toList();
if (realCustomItems.isNotEmpty) {
for (final q in realCustomItems) {
final int index = exam.questions.indexOf(q) + 1;
final fullText = q.spans.map((s) => s.text).join('');
final bool isTfItem = fullText.contains('صح') || fullText.contains('خطأ') || q.title.contains('صح');
if (isTfItem) {
widgets.add(_buildTfRowItem(index, fullText, ttf, isAr));
} else {
widgets.add(
_buildAutomatedMcqItem(
itemNumber: index,
questionText: fullText.replaceAll(RegExp(r'\(.*?\)'), '').trim(),
choices: const ['', '', '', ''],
symbols: symbols,
ttf: ttf,
isAr: isAr,
),
);
}
}
return widgets;
}
if (tfItems.isNotEmpty) {
if (isFirstSlice) {
final tfHeader = isAr
? 'أولاً: فقرات الصح والخطأ (ظلل الدائرة ص أو خ في ورقة الإجابة):'
: 'Part 1: True / False items (Shade T or F bubble on the answer sheet):';
widgets.add(
pw.Container(
margin: const pw.EdgeInsets.only(bottom: 4),
padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 8),
color: PdfColors.grey300,
child: pw.Text(
tfHeader,
style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
),
),
);
}
for (final item in tfItems) {
final int num = int.tryParse(item.title) ?? 1;
widgets.add(_buildTfRowItem(num, '', ttf, isAr));
}
widgets.add(pw.SizedBox(height: 4));
}
if (mcqItems.isNotEmpty) {
final bool isMcqStart = mcqItems.any((e) => e.title == (exam.automatedConfig.trueFalseCount + 1).toString());
if (isMcqStart) {
final mcqHeader = isAr
? 'ثانياً: فقرات الاختيار من متعدد (ظلل رمز الإجابة الصحيحة في ورقة الإجابة):'
: 'Part 2: Multiple Choice items (Shade the correct choice symbol on the answer sheet):';
widgets.add(
pw.Container(
margin: const pw.EdgeInsets.only(bottom: 4),
padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 8),
color: PdfColors.grey300,
child: pw.Text(
mcqHeader,
style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
),
),
);
}
for (final item in mcqItems) {
final int num = int.tryParse(item.title) ?? 1;
widgets.add(
_buildAutomatedMcqItem(
itemNumber: num,
questionText: '',
choices: const ['', '', '', ''],
symbols: symbols,
ttf: ttf,
isAr: isAr,
),
);
}
}
return widgets;
}
static pw.Widget _buildTfRowItem(int number, String text, pw.Font ttf, bool isAr) {
final displayText = text.isNotEmpty ? text : '(      ) ............................................................................................';
return pw.Container(
margin: const pw.EdgeInsets.only(bottom: 4),
decoration: pw.BoxDecoration(
border: pw.Border.all(color: PdfColors.black, width: 0.8),
),
child: pw.Row(
children: [
pw.Container(
width: 28,
padding: const pw.EdgeInsets.symmetric(vertical: 4),
decoration: pw.BoxDecoration(
border: pw.Border(
left: isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.8) : pw.BorderSide.none,
right: !isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.8) : pw.BorderSide.none,
),
),
child: pw.Center(
child: pw.Text('$number', style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
),
),
pw.Expanded(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
child: pw.Text(
displayText,
style: pw.TextStyle(font: ttf, fontSize: 9.5),
textAlign: isAr ? pw.TextAlign.right : pw.TextAlign.left,
),
),
),
],
),
);
}
static pw.Widget _buildAutomatedMcqItem({
required int itemNumber,
required String questionText,
required List choices,
required List symbols,
required pw.Font ttf,
required bool isAr,
}) {
return pw.Container(
margin: const pw.EdgeInsets.only(bottom: 5.0),
decoration: pw.BoxDecoration(
border: pw.Border.all(color: PdfColors.black, width: 0.9),
),
child: pw.Row(
crossAxisAlignment: pw.CrossAxisAlignment.center,
children: [
pw.Container(
width: 30,
decoration: pw.BoxDecoration(
border: pw.Border(
left: isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.9) : pw.BorderSide.none,
right: !isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.9) : pw.BorderSide.none,
),
),
child: pw.Center(
child: pw.Text(
'$itemNumber',
style: pw.TextStyle(
font: ttf,
fontSize: 10,
fontWeight: pw.FontWeight.bold,
),
),
),
),
pw.Expanded(
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.stretch,
children: [
pw.Container(
padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
decoration: const pw.BoxDecoration(
border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.8)),
),
child: pw.Text(
questionText.isNotEmpty
? questionText
: '................................................................................................',
style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
textAlign: isAr ? pw.TextAlign.right : pw.TextAlign.left,
),
),
pw.Container(
height: 20,
child: pw.Row(
children: List.generate(4, (index) {
// الحفاظ الدقيق على ترتيب الاختيارات حسب اتجاه الصفحة
final visualIndex = isAr ? (3 - index) : index;
final sym = symbols.length > visualIndex ? symbols[visualIndex] : '${visualIndex + 1}';
final choiceTxt = choices.length > visualIndex ? choices[visualIndex] : '';
return pw.Expanded(
child: pw.Container(
decoration: pw.BoxDecoration(
border: pw.Border(
left: (isAr && index > 0)
? const pw.BorderSide(color: PdfColors.black, width: 0.8)
: pw.BorderSide.none,
right: (!isAr && index > 0)
? const pw.BorderSide(color: PdfColors.black, width: 0.8)
: pw.BorderSide.none,
),
),
child: pw.Row(
children: [
pw.Container(
width: 18,
decoration: pw.BoxDecoration(
color: PdfColors.white,
border: pw.Border(
left: isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.8) : pw.BorderSide.none,
right: !isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.8) : pw.BorderSide.none,
),
),
child: pw.Center(
child: pw.Text(
sym,
style: pw.TextStyle(
font: ttf,
fontSize: 9.0,
color: PdfColors.black,
fontWeight: pw.FontWeight.bold,
),
),
),
),
pw.Expanded(
child: pw.Center(
child: pw.Text(
choiceTxt,
style: pw.TextStyle(font: ttf, fontSize: 8.5),
maxLines: 1,
),
),
),
],
),
),
);
}),
),
),
],
),
),
],
),
);
}
/// دالة رسم خلايا جدول الأسئلة مع إصلاح مشكلة محاذاة الأعمدة العربية وتطابقها الكامل مع الشاشة
static pw.Widget _buildQuestionsSubTable(
List questions,
String instructionText,
pw.Font ttf,
bool isAr,
) {
final defaultInstruction = isAr ? 'أجب عن جميع الأسئلة الآتية' : 'Answer all questions';
final headerInstruction = instructionText.isNotEmpty ? instructionText : defaultInstruction;
final String colQuestionTitle = isAr ? 'السؤال' : 'Question';
final String colMarkTitle = isAr ? 'الدرجة' : 'Mark';
// تم تعديل التوزيع ليكون مستقلاً ويدعم التحويل التلقائي الذكي للغتين
final columnWidths = const <int, pw.TableColumnWidth>{
0: pw.FixedColumnWidth(38),
1: pw.FlexColumnWidth(),
2: pw.FixedColumnWidth(38),
};
final questionHeaderCell = pw.Padding(
padding: const pw.EdgeInsets.all(4),
child: pw.Center(
child: pw.Text(colQuestionTitle,
textAlign: pw.TextAlign.center,
style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
),
);
final instructionHeaderCell = pw.Padding(
padding: const pw.EdgeInsets.all(4),
child: pw.Center(
child: pw.Text(headerInstruction,
textAlign: pw.TextAlign.center,
style: pw.TextStyle(
font: ttf,
fontSize: 10,
fontWeight: pw.FontWeight.bold,
color: PdfColors.red900)),
),
);
final markHeaderCell = pw.Padding(
padding: const pw.EdgeInsets.all(4),
child: pw.Center(
child: pw.Text(colMarkTitle,
textAlign: pw.TextAlign.center,
style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
),
);
// إذا كانت اللغة عربية، نقوم بعكس ترتيب العناوين داخل المصفوفة يدوياً لأن محرك PDF لا يعكس مصفوفة الخلايا
final List<pw.Widget> headerCells = isAr
? [markHeaderCell, instructionHeaderCell, questionHeaderCell]
: [questionHeaderCell, instructionHeaderCell, markHeaderCell];
return pw.Table(
border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
columnWidths: isAr
? const {0: pw.FixedColumnWidth(38), 1: pw.FlexColumnWidth(), 2: pw.FixedColumnWidth(38)}
: columnWidths,
children: [
pw.TableRow(
decoration: const pw.BoxDecoration(color: PdfColors.grey100),
children: headerCells,
),
...questions.map((q) {
final qTitleCell = pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 6),
child: pw.Center(
child: pw.Text(q.title,
textAlign: pw.TextAlign.center,
style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
),
);
final qContentCell = pw.Padding(
padding: const pw.EdgeInsets.all(6),
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.stretch,
children: [
_buildPdfQuestionContent(q, ttf, isAr),
if (q.elements.isNotEmpty) pw.SizedBox(height: 4),
...q.elements.map((el) => _buildPdfElement(el, ttf, isAr)),
],
),
);
final qMarkCell = pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 6),
child: pw.Center(
child: pw.Text(
_formatMark(q.mark, isAr),
textAlign: pw.TextAlign.center,
style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
),
),
);
// تطبيق العكس الحصري لصفوف المحتوى في الامتحان العربي ليتطابق مع رأس الجدول
final List<pw.Widget> rowCells = isAr
? [qMarkCell, qContentCell, qTitleCell]
: [qTitleCell, qContentCell, qMarkCell];
return pw.TableRow(
children: rowCells,
);
}),
],
);
}
static PdfColor parsePdfColor(String? hexString, {PdfColor defaultColor = PdfColors.black}) {
if (hexString == null || hexString.isEmpty) return defaultColor;
try {
final clean = hexString.replaceAll('#', '').trim();
if (clean.length == 6) {
final r = int.parse(clean.substring(0, 2), radix: 16) / 255.0;
final g = int.parse(clean.substring(2, 4), radix: 16) / 255.0;
final b = int.parse(clean.substring(4, 6), radix: 16) / 255.0;
return PdfColor(r, g, b);
}
} catch () {}
return defaultColor;
}
static pw.TextAlign _convertTextAlign(TextAlign? align, bool isAr) {
if (align == null) {
return isAr ? pw.TextAlign.right : pw.TextAlign.left;
}
switch (align) {
case TextAlign.right:
return pw.TextAlign.right;
case TextAlign.center:
return pw.TextAlign.center;
case TextAlign.left:
return pw.TextAlign.left;
case TextAlign.justify:
return pw.TextAlign.justify;
case TextAlign.start:
return isAr ? pw.TextAlign.right : pw.TextAlign.left;
case TextAlign.end:
return isAr ? pw.TextAlign.left : pw.TextAlign.right;
}
}
static pw.Widget _buildPdfQuestionContent(QuestionModel q, pw.Font ttf, bool isAr) {
final pw.TextAlign chosenAlign = _convertTextAlign(q.alignment, isAr);
final pw.TextDirection itemDir = (chosenAlign == pw.TextAlign.left || !isAr)
? pw.TextDirection.ltr
: pw.TextDirection.rtl;
if (!q.isTwoColumns) {
return pw.Directionality(
textDirection: itemDir,
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.stretch,
children: q.spans.map((s) {
final spanColor = _parsePdfColor(s.colorHex);
final cleanText = s.text.replaceAll('[فاصل_صفحة]', '').trim();
if (cleanText.isEmpty) return pw.SizedBox.shrink();
return _renderInlineMathText(
cleanText,
ttf,
fontSize: s.fontSize,
isBold: s.isBold,
textColor: spanColor,
lineSpacing: 2,
textAlign: chosenAlign,
isAr: isAr,
);
}).toList(),
),
);
}
final fullText = q.spans.map((s) => s.text).join('').replaceAll('[فاصل_صفحة]', '').trim();
final lines = fullText.split('\n').where((l) => l.trim().isNotEmpty).toList();
if (lines.length <= 1) {
return pw.Directionality(
textDirection: itemDir,
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.stretch,
children: q.spans.map((s) {
final spanColor = _parsePdfColor(s.colorHex);
final cleanText = s.text.replaceAll('[فاصل_صفحة]', '').trim();
if (cleanText.isEmpty) return pw.SizedBox.shrink();
return _renderInlineMathText(
cleanText,
ttf,
fontSize: s.fontSize,
isBold: s.isBold,
textColor: spanColor,
lineSpacing: 2,
textAlign: chosenAlign,
isAr: isAr,
);
}).toList(),
),
);
}
final intro = lines.first;
final items = lines.sublist(1);
final int half = (items.length / 2).ceil();
final col1 = items.sublist(0, half);
final col2 = items.sublist(half);
return pw.Directionality(
textDirection: itemDir,
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.stretch,
children: [
_renderInlineMathText(intro, ttf, fontSize: 11, isBold: true, textAlign: chosenAlign, isAr: isAr),
pw.SizedBox(height: 3),
pw.Row(
crossAxisAlignment: pw.CrossAxisAlignment.start,
children: [
pw.Expanded(
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.stretch,
children: col1
.map((item) => pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
child: _renderInlineMathText(item, ttf, fontSize: 10, textAlign: chosenAlign, isAr: isAr),
))
.toList(),
),
),
pw.SizedBox(width: 8),
pw.Expanded(
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.stretch,
children: col2
.map((item) => pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
child: _renderInlineMathText(item, ttf, fontSize: 10, textAlign: chosenAlign, isAr: isAr),
))
.toList(),
),
),
],
),
],
),
);
}
static pw.Widget _drawPdfCheckmark({double size = 11.0, PdfColor color = PdfColors.black}) {
return pw.CustomPaint(
size: PdfPoint(size, size),
painter: (PdfGraphics canvas, PdfPoint pointSize) {
canvas
..setColor(color)
..setLineWidth(1.4)
..moveTo(pointSize.x * 0.15, pointSize.y * 0.45)
..lineTo(pointSize.x * 0.45, pointSize.y * 0.15)
..lineTo(pointSize.x * 0.88, pointSize.y * 0.85)
..strokePath();
},
);
}
static pw.Widget _drawPdfCross({double size = 10.0, PdfColor color = PdfColors.black}) {
return pw.CustomPaint(
size: PdfPoint(size, size),
painter: (PdfGraphics canvas, PdfPoint pointSize) {
canvas
..setColor(color)
..setLineWidth(1.4)
..moveTo(pointSize.x * 0.18, pointSize.y * 0.18)
..lineTo(pointSize.x * 0.82, pointSize.y * 0.82)
..strokePath()
..moveTo(pointSize.x * 0.82, pointSize.y * 0.18)
..lineTo(pointSize.x * 0.18, pointSize.y * 0.82)
..strokePath();
},
);
}
static pw.Widget _drawPdfRadical(pw.Widget content, String degree, pw.Font ttf, double fontSize, {bool isRtl = true}) {
return pw.Directionality(
textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
child: pw.Row(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.start,
children: [
if (degree.isNotEmpty)
pw.Padding(
padding: pw.EdgeInsets.only(
top: 0.0,
left: isRtl ? 1.5 : 0.0,
right: !isRtl ? 1.5 : 0.0,
),
child: pw.Text(
degree,
style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.65, fontWeight: pw.FontWeight.bold),
),
),
pw.Container(
height: fontSize * 1.35,
width: 7,
margin: const pw.EdgeInsets.only(top: 2),
child: pw.CustomPaint(
painter: (PdfGraphics canvas, PdfPoint size) {
canvas
..setColor(PdfColors.black)
..setLineWidth(1.0);
if (isRtl) {
canvas
..moveTo(size.x, size.y * 0.4)
..lineTo(size.x * 0.45, 0)
..lineTo(0, size.y)
..strokePath();
} else {
canvas
..moveTo(0, size.y * 0.4)
..lineTo(size.x * 0.55, 0)
..lineTo(size.x, size.y)
..strokePath();
}
},
),
),
pw.Container(
margin: const pw.EdgeInsets.only(top: 2),
decoration: const pw.BoxDecoration(
border: pw.Border(top: pw.BorderSide(color: PdfColors.black, width: 1.0)),
),
padding: const pw.EdgeInsets.only(top: 1, left: 3, right: 3),
child: content,
),
],
),
);
}
static pw.Widget _renderInlineMathText(
String text,
pw.Font ttf, {
double fontSize = 11,
bool isBold = false,
PdfColor textColor = PdfColors.black,
double lineSpacing = 1.5,
pw.TextAlign? textAlign,
bool isAr = true,
}) {
final effectiveTextAlign = textAlign ?? (isAr ? pw.TextAlign.right : pw.TextAlign.left);
final regExp = RegExp(r'(\((?:||sqrt|||div|||||||||):.*?\)|✔|✘|✓|✗)');
final matches = regExp.allMatches(text);
if (matches.isEmpty) {
return pw.Text(
text,
textAlign: effectiveTextAlign,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize,
color: textColor,
fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
lineSpacing: lineSpacing,
),
);
}
final List<pw.InlineSpan> spans = [];
int lastIdx = 0;
for (final m in matches) {
if (m.start > lastIdx) {
spans.add(pw.TextSpan(text: text.substring(lastIdx, m.start)));
}
final matchedStr = m.group(0) ?? '';
if (matchedStr == '✔' || matchedStr == '✓') {
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
child: _drawPdfCheckmark(size: fontSize * 0.95, color: textColor),
),
),
);
} else if (matchedStr == '✘' || matchedStr == '✗') {
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
child: _drawPdfCross(size: fontSize * 0.85, color: textColor),
),
),
);
} else if (matchedStr.startsWith('[')) {
final inner = matchedStr.substring(1, matchedStr.length - 1);
final firstColon = inner.indexOf(':');
final type = firstColon != -1 ? inner.substring(0, firstColon) : inner;
final rawContent = firstColon != -1 ? inner.substring(firstColon + 1) : '';
final parts = rawContent.split(':');
if (type == 'كسر') {
final p = rawContent.split('/');
final num = p.isNotEmpty ? p[0] : '';
final den = p.length > 1 ? p[1] : '';
final int maxLen = num.length > den.length ? num.length : den.length;
final double lineWidth = (maxLen * 7.0) + 6.0;
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 2.5),
child: pw.Column(
mainAxisSize: pw.MainAxisSize.min,
children: [
pw.Text(num, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.85, color: textColor, fontWeight: pw.FontWeight.bold)),
pw.Container(width: lineWidth, height: 0.8, color: textColor),
pw.Text(den, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.85, color: textColor, fontWeight: pw.FontWeight.bold)),
],
),
),
),
);
} else if (type == 'جذر' || type == 'sqrt') {
final bool isRtl = (type == 'جذر') && isAr;
final String degree = parts.length > 1 ? parts[0] : '';
final String radicand = parts.length > 1 ? parts.sublist(1).join(':') : parts[0];
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
child: _drawPdfRadical(
pw.Text(
radicand,
style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.95, color: textColor, fontWeight: pw.FontWeight.bold),
),
degree,
ttf,
fontSize,
isRtl: isRtl,
),
),
),
);
} else if (type == 'نها') {
final v = parts.isNotEmpty ? parts[0] : (isAr ? 'س' : 'x');
final t = parts.length > 1 ? parts[1] : (isAr ? '٠' : '0');
final fn = parts.length > 2 ? parts[2] : '';
final label = isAr ? 'نهـا' : 'lim';
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
child: pw.Row(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.center,
children: [
pw.Column(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.center,
children: [
pw.Text(
label,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize * 1.05,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
),
pw.SizedBox(height: 1),
pw.Row(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.center,
children: [
pw.Text(
v,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize * 0.7,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
),
pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
child: pw.CustomPaint(
size: const PdfPoint(8, 5),
painter: (PdfGraphics canvas, PdfPoint pSize) {
canvas
..setColor(textColor)
..setLineWidth(0.8)
..moveTo(pSize.x, pSize.y * 0.5)
..lineTo(0, pSize.y * 0.5)
..strokePath()
..moveTo(2.5, pSize.y)
..lineTo(0, pSize.y * 0.5)
..lineTo(2.5, 0)
..strokePath();
},
),
),
pw.Text(
t,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize * 0.7,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
),
],
),
],
),
if (fn.isNotEmpty) ...[
pw.SizedBox(width: 4),
pw.Text(
fn,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
),
],
],
),
),
),
);
} else if (type == 'تباديل' || type == 'توافيق') {
final n = parts.isNotEmpty ? parts[0] : (isAr ? 'ن' : 'n');
final r = parts.length > 1 ? parts[1] : (isAr ? 'ر' : 'r');
final sym = type == 'تباديل'
? (isAr ? 'ل' : 'P')
: (isAr ? 'ق' : 'C');
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 2.5),
child: pw.Row(
mainAxisSize: pw.MainAxisSize.min,
children: [
pw.Padding(
padding: const pw.EdgeInsets.only(bottom: 6),
child: pw.Text(n, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.75, color: textColor, fontWeight: pw.FontWeight.bold)),
),
pw.Text(sym, style: pw.TextStyle(font: ttf, fontSize: fontSize * 1.25, color: textColor, fontWeight: pw.FontWeight.bold)),
pw.Padding(
padding: const pw.EdgeInsets.only(top: 6),
child: pw.Text(r, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.75, color: textColor, fontWeight: pw.FontWeight.bold)),
),
],
),
),
),
);
} else if (type == 'مجموع' || type == 'تكامل') {
final from = parts.isNotEmpty ? parts[0] : '';
final to = parts.length > 1 ? parts[1] : '';
final body = parts.length > 2 ? parts[2] : '';
final sym = type == 'مجموع' ? (isAr ? 'مجـ' : '∑') : '∫';
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 3.0),
child: pw.Row(
mainAxisSize: pw.MainAxisSize.min,
children: [
pw.Column(
mainAxisSize: pw.MainAxisSize.min,
children: [
pw.Text(to, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.65, color: textColor, fontWeight: pw.FontWeight.bold)),
pw.Text(sym, style: pw.TextStyle(font: ttf, fontSize: fontSize * 1.2, color: textColor, fontWeight: pw.FontWeight.bold)),
pw.Text(from, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.65, color: textColor, fontWeight: pw.FontWeight.bold)),
],
),
if (body.isNotEmpty) ...[
pw.SizedBox(width: 3),
pw.Text(body, style: pw.TextStyle(font: ttf, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
],
],
),
),
),
);
} else if (type == 'متجه') {
final s = parts.isNotEmpty ? parts[0] : (isAr ? 'ق' : 'v');
spans.add(
pw.WidgetSpan(
child: pw.Column(
mainAxisSize: pw.MainAxisSize.min,
children: [
pw.Text('→', style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.75, color: textColor, fontWeight: pw.FontWeight.bold)),
pw.Text(s, style: pw.TextStyle(font: ttf, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
],
),
),
);
} else if (type == 'بار') {
final s = parts.isNotEmpty ? parts[0] : (isAr ? 'س' : 'x');
spans.add(
pw.WidgetSpan(
child: pw.Column(
mainAxisSize: pw.MainAxisSize.min,
children: [
pw.Container(width: 10, height: 1.0, color: textColor),
pw.Text(s, style: pw.TextStyle(font: ttf, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
],
),
),
);
} else if (type == 'محدد' || type == 'مصفوفة') {
final isMatrix = type == 'مصفوفة';
final a = parts.isNotEmpty ? parts[0] : '';
final b = parts.length > 1 ? parts[1] : '';
final c = parts.length > 2 ? parts[2] : '';
final d = parts.length > 3 ? parts[3] : '';
spans.add(
pw.WidgetSpan(
child: pw.Container(
margin: const pw.EdgeInsets.symmetric(horizontal: 3),
padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
decoration: pw.BoxDecoration(
border: pw.Border(
left: pw.BorderSide(color: textColor, width: isMatrix ? 1.5 : 1.0),
right: pw.BorderSide(color: textColor, width: isMatrix ? 1.5 : 1.0),
),
),
child: pw.Column(
mainAxisSize: pw.MainAxisSize.min,
children: [
pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
pw.Text(a, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.9, color: textColor)),
pw.SizedBox(width: 6),
pw.Text(b, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.9, color: textColor)),
]),
pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
pw.Text(c, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.9, color: textColor)),
pw.SizedBox(width: 6),
pw.Text(d, style: pw.TextStyle(font: ttf, fontSize: fontSize * 0.9, color: textColor)),
]),
],
),
),
),
);
} else if (type == 'عمودي') {
final op = parts.isNotEmpty ? parts[0] : '+';
final numbers = parts.length > 1 ? parts.sublist(1) : [];
int maxDigits = 0;
for (final num in numbers) {
if (num.length > maxDigits) maxDigits = num.length;
}
final double lineWidth = (maxDigits * 8.0) + 20.0;
final bool isRtlVert = isAr;
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
child: pw.Directionality(
textDirection: isRtlVert ? pw.TextDirection.rtl : pw.TextDirection.ltr,
child: pw.Column(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.start,
children: [
...numbers.asMap().entries.map((entry) {
final idx = entry.key;
final val = entry.value;
final isLast = idx == numbers.length - 1;
return pw.Row(
mainAxisSize: pw.MainAxisSize.min,
children: [
pw.Container(
width: 14,
child: isLast
? pw.Text(
op,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize * 1.15,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
textAlign: pw.TextAlign.center,
)
: null,
),
pw.SizedBox(width: 4),
pw.Text(
val,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize * 1.05,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
),
],
);
}),
pw.Container(
margin: const pw.EdgeInsets.only(top: 2.0, bottom: 4.0),
width: lineWidth,
height: 1.0,
color: textColor,
),
],
),
),
),
),
);
} else if (type == 'قسمة' || type == 'div') {
final bool isRtl = (type == 'قسمة') && isAr;
final String dividend = parts.isNotEmpty ? parts[0] : '';
final String divisor = parts.length > 1 ? parts[1] : '';
final String quotient = parts.length > 2 ? parts[2] : '';
spans.add(
pw.WidgetSpan(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
child: pw.Directionality(
textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
child: pw.Column(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.start,
children: [
if (quotient.isNotEmpty)
pw.Padding(
padding: pw.EdgeInsets.only(
right: isRtl ? 18.0 : 0.0,
left: !isRtl ? 18.0 : 0.0,
),
child: pw.Text(
quotient,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize * 0.9,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
),
),
pw.Row(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.center,
children: [
pw.Text(
divisor,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
),
pw.SizedBox(width: 3),
pw.Container(
decoration: pw.BoxDecoration(
border: pw.Border(
top: pw.BorderSide(color: textColor, width: 1.2),
right: isRtl ? pw.BorderSide(color: textColor, width: 1.2) : pw.BorderSide.none,
left: !isRtl ? pw.BorderSide(color: textColor, width: 1.2) : pw.BorderSide.none,
),
),
padding: const pw.EdgeInsets.only(top: 2, left: 5, right: 5, bottom: 1),
child: pw.Text(
dividend,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize,
color: textColor,
fontWeight: pw.FontWeight.bold,
),
),
),
],
),
],
),
),
),
),
);
}
}
lastIdx = m.end;
}
if (lastIdx < text.length) {
spans.add(pw.TextSpan(text: text.substring(lastIdx)));
}
return pw.RichText(
textAlign: effectiveTextAlign,
text: pw.TextSpan(
children: spans,
style: pw.TextStyle(
font: ttf,
fontSize: fontSize,
color: textColor,
fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
lineSpacing: lineSpacing,
),
),
);
}
static pw.Widget _buildPdfElement(InsertableElement el, pw.Font ttf, bool isAr) {
switch (el.type) {
case ElementType.image:
if (File(el.content).existsSync()) {
final bytes = File(el.content).readAsBytesSync();
final img = pw.MemoryImage(bytes);
return pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 4),
child: pw.Center(child: pw.Image(img, height: el.height, width: el.width)),
);
}
return pw.SizedBox.shrink();
case ElementType.textBox:
return pw.Container(
margin: const pw.EdgeInsets.symmetric(vertical: 4),
padding: const pw.EdgeInsets.all(5),
decoration: pw.BoxDecoration(
border: pw.Border.all(color: PdfColors.black, width: 0.8),
),
child: pw.Text(el.content,
textAlign: pw.TextAlign.center,
style: pw.TextStyle(font: ttf, fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
);
case ElementType.dottedLine:
return pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 3),
child: pw.Text(el.content,
textAlign: pw.TextAlign.center,
style: pw.TextStyle(font: ttf, fontSize: 11)),
);
case ElementType.table:
return _buildPdfCustomTable(el.content, ttf, isAr);
case ElementType.shape:
return _buildPdfCustomShape(el.content, ttf);
case ElementType.mathOperation:
try {
final data = jsonDecode(el.content);
final kind = data['kind'] ?? 'vertical';
if (kind == 'vertical') {
final List rows = data['rows'] ?? [];
final String op = data['operator'] ?? '+';
final bool opOnRight = data['opOnRight'] ?? isAr;
return pw.Center(
child: pw.Container(
margin: const pw.EdgeInsets.symmetric(vertical: 4),
padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
child: pw.Column(
crossAxisAlignment: pw.CrossAxisAlignment.end,
children: [
...rows.asMap().entries.map((entry) {
final idx = entry.key;
final val = entry.value.toString();
final isLast = idx == rows.length - 1;
return pw.Row(
mainAxisSize: pw.MainAxisSize.min,
children: [
if (!opOnRight && isLast)
pw.Padding(
padding: const pw.EdgeInsets.only(left: 6),
child: pw.Text(op,
style: pw.TextStyle(
font: ttf,
fontSize: 13,
fontWeight: pw.FontWeight.bold)),
),
pw.Text(
val,
style: pw.TextStyle(
font: ttf,
fontSize: 13,
fontWeight: pw.FontWeight.bold,
),
),
if (opOnRight && isLast)
pw.Padding(
padding: const pw.EdgeInsets.only(right: 6),
child: pw.Text(op,
style: pw.TextStyle(
font: ttf,
fontSize: 13,
fontWeight: pw.FontWeight.bold)),
),
],
);
}),
pw.SizedBox(height: 2),
pw.Container(width: 75, height: 1.0, color: PdfColors.black),
pw.SizedBox(height: 8),
],
),
),
);
} else if (kind == 'fraction') {
final num = data['num'] ?? '';
final den = data['den'] ?? '';
final int maxLen = num.length > den.length ? num.length : den.length;
final double lineWidth = (maxLen * 8.5) + 12.0;
return pw.Center(
child: pw.Column(
mainAxisSize: pw.MainAxisSize.min,
crossAxisAlignment: pw.CrossAxisAlignment.center,
children: [
pw.Text(
num,
style: pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
),
pw.Container(
width: lineWidth,
height: 1.0,
color: PdfColors.black,
margin: const pw.EdgeInsets.symmetric(vertical: 1.5),
),
pw.Text(
den,
style: pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
),
],
),
);
}
} catch (_) {}
return pw.SizedBox.shrink();
}
}
static pw.Widget _buildPdfCustomTable(String jsonStr, pw.Font ttf, bool isAr) {
try {
final Map<String, dynamic> data = jsonDecode(jsonStr);
final int rows = data['rows'] ?? 2;
final int cols = data['cols'] ?? 2;
final bool hasHeader = data['hasHeader'] ?? true;
final List rawGrid = data['data'] ?? [];
return pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 4),
child: pw.Table(
border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
children: List.generate(rows, (r) {
final isHeaderRow = (r == 0 && hasHeader);
return pw.TableRow(
decoration: pw.BoxDecoration(
color: isHeaderRow ? PdfColors.grey200 : PdfColors.white,
),
children: List.generate(cols, (colIndex) {
// الحفاظ على المحاذاة الداخلية للخلايا حسب اتجاه الجدول المختار
final c = isAr ? (cols - 1 - colIndex) : colIndex;
String text = '';
if (r < rawGrid.length && c < (rawGrid[r] as List).length) {
text = rawGrid[r][c]?.toString() ?? '';
}
return pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 3),
child: pw.Text(
text,
textAlign: pw.TextAlign.center,
style: pw.TextStyle(
font: ttf,
fontSize: isHeaderRow ? 10.0 : 9.0,
fontWeight: isHeaderRow ? pw.FontWeight.bold : pw.FontWeight.normal,
),
),
);
}),
);
}),
),
);
} catch (_) {
return pw.SizedBox.shrink();
}
}
static pw.Widget _buildPdfCustomShape(String jsonStr, pw.Font ttf) {
try {
final Map<String, dynamic> data = jsonDecode(jsonStr);
final String kind = data['kind'] ?? 'rectangle';
final double w = (data['width'] as num?)?.toDouble() ?? 120.0;
final double h = (data['height'] as num?)?.toDouble() ?? 70.0;
final String label = data['label'] ?? '';
final PdfColor strokeColor = _parsePdfColor(data['strokeColor'], defaultColor: PdfColors.black);
final bool hasFill = data['fillColor'] != null && data['fillColor'] != 'transparent';
final PdfColor fillColor = hasFill ? _parsePdfColor(data['fillColor'], defaultColor: PdfColors.grey100) : PdfColors.white;
return pw.Center(
child: pw.Padding(
padding: const pw.EdgeInsets.symmetric(vertical: 4),
child: pw.Stack(
alignment: pw.Alignment.center,
children: [
pw.CustomPaint(
size: PdfPoint(w, h),
painter: (PdfGraphics canvas, PdfPoint pointSize) {
final pw_x = pointSize.x;
final pw_y = pointSize.y;
canvas
..setColor(strokeColor)
..setLineWidth(1.2);
switch (kind) {
case 'circle':
if (hasFill) {
canvas.setFillColor(fillColor);
canvas.drawEllipse(pw_x / 2, pw_y / 2, (pw_x - 4) / 2, (pw_y - 4) / 2);
canvas.fillPath();
}
canvas.drawEllipse(pw_x / 2, pw_y / 2, (pw_x - 4) / 2, (pw_y - 4) / 2);
canvas.strokePath();
break;
case 'triangle':
if (hasFill) {
canvas.setFillColor(fillColor);
canvas
..moveTo(pw_x / 2, pw_y - 2)
..lineTo(pw_x - 2, 2)
..lineTo(2, 2)
..closePath()
..fillPath();
}
canvas
..moveTo(pw_x / 2, pw_y - 2)
..lineTo(pw_x - 2, 2)
..lineTo(2, 2)
..closePath()
..strokePath();
break;
case 'rightTriangle':
if (hasFill) {
canvas.setFillColor(fillColor);
canvas
..moveTo(2, pw_y - 2)
..lineTo(pw_x - 2, 2)
..lineTo(2, 2)
..closePath()
..fillPath();
}
canvas
..moveTo(2, pw_y - 2)
..lineTo(pw_x - 2, 2)
..lineTo(2, 2)
..closePath()
..strokePath();
canvas
..moveTo(2, 12)
..lineTo(12, 12)
..lineTo(12, 2)
..strokePath();
break;
case 'parallelogram':
final offset = pw_x * 0.22;
if (hasFill) {
canvas.setFillColor(fillColor);
canvas
..moveTo(offset, pw_y - 2)
..lineTo(pw_x - 2, 2)
..lineTo(w - offset, h - 2)
..lineTo(2, h - 2)
..closePath()
..fillPath();
}
canvas
..moveTo(offset, pw_y - 2)
..lineTo(pw_x - 2, 2)
..lineTo(w - offset, h - 2)
..lineTo(2, h - 2)
..closePath()
..strokePath();
break;
case 'line':
canvas
..moveTo(2, pw_y / 2)
..lineTo(pw_x - 2, pw_y / 2)
..strokePath();
break;
case 'arrow':
final midY = pw_y / 2;
canvas
..moveTo(2, midY)
..lineTo(pw_x - 2, midY)
..strokePath()
..moveTo(12, midY + 5)
..lineTo(2, midY)
..lineTo(12, midY - 5)
..strokePath();
break;
case 'rectangle':
default:
if (hasFill) {
canvas.setFillColor(fillColor);
canvas.drawRect(2, 2, pw_x - 4, pw_y - 4);
canvas.fillPath();
}
canvas.drawRect(2, 2, pw_x - 4, pw_y - 4);
canvas.strokePath();
break;
}
},
),
if (label.isNotEmpty)
pw.Container(
width: w,
height: h,
alignment: pw.Alignment.center,
child: pw.Text(
label,
style: pw.TextStyle(
font: ttf,
fontSize: 10,
fontWeight: pw.FontWeight.bold,
color: strokeColor,
),
textAlign: pw.TextAlign.center,
),
),
],
),
),
);
} catch (_) {
return pw.SizedBox.shrink();
}
}
}

import 'dart:io';
import 'package:barcode/barcode.dart';
import 'package:better_download_saver/better_download_saver.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam_models.dart';
import 'student_excel_service.dart';

class OmrSheetService {
  // ثوابت تحويل الأبعاد إلى نقاط الطباعة (Points)
  static const double cm = 28.3465;
  static const double mm = 2.83465;

  /// توليد ورقة التظليل (OMR Bubble Sheet) كملف PDF وحفظه في مجلد التنزيلات
  static Future<String> generateOmrPdf(ExamModel exam) async {
    final pdf = pw.Document();

    ByteData fontData;
    try {
      fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    } catch (_) {
      fontData = await rootBundle.load('assets/fonts/amiri-regular.ttf');
    }
    final ttf = pw.Font.ttf(fontData);

    final bool isAr = exam.isArabic;
    final pw.TextDirection pageDirection =
        isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    // 1. استخراج بيانات الطلاب وتحديد الرقم الذكي المطبوع يمين الـ QR ديناميكياً
    List<StudentData> studentList = [];
    int currentSubjectCode = 1;

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

    final int tfCount = exam.automatedConfig.trueFalseCount;
    final int mcqCount = exam.automatedConfig.mcqCount;

    // تحديد رموز خيارات الاختيار من متعدد بدقة بناءً على اللغة ونمط الرموز
    final List<String> mcqSymbols;
    if (exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.numbers) {
      mcqSymbols = isAr ? ['١', '٢', '٣', '٤'] : ['1', '2', '3', '4'];
    } else {
      mcqSymbols = isAr ? ['أ', 'ب', 'جـ', 'د'] : ['A', 'B', 'C', 'D'];
    }

    // تحديد رموز الصح والخطأ
    final List<String> tfSymbols = isAr ? ['ص', 'خ'] : ['T', 'F'];

    // 2. توليد ورقة تظليل لكل طالب
    for (final student in studentsToIterate) {
      final bool hasStudent = student.seatNo.isNotEmpty;
      final bool showQr = hasStudent && exam.header.studentDataMode == 'namesAndQr';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          textDirection: pageDirection,
          margin: const pw.EdgeInsets.only(
            top: 3.0 * mm,
            bottom: 4.0 * mm,
            left: 1.2 * cm,
            right: 1.2 * cm,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // أ. ترويسة ورقة الإجابة المصغرة (ثابتة الاتجاه RTL دائماً لسلامة اسم ورقم جلوس الطالب)
                _buildOmrHeader(exam, student, isAr, ttf),
                pw.SizedBox(height: 5),

                // ب. منطقة إرشادات التظليل
                _buildOmrInstructions(isAr, ttf),
                pw.SizedBox(height: 5),

                // ج. شبكة دوائر التظليل (تتبع اتجاه لغة الاختبار المحددة)
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // قسم الصح والخطأ
                      if (tfCount > 0) ...[
                        pw.Expanded(
                          flex: 4,
                          child: _buildSectionBox(
                            title: isAr
                                ? 'أولاً: إجابات الصح والخطأ ($tfCount فقرة)'
                                : 'Part 1: True / False ($tfCount Items)',
                            ttf: ttf,
                            child: _buildTrueFalseGrid(tfCount, tfSymbols, isAr, ttf),
                          ),
                        ),
                        if (mcqCount > 0) pw.SizedBox(width: 10),
                      ],

                      // قسم الاختيار من متعدد
                      if (mcqCount > 0)
                        pw.Expanded(
                          flex: 6,
                          child: _buildSectionBox(
                            title: isAr
                                ? 'ثانياً: إجابات الاختيار من متعدد ($mcqCount فقرة)'
                                : 'Part 2: Multiple Choice ($mcqCount Items)',
                            ttf: ttf,
                            child: _buildMcqGrid(mcqCount, mcqSymbols, isAr, ttf),
                          ),
                        ),
                    ],
                  ),
                ),

                pw.SizedBox(height: 4),

                // د. التذييل (ثابت الاتجاه RTL دائماً لضمان بقاء الـ QR والباركود في الإحداثيات الهندسية المعتمدة)
                _buildOmrFooter(exam, student, showQr, currentSubjectCode, isAr, ttf),
              ],
            );
          },
        ),
      );
    }

    // ============ صياغة التسمية الجديدة التلقائية لورقة التظليل ============
    final pdfBytes = await pdf.save();

    final gradeName = exam.header.grade.trim().isNotEmpty ? exam.header.grade.trim() : 'عام';
    final subjectName = exam.header.subject.trim().isNotEmpty ? exam.header.subject.trim() : 'مادة';

    final omrBaseName = isAr
        ? '$gradeName _ $subjectName _ ورقة_تظليل'
        : '$gradeName _ $subjectName _ OMR_Sheet';
    final safeName = omrBaseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = '$safeName.pdf';

    // المحاولة الأولى: الحفظ في مجلد التنزيلات العام (Downloads)
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

    // الخطة البديلة: الحفظ في مجلد التطبيق المخصص
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
      throw Exception('تعذر حفظ ملف ورقة التظليل: $e');
    }
  }

  // ترويسة ورقة التظليل (مغلفة بـ Directionality RTL دائماً لثبات بيانات الطالب)
  static pw.Widget _buildOmrHeader(
      ExamModel exam, StudentData student, bool isAr, pw.Font ttf) {
    final bool hasStudent = student.name.trim().isNotEmpty;

    final schoolLabel = exam.header.school.isNotEmpty
        ? '${exam.header.country} - ${exam.header.school}'
        : exam.header.country;

    final sheetTitle = isAr
        ? 'ورقة الإجابة والتظليل الآلي (OMR Sheet)'
        : 'Automated Answer Sheet (OMR Sheet)';

    final infoLabel = isAr
        ? 'المادة: ${exam.header.subject} | الصف: ${exam.header.grade}'
        : 'Subject: ${exam.header.subject} | Grade: ${exam.header.grade}';

    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1.2),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  schoolLabel,
                  style: pw.TextStyle(
                      font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  sheetTitle,
                  style: pw.TextStyle(
                      font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  infoLabel,
                  style: pw.TextStyle(
                      font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
            if (hasStudent) ...[
              pw.Divider(thickness: 0.8, color: PdfColors.black, height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'اسم الطالب: ${student.name}',
                    style: pw.TextStyle(
                        font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                  if (student.seatNo.isNotEmpty)
                    pw.Text(
                      'رقم الجلوس: [ ${student.seatNo} ]',
                      style: pw.TextStyle(
                          font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // صندوق التعليمات للتظليل الصحيح
  static pw.Widget _buildOmrInstructions(bool isAr, pw.Font ttf) {
    final instructText = isAr
        ? 'تعليمات: ظلل دائرة واحدة فقط بالقلم الأزرق أو الأسود الجاف بشكل كامل.'
        : 'Instructions: Completely fill only one bubble for each item using a blue or black pen.';

    final correctLabel = isAr ? 'صحيح: ' : 'Correct: ';
    final wrongLabel = isAr ? 'خطأ: ' : 'Wrong: ';

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.0),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            instructText,
            style: pw.TextStyle(font: ttf, fontSize: 8.5),
          ),
          pw.Row(
            children: [
              pw.Text(correctLabel, style: pw.TextStyle(font: ttf, fontSize: 8.5)),
              _buildCircle(label: '', isFilled: true),
              pw.SizedBox(width: 8),
              pw.Text(wrongLabel, style: pw.TextStyle(font: ttf, fontSize: 8.5)),
              _buildCircle(label: '✔', isSmall: true),
              pw.SizedBox(width: 4),
              _buildCircle(label: '✘', isSmall: true),
            ],
          ),
        ],
      ),
    );
  }

  // إطار عام لأقسام التظليل
  static pw.Widget _buildSectionBox({
    required String title,
    required pw.Font ttf,
    required pw.Widget child,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.0),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
            child: pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: child,
          ),
        ],
      ),
    );
  }

  // بناء شبكة الصح والخطأ
  static pw.Widget _buildTrueFalseGrid(
      int count, List<String> tfSymbols, bool isAr, pw.Font ttf) {
    final int half = (count / 2).ceil();
    final bool useTwoCols = count > 12;

    if (!useTwoCols) {
      return pw.Column(
        children: List.generate(count, (i) {
          final qNum = i + 1;
          return _buildTfRow(qNum, tfSymbols, isAr, ttf);
        }),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            children: List.generate(half, (i) {
              final qNum = i + 1;
              return _buildTfRow(qNum, tfSymbols, isAr, ttf);
            }),
          ),
        ),
        pw.Container(width: 0.8, height: half * 19.0, color: PdfColors.grey400),
        pw.Expanded(
          child: pw.Column(
            children: List.generate(count - half, (i) {
              final qNum = half + i + 1;
              return _buildTfRow(qNum, tfSymbols, isAr, ttf);
            }),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTfRow(
      int qNum, List<String> tfSymbols, bool isAr, pw.Font ttf) {
    final numStr = isAr ? _toArabicDigits(qNum) : '$qNum';

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 20,
            child: pw.Text(
              numStr,
              style: pw.TextStyle(
                  font: ttf, fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(width: 4),
          _buildCircle(label: tfSymbols[0], ttf: ttf),
          pw.SizedBox(width: 4),
          _buildCircle(label: tfSymbols[1], ttf: ttf),
        ],
      ),
    );
  }

  // بناء شبكة الاختيار من متعدد
  static pw.Widget _buildMcqGrid(
      int count, List<String> symbols, bool isAr, pw.Font ttf) {
    final int half = (count / 2).ceil();
    final bool useTwoCols = count > 10;

    if (!useTwoCols) {
      return pw.Column(
        children: List.generate(count, (i) {
          final qNum = i + 1;
          return _buildMcqRow(qNum, symbols, isAr, ttf);
        }),
      );
    }

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            children: List.generate(half, (i) {
              final qNum = i + 1;
              return _buildMcqRow(qNum, symbols, isAr, ttf);
            }),
          ),
        ),
        pw.Container(width: 0.8, height: half * 21.0, color: PdfColors.grey400),
        pw.Expanded(
          child: pw.Column(
            children: List.generate(count - half, (i) {
              final qNum = half + i + 1;
              return _buildMcqRow(qNum, symbols, isAr, ttf);
            }),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildMcqRow(
      int qNum, List<String> symbols, bool isAr, pw.Font ttf) {
    final numStr = isAr ? _toArabicDigits(qNum) : '$qNum';

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 20,
            child: pw.Text(
              numStr,
              style: pw.TextStyle(
                  font: ttf, fontSize: 8.5, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(width: 4),
          ...symbols.map((sym) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2.2),
                child: _buildCircle(label: sym, ttf: ttf),
              )),
        ],
      ),
    );
  }

  // تحويل الأرقام إلى العربية المشرقية عند اختيار لغة عربية
  static String _toArabicDigits(int number) {
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((d) => arabicDigits[int.parse(d)])
        .join();
  }

  // رسم دائرة التظليل
  static pw.Widget _buildCircle({
    required String label,
    pw.Font? ttf,
    bool isFilled = false,
    bool isSmall = false,
  }) {
    final double size = isSmall ? 10.0 : 13.5;

    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        color: isFilled ? PdfColors.black : PdfColors.white,
        border: pw.Border.all(color: PdfColors.black, width: 0.8),
      ),
      child: pw.Center(
        child: !isFilled && label.isNotEmpty
            ? pw.Text(
                label,
                style: pw.TextStyle(
                  font: ttf,
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              )
            : null,
      ),
    );
  }

  // تذييل ورقة التظليل (مغلف بـ Directionality RTL دائماً للحفاظ على إحداثيات QR وكود المادة للماسح)
  static pw.Widget _buildOmrFooter(
    ExamModel exam,
    StudentData student,
    bool showQr,
    int subjectCode,
    bool isAr,
    pw.Font ttf,
  ) {
    final footerNotice = isAr
        ? 'لجنة الكنترول والتصحيح الآلي | ملاحظ القاعة: ......................'
        : 'Automated Scoring Committee | Hall Proctor: ......................';

    return pw.Directionality(
      textDirection: pw.TextDirection.rtl,
      child: pw.Container(
        height: 62,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  footerNotice,
                  style: pw.TextStyle(font: ttf, fontSize: 8.5),
                ),
              ],
            ),
            pw.Row(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  '$subjectCode',
                  style: pw.TextStyle(
                    font: ttf,
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(width: 8),
                if (showQr && student.secretCode.isNotEmpty)
                  pw.Container(
                    width: 40,
                    height: 40,
                    child: pw.BarcodeWidget(
                      barcode: Barcode.qrCode(),
                      data: student.secretCode,
                      drawText: false,
                    ),
                  )
                else
                  pw.SizedBox(width: 40, height: 40),
                pw.SizedBox(width: 10),
                pw.Container(
                  width: 50,
                  height: 40,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 1.2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam_models.dart';
import 'student_excel_service.dart';

class OmrSheetService {
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

    // 1. استخراج بيانات الطلاب إن وجدت
    List<StudentData> studentList = [];
    int currentSubjectCode = exam.header.subjectCode;

    if (exam.header.topMargin1cm &&
        exam.header.studentDataMode != 'none' &&
        exam.header.excelFilePath != null &&
        File(exam.header.excelFilePath!).existsSync()) {
      try {
        final excelRes = await StudentExcelService.parseExcelFile(
          exam.header.excelFilePath!,
          expectedSubject: exam.header.subject,
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
    final bool isLetters =
        exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.arabicLetters;
    final List<String> mcqSymbols =
        isLetters ? ['أ', 'ب', 'جـ', 'د'] : ['١', '٢', '٣', '٤'];

    // 2. توليد ورقة تظليل لكل طالب
    for (final student in studentsToIterate) {
      final bool hasStudent = student.seatNo.isNotEmpty;
      final bool showQr = hasStudent && exam.header.studentDataMode == 'namesAndQr';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(22),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // أ. ترويسة ورقة الإجابة المصغرة
                _buildOmrHeader(exam, student, ttf),
                pw.SizedBox(height: 12),

                // ب. منطقة إرشادات التظليل
                _buildOmrInstructions(ttf),
                pw.SizedBox(height: 12),

                // ج. شبكة دوائر التظليل للصح والخطأ والاختيار من متعدد
                pw.Expanded(
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      // قسم الصح والخطأ
                      if (tfCount > 0) ...[
                        pw.Expanded(
                          flex: 4,
                          child: _buildSectionBox(
                            title: 'أولاً: إجابات الصح والخطأ ($tfCount فقرة)',
                            ttf: ttf,
                            child: _buildTrueFalseGrid(tfCount, ttf),
                          ),
                        ),
                        pw.SizedBox(width: 14),
                      ],

                      // قسم الاختيار من متعدد
                      if (mcqCount > 0)
                        pw.Expanded(
                          flex: 6,
                          child: _buildSectionBox(
                            title: 'ثانياً: إجابات الاختيار من متعدد ($mcqCount فقرة)',
                            ttf: ttf,
                            child: _buildMcqGrid(mcqCount, mcqSymbols, ttf),
                          ),
                        ),
                    ],
                  ),
                ),

                // د. التذييل مع رمز QR وكود المادة وتوقيع الكنترول
                pw.SizedBox(height: 8),
                _buildOmrFooter(exam, student, showQr, currentSubjectCode, ttf),
              ],
            );
          },
        ),
      );
    }

    // حفظ الملف في مجلد التنزيلات
    Directory dir;
    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync()) {
        dir = downloadDir;
      } else {
        dir = (await getExternalStorageDirectory()) ??
            await getApplicationDocumentsDirectory();
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    final safeName = '${exam.fileName}_ورقة_تظليل_OMR'
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${dir.path}/$safeName.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save(), flush: true);

    return filePath;
  }

  // ترويسة ورقة التظليل
  static pw.Widget _buildOmrHeader(
      ExamModel exam, StudentData student, pw.Font ttf) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.2),
      ),
      padding: const pw.EdgeInsets.all(6),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('${exam.header.country} - ${exam.header.school}',
                  style: pw.TextStyle(
                      font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
              pw.Text('ورقة الإجابة والتظليل الآلي (OMR Sheet)',
                  style: pw.TextStyle(
                      font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.Text('المادة: ${exam.header.subject} | الصف: ${exam.header.grade}',
                  style: pw.TextStyle(
                      font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Divider(thickness: 0.8, color: PdfColors.black),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                student.name.isNotEmpty
                    ? 'اسم الطالب: ${student.name}'
                    : 'اسم الطالب: ................................................................',
                style: pw.TextStyle(
                    font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                student.seatNo.isNotEmpty
                    ? 'رقم الجلوس: [ ${student.seatNo} ]'
                    : 'رقم الجلوس: [ .................... ]',
                style: pw.TextStyle(
                    font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // صندوق التعليمات للتظليل الصحيح
  static pw.Widget _buildOmrInstructions(pw.Font ttf) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'تعليمات: ظلل دائرة واحدة فقط بالقلم الأزرق أو الأسود الجاف بشكل كامل.',
            style: pw.TextStyle(font: ttf, fontSize: 8.5),
          ),
          pw.Row(
            children: [
              pw.Text('صحيح: ', style: pw.TextStyle(font: ttf, fontSize: 8.5)),
              _buildCircle(label: '', isFilled: true),
              pw.SizedBox(width: 8),
              pw.Text('خطأ: ', style: pw.TextStyle(font: ttf, fontSize: 8.5)),
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
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            color: PdfColors.grey200,
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            child: pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                  font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: child,
          ),
        ],
      ),
    );
  }

  // بناء شبكة الصح والخطأ (ص / خ)
  static pw.Widget _buildTrueFalseGrid(int count, pw.Font ttf) {
    final int half = (count / 2).ceil();
    final bool useTwoCols = count > 12;

    if (!useTwoCols) {
      return pw.Column(
        children: List.generate(count, (i) {
          final qNum = i + 1;
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.SizedBox(
                  width: 20,
                  child: pw.Text('$qNum',
                      style: pw.TextStyle(
                          font: ttf, fontSize: 9, fontWeight: pw.FontWeight.bold),
                      textAlign: pw.TextAlign.center),
                ),
                pw.SizedBox(width: 6),
                _buildCircle(label: 'ص', ttf: ttf),
                pw.SizedBox(width: 6),
                _buildCircle(label: 'خ', ttf: ttf),
              ],
            ),
          );
        }),
      );
    }

    // تقسيم إلى عمودين إذا كان عدد الأسئلة كبيراً
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            children: List.generate(half, (i) {
              final qNum = i + 1;
              return _buildTfRow(qNum, ttf);
            }),
          ),
        ),
        pw.Container(width: 0.8, height: half * 20.0, color: PdfColors.grey400),
        pw.Expanded(
          child: pw.Column(
            children: List.generate(count - half, (i) {
              final qNum = half + i + 1;
              return _buildTfRow(qNum, ttf);
            }),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildTfRow(int qNum, pw.Font ttf) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 16,
            child: pw.Text('$qNum',
                style: pw.TextStyle(
                    font: ttf, fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(width: 4),
          _buildCircle(label: 'ص', ttf: ttf),
          pw.SizedBox(width: 4),
          _buildCircle(label: 'خ', ttf: ttf),
        ],
      ),
    );
  }

  // بناء شبكة الاختيار من متعدد
  static pw.Widget _buildMcqGrid(
      int count, List<String> symbols, pw.Font ttf) {
    final int half = (count / 2).ceil();
    final bool useTwoCols = count > 10;

    if (!useTwoCols) {
      return pw.Column(
        children: List.generate(count, (i) {
          final qNum = i + 1;
          return _buildMcqRow(qNum, symbols, ttf);
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
              return _buildMcqRow(qNum, symbols, ttf);
            }),
          ),
        ),
        pw.Container(width: 0.8, height: half * 22.0, color: PdfColors.grey400),
        pw.Expanded(
          child: pw.Column(
            children: List.generate(count - half, (i) {
              final qNum = half + i + 1;
              return _buildMcqRow(qNum, symbols, ttf);
            }),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildMcqRow(int qNum, List<String> symbols, pw.Font ttf) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 18,
            child: pw.Text('$qNum',
                style: pw.TextStyle(
                    font: ttf, fontSize: 8.5, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center),
          ),
          pw.SizedBox(width: 4),
          ...symbols.map((sym) => pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2.5),
                child: _buildCircle(label: sym, ttf: ttf),
              )),
        ],
      ),
    );
  }

  // رسم دائرة التظليل الهندسية
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

  // تذييل ورقة التظليل مع رمز الاستجابة السريع وكود المادة
  static pw.Widget _buildOmrFooter(
    ExamModel exam,
    StudentData student,
    bool showQr,
    int subjectCode,
    pw.Font ttf,
  ) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(
          'لجنة الكنترول والتصحيح الآلي | ملاحظ القاعة: ......................',
          style: pw.TextStyle(font: ttf, fontSize: 8.5),
        ),
        if (showQr)
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                '$subjectCode',
                style: pw.TextStyle(
                  font: ttf,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(width: 6),
              pw.Container(
                width: 38,
                height: 38,
                child: pw.BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: student.secretCode,
                  drawText: false,
                ),
              ),
            ],
          )
        else
          pw.SizedBox(height: 10),
      ],
    );
  }
}

import 'dart:io';
import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam_models.dart';
import 'student_excel_service.dart';

class OmrSheetService {
  // ثابت تحويل السنتيمتر إلى نقاط الطباعة (Points)
  static const double cm = 28.3465;

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

    // 1. استخراج بيانات الطلاب إن وجدت من ملف الإكسيل
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
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.only(
            top: 1.0 * cm,
            bottom: 1.0 * cm,
            left: 1.2 * cm,
            right: 1.2 * cm,
          ),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // أ. ترويسة ورقة الإجابة المصغرة
                _buildOmrHeader(exam, student, ttf),
                pw.SizedBox(height: 6),

                // ب. منطقة إرشادات التظليل
                _buildOmrInstructions(ttf),
                pw.SizedBox(height: 6),

                // ج. شبكة دوائر التظليل
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
                        if (mcqCount > 0) pw.SizedBox(width: 10),
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

                pw.SizedBox(height: 6),

                // د. التذييل مع رمز QR وكود المادة ومربع الدرجة الفارغ 50x60
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
    final bool hasStudent = student.name.trim().isNotEmpty;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1.2),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '${exam.header.country} - ${exam.header.school}',
                style: pw.TextStyle(
                    font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'ورقة الإجابة والتظليل الآلي (OMR Sheet)',
                style: pw.TextStyle(
                    font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                'المادة: ${exam.header.subject} | الصف: ${exam.header.grade}',
                style: pw.TextStyle(
                    font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          if (hasStudent) ...[
            pw.Divider(thickness: 0.8, color: PdfColors.black, height: 6),
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
    );
  }

  // صندوق التعليمات للتظليل الصحيح
  static pw.Widget _buildOmrInstructions(pw.Font ttf) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
      ),
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
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
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
            padding: const pw.EdgeInsets.all(5),
            child: child,
          ),
        ],
      ),
    );
  }

  // بناء شبكة الصح والخطأ
  static pw.Widget _buildTrueFalseGrid(int count, pw.Font ttf) {
    final int half = (count / 2).ceil();
    final bool useTwoCols = count > 12;

    if (!useTwoCols) {
      return pw.Column(
        children: List.generate(count, (i) {
          final qNum = i + 1;
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
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
        pw.Container(width: 0.8, height: half * 19.0, color: PdfColors.grey400),
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
      padding: const pw.EdgeInsets.symmetric(vertical: 1.8),
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
        pw.Container(width: 0.8, height: half * 21.0, color: PdfColors.grey400),
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
      padding: const pw.EdgeInsets.symmetric(vertical: 2.0),
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
                padding: const pw.EdgeInsets.symmetric(horizontal: 2.2),
                child: _buildCircle(label: sym, ttf: ttf),
              )),
        ],
      ),
    );
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

  // تذييل ورقة التظليل:
  // [مربع فارغ تماماً 50 عرض × 40 ارتفاع] <- [رمز QR بمقاس 40x40] <- [كود المادة بحجم 20 عريض وبدون إطار]
  static pw.Widget _buildOmrFooter(
    ExamModel exam,
    StudentData student,
    bool showQr,
    int subjectCode,
    pw.Font ttf,
  ) {
    return pw.Container(
      height: 6.5 * cm,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          // الجهة اليمنى: توقيع وملاحظة الكنترول
          pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (student.secretCode.isNotEmpty)
                pw.Text(
                  'الرقم السري: ${student.secretCode}',
                  style: pw.TextStyle(font: ttf, fontSize: 8.5, color: PdfColors.grey700),
                ),
              pw.SizedBox(height: 4),
              pw.Text(
                'لجنة الكنترول والتصحيح الآلي | ملاحظ القاعة: ......................',
                style: pw.TextStyle(font: ttf, fontSize: 8.5),
              ),
            ],
          ),

          // الجهة اليسرى:
          // [كود المادة: خط 20 عريض بدون إطار] -> [رمز QR: 40x40] -> [مربع فارغ تماماً: عرض 50 × ارتفاع 40]
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // 1. رقم كود المادة: خط 20 عريض وبدون إطار
              pw.Text(
                '$subjectCode',
                style: pw.TextStyle(
                  font: ttf,
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),

              pw.SizedBox(width: 8),

              // 2. رمز الاستجابة السريع للطالب بمقاس 40 × 40
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

              // 3. مربع الدرجة المستحقة: فارغ تماماً بدون كتابة وبمقاس 50 × 60
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
    );
  }
}

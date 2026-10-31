import 'dart:convert';
import 'dart:io';
import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import '../models/exam_models.dart';
import 'student_excel_service.dart';

class PdfExportService {
  static const double cm = 28.3465;
  static const double mm = 2.83465;

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

    final bool isAutomated = exam.examType == ExamType.automated;
    final bool isLetters = exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.arabicLetters;
    final List<String> symbols = isLetters ? ['أ', 'ب', 'جـ', 'د'] : ['١', '٢', '٣', '٤'];

    for (final student in studentsToIterate) {
      final bool hasStudent = student.seatNo.isNotEmpty;
      final bool showQrMode = hasStudent &&
          exam.header.studentDataMode == 'namesAndQr' &&
          !isAutomated;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.only(
            top: 3.0 * mm,
            bottom: 4.0 * mm,
            left: 20.0,
            right: 20.0,
          ),
          textDirection: pw.TextDirection.rtl,
          header: (pw.Context context) {
            if (exam.header.topMargin1cm && hasStudent) {
              return pw.Padding(
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
              );
            }
            return pw.SizedBox.shrink();
          },
          footer: (pw.Context context) {
            return pw.Container(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Center(
                    child: pw.Text(
                      exam.header.singlePageFooterText,
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
                        exam.header.teacherSignature,
                        style: pw.TextStyle(font: ttf, fontSize: 9.0),
                      ),
                      if (showQrMode)
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              '$currentSubjectCode',
                              style: pw.TextStyle(
                                font: ttf,
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.SizedBox(width: 8),
                            if (student.secretCode.isNotEmpty)
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
                              width: 60,
                              height: 50,
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(color: PdfColors.black, width: 1.2),
                              ),
                            ),
                          ],
                        )
                      else
                        pw.SizedBox(height: 10),
                    ],
                  ),
                ],
              ),
            );
          },
          build: (pw.Context context) {
            return [
              _buildExamHeaderBox(exam, ttf, logoImage),
              pw.SizedBox(height: 6),
              if (isAutomated)
                ..._buildAutomatedQuestionsList(exam, symbols, ttf)
              else
                ..._buildTraditionalExamWidgets(exam, ttf),
            ];
          },
        ),
      );
    }

    // تحديد المجلد الآمن المتاح للكتابة
    Directory dir;
    final pdfBytes = await pdf.save();
    final safeName = exam.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    if (Platform.isAndroid) {
      bool canWriteToPublicDownload = false;
      final publicDownload = Directory('/storage/emulated/0/Download');

      // تجربة الكتابة في مجلد التنزيلات العام أولاً
      try {
        if (!publicDownload.existsSync()) {
          publicDownload.createSync(recursive: true);
        }
        final testFile = File('${publicDownload.path}/.test_permission.tmp');
        testFile.writeAsStringSync('test');
        testFile.deleteSync();
        canWriteToPublicDownload = true;
      } catch (_) {
        canWriteToPublicDownload = false;
      }

      if (canWriteToPublicDownload) {
        dir = publicDownload;
      } else {
        // إذا كان النظام يحظر الوصول للمسار المباشر، نستخدم مسار التنزيلات الرسمي للتطبيق
        final extDir = await getExternalStorageDirectory();
        dir = extDir ?? await getApplicationDocumentsDirectory();
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final filePath = '${dir.path}/$safeName.pdf';
    final file = File(filePath);
    await file.writeAsBytes(pdfBytes, flush: true);

    return filePath;
  }

  static pw.Widget _buildExamHeaderBox(ExamModel exam, pw.Font ttf, pw.MemoryImage? logoImage) {
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

  static List<pw.Widget> _buildAutomatedQuestionsList(
    ExamModel exam,
    List<String> symbols,
    pw.Font ttf,
  ) {
    final List<pw.Widget> widgets = [];
    final int tfCount = exam.automatedConfig.trueFalseCount;
    final int mcqCount = exam.automatedConfig.mcqCount;

    widgets.add(
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        color: PdfColors.grey100,
        child: pw.Text(
          exam.header.instructionText.isNotEmpty
              ? exam.header.instructionText
              : 'أجب بتظليل الدائرة المناسبة في ورقة الإجابة المخصصة (OMR)',
          style: pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );

    if (tfCount > 0) {
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 4),
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 8),
          color: PdfColors.grey300,
          child: pw.Text(
            'أولاً: فقرات الصح والخطأ (ظلل الدائرة ص أو خ في ورقة الإجابة):',
            style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );

      for (int i = 1; i <= tfCount; i++) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.8),
            ),
            child: pw.Row(
              children: [
                pw.Container(
                  width: 28,
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(left: pw.BorderSide(color: PdfColors.black, width: 0.8)),
                  ),
                  child: pw.Center(
                    child: pw.Text('$i', style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  ),
                ),
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: pw.Text(
                      '(      ) ............................................................................................',
                      style: pw.TextStyle(font: ttf, fontSize: 9.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      widgets.add(pw.SizedBox(height: 6));
    }

    if (mcqCount > 0) {
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 4),
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 8),
          color: PdfColors.grey300,
          child: pw.Text(
            'ثانياً: فقرات الاختيار من متعدد (ظلل رمز الإجابة الصحيحة في ورقة الإجابة):',
            style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );

      for (int i = 1; i <= mcqCount; i++) {
        final int itemNumber = tfCount + i;
        widgets.add(
          _buildAutomatedMcqItem(
            itemNumber: itemNumber,
            questionText: '',
            choices: ['', '', '', ''],
            symbols: symbols,
            ttf: ttf,
          ),
        );
      }
    }

    return widgets;
  }

  static pw.Widget _buildAutomatedMcqItem({
    required int itemNumber,
    required String questionText,
    required List<String> choices,
    required List<String> symbols,
    required pw.Font ttf,
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
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: PdfColors.black, width: 0.9)),
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
                    textAlign: pw.TextAlign.right,
                  ),
                ),
                pw.Container(
                  height: 20,
                  child: pw.Row(
                    children: List.generate(4, (index) {
                      final sym = symbols.length > index ? symbols[index] : '${index + 1}';
                      final choiceTxt = choices.length > index ? choices[index] : '';

                      return pw.Expanded(
                        child: pw.Container(
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              left: index > 0
                                  ? const pw.BorderSide(color: PdfColors.black, width: 0.8)
                                  : pw.BorderSide.none,
                            ),
                          ),
                          child: pw.Row(
                            children: [
                              pw.Container(
                                width: 18,
                                decoration: const pw.BoxDecoration(
                                  color: PdfColors.white,
                                  border: pw.Border(
                                    left: pw.BorderSide(color: PdfColors.black, width: 0.8),
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

  static List<pw.Widget> _buildTraditionalExamWidgets(ExamModel exam, pw.Font ttf) {
    final List<pw.Widget> widgets = [];
    List<QuestionModel> currentChunk = [];

    for (int i = 0; i < exam.questions.length; i++) {
      final q = exam.questions[i];
      final fullText = q.spans.map((s) => s.text).join('');
      final bool hasPageBreak = fullText.contains('[فاصل_صفحة]');

      currentChunk.add(q);

      if (hasPageBreak && i < exam.questions.length - 1) {
        widgets.add(_buildQuestionsSubTable(currentChunk, exam.header.instructionText, ttf));
        widgets.add(pw.NewPage());
        currentChunk = [];
      }
    }

    if (currentChunk.isNotEmpty) {
      widgets.add(_buildQuestionsSubTable(currentChunk, exam.header.instructionText, ttf));
    }

    return widgets;
  }

  static pw.Widget _buildQuestionsSubTable(
    List<QuestionModel> questions,
    String instructionText,
    pw.Font ttf,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
      columnWidths: {
        0: const pw.FixedColumnWidth(35),
        1: const pw.FlexColumnWidth(),
        2: const pw.FixedColumnWidth(35),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('الدرجة',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(instructionText,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: ttf,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red900)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('السؤال',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        ...questions.map((q) {
          return pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                child: pw.Center(
                  child: pw.Text(
                    q.mark > 0 ? '${q.mark.toInt()} د' : '-',
                    style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _buildPdfQuestionContent(q, ttf),
                    if (q.elements.isNotEmpty) pw.SizedBox(height: 4),
                    ...q.elements.map((el) => _buildPdfElement(el, ttf)),
                  ],
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                child: pw.Center(
                  child: pw.Text(q.title,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  static PdfColor _parsePdfColor(String? hexString, {PdfColor defaultColor = PdfColors.black}) {
    if (hexString == null || hexString.isEmpty) return defaultColor;
    try {
      final clean = hexString.replaceAll('#', '').trim();
      if (clean.length == 6) {
        final r = int.parse(clean.substring(0, 2), radix: 16) / 255.0;
        final g = int.parse(clean.substring(2, 4), radix: 16) / 255.0;
        final b = int.parse(clean.substring(4, 6), radix: 16) / 255.0;
        return PdfColor(r, g, b);
      }
    } catch (_) {}
    return defaultColor;
  }

  static pw.Widget _buildPdfQuestionContent(QuestionModel q, pw.Font ttf) {
    if (!q.isTwoColumns) {
      return pw.Column(
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
          );
        }).toList(),
      );
    }

    final fullText = q.spans.map((s) => s.text).join('').replaceAll('[فاصل_صفحة]', '').trim();
    final lines = fullText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) {
      return pw.Column(
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
          );
        }).toList(),
      );
    }

    final intro = lines.first;
    final items = lines.sublist(1);
    final int half = (items.length / 2).ceil();
    final colRight = items.sublist(0, half);
    final colLeft = items.sublist(half);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _renderInlineMathText(intro, ttf, fontSize: 11, isBold: true),
        pw.SizedBox(height: 3),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: colRight
                    .map((item) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                          child: _renderInlineMathText(item, ttf, fontSize: 10),
                        ))
                    .toList(),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: colLeft
                    .map((item) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                          child: _renderInlineMathText(item, ttf, fontSize: 10),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ],
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
  }) {
    final regExp = RegExp(r'(\[(?:كسر|جذر|sqrt|عمودي|قسمة|div|نها|تباديل|توافيق|مجموع|تكامل|متجه|بار|محدد|مصفوفة):.*?\]|✔|✘|✓|✗)');
    final matches = regExp.allMatches(text);

    if (matches.isEmpty) {
      return pw.Text(
        text,
        textAlign: pw.TextAlign.right,
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
          final bool isRtl = type == 'جذر';
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
          final v = parts.isNotEmpty ? parts[0] : 'س';
          final t = parts.length > 1 ? parts[1] : '٠';
          final fn = parts.length > 2 ? parts[2] : '';

          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'نهـا',
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
                          crossAxisAlignment: CrossAxisAlignment.center,
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
          final n = parts.isNotEmpty ? parts[0] : 'ن';
          final r = parts.length > 1 ? parts[1] : 'ر';
          final sym = type == 'تباديل' ? 'ل' : 'ق';

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
          final sym = type == 'مجموع' ? 'مجـ' : '∫';

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
          final s = parts.isNotEmpty ? parts[0] : 'ق';
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
          final s = parts.isNotEmpty ? parts[0] : 'س';
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
          final numbers = parts.length > 1 ? parts.sublist(1) : <String>[];

          int maxDigits = 0;
          for (final num in numbers) {
            if (num.length > maxDigits) maxDigits = num.length;
          }
          final double lineWidth = (maxDigits * 8.0) + 20.0;

          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                child: pw.Directionality(
                  textDirection: pw.TextDirection.rtl,
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
          final bool isRtl = type == 'قسمة';
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
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        crossAxisAlignment: CrossAxisAlignment.center,
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
      textAlign: pw.TextAlign.right,
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

  static pw.Widget _buildPdfElement(InsertableElement el, pw.Font ttf) {
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
        return _buildPdfCustomTable(el.content, ttf);

      case ElementType.shape:
        return _buildPdfCustomShape(el.content, ttf);

      case ElementType.mathOperation:
        try {
          final data = jsonDecode(el.content);
          final kind = data['kind'] ?? 'vertical';

          if (kind == 'vertical') {
            final List<dynamic> rows = data['rows'] ?? [];
            final String op = data['operator'] ?? '+';
            final bool opOnRight = data['opOnRight'] ?? true;

            return pw.Center(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(vertical: 4),
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: pw.Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
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

  static pw.Widget _buildPdfCustomTable(String jsonStr, pw.Font ttf) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final int rows = data['rows'] ?? 2;
      final int cols = data['cols'] ?? 2;
      final bool hasHeader = data['hasHeader'] ?? true;
      final List<dynamic> rawGrid = data['data'] ?? [];

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
                final c = cols - 1 - colIndex;
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
                          ..lineTo(pw_x - 2, pw_y - 2)
                          ..lineTo(pw_x - offset, 2)
                          ..lineTo(2, 2)
                          ..closePath()
                          ..fillPath();
                      }
                      canvas
                        ..moveTo(offset, pw_y - 2)
                        ..lineTo(pw_x - 2, pw_y - 2)
                        ..lineTo(pw_x - offset, 2)
                        ..lineTo(2, 2)
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

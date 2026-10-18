import 'dart:convert';
import 'dart:io';
import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam_models.dart';
import 'student_excel_service.dart';

class PdfExportService {
  // ثوابت تحويل الأبعاد إلى نقاط الطباعة
  static const double cm = 28.3465;
  static const double mm = 2.83465;

  static Future<String> exportToDownloadsPdf(ExamModel exam) async {
    final pdf = pw.Document();

    ByteData fontData;
    try {
      fontData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    } catch (_) {
      fontData = await rootBundle.load('assets/fonts/amiri-regular.ttf');
    }
    final ttf = pw.Font.ttf(fontData);

    pw.MemoryImage? logoImage;
    if (exam.header.logoImagePath != null &&
        File(exam.header.logoImagePath!).existsSync()) {
      final bytes = await File(exam.header.logoImagePath!).readAsBytes();
      logoImage = pw.MemoryImage(bytes);
    }

    // 1. فحص هل تم تفعيل وضع تخصيص أوراق الطلاب من الإكسيل
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

    // 2. إذا كان الخيار "ورق عادي" أو لم يتم استيراد كشف، نطبع نسخة عامة واحدة فقط
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
          margin: pw.EdgeInsets.only(
            top: 3.0 * mm,     // 3 مم من الحافة العلوية للورقة
            bottom: 4.0 * mm,  // 4 مم من الحافة السفلية للورقة
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
                      // الجهة اليمنى: توقيع المعلم
                      pw.Text(
                        exam.header.teacherSignature,
                        style: pw.TextStyle(font: ttf, fontSize: 9.0),
                      ),

                      // الجهة اليسرى:
                      // [كود المادة: 20 عريض بدون إطار] -> [رمز QR: 40x40 مشفر داخله الرقم السري] -> [مربع فارغ تماماً: 50x60]
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
                              width: 50,
                              height: 40,
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
                _buildTraditionalQuestionsTable(exam, ttf),
            ];
          },
        ),
      );
    }

    Directory dir;
    if (Platform.isAndroid) {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync()) {
        dir = downloadDir;
      } else {
        dir = (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
      }
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    final safeName = exam.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${dir.path}/$safeName.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save(), flush: true);

    return filePath;
  }

  // ترويسة الاختبار الرسمية
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
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
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

  // بناء الأسئلة المؤتمتة بالتسطير والجدولة الهندسية
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

    // قسم فقرات الصح والخطأ
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

    // قسم فقرات الاختيار من متعدد
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

  // بناء فقرة اختيار من متعدد: تم إزالة السواد وجعل الخلفية بيضاء نقية
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
          // 1. عمود رقم الفقرة على اليمين
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

          // 2. الجانب الأيسر: مقسوم أفقياً (نص السؤال، والصف السفلي للخيارات)
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // أ. نص السؤال
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

                // ب. صف البدائل الأربعة المجدولة بخلفية بيضاء نقية (بدون سواد)
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
                              // مربع رمز الاختيار بخلفية بيضاء وحد أسود واضح وبدون أي سواد
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
                              // مساحة نص الاختيار
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

  // بناء جدول الأسئلة الشاملة التقليدية
  static pw.Widget _buildTraditionalQuestionsTable(ExamModel exam, pw.Font ttf) {
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
              child: pw.Text('السؤال',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text(exam.header.instructionText,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      font: ttf,
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red900)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('الدرجة',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        ...exam.questions.map((q) {
          return pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 6),
                child: pw.Center(
                  child: pw.Text(q.title,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
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
                  child: pw.Text(
                    q.mark > 0 ? '${q.mark.toInt()} د' : '-',
                    style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  // بناء نص السؤال
  static pw.Widget _buildPdfQuestionContent(QuestionModel q, pw.Font ttf) {
    final fullText = q.spans.map((s) => s.text).join('');

    if (!q.isTwoColumns) {
      return _renderInlineMathText(fullText, ttf, fontSize: 11, lineSpacing: 2);
    }

    final lines = fullText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) {
      return _renderInlineMathText(fullText, ttf, fontSize: 11, lineSpacing: 2);
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

  // دالة تحويل وسوم الرياضيات المضمنة
  static pw.Widget _renderInlineMathText(
    String text,
    pw.Font ttf, {
    double fontSize = 11,
    bool isBold = false,
    double lineSpacing = 1.5,
  }) {
    final regExp = RegExp(r'\[(كسر|جذر|sqrt|عمودي):(.*?)\]');
    final matches = regExp.allMatches(text);

    if (matches.isEmpty) {
      return pw.Text(
        text,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          font: ttf,
          fontSize: fontSize,
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

      final type = m.group(1);
      final rawContent = m.group(2) ?? '';

      if (type == 'كسر') {
        final parts = rawContent.split('/');
        final num = parts.isNotEmpty ? parts[0] : '';
        final den = parts.length > 1 ? parts[1] : '';

        final int maxLen = num.length > den.length ? num.length : den.length;
        final double lineWidth = (maxLen * 7.0) + 6.0;

        spans.add(
          pw.WidgetSpan(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2.5),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text(
                    num,
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: fontSize * 0.85,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Container(width: lineWidth, height: 0.8, color: PdfColors.black),
                  pw.Text(
                    den,
                    style: pw.TextStyle(
                      font: ttf,
                      fontSize: fontSize * 0.85,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else if (type == 'جذر') {
        final parts = rawContent.split(':');
        final String degree = parts.length > 1 ? parts[0] : '';
        final String radicand = parts.length > 1 ? parts.sublist(1).join(':') : parts[0];

        spans.add(
          pw.WidgetSpan(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
              child: pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (degree.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 0.0, left: 1.5),
                        child: pw.Text(
                          degree,
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: fontSize * 0.70,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    pw.Text(
                      '⎷',
                      style: pw.TextStyle(
                        font: ttf,
                        fontSize: fontSize * 1.35,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 2),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: PdfColors.black, width: 0.9),
                        ),
                      ),
                      padding: const pw.EdgeInsets.only(top: 1, left: 2, right: 2),
                      child: pw.Text(
                        radicand,
                        style: pw.TextStyle(
                          font: ttf,
                          fontSize: fontSize * 0.95,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else if (type == 'sqrt') {
        final parts = rawContent.split(':');
        final String degree = parts.length > 1 ? parts[0] : '';
        final String radicand = parts.length > 1 ? parts.sublist(1).join(':') : parts[0];

        spans.add(
          pw.WidgetSpan(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
              child: pw.Directionality(
                textDirection: pw.TextDirection.ltr,
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    if (degree.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(top: 0.0, right: 1.5),
                        child: pw.Text(
                          degree,
                          style: pw.TextStyle(
                            font: ttf,
                            fontSize: fontSize * 0.70,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    pw.Text(
                      '√',
                      style: pw.TextStyle(
                        font: ttf,
                        fontSize: fontSize * 1.35,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Container(
                      margin: const pw.EdgeInsets.only(top: 2),
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: PdfColors.black, width: 0.9),
                        ),
                      ),
                      padding: const pw.EdgeInsets.only(top: 1, left: 2, right: 2),
                      child: pw.Text(
                        radicand,
                        style: pw.TextStyle(
                          font: ttf,
                          fontSize: fontSize * 0.95,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      } else if (type == 'عمودي') {
        final parts = rawContent.split(':');
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
                      color: PdfColors.black,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
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
}

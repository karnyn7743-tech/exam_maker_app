import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam_models.dart';

class PdfExportService {
  static Future<String> exportToDownloadsPdf(ExamModel exam) async {
    final pdf = pw.Document();

    // تحميل الخط من الأصول المحلية مباشرة
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

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.only(
          top: exam.header.topMargin1cm ? 28.3 : 20.0,
          bottom: 20.0,
          left: 20.0,
          right: 20.0,
        ),
        textDirection: pw.TextDirection.rtl,
        build: (pw.Context context) {
          return [
            // 1. ترويسة الاختبار
            pw.Container(
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
                                    font: ttf,
                                    fontSize: 10,
                                    fontWeight: pw.FontWeight.bold),
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
                                    font: ttf,
                                    fontSize: 8.5,
                                    fontWeight: pw.FontWeight.bold),
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
                                    font: ttf,
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold),
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
                                    font: ttf,
                                    fontSize: 9.5,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.Text('المادة : ${exam.header.subject}',
                                style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 9.5,
                                    fontWeight: pw.FontWeight.bold)),
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
            ),
            pw.SizedBox(height: 6),

            // 2. جدول الأسئلة
            pw.Table(
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
                          style: pw.TextStyle(
                              font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
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
                          style: pw.TextStyle(
                              font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
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
                              style: pw.TextStyle(
                                  font: ttf,
                                  fontSize: 9.5,
                                  fontWeight: pw.FontWeight.bold)),
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
                            style: pw.TextStyle(
                                font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 8),

            // 3. التذييل
            pw.Column(
              children: [
                pw.Center(
                  child: pw.Text(
                    exam.header.isMultiPage
                        ? exam.header.continuationText
                        : exam.header.singlePageFooterText,
                    style: pw.TextStyle(
                        font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Align(
                  alignment: pw.Alignment.centerLeft,
                  child: pw.Text(
                    exam.header.teacherSignature,
                    style: pw.TextStyle(font: ttf, fontSize: 9.5),
                  ),
                ),
              ],
            ),
          ];
        },
      ),
    );

    Directory dir;
    if (Platform.isAndroid) {
      dir = (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
    } else {
      dir = await getApplicationDocumentsDirectory();
    }

    final safeName = exam.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${dir.path}/$safeName.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save(), flush: true);

    return filePath;
  }

  static pw.Widget _buildPdfQuestionContent(QuestionModel q, pw.Font ttf) {
    final fullText = q.spans.map((s) => s.text).join('');

    if (!q.isTwoColumns) {
      return pw.Text(
        fullText,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(font: ttf, fontSize: 11, lineSpacing: 2),
      );
    }

    final lines = fullText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) {
      return pw.Text(
        fullText,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(font: ttf, fontSize: 11, lineSpacing: 2),
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
        pw.Text(
          intro,
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
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
                          child: pw.Text(item,
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(font: ttf, fontSize: 10)),
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
                          child: pw.Text(item,
                              textAlign: pw.TextAlign.right,
                              style: pw.TextStyle(font: ttf, fontSize: 10)),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ],
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

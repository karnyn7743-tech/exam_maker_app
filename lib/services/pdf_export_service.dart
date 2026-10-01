import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/exam_models.dart';
import 'file_manager.dart';

class PdfExportService {
  static Future<String?> exportToDownloadsPdf(ExamModel exam) async {
    // 1. طلب إذن التخزين إن لزم
    if (Platform.isAndroid) {
      await Permission.storage.request();
    }

    final pdf = pw.Document();

    // 2. تحميل خط الأميري لدعم العربية في PDF
    final fontRegular = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final fontBold = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
    final ttfRegular = pw.Font.ttf(fontRegular);
    final ttfBold = pw.Font.ttf(fontBold);

    // 3. تجهيز صورة الشعار إن وجدت
    pw.MemoryImage? logoImage;
    if (exam.header.logoImagePath != null && File(exam.header.logoImagePath!).existsSync()) {
      final bytes = File(exam.header.logoImagePath!).readAsBytesSync();
      logoImage = pw.MemoryImage(bytes);
    }

    // 4. بناء صفحة A4 متوافقة مع الاتجاه العربي RTL
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: ttfRegular, bold: ttfBold),
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // إطار الترويسة
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1.5),
                ),
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // الجهة اليمنى
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(exam.header.country, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.Text(exam.header.ministry, style: const pw.TextStyle(fontSize: 8)),
                            pw.Text('مكتب التربية بمحافظة ${exam.header.governorate}', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text('إدارة التربية بمديرية ${exam.header.directorate}', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text(exam.header.school, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                          ],
                        ),
                        // الوسط: الشعار والبسملة
                        pw.Column(
                          children: [
                            pw.Text(exam.header.basmalaText, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                            pw.SizedBox(height: 4),
                            if (logoImage != null)
                              pw.Image(logoImage, height: 40, width: 40)
                            else
                              pw.SizedBox(height: 40),
                          ],
                        ),
                        // الجهة اليسرى
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('الصف : ${exam.header.grade}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                            pw.Text('المادة : ${exam.header.subject}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                            pw.Text('التاريخ: ${exam.header.examDate}', style: const pw.TextStyle(fontSize: 8)),
                            pw.Text('الزمن: ${exam.header.examTime}', style: const pw.TextStyle(fontSize: 8)),
                          ],
                        ),
                      ],
                    ),
                    pw.Divider(thickness: 1),
                    pw.Center(
                      child: pw.Text(exam.header.examTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 6),

              // جدول الأسئلة
              pw.Expanded(
                child: pw.Table(
                  border: pw.TableBorder.all(width: 0.8),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(40), // السؤال
                    1: const pw.FlexColumnWidth(),   // المحتوى
                    2: const pw.FixedColumnWidth(35), // الدرجة
                  },
                  children: exam.questions.map((q) {
                    return pw.TableRow(
                      children: [
                        pw.Center(child: pw.Text(q.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(q.spans.map((s) => s.text).join(' '), style: const pw.TextStyle(fontSize: 10)),
                              ...q.elements.map((el) => pw.Text(el.content, style: const pw.TextStyle(fontSize: 10))),
                            ],
                          ),
                        ),
                        pw.Center(child: pw.Text(q.mark > 0 ? '${q.mark}' : '-', style: const pw.TextStyle(fontSize: 9))),
                      ],
                    );
                  }).toList(),
                ),
              ),

              // التذييل والتوقيع
              pw.SizedBox(height: 6),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(exam.header.singlePageFooterText, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  pw.Text(exam.header.teacherSignature, style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          );
        },
      ),
    );

    // 5. حفظ الملف في مجلد التنزيلات الخارجي: /storage/emulated/0/Download/ExamMaker/
    Directory? downloadDir;
    if (Platform.isAndroid) {
      downloadDir = Directory('/storage/emulated/0/Download/ExamMaker');
      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }
    } else {
      downloadDir = await getApplicationDocumentsDirectory();
    }

    final safeName = FileManager.sanitizeFileName(exam.fileName);
    final outputFilePath = '${downloadDir.path}/$safeName.pdf';
    final file = File(outputFilePath);
    await file.writeAsBytes(await pdf.save());

    return outputFilePath;
  }
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/exam_models.dart';
import 'pdf_export_service.dart';

class DirectPrintService {
  /// إرسال الاختبار أو نموذج الإجابة مباشرة إلى الطابعة
  static Future<void> printExamDocument({
    required BuildContext context,
    required ExamModel exam,
    required bool isAnswerKey,
  }) async {
    try {
      final String docTitle = isAnswerKey
          ? '${exam.fileName} - نموذج الإجابة'
          : '${exam.fileName} - ورقة الاختبار';

      await Printing.layoutPdf(
        name: docTitle,
        format: PdfPageFormat.a4,
        onLayout: (PdfPageFormat format) async {
          // توليد ملف PDF باستخدام الخدمة المعتمدة في المشروع
          final Uint8List pdfBytes = await PdfExportService.generatePdfBytes(exam);
          return pdfBytes;
        },
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إتمام أمر الطباعة المباشرة: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  /// إرسال ورقة التظليل (OMR Sheet) مباشرة إلى الطابعة
  static Future<void> printOmrDocument({
    required BuildContext context,
    required Uint8List omrPdfBytes,
    required String examTitle,
  }) async {
    try {
      await Printing.layoutPdf(
        name: 'ورقة التظليل OMR - $examTitle',
        format: PdfPageFormat.a4,
        onLayout: (PdfPageFormat format) async => omrPdfBytes,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر إرسال ورقة التظليل للطابعة: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
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

      // تصدير PDF وقراءة البايتات مباشرة بشكل آمن ومطابق لمشروعك
      final filePath = await PdfExportService.exportToDownloadsPdf(exam);
      final pdfBytes = await File(filePath).readAsBytes();

      await Printing.layoutPdf(
        name: docTitle,
        format: PdfPageFormat.a4,
        onLayout: (PdfPageFormat format) async => pdfBytes,
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
}

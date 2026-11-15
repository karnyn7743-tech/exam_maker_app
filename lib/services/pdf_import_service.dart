import 'dart:io';

import 'dart:ui' show Rect;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';

/// يحول صفحات PDF المحددة إلى صور PNG عالية الدقة يحتفظ بها ملف الاختبار.
class PdfImportService {
  static const double _pointsPerMillimeter = 72.0 / 25.4;

  static Future<int> getPageCount(String pdfPath) async {
    final document = await PdfDocument.openFile(pdfPath);
    try {
      return document.pagesCount;
    } finally {
      await document.close();
    }
  }

  static Future<List<String>> importPages({
    required String pdfPath,
    required String examId,
    required int firstPage,
    required int pageCount,
    required double cropTopMm,
    required double cropBottomMm,
  }) async {
    if (pageCount < 1 || pageCount > 3) {
      throw ArgumentError('يمكن استيراد صفحة واحدة إلى ثلاث صفحات فقط.');
    }

    final document = await PdfDocument.openFile(pdfPath);
    final createdPaths = <String>[];

    try {
      if (firstPage < 1 || firstPage + pageCount - 1 > document.pagesCount) {
        throw RangeError('نطاق الصفحات المحدد خارج عدد صفحات ملف PDF.');
      }

      final baseDirectory = await getApplicationDocumentsDirectory();
      final outputDirectory = Directory(
        '${baseDirectory.path}/imported_pdf/$examId',
      );
      await outputDirectory.create(recursive: true);

      for (var offset = 0; offset < pageCount; offset++) {
        final pageNumber = firstPage + offset;
        final page = await document.getPage(pageNumber);

        try {
          final renderWidth = page.width * 2;
          final renderHeight = page.height * 2;
          final topCrop = (cropTopMm * _pointsPerMillimeter * 2)
              .clamp(0.0, renderHeight - 1.0)
              .toDouble();
          final bottomCrop = (cropBottomMm * _pointsPerMillimeter * 2)
              .clamp(0.0, renderHeight - topCrop - 1.0)
              .toDouble();

          final image = await page.render(
            width: renderWidth,
            height: renderHeight,
            format: PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
            quality: 92,
            cropRect: Rect.fromLTRB(
              0,
              topCrop,
              renderWidth.toDouble(),
              renderHeight - bottomCrop,
            ),
          );

          if (image == null || image.bytes.isEmpty) {
            throw Exception('تعذر تحويل صفحة PDF رقم $pageNumber إلى صورة.');
          }

          final outputFile = File(
            '${outputDirectory.path}/page_${(offset + 1).toString().padLeft(2, '0')}.png',
          );
          await outputFile.writeAsBytes(image.bytes, flush: true);
          createdPaths.add(outputFile.path);

          await page.close();
        } catch (_) {
          if (!page.isClosed) {
            await page.close();
          }
          rethrow;
        }
      }

      return createdPaths;
    } catch (_) {
      for (final path in createdPaths) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      await document.close();
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:barcode/barcode.dart';
import 'package:better_download_saver/better_download_saver.dart';
import 'package:flutter/material.dart' show TextAlign;
import 'package:flutter/services.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/exam_models.dart';
import '../utils/app_font_catalog.dart';
import 'student_excel_service.dart';

class PdfExportService {
  static const Map<String, String> _pdfSuperscriptMap = {
    '⁰': '0', '¹': '1', '²': '2', '³': '3', '⁴': '4',
    '⁵': '5', '⁶': '6', '⁷': '7', '⁸': '8', '⁹': '9',
    '⁺': '+', '⁻': '-', '⁼': '=', '⁽': '(', '⁾': ')',
    'ⁿ': 'n', 'ˣ': 'x', 'ʸ': 'y', 'ᵃ': 'a', 'ᵇ': 'b',
    'ᶜ': 'c', 'ᵈ': 'd', 'ᵉ': 'e', 'ᶠ': 'f', 'ᵍ': 'g',
    'ʰ': 'h', 'ⁱ': 'i', 'ʲ': 'j', 'ᵏ': 'k', 'ˡ': 'l',
    'ᵐ': 'm', 'ᵒ': 'o', 'ᵖ': 'p', 'ʳ': 'r', 'ˢ': 's',
    'ᵗ': 't', 'ᵘ': 'u', 'ᵛ': 'v', 'ʷ': 'w', 'ᶻ': 'z',
  };
  static const Map<String, String> _pdfSubscriptMap = {
    '₀': '0', '₁': '1', '₂': '2', '₃': '3', '₄': '4',
    '₅': '5', '₆': '6', '₇': '7', '₈': '8', '₉': '9',
    '₊': '+', '₋': '-', '₌': '=', '₍': '(', '₎': ')',
    'ₐ': 'a', 'ₑ': 'e', 'ₒ': 'o', 'ₓ': 'x', 'ₙ': 'n',
    'ₕ': 'h', 'ₖ': 'k', 'ₗ': 'l', 'ₘ': 'm', 'ₚ': 'p',
    'ₛ': 's', 'ₜ': 't',
  };

  static MapEntry<bool, String>? _parsePdfScriptToken(String token) {
    if (token.startsWith('^{') && token.endsWith('}')) {
      return MapEntry(true, token.substring(2, token.length - 1));
    }
    if (token.startsWith('_{') && token.endsWith('}')) {
      return MapEntry(false, token.substring(2, token.length - 1));
    }
    if (token.startsWith('^')) return MapEntry(true, token.substring(1));
    if (token.startsWith('_')) return MapEntry(false, token.substring(1));
    final chars = token.split('');
    if (chars.isNotEmpty && chars.every(_pdfSuperscriptMap.containsKey)) {
      return MapEntry(true, chars.map((c) => _pdfSuperscriptMap[c]!).join());
    }
    if (chars.isNotEmpty && chars.every(_pdfSubscriptMap.containsKey)) {
      return MapEntry(false, chars.map((c) => _pdfSubscriptMap[c]!).join());
    }
    return null;
  }

  static List<pw.InlineSpan> _pdfScriptAwareSpans(
    String text,
    pw.TextStyle baseStyle,
  ) {
    final pattern = RegExp(r'(\^\{[^}]+\}|_\{[^}]+\}|\^[0-9٠-٩+\-−=()]+|_[0-9٠-٩+\-−=()]+|[⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿˣʸᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐᵒᵖʳˢᵗᵘᵛʷᶻ]+|[₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₒₓₙₕₖₗₘₚₛₜ]+)');
    final result = <pw.InlineSpan>[];
    var lastIndex = 0;
    for (final match in pattern.allMatches(text)) {
      final matchedStr = match.group(0) ?? '';
      if (match.start > lastIndex) {
        result.add(pw.TextSpan(text: text.substring(lastIndex, match.start)));
      }
      final parsed = _parsePdfScriptToken(matchedStr);
      if (parsed == null) {
        result.add(pw.TextSpan(text: matchedStr));
      } else {
        final baseSize = baseStyle.fontSize ?? 11;
        result.add(pw.WidgetSpan(
          child: pw.Transform.translate(
            offset: PdfPoint(
              0,
              parsed.key ? baseSize * 0.30 : -baseSize * 0.20,
            ),
            child: pw.Text(
              parsed.value,
              style: baseStyle.copyWith(fontSize: baseSize * 0.62),
            ),
          ),
        ));
      }
      lastIndex = match.end;
    }
    if (lastIndex < text.length) {
      result.add(pw.TextSpan(text: text.substring(lastIndex)));
    }
    if (result.isEmpty) result.add(pw.TextSpan(text: text));
    return result;
  }

  // The PDF exporter reads the same font catalog used by the editor toolbar.
  static final Map<String, String> _fontAssetPaths = {
    for (final item in appFontsList) item['id']!: item['asset']!,
  };
  static final Map<String, pw.Font> _pdfFontByFamily = {};
  static final Set<String> _attemptedFontFamilies = {};

  static const double cm = 28.3465;
  static const double mm = 2.83465;

  /// دالة مساعدة لتنسيق الدرجة بحذف الأصفار العشرية الزائدة
  static String _formatMark(double mark, bool isArabic) {
    if (mark <= 0) return '-';
    final unit = isArabic ? 'د' : 'm';
    if (mark % 1 == 0) {
      return '${mark.toInt()} $unit';
    }
    return '$mark $unit';
  }

  static bool _isExporting = false;

  static Future<String> exportToDownloadsPdf(ExamModel exam) async {
    if (_isExporting) {
      throw StateError('توجد عملية تصدير PDF أخرى قيد التنفيذ.');
    }
    _isExporting = true;
    _pdfFontByFamily.clear();
    _attemptedFontFamilies.clear();
    try {
      return await _exportToDownloadsPdfInternal(exam);
    } finally {
      // لا نحتفظ بكائنات الخطوط المرتبطة بمستند PDF بعد انتهاء التصدير.
      _pdfFontByFamily.clear();
      _attemptedFontFamilies.clear();
      _isExporting = false;
    }
  }

  /// تحميل خط محدد عند الحاجة إليه فقط لتقليل استهلاك الذاكرة أثناء التصدير.
  static Future<pw.Font> _loadFontIfNeeded(String? family, pw.Font fallback) async {
    final raw = (family ?? '').trim();
    if (raw.isEmpty) return fallback;

    final normalizedTarget = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final entry in _pdfFontByFamily.entries) {
      final candidate = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (candidate == normalizedTarget) {
        return entry.value;
      }
    }

    String? matchedKey;
    for (final key in _fontAssetPaths.keys) {
      final candidate = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (candidate == normalizedTarget) {
        matchedKey = key;
        break;
      }
    }

    if (matchedKey == null || _attemptedFontFamilies.contains(matchedKey)) {
      return fallback;
    }

    _attemptedFontFamilies.add(matchedKey);
    final assetPath = _fontAssetPaths[matchedKey];
    if (assetPath == null || assetPath.isEmpty) {
      return fallback;
    }

    try {
      final data = await rootBundle.load(assetPath);
      final loadedFont = pw.Font.ttf(data);
      _pdfFontByFamily[matchedKey] = loadedFont;
      return loadedFont;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> _preloadExamFonts(ExamModel exam, pw.Font fallback) async {
    final families = <String>{
      exam.header.adminFont,
      exam.header.basmalaFont,
      exam.header.detailsFont,
      exam.header.titleFont,
    };

    for (final q in exam.questions) {
      for (final span in q.spans) {
        if (span.fontFamily.trim().isNotEmpty) {
          families.add(span.fontFamily);
        }
      }
      if (q.richDocumentJson != null && q.richDocumentJson!.isNotEmpty) {
        try {
          final decoded = jsonDecode(q.richDocumentJson!);
          if (decoded is Map<String, dynamic>) {
            final document = FluentDocument.fromJson(decoded);
            _collectRichNodeFonts(document.content.nodes, families);
          }
        } catch (_) {}
      }
    }

    for (final fam in families) {
      await _loadFontIfNeeded(fam, fallback);
    }
  }

  static void _collectRichNodeFonts(List<FNode> nodes, Set<String> families) {
    for (final node in nodes) {
      if (node is Paragraph) {
        for (final fragment in node.fragments) {
          if (fragment is Link) {
            for (final child in fragment.fragments) {
              if (child is Fragment && child.fontFamily != null && child.fontFamily!.trim().isNotEmpty) {
                families.add(child.fontFamily!);
              }
            }
          } else if (fragment is Fragment && fragment.fontFamily != null && fragment.fontFamily!.trim().isNotEmpty) {
            families.add(fragment.fontFamily!);
          }
        }
      } else if (node is FluentList) {
        for (final item in node.items) {
          _collectRichNodeFonts(item.children, families);
        }
      } else if (node is FluentTable) {
        for (final row in node.rows) {
          for (final cell in row.cells) {
            _collectRichNodeFonts(cell.children, families);
          }
        }
      }
    }
  }

  static Future<String> _exportToDownloadsPdfInternal(ExamModel exam) async {
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

    _pdfFontByFamily.clear();
    _attemptedFontFamilies.clear();
    _pdfFontByFamily['Arial'] = ttf;
    _pdfFontByFamily['Amiri'] = ttf;

    // تحميل الخطوط المستخدمة فعلياً في هذا الاختبار فقط لتوفير الذاكرة.
    await _preloadExamFonts(exam, ttf);

    pw.MemoryImage? logoImage;
    if (exam.header.logoImagePath != null &&
        File(exam.header.logoImagePath!).existsSync()) {
      final bytes = await File(exam.header.logoImagePath!).readAsBytes();
      logoImage = pw.MemoryImage(bytes);
    }

    final Map<String, pw.MemoryImage> importedPdfImages = {};
    for (final imagePath in exam.importedPdfPagePaths) {
      final imageFile = File(imagePath);
      if (await imageFile.exists()) {
        importedPdfImages[imagePath] =
            pw.MemoryImage(await imageFile.readAsBytes());
      }
    }

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

    final bool isAr = exam.isArabic;
    final bool isAutomated = exam.examType == ExamType.automated;

    final List<String> symbols;
    if (exam.automatedConfig.choiceSymbolType == ChoiceSymbolType.numbers) {
      symbols = isAr ? ['١', '٢', '٣', '٤'] : ['1', '2', '3', '4'];
    } else {
      symbols = isAr ? ['أ', 'ب', 'جـ', 'د'] : ['A', 'B', 'C', 'D'];
    }

    final pw.TextDirection pageDir = isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr;

    final List<List<QuestionModel>> pagesQuestions = [[]];
    for (final q in exam.questions) {
      final fullText = q.spans.map((s) => s.text).join('');
      if (q.id.startsWith('page_break_') || fullText.contains('[فاصل_صفحة]')) {
        pagesQuestions.add([]);
      } else {
        pagesQuestions.last.add(q);
      }
    }

    for (final student in studentsToIterate) {
      final bool hasStudent = student.seatNo.isNotEmpty;
      final bool showQrMode = hasStudent &&
          exam.header.studentDataMode == 'namesAndQr' &&
          !isAutomated;
      final bool reserveStudentFooterArea = hasStudent &&
          exam.header.topMargin1cm &&
          exam.header.studentDataMode != 'none';

      for (int pageIdx = 0; pageIdx < pagesQuestions.length; pageIdx++) {
        final currentQuestions = pagesQuestions[pageIdx];
        final bool isFirstPage = pageIdx == 0;
        final bool isLastPage = pageIdx == pagesQuestions.length - 1;
        final String? importedPdfPagePath =
            pageIdx < exam.importedPdfPagePaths.length
                ? exam.importedPdfPagePaths[pageIdx]
                : null;
        final bool hasImportedPdfPage = importedPdfPagePath != null &&
            File(importedPdfPagePath).existsSync();

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.only(
              top: 5.0 * mm,
              bottom: 6.0 * mm,
              left: 20.0,
              right: 20.0,
            ),
            textDirection: pageDir,
            footer: (pw.Context footerContext) {
              final bool footerHasQr = showQrMode && isFirstPage;
              final double footerHeight = reserveStudentFooterArea && isFirstPage
                  ? 3.0 * cm
                  : 1.0 * cm;

              return pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Container(
                  height: footerHeight,
                  alignment: pw.Alignment.bottomCenter,
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Center(
                        child: pw.Text(
                          isLastPage
                              ? (exam.header.singlePageFooterText.isNotEmpty
                                  ? exam.header.singlePageFooterText
                                  : (isAr ? 'انتهت الأسئلة مع تمنياتنا لكم بالتوفيق والنجاح' : 'End of Questions - Best of Luck'))
                              : (exam.header.continuationText.isNotEmpty
                                  ? exam.header.continuationText
                                  : (isAr ? 'يتبع في الصفحة التالية...' : 'To be continued on next page...')),
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
                            exam.header.teacherSignature.isNotEmpty
                                ? exam.header.teacherSignature
                                : (isAr ? 'معلم المادة: ......................' : 'Teacher: ......................'),
                            style: pw.TextStyle(font: ttf, fontSize: 9.0),
                          ),
                          if (footerHasQr)
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Text(
                                  '$currentSubjectCode',
                                  style: pw.TextStyle(
                                    font: ttf,
                                    fontSize: 22,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                ),
                                pw.SizedBox(width: 8),
                                if (student.secretCode.isNotEmpty)
                                  pw.Container(
                                    width: 38,
                                    height: 38,
                                    child: pw.BarcodeWidget(
                                      barcode: Barcode.qrCode(),
                                      data: student.secretCode,
                                      drawText: false,
                                    ),
                                  )
                                else
                                  pw.SizedBox(width: 38, height: 38),
                                pw.SizedBox(width: 10),
                                pw.Container(
                                  width: 55,
                                  height: 45,
                                  decoration: pw.BoxDecoration(
                                    border: pw.Border.all(color: PdfColors.black, width: 1.2),
                                  ),
                                ),
                              ],
                            )
                          else
                            pw.Text(
                              'صفحة ' + (pageIdx + 1).toString() + ' من ' + pagesQuestions.length.toString(),
                              style: pw.TextStyle(font: ttf, fontSize: 8.5),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
            build: (pw.Context context) {
              return [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    if (exam.header.topMargin1cm && hasStudent && isFirstPage) ...[
                      pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Padding(
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
                        ),
                      ),
                    ],
                    if (isFirstPage) ...[
                      pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: _buildExamHeaderBox(exam, ttf, logoImage, isAr),
                      ),
                    ] else ...[
                      pw.Directionality(
                        textDirection: pw.TextDirection.rtl,
                        child: pw.Container(
                          padding: const pw.EdgeInsets.symmetric(vertical: 6),
                          margin: const pw.EdgeInsets.only(bottom: 6),
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 1.2)),
                          ),
                          child: pw.Center(
                            child: pw.Text(
                              'تابع اختبار مادة ${exam.header.subject} للصف ${exam.header.grade}',
                              style: pw.TextStyle(font: ttf, fontSize: 13, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ],
                    pw.SizedBox(height: 5),
                    if (hasImportedPdfPage &&
                        importedPdfImages.containsKey(importedPdfPagePath))
                      pw.Image(
                        importedPdfImages[importedPdfPagePath]!,
                        width: PdfPageFormat.a4.width - 40.0,
                        fit: pw.BoxFit.fitWidth,
                        alignment: pw.Alignment.topLeft,
                      )
                    else if (isAutomated)
                      ..._buildAutomatedQuestionsList(exam, symbols, ttf, isAr)
                    else
                      _buildQuestionsSubTable(currentQuestions, exam.header.instructionText, ttf, isAr),
                    pw.SizedBox(height: 2),
                  ],
                ),
              ];
            },
          ),
        );
      }
    }

    final pdfBytes = await pdf.save();

    final gradeName = exam.header.grade.trim().isNotEmpty ? exam.header.grade.trim() : 'عام';
    final subjectName = exam.header.subject.trim().isNotEmpty ? exam.header.subject.trim() : 'مادة';
    final typeName = isAutomated ? (isAr ? 'مؤتمت' : 'Automated') : (isAr ? 'شامل' : 'Comprehensive');

    final defaultGeneratedName = '$gradeName _ $subjectName _ $typeName';
    final nameToUse = exam.fileName.trim().isNotEmpty && !exam.fileName.startsWith('اختبار_')
        ? exam.fileName.trim()
        : defaultGeneratedName;

    final safeName = nameToUse.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final fileName = '$safeName.pdf';

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
      throw Exception('تعذر حفظ ملف PDF: $e');
    }
  }

  static pw.Widget _buildExamHeaderBox(
    ExamModel exam,
    pw.Font ttf,
    pw.MemoryImage? logoImage,
    bool isAr,
  ) {
    final adminFont = _resolvePdfFont(exam.header.adminFont, ttf);
    final basmalaFont = _resolvePdfFont(exam.header.basmalaFont, ttf);
    final detailsFont = _resolvePdfFont(exam.header.detailsFont, ttf);
    final titleFont = _resolvePdfFont(exam.header.titleFont, ttf);

    final adminWeight = exam.header.adminBold
        ? pw.FontWeight.bold
        : pw.FontWeight.normal;
    final detailsWeight = exam.header.detailsBold
        ? pw.FontWeight.bold
        : pw.FontWeight.normal;
    final basmalaWeight = exam.header.basmalaBold
        ? pw.FontWeight.bold
        : pw.FontWeight.normal;
    final titleWeight = exam.header.titleBold
        ? pw.FontWeight.bold
        : pw.FontWeight.normal;

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
                    pw.Text(
                      exam.header.country,
                      style: pw.TextStyle(
                        font: adminFont,
                        fontSize: exam.header.adminFontSize + 1.5,
                        fontWeight: adminWeight,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.Text(
                      exam.header.ministry,
                      style: pw.TextStyle(
                        font: adminFont,
                        fontSize: exam.header.adminFontSize,
                        fontWeight: adminWeight,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.Text(
                      exam.header.governorate,
                      style: pw.TextStyle(
                        font: adminFont,
                        fontSize: exam.header.adminFontSize - 0.5,
                        fontWeight: adminWeight,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.Text(
                      exam.header.directorate,
                      style: pw.TextStyle(
                        font: adminFont,
                        fontSize: exam.header.adminFontSize - 0.5,
                        fontWeight: adminWeight,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                    pw.Text(
                      exam.header.school,
                      style: pw.TextStyle(
                        font: adminFont,
                        fontSize: exam.header.adminFontSize,
                        fontWeight: adminWeight,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      exam.header.basmalaText,
                      style: pw.TextStyle(
                        font: basmalaFont,
                        fontSize: exam.header.basmalaFontSize,
                        fontWeight: basmalaWeight,
                      ),
                      textAlign: pw.TextAlign.center,
                    ),
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
                    pw.Text(
                      'الصف : ${exam.header.grade}',
                      style: pw.TextStyle(
                        font: detailsFont,
                        fontSize: exam.header.detailsFontSize,
                        fontWeight: detailsWeight,
                      ),
                    ),
                    pw.Text(
                      'المادة : ${exam.header.subject}',
                      style: pw.TextStyle(
                        font: detailsFont,
                        fontSize: exam.header.detailsFontSize,
                        fontWeight: detailsWeight,
                      ),
                    ),
                    pw.Text(
                      'التاريخ: ${exam.header.examDate}',
                      style: pw.TextStyle(
                        font: detailsFont,
                        fontSize: exam.header.detailsFontSize - 1,
                        fontWeight: detailsWeight,
                      ),
                    ),
                    pw.Text(
                      'الزمن: ${exam.header.examTime}',
                      style: pw.TextStyle(
                        font: detailsFont,
                        fontSize: exam.header.detailsFontSize - 1,
                        fontWeight: detailsWeight,
                      ),
                    ),
                    pw.Text(
                      'الفترة: ${exam.header.period}',
                      style: pw.TextStyle(
                        font: detailsFont,
                        fontSize: exam.header.detailsFontSize - 1,
                        fontWeight: detailsWeight,
                      ),
                    ),
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
                font: titleFont,
                fontSize: exam.header.titleFontSize,
                fontWeight: titleWeight,
              ),
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
    bool isAr,
  ) {
    final List<pw.Widget> widgets = [];
    final int tfCount = exam.automatedConfig.trueFalseCount;
    final int mcqCount = exam.automatedConfig.mcqCount;

    final defaultInstruction = isAr
        ? 'أجب بتظليل الدائرة المناسبة في ورقة الإجابة المخصصة (OMR)'
        : 'Answer by shading the corresponding bubble on the designated OMR sheet';

    widgets.add(
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        color: PdfColors.grey100,
        child: pw.Text(
          exam.header.instructionText.isNotEmpty
              ? exam.header.instructionText
              : defaultInstruction,
          style: pw.TextStyle(font: ttf, fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red900),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );

    if (tfCount > 0) {
      final tfHeader = isAr
          ? 'أولاً: فقرات الصح والخطأ (ظلل الدائرة ص أو خ في ورقة الإجابة):'
          : 'Part 1: True / False items (Shade T or F bubble on the answer sheet):';

      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 4),
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 8),
          color: PdfColors.grey300,
          child: pw.Text(
            tfHeader,
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
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      left: isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.8) : pw.BorderSide.none,
                      right: !isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.8) : pw.BorderSide.none,
                    ),
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
                      textAlign: isAr ? pw.TextAlign.right : pw.TextAlign.left,
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
      final mcqHeader = isAr
          ? 'ثانياً: فقرات الاختيار من متعدد (ظلل رمز الإجابة الصحيحة في ورقة الإجابة):'
          : 'Part 2: Multiple Choice items (Shade the correct choice symbol on the answer sheet):';

      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 4),
          padding: const pw.EdgeInsets.symmetric(vertical: 2.5, horizontal: 8),
          color: PdfColors.grey300,
          child: pw.Text(
            mcqHeader,
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
            isAr: isAr,
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
    required bool isAr,
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
            decoration: pw.BoxDecoration(
              border: pw.Border(
                left: isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.9) : pw.BorderSide.none,
                right: !isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.9) : pw.BorderSide.none,
              ),
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
                  child: _pdfScriptText(
                    questionText.isNotEmpty
                        ? questionText
                        : '................................................................................................',
                    pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
                    textAlign: isAr ? pw.TextAlign.right : pw.TextAlign.left,
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
                              left: (isAr && index > 0)
                                  ? const pw.BorderSide(color: PdfColors.black, width: 0.8)
                                  : pw.BorderSide.none,
                              right: (!isAr && index > 0)
                                  ? const pw.BorderSide(color: PdfColors.black, width: 0.8)
                                  : pw.BorderSide.none,
                            ),
                          ),
                          child: pw.Row(
                            children: [
                              pw.Container(
                                width: 18,
                                decoration: pw.BoxDecoration(
                                  color: PdfColors.white,
                                  border: pw.Border(
                                    left: isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.8) : pw.BorderSide.none,
                                    right: !isAr ? const pw.BorderSide(color: PdfColors.black, width: 0.8) : pw.BorderSide.none,
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
                                  child: _pdfScriptText(
                                    choiceTxt,
                                    pw.TextStyle(font: ttf, fontSize: 8.5),
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

  static List<pw.Widget> _buildTraditionalExamWidgets(ExamModel exam, pw.Font ttf, bool isAr) {
    return [_buildQuestionsSubTable(exam.questions, exam.header.instructionText, ttf, isAr)];
  }

  static pw.Widget _buildQuestionsSubTable(
    List<QuestionModel> questions,
    String instructionText,
    pw.Font ttf,
    bool isAr,
  ) {
    final defaultInstruction = isAr ? 'أجب عن جميع الأسئلة الآتية' : 'Answer all questions';
    final headerInstruction = instructionText.isNotEmpty ? instructionText : defaultInstruction;

    final String colQuestionTitle = isAr ? 'السؤال' : 'Question';
    final String colMarkTitle = isAr ? 'الدرجة' : 'Mark';

    final columnWidths = const <int, pw.TableColumnWidth>{
      0: pw.FixedColumnWidth(38),
      1: pw.FlexColumnWidth(),
      2: pw.FixedColumnWidth(38),
    };

    final questionHeaderCell = pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Center(
        child: pw.Text(colQuestionTitle,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
      ),
    );

    final instructionHeaderCell = pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Center(
        child: pw.Text(headerInstruction,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
                font: ttf,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red900)),
      ),
    );

    final markHeaderCell = pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Center(
        child: pw.Text(colMarkTitle,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
      ),
    );

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
      columnWidths: columnWidths,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: isAr
              ? [markHeaderCell, instructionHeaderCell, questionHeaderCell]
              : [questionHeaderCell, instructionHeaderCell, markHeaderCell],
        ),
        ...questions.map((q) {
          final qTitleCell = pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Center(
              child: pw.Text(q.title,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
            ),
          );

          final qContentCell = pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildPdfQuestionContent(q, ttf, isAr),
                if (q.elements.isNotEmpty) pw.SizedBox(height: 4),
                ...q.elements.map((el) => _buildPdfElement(el, ttf, isAr)),
              ],
            ),
          );

          final qMarkCell = pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 6),
            child: pw.Center(
              child: pw.Text(
                _formatMark(q.mark, isAr),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(font: ttf, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
              ),
            ),
          );

          return pw.TableRow(
            children: isAr
                ? [qMarkCell, qContentCell, qTitleCell]
                : [qTitleCell, qContentCell, qMarkCell],
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

  static pw.TextAlign _convertTextAlign(TextAlign? align, bool isAr) {
    if (align == null) {
      return isAr ? pw.TextAlign.right : pw.TextAlign.left;
    }
    switch (align) {
      case TextAlign.right:
        return pw.TextAlign.right;
      case TextAlign.center:
        return pw.TextAlign.center;
      case TextAlign.left:
        return pw.TextAlign.left;
      case TextAlign.justify:
        return pw.TextAlign.justify;
      case TextAlign.start:
        return isAr ? pw.TextAlign.right : pw.TextAlign.left;
      case TextAlign.end:
        return isAr ? pw.TextAlign.left : pw.TextAlign.right;
    }
  }

  static pw.Widget _buildPdfQuestionContent(QuestionModel q, pw.Font ttf, bool isAr) {
    if (q.richDocumentJson != null && q.richDocumentJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(q.richDocumentJson!);
        if (decoded is Map<String, dynamic>) {
          final document = FluentDocument.fromJson(decoded);
          return pw.Directionality(
            textDirection: isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: _buildPdfRichNodes(document.content.nodes, ttf, isAr),
            ),
          );
        }
      } catch (_) {}
    }
    final pw.TextAlign chosenAlign = _convertTextAlign(q.alignment, isAr);
    final pw.TextDirection itemDir = (chosenAlign == pw.TextAlign.left || !isAr)
        ? pw.TextDirection.ltr
        : pw.TextDirection.rtl;

    if (!q.isTwoColumns) {
      return pw.Directionality(
        textDirection: itemDir,
        child: pw.Column(
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
              isItalic: s.isItalic,
              isUnderline: s.isUnderline,
              isStrikethrough: s.isStrikethrough,
              fontOverride: _pdfFontByFamily[s.fontFamily],
              textColor: spanColor,
              highlightColor: s.highlightHex == null ? null : _parsePdfColor(s.highlightHex),
              lineSpacing: q.lineSpacing,
              textAlign: chosenAlign,
              isAr: isAr,
            );
          }).toList(),
        ),
      );
    }

    final fullText = q.spans.map((s) => s.text).join('').replaceAll('[فاصل_صفحة]', '').trim();
    final lines = fullText.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) {
      return pw.Directionality(
        textDirection: itemDir,
        child: pw.Column(
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
              isItalic: s.isItalic,
              isUnderline: s.isUnderline,
              isStrikethrough: s.isStrikethrough,
              fontOverride: _pdfFontByFamily[s.fontFamily],
              textColor: spanColor,
              highlightColor: s.highlightHex == null ? null : _parsePdfColor(s.highlightHex),
              lineSpacing: q.lineSpacing,
              textAlign: chosenAlign,
              isAr: isAr,
            );
          }).toList(),
        ),
      );
    }

    final styledLines = _splitPdfQuestionSpansIntoLines(q.spans);
    final itemLines = styledLines.length > 1
        ? styledLines.sublist(1)
        : <List<TextSpanModel>>[];
    final int half = (itemLines.length / 2).ceil();
    final col1 = itemLines.sublist(0, half);
    final col2 = itemLines.sublist(half);

    return pw.Directionality(
      textDirection: itemDir,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _renderPdfStyledQuestionLine(
            styledLines.isNotEmpty ? styledLines.first : q.spans,
            ttf,
            alignment: chosenAlign,
            isAr: isAr,
            lineSpacing: q.lineSpacing,
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: col1.map((line) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: _renderPdfStyledQuestionLine(
                      line,
                      ttf,
                      alignment: chosenAlign,
                      isAr: isAr,
                      lineSpacing: q.lineSpacing,
                    ),
                  )).toList(),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: col2.map((line) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
                    child: _renderPdfStyledQuestionLine(
                      line,
                      ttf,
                      alignment: chosenAlign,
                      isAr: isAr,
                      lineSpacing: q.lineSpacing,
                    ),
                  )).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildPdfRichNodes(
    List<FNode> nodes,
    pw.Font font,
    bool isAr,
  ) {
    final widgets = <pw.Widget>[];
    for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex++) {
      final node = nodes[nodeIndex];

      if (node is FluentImage && node.isFloating) {
        final image = _pdfRichImage(node);
        if (image != null) {
          const double logicalPixelToPdfPoint = 72.0 / 96.0;
          final double reservedHeight =
              ((node.height ?? 120.0) * logicalPixelToPdfPoint) + 8.0;
          final suffix = _buildPdfRichNodes(
            nodes.sublist(nodeIndex + 1),
            font,
            isAr,
          );
          final alignment = node.textAlign == 'center'
              ? pw.Alignment.center
              : node.textAlign == 'right'
                  ? pw.Alignment.centerRight
                  : pw.Alignment.centerLeft;

          widgets.add(pw.SizedBox(height: reservedHeight));
          widgets.add(
            pw.Stack(
              overflow: pw.Overflow.visible,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  mainAxisSize: pw.MainAxisSize.min,
                  children: suffix.isEmpty
                      ? [pw.SizedBox(height: 1)]
                      : suffix,
                ),
                pw.Positioned(
                  top: -reservedHeight +
                      node.offsetY * logicalPixelToPdfPoint,
                  left: 0,
                  right: 0,
                  child: pw.Align(
                    alignment: alignment,
                    child: pw.Transform.translate(
                      offset: PdfPoint(
                        node.offsetX * logicalPixelToPdfPoint,
                        0,
                      ),
                      child: image,
                    ),
                  ),
                ),
              ],
            ),
          );
          return widgets;
        }
      }
      if (node is FluentList) {
        for (var i = 0; i < node.items.length; i++) {
          final item = node.items[i];
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(
                  width: 18,
                  child: pw.Text(
                    node.listType == 'ordered' ? '${i + 1}.' : '•',
                    style: pw.TextStyle(font: font, fontSize: 10),
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: _buildPdfRichNodes(item.children, font, isAr),
                  ),
                ),
              ],
            ),
          ));
        }
      } else if (node is Paragraph) {
        widgets.add(_buildPdfRichParagraph(node, font, isAr));
      } else if (node is FluentImage) {
        final image = _pdfRichImage(node);
        if (image != null) {
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Align(
              alignment: node.textAlign == 'center'
                  ? pw.Alignment.center
                  : node.textAlign == 'right'
                      ? pw.Alignment.centerRight
                      : pw.Alignment.centerLeft,
              child: image,
            ),
          ));
        }
      } else if (node is HorizontalRule) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          child: pw.Divider(thickness: 0.8, color: PdfColors.grey600),
        ));
      } else if (node is FluentTable) {
        final rows = <pw.TableRow>[];
        for (final row in node.rows) {
          rows.add(pw.TableRow(
            children: row.cells.map((cell) {
              final children = _buildPdfRichNodes(cell.children, font, isAr);
              return pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: children.isEmpty
                    ? pw.SizedBox(height: 12)
                    : pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: children,
                      ),
              );
            }).toList(),
          ));
        }
        if (rows.isNotEmpty) {
          widgets.add(pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.6),
            children: rows,
          ));
        }
      }
    }
    return widgets;
  }

  static List<pw.InlineSpan> _pdfRichFragmentSpans(
    Fragment fragment,
    pw.TextStyle style,
  ) {
    final styles = fragment.styles ?? const <String>[];
    final isSuperscript = styles.contains('superscript');
    final isSubscript = styles.contains('subscript');
    if (isSuperscript || isSubscript) {
      final baseSize = style.fontSize ?? 11;
      return [
        pw.WidgetSpan(
          child: pw.Transform.translate(
            offset: PdfPoint(
              0,
              isSuperscript ? baseSize * 0.30 : -baseSize * 0.20,
            ),
            child: pw.Text(
              fragment.text,
              style: style.copyWith(fontSize: baseSize * 0.62),
            ),
          ),
        ),
      ];
    }
    return _pdfScriptAwareSpans(fragment.text, style);
  }

  static pw.Widget _buildPdfRichParagraph(
    Paragraph paragraph,
    pw.Font font,
    bool isAr,
  ) {
    if (paragraph.fragments.isEmpty) {
      return pw.SizedBox.shrink();
    }

    final paragraphStyle = paragraph.getStyle();
    final spans = <pw.InlineSpan>[];
    for (final fragment in paragraph.fragments) {
      if (fragment is Link) {
        for (final child in fragment.fragments) {
          if (child is FluentImage) {
            final image = _pdfRichInlineImage(child);
            if (image != null) spans.add(pw.WidgetSpan(child: image));
          } else if (child is Fragment) {
            final childStyle = _pdfRichTextStyle(child, paragraphStyle, font);
            spans.add(pw.TextSpan(
              children: _pdfRichFragmentSpans(child, childStyle),
              style: childStyle,
            ));
          }
        }
      } else if (fragment is FluentImage) {
        final image = _pdfRichInlineImage(fragment);
        if (image != null) spans.add(pw.WidgetSpan(child: image));
      } else if (fragment is Fragment) {
        final fragmentStyle = _pdfRichTextStyle(fragment, paragraphStyle, font);
        spans.add(pw.TextSpan(
          children: _pdfRichFragmentSpans(fragment, fragmentStyle),
          style: fragmentStyle,
        ));
      }
    }
    final align = switch (paragraph.textAlign) {
      'center' => pw.TextAlign.center,
      'right' => pw.TextAlign.right,
      'justify' => pw.TextAlign.justify,
      'left' => pw.TextAlign.left,
      _ => isAr ? pw.TextAlign.right : pw.TextAlign.left,
    };
    final lineHeight = paragraphStyle.lineHeight ?? 1.15;
    return pw.Padding(
      padding: pw.EdgeInsets.only(
        top: paragraphStyle.spacingBefore ?? 0,
        bottom: paragraphStyle.spacingAfter ?? 4,
        left: paragraph.indent * 12.0,
      ),
      child: pw.RichText(
        textAlign: align,
        text: pw.TextSpan(
          children: spans,
          style: pw.TextStyle(font: font, lineSpacing: lineHeight),
        ),
      ),
    );
  }

  static pw.Font _resolvePdfFont(String? family, pw.Font fallback) {
    final requested = (family ?? '').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (requested.isEmpty) return fallback;
    for (final entry in _pdfFontByFamily.entries) {
      final candidate = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (candidate == requested) return entry.value;
    }
    return fallback;
  }

  static pw.TextStyle _pdfRichTextStyle(
    Fragment fragment,
    dynamic paragraphStyle,
    pw.Font font,
  ) {
    final styles = fragment.styles ?? const <String>[];
    final paragraphStyles = paragraphStyle.styles as List<String>? ?? const <String>[];
    final color = _parsePdfColor(
      fragment.color ?? paragraphStyle.color?.toString(),
    );
    pw.TextDecoration? decoration;
    if (styles.contains('underline') && styles.contains('strikethrough')) {
      decoration = pw.TextDecoration.combine([
        pw.TextDecoration.underline,
        pw.TextDecoration.lineThrough,
      ]);
    } else if (styles.contains('underline')) {
      decoration = pw.TextDecoration.underline;
    } else if (styles.contains('strikethrough')) {
      decoration = pw.TextDecoration.lineThrough;
    }
    return pw.TextStyle(
      font: _resolvePdfFont(fragment.fontFamily, font),
      fontSize: fragment.fontSize,
      color: color,
      fontWeight: styles.contains('bold') || paragraphStyles.contains('bold')
          ? pw.FontWeight.bold
          : pw.FontWeight.normal,
      fontStyle: styles.contains('italic') || paragraphStyles.contains('italic')
          ? pw.FontStyle.italic
          : pw.FontStyle.normal,
      decoration: decoration,
      background: fragment.highlightColor == null
          ? null
          : pw.BoxDecoration(color: _parsePdfColor(fragment.highlightColor)),
    );
  }

  static pw.Widget? _pdfRichInlineImage(FluentImage image) {
    final rendered = _pdfRichImage(image);
    if (rendered == null || !image.isFloating) return rendered;
    const double logicalPixelToPdfPoint = 72.0 / 96.0;
    return pw.Transform.translate(
      offset: PdfPoint(
        image.offsetX * logicalPixelToPdfPoint,
        image.offsetY * logicalPixelToPdfPoint,
      ),
      child: rendered,
    );
  }

  static pw.Widget? _pdfRichImage(FluentImage image) {
    try {
      Uint8List? bytes;
      if (image.src.startsWith('data:')) {
        final comma = image.src.indexOf(',');
        if (comma >= 0) bytes = base64Decode(image.src.substring(comma + 1));
      } else if (File(image.src).existsSync()) {
        bytes = File(image.src).readAsBytesSync();
      }
      if (bytes == null) return null;
      const double logicalPixelToPdfPoint = 72.0 / 96.0;
      return pw.Image(
        pw.MemoryImage(bytes),
        width: image.width == null
            ? null
            : image.width! * logicalPixelToPdfPoint,
        height: image.height == null
            ? null
            : image.height! * logicalPixelToPdfPoint,
        fit: pw.BoxFit.contain,
      );
    } catch (_) {
      return null;
    }
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

  static List<List<TextSpanModel>> _splitPdfQuestionSpansIntoLines(
    List<TextSpanModel> source,
  ) {
    final lines = <List<TextSpanModel>>[];
    var current = <TextSpanModel>[];
    for (final span in source) {
      final parts = span.text.split('\\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) {
          current.add(TextSpanModel(
            text: parts[i],
            isBold: span.isBold,
            isItalic: span.isItalic,
            isUnderline: span.isUnderline,
            isStrikethrough: span.isStrikethrough,
            fontSize: span.fontSize,
            fontFamily: span.fontFamily,
            colorHex: span.colorHex,
            highlightHex: span.highlightHex,
          ));
        }
        if (i < parts.length - 1) {
          if (current.any((part) => part.text.trim().isNotEmpty)) {
            lines.add(current);
          }
          current = <TextSpanModel>[];
        }
      }
    }
    if (current.any((part) => part.text.trim().isNotEmpty)) lines.add(current);
    return lines;
  }

  static pw.Widget _renderPdfStyledQuestionLine(
    List<TextSpanModel> spans,
    pw.Font fallback, {
    required pw.TextAlign alignment,
    required bool isAr,
    required double lineSpacing,
  }) {
    final combined = spans.map((span) => span.text).join();
    final hasInlineSymbol = RegExp(
      r'(\[(?:كسر|جذر|sqrt|عمودي|قسمة|div|نها|تباديل|توافيق|مجموع|تكامل|متجه|بار|محدد|مصفوفة|مصفوفة_عامة|تفاضل|لوغاريتم|مثلثية|جداء):.*?\]|✔|✘|✓|✗)',
    ).hasMatch(combined);
    if (hasInlineSymbol) {
      if (spans.length == 1) {
        final span = spans.first;
        return _renderInlineMathText(
          span.text,
          fallback,
          fontSize: span.fontSize,
          isBold: span.isBold,
          isItalic: span.isItalic,
          isUnderline: span.isUnderline,
          isStrikethrough: span.isStrikethrough,
          fontOverride: _pdfFontByFamily[span.fontFamily],
          textColor: _parsePdfColor(span.colorHex),
          highlightColor: span.highlightHex == null
              ? null
              : _parsePdfColor(span.highlightHex),
          lineSpacing: lineSpacing,
          textAlign: alignment,
          isAr: isAr,
        );
      }
      final first = spans.first;
      return _renderInlineMathText(
        combined,
        fallback,
        fontSize: first.fontSize,
        isBold: first.isBold,
        isItalic: first.isItalic,
        isUnderline: first.isUnderline,
        isStrikethrough: first.isStrikethrough,
        fontOverride: _pdfFontByFamily[first.fontFamily],
        textColor: _parsePdfColor(first.colorHex),
        highlightColor: first.highlightHex == null
            ? null
            : _parsePdfColor(first.highlightHex),
        lineSpacing: lineSpacing,
        textAlign: alignment,
        isAr: isAr,
      );
    }
    return pw.RichText(
      textAlign: alignment,
      text: pw.TextSpan(
        children: spans.map((span) {
          final decorations = <pw.TextDecoration>[
            if (span.isUnderline) pw.TextDecoration.underline,
            if (span.isStrikethrough) pw.TextDecoration.lineThrough,
          ];
          final highlight = span.highlightHex == null
              ? null
              : _parsePdfColor(span.highlightHex);
          final spanStyle = pw.TextStyle(
            font: _pdfFontByFamily[span.fontFamily] ?? fallback,
            fontSize: span.fontSize,
            fontWeight:
                span.isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            fontStyle:
                span.isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
            color: _parsePdfColor(span.colorHex),
            decoration: decorations.isEmpty
                ? null
                : pw.TextDecoration.combine(decorations),
            background: highlight == null
                ? null
                : pw.BoxDecoration(color: highlight),
            lineSpacing: lineSpacing,
          );
          return pw.TextSpan(
            children: _pdfScriptAwareSpans(span.text, spanStyle),
            style: spanStyle,
          );
        }).toList(),
      ),
    );
  }

  static pw.Widget _renderInlineMathText(
    String text,
    pw.Font ttf, {
    double fontSize = 11,
    bool isBold = false,
    bool isItalic = false,
    bool isUnderline = false,
    bool isStrikethrough = false,
    pw.Font? fontOverride,
    PdfColor textColor = PdfColors.black,
    PdfColor? highlightColor,
    double lineSpacing = 1.5,
    pw.TextAlign? textAlign,
    bool isAr = true,
  }) {
    final effectiveFont = fontOverride ?? ttf;
    final effectiveTextAlign = textAlign ?? (isAr ? pw.TextAlign.right : pw.TextAlign.left);
    final regExp = RegExp(r'(\[(?:كسر|جذر|sqrt|عمودي|قسمة|div|نها|تباديل|توافيق|مجموع|تكامل|متجه|بار|محدد|مصفوفة|مصفوفة_عامة|تفاضل|لوغاريتم|مثلثية|جداء):.*?\]|✔|✘|✓|✗)');
    final matches = regExp.allMatches(text);

    final baseTextStyle = pw.TextStyle(
      font: effectiveFont,
      fontSize: fontSize,
      color: textColor,
      fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: isItalic ? pw.FontStyle.italic : pw.FontStyle.normal,
      decoration: [
        if (isUnderline) pw.TextDecoration.underline,
        if (isStrikethrough) pw.TextDecoration.lineThrough,
      ].isEmpty ? null : pw.TextDecoration.combine([
        if (isUnderline) pw.TextDecoration.underline,
        if (isStrikethrough) pw.TextDecoration.lineThrough,
      ]),
      background: highlightColor == null ? null : pw.BoxDecoration(color: highlightColor),
      lineSpacing: lineSpacing,
    );

    if (matches.isEmpty) {
      final scriptSpans = _pdfScriptAwareSpans(text, baseTextStyle);
      if (scriptSpans.length == 1 && scriptSpans.first is pw.TextSpan) {
        return pw.Text(text, textAlign: effectiveTextAlign, style: baseTextStyle);
      }
      return pw.RichText(
        textAlign: effectiveTextAlign,
        text: pw.TextSpan(children: scriptSpans, style: baseTextStyle),
      );
    }

    final List<pw.InlineSpan> spans = [];
    int lastIdx = 0;

    for (final m in matches) {
      if (m.start > lastIdx) {
        spans.addAll(_pdfScriptAwareSpans(
          text.substring(lastIdx, m.start),
          baseTextStyle,
        ));
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
                    pw.Text(num, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.85, color: textColor, fontWeight: pw.FontWeight.bold)),
                    pw.Container(width: lineWidth, height: 0.8, color: textColor),
                    pw.Text(den, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.85, color: textColor, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'جذر' || type == 'sqrt') {
          final bool isRtl = (type == 'جذر') && isAr;
          final String degree = parts.length > 1 ? parts[0] : '';
          final String radicand = parts.length > 1 ? parts.sublist(1).join(':') : parts[0];

          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
                child: _drawPdfRadical(
                  pw.Text(
                    radicand,
                    style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.95, color: textColor, fontWeight: pw.FontWeight.bold),
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
          final v = parts.isNotEmpty ? parts[0] : (isAr ? 'س' : 'x');
          final t = parts.length > 1 ? parts[1] : (isAr ? '٠' : '0');
          final fn = parts.length > 2 ? parts[2] : '';
          final label = isAr ? 'نهـا' : 'lim';

          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2.0),
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          label,
                          style: pw.TextStyle(
                            font: effectiveFont,
                            fontSize: fontSize * 1.05,
                            color: textColor,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 1),
                        pw.Row(
                          mainAxisSize: pw.MainAxisSize.min,
                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                          children: [
                            pw.Text(
                              v,
                              style: pw.TextStyle(
                                font: effectiveFont,
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
                                font: effectiveFont,
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
                          font: effectiveFont,
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
          final n = parts.isNotEmpty ? parts[0] : (isAr ? 'ن' : 'n');
          final r = parts.length > 1 ? parts[1] : (isAr ? 'ر' : 'r');
          final sym = type == 'تباديل'
              ? (isAr ? 'ل' : 'P')
              : (isAr ? 'ق' : 'C');

          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2.5),
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 6),
                      child: pw.Text(n, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.75, color: textColor, fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Text(sym, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 1.25, color: textColor, fontWeight: pw.FontWeight.bold)),
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(top: 6),
                      child: pw.Text(r, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.75, color: textColor, fontWeight: pw.FontWeight.bold)),
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
          final sym = type == 'مجموع' ? (isAr ? 'مجـ' : '∑') : '∫';

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
                        pw.Text(to, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.65, color: textColor, fontWeight: pw.FontWeight.bold)),
                        pw.Text(sym, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 1.2, color: textColor, fontWeight: pw.FontWeight.bold)),
                        pw.Text(from, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.65, color: textColor, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      pw.SizedBox(width: 3),
                      pw.Text(body, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
                    ],
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'تفاضل') {
          final variable = parts.isNotEmpty ? parts[0] : (isAr ? 'س' : 'x');
          final fn = parts.length > 1 ? parts[1] : 'f($variable)';
          final order = parts.length > 2 ? parts[2] : '1';
          final power = order == '1' ? '' : order;
          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 3),
                child: pw.Column(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Text('d$power($fn)', style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.82, color: textColor, fontWeight: pw.FontWeight.bold)),
                    pw.Container(width: 34, height: 0.8, color: textColor),
                    pw.Text('d$variable$power', style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.75, color: textColor, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'لوغاريتم') {
          final base = parts.isNotEmpty ? parts[0] : '';
          final arg = parts.length > 1 ? parts.sublist(1).join(':') : '';
          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(isAr ? 'لو' : 'log', style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
                    if (base.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 1),
                        child: pw.Text(base, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.6, color: textColor)),
                      ),
                    pw.Text('($arg)', style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'مثلثية') {
          final fn = parts.isNotEmpty ? parts[0] : (isAr ? 'جا' : 'sin');
          final arg = parts.length > 1 ? parts.sublist(1).join(':') : '';
          spans.add(pw.WidgetSpan(child: pw.Text('$fn($arg)', style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold))));
        } else if (type == 'جداء') {
          final from = parts.isNotEmpty ? parts[0] : '';
          final to = parts.length > 1 ? parts[1] : '';
          final body = parts.length > 2 ? parts.sublist(2).join(':') : '';
          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 3),
                child: pw.Row(
                  mainAxisSize: pw.MainAxisSize.min,
                  children: [
                    pw.Column(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        pw.Text(to, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.62, color: textColor, fontWeight: pw.FontWeight.bold)),
                        pw.Text('Π', style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 1.2, color: textColor, fontWeight: pw.FontWeight.bold)),
                        pw.Text(from, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.62, color: textColor, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    if (body.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 3),
                        child: pw.Text(body, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
                      ),
                  ],
                ),
              ),
            ),
          );
        } else if (type == 'متجه') {
          final s = parts.isNotEmpty ? parts[0] : (isAr ? 'ق' : 'v');
          spans.add(
            pw.WidgetSpan(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Text('→', style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.75, color: textColor, fontWeight: pw.FontWeight.bold)),
                  pw.Text(s, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          );
        } else if (type == 'بار') {
          final s = parts.isNotEmpty ? parts[0] : (isAr ? 'س' : 'x');
          spans.add(
            pw.WidgetSpan(
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                children: [
                  pw.Container(width: 10, height: 1.0, color: textColor),
                  pw.Text(s, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          );
        } else if (type == 'مصفوفة_عامة') {
          try {
            final payload = parts.isNotEmpty
                ? jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts.join(':'))))) as Map<String, dynamic>
                : <String, dynamic>{};
            final rows = (payload['rows'] as num?)?.toInt() ?? 0;
            final cols = (payload['cols'] as num?)?.toInt() ?? 0;
            final cells = (payload['cells'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
            if (rows < 1 || rows > 6 || cols < 1 || cols > 6 || cells.length != rows * cols) {
              spans.add(pw.TextSpan(text: matchedStr, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor)));
            } else {
              spans.add(pw.WidgetSpan(
                child: pw.Container(
                  margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                  padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      left: pw.BorderSide(color: textColor, width: 1.5),
                      right: pw.BorderSide(color: textColor, width: 1.5),
                    ),
                  ),
                  child: pw.Table(
                    children: List.generate(rows, (ri) => pw.TableRow(
                      children: List.generate(cols, (ci) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        child: pw.Text(cells[ri * cols + ci], textAlign: pw.TextAlign.center, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor)),
                      )),
                    )),
                  ),
                ),
              ));
            }
          } catch (_) {
            spans.add(pw.TextSpan(text: matchedStr, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize, color: textColor)));
          }
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
                      pw.Text(a, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.9, color: textColor)),
                      pw.SizedBox(width: 6),
                      pw.Text(b, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.9, color: textColor)),
                    ]),
                    pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
                      pw.Text(c, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.9, color: textColor)),
                      pw.SizedBox(width: 6),
                      pw.Text(d, style: pw.TextStyle(font: effectiveFont, fontSize: fontSize * 0.9, color: textColor)),
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
          final bool isRtlVert = isAr;

          spans.add(
            pw.WidgetSpan(
              child: pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
                child: pw.Directionality(
                  textDirection: isRtlVert ? pw.TextDirection.rtl : pw.TextDirection.ltr,
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
                                        font: effectiveFont,
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
                                font: effectiveFont,
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
          final bool isRtl = (type == 'قسمة') && isAr;
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
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
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
                              font: effectiveFont,
                              fontSize: fontSize * 0.9,
                              color: textColor,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ),
                      pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Text(
                            divisor,
                            style: pw.TextStyle(
                              font: effectiveFont,
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
                                font: effectiveFont,
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
      spans.addAll(_pdfScriptAwareSpans(
        text.substring(lastIdx),
        baseTextStyle,
      ));
    }

    return pw.RichText(
      textAlign: effectiveTextAlign,
      text: pw.TextSpan(children: spans, style: baseTextStyle),
    );
  }

  static pw.Widget _pdfScriptText(
    String text,
    pw.TextStyle style, {
    pw.TextAlign? textAlign,
    int? maxLines,
    bool? softWrap,
  }) {
    final spans = _pdfScriptAwareSpans(text, style);
    if (spans.length == 1 && spans.first is pw.TextSpan) {
      return pw.Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        softWrap: softWrap,
      );
    }
    return pw.RichText(
      textAlign: textAlign,
      maxLines: maxLines,
      softWrap: softWrap,
      text: pw.TextSpan(children: spans, style: style),
    );
  }

  static pw.Widget _buildPdfElement(InsertableElement el, pw.Font ttf, bool isAr) {
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
          child: _pdfScriptText(
            el.content,
            pw.TextStyle(font: ttf, fontSize: 10.5, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center,
          ),
        );

      case ElementType.dottedLine:
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          child: _pdfScriptText(
            el.content,
            pw.TextStyle(font: ttf, fontSize: 11),
            textAlign: pw.TextAlign.center,
          ),
        );

      case ElementType.table:
        return _buildPdfCustomTable(el.content, ttf, isAr, el.width, el.height);

      case ElementType.shape:
        return _buildPdfCustomShape(el.content, ttf);

      case ElementType.mathOperation:
        try {
          final data = jsonDecode(el.content);
          final kind = data['kind'] ?? 'vertical';

          if (kind == 'vertical') {
            final List<dynamic> rows = data['rows'] ?? [];
            final String op = data['operator'] ?? '+';
            final bool opOnRight = data['opOnRight'] ?? isAr;

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
                          _pdfScriptText(
                            val,
                            pw.TextStyle(
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
                  _pdfScriptText(
                    num,
                    pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.Container(
                    width: lineWidth,
                    height: 1.0,
                    color: PdfColors.black,
                    margin: const pw.EdgeInsets.symmetric(vertical: 1.5),
                  ),
                  _pdfScriptText(
                    den,
                    pw.TextStyle(font: ttf, fontSize: 11, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            );
          }
        } catch (_) {}
        return pw.SizedBox.shrink();
    }
  }

  static pw.Widget _buildPdfCustomTable(
    String jsonStr,
    pw.Font ttf,
    bool isAr, [
    double tableWidth = 320,
    double tableHeight = 120,
  ]) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final int rows = (data['rows'] as num?)?.toInt() ?? 2;
      final int cols = (data['cols'] as num?)?.toInt() ?? 2;
      final bool hasHeader = data['hasHeader'] ?? true;
      final rawGrid = (data['data'] as List?) ?? [];
      final rawMerges = (data['merges'] as List?) ?? const [];
      final merges = [
        for (final item in rawMerges)
          if (item is Map)
            Map<String, int>.from(
              item.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
            ),
      ];
      Map<String, int>? mergeAt(int r, int c) {
        for (final m in merges) {
          final mr = m['row'] ?? 0, mc = m['col'] ?? 0;
          final rs = m['rowSpan'] ?? 1, cs = m['colSpan'] ?? 1;
          if (r >= mr && r < mr + rs && c >= mc && c < mc + cs) return m;
        }
        return null;
      }
      final cellW = tableWidth / cols;
      final cellH = tableHeight / rows;
      final children = <pw.Widget>[];
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final merge = mergeAt(r, c);
          if (merge != null &&
              ((merge['row'] ?? 0) != r || (merge['col'] ?? 0) != c)) {
            continue;
          }
          final spanC = merge == null ? 1 : (merge['colSpan'] ?? 1);
          final spanR = merge == null ? 1 : (merge['rowSpan'] ?? 1);
          String text = '';
          if (r < rawGrid.length && rawGrid[r] is List &&
              c < (rawGrid[r] as List).length) {
            text = rawGrid[r][c]?.toString() ?? '';
          }
          final visualColumn = isAr ? cols - c - spanC : c;
          final isHeaderRow = r == 0 && hasHeader;
          children.add(pw.Positioned(
            left: visualColumn * cellW,
            top: r * cellH,
            right: tableWidth - ((visualColumn + spanC) * cellW),
            bottom: tableHeight - ((r + spanR) * cellH),
            child: pw.Container(
              alignment: pw.Alignment.center,
              padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
              decoration: pw.BoxDecoration(
                color: isHeaderRow ? PdfColors.grey200 : PdfColors.white,
                border: pw.Border.all(color: PdfColors.black, width: 0.8),
              ),
              child: _pdfScriptText(
                text,
                pw.TextStyle(
                  font: ttf,
                  fontSize: isHeaderRow ? 10.0 : 9.0,
                  fontWeight: isHeaderRow ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ));
        }
      }
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.SizedBox(
          width: tableWidth,
          height: tableHeight,
          child: pw.Stack(children: children),
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
                          ..lineTo(pw_x - 2, 2)
                          ..lineTo(pw_x - offset, pw_y - 2)
                          ..lineTo(2, pw_y - 2)
                          ..closePath()
                          ..fillPath();
                      }
                      canvas
                        ..moveTo(offset, pw_y - 2)
                        ..lineTo(pw_x - 2, 2)
                        ..lineTo(pw_x - offset, pw_y - 2)
                        ..lineTo(2, pw_y - 2)
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
                  child: _pdfScriptText(
                    label,
                    pw.TextStyle(
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

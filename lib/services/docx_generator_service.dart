import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../models/exam_models.dart';

class DocxGeneratorService {
  static Future<String> generateAndOpenDocx(ExamModel exam) async {
    final docxBytes = await _buildDocxBytes(exam);

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
    final filePath = '${dir.path}/$safeName.docx';
    final file = File(filePath);
    await file.writeAsBytes(docxBytes, flush: true);

    return filePath;
  }

  static Future<List<int>> _buildDocxBytes(ExamModel exam) async {
    final archive = Archive();

    archive.addFile(ArchiveFile(
      '[Content_Types].xml',
      _contentTypesXml.length,
      utf8.encode(_contentTypesXml),
    ));

    archive.addFile(ArchiveFile(
      '_rels/.rels',
      _rootRelsXml.length,
      utf8.encode(_rootRelsXml),
    ));

    archive.addFile(ArchiveFile(
      'word/_rels/document.xml.rels',
      _docRelsXml.length,
      utf8.encode(_docRelsXml),
    ));

    final documentXml = _buildDocumentXml(exam);
    archive.addFile(ArchiveFile(
      'word/document.xml',
      documentXml.length,
      utf8.encode(documentXml),
    ));

    final zipEncoder = ZipEncoder();
    return zipEncoder.encode(archive)!;
  }

  static String _buildDocumentXml(ExamModel exam) {
    final buffer = StringBuffer();

    buffer.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    buffer.write('<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">');
    buffer.write('<w:body>');

    final topMarginDxa = exam.header.topMargin1cm ? '567' : '283';

    // 1. جدول الترويسة
    buffer.write('<w:tbl>');
    buffer.write('<w:tblPr>');
    buffer.write('<w:tblW w:w="0" w:type="auto"/>');
    buffer.write('<w:bidiVisual/>');
    buffer.write('<w:tblBorders>');
    buffer.write('<w:top w:val="single" w:sz="12" w:space="0" w:color="000000"/>');
    buffer.write('<w:left w:val="single" w:sz="12" w:space="0" w:color="000000"/>');
    buffer.write('<w:bottom w:val="single" w:sz="12" w:space="0" w:color="000000"/>');
    buffer.write('<w:right w:val="single" w:sz="12" w:space="0" w:color="000000"/>');
    buffer.write('<w:insideH w:val="none"/>');
    buffer.write('<w:insideV w:val="none"/>');
    buffer.write('</w:tblBorders>');
    buffer.write('</w:tblPr>');

    // صف الترويسة العلوي
    buffer.write('<w:tr>');

    // الخانة اليمنى: البيانات الإدارية
    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>');
    buffer.write(_buildHeaderParagraph(exam.header.country, isBold: true, fontSize: 20));
    buffer.write(_buildHeaderParagraph(exam.header.ministry, fontSize: 18));
    buffer.write(_buildHeaderParagraph(exam.header.governorate, fontSize: 17));
    buffer.write(_buildHeaderParagraph(exam.header.directorate, fontSize: 17));
    buffer.write(_buildHeaderParagraph(exam.header.school, isBold: true, fontSize: 18));
    buffer.write('</w:tc>');

    // الخانة الوسطى: البسملة
    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="3500" w:type="dxa"/></w:tcPr>');
    buffer.write(_buildHeaderParagraph(exam.header.basmalaText, isBold: true, fontSize: 22, align: 'center'));
    buffer.write('</w:tc>');

    // الخانة اليسرى: بيانات الامتحان
    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="3000" w:type="dxa"/></w:tcPr>');
    buffer.write(_buildHeaderParagraph('الصف : ${exam.header.grade}', isBold: true, fontSize: 20, align: 'left'));
    buffer.write(_buildHeaderParagraph('المادة : ${exam.header.subject}', isBold: true, fontSize: 20, align: 'left'));
    buffer.write(_buildHeaderParagraph('التاريخ : ${exam.header.examDate}', fontSize: 18, align: 'left'));
    buffer.write(_buildHeaderParagraph('الزمن : ${exam.header.examTime}', fontSize: 17, align: 'left'));
    buffer.write(_buildHeaderParagraph('الفترة : ${exam.header.period}', fontSize: 17, align: 'left'));
    buffer.write('</w:tc>');

    buffer.write('</w:tr>');

    // صف عنوان الامتحان
    buffer.write('<w:tr>');
    buffer.write('<w:tc>');
    buffer.write('<w:tcPr>');
    buffer.write('<w:gridSpan w:val="3"/>');
    buffer.write('<w:shd w:val="clear" w:color="auto" w:fill="EEEEEE"/>');
    buffer.write('</w:tcPr>');
    buffer.write(_buildHeaderParagraph(exam.header.examTitle, isBold: true, fontSize: 22, align: 'center'));
    buffer.write('</w:tc>');
    buffer.write('</w:tr>');

    buffer.write('</w:tbl>');

    buffer.write('<w:p><w:pPr><w:spacing w:before="120" w:after="120"/></w:pPr></w:p>');

    // 2. جدول الأسئلة
    buffer.write('<w:tbl>');
    buffer.write('<w:tblPr>');
    buffer.write('<w:tblW w:w="0" w:type="auto"/>');
    buffer.write('<w:bidiVisual/>');
    buffer.write('<w:tblBorders>');
    buffer.write('<w:top w:val="single" w:sz="6" w:space="0" w:color="000000"/>');
    buffer.write('<w:left w:val="single" w:sz="6" w:space="0" w:color="000000"/>');
    buffer.write('<w:bottom w:val="single" w:sz="6" w:space="0" w:color="000000"/>');
    buffer.write('<w:right w:val="single" w:sz="6" w:space="0" w:color="000000"/>');
    buffer.write('<w:insideH w:val="single" w:sz="6" w:space="0" w:color="000000"/>');
    buffer.write('<w:insideV w:val="single" w:sz="6" w:space="0" w:color="000000"/>');
    buffer.write('</w:tblBorders>');
    buffer.write('</w:tblPr>');

    // صف العناوين الأول
    buffer.write('<w:tr>');
    buffer.write('<w:trPr><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/></w:trPr>');

    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
    buffer.write(_buildCellParagraph('السؤال', isBold: true, fontSize: 19, align: 'center'));
    buffer.write('</w:tc>');

    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="7900" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
    buffer.write(_buildCellParagraph(exam.header.instructionText, isBold: true, fontSize: 20, align: 'center', color: 'C00000'));
    buffer.write('</w:tc>');

    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
    buffer.write(_buildCellParagraph('الدرجة', isBold: true, fontSize: 19, align: 'center'));
    buffer.write('</w:tc>');

    buffer.write('</w:tr>');

    // صفوف الأسئلة
    for (final q in exam.questions) {
      buffer.write('<w:tr>');

      // عمود العنوان
      buffer.write('<w:tc>');
      buffer.write('<w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
      buffer.write(_buildCellParagraph(q.title, isBold: true, fontSize: 20, align: 'center'));
      buffer.write('</w:tc>');

      // عمود المحتوى
      buffer.write('<w:tc>');
      buffer.write('<w:tcPr><w:tcW w:w="7900" w:type="dxa"/></w:tcPr>');

      if (!q.isTwoColumns) {
        buffer.write(_renderDocxParagraphOrTable(q.spans));
      } else {
        buffer.write(_buildDocxTwoColumnContent(q));
      }

      // معالجة العناصر المدرجة (جداول، أشكال، مربعات نصية، أسطر إجابة، عمليات)
      for (final el in q.elements) {
        if (el.type == ElementType.textBox) {
          buffer.write('<w:p>');
          buffer.write('<w:pPr><w:bidi/><w:jc w:val="center"/><w:pBdr><w:bottom w:val="single" w:sz="6"/><w:top w:val="single" w:sz="6"/><w:left w:val="single" w:sz="6"/><w:right w:val="single" w:sz="6"/></w:pBdr></w:pPr>');
          buffer.write('<w:r><w:rPr><w:b/><w:rtl/><w:sz w:val="20"/></w:rPr><w:t>${_xmlEscape(el.content)}</w:t></w:r>');
          buffer.write('</w:p>');
        } else if (el.type == ElementType.dottedLine) {
          buffer.write('<w:p>');
          buffer.write('<w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr>');
          buffer.write('<w:r><w:rPr><w:rtl/><w:sz w:val="22"/></w:rPr><w:t>${_xmlEscape(el.content)}</w:t></w:r>');
          buffer.write('</w:p>');
        } else if (el.type == ElementType.mathOperation) {
          buffer.write(_buildDocxMathOperation(el.content));
        } else if (el.type == ElementType.table) {
          buffer.write(_buildDocxCustomTable(el.content));
        } else if (el.type == ElementType.shape) {
          buffer.write(_buildDocxCustomShape(el.content));
        }
      }

      buffer.write('</w:tc>');

      // عمود الدرجة
      buffer.write('<w:tc>');
      buffer.write('<w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
      final markText = q.mark > 0 ? '${q.mark.toInt()} د' : '-';
      buffer.write(_buildCellParagraph(markText, isBold: true, fontSize: 20, align: 'center'));
      buffer.write('</w:tc>');

      buffer.write('</w:tr>');
    }

    buffer.write('</w:tbl>');

    // 3. التذييل
    buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:before="200" w:after="80"/></w:pPr>');
    final footerMsg = exam.header.isMultiPage ? exam.header.continuationText : exam.header.singlePageFooterText;
    buffer.write('<w:r><w:rPr><w:b/><w:rtl/><w:sz w:val="22"/></w:rPr><w:t>${_xmlEscape(footerMsg)}</w:t></w:r>');
    buffer.write('</w:p>');

    buffer.write('<w:p><w:pPr><w:bidi/><w:jc w:val="left"/></w:pPr>');
    buffer.write('<w:r><w:rPr><w:rtl/><w:sz w:val="20"/></w:rPr><w:t>${_xmlEscape(exam.header.teacherSignature)}</w:t></w:r>');
    buffer.write('</w:p>');

    buffer.write('<w:sectPr>');
    buffer.write('<w:pgSz w:w="11906" w:h="16838"/>');
    buffer.write('<w:pgMar w:top="$topMarginDxa" w:right="1134" w:bottom="1134" w:left="1134"/>');
    buffer.write('<w:bidi/>');
    buffer.write('</w:sectPr>');

    buffer.write('</w:body>');
    buffer.write('</w:document>');

    return buffer.toString();
  }

  // بناء جدول Word حقيقي مخصص وقابل للتعديل
  static String _buildDocxCustomTable(String jsonStr) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final int rows = data['rows'] ?? 2;
      final int cols = data['cols'] ?? 2;
      final bool hasHeader = data['hasHeader'] ?? true;
      final List<dynamic> rawGrid = data['data'] ?? [];

      final sb = StringBuffer();
      sb.write('<w:tbl>');
      sb.write('<w:tblPr>');
      sb.write('<w:tblW w:w="7600" w:type="dxa"/>');
      sb.write('<w:jc w:val="center"/>');
      sb.write('<w:bidiVisual/>');
      sb.write('<w:tblBorders>');
      sb.write('<w:top w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
      sb.write('<w:left w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
      sb.write('<w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
      sb.write('<w:right w:val="single" w:sz="8" w:space="0" w:color="000000"/>');
      sb.write('<w:insideH w:val="single" w:sz="6" w:space="0" w:color="000000"/>');
      sb.write('<w:insideV w:val="single" w:sz="6" w:space="0" w:color="000000"/>');
      sb.write('</w:tblBorders>');
      sb.write('</w:tblPr>');

      final int cellWidth = (7600 / (cols > 0 ? cols : 1)).floor();

      for (int r = 0; r < rows; r++) {
        final isHeaderRow = (r == 0 && hasHeader);
        sb.write('<w:tr>');
        if (isHeaderRow) {
          sb.write('<w:trPr><w:tblHeader/></w:trPr>');
        }

        for (int c = 0; c < cols; c++) {
          String val = '';
          if (r < rawGrid.length && c < (rawGrid[r] as List).length) {
            val = rawGrid[r][c]?.toString() ?? '';
          }

          sb.write('<w:tc>');
          sb.write('<w:tcPr>');
          sb.write('<w:tcW w:w="$cellWidth" w:type="dxa"/>');
          sb.write('<w:vAlign w:val="center"/>');
          if (isHeaderRow) {
            sb.write('<w:shd w:val="clear" w:color="auto" w:fill="E2E8F0"/>');
          }
          sb.write('</w:tcPr>');

          sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:line="240" w:lineRule="auto"/></w:pPr>');
          sb.write('<w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:rtl/>');
          if (isHeaderRow) sb.write('<w:b/><w:bCs/>');
          sb.write('<w:sz w:val="${isHeaderRow ? 22 : 20}"/><w:szCs w:val="${isHeaderRow ? 22 : 20}"/>');
          sb.write('</w:rPr><w:t>${_xmlEscape(val)}</w:t></w:r></w:p>');

          sb.write('</w:tc>');
        }
        sb.write('</w:tr>');
      }

      sb.write('</w:tbl>');
      sb.write('<w:p><w:pPr><w:spacing w:after="80"/></w:pPr></w:p>');
      return sb.toString();
    } catch (_) {
      return '';
    }
  }

  // بناء الأشكال التلقائية كإطارات وبطاقات هندسية في Word
  static String _buildDocxCustomShape(String jsonStr) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final String kind = data['kind'] ?? 'rectangle';
      final String label = data['label'] ?? '';
      String stroke = (data['strokeColor'] ?? '000000').replaceAll('#', '').toUpperCase();
      if (stroke.length != 6) stroke = '000000';

      String fill = 'FAFAFA';
      if (data['fillColor'] != null && data['fillColor'] != 'transparent') {
        final cleanFill = (data['fillColor'] as String).replaceAll('#', '').toUpperCase();
        if (cleanFill.length == 6) fill = cleanFill;
      }

      final shapeTitles = {
        'rectangle': 'مستطيل',
        'circle': 'دائرة / شكل بيضاوي',
        'triangle': 'مثلث',
        'rightTriangle': 'مثلث قائم الزاوية',
        'parallelogram': 'متوازي أضلاع',
        'line': 'خط مستقيم',
        'arrow': 'سهم توجيهي',
      };

      final title = shapeTitles[kind] ?? 'شكل هندسي';
      final displayText = label.isNotEmpty ? '$title: $label' : title;

      final sb = StringBuffer();
      sb.write('<w:tbl>');
      sb.write('<w:tblPr>');
      sb.write('<w:tblW w:w="3600" w:type="dxa"/>');
      sb.write('<w:jc w:val="center"/>');
      sb.write('<w:bidiVisual/>');
      sb.write('<w:tblBorders>');
      sb.write('<w:top w:val="single" w:sz="12" w:space="0" w:color="$stroke"/>');
      sb.write('<w:left w:val="single" w:sz="12" w:space="0" w:color="$stroke"/>');
      sb.write('<w:bottom w:val="single" w:sz="12" w:space="0" w:color="$stroke"/>');
      sb.write('<w:right w:val="single" w:sz="12" w:space="0" w:color="$stroke"/>');
      sb.write('</w:tblBorders>');
      sb.write('</w:tblPr>');

      sb.write('<w:tr>');
      sb.write('<w:tc>');
      sb.write('<w:tcPr>');
      sb.write('<w:tcW w:w="3600" w:type="dxa"/>');
      sb.write('<w:shd w:val="clear" w:color="auto" w:fill="$fill"/>');
      sb.write('<w:vAlign w:val="center"/>');
      sb.write('</w:tcPr>');

      sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:before="120" w:after="120"/></w:pPr>');
      sb.write('<w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:b/><w:bCs/><w:rtl/><w:color w:val="$stroke"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr>');
      sb.write('<w:t>${_xmlEscape(displayText)}</w:t></w:r></w:p>');

      sb.write('</w:tc>');
      sb.write('</w:tr>');
      sb.write('</w:tbl>');
      sb.write('<w:p><w:pPr><w:spacing w:after="60"/></w:pPr></w:p>');
      return sb.toString();
    } catch (_) {
      return '';
    }
  }

  // بناء محتوى السؤال مع دعم رصف العمليات المضمنة
  static String _renderDocxParagraphOrTable(List<TextSpanModel> spans) {
    final fullText = spans.map((s) => s.text).join('');
    final lines = fullText.split('\n');
    final sb = StringBuffer();

    for (final line in lines) {
      if (line.contains('[عمودي:')) {
        sb.write(_renderDocxLineWithVerticalOps(line));
      } else if (line.contains('[قسمة:') || line.contains('[div:')) {
        sb.write(_renderDocxLineWithDivision(line));
      } else {
        sb.write('<w:p>');
        sb.write('<w:pPr><w:bidi/><w:jc w:val="right"/><w:spacing w:line="320" w:lineRule="auto"/></w:pPr>');
        final dummySpan = spans.isNotEmpty
            ? TextSpanModel(
                text: line,
                fontSize: spans.first.fontSize,
                isBold: spans.first.isBold,
                isUnderline: spans.first.isUnderline,
                fontFamily: spans.first.fontFamily,
                colorHex: spans.first.colorHex,
              )
            : TextSpanModel(text: line, fontSize: 11, fontFamily: 'Amiri');
        sb.write(_renderDocxInlineRunsWithMath(dummySpan));
        sb.write('</w:p>');
      }
    }

    return sb.toString();
  }

  // رصف العمليات الحسابية العمودية (+, -, ×)
  static String _renderDocxLineWithVerticalOps(String line) {
    final regExp = RegExp(r'\[عمودي:(.*?)\]');
    final matches = regExp.allMatches(line).toList();

    if (matches.isEmpty) {
      return '<w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:rtl/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr><w:t>${_xmlEscape(line)}</w:t></w:r></w:p>';
    }

    final sb = StringBuffer();
    sb.write('<w:tbl>');
    sb.write('<w:tblPr>');
    sb.write('<w:tblW w:w="7800" w:type="dxa"/>');
    sb.write('<w:jc w:val="right"/>');
    sb.write('<w:bidiVisual/>');
    sb.write('<w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders>');
    sb.write('</w:tblPr>');
    sb.write('<w:tr>');

    final int colWidth = (7800 / matches.length).floor();

    for (final m in matches) {
      final content = m.group(1) ?? '';
      final parts = content.split(':');
      final op = parts.isNotEmpty ? parts[0] : '+';
      final numbers = parts.length > 1 ? parts.sublist(1) : <String>[];

      sb.write('<w:tc>');
      sb.write('<w:tcPr><w:tcW w:w="$colWidth" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');

      for (int i = 0; i < numbers.length; i++) {
        final isLast = i == numbers.length - 1;
        final val = numbers[i];
        final lineStr = isLast ? '$op  $val' : '    $val';

        sb.write('<w:p>');
        sb.write('<w:pPr><w:bidi/><w:jc w:val="right"/>');
        if (isLast) {
          sb.write('<w:pBdr><w:bottom w:val="single" w:sz="8" w:space="1" w:color="000000"/></w:pBdr>');
        }
        sb.write('</w:pPr>');
        sb.write('<w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:b/><w:rtl/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr><w:t xml:space="preserve">${_xmlEscape(lineStr)}</w:t></w:r>');
        sb.write('</w:p>');
      }

      sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/><w:spacing w:before="60"/></w:pPr></w:p>');
      sb.write('</w:tc>');
    }

    sb.write('</w:tr>');
    sb.write('</w:tbl>');
    return sb.toString();
  }

  // رصف القسمة المطولة كرسم هندسي في Word
  static String _renderDocxLineWithDivision(String line) {
    final regExp = RegExp(r'\[(قسمة|div):(.*?)(?::(.*?))?(?::(.*?))?\]');
    final m = regExp.firstMatch(line);

    if (m == null) {
      return '<w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:rtl/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr><w:t>${_xmlEscape(line)}</w:t></w:r></w:p>';
    }

    final isRtl = m.group(1) == 'قسمة';
    final dividend = m.group(2) ?? '';
    final divisor = m.group(3) ?? '';
    final quotient = m.group(4) ?? '';

    final sb = StringBuffer();
    sb.write('<w:tbl>');
    sb.write('<w:tblPr>');
    sb.write('<w:tblW w:w="3200" w:type="dxa"/>');
    sb.write('<w:jc w:val="right"/>');
    sb.write('<w:bidiVisual/>');
    sb.write('<w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders>');
    sb.write('</w:tblPr>');

    // صف الناتج
    if (quotient.isNotEmpty) {
      sb.write('<w:tr>');
      sb.write('<w:tc><w:tcPr><w:tcW w:w="800" w:type="dxa"/></w:tcPr><w:p/></w:tc>');
      sb.write('<w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/></w:tcPr>');
      sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:b/><w:rtl/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr><w:t>${_xmlEscape(quotient)}</w:t></w:r></w:p>');
      sb.write('</w:tc>');
      sb.write('</w:tr>');
    }

    // صف كرسي القسمة والمقسوم
    sb.write('<w:tr>');

    // المقسوم عليه
    sb.write('<w:tc>');
    sb.write('<w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
    sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:b/><w:rtl/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr><w:t>${_xmlEscape(divisor)}</w:t></w:r></w:p>');
    sb.write('</w:tc>');

    // المقسوم داخل الكرسي مع إطار علوي وفاصل
    sb.write('<w:tc>');
    sb.write('<w:tcPr>');
    sb.write('<w:tcW w:w="2400" w:type="dxa"/>');
    sb.write('<w:vAlign w:val="center"/>');
    sb.write('<w:tcBorders>');
    sb.write('<w:top w:val="single" w:sz="12" w:space="0" w:color="000000"/>');
    if (isRtl) {
      sb.write('<w:right w:val="single" w:sz="12" w:space="0" w:color="000000"/>');
    } else {
      sb.write('<w:left w:val="single" w:sz="12" w:space="0" w:color="000000"/>');
    }
    sb.write('</w:tcBorders>');
    sb.write('</w:tcPr>');
    sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/><w:spacing w:before="60" w:after="60"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:b/><w:rtl/><w:sz w:val="24"/><w:szCs w:val="24"/></w:rPr><w:t xml:space="preserve"> ${_xmlEscape(dividend)} </w:t></w:r></w:p>');
    sb.write('</w:tc>');

    sb.write('</w:tr>');
    sb.write('</w:tbl>');
    return sb.toString();
  }

  // دعم تحويل النصوص وجميع وسوم المعادلات المركبة إلى عناصر Word
  static String _renderDocxInlineRunsWithMath(TextSpanModel s) {
    final text = s.text;
    final regExp = RegExp(r'\[(كسر|جذر|sqrt|نها|تباديل|توافيق|مجموع|تكامل|متجه|بار|محدد|مصفوفة):(.*?)(?:/(.*?))?\]');
    final matches = regExp.allMatches(text);

    String colorXml = '';
    if (s.colorHex.isNotEmpty && s.colorHex != '#000000') {
      final clean = s.colorHex.replaceAll('#', '').toUpperCase();
      if (clean.length == 6) colorXml = '<w:color w:val="$clean"/>';
    }

    final fontXml = '<w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="${s.fontFamily}"/>';
    final boldXml = s.isBold ? '<w:b/><w:bCs/>' : '';
    final underlineXml = s.isUnderline ? '<w:u w:val="single"/>' : '';
    final szVal = (s.fontSize * 2).toInt();
    final rPr = '<w:rPr>$fontXml<w:rtl/>$boldXml$underlineXml$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr>';

    if (matches.isEmpty) {
      return '<w:r>$rPr<w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r>';
    }

    final sb = StringBuffer();
    int lastIdx = 0;

    for (final m in matches) {
      if (m.start > lastIdx) {
        final part = text.substring(lastIdx, m.start);
        sb.write('<w:r>$rPr<w:t xml:space="preserve">${_xmlEscape(part)}</w:t></w:r>');
      }

      final type = m.group(1);
      final rawContent = m.group(2) ?? '';
      final rawAlt = m.group(3);
      final parts = rawContent.split(':');

      if (type == 'كسر') {
        String num = rawContent;
        String den = rawAlt ?? '';
        if (rawAlt == null && rawContent.contains('/')) {
          final p = rawContent.split('/');
          num = p[0];
          den = p.length > 1 ? p[1] : '';
        }

        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:instrText xml:space="preserve"> EQ \\f(${_xmlEscape(num)},${_xmlEscape(den)}) </w:instrText></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:t xml:space="preserve">${_xmlEscape(num)}/${_xmlEscape(den)}</w:t></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>');
      } else if (type == 'جذر' || type == 'sqrt') {
        final String degree = parts.length > 1 ? parts[0] : '';
        final String radicand = parts.length > 1 ? parts.sublist(1).join(':') : parts[0];

        final eqInstruction = degree.isNotEmpty
            ? ' EQ \\r(${_xmlEscape(degree)},${_xmlEscape(radicand)}) '
            : ' EQ \\r(${_xmlEscape(radicand)}) ';

        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:instrText xml:space="preserve">$eqInstruction</w:instrText></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>');
        final prefix = type == 'جذر' ? '⎷' : '√';
        final fallback = degree.isNotEmpty ? '$prefix($degree)$radicand' : '$prefix$radicand';
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:t xml:space="preserve">${_xmlEscape(fallback)}</w:t></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>');
      } else if (type == 'نها') {
        final v = parts.isNotEmpty ? parts[0] : 'س';
        final t = parts.length > 1 ? parts[1] : '٠';
        final fn = parts.length > 2 ? parts[2] : '';

        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="begin"/></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:instrText xml:space="preserve"> EQ \\o(نهـا,${_xmlEscape(v)} \u2190 ${_xmlEscape(t)}) </w:instrText></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="separate"/></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:t xml:space="preserve">نهـا($v \u2190 $t) $fn</w:t></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="$szVal"/><w:szCs w:val="$szVal"/></w:rPr><w:fldChar w:fldCharType="end"/></w:r>');
        if (fn.isNotEmpty) {
          sb.write('<w:r>$rPr<w:t xml:space="preserve"> ${_xmlEscape(fn)}</w:t></w:r>');
        }
      } else if (type == 'تباديل' || type == 'توافيق') {
        final n = parts.isNotEmpty ? parts[0] : 'ن';
        final r = parts.length > 1 ? parts[1] : 'ر';
        final sym = type == 'تباديل' ? 'ل' : 'ق';

        // العلم فوق والدليل تحت
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:vertAlign w:val="superscript"/><w:sz w:val="${(szVal * 0.75).toInt()}"/></w:rPr><w:t>${_xmlEscape(n)}</w:t></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:sz w:val="${(szVal * 1.2).toInt()}"/></w:rPr><w:t>${_xmlEscape(sym)}</w:t></w:r>');
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:vertAlign w:val="subscript"/><w:sz w:val="${(szVal * 0.75).toInt()}"/></w:rPr><w:t>${_xmlEscape(r)}</w:t></w:r>');
      } else if (type == 'مجموع' || type == 'تكامل') {
        final from = parts.isNotEmpty ? parts[0] : '';
        final to = parts.length > 1 ? parts[1] : '';
        final body = parts.length > 2 ? parts[2] : '';
        final sym = type == 'مجموع' ? 'مجـ' : '∫';

        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:sz w:val="${(szVal * 1.25).toInt()}"/></w:rPr><w:t>${_xmlEscape(sym)}</w:t></w:r>');
        if (from.isNotEmpty || to.isNotEmpty) {
          sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$colorXml<w:sz w:val="${(szVal * 0.75).toInt()}"/></w:rPr><w:t xml:space="preserve"> [${_xmlEscape(from)} \u2192 ${_xmlEscape(to)}] </w:t></w:r>');
        }
        if (body.isNotEmpty) {
          sb.write('<w:r>$rPr<w:t xml:space="preserve">${_xmlEscape(body)}</w:t></w:r>');
        }
      } else if (type == 'متجه') {
        final v = parts.isNotEmpty ? parts[0] : 'ق';
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:sz w:val="$szVal"/></w:rPr><w:t xml:space="preserve">\u20D7${_xmlEscape(v)}</w:t></w:r>');
      } else if (type == 'بار') {
        final v = parts.isNotEmpty ? parts[0] : 'س';
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:sz w:val="$szVal"/></w:rPr><w:t xml:space="preserve">\u0304${_xmlEscape(v)}</w:t></w:r>');
      } else if (type == 'محدد' || type == 'مصفوفة') {
        final isMatrix = type == 'مصفوفة';
        final a = parts.isNotEmpty ? parts[0] : '';
        final b = parts.length > 1 ? parts[1] : '';
        final c = parts.length > 2 ? parts[2] : '';
        final d = parts.length > 3 ? parts[3] : '';

        final open = isMatrix ? '[' : '|';
        final close = isMatrix ? ']' : '|';
        sb.write('<w:r><w:rPr>$fontXml<w:rtl/>$boldXml$colorXml<w:sz w:val="$szVal"/></w:rPr><w:t xml:space="preserve">$open ${_xmlEscape(a)}  ${_xmlEscape(b)} ; ${_xmlEscape(c)}  ${_xmlEscape(d)} $close</w:t></w:r>');
      }

      lastIdx = m.end;
    }

    if (lastIdx < text.length) {
      final part = text.substring(lastIdx);
      sb.write('<w:r>$rPr<w:t xml:space="preserve">${_xmlEscape(part)}</w:t></w:r>');
    }

    return sb.toString();
  }

  static String _buildDocxTwoColumnContent(QuestionModel q) {
    final fullText = q.spans.map((s) => s.text).join('');
    final lines = fullText.split('\n').where((l) => l.trim().isNotEmpty).toList();

    if (lines.length <= 1) {
      final dummySpan = q.spans.isNotEmpty
          ? q.spans.first
          : TextSpanModel(text: fullText, fontSize: 11, fontFamily: 'Amiri');
      return '<w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>${_renderDocxInlineRunsWithMath(dummySpan)}</w:p>';
    }

    final intro = lines.first;
    final items = lines.sublist(1);
    final int half = (items.length / 2).ceil();
    final colRight = items.sublist(0, half);
    final colLeft = items.sublist(half);

    final sb = StringBuffer();

    final introSpan = TextSpanModel(text: intro, fontSize: 11, isBold: true, fontFamily: 'Amiri');
    sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>${_renderDocxInlineRunsWithMath(introSpan)}</w:p>');

    sb.write('<w:tbl>');
    sb.write('<w:tblPr>');
    sb.write('<w:tblW w:w="7800" w:type="dxa"/>');
    sb.write('<w:bidiVisual/>');
    sb.write('<w:tblBorders>');
    sb.write('<w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/>');
    sb.write('<w:insideH w:val="none"/><w:insideV w:val="none"/>');
    sb.write('</w:tblBorders>');
    sb.write('</w:tblPr>');

    final int maxRows = half;
    for (int i = 0; i < maxRows; i++) {
      final rightText = i < colRight.length ? colRight[i] : '';
      final leftText = i < colLeft.length ? colLeft[i] : '';

      final rSpan = TextSpanModel(text: rightText, fontSize: 10.5, fontFamily: 'Amiri');
      final lSpan = TextSpanModel(text: leftText, fontSize: 10.5, fontFamily: 'Amiri');

      sb.write('<w:tr>');

      sb.write('<w:tc>');
      sb.write('<w:tcPr><w:tcW w:w="3900" w:type="dxa"/></w:tcPr>');
      sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>${_renderDocxInlineRunsWithMath(rSpan)}</w:p>');
      sb.write('</w:tc>');

      sb.write('<w:tc>');
      sb.write('<w:tcPr><w:tcW w:w="3900" w:type="dxa"/></w:tcPr>');
      sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>${_renderDocxInlineRunsWithMath(lSpan)}</w:p>');
      sb.write('</w:tc>');

      sb.write('</w:tr>');
    }

    sb.write('</w:tbl>');
    return sb.toString();
  }

  static String _buildDocxMathOperation(String jsonStr) {
    try {
      final data = jsonDecode(jsonStr);
      final kind = data['kind'] ?? 'vertical';

      if (kind == 'vertical') {
        final List<dynamic> rows = data['rows'] ?? [];
        final String op = data['operator'] ?? '+';
        final bool opOnRight = data['opOnRight'] ?? true;

        final sb = StringBuffer();
        sb.write('<w:tbl>');
        sb.write('<w:tblPr>');
        sb.write('<w:tblW w:w="0" w:type="auto"/>');
        sb.write('<w:jc w:val="center"/>');
        sb.write('<w:bidiVisual/>');
        sb.write('<w:tblBorders>');
        sb.write('<w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/>');
        sb.write('<w:insideH w:val="none"/><w:insideV w:val="none"/>');
        sb.write('</w:tblBorders>');
        sb.write('</w:tblPr>');

        for (int i = 0; i < rows.length; i++) {
          final isLast = i == rows.length - 1;
          final val = rows[i].toString();

          sb.write('<w:tr>');
          sb.write('<w:tc>');
          sb.write('<w:tcPr>');
          sb.write('<w:tcW w:w="1800" w:type="dxa"/>');
          if (isLast) {
            sb.write('<w:tcBorders>');
            sb.write('<w:bottom w:val="single" w:sz="12" w:space="0" w:color="000000"/>');
            sb.write('</w:tcBorders>');
          }
          sb.write('</w:tcPr>');

          final prefix = (opOnRight && isLast) ? '$op ' : '';
          final suffix = (!opOnRight && isLast) ? ' $op' : '';
          final line = '$prefix$val$suffix';

          sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>');
          sb.write('<w:r><w:rPr><w:b/><w:rtl/><w:sz w:val="26"/></w:rPr><w:t>${_xmlEscape(line)}</w:t></w:r>');
          sb.write('</w:p>');

          sb.write('</w:tc>');
          sb.write('</w:tr>');
        }

        sb.write('<w:tr><w:tc><w:tcPr><w:tcW w:w="1800" w:type="dxa"/></w:tcPr>');
        sb.write('<w:p><w:pPr><w:bidi/><w:spacing w:before="100" w:after="100"/></w:pPr></w:p>');
        sb.write('</w:tc></w:tr>');

        sb.write('</w:tbl>');
        return sb.toString();
      } else if (kind == 'fraction') {
        final num = data['num'] ?? '';
        final den = data['den'] ?? '';
        final int maxLen = num.length > den.length ? num.length : den.length;
        final int colWidth = (maxLen * 160) + 300;

        final sb = StringBuffer();
        sb.write('<w:tbl>');
        sb.write('<w:tblPr>');
        sb.write('<w:tblW w:w="$colWidth" w:type="dxa"/>');
        sb.write('<w:jc w:val="center"/>');
        sb.write('<w:bidiVisual/>');
        sb.write('<w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders>');
        sb.write('</w:tblPr>');

        sb.write('<w:tr><w:tc><w:tcPr><w:tcW w:w="$colWidth" w:type="dxa"/>');
        sb.write('<w:tcBorders><w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/></w:tcBorders>');
        sb.write('</w:tcPr>');
        sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr>');
        sb.write('<w:r><w:rPr><w:b/><w:rtl/><w:sz w:val="22"/></w:rPr><w:t>${_xmlEscape(num)}</w:t></w:r>');
        sb.write('</w:p></w:tc></w:tr>');

        sb.write('<w:tr><w:tc><w:tcPr><w:tcW w:w="$colWidth" w:type="dxa"/></w:tcPr>');
        sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr>');
        sb.write('<w:r><w:rPr><w:b/><w:rtl/><w:sz w:val="22"/></w:rPr><w:t>${_xmlEscape(den)}</w:t></w:r>');
        sb.write('</w:p></w:tc></w:tr>');

        sb.write('</w:tbl>');
        return sb.toString();
      }
    } catch (_) {}
    return '';
  }

  static String _buildHeaderParagraph(String text, {bool isBold = false, int fontSize = 18, String align = 'center'}) {
    return '<w:p><w:pPr><w:bidi/><w:jc w:val="$align"/><w:spacing w:line="240" w:lineRule="auto"/></w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:rtl/>'
        '${isBold ? '<w:b/><w:bCs/>' : ''}'
        '<w:sz w:val="$fontSize"/><w:szCs w:val="$fontSize"/>'
        '</w:rPr><w:t>${_xmlEscape(text)}</w:t></w:r></w:p>';
  }

  static String _buildCellParagraph(String text, {bool isBold = false, int fontSize = 20, String align = 'right', String? color}) {
    return '<w:p><w:pPr><w:bidi/><w:jc w:val="$align"/></w:pPr>'
        '<w:r><w:rPr><w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="Amiri"/><w:rtl/>'
        '${isBold ? '<w:b/><w:bCs/>' : ''}'
        '${color != null ? '<w:color w:val="$color"/>' : ''}'
        '<w:sz w:val="$fontSize"/><w:szCs w:val="$fontSize"/>'
        '</w:rPr><w:t>${_xmlEscape(text)}</w:t></w:r></w:p>';
  }

  static String _xmlEscape(String str) {
    return str
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  static const _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

  static const _rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static const _docRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';
}


import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import '../models/exam_models.dart';

class DocxGeneratorService {
  static Future<void> generateAndOpenDocx(ExamModel exam) async {
    final docxBytes = await _buildDocxBytes(exam);

    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
      if (!downloadsDir.existsSync()) {
        downloadsDir = await getExternalStorageDirectory();
      }
    } else {
      downloadsDir = await getApplicationDocumentsDirectory();
    }

    final safeName = exam.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final filePath = '${downloadsDir!.path}/$safeName.docx';
    final file = File(filePath);
    await file.writeAsBytes(docxBytes);

    await OpenFile.open(filePath);
  }

  static Future<List<int>> _buildDocxBytes(ExamModel exam) async {
    final archive = Archive();

    // 1. [Content_Types].xml
    archive.addFile(ArchiveFile(
      '[Content_Types].xml',
      _contentTypesXml.length,
      utf8.encode(_contentTypesXml),
    ));

    // 2. _rels/.rels
    archive.addFile(ArchiveFile(
      '_rels/.rels',
      _rootRelsXml.length,
      utf8.encode(_rootRelsXml),
    ));

    // 3. word/_rels/document.xml.rels
    archive.addFile(ArchiveFile(
      'word/_rels/document.xml.rels',
      _docRelsXml.length,
      utf8.encode(_docRelsXml),
    ));

    // 4. word/document.xml
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

    // ضبط الهامش العلوي والصفحة RTL
    final topMarginDxa = exam.header.topMargin1cm ? '567' : '283'; // 1 سم = 567 dxa

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

    // الصف الأول في الترويسة (3 خانات)
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

    // مسافة فاصلة بين الترويسة وجدول الأسئلة
    buffer.write('<w:p><w:pPr><w:spacing w:before="120" w:after="120"/></w:pPr></w:p>');

    // 2. جدول الأسئلة مع صف العناوين المدمج
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

    // عمود السؤال
    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
    buffer.write(_buildCellParagraph('السؤال', isBold: true, fontSize: 19, align: 'center'));
    buffer.write('</w:tc>');

    // عمود عبارة التوجيه
    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="7900" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
    buffer.write(_buildCellParagraph(exam.header.instructionText, isBold: true, fontSize: 20, align: 'center', color: 'C00000'));
    buffer.write('</w:tc>');

    // عمود الدرجة
    buffer.write('<w:tc>');
    buffer.write('<w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
    buffer.write(_buildCellParagraph('الدرجة', isBold: true, fontSize: 19, align: 'center'));
    buffer.write('</w:tc>');

    buffer.write('</w:tr>');

    // صفوف الأسئلة والفقرات
    for (final q in exam.questions) {
      buffer.write('<w:tr>');

      // 1. رقم السؤال
      buffer.write('<w:tc>');
      buffer.write('<w:tcPr><w:tcW w:w="800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>');
      buffer.write(_buildCellParagraph(q.title, isBold: true, fontSize: 20, align: 'center'));
      buffer.write('</w:tc>');

      // 2. محتوى السؤال والعناصر المرفقة
      buffer.write('<w:tc>');
      buffer.write('<w:tcPr><w:tcW w:w="7900" w:type="dxa"/></w:tcPr>');

      // فقرة نص السؤال
      buffer.write('<w:p>');
      buffer.write('<w:pPr><w:bidi/><w:jc w:val="right"/><w:spacing w:line="320" w:lineRule="auto"/></w:pPr>');
      for (final s in q.spans) {
        buffer.write('<w:r>');
        buffer.write('<w:rPr>');
        buffer.write('<w:rFonts w:ascii="Amiri" w:hAnsi="Amiri" w:cs="${s.fontFamily}"/>');
        buffer.write('<w:rtl/>');
        if (s.isBold) buffer.write('<w:b/><w:bCs/>');
        if (s.isUnderline) buffer.write('<w:u w:val="single"/>');
        buffer.write('<w:sz w:val="${(s.fontSize * 2).toInt()}"/>');
        buffer.write('<w:szCs w:val="${(s.fontSize * 2).toInt()}"/>');
        buffer.write('</w:rPr>');
        buffer.write('<w:t xml:space="preserve">${_xmlEscape(s.text)}</w:t>');
        buffer.write('</w:r>');
      }
      buffer.write('</w:p>');

      // العناصر المرفقة (مربعات إرشاد، أسطر إجابة، عمليات رياضية)
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
        }
      }

      buffer.write('</w:tc>');

      // 3. درجة السؤال
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

    // خصائص الصفحة
    buffer.write('<w:sectPr>');
    buffer.write('<w:pgSz w:w="11906" w:h="16838"/>'); // A4
    buffer.write('<w:pgMar w:top="$topMarginDxa" w:right="1134" w:bottom="1134" w:left="1134"/>');
    buffer.write('<w:bidi/>');
    buffer.write('</w:sectPr>');

    buffer.write('</w:body>');
    buffer.write('</w:document>');

    return buffer.toString();
  }

  // بناء العملية الرياضية الرأسية أو الكسر داخل جدول Word مدمج
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

          final prefix = (!opOnRight && isLast) ? '$op ' : '';
          final suffix = (opOnRight && isLast) ? ' $op' : '';
          final line = '$prefix$val$suffix';

          sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="right"/></w:pPr>');
          sb.write('<w:r><w:rPr><w:b/><w:rtl/><w:sz w:val="26"/></w:rPr><w:t>${_xmlEscape(line)}</w:t></w:r>');
          sb.write('</w:p>');

          sb.write('</w:tc>');
          sb.write('</w:tr>');
        }

        // صف فارغ للناتج
        sb.write('<w:tr><w:tc><w:tcPr><w:tcW w:w="1800" w:type="dxa"/></w:tcPr>');
        sb.write('<w:p><w:pPr><w:bidi/><w:spacing w:before="100" w:after="100"/></w:pPr></w:p>');
        sb.write('</w:tc></w:tr>');

        sb.write('</w:tbl>');
        return sb.toString();
      } else if (kind == 'fraction') {
        final num = data['num'] ?? '';
        final den = data['den'] ?? '';

        final sb = StringBuffer();
        sb.write('<w:tbl>');
        sb.write('<w:tblPr>');
        sb.write('<w:tblW w:w="0" w:type="auto"/>');
        sb.write('<w:bidiVisual/>');
        sb.write('<w:tblBorders><w:top w:val="none"/><w:left w:val="none"/><w:bottom w:val="none"/><w:right w:val="none"/><w:insideH w:val="none"/><w:insideV w:val="none"/></w:tblBorders>');
        sb.write('</w:tblPr>');

        // البسط مع خط سفلي
        sb.write('<w:tr><w:tc><w:tcPr><w:tcW w:w="1200" w:type="dxa"/>');
        sb.write('<w:tcBorders><w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/></w:tcBorders>');
        sb.write('</w:tcPr>');
        sb.write('<w:p><w:pPr><w:bidi/><w:jc w:val="center"/></w:pPr>');
        sb.write('<w:r><w:rPr><w:b/><w:rtl/><w:sz w:val="22"/></w:rPr><w:t>${_xmlEscape(num)}</w:t></w:r>');
        sb.write('</w:p></w:tc></w:tr>');

        // المقام
        sb.write('<w:tr><w:tc><w:tcPr><w:tcW w:w="1200" w:type="dxa"/></w:tcPr>');
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

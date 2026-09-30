import 'dart:io';
import 'package:archive/archive.dart';
import 'package:open_filex/open_filex.dart';
import '../models/exam_models.dart';
import 'file_manager.dart';

class DocxGeneratorService {
  /// توليد مستند Word DOCX وحفظه في مجلد التنزيلات ثم فتحه
  static Future<String> generateAndOpenDocx(ExamModel exam) async {
    final filePath = await FileManager.getFullFilePath(exam.fileName);
    final file = File(filePath);

    final archive = Archive();

    // 1. [Content_Types].xml
    archive.addFile(ArchiveFile('[Content_Types].xml', _contentTypesXml.length, _contentTypesXml.codeUnits));

    // 2. _rels/.rels
    archive.addFile(ArchiveFile('_rels/.rels', _globalRelsXml.length, _globalRelsXml.codeUnits));

    // 3. word/_rels/document.xml.rels
    archive.addFile(ArchiveFile('word/_rels/document.xml.rels', _documentRelsXml.length, _documentRelsXml.codeUnits));

    // 4. word/document.xml
    final documentXml = _buildDocumentXml(exam);
    archive.addFile(ArchiveFile('word/document.xml', documentXml.length, documentXml.codeUnits));

    // ضغط الملف وحفظه
    final zipEncoder = ZipEncoder();
    final encodedZip = zipEncoder.encode(archive);
    if (encodedZip != null) {
      await file.writeAsBytes(encodedZip);
    }

    // فتح الملف فوراً داخل Microsoft Office على هاتف المعلم
    await OpenFilex.open(filePath);

    return filePath;
  }

  /// دالة تحويل اتجاه اسم السؤال إلى وسم OpenXML المقابل
  static String _getTitleDirectionXml(QuestionTitleOrientation orientation) {
    switch (orientation) {
      case QuestionTitleOrientation.verticalBottomToTop:
        return '<w:textDirection w:val="btLr"/>'; // رأسي للأعلى
      case QuestionTitleOrientation.verticalTopToBottom:
        return '<w:textDirection w:val="tbRl"/>'; // رأسي للأسفل
      case QuestionTitleOrientation.horizontal:
      default:
        return ''; // أفقي عادي
    }
  }

  /// بناء مستند OpenXML الكامل
  static String _buildDocumentXml(ExamModel exam) {
    final topMarginTwips = exam.header.topMargin1cm ? "567" : "1134"; // 1 سم = 567 twips

    final sb = StringBuffer();
    sb.write('''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
''');

    // --- جدول الترويسة المعتمدة المطابقة لنموذجك ---
    sb.write('''
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="0" w:type="auto"/>
        <w:tblBorders>
          <w:top w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:left w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:bottom w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:right w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/>
          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/>
        </w:tblBorders>
        <w:bidiVisual/>
      </w:tblPr>

      <!-- الصف 1: الأعمدة الثلاثة -->
      <w:tr>
        <!-- اليمين: إدارة ومدرسة -->
        <w:tc>
          <w:tcPr><w:tcW w:w="3600" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="24"/></w:rPr><w:t>${exam.header.country}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:sz w:val="20"/></w:rPr><w:t>${exam.header.ministry}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:sz w:val="20"/></w:rPr><w:t>${exam.header.governorate}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:sz w:val="20"/></w:rPr><w:t>${exam.header.directorate}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="20"/></w:rPr><w:t>${exam.header.school}</w:t></w:r></w:p>
        </w:tc>

        <!-- الوسط: البسملة والشعار -->
        <w:tc>
          <w:tcPr><w:tcW w:w="2800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="22"/></w:rPr><w:t>${exam.header.basmalaText}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="18"/></w:rPr><w:t>[ طير الجمهورية ]</w:t></w:r></w:p>
        </w:tc>

        <!-- اليسار: بيانات المادة -->
        <w:tc>
          <w:tcPr><w:tcW w:w="3600" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="22"/></w:rPr><w:t>الصف : ${exam.header.grade}</w:t></w:r></w:p>
          <w:p><w:pPr><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="22"/></w:rPr><w:t>الماده : ${exam.header.subject}</w:t></w:r></w:p>
          <w:p><w:pPr><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:sz w:val="20"/></w:rPr><w:t>التاريخ: ${exam.header.examDate}</w:t></w:r></w:p>
          <w:p><w:pPr><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:sz w:val="20"/></w:rPr><w:t>الزمن: ${exam.header.examTime}   الفتره ( ${exam.header.period} )</w:t></w:r></w:p>
        </w:tc>
      </w:tr>

      <!-- الصف 2: الشريط العريض للعنوان -->
      <w:tr>
        <w:tc>
          <w:tcPr><w:gridSpan w:val="3"/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="26"/></w:rPr><w:t>${exam.header.examTitle}</w:t></w:r></w:p>
        </w:tc>
      </w:tr>

      <!-- الصف 3: التوجيه (السؤال | العبارة | الدرجة) -->
      <w:tr>
        <w:tc>
          <w:tcPr><w:tcW w:w="1200" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="22"/></w:rPr><w:t>السؤال</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="7600" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:color w:val="C00000"/><w:sz w:val="22"/></w:rPr><w:t>${exam.header.instructionText}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="1200" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="22"/></w:rPr><w:t>الدرجه</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
    </w:tbl>
''');

    // --- جدول الأسئلة بالتقسيم الثلاثي وتدوير الخلايا ---
    sb.write('''
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="0" w:type="auto"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="4" w:space="0" w:color="000000"/>
          <w:left w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:bottom w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:right w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="CCCCCC"/>
          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/>
        </w:tblBorders>
        <w:bidiVisual/>
      </w:tblPr>
''');

    for (var q in exam.questions) {
      final directionTag = _getTitleDirectionXml(q.titleOrientation);

      sb.write('''
      <w:tr>
        <!-- 1. خانة اسم السؤال مع التدوير الرأسي/الأفقي -->
        <w:tc>
          <w:tcPr>
            <w:tcW w:w="1200" w:type="dxa"/>
            $directionTag
            <w:vAlign w:val="center"/>
          </w:tcPr>
          <w:p>
            <w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr>
            <w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="22"/></w:rPr><w:t>${q.title}</w:t></w:r>
          </w:p>
        </w:tc>

        <!-- 2. خانة محتوى السؤال (كشيدة، تسطير، تفخيم) -->
        <w:tc>
          <w:tcPr><w:tcW w:w="7600" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:bidi/></w:pPr>
''');

      for (var span in q.spans) {
        final halfPtSize = (span.fontSize * 2).toInt();
        sb.write('''
            <w:r>
              <w:rPr>
                <w:rFonts w:cs="${span.fontFamily}"/>
                ${span.isBold ? '<w:b/>' : ''}
                ${span.isUnderline ? '<w:u w:val="single"/>' : ''}
                <w:sz w:val="$halfPtSize"/>
              </w:rPr>
              <w:t xml:space="preserve">${span.text}</w:t>
            </w:r>
''');
      }

      sb.write('''
          </w:p>
        </w:tc>

        <!-- 3. خانة الدرجة -->
        <w:tc>
          <w:tcPr><w:tcW w:w="1200" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p>
            <w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr>
            <w:r><w:rPr><w:rFonts w:cs="Traditional Arabic"/><w:b/><w:sz w:val="22"/></w:rPr><w:t>${q.mark > 0 ? q.mark.toString() : ''}</w:t></w:r>
          </w:p>
        </w:tc>
      </w:tr>
''');
    }

    sb.write('</w:tbl>');

    // --- التذييل المرن الملتصق بآخر سؤال مباشرة ---
    sb.write('''
    <w:p>
      <w:pPr>
        <w:spacing w:before="240" w:after="80"/>
        <w:jc w:val="center"/>
        <w:bidi/>
      </w:pPr>
      <w:r>
        <w:rPr>
          <w:rFonts w:cs="Traditional Arabic"/>
          <w:b/>
          <w:sz w:val="24"/>
        </w:rPr>
        <w:t xml:space="preserve">${exam.header.isMultiPage ? exam.header.continuationText : exam.header.singlePageFooterText}</w:t>
      </w:r>
    </w:p>

    <!-- توقيع المعلم -->
    <w:p>
      <w:pPr>
        <w:jc w:val="left"/>
        <w:bidi/>
      </w:pPr>
      <w:r>
        <w:rPr>
          <w:rFonts w:cs="Traditional Arabic"/>
          <w:b/>
          <w:sz w:val="22"/>
        </w:rPr>
        <w:t xml:space="preserve">${exam.header.teacherSignature}</w:t>
      </w:r>
    </w:p>
''');

    // ضبط الهوامش (فراغ 1 سم علوي)
    sb.write('''
    <w:sectPr>
      <w:pgMar w:top="$topMarginTwips" w:bottom="567" w:left="567" w:right="567" w:header="0" w:footer="0"/>
    </w:sectPr>
  </w:body>
</w:document>
''');

    return sb.toString();
  }

  static const _contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

  static const _globalRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

  static const _documentRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
</Relationships>''';
}

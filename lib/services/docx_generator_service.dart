import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/exam_models.dart';
import 'file_manager.dart';

class DocxGeneratorService {
  static Future<void> generateAndOpenDocx(ExamModel exam) async {
    final archive = Archive();

    // 1. [Content_Types].xml
    const contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="png" ContentType="image/png"/>
  <Default Extension="jpeg" ContentType="image/jpeg"/>
  <Default Extension="jpg" ContentType="image/jpeg"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';
    _addFile(archive, '[Content_Types].xml', utf8.encode(contentTypesXml));

    // 2. _rels/.rels
    const rootRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';
    _addFile(archive, '_rels/.rels', utf8.encode(rootRelsXml));

    // 3. معالجة الصور وضبط علاقات word/_rels/document.xml.rels
    final imageRelationships = <String>[];
    int imageIndex = 1;

    // إضافة شعار الترويسة إن وجد
    if (exam.header.logoImagePath != null &&
        File(exam.header.logoImagePath!).existsSync()) {
      final logoBytes = File(exam.header.logoImagePath!).readAsBytesSync();
      final mediaPath = 'word/media/image$imageIndex.png';
      _addFile(archive, mediaPath, logoBytes);
      imageRelationships.add(
          '<Relationship Id="rIdLogo" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image$imageIndex.png"/>');
      imageIndex++;
    }

    // إضافة صور الأسئلة المدرجة
    final elementRelMap = <String, String>{};
    for (var q in exam.questions) {
      for (var el in q.elements) {
        if (el.type == ElementType.image && File(el.content).existsSync()) {
          final relId = 'rIdImg$imageIndex';
          final imgBytes = File(el.content).readAsBytesSync();
          final mediaPath = 'word/media/image$imageIndex.png';
          _addFile(archive, mediaPath, imgBytes);
          imageRelationships.add(
              '<Relationship Id="$relId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image$imageIndex.png"/>');
          elementRelMap[el.id] = relId;
          imageIndex++;
        }
      }
    }

    final docRelsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  ${imageRelationships.join('\n  ')}
</Relationships>''';
    _addFile(archive, 'word/_rels/document.xml.rels', utf8.encode(docRelsXml));

    // 4. بناء word/document.xml
    final documentXml = _buildDocumentXml(exam, elementRelMap);
    _addFile(archive, 'word/document.xml', utf8.encode(documentXml));

    // 5. ضغط الأرشيف وتخزين الملف محلياً
    final zipEncoder = ZipEncoder();
    final docxBytes = zipEncoder.encode(archive);
    if (docxBytes == null) return;

    final tempDir = await getTemporaryDirectory();
    final safeName = FileManager.sanitizeFileName(exam.fileName);
    final filePath = '${tempDir.path}/$safeName.docx';
    final docxFile = File(filePath);
    await docxFile.writeAsBytes(docxBytes, flush: true);

    // 6. فتح الملف مباشرة في تطبيق الأوفيس المثبت على الهاتف
    await OpenFilex.open(filePath);
  }

  static void _addFile(Archive archive, String path, List<int> bytes) {
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  static String _buildDocumentXml(
      ExamModel exam, Map<String, String> elementRelMap) {
    final topMarginDxa = exam.header.topMargin1cm ? '567' : '1134';

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
            xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
            xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
            xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
  <w:body>
    ${_buildHeaderTableXml(exam)}
    <w:p><w:r><w:t></w:t></w:r></w:p>
    ${_buildQuestionsTableXml(exam, elementRelMap)}
    ${_buildFooterXml(exam)}

    <w:sectPr>
      <w:pgSz w:w="11906" w:h="16838"/>
      <w:pgMar w:top="$topMarginDxa" w:right="850" w:bottom="850" w:left="850" w:header="0" w:footer="0"/>
      <w:bidi/>
    </w:sectPr>
  </w:body>
</w:document>''';
  }

  static String _buildHeaderTableXml(ExamModel exam) {
    return '''
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="10200" w:type="dxa"/>
        <w:tblBorders>
          <w:top w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:left w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:bottom w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:right w:val="double" w:sz="12" w:space="0" w:color="000000"/>
          <w:insideH w:val="single" w:sz="4" w:space="0" w:color="000000"/>
          <w:insideV w:val="single" w:sz="4" w:space="0" w:color="000000"/>
        </w:tblBorders>
        <w:jc w:val="center"/>
        <w:bidiVisual/>
      </w:tblPr>
      <w:tr>
        <w:tc>
          <w:tcPr><w:tcW w:w="3600" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t>${exam.header.country}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>${exam.header.ministry}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>${exam.header.governorate}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>${exam.header.directorate}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="20"/></w:rPr><w:t>${exam.header.school}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="3000" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t>${exam.header.basmalaText}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="3600" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="right"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t>الصف: ${exam.header.grade}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="right"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t>المادة: ${exam.header.subject}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="right"/><w:bidi/></w:pPr><w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>التاريخ: ${exam.header.examDate}</w:t></w:r></w:p>
          <w:p><w:pPr><w:jc w:val="right"/><w:bidi/></w:pPr><w:r><w:rPr><w:sz w:val="18"/></w:rPr><w:t>الزمن: ${exam.header.examTime} (الفترة ${exam.header.period})</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
      <w:tr>
        <w:tc>
          <w:tcPr><w:gridSpan w:val="3"/><w:shd w:val="clear" w:color="auto" w:fill="E8E8E8"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="24"/></w:rPr><w:t>${exam.header.examTitle}</w:t></w:r></w:p>
        </w:tc>
      </w:tr>
      <w:tr>
        <w:tc><w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t>السؤال</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:color w:val="C00000"/><w:sz w:val="22"/></w:rPr><w:t>${exam.header.instructionText}</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t>الدرجة</w:t></w:r></w:p></w:tc>
      </w:tr>
    </w:tbl>''';
  }

  static String _buildQuestionsTableXml(
      ExamModel exam, Map<String, String> elementRelMap) {
    final rows = <String>[];

    for (var q in exam.questions) {
      String orientationXml = '';
      if (q.titleOrientation == QuestionTitleOrientation.verticalBottomToTop) {
        orientationXml = '<w:textDirection w:val="btLr"/>';
      } else if (q.titleOrientation ==
          QuestionTitleOrientation.verticalTopToBottom) {
        orientationXml = '<w:textDirection w:val="tbRl"/>';
      }

      final spansXml = q.spans.map((s) {
        return '''
        <w:r>
          <w:rPr>
            <w:rFonts w:ascii="${s.fontFamily}" w:cs="${s.fontFamily}"/>
            ${s.isBold ? '<w:b/>' : ''}
            ${s.isUnderline ? '<w:u w:val="single"/>' : ''}
            <w:sz w:val="${(s.fontSize * 2).toInt()}"/>
            <w:rtl/>
          </w:rPr>
          <w:t xml:space="preserve">${s.text}</w:t>
        </w:r>''';
      }).join('');

      final elementsXml = q.elements.map((el) {
        if (el.type == ElementType.textBox) {
          return '''
          <w:p>
            <w:pPr>
              <w:pBdr>
                <w:top w:val="single" w:sz="6" w:space="2" w:color="000000"/>
                <w:left w:val="single" w:sz="6" w:space="2" w:color="000000"/>
                <w:bottom w:val="single" w:sz="6" w:space="2" w:color="000000"/>
                <w:right w:val="single" w:sz="6" w:space="2" w:color="000000"/>
              </w:pBdr>
              <w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/>
              <w:jc w:val="center"/>
              <w:bidi/>
            </w:pPr>
            <w:r>
              <w:rPr><w:b/><w:sz w:val="22"/><w:rtl/></w:rPr>
              <w:t>${el.content}</w:t>
            </w:r>
          </w:p>''';
        } else if (el.type == ElementType.dottedLine) {
          return '''
          <w:p>
            <w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr>
            <w:r><w:rPr><w:sz w:val="24"/></w:rPr><w:t>${el.content}</w:t></w:r>
          </w:p>''';
        } else if (el.type == ElementType.image) {
          final relId = elementRelMap[el.id];
          if (relId != null) {
            return '''
            <w:p>
              <w:pPr><w:jc w:val="center"/></w:pPr>
              <w:r>
                <w:drawing>
                  <wp:inline distT="0" distB="0" distL="0" distR="0">
                    <wp:extent cx="1080000" cy="1080000"/>
                    <wp:docPr id="1" name="ElementImage"/>
                    <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
                      <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                        <pic:pic>
                          <pic:nvPicPr>
                            <pic:cNvPr id="0" name="Picture"/>
                            <pic:cNvPicPr/>
                          </pic:nvPicPr>
                          <pic:blipFill>
                            <a:blip r:embed="$relId"/>
                            <a:stretch><a:fillRect/></a:stretch>
                          </pic:blipFill>
                          <pic:spPr>
                            <a:xfrm><a:off x="0" y="0"/><a:ext cx="1080000" cy="1080000"/></a:xfrm>
                            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                          </pic:spPr>
                        </pic:pic>
                      </a:graphicData>
                    </a:graphic>
                  </wp:inline>
                </w:drawing>
              </w:r>
            </w:p>''';
          }
        }
        return '';
      }).join('');

      rows.add('''
      <w:tr>
        <w:tc>
          <w:tcPr>
            <w:tcW w:w="1200" w:type="dxa"/>
            <w:vAlign w:val="center"/>
            $orientationXml
          </w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t>${q.title}</w:t></w:r></w:p>
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="7800" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="right"/><w:bidi/></w:pPr>$spansXml</w:p>
          $elementsXml
        </w:tc>
        <w:tc>
          <w:tcPr><w:tcW w:w="1200" w:type="dxa"/><w:vAlign w:val="center"/></w:tcPr>
          <w:p><w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr><w:r><w:rPr><w:b/><w:sz w:val="22"/></w:rPr><w:t>${q.mark > 0 ? q.mark.toString() : '-'}</w:t></w:r></w:p>
        </w:tc>
      </w:tr>''');
    }

    return '''
    <w:tbl>
      <w:tblPr>
        <w:tblW w:w="10200" w:type="dxa"/>
        <w:tblBorders>
          <w:top w:val="single" w:sz="8" w:space="0" w:color="000000"/>
          <w:left w:val="single" w:sz="8" w:space="0" w:color="000000"/>
          <w:bottom w:val="single" w:sz="8" w:space="0" w:color="000000"/>
          <w:right w:val="single" w:sz="8" w:space="0" w:color="000000"/>
          <w:insideH w:val="single" w:sz="6" w:space="0" w:color="000000"/>
          <w:insideV w:val="single" w:sz="6" w:space="0" w:color="000000"/>
        </w:tblBorders>
        <w:jc w:val="center"/>
        <w:bidiVisual/>
      </w:tblPr>
      ${rows.join('\n')}
    </w:tbl>''';
  }

  static String _buildFooterXml(ExamModel exam) {
    final footerMsg = exam.header.isMultiPage
        ? exam.header.continuationText
        : exam.header.singlePageFooterText;

    return '''
    <w:p>
      <w:pPr><w:jc w:val="center"/><w:bidi/></w:pPr>
      <w:r><w:rPr><w:b/><w:sz w:val="24"/></w:rPr><w:t>$footerMsg</w:t></w:r>
    </w:p>
    <w:p>
      <w:pPr><w:jc w:val="left"/><w:bidi/></w:pPr>
      <w:r><w:rPr><w:sz w:val="20"/></w:rPr><w:t>${exam.header.teacherSignature}</w:t></w:r>
    </w:p>''';
  }
}

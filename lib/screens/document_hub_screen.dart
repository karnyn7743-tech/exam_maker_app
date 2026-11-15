import 'dart:io';

import 'package:fluent_editor/fluent_editor.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/localization/fluent_editor_labels.dart';
import 'package:fluent_editor/services/import_docx_service.dart';
import 'package:fluent_editor/services/export_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/student_excel_service.dart';
import 'package:pdfx/pdfx.dart';
import 'package:printing/printing.dart';

/// بوابة مستقلة لفتح مستندات PDF وDOCX دون إدخالها في نموذج الاختبار القديم.
class DocumentHubScreen extends StatefulWidget {
  const DocumentHubScreen({super.key});

  @override
  State<DocumentHubScreen> createState() => _DocumentHubScreenState();
}

class _DocumentHubScreenState extends State<DocumentHubScreen> {
  String? _filePath;
  String? _fileName;
  String? _originalPdfPath;
  String? _excelPath;
  bool _isPdf = true;
  bool _isBusy = false;
  String? _loadError;
  PdfControllerPinch? _pdfController;
  FluentDocument? _wordDocument;
  final TextEditingController _subjectController =
      TextEditingController(text: 'الرياضيات');
  final TextEditingController _gradeController =
      TextEditingController(text: 'التاسع');
  final TextEditingController _examTitleController =
      TextEditingController(text: 'اختبار الشهر');

  @override
  void dispose() {
    _pdfController?.dispose();
    _subjectController.dispose();
    _gradeController.dispose();
    _examTitleController.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'docx'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null || path.trim().isEmpty) {
      _showMessage('تعذر الوصول إلى الملف المحدد.', isError: true);
      return;
    }

    final lower = path.toLowerCase();
    final isPdf = lower.endsWith('.pdf');
    if (!isPdf && !lower.endsWith('.docx')) {
      _showMessage('الصيغ المدعومة هي PDF وDOCX فقط.', isError: true);
      return;
    }

    setState(() {
      _isBusy = true;
      _filePath = null;
      _fileName = null;
      _wordDocument = null;
      _originalPdfPath = null;
      _loadError = null;
    });

    try {
      final file = File(path);
      if (!await file.exists()) throw Exception('الملف المحدد غير موجود.');
      if (await file.length() == 0) throw Exception('الملف المحدد فارغ.');

      PdfControllerPinch? newPdfController;
      FluentDocument? loadedWordDocument;

      if (isPdf) {
        // Open the PDF completely before constructing the viewer controller.
        final openedPdf = await PdfDocument.openFile(path);
        if (openedPdf.pagesCount < 1) {
          throw Exception('ملف PDF لا يحتوي على صفحات قابلة للعرض.');
        }
        newPdfController = PdfControllerPinch(
          document: Future<PdfDocument>.value(openedPdf),
        );
      } else {
        final bytes = await file.readAsBytes();
        final root = ImportDocxService().importFromDocx(bytes);
        if (root.nodes.isEmpty) {
          throw Exception('لم يتم العثور على محتوى قابل للاستيراد داخل مستند Word.');
        }
        loadedWordDocument = FluentDocument()
          ..documentLanguage = 'ar'
          ..load(root.nodes);
        if (loadedWordDocument.content.nodes.isEmpty) {
          throw Exception('تم استيراد ملف Word دون إنشاء محتوى قابل للتحرير.');
        }
      }

      if (!mounted) {
        newPdfController?.dispose();
        loadedWordDocument?.dispose();
        return;
      }

      _pdfController?.dispose();
      setState(() {
        _pdfController = newPdfController;
        _filePath = path;
        _fileName = result.files.single.name;
        _isPdf = isPdf;
        _originalPdfPath = isPdf ? path : null;
        _excelPath = null;
        _wordDocument = loadedWordDocument;
        _loadError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _filePath = null;
          _wordDocument = null;
          _loadError = e.toString();
        });
      }
      _showMessage('تعذر تحميل المستند وعرضه: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _pickExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xlsm'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) throw Exception('تعذر الوصول إلى ملف Excel.');
      if (!mounted) return;
      setState(() => _excelPath = path);
      _showMessage('تم اختيار ملف بيانات الطلاب.');
    } catch (e) {
      _showMessage('تعذر اختيار ملف Excel: $e', isError: true);
    }
  }

  Future<void> _configureStudentPdf() async {
    if (_filePath == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFFFAF8F1),
          title: Text(_isPdf ? 'إضافة بيانات الطلاب إلى PDF' : 'إنشاء نسخ الطلاب من Word'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _subjectController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المادة / ورقة العمل في Excel',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _gradeController,
                  decoration: const InputDecoration(labelText: 'الصف الدراسي'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _examTitleController,
                  decoration: const InputDecoration(labelText: 'اسم الاختبار أو الشهر'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickExcel,
                  icon: const Icon(Icons.table_view),
                  label: Text(
                    _excelPath == null
                        ? 'اختيار ملف Excel للطلاب'
                        : 'تم اختيار ملف Excel',
                  ),
                ),
                if (_excelPath != null)
                  Text(
                    _excelPath!.split(Platform.pathSeparator).last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF52796F)),
                  ),
                const SizedBox(height: 5),
                const Text(
                  'سيتم إنشاء نسخة PDF لكل طالب، وتظهر بياناته ورقم جلوسه ورمز QR وكود المادة في الصفحة الأولى فقط. يبقى ملف Word الأصلي قابلاً للتحرير دون تغيير.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF777568)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('إنشاء نسخ الطلاب'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) await _createStudentPdf();
  }

  Future<void> _createStudentPdf() async {
    final currentPath = _filePath;
    if (currentPath == null) return;

    setState(() => _isBusy = true);
    try {
      String sourcePath;
      if (_isPdf) {
        sourcePath = _originalPdfPath ?? currentPath;
      } else {
        final wordDocument = _wordDocument;
        if (wordDocument == null) throw Exception('مستند Word غير جاهز للتحويل.');
        final wordPdfBytes = await ExportService(wordDocument).exportToPdf();
        final tempDirectory = await getTemporaryDirectory();
        sourcePath = '${tempDirectory.path}/word_source_${DateTime.now().millisecondsSinceEpoch}.pdf';
        await File(sourcePath).writeAsBytes(wordPdfBytes, flush: true);
      }
      StudentExcelResult? excelResult;
      if (_excelPath != null) {
        excelResult = await StudentExcelService.parseExcelFile(
          _excelPath!,
          expectedSubject: _subjectController.text.trim(),
          targetGrade: _gradeController.text.trim(),
          examTitle: _examTitleController.text.trim(),
        );
        if (excelResult.students.isEmpty) {
          throw Exception('لم يتم العثور على طلاب مطابقين للصف والمادة المحددين.');
        }
      }

      final directory = await getTemporaryDirectory();
      final outputName = _buildStudentPdfName();
      final outputPath = '${directory.path}/$outputName';
      final students = excelResult?.students
              .map((student) => <String, String>{
                    'seatNo': student.seatNo,
                    'name': student.name,
                    'secretCode': student.secretCode,
                  })
              .toList() ??
          <Map<String, String>>[];

      final generatedPath = await const MethodChannel(
        'com.fawaz.exam_maker_app/document_pdf',
      ).invokeMethod<String>('createStudentPdf', {
        'sourcePath': sourcePath,
        'outputPath': outputPath,
        'students': students,
        'subjectCode': excelResult?.subjectCode ?? 1,
      });

      if (generatedPath == null || !await File(generatedPath).exists()) {
        throw Exception('لم يتم إنشاء ملف PDF الناتج.');
      }

      final generatedPdf = await PdfDocument.openFile(generatedPath);
      if (generatedPdf.pagesCount < 1) {
        throw Exception('ملف PDF الناتج لا يحتوي على صفحات.');
      }
      _pdfController?.dispose();
      _pdfController = PdfControllerPinch(
        document: Future<PdfDocument>.value(generatedPdf),
      );

      if (!mounted) return;
      setState(() {
        _filePath = generatedPath;
        _fileName = outputName;
        _originalPdfPath = generatedPath;
        _isPdf = true;
        _wordDocument = null;
      });
      _showMessage(
        excelResult == null
            ? 'تم تجهيز صفحات PDF بمقاس A4 مع الاحتفاظ بالمحتوى الأصلي.'
            : 'تم تجهيز ${excelResult.students.length} نسخة باسم $outputName، مع بيانات الطلاب في الصفحة الأولى لكل نسخة.',
      );
    } catch (e) {
      _showMessage('تعذرت معالجة ملف PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String _buildStudentPdfName() {
    String cleanPart(String value) {
      final cleaned = value.trim().replaceAll(RegExp(r'[/:*?"<>|\\]'), '-');
      return cleaned.isEmpty ? 'غير محدد' : cleaned;
    }

    final grade = cleanPart(_gradeController.text);
    final subject = cleanPart(_subjectController.text);
    var period = _examTitleController.text.trim();
    final endIndex = period.indexOf('نهاية');
    if (endIndex >= 0) {
      period = period.substring(endIndex + 'نهاية'.length).trim();
    }
    if (period.isEmpty) period = _examTitleController.text.trim();
    return '${grade}_${subject}_${cleanPart(period)}.pdf';
  }

  Future<void> _saveDocx() async {
    final document = _wordDocument;
    if (_filePath == null || _isPdf || document == null) return;

    setState(() => _isBusy = true);
    try {
      final bytes = await ExportService(document).exportToDocx();
      final baseName = (_fileName ?? 'document.docx')
          .replaceAll(RegExp(r'\.docx$', caseSensitive: false), '');
      final savedPath = await ExportService(document)
          .saveFileNative(bytes, baseName, 'docx');
      if (savedPath == null) {
        _showMessage('لم يتم اختيار مكان لحفظ مستند Word.', isError: true);
      } else {
        _showMessage('تم حفظ المستند المعدّل في: $savedPath');
      }
    } catch (e) {
      _showMessage('تعذر حفظ مستند Word: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }


  Future<void> _savePdfCopy() async {
    final path = _filePath;
    if (path == null || !_isPdf) return;
    setState(() => _isBusy = true);
    try {
      final bytes = await File(path).readAsBytes();
      final saved = await FilePicker.platform.saveFile(
        fileName: _fileName ?? 'document.pdf',
        bytes: bytes,
      );
      if (saved == null) {
        _showMessage('تم إلغاء حفظ الملف.');
      } else {
        _showMessage('تم حفظ ملف PDF.');
      }
    } catch (e) {
      _showMessage('تعذر حفظ ملف PDF: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _printWordAsPdf() async {
    final document = _wordDocument;
    if (document == null || _isPdf) return;
    setState(() => _isBusy = true);
    try {
      final bytes = await ExportService(document).exportToPdf();
      await Printing.layoutPdf(
        name: (_fileName ?? 'document.docx').replaceAll('.docx', '.pdf'),
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      _showMessage('تعذر تحويل مستند Word إلى PDF للطباعة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _printPdf() async {
    final path = _filePath;
    if (path == null || !_isPdf) return;

    setState(() => _isBusy = true);
    try {
      final bytes = await File(path).readAsBytes();
      await Printing.layoutPdf(
        name: _fileName ?? 'document.pdf',
        onLayout: (_) async => bytes,
      );
    } catch (e) {
      _showMessage('تعذرت الطباعة: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red.shade700 : const Color(0xFF52796F),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFile = _filePath != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F0E7),
      appBar: AppBar(
        title: const Text(
          'محرر المستندات',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF52796F),
        actions: [
          if (hasFile && !_isPdf)
            IconButton(
              tooltip: 'إنشاء نسخ PDF للطلاب من Word',
              onPressed: _isBusy ? null : _configureStudentPdf,
              icon: const Icon(Icons.group_add_outlined, color: Colors.white),
            ),
          if (hasFile && !_isPdf)
            IconButton(
              tooltip: 'حفظ تعديلات Word',
              onPressed: _isBusy ? null : _saveDocx,
              icon: const Icon(Icons.save_outlined, color: Colors.white),
            ),
          if (hasFile && !_isPdf)
            IconButton(
              tooltip: 'طباعة Word عبر Wi-Fi',
              onPressed: _isBusy ? null : _printWordAsPdf,
              icon: const Icon(Icons.print_outlined, color: Colors.white),
            ),
          if (hasFile && _isPdf)
            IconButton(
              tooltip: 'إضافة بيانات الطلاب من Excel',
              onPressed: _isBusy ? null : _configureStudentPdf,
              icon: const Icon(Icons.group_add_outlined, color: Colors.white),
            ),
          if (hasFile && _isPdf)
            IconButton(
              tooltip: 'حفظ نسخة PDF',
              onPressed: _isBusy ? null : _savePdfCopy,
              icon: const Icon(Icons.save_alt_outlined, color: Colors.white),
            ),
          if (hasFile && _isPdf)
            IconButton(
              tooltip: 'طباعة عبر Wi-Fi',
              onPressed: _isBusy ? null : _printPdf,
              icon: const Icon(Icons.print_outlined, color: Colors.white),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _pickDocument,
        backgroundColor: const Color(0xFF52796F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.folder_open),
        label: const Text('فتح PDF أو Word'),
      ),
      // Use a bounded Column/Expanded viewport. The previous Stack placed
      // the document surface beside an unconstrained header, which could
      // leave platform viewers with no usable layout height on Android.
      body: Column(
        children: [
          if (hasFile)
            Container(
              width: double.infinity,
              color: const Color(0xFFE5E1D5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(
                _fileName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF344E41),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (!hasFile)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Container(
                        padding: const EdgeInsets.all(26),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFEFA),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFD8D1C1)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x18000000),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: _loadError == null
                            ? const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.description_outlined,
                                      size: 58, color: Color(0xFF52796F)),
                                  SizedBox(height: 14),
                                  Text(
                                    'افتح مستند PDF أو Word',
                                    style: TextStyle(
                                      fontSize: 19,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF344E41),
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'يدعم المحرر ملفات PDF الأصلية ومستندات DOCX القابلة للتحرير.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF6B705C),
                                      height: 1.6,
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 52, color: Colors.redAccent),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'تعذر عرض المستند',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(_loadError!,
                                      textAlign: TextAlign.center),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'يمكنك اختيار الملف مرة أخرى بعد التأكد من سلامته.',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                if (hasFile)
                  _isPdf
                      ? PdfViewPinch(
                          key: ValueKey(_filePath),
                          controller: _pdfController!,
                        )
                      : (_wordDocument == null
                          ? const Center(
                              child: Text(
                                  'تعذر تجهيز مستند Word للتحرير.'))
                          : Directionality(
                              textDirection: TextDirection.rtl,
                              child: FluentEditor(
                                key: ValueKey(_filePath),
                                document: _wordDocument!,
                                labels: const FluentEditorLabels(
                                  file: 'ملف',
                                  save: 'حفظ',
                                  open: 'فتح',
                                  exportAs: 'تصدير باسم',
                                  microsoftWord: 'مستند Word',
                                  pdf: 'ملف PDF',
                                  importDocx: 'استيراد Word',
                                  edit: 'تحرير',
                                  undo: 'تراجع',
                                  redo: 'إعادة',
                                  cut: 'قص',
                                  copy: 'نسخ',
                                  paste: 'لصق',
                                  selectAll: 'تحديد الكل',
                                  delete: 'حذف',
                                  wordCount: 'عدد الكلمات',
                                  characterCount: 'عدد الأحرف',
                                  insert: 'إدراج',
                                  link: 'رابط',
                                  image: 'صورة',
                                  table: 'جدول',
                                  horizontalLine: 'خط أفقي',
                                  settings: 'إعدادات',
                                  showStats: 'إظهار الإحصاءات',
                                  documentLanguage: 'لغة المستند',
                                  format: 'تنسيق',
                                  text: 'نص',
                                  bold: 'غامق',
                                  italic: 'مائل',
                                  underline: 'تسطير',
                                  strikethrough: 'يتوسطه خط',
                                  align: 'محاذاة',
                                  alignLeft: 'محاذاة لليسار',
                                  alignCenter: 'توسيط',
                                  alignRight: 'محاذاة لليمين',
                                  justify: 'ضبط النص',
                                  cancel: 'إلغاء',
                                  confirmButton: 'تأكيد',
                                  insertButton: 'إدراج',
                                  apply: 'تطبيق',
                                  done: 'تم',
                                ),
                              ),
                            )),
                if (_isBusy)
                  const ColoredBox(
                    color: Color(0x55000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';

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
import '../services/excel_file_access_service.dart';
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
  String? _excelName;
  bool _isPdf = true;
  bool _isBusy = false;
  double _cropTopFraction = 0.0;
  double _cropBottomFraction = 0.0;
  bool _cropConfigured = false;
  bool _studentDataOnLastPage = false;
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
      _cropTopFraction = 0.0;
      _cropBottomFraction = 0.0;
      _cropConfigured = false;
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
    if (mounted && _filePath == path) {
      await _showOriginalCropForImportedFile();
    }
  }

  Future<String> _prepareSourcePdfPath() async {
    final currentPath = _filePath;
    if (currentPath == null) throw Exception('لم يتم استيراد ملف اختبار.');
    if (_isPdf) return _originalPdfPath ?? currentPath;
    final wordDocument = _wordDocument;
    if (wordDocument == null) throw Exception('مستند Word غير جاهز للتحويل.');
    final wordPdfBytes = await ExportService(wordDocument).exportToPdf();
    final tempDirectory = await getTemporaryDirectory();
    final sourcePath = '${tempDirectory.path}/word_source_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await File(sourcePath).writeAsBytes(wordPdfBytes, flush: true);
    return sourcePath;
  }

  Future<void> _showOriginalCropForImportedFile() async {
    try {
      final sourcePath = await _prepareSourcePdfPath();
      if (!mounted) return;
      final crop = await showDialog<Map<String, double>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OriginalPageCropDialog(pdfPath: sourcePath),
      );
      if (!mounted || crop == null) return;
      setState(() {
        _cropTopFraction = crop['top'] ?? 0.0;
        _cropBottomFraction = crop['bottom'] ?? 0.0;
        _cropConfigured = true;
      });
      _showMessage(
        (_cropTopFraction == 0 && _cropBottomFraction == 0)
            ? 'تم اعتماد الصفحة الأولى كاملة دون قص.'
            : 'تم حفظ حدود القص للصفحة الأولى.',
      );
    } catch (e) {
      _showMessage('تعذر فتح أداة قص الصفحة الأولى: $e', isError: true);
    }
  }

  Future<void> _configureStudentPdf() async {
    if (_filePath == null) return;

    String? selectedExcelPath = _excelPath;
    String? selectedExcelName = _excelName;
    String? selectedSubject;
    String? selectedGrade;
    String? selectedPeriod;
    List<String> subjects = [];
    List<String> grades = [];
    List<String> periods = [];
    bool loading = false;
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> chooseExcel() async {
            try {
              final selected = await ExcelFileAccessService.pickExcelDocument();
              if (selected == null) return;
              final path = selected.reference;

              setDialogState(() {
                loading = true;
                error = null;
                selectedExcelPath = path;
                selectedExcelName = selected.name;
                selectedSubject = null;
                selectedGrade = null;
                selectedPeriod = null;
                subjects = [];
                grades = [];
                periods = [];
              });

              final loadedSubjects =
                  await StudentExcelService.getSubjectSheetNames(path);
              if (loadedSubjects.isEmpty) {
                throw Exception(
                  'لم يُعثر على أوراق مواد تحتوي على كشف الطلاب المتوقع.',
                );
              }
              setDialogState(() => subjects = loadedSubjects);
            } catch (e) {
              setDialogState(() => error = 'تعذر قراءة ملف Excel: $e');
            } finally {
              setDialogState(() => loading = false);
            }
          }

          Future<void> selectSubject(String? value) async {
            if (value == null || selectedExcelPath == null) return;
            setDialogState(() {
              loading = true;
              error = null;
              selectedSubject = value;
              selectedGrade = null;
              selectedPeriod = null;
              grades = [];
              periods = [];
            });
            try {
              final options = await StudentExcelService.getSheetOptions(
                selectedExcelPath!,
                value,
              );
              if (options.grades.isEmpty) {
                throw Exception('لم تُوجد صفوف دراسية في العمود C.');
              }
              if (options.periods.isEmpty) {
                throw Exception('لم تُوجد أسماء أشهر أو فصول دراسية في ورقة المادة.');
              }
              setDialogState(() {
                grades = options.grades;
                periods = options.periods;
              });
            } catch (e) {
              setDialogState(() => error = 'تعذر قراءة بيانات ورقة المادة: $e');
            } finally {
              setDialogState(() => loading = false);
            }
          }

          Widget dropdown({
            required String label,
            required String? value,
            required List<String> items,
            required ValueChanged<String?>? onChanged,
          }) {
            return DropdownButtonFormField<String>(
              value: value,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
              ),
              items: items
                  .map((item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(item, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: loading ? null : onChanged,
            );
          }

          return Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              backgroundColor: const Color(0xFFFAF8F1),
              title: Text(
                _isPdf
                    ? 'إضافة بيانات الطلاب إلى PDF'
                    : 'إنشاء نسخ الطلاب من Word',
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: loading ? null : chooseExcel,
                          icon: const Icon(Icons.table_view),
                          label: Text(
                            selectedExcelPath == null
                                ? '١ - اختيار ملف Excel'
                                : 'تم اختيار ملف Excel',
                          ),
                        ),
                      ),
                      if (selectedExcelPath != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          selectedExcelName ?? selectedExcelPath!.split(Platform.pathSeparator).last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF52796F),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      dropdown(
                        label: '٢ - المادة / ورقة العمل',
                        value: selectedSubject,
                        items: subjects,
                        onChanged: selectedExcelPath == null
                            ? null
                            : selectSubject,
                      ),
                      const SizedBox(height: 12),
                      dropdown(
                        label: '٣ - الصف الدراسي',
                        value: selectedGrade,
                        items: grades,
                        onChanged: selectedSubject == null
                            ? null
                            : (value) => setDialogState(
                                  () => selectedGrade = value,
                                ),
                      ),
                      const SizedBox(height: 12),
                      dropdown(
                        label: '٤ - الشهر أو الفصل الدراسي',
                        value: selectedPeriod,
                        items: periods,
                        onChanged: selectedSubject == null
                            ? null
                            : (value) => setDialogState(
                                  () => selectedPeriod = value,
                                ),
                      ),
                      const SizedBox(height: 14),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '٥ - موضع بيانات الطالب بحسب نوع الاختبار',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ),
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: false,
                        groupValue: _studentDataOnLastPage,
                        onChanged: loading
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(
                                    () => _studentDataOnLastPage = value,
                                  );
                                }
                              },
                        title: const Text('اختبار شامل أو عادي'),
                        subtitle: const Text(
                          'تظهر بيانات الطالب في الصفحة الأولى.',
                        ),
                      ),
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: true,
                        groupValue: _studentDataOnLastPage,
                        onChanged: loading
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(
                                    () => _studentDataOnLastPage = value,
                                  );
                                }
                              },
                        title: const Text('اختبار أتمتة'),
                        subtitle: const Text(
                          'تظهر بيانات الطالب في الصفحة الأخيرة (ورقة التظليل).',
                        ),
                      ),
                      if (loading) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                        const SizedBox(height: 6),
                        const Text('جارٍ قراءة بيانات ملف Excel...'),
                      ],
                      if (error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        _studentDataOnLastPage
                            ? 'ستظهر بيانات الطالب ورقم جلوسه ورمز QR وكود المادة في الصفحة الأخيرة فقط.'
                            : 'ستظهر بيانات الطالب ورقم جلوسه ورمز QR وكود المادة في الصفحة الأولى فقط.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF777568),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: loading ||
                          selectedExcelPath == null ||
                          selectedSubject == null ||
                          selectedGrade == null ||
                          selectedPeriod == null
                      ? null
                      : () {
                          setState(() {
                            _excelPath = selectedExcelPath;
                            _subjectController.text = selectedSubject!;
                            _gradeController.text = selectedGrade!;
                            _examTitleController.text = selectedPeriod!;
                          });
                          Navigator.pop(dialogContext, true);
                        },
                  child: const Text('إنشاء نسخ الطلاب'),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed == true) await _createStudentPdf();
  }

  Future<void> _createStudentPdf() async {
    final currentPath = _filePath;
    if (currentPath == null) return;

    setState(() => _isBusy = true);
    try {
      final sourcePath = await _prepareSourcePdfPath();
      if (!mounted) return;

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
        'studentDataOnLastPage': _studentDataOnLastPage,
        'cropTopFraction': _cropConfigured ? _cropTopFraction : 0.0,
        'cropBottomFraction': _cropConfigured ? _cropBottomFraction : 0.0,
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
            : 'تم تجهيز ${excelResult.students.length} نسخة باسم $outputName، مع بيانات الطلاب في ${_studentDataOnLastPage ? 'الصفحة الأخيرة' : 'الصفحة الأولى'} لكل نسخة.',
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

/// نافذة قص اختيارية للورقة الأصلية. الخطان يحددان الجزء الذي سيبقى،
/// ويمكن سحبهما بحرية من أعلى الصفحة وأسفلها.
class _OriginalPageCropDialog extends StatefulWidget {
  final String pdfPath;

  const _OriginalPageCropDialog({required this.pdfPath});

  @override
  State<_OriginalPageCropDialog> createState() => _OriginalPageCropDialogState();
}

class _OriginalPageCropDialogState extends State<_OriginalPageCropDialog> {
  Uint8List? _previewBytes;
  double _aspectRatio = 210 / 297;
  double _top = 0.0;
  double _bottom = 1.0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    PdfDocument? document;
    PdfPage? page;
    try {
      document = await PdfDocument.openFile(widget.pdfPath);
      if (document.pagesCount < 1) {
        throw Exception('ملف PDF لا يحتوي على صفحات.');
      }
      page = await document.getPage(1);
      final aspect = page.width / page.height;
      final rendered = await page.render(
        width: 1000,
        height: 1000 / aspect,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      if (rendered == null || rendered.bytes.isEmpty) {
        throw Exception('تعذرت معاينة الصفحة الأولى.');
      }
      final bytes = rendered.bytes;
      await page.close();
      page = null;
      await document.close();
      document = null;
      if (!mounted) return;
      setState(() {
        _previewBytes = bytes;
        _aspectRatio = aspect;
        _loading = false;
      });
    } catch (e) {
      if (page != null && !page.isClosed) await page.close();
      if (document != null) await document.close();
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _moveTop(double delta, double height) {
    if (height <= 0) return;
    setState(() {
      _top = (_top + delta / height).clamp(0.0, _bottom - 0.01).toDouble();
    });
  }

  void _moveBottom(double delta, double height) {
    if (height <= 0) return;
    setState(() {
      _bottom = (_bottom + delta / height).clamp(_top + 0.01, 1.0).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('قص الورقة الأصلية (اختياري)'),
        content: SizedBox(
          width: 420,
          child: _loading
              ? const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                )
              : _error != null
                  ? Text('تعذرت معاينة الصفحة: $_error')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'اسحب الخط الأخضر لتحديد بداية الجزء المحتفظ به، '
                          'والخط البرتقالي لتحديد نهايته. يمكنك ترك الصفحة كاملة دون قص.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = constraints.maxWidth;
                            final height =
                                (width / _aspectRatio).clamp(180.0, 430.0).toDouble();
                            return SizedBox(
                              width: width,
                              height: height,
                              child: ClipRect(
                                child: Stack(
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    Positioned.fill(
                                      child: Image.memory(
                                        _previewBytes!,
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                    Positioned(
                                      top: (_top * height - 13).clamp(0.0, height - 26).toDouble(),
                                      left: 0,
                                      right: 0,
                                      height: 26,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onVerticalDragUpdate: (details) =>
                                            _moveTop(details.delta.dy, height),
                                        child: Center(
                                          child: Container(
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade700,
                                              boxShadow: const [
                                                BoxShadow(color: Colors.white, blurRadius: 3),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: (_bottom * height - 13).clamp(0.0, height - 26).toDouble(),
                                      left: 0,
                                      right: 0,
                                      height: 26,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onVerticalDragUpdate: (details) =>
                                            _moveBottom(details.delta.dy, height),
                                        child: Center(
                                          child: Container(
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: Colors.deepOrange.shade700,
                                              boxShadow: const [
                                                BoxShadow(color: Colors.white, blurRadius: 3),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'الجزء الواقع بين الخطين هو الذي سيبقى في ملف الاختبار.',
                          style: TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                    ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, <String, double>{
              'top': 0.0,
              'bottom': 0.0,
            }),
            child: const Text('متابعة دون قص'),
          ),
          FilledButton(
            onPressed: _loading || _previewBytes == null || _error != null
                ? null
                : () => Navigator.pop(context, <String, double>{
                      'top': _top,
                      'bottom': 1.0 - _bottom,
                    }),
            child: const Text('اعتماد القص'),
          ),
        ],
      ),
    );
  }
}


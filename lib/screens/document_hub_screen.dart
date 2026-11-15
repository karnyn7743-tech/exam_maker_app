import 'dart:io';

import 'package:docx_viewer_plus/docx_viewer_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
  bool _isPdf = true;
  bool _isBusy = false;
  PdfControllerPinch? _pdfController;
  final GlobalKey<DocxViewerWidgetState> _docxKey =
      GlobalKey<DocxViewerWidgetState>();

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'docx'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final path = result.files.single.path;
      if (path == null || path.trim().isEmpty) {
        throw Exception('تعذر الوصول إلى الملف المحدد.');
      }

      final lower = path.toLowerCase();
      final isPdf = lower.endsWith('.pdf');
      if (!isPdf && !lower.endsWith('.docx')) {
        throw Exception('الصيغ المدعومة هي PDF وDOCX فقط.');
      }

      final file = File(path);
      if (!await file.exists()) throw Exception('الملف غير موجود.');

      _pdfController?.dispose();
      _pdfController = null;

      if (isPdf) {
        _pdfController = PdfControllerPinch(
          document: PdfDocument.openFile(path),
        );
      }

      if (!mounted) return;
      setState(() {
        _filePath = path;
        _fileName = result.files.single.name;
        _isPdf = isPdf;
      });
    } catch (e) {
      _showMessage('تعذر فتح المستند: $e', isError: true);
    }
  }

  Future<void> _saveDocx() async {
    final path = _filePath;
    if (path == null || _isPdf) return;

    setState(() => _isBusy = true);
    try {
      final savedPath = await _docxKey.currentState?.save(
        outputPath: path,
      );
      if (savedPath == null) {
        throw Exception('لم يتمكن محرر Word من حفظ المستند.');
      }
      _showMessage('تم حفظ تعديلات مستند Word.');
    } catch (e) {
      _showMessage('تعذر حفظ مستند Word: $e', isError: true);
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
              tooltip: 'حفظ تعديلات Word',
              onPressed: _isBusy ? null : _saveDocx,
              icon: const Icon(Icons.save_outlined, color: Colors.white),
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
      body: Stack(
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
                  child: const Column(
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
                  ),
                ),
              ),
            )
          else ...[
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
            Positioned.fill(
              top: 42,
              child: _isPdf
                  ? PdfViewPinch(
                      key: ValueKey(_filePath),
                      controller: _pdfController!,
                    )
                  : DocxViewerWidget(
                      key: _docxKey,
                      filePath: _filePath!,
                      config: DocxViewerConfig(
                        toolbarPosition: ToolbarPosition.bottom,
                        forceTextDirection: TextDirection.rtl,
                        strings: DocxViewerStrings.arabic,
                      ),
                    ),
            ),
          ],
          if (_isBusy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x55000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

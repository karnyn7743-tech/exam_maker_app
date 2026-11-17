import 'package:flutter/material.dart';
import 'package:fluent_editor/factories.dart';
import 'package:fluent_editor/fluent_document.dart';
import 'package:fluent_editor/utils/handler_helpers.dart';
import '../utils/app_font_catalog.dart';

/// اختيار الخط في المحرر الغني. يطبق على التحديد الحالي أو يحدد خط الكتابة التالية.
class RichFontSelector extends StatelessWidget {
  final FluentDocument document;
  const RichFontSelector({super.key, required this.document});

  void _apply(String family) {
    applyStyleProperty<String>(
      document,
      family,
      description: 'Change font family',
      modifyLeaf: (leaf, value) => leaf.fontFamily = value,
      setPending: (doc, value) => doc.pendingFontFamily = value,
    );
    document.requestEditorFocus();
  }

  @override
  Widget build(BuildContext context) {
    final selected = appFontsList.any((f) => f['id'] == document.pendingFontFamily)
        ? document.pendingFontFamily
        : 'Amiri';
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD5DCE7)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.font_download_outlined, size: 19, color: Color(0xFF1E3A8A)),
          const SizedBox(width: 5),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selected,
              isDense: true,
              hint: const Text('نوع الخط'),
              items: appFontsList.map((font) => DropdownMenuItem<String>(
                value: font['id'],
                child: Text(font['name']!, style: TextStyle(fontFamily: font['id'], fontSize: 13)),
              )).toList(),
              onChanged: (value) { if (value != null) _apply(value); },
            ),
          ),
        ],
      ),
    );
  }
}

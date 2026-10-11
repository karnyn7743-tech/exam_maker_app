import 'package:flutter/material.dart';

enum KeyboardMode {
  arabic,
  english,
  mathArabic,
  mathEnglish,
  symbols,
}

class ExamCustomKeyboard extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onClose;

  const ExamCustomKeyboard({
    super.key,
    required this.controller,
    this.onClose,
  });

  @override
  State<ExamCustomKeyboard> createState() => _ExamCustomKeyboardState();
}

class _ExamCustomKeyboardState extends State<ExamCustomKeyboard> {
  KeyboardMode _mode = KeyboardMode.arabic;
  bool _isShift = false;

  void _insertText(String text) {
    final c = widget.controller;
    final selection = c.selection;
    final currentText = c.text;

    if (!selection.isValid || selection.isCollapsed) {
      final pos = selection.isValid ? selection.start : currentText.length;
      final newText = currentText.substring(0, pos) + text + currentText.substring(pos);
      c.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: pos + text.length),
      );
    } else {
      final newText = currentText.replaceRange(selection.start, selection.end, text);
      c.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + text.length),
      );
    }
  }

  void _backspace() {
    final c = widget.controller;
    final selection = c.selection;
    final currentText = c.text;

    if (!selection.isValid || (selection.isCollapsed && selection.start == 0)) {
      return;
    }

    if (!selection.isCollapsed) {
      final newText = currentText.replaceRange(selection.start, selection.end, '');
      c.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    } else {
      final pos = selection.start;
      final newText = currentText.substring(0, pos - 1) + currentText.substring(pos);
      c.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: pos - 1),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // إجبار لوحة المفاتيح بالكامل على اتجاه LTR لمنع قلب المفاتيح 180 درجة
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF1E293B),
        padding: const EdgeInsets.only(top: 4, bottom: 6, left: 4, right: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTopBar(),
            const SizedBox(height: 4),
            _buildActiveLayout(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildModeTab('عربي', KeyboardMode.arabic),
          _buildModeTab('English', KeyboardMode.english),
          _buildModeTab('رياضيات ع', KeyboardMode.mathArabic),
          _buildModeTab('Math EN', KeyboardMode.mathEnglish),
          _buildModeTab('رموز وأسس', KeyboardMode.symbols),
          if (widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.keyboard_hide, color: Colors.white70, size: 20),
              onPressed: widget.onClose,
            ),
        ],
      ),
    );
  }

  Widget _buildModeTab(String title, KeyboardMode mode) {
    final isSelected = _mode == mode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ChoiceChip(
        label: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
        selected: isSelected,
        selectedColor: const Color(0xFF2563EB),
        backgroundColor: Colors.grey.shade300,
        visualDensity: VisualDensity.compact,
        onSelected: (val) {
          if (val) setState(() => _mode = mode);
        },
      ),
    );
  }

  Widget _buildActiveLayout() {
    switch (_mode) {
      case KeyboardMode.arabic:
        return _buildArabicLayout();
      case KeyboardMode.english:
        return _buildEnglishLayout();
      case KeyboardMode.mathArabic:
        return _buildMathArabicLayout();
      case KeyboardMode.mathEnglish:
        return _buildMathEnglishLayout();
      case KeyboardMode.symbols:
        return _buildSymbolsLayout();
    }
  }

  // 1. لوحة الحروف والأرقام العربية مرتبة قياسياً
  Widget _buildArabicLayout() {
    final rows = [
      ['١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩', '٠'],
      ['د', 'ج', 'ح', 'خ', 'ه', 'ع', 'غ', 'ف', 'ق', 'ث', 'ص', 'ض'],
      ['ط', 'ك', 'م', 'ن', 'ت', 'ا', 'ل', 'ب', 'ي', 'س', 'ش'],
      ['ذ', 'ظ', 'ز', 'و', 'ة', 'ى', 'لا', 'ر', 'ؤ', 'ء', 'ئ'],
    ];

    return Column(
      children: [
        ...rows.map((row) => _buildRow(row)),
        _buildBottomControlRow(),
      ],
    );
  }

  // 2. لوحة الحروف والأرقام الإنجليزية QWERTY
  Widget _buildEnglishLayout() {
    final nums = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
    final r1 = ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'];
    final r2 = ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'];
    final r3 = ['z', 'x', 'c', 'v', 'b', 'n', 'm'];

    List<String> mapShift(List<String> list) =>
        _isShift ? list.map((e) => e.toUpperCase()).toList() : list;

    return Column(
      children: [
        _buildRow(nums),
        _buildRow(mapShift(r1)),
        _buildRow(mapShift(r2)),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSpecialKey(
              icon: Icons.arrow_upward,
              color: _isShift ? Colors.blue : Colors.blueGrey.shade800,
              onTap: () => setState(() => _isShift = !_isShift),
            ),
            ...mapShift(r3).map((k) => _buildKey(k)),
            _buildSpecialKey(
              icon: Icons.backspace_outlined,
              color: Colors.red.shade900,
              onTap: _backspace,
            ),
          ],
        ),
        _buildBottomControlRow(excludeBackspace: true),
      ],
    );
  }

  // 3. لوحة الرياضيات العربية
  Widget _buildMathArabicLayout() {
    final rows = [
      ['س', 'ص', 'ع', 'د', 'ن', 'ل', 'ك', 'ق', 'ط', 'هـ'],
      ['نهـا', 'مجـ', 'جا', 'جتا', 'ظا', 'ظتا', 'قا', 'قتا', 'لو', '∆'],
      ['⎷', '½', '¼', '¾', 'س²', 'ص²', 'س³', 'ص³', 'ـ', '(   )'],
      ['+', '-', '×', '÷', '=', '≠', '≈', '<', '>', '±'],
    ];

    return Column(
      children: [
        ...rows.map((row) => _buildRow(row)),
        _buildBottomControlRow(),
      ],
    );
  }

  // 4. لوحة الرياضيات الإنجليزية
  Widget _buildMathEnglishLayout() {
    final rows = [
      ['x', 'y', 'z', 'a', 'b', 'c', 'f(x)', 'lim', 'log', 'ln'],
      ['sin', 'cos', 'tan', 'π', 'θ', 'α', 'β', 'λ', 'μ', 'Δ'],
      ['√', '∫', '∑', '∞', 'x²', 'y²', 'xⁿ', '(', ')', '[   ]'],
      ['+', '-', '×', '÷', '=', '≠', '≤', '≥', '±', '%'],
    ];

    return Column(
      children: [
        ...rows.map((row) => _buildRow(row)),
        _buildBottomControlRow(),
      ],
    );
  }

  // 5. لوحة الأسس والصيغ الكيميائية
  Widget _buildSymbolsLayout() {
    final rows = [
      ['⁰', '¹', '²', '³', '⁴', '⁵', '⁶', '⁷', '⁸', '⁹'],
      ['₀', '₁', '₂', '₃', '₄', '₅', '₆', '₇', '₈', '₉'],
      ['∈', '∉', '⊂', '⊄', '∪', '∩', '∅', '←', '→', '↔'],
      ['✔', '✘', '°', '·', ':', '؟', '!', '"', '«', '»'],
    ];

    return Column(
      children: [
        ...rows.map((row) => _buildRow(row)),
        _buildBottomControlRow(),
      ],
    );
  }

  Widget _buildRow(List<String> keys) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys.map((k) => _buildKey(k)).toList(),
      ),
    );
  }

  Widget _buildKey(String label) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: InkWell(
          onTap: () => _insertText(label),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF334155),
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 1),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpecialKey({
    IconData? icon,
    String? label,
    required Color color,
    required VoidCallback onTap,
    int flex = 1,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: icon != null
                ? Icon(icon, color: Colors.white, size: 18)
                : Text(
                    label ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControlRow({bool excludeBackspace = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          _buildSpecialKey(
            label: 'Enter ↵',
            color: const Color(0xFF0F766E),
            onTap: () => _insertText('\n'),
            flex: 2,
          ),
          _buildSpecialKey(
            label: 'مسافة Space',
            color: const Color(0xFF475569),
            onTap: () => _insertText(' '),
            flex: 5,
          ),
          if (!excludeBackspace)
            _buildSpecialKey(
              icon: Icons.backspace_outlined,
              color: Colors.red.shade900,
              onTap: _backspace,
              flex: 2,
            ),
        ],
      ),
    );
  }
}

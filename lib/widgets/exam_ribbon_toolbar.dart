import 'package:flutter/material.dart';
import '../utils/app_font_catalog.dart';

enum RibbonTab {
  home,       // الرئيسية
  format,     // تنسيق
  insert,     // إدراج
  math,       // رياضيات
  layout,     // تخطيط
  view,       // عرض
}

class ExamRibbonToolbar extends StatefulWidget {
  final bool isBold;
  final bool isUnderline;
  final TextAlign currentAlignment;
  final String currentColor;
  final String currentFont;
  final double currentFontSize;
  final bool isArabicInput;

  // خصائص التحكم في إظهار الإعدادات، التحديد، الحافظة، تباعد الأسطر، والتكبير
  final bool showQuestionSettings;
  final VoidCallback onToggleQuestionSettings;
  final bool isTextSelected;
  final bool hasClipboardContent;
  final double currentLineSpacing;
  final double currentZoom;

  final VoidCallback? onToggleBold;
  final VoidCallback? onToggleUnderline;
  final Function(TextAlign)? onAlignmentChanged;
  final Function(String)? onColorChanged;
  final Function(String)? onFontChanged;
  final Function(double)? onFontSizeChanged;
  final VoidCallback? onToggleInputLanguage;

  final VoidCallback? onCopy;
  final VoidCallback? onPaste;
  final VoidCallback? onCut;
  final VoidCallback? onShare;
  final VoidCallback? onSelectAll;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onOpenQuestionBank;

  final VoidCallback? onInsertImage;
  final VoidCallback? onInsertDottedLine;
  final VoidCallback? onInsertPageBreak;
  final VoidCallback? onInsertTextBox;

  final VoidCallback? onInsertFraction;
  final VoidCallback? onInsertRadical;
  final VoidCallback? onInsertEquation;
  final VoidCallback? onInsertVerticalMath;
  final VoidCallback? onInsertLongDivision;
  final VoidCallback? onOpenSymbolsModal;

  final VoidCallback? onOpenTableDesigner;
  final Function(String kind)? onInsertShape;
  
  final Function(double)? onLineSpacingChanged;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;
  final VoidCallback? onFitScreen;

  const ExamRibbonToolbar({
    super.key,
    required this.isBold,
    required this.isUnderline,
    required this.currentAlignment,
    required this.currentColor,
    required this.currentFont,
    required this.currentFontSize,
    required this.isArabicInput,
    required this.showQuestionSettings,
    required this.onToggleQuestionSettings,
    required this.isTextSelected,
    required this.hasClipboardContent,
    required this.currentLineSpacing,
    required this.currentZoom,
    required this.onToggleBold,
    required this.onToggleUnderline,
    required this.onAlignmentChanged,
    required this.onColorChanged,
    required this.onFontChanged,
    required this.onFontSizeChanged,
    required this.onToggleInputLanguage,
    required this.onCopy,
    required this.onPaste,
    required this.onCut,
    required this.onShare,
    required this.onSelectAll,
    required this.onDeleteSelected,
    required this.onOpenQuestionBank,
    required this.onInsertImage,
    required this.onInsertDottedLine,
    required this.onInsertPageBreak,
    required this.onInsertTextBox,
    required this.onInsertFraction,
    required this.onInsertRadical,
    required this.onInsertEquation,
    required this.onInsertVerticalMath,
    required this.onInsertLongDivision,
    required this.onOpenSymbolsModal,
    required this.onOpenTableDesigner,
    required this.onInsertShape,
    required this.onLineSpacingChanged,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFitScreen,
  });

  @override
  State<ExamRibbonToolbar> createState() => _ExamRibbonToolbarState();
}

class _ExamRibbonToolbarState extends State<ExamRibbonToolbar> {
  RibbonTab _activeTab = RibbonTab.format;
  bool _isExpanded = true;

  String _t(String arabic, String english) =>
      widget.isArabicInput ? arabic : english;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: widget.isArabicInput ? TextDirection.rtl : TextDirection.ltr,
      child: Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFCBD5E1), width: 1)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: const Color(0xFF334155),
                  ),
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                ),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _buildTabButton(_t('الرئيسية', 'Home'), RibbonTab.home),
                      _buildTabButton(_t('تنسيق', 'Format'), RibbonTab.format),
                      _buildTabButton(_t('إدراج', 'Insert'), RibbonTab.insert),
                      _buildTabButton(_t('رياضيات', 'Math'), RibbonTab.math),
                      _buildTabButton(_t('تخطيط', 'Layout'), RibbonTab.layout),
                      _buildTabButton(_t('عرض', 'View'), RibbonTab.view),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_isExpanded)
            Container(
              height: 108,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: Colors.white,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [_buildTabContent()],
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _buildTabButton(String title, RibbonTab tab) {
    final bool isSelected = _activeTab == tab;
    return InkWell(
      onTap: () => setState(() { _activeTab = tab; _isExpanded = true; }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE2E8F0) : Colors.transparent,
          border: isSelected ? const Border(bottom: BorderSide(color: Color(0xFF1E3A8A), width: 2.5)) : null,
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case RibbonTab.home: return _buildHomeTab();
      case RibbonTab.format: return _buildFormatTab();
      case RibbonTab.insert: return _buildInsertTab();
      case RibbonTab.math: return _buildMathTab();
      case RibbonTab.layout: return _buildLayoutTab();
      case RibbonTab.view: return _buildViewTab();
    }
  }

  Widget _buildRibbonGroup({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(child: Center(child: child)),
          const SizedBox(height: 2),
          Text(title, style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildToolItem({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool isSelected = false,
    Color? color,
  }) {
    final bool isEnabled = onTap != null;
    final Color effectiveColor = isSelected ? const Color(0xFF1E3A8A) : (color ?? (isEnabled ? const Color(0xFF334155) : const Color(0xFFCBD5E1)));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFDBEAFE) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: effectiveColor),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: effectiveColor,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    return Row(
      children: [
        _buildRibbonGroup(
          title: _t('الحافظة', 'Clipboard'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.content_cut, label: _t('قص', 'Cut'), onTap: widget.isTextSelected ? widget.onCut : null),
              _buildToolItem(icon: Icons.copy_outlined, label: _t('نسخ', 'Copy'), onTap: widget.isTextSelected ? widget.onCopy : null),
              _buildToolItem(icon: Icons.paste_outlined, label: _t('لصق', 'Paste'), onTap: widget.hasClipboardContent ? widget.onPaste : null),
              _buildToolItem(icon: Icons.share_outlined, label: _t('مشاركة', 'Share'), onTap: widget.isTextSelected ? widget.onShare : null),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: _t('تحديد', 'Selection'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.select_all, label: _t('تحديد الكل', 'Select all'), onTap: widget.onSelectAll),
              _buildToolItem(icon: Icons.delete_sweep_outlined, label: _t('حذف المحدد', 'Delete selection'), onTap: widget.onDeleteSelected),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: _t('بنك الأسئلة', 'Question bank'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.account_balance, label: _t('بنك الأسئلة', 'Question bank'), onTap: widget.onOpenQuestionBank, color: const Color(0xFF1E3A8A)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormatTab() {
    final double clampedCurrentSize = widget.currentFontSize.clamp(8.0, 36.0).toDouble();
    return Row(
      children: [
        _buildRibbonGroup(
          title: _t('السؤال', 'Question'),
          child: Row(
            children: [
              _buildToolItem(
                icon: Icons.tune,
                label: _t('إعدادات السؤال', 'Question settings'),
                isSelected: widget.showQuestionSettings,
                color: const Color(0xFF1E3A8A),
                onTap: widget.onToggleQuestionSettings,
              ),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: _t('نوع الخط', 'Font family'),
          child: Row(
            children: [
              PopupMenuButton<String>(
                tooltip: _t('نوع الخط', 'Font family'),
                onSelected: widget.onFontChanged,
                itemBuilder: (ctx) => appFontsList.map((f) => PopupMenuItem(
                  value: f['id']!,
                  child: Text(f['name']!, style: TextStyle(fontFamily: f['id']!, fontSize: 13)),
                )).toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.text_fields, size: 20, color: Color(0xFF334155)),
                      const SizedBox(height: 2),
                      Text(widget.currentFont, style: const TextStyle(fontSize: 10, color: Color(0xFF334155))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: _t('الخط', 'Font style'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.format_bold, label: _t('عريض', 'Bold'), isSelected: widget.isBold, onTap: widget.onToggleBold),
              _buildToolItem(icon: Icons.format_underlined, label: _t('تسطير', 'Underline'), isSelected: widget.isUnderline, onTap: widget.onToggleUnderline),
              _buildToolItem(
                icon: Icons.text_increase,
                label: _t('تكبير', 'Increase'),
                onTap: () => widget.onFontSizeChanged?.call((clampedCurrentSize + 1).clamp(8.0, 36.0).toDouble()),
              ),
              _buildToolItem(
                icon: Icons.text_decrease,
                label: _t('تصغير', 'Decrease'),
                onTap: () => widget.onFontSizeChanged?.call((clampedCurrentSize - 1).clamp(8.0, 36.0).toDouble()),
              ),
              PopupMenuButton<double>(
                tooltip: _t('اختيار حجم الخط (8–36)', 'Choose font size (8–36)'),
                onSelected: (size) => widget.onFontSizeChanged?.call(size.clamp(8.0, 36.0).toDouble()),
                itemBuilder: (ctx) => List<PopupMenuEntry<double>>.generate(
                  29,
                  (index) {
                    final size = (index + 8).toDouble();
                    return PopupMenuItem<double>(
                      value: size,
                      child: Text('${size.toInt()}', textAlign: TextAlign.center),
                    );
                  },
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.format_size, size: 20, color: Color(0xFF334155)),
                      const SizedBox(height: 2),
                      Text(
                        clampedCurrentSize.toStringAsFixed(
                          clampedCurrentSize == clampedCurrentSize.roundToDouble() ? 0 : 1,
                        ),
                        style: const TextStyle(fontSize: 10, color: Color(0xFF334155)),
                      ),
                    ],
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: _t('لون النص', 'Text color'),
                onSelected: widget.onColorChanged,
                itemBuilder: (ctx) => [
                  {'name': _t('أسود', 'Black'), 'hex': '#000000'}, {'name': _t('أحمر', 'Red'), 'hex': '#B91C1C'},
                  {'name': _t('أزرق', 'Blue'), 'hex': '#1D4ED8'}, {'name': _t('أخضر', 'Green'), 'hex': '#047857'},
                ].map((c) => PopupMenuItem(
                  value: c['hex'],
                  child: Row(children: [
                    Container(width: 14, height: 14, color: Color(int.parse(c['hex']!.replaceFirst('#', '0xFF')))),
                    const SizedBox(width: 6), Text(c['name']!),
                  ]),
                )).toList(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.palette, size: 20, color: Color(int.parse(widget.currentColor.replaceFirst('#', '0xFF')))),
                      const SizedBox(height: 2),
                      const Text(_t('لون', 'Color'), style: TextStyle(fontSize: 10, color: Color(0xFF334155))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: _t('المحاذاة والاتجاه', 'Alignment and direction'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.format_align_right, label: _t('يمين', 'Right'), isSelected: widget.currentAlignment == TextAlign.right, onTap: () => widget.onAlignmentChanged?.call(TextAlign.right)),
              _buildToolItem(icon: Icons.format_align_center, label: _t('وسط', 'Center'), isSelected: widget.currentAlignment == TextAlign.center, onTap: () => widget.onAlignmentChanged?.call(TextAlign.center)),
              _buildToolItem(icon: Icons.format_align_left, label: _t('يسار', 'Left'), isSelected: widget.currentAlignment == TextAlign.left, onTap: () => widget.onAlignmentChanged?.call(TextAlign.left)),
              _buildToolItem(icon: Icons.language, label: widget.isArabicInput ? 'كتابة: ع' : 'Input: En', isSelected: !widget.isArabicInput, color: widget.isArabicInput ? const Color(0xFF0F766E) : const Color(0xFFD97706), onTap: widget.onToggleInputLanguage),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInsertTab() {
    return Row(
      children: [
        _buildRibbonGroup(
          title: _t('عناصر', 'Elements'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.image_outlined, label: _t('صورة', 'Image'), onTap: widget.onInsertImage),
              _buildToolItem(icon: Icons.table_chart_outlined, label: _t('جدول', 'Table'), onTap: widget.onOpenTableDesigner),
              _buildToolItem(icon: Icons.border_horizontal, label: _t('خط إجابة', 'Answer line'), onTap: widget.onInsertDottedLine),
              _buildToolItem(icon: Icons.edit_note, label: _t('مربع إرشاد', 'Text box'), onTap: widget.onInsertTextBox),
              _buildToolItem(icon: Icons.note_add_outlined, label: _t('صفحة جديدة', 'New page'), onTap: widget.onInsertPageBreak),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: _t('الأشكال', 'Shapes'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.crop_square, label: _t('مستطيل', 'Rectangle'), onTap: () => widget.onInsertShape?.call('rectangle')),
              _buildToolItem(icon: Icons.circle_outlined, label: _t('دائرة', 'Circle'), onTap: () => widget.onInsertShape?.call('circle')),
              _buildToolItem(icon: Icons.change_history, label: _t('مثلث', 'Triangle'), onTap: () => widget.onInsertShape?.call('triangle')),
              _buildToolItem(icon: Icons.pentagon_outlined, label: _t('خماسي', 'Pentagon'), onTap: () => widget.onInsertShape?.call('pentagon')),
              _buildToolItem(icon: Icons.hexagon_outlined, label: _t('سداسي', 'Hexagon'), onTap: () => widget.onInsertShape?.call('hexagon')),
              _buildToolItem(icon: Icons.chat_bubble_outline, label: _t('تعليق', 'Callout'), onTap: () => widget.onInsertShape?.call('callout')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMathTab() {
    return Row(
      children: [
        _buildRibbonGroup(
          title: _t('عمليات وصيغ', 'Operations'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.percent, label: _t('بسط/مقام', 'Fraction'), onTap: widget.onInsertFraction),
              _buildToolItem(icon: Icons.square_foot, label: _t('جذر', 'Radical'), onTap: widget.onInsertRadical),
              _buildToolItem(icon: Icons.functions, label: _t('معادلة f(x)', 'Equation f(x)'), onTap: widget.onInsertEquation),
              _buildToolItem(icon: Icons.view_headline, label: _t('عمودي ± ×', 'Vertical ± ×'), onTap: widget.onInsertVerticalMath),
              _buildToolItem(icon: Icons.airline_seat_recline_normal, label: _t('قسمة ⟌', 'Long division'), onTap: widget.onInsertLongDivision),
              _buildToolItem(icon: Icons.emoji_symbols, label: _t('رموز', 'Symbols'), onTap: widget.onOpenSymbolsModal),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLayoutTab() {
    return Row(
      children: [
        _buildRibbonGroup(
          title: _t('تباعد الأسطر', 'Line spacing'),
          child: Row(
            children: [
              PopupMenuButton<double>(
                tooltip: _t('تباعد الأسطر', 'Line spacing'),
                onSelected: widget.onLineSpacingChanged,
                itemBuilder: (ctx) => [
                  PopupMenuItem(value: 1.0, child: Text(_t('عادي (1.0)', 'Single (1.0)'))),
                  PopupMenuItem(value: 1.5, child: Text(_t('متوسط (1.5)', 'Medium (1.5)'))),
                  PopupMenuItem(value: 2.0, child: Text(_t('مزدوج (2.0)', 'Double (2.0)'))),
                  PopupMenuItem(value: 2.5, child: Text(_t('واسع (2.5)', 'Wide (2.5)'))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.format_line_spacing, size: 20, color: Color(0xFF334155)),
                      const SizedBox(height: 2),
                      Text('${widget.currentLineSpacing}x', style: const TextStyle(fontSize: 10, color: Color(0xFF334155))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViewTab() {
    return Row(
      children: [
        _buildRibbonGroup(
          title: _t('معاينة الورقة', 'Page view'),
          child: Row(
            children: [
              _buildToolItem(icon: Icons.fit_screen_outlined, label: _t('ملاءمة الصفحة', 'Fit page'), onTap: widget.onFitScreen),
              _buildToolItem(icon: Icons.zoom_in, label: _t('تكبير', 'Increase'), onTap: widget.onZoomIn),
              _buildToolItem(icon: Icons.zoom_out, label: _t('تصغير', 'Decrease'), onTap: widget.onZoomOut),
            ],
          ),
        ),
      ],
    );
  }
}

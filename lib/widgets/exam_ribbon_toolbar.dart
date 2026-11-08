import 'package:flutter/material.dart';

enum RibbonTab {
  home,       // الرئيسية
  format,     // تنسيق
  insert,     // إدراج
  math,       // رياضيات
  table,      // جدول
  layout,     // تخطيط
  shapes,     // رسم
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

  // ✅ الخصائص الجديدة المضافة لإخفاء وإظهار إعدادات السؤال
  final bool showQuestionSettings;
  final VoidCallback onToggleQuestionSettings;

  final VoidCallback onToggleBold;
  final VoidCallback onToggleUnderline;
  final Function(TextAlign) onAlignmentChanged;
  final Function(String) onColorChanged;
  final Function(String) onFontChanged;
  final Function(double) onFontSizeChanged;
  final VoidCallback onToggleInputLanguage;

  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onCut;
  final VoidCallback onSelectAll;
  final VoidCallback onDeleteSelected;
  final VoidCallback onOpenQuestionBank;

  final VoidCallback onInsertImage;
  final VoidCallback onInsertDottedLine;
  final VoidCallback onInsertPageBreak;
  final VoidCallback onInsertTextBox;

  final VoidCallback onInsertFraction;
  final VoidCallback onInsertRadical;
  final VoidCallback onInsertEquation;
  final VoidCallback onInsertVerticalMath;
  final VoidCallback onInsertLongDivision;
  final VoidCallback onOpenSymbolsModal;

  final VoidCallback onOpenTableDesigner;
  final Function(String kind) onInsertShape;

  const ExamRibbonToolbar({
    super.key,
    required this.isBold,
    required this.isUnderline,
    required this.currentAlignment,
    required this.currentColor,
    required this.currentFont,
    required this.currentFontSize,
    required this.isArabicInput,
    required this.showQuestionSettings, // ✅ إضافة
    required this.onToggleQuestionSettings, // ✅ إضافة
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
  });

  @override
  State<ExamRibbonToolbar> createState() => _ExamRibbonToolbarState();
}

class _ExamRibbonToolbarState extends State<ExamRibbonToolbar> {
  RibbonTab _activeTab = RibbonTab.format;
  bool _isExpanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. شريط أسماء التبويبات مع زر الطي والإظهار
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
                      _buildTabButton('الرئيسية', RibbonTab.home),
                      _buildTabButton('تنسيق', RibbonTab.format),
                      _buildTabButton('إدراج', RibbonTab.insert),
                      _buildTabButton('رياضيات', RibbonTab.math),
                      _buildTabButton('جدول', RibbonTab.table),
                      _buildTabButton('تخطيط', RibbonTab.layout),
                      _buildTabButton('رسم', RibbonTab.shapes),
                      _buildTabButton('عرض', RibbonTab.view),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. محتوى أدوات التبويب النشط
          if (_isExpanded)
            Container(
              height: 108,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              color: Colors.white,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildTabContent(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTabButton(String title, RibbonTab tab) {
    final bool isSelected = _activeTab == tab;
    return InkWell(
      onTap: () {
        setState(() {
          _activeTab = tab;
          _isExpanded = true;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE2E8F0) : Colors.transparent,
          border: isSelected
              ? const Border(bottom: BorderSide(color: Color(0xFF1E3A8A), width: 2.5))
              : null,
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
      case RibbonTab.home:
        return _buildHomeTab();
      case RibbonTab.format:
        return _buildFormatTab();
      case RibbonTab.insert:
        return _buildInsertTab();
      case RibbonTab.math:
        return _buildMathTab();
      case RibbonTab.table:
        return _buildTableTab();
      case RibbonTab.layout:
        return _buildLayoutTab();
      case RibbonTab.shapes:
        return _buildShapesTab();
      case RibbonTab.view:
        return _buildViewTab();
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
          Text(
            title,
            style: const TextStyle(fontSize: 9.5, color: Color(0xFF64748B), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildToolItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isSelected = false,
    Color? color,
  }) {
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
            Icon(icon, size: 20, color: isSelected ? const Color(0xFF1E3A8A) : (color ?? const Color(0xFF334155))),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isSelected ? const Color(0xFF1E3A8A) : const Color(0xFF334155),
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
          title: 'الحافظة',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.paste_outlined, label: 'لصق', onTap: widget.onPaste),
              _buildToolItem(icon: Icons.copy_outlined, label: 'نسخ', onTap: widget.onCopy),
              _buildToolItem(icon: Icons.content_cut, label: 'قص', onTap: widget.onCut),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: 'تحديد',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.select_all, label: 'تحديد الكل', onTap: widget.onSelectAll),
              _buildToolItem(icon: Icons.delete_sweep_outlined, label: 'حذف المحدد', onTap: widget.onDeleteSelected),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: 'بنك الأسئلة',
          child: Row(
            children: [
              _buildToolItem(
                icon: Icons.account_balance,
                label: 'بنك الأسئلة',
                onTap: widget.onOpenQuestionBank,
                color: const Color(0xFF1E3A8A),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormatTab() {
    return Row(
      children: [
        // ✅ مجموعة جديدة: إعدادات السؤال (تتحكم في إخفاء/إظهار حقول العنوان والدرجة)
        _buildRibbonGroup(
          title: 'السؤال',
          child: Row(
            children: [
              _buildToolItem(
                icon: Icons.tune,
                label: 'إعدادات السؤال',
                isSelected: widget.showQuestionSettings,
                color: const Color(0xFF1E3A8A),
                onTap: widget.onToggleQuestionSettings,
              ),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: 'الخط',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.format_bold, label: 'عريض', isSelected: widget.isBold, onTap: widget.onToggleBold),
              _buildToolItem(icon: Icons.format_underlined, label: 'تسطير', isSelected: widget.isUnderline, onTap: widget.onToggleUnderline),
              _buildToolItem(
                icon: Icons.text_increase,
                label: 'تكبير',
                onTap: () => widget.onFontSizeChanged(widget.currentFontSize + 1),
              ),
              _buildToolItem(
                icon: Icons.text_decrease,
                label: 'تصغير',
                onTap: () => widget.onFontSizeChanged(widget.currentFontSize > 8 ? widget.currentFontSize - 1 : 8),
              ),
              _buildToolItem(
                icon: Icons.palette,
                label: 'لون النص',
                color: Color(int.parse(widget.currentColor.replaceFirst('#', '0xFF'))),
                onTap: () {
                  const colors = ['#000000', '#1D4ED8', '#B91C1C', '#047857'];
                  final nextIdx = (colors.indexOf(widget.currentColor) + 1) % colors.length;
                  widget.onColorChanged(colors[nextIdx]);
                },
              ),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: 'المحاذاة والاتجاه',
          child: Row(
            children: [
              _buildToolItem(
                icon: Icons.format_align_right,
                label: 'يمين',
                isSelected: widget.currentAlignment == TextAlign.right,
                onTap: () => widget.onAlignmentChanged(TextAlign.right),
              ),
              _buildToolItem(
                icon: Icons.format_align_center,
                label: 'وسط',
                isSelected: widget.currentAlignment == TextAlign.center,
                onTap: () => widget.onAlignmentChanged(TextAlign.center),
              ),
              _buildToolItem(
                icon: Icons.format_align_left,
                label: 'يسار',
                isSelected: widget.currentAlignment == TextAlign.left,
                onTap: () => widget.onAlignmentChanged(TextAlign.left),
              ),
              _buildToolItem(
                icon: Icons.language,
                label: widget.isArabicInput ? 'كتابة: ع' : 'Input: En',
                isSelected: !widget.isArabicInput,
                color: widget.isArabicInput ? const Color(0xFF0F766E) : const Color(0xFFD97706),
                onTap: widget.onToggleInputLanguage,
              ),
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
          title: 'عناصر',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.image_outlined, label: 'صورة', onTap: widget.onInsertImage),
              _buildToolItem(icon: Icons.table_chart_outlined, label: 'جدول', onTap: widget.onOpenTableDesigner),
              _buildToolItem(icon: Icons.border_horizontal, label: 'خط إجابة', onTap: widget.onInsertDottedLine),
              _buildToolItem(icon: Icons.edit_note, label: 'مربع إرشاد', onTap: widget.onInsertTextBox),
              _buildToolItem(icon: Icons.note_add_outlined, label: 'صفحة جديدة', onTap: widget.onInsertPageBreak),
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
          title: 'عمليات وصيغ',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.percent, label: 'بسط/مقام', onTap: widget.onInsertFraction),
              _buildToolItem(icon: Icons.square_foot, label: 'جذر', onTap: widget.onInsertRadical),
              _buildToolItem(icon: Icons.functions, label: 'معادلة f(x)', onTap: widget.onInsertEquation),
              _buildToolItem(icon: Icons.view_headline, label: 'عمودي ± ×', onTap: widget.onInsertVerticalMath),
              _buildToolItem(icon: Icons.airline_seat_recline_normal, label: 'قسمة ⟌', onTap: widget.onInsertLongDivision),
              _buildToolItem(icon: Icons.emoji_symbols, label: 'رموز', onTap: widget.onOpenSymbolsModal),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTableTab() {
    return Row(
      children: [
        _buildRibbonGroup(
          title: 'إدارة الجدول',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.add_box_outlined, label: 'تصميم جدول', onTap: widget.onOpenTableDesigner),
              _buildToolItem(icon: Icons.border_clear, label: 'إلغاء التحديد', onTap: () {}),
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
          title: 'شبكة السطور والصفحة',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.format_line_spacing, label: 'تباعد السطور', onTap: () {}),
              _buildToolItem(icon: Icons.insert_page_break, label: 'فاصل صفحة', onTap: widget.onInsertPageBreak),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShapesTab() {
    return Row(
      children: [
        _buildRibbonGroup(
          title: 'الأشكال التلقائية',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.crop_square, label: 'مستطيل', onTap: () => widget.onInsertShape('rectangle')),
              _buildToolItem(icon: Icons.circle_outlined, label: 'دائرة', onTap: () => widget.onInsertShape('circle')),
              _buildToolItem(icon: Icons.change_history, label: 'مثلث', onTap: () => widget.onInsertShape('triangle')),
              _buildToolItem(icon: Icons.straighten, label: 'قائم', onTap: () => widget.onInsertShape('rightTriangle')),
              _buildToolItem(icon: Icons.timeline, label: 'خط', onTap: () => widget.onInsertShape('line')),
              _buildToolItem(icon: Icons.arrow_forward, label: 'سهم', onTap: () => widget.onInsertShape('arrow')),
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
          title: 'معاينة الورقة',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.fit_screen_outlined, label: 'ملاءمة الصفحة', onTap: () {}),
              _buildToolItem(icon: Icons.zoom_in, label: 'تكبير', onTap: () {}),
              _buildToolItem(icon: Icons.zoom_out, label: 'تصغير', onTap: () {}),
            ],
          ),
        ),
      ],
    );
  }
}

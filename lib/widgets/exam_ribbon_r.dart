import 'package:flutter/material.dart';

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

  // ✅ خصائص جديدة: التحكم في إظهار الإعدادات، التحديد، الحافظة، تباعد الأسطر، والتكبير
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

  @override
  Widget build(BuildContext context) {
    return Container(
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
                      _buildTabButton('الرئيسية', RibbonTab.home),
                      _buildTabButton('تنسيق', RibbonTab.format),
                      _buildTabButton('إدراج', RibbonTab.insert),
                      _buildTabButton('رياضيات', RibbonTab.math),
                      _buildTabButton('تخطيط', RibbonTab.layout),
                      _buildTabButton('عرض', RibbonTab.view),
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
      default: return const SizedBox.shrink();
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
    required VoidCallback? onTap, // ✅ أصبحت nullable لتعطيل الأزرار
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
          title: 'الحافظة',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.content_cut, label: 'قص', onTap: widget.isTextSelected ? widget.onCut : null),
              _buildToolItem(icon: Icons.copy_outlined, label: 'نسخ', onTap: widget.isTextSelected ? widget.onCopy : null),
              _buildToolItem(icon: Icons.paste_outlined, label: 'لصق', onTap: widget.hasClipboardContent ? widget.onPaste : null),
              _buildToolItem(icon: Icons.share_outlined, label: 'مشاركة', onTap: widget.isTextSelected ? widget.onShare : null),
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
              _buildToolItem(icon: Icons.account_balance, label: 'بنك الأسئلة', onTap: widget.onOpenQuestionBank, color: const Color(0xFF1E3A8A)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFormatTab() {
    return Row(
      children: [
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
          title: 'نوع الخط',
          child: Row(
            children: [
              // ✅ إضافة أداة اختيار نوع الخط
              PopupMenuButton<String>(
                tooltip: 'نوع الخط',
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
          title: 'الخط',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.format_bold, label: 'عريض', isSelected: widget.isBold, onTap: widget.onToggleBold),
              _buildToolItem(icon: Icons.format_underlined, label: 'تسطير', isSelected: widget.isUnderline, onTap: widget.onToggleUnderline),
              _buildToolItem(icon: Icons.text_increase, label: 'تكبير', onTap: () => widget.onFontSizeChanged?.call(widget.currentFontSize + 1)),
              _buildToolItem(icon: Icons.text_decrease, label: 'تصغير', onTap: () => widget.onFontSizeChanged?.call(widget.currentFontSize > 8 ? widget.currentFontSize - 1 : 8)),
              PopupMenuButton<String>(
                tooltip: 'لون النص',
                onSelected: widget.onColorChanged,
                itemBuilder: (ctx) => [
                  {'name': 'أسود', 'hex': '#000000'}, {'name': 'أحمر', 'hex': '#B91C1C'},
                  {'name': 'أزرق', 'hex': '#1D4ED8'}, {'name': 'أخضر', 'hex': '#047857'},
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
                      const Text('لون', style: TextStyle(fontSize: 10, color: Color(0xFF334155))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildRibbonGroup(
          title: 'المحاذاة والاتجاه',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.format_align_right, label: 'يمين', isSelected: widget.currentAlignment == TextAlign.right, onTap: () => widget.onAlignmentChanged?.call(TextAlign.right)),
              _buildToolItem(icon: Icons.format_align_center, label: 'وسط', isSelected: widget.currentAlignment == TextAlign.center, onTap: () => widget.onAlignmentChanged?.call(TextAlign.center)),
              _buildToolItem(icon: Icons.format_align_left, label: 'يسار', isSelected: widget.currentAlignment == TextAlign.left, onTap: () => widget.onAlignmentChanged?.call(TextAlign.left)),
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
        _buildRibbonGroup(
          title: 'الأشكال',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.crop_square, label: 'مستطيل', onTap: () => widget.onInsertShape?.call('rectangle')),
              _buildToolItem(icon: Icons.circle_outlined, label: 'دائرة', onTap: () => widget.onInsertShape?.call('circle')),
              _buildToolItem(icon: Icons.change_history, label: 'مثلث', onTap: () => widget.onInsertShape?.call('triangle')),
              _buildToolItem(icon: Icons.pentagon_outlined, label: 'خماسي', onTap: () => widget.onInsertShape?.call('pentagon')),
              _buildToolItem(icon: Icons.hexagon_outlined, label: 'سداسي', onTap: () => widget.onInsertShape?.call('hexagon')),
              _buildToolItem(icon: Icons.chat_bubble_outline, label: 'تعليق', onTap: () => widget.onInsertShape?.call('callout')),
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

  Widget _buildLayoutTab() {
    return Row(
      children: [
        _buildRibbonGroup(
          title: 'تباعد الأسطر',
          child: Row(
            children: [
              // ✅ إضافة أداة تباعد الأسطر
              PopupMenuButton<double>(
                tooltip: 'تباعد الأسطر',
                onSelected: widget.onLineSpacingChanged,
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 1.0, child: Text('عادي (1.0)')),
                  const PopupMenuItem(value: 1.5, child: Text('متوسط (1.5)')),
                  const PopupMenuItem(value: 2.0, child: Text('مزدوج (2.0)')),
                  const PopupMenuItem(value: 2.5, child: Text('واسع (2.5)')),
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
        _buildRibbonGroup(
          title: 'الصفحة',
          child: Row(
            children: [
              _buildToolItem(icon: Icons.insert_page_break, label: 'فاصل صفحة', onTap: widget.onInsertPageBreak),
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
              _buildToolItem(icon: Icons.fit_screen_outlined, label: 'ملاءمة الصفحة', onTap: widget.onFitScreen),
              _buildToolItem(icon: Icons.zoom_in, label: 'تكبير', onTap: widget.onZoomIn),
              _buildToolItem(icon: Icons.zoom_out, label: 'تصغير', onTap: widget.onZoomOut),
            ],
          ),
        ),
      ],
    );
  }
}

// Fonts list should be accessible globally in the app
const List<Map<String, String>> appFontsList = [
  {'id': 'Amiri', 'name': 'خط الأميري (الافتراضي)'},
  {'id': 'Hafs', 'name': 'مصحف حفص (عثماني)'},
  {'id': 'Thuluth', 'name': 'خط الثلث'},
  {'id': 'Almarai', 'name': 'المراعي'},
  {'id': 'Changa', 'name': 'تشانجا'},
  {'id': 'Kufam', 'name': 'كوفام'},
  {'id': 'Rubik', 'name': 'روبيك'},
  {'id': 'Arial', 'name': 'أريال (Arial)'},
  {'id': 'ElHijaz', 'name': 'الحجاز عادي'},
  {'id': 'ElSHijazAdorn', 'name': 'زخارف الحجاز (ElS-Hijaz Adorn)'},
  {'id': 'ElourQuraaKufi', 'name': 'قراء كوفي'},
  {'id': 'ElghAnSrame', 'name': 'الغصن الصارم'},
  {'id': 'ElAfrica', 'name': 'إفريقيا (ElAfrica)'},
  {'id': 'SultanCtangle', 'name': 'سلطان (Sultan)'},
  {'id': 'Tahrir', 'name': 'تحرير'},
  {'id': 'DTUTH', 'name': 'ديتوث (DTUTH)'},
  {'id': 'Lishposter', 'name': 'ليش بوستر'},
  {'id': 'Axdf', 'name': 'أكسدف (Axdf)'},
  {'id': 'Banyeh', 'name': 'بنية (Banyeh)'},
  {'id': 'Meshref', 'name': 'مشرف'},
  {'id': 'Minder', 'name': 'ميندر'},
  {'id': 'Mobv2', 'name': 'موب V2'},
  {'id': 'GSoon', 'name': 'غصون'},
  {'id': 'DeApple', 'name': 'دي آبل'},
  {'id': 'JsMath', 'name': 'رموز الرياضيات (JsMath)'},
  {'id': 'Satisfy', 'name': 'Satisfy'},
  {'id': 'Schoolbell', 'name': 'Schoolbell'},
  {'id': 'Caps', 'name': 'Caps Regular'},
  {'id': 'Chewy', 'name': 'Chewy'},
  {'id': 'Crushed', 'name': 'Crushed'},
  {'id': 'Girls', 'name': 'Girls'},
  {'id': 'Grover', 'name': 'Grover'},
  {'id': 'RSwanky', 'name': 'R-Swanky'},
  {'id': 'SMono', 'name': 'خط أحادي (SMono)'},
];

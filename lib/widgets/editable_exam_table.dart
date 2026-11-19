import 'dart:convert';
import 'package:flutter/material.dart';

/// Editable table used directly on the A4 question canvas.
/// The JSON format remains backward compatible with rows/cols/data/hasHeader.
class EditableExamTable extends StatefulWidget {
  final String value;
  final double width;
  final double height;
  final bool isArabic;
  final ValueChanged<String> onChanged;

  const EditableExamTable({
    super.key,
    required this.value,
    required this.width,
    required this.height,
    required this.isArabic,
    required this.onChanged,
  });

  @override
  State<EditableExamTable> createState() => _EditableExamTableState();
}

class _EditableExamTableState extends State<EditableExamTable> {
  late List<List<String>> grid;
  late bool hasHeader;
  late List<Map<String, int>> merges;
  int? anchorRow;
  int? anchorCol;
  int? focusRow;
  int? focusCol;

  @override
  void initState() {
    super.initState();
    _read(widget.value);
  }

  @override
  void didUpdateWidget(covariant EditableExamTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _read(widget.value);
  }

  void _read(String raw) {
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final rows = (map['rows'] as num?)?.toInt().clamp(1, 30).toInt() ?? 2;
      final cols = (map['cols'] as num?)?.toInt().clamp(1, 16).toInt() ?? 2;
      final source = map['data'] as List? ?? const [];
      grid = List.generate(rows, (r) => List.generate(cols, (c) {
        if (r < source.length && source[r] is List && c < (source[r] as List).length) {
          return (source[r][c] ?? '').toString();
        }
        return '';
      }));
      hasHeader = map['hasHeader'] as bool? ?? true;
      merges = (map['merges'] as List? ?? const []).whereType<Map>().map((e) =>
        Map<String, int>.from(e.map((k, v) => MapEntry(k.toString(), (v as num).toInt())))
      ).toList();
    } catch (_) {
      grid = List.generate(3, (_) => List.filled(3, ''));
      hasHeader = true;
      merges = [];
    }
  }

  void _emit() {
    widget.onChanged(jsonEncode({
      'rows': grid.length,
      'cols': grid.first.length,
      'hasHeader': hasHeader,
      'data': grid,
      'merges': merges,
    }));
  }

  Map<String, int>? _mergeAt(int r, int c) {
    for (final m in merges) {
      final mr = m['row'] ?? 0, mc = m['col'] ?? 0;
      final rs = m['rowSpan'] ?? 1, cs = m['colSpan'] ?? 1;
      if (r >= mr && r < mr + rs && c >= mc && c < mc + cs) return m;
    }
    return null;
  }

  bool _covered(int r, int c) {
    final m = _mergeAt(r, c);
    return m != null && ((m['row'] ?? 0) != r || (m['col'] ?? 0) != c);
  }

  void _select(int r, int c) {
    setState(() {
      if (anchorRow == null) {
        anchorRow = focusRow = r;
        anchorCol = focusCol = c;
      } else {
        focusRow = r;
        focusCol = c;
      }
    });
  }

  List<int> get _bounds {
    final ar = anchorRow ?? 0, ac = anchorCol ?? 0;
    final fr = focusRow ?? ar, fc = focusCol ?? ac;
    return [ar < fr ? ar : fr, ac < fc ? ac : fc, ar > fr ? ar : fr, ac > fc ? ac : fc];
  }

  bool get _hasRange {
    if (anchorRow == null || focusRow == null) return false;
    final b = _bounds;
    return b[0] != b[2] || b[1] != b[3];
  }

  void _addRow() {
    setState(() => grid.add(List.filled(grid.first.length, '')));
    _emit();
  }

  void _removeRow() {
    if (grid.length <= 1) return;
    final r = focusRow ?? grid.length - 1;
    setState(() {
      grid.removeAt(r.clamp(0, grid.length - 1).toInt());
      merges.clear();
      anchorRow = focusRow = null;
    });
    _emit();
  }

  void _addColumn() {
    setState(() { for (final row in grid) { row.add(''); } });
    _emit();
  }

  void _removeColumn() {
    if (grid.first.length <= 1) return;
    final c = focusCol ?? grid.first.length - 1;
    setState(() {
      for (final row in grid) { row.removeAt(c.clamp(0, row.length - 1).toInt()); }
      merges.clear();
      anchorCol = focusCol = null;
    });
    _emit();
  }

  void _merge() {
    if (!_hasRange) return;
    final b = _bounds;
    final texts = <String>[];
    for (var r = b[0]; r <= b[2]; r++) {
      for (var c = b[1]; c <= b[3]; c++) {
        if (grid[r][c].trim().isNotEmpty) texts.add(grid[r][c]);
        if (r != b[0] || c != b[1]) grid[r][c] = '';
      }
    }
    grid[b[0]][b[1]] = texts.join('\n');
    setState(() {
      merges.removeWhere((m) {
        final mr = m['row'] ?? 0, mc = m['col'] ?? 0;
        final meR = mr + (m['rowSpan'] ?? 1) - 1;
        final meC = mc + (m['colSpan'] ?? 1) - 1;
        return mr >= b[0] && mc >= b[1] && meR <= b[2] && meC <= b[3];
      });
      merges.add({'row': b[0], 'col': b[1], 'rowSpan': b[2] - b[0] + 1, 'colSpan': b[3] - b[1] + 1});
    });
    _emit();
  }

  void _split() {
    if (focusRow == null || focusCol == null) return;
    final m = _mergeAt(focusRow!, focusCol!);
    if (m == null) return;
    setState(() => merges.remove(m));
    _emit();
  }

  Widget _tool(IconData icon, String label, VoidCallback? action) => Tooltip(
    message: label,
    child: IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 32),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 18),
      onPressed: action,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final selectedMerge = focusRow == null || focusCol == null ? null : _mergeAt(focusRow!, focusCol!);
    final rowCount = grid.length;
    final colCount = grid.first.length;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Column(
        children: [
          Container(
            height: 30,
            color: const Color(0xFFE8EEF8),
            child: Row(
              children: [
                _tool(Icons.add, 'إضافة صف', _addRow),
                _tool(Icons.remove, 'حذف الصف المحدد', rowCount > 1 ? _removeRow : null),
                const VerticalDivider(width: 1),
                _tool(Icons.view_column, 'إضافة عمود', _addColumn),
                _tool(Icons.remove, 'حذف العمود المحدد', colCount > 1 ? _removeColumn : null),
                const VerticalDivider(width: 1),
                _tool(Icons.merge_type, 'دمج الخلايا المحددة', _hasRange ? _merge : null),
                _tool(Icons.call_split, 'تقسيم الخلية', selectedMerge != null ? _split : null),
                const Spacer(),
                Text('${rowCount}×${colCount}', style: const TextStyle(fontSize: 10)),
                const SizedBox(width: 5),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellW = constraints.maxWidth / colCount;
                final cellH = constraints.maxHeight / rowCount;
                final children = <Widget>[];
                for (var r = 0; r < rowCount; r++) {
                  for (var c = 0; c < colCount; c++) {
                    if (_covered(r, c)) continue;
                    final m = _mergeAt(r, c);
                    final spanC = m == null ? 1 : (m['colSpan'] ?? 1);
                    final spanR = m == null ? 1 : (m['rowSpan'] ?? 1);
                    final selected = _hasRange && r >= _bounds[0] && r <= _bounds[2] && c >= _bounds[1] && c <= _bounds[3];
                    children.add(Positioned(
                      left: c * cellW,
                      top: r * cellH,
                      width: cellW * spanC,
                      height: cellH * spanR,
                      child: GestureDetector(
                        onTap: () => _select(r, c),
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected ? const Color(0xFFE3F2FD) : (hasHeader && r == 0 ? Colors.grey.shade200 : Colors.white),
                            border: Border.all(color: selected ? Colors.blue : Colors.black87, width: selected ? 1.4 : 0.7),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          child: TextFormField(
                            key: ValueKey('cell-$r-$c'),
                            initialValue: grid[r][c],
                            expands: true,
                            maxLines: null,
                            minLines: null,
                            textAlign: TextAlign.center,
                            textAlignVertical: TextAlignVertical.center,
                            style: TextStyle(
                              fontFamily: widget.isArabic ? 'Amiri' : 'Arial',
                              fontSize: hasHeader && r == 0 ? 12 : 11,
                              fontWeight: hasHeader && r == 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                            onTap: () => _select(r, c),
                            onChanged: (v) { grid[r][c] = v; _emit(); },
                          ),
                        ),
                      ),
                    ));
                  }
                }
                return SizedBox.expand(child: Stack(clipBehavior: Clip.hardEdge, children: children));
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

class InteractiveElementWrapper extends StatefulWidget {
  final Widget child;
  final double initialWidth;
  final double initialHeight;
  final Offset initialPosition;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(Offset newPos) onPositionChanged;
  final Function(double newWidth, double newHeight) onSizeChanged;

  const InteractiveElementWrapper({
    super.key,
    required this.child,
    required this.initialWidth,
    required this.initialHeight,
    this.initialPosition = Offset.zero,
    required this.isSelected,
    required this.onTap,
    required this.onPositionChanged,
    required this.onSizeChanged,
  });

  @override
  State<InteractiveElementWrapper> createState() => _InteractiveElementWrapperState();
}

class _InteractiveElementWrapperState extends State<InteractiveElementWrapper> {
  late double _width;
  late double _height;
  late Offset _position;

  @override
  void initState() {
    super.initState();
    _width = widget.initialWidth;
    _height = widget.initialHeight;
    _position = widget.initialPosition;
  }

  @override
  void didUpdateWidget(covariant InteractiveElementWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialWidth != widget.initialWidth) _width = widget.initialWidth;
    if (oldWidget.initialHeight != widget.initialHeight) _height = widget.initialHeight;
    if (oldWidget.initialPosition != widget.initialPosition) _position = widget.initialPosition;
  }

  @override
  Widget build(BuildContext context) {
    const double handleSize = 12.0;

    return Transform.translate(
      offset: _position,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // العنصر الداخلي الفعلي (الشكل التلقائي أو الجدول)
            Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                border: widget.isSelected
                    ? Border.all(color: const Color(0xFF1976D2), width: 1.5, style: BorderStyle.solid)
                    : null,
              ),
              child: widget.child,
            ),

            // طبقة أدوات التحكم كما في برنامج Word تظهر فقط عند التحديد
            if (widget.isSelected) ...[
              // زر الأسهم المتصالبة للتحريك الحر (يظهر أعلى العنصر بالمنتصف)
              Positioned(
                top: -36,
                left: (_width / 2) - 18,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _position += details.delta;
                    });
                    widget.onPositionChanged(_position);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1976D2),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 4, offset: const Offset(0, 2))
                      ],
                    ),
                    child: const Icon(Icons.open_with, color: Colors.white, size: 20),
                  ),
                ),
              ),

              // نقاط التحكم بالتكبير والتصغير (المقابض الثمانية)
              // 1. أعلى اليمين
              _buildResizeHandle(
                top: -handleSize / 2,
                right: -handleSize / 2,
                size: handleSize,
                onPan: (delta) {
                  setState(() {
                    _width = (_width + delta.dx).clamp(40.0, 600.0);
                    _height = (_height - delta.dy).clamp(30.0, 600.0);
                    _position += Offset(0, delta.dy);
                  });
                  widget.onSizeChanged(_width, _height);
                  widget.onPositionChanged(_position);
                },
              ),
              // 2. أسفل اليمين
              _buildResizeHandle(
                bottom: -handleSize / 2,
                right: -handleSize / 2,
                size: handleSize,
                onPan: (delta) {
                  setState(() {
                    _width = (_width + delta.dx).clamp(40.0, 600.0);
                    _height = (_height + delta.dy).clamp(30.0, 600.0);
                  });
                  widget.onSizeChanged(_width, _height);
                },
              ),
              // 3. أسفل اليسار
              _buildResizeHandle(
                bottom: -handleSize / 2,
                left: -handleSize / 2,
                size: handleSize,
                onPan: (delta) {
                  setState(() {
                    _width = (_width - delta.dx).clamp(40.0, 600.0);
                    _height = (_height + delta.dy).clamp(30.0, 600.0);
                    _position += Offset(delta.dx, 0);
                  });
                  widget.onSizeChanged(_width, _height);
                  widget.onPositionChanged(_position);
                },
              ),
              // 4. أعلى اليسار
              _buildResizeHandle(
                top: -handleSize / 2,
                left: -handleSize / 2,
                size: handleSize,
                onPan: (delta) {
                  setState(() {
                    _width = (_width - delta.dx).clamp(40.0, 600.0);
                    _height = (_height - delta.dy).clamp(30.0, 600.0);
                    _position += Offset(delta.dx, delta.dy);
                  });
                  widget.onSizeChanged(_width, _height);
                  widget.onPositionChanged(_position);
                },
              ),
              // 5. منتصف الحافة اليمنى
              _buildResizeHandle(
                top: (_height / 2) - (handleSize / 2),
                right: -handleSize / 2,
                size: handleSize,
                onPan: (delta) {
                  setState(() {
                    _width = (_width + delta.dx).clamp(40.0, 600.0);
                  });
                  widget.onSizeChanged(_width, _height);
                },
              ),
              // 6. منتصف الحافة اليسرى
              _buildResizeHandle(
                top: (_height / 2) - (handleSize / 2),
                left: -handleSize / 2,
                size: handleSize,
                onPan: (delta) {
                  setState(() {
                    _width = (_width - delta.dx).clamp(40.0, 600.0);
                    _position += Offset(delta.dx, 0);
                  });
                  widget.onSizeChanged(_width, _height);
                  widget.onPositionChanged(_position);
                },
              ),
              // 7. منتصف الحافة السفلية
              _buildResizeHandle(
                bottom: -handleSize / 2,
                left: (_width / 2) - (handleSize / 2),
                size: handleSize,
                onPan: (delta) {
                  setState(() {
                    _height = (_height + delta.dy).clamp(30.0, 600.0);
                  });
                  widget.onSizeChanged(_width, _height);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResizeHandle({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Function(Offset delta) onPan,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: GestureDetector(
        onPanUpdate: (details) => onPan(details.delta),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFF1976D2), width: 2.0),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

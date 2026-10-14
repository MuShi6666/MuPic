import 'package:flutter/material.dart';

/// Interactive crop rectangle drawn on top of the *full* (uncropped) preview.
///
/// The rect is normalized in image space (left/top/right/bottom in 0..1).
/// Drag inside to move, drag a corner / edge handle to resize. When [aspect]
/// is non-null the box keeps that pixel ratio (w / h). Every live change
/// reports through [onChanged]; the gesture end calls [onCommit] (history +
/// full-quality render).
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.rect,
    required this.aspect,
    required this.onChanged,
    required this.onCommit,
  });

  final Rect rect; // normalized l,t,r,b
  final double? aspect; // target width/height in pixels, null = free
  final ValueChanged<Rect> onChanged;
  final VoidCallback onCommit;

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

enum _DragMode { none, move, left, top, right, bottom, topLeft, topRight, bottomLeft, bottomRight }

class _CropOverlayState extends State<CropOverlay> {
  static const double _handleHit = 28;
  static const double _minFraction = 0.1; // smallest box = 10% of the image

  _DragMode _mode = _DragMode.none;
  Rect _start = Rect.zero; // px rect when the gesture began
  Size _imageSize = Size.zero;

  Rect get _px {
    final s = widget.rect;
    return Rect.fromLTRB(
      s.left * _imageSize.width,
      s.top * _imageSize.height,
      s.right * _imageSize.width,
      s.bottom * _imageSize.height,
    );
  }

  void _emit(Rect px) {
    widget.onChanged(Rect.fromLTRB(
      (px.left / _imageSize.width).clamp(0.0, 1.0),
      (px.top / _imageSize.height).clamp(0.0, 1.0),
      (px.right / _imageSize.width).clamp(0.0, 1.0),
      (px.bottom / _imageSize.height).clamp(0.0, 1.0),
    ));
  }

  _DragMode _classify(Offset p) {
    final r = _px;
    final minW = _imageSize.width * _minFraction;
    final minH = _imageSize.height * _minFraction;
    bool near(double v) => (p.dx - v).abs() <= _handleHit;
    bool nearY(double v) => (p.dy - v).abs() <= _handleHit;
    final inX = p.dx >= r.left - _handleHit && p.dx <= r.right + _handleHit;
    final inY = p.dy >= r.top - _handleHit && p.dy <= r.bottom + _handleHit;

    if (near(r.left) && nearY(r.top) && r.width > minW) return _DragMode.topLeft;
    if (near(r.right) && nearY(r.top) && r.width > minW) return _DragMode.topRight;
    if (near(r.left) && nearY(r.bottom) && r.width > minW) return _DragMode.bottomLeft;
    if (near(r.right) && nearY(r.bottom) && r.width > minW) return _DragMode.bottomRight;
    if (near(r.left) && inY && r.width > minW) return _DragMode.left;
    if (near(r.right) && inY && r.width > minW) return _DragMode.right;
    if (nearY(r.top) && inX && r.height > minH) return _DragMode.top;
    if (nearY(r.bottom) && inX && r.height > minH) return _DragMode.bottom;
    if (r.contains(p)) return _DragMode.move;
    return _DragMode.none;
  }

  void _onPanStart(DragStartDetails d) {
    _start = _px;
    setState(() => _mode = _classify(d.localPosition));
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_mode == _DragMode.none) return;
    final dx = d.delta.dx;
    final dy = d.delta.dy;
    final minW = _imageSize.width * _minFraction;
    final minH = _imageSize.height * _minFraction;
    final maxW = _imageSize.width;
    final maxH = _imageSize.height;
    var r = _start; // recompute from gesture start, deltas accumulated in _start

    // Work on a mutable copy advanced by this frame's delta.
    var l = r.left, t = r.top, rt = r.right, b = r.bottom;
    switch (_mode) {
      case _DragMode.move:
        final w = rt - l, h = b - t;
        l = (l + dx).clamp(0.0, maxW - w);
        rt = l + w;
        t = (t + dy).clamp(0.0, maxH - h);
        b = t + h;
      case _DragMode.left:
        l = (l + dx).clamp(0.0, rt - minW);
      case _DragMode.right:
        rt = (rt + dx).clamp(l + minW, maxW);
      case _DragMode.top:
        t = (t + dy).clamp(0.0, b - minH);
      case _DragMode.bottom:
        b = (b + dy).clamp(t + minH, maxH);
      case _DragMode.topLeft:
        l = (l + dx).clamp(0.0, rt - minW);
        t = (t + dy).clamp(0.0, b - minH);
      case _DragMode.topRight:
        rt = (rt + dx).clamp(l + minW, maxW);
        t = (t + dy).clamp(0.0, b - minH);
      case _DragMode.bottomLeft:
        l = (l + dx).clamp(0.0, rt - minW);
        b = (b + dy).clamp(t + minH, maxH);
      case _DragMode.bottomRight:
        rt = (rt + dx).clamp(l + minW, maxW);
        b = (b + dy).clamp(t + minH, maxH);
      case _DragMode.none:
        return;
    }
    var next = Rect.fromLTRB(l, t, rt, b);

    final aspect = widget.aspect;
    if (aspect != null && _mode != _DragMode.move && _mode != _DragMode.none) {
      next = _enforceAspect(next, aspect);
    }

    _start = next; // chain frames (aspect correction included)
    setState(() {}); // keep hit-testing in sync while dragging
    _emit(next);
  }

  /// After a resize, re-derive the free dimension so w/h == [aspect], keeping
  /// the dragged edge / corner anchored, then clamp the box back into the
  /// frame without changing its size.
  Rect _enforceAspect(Rect r, double aspect) {
    final maxW = _imageSize.width;
    final maxH = _imageSize.height;
    var w = r.width, h = r.height;
    if (_mode == _DragMode.top || _mode == _DragMode.bottom) {
      w = h * aspect;
      if (w > maxW) {
        w = maxW;
        h = w / aspect;
      }
    } else {
      h = w / aspect;
      if (h > maxH) {
        h = maxH;
        w = h * aspect;
      }
    }
    var l = r.left, t = r.top;
    switch (_mode) {
      case _DragMode.left:
        l = r.right - w;
      case _DragMode.right:
        l = r.left;
      case _DragMode.top:
        t = r.bottom - h;
        l = (r.center.dx - w / 2).clamp(0.0, maxW - w);
      case _DragMode.bottom:
        t = r.top;
        l = (r.center.dx - w / 2).clamp(0.0, maxW - w);
      case _DragMode.topLeft:
        l = r.right - w;
        t = r.bottom - h;
      case _DragMode.topRight:
        t = r.bottom - h;
      case _DragMode.bottomLeft:
        l = r.right - w;
      case _DragMode.bottomRight:
        break;
      default:
        break;
    }
    l = l.clamp(0.0, maxW - w);
    t = t.clamp(0.0, maxH - h);
    return Rect.fromLTWH(l, t, w, h);
  }

  void _onPanEnd(DragEndDetails _) {
    if (_mode != _DragMode.none) widget.onCommit();
    setState(() => _mode = _DragMode.none);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      _imageSize = Size(cons.maxWidth, cons.maxHeight);
      // The normalized rect lives in widget; mirror it into px for painting.
      final px = _px;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: CustomPaint(
          painter: _CropPainter(rect: px, active: _mode != _DragMode.none),
          child: const SizedBox.expand(),
        ),
      );
    });
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter({required this.rect, required this.active});
  final Rect rect;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = Offset.zero & size;

    // Dim everything outside the crop box.
    final scrim = Paint()..color = const Color(0x99000000);
    canvas
      ..drawRect(Rect.fromLTWH(0, 0, whole.width, rect.top), scrim)
      ..drawRect(Rect.fromLTWH(0, rect.bottom, whole.width, whole.height - rect.bottom), scrim)
      ..drawRect(Rect.fromLTWH(0, rect.top, rect.left, rect.height), scrim)
      ..drawRect(Rect.fromLTWH(rect.right, rect.top, whole.width - rect.right, rect.height), scrim);

    // Frame + rule-of-thirds grid.
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRect(rect, border);
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.55);
    for (var i = 1; i < 3; i++) {
      final x = rect.left + rect.width * i / 3;
      final y = rect.top + rect.height * i / 3;
      canvas
        ..drawLine(Offset(x, rect.top), Offset(x, rect.bottom), grid)
        ..drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
    }

    // Corner brackets + edge grab bars (fatter while dragging).
    final h = Paint()
      ..color = Colors.white
      ..strokeWidth = active ? 6 : 4
      ..strokeCap = StrokeCap.round;
    final arm = 24.0;
    for (final c in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
      final sx = c.dx == rect.left ? 1 : -1;
      final sy = c.dy == rect.top ? 1 : -1;
      canvas
        ..drawLine(c, Offset(c.dx + arm * sx, c.dy), h)
        ..drawLine(c, Offset(c.dx, c.dy + arm * sy), h);
    }
    final mid = [
      Offset(rect.center.dx, rect.top),
      Offset(rect.center.dx, rect.bottom),
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
    ];
    for (final p in mid) {
      final horiz = p.dx == rect.center.dx;
      canvas.drawLine(
        horiz ? p - const Offset(16, 0) : Offset(p.dx, p.dy - 16),
        horiz ? p + const Offset(16, 0) : Offset(p.dx, p.dy + 16),
        h,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.rect != rect || old.active != active;
}

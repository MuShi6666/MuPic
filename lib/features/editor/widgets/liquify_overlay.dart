import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/models/adjustments.dart';

/// Liquify brush tools. [type] values 0..3 map straight onto the native
/// `warp[].type` encoding; [reconstruct] is client-side only (it deletes
/// impulses under the brush and is never serialized to the render struct).
enum LiquifyBrush {
  push(kWarpPush),
  bloat(kWarpBloat),
  pucker(kWarpPucker),
  twirl(kWarpTwirl),
  reconstruct(-1);

  const LiquifyBrush(this.type);
  final int type;
}

/// Gesture layer for the liquify tab: a single-finger drag lays down
/// deformation impulses along the path (sparse-sampled), or — for the
/// reconstruct brush — erases the impulses whose center falls under the brush.
///
/// Coordinates are mapped from the (possibly cropped / quarter-turned) display
/// rect back into normalized *source* space, mirroring the retouch spot layer,
/// so impulse semantics stay correct regardless of the current crop.
class LiquifyOverlay extends StatefulWidget {
  const LiquifyOverlay({
    super.key,
    required this.adj,
    required this.boxSize,
    required this.srcAspect,
    required this.brush,
    required this.brushSize,
    required this.strength,
    required this.warp,
    required this.onChanged,
    required this.onCommit,
    this.facePts = const <Offset>[],
  });

  final Adjustments adj;
  final Size boxSize;
  final double srcAspect; // source width / height (for min-dim displacement)
  final LiquifyBrush brush;
  final double brushSize; // 0..1
  final double strength; // 0..1
  final List<WarpImpulse> warp;
  final ValueChanged<List<WarpImpulse>> onChanged;
  final VoidCallback onCommit;

  /// Face-mesh key points (source-normalized, fixed 45-point order) drawn as a
  /// non-interactive guide so the user can see what the auto sliders act on.
  final List<Offset> facePts;

  @override
  State<LiquifyOverlay> createState() => _LiquifyOverlayState();
}

class _LiquifyOverlayState extends State<LiquifyOverlay> {
  static const double _sampleSpacing = 12.0; // px between impulses along a drag

  List<WarpImpulse>? _working;
  Offset? _last;
  Offset? _cursor;

  int get _turns => (widget.adj.cropTurns.round() % 4 + 4) % 4;

  double get _impulseRadius => 0.02 + widget.brushSize * 0.13; // of min-dim

  /// Display local point -> normalized source coords (crop rect + turns).
  Offset _displayToSource(Offset pq) {
    final p = (pq.dx / widget.boxSize.width).clamp(0.0, 1.0);
    final q = (pq.dy / widget.boxSize.height).clamp(0.0, 1.0);
    final (a, b) = switch (_turns) {
      1 => (q, 1 - p),
      2 => (1 - p, 1 - q),
      3 => (1 - q, p),
      _ => (p, q),
    };
    final adj = widget.adj;
    return Offset(
      adj.cropLeft + a * (adj.cropRight - adj.cropLeft),
      adj.cropTop + b * (adj.cropBottom - adj.cropTop),
    );
  }

  /// Display-space drag delta -> displacement vector in native impulse units
  /// (fraction of the shorter source edge), rotated through the current turns.
  Offset _deltaToSource(Offset d) {
    final dp = d.dx / widget.boxSize.width;
    final dq = d.dy / widget.boxSize.height;
    final adj = widget.adj;
    final sx = adj.cropRight - adj.cropLeft;
    final sy = adj.cropBottom - adj.cropTop;
    final (nu, nv) = switch (_turns) {
      1 => (dq, -dp),
      2 => (-dp, -dq),
      3 => (-dq, dp),
      _ => (dp, dq),
    };
    // Convert normalized source delta to min-dim units: W/minDim = max(aspect,1),
    // H/minDim = max(1/aspect,1).
    final wx = math.max(widget.srcAspect, 1.0);
    final wy = math.max(1.0 / widget.srcAspect, 1.0);
    return Offset(nu * sx * wx, nv * sy * wy) * (0.4 + widget.strength);
  }

  /// Normalized *source* point -> display-local coords: the exact inverse of
  /// [_displayToSource] (crop rect + quarter turns). Used only to draw the face
  /// guide; it never feeds back into impulse coordinates.
  Offset _sourceToDisplay(Offset src) {
    final adj = widget.adj;
    final u = (src.dx - adj.cropLeft) / (adj.cropRight - adj.cropLeft);
    final v = (src.dy - adj.cropTop) / (adj.cropBottom - adj.cropTop);
    final (p, q) = switch (_turns) {
      1 => (1 - v, u),
      2 => (1 - u, 1 - v),
      3 => (v, 1 - u),
      _ => (u, v),
    };
    return Offset(p * widget.boxSize.width, q * widget.boxSize.height);
  }

  void _onPanStart(DragStartDetails d) {
    _working = List<WarpImpulse>.of(widget.warp);
    _last = d.localPosition;
    _applyAt(d.localPosition, null);
    setState(() {});
  }

  void _onPanUpdate(DragUpdateDetails d) {
    _applyAt(d.localPosition, d.delta);
    setState(() {});
  }

  void _onPanEnd(DragEndDetails _) {
    _working = null;
    _last = null;
    _cursor = null;
    setState(() {});
    widget.onCommit();
  }

  void _applyAt(Offset local, Offset? delta) {
    final working = _working;
    if (working == null) return;
    _cursor = local;
    final center = _displayToSource(local);

    if (widget.brush == LiquifyBrush.reconstruct) {
      final r = _impulseRadius;
      working.removeWhere((im) {
        final dx = im.x - center.dx;
        final dy = im.y - center.dy;
        return dx * dx + dy * dy <= r * r;
      });
      widget.onChanged(List<WarpImpulse>.of(working));
      _last = local;
      return;
    }

    // Sparse-sample along the drag so a fast stroke still lays a smooth path.
    if (delta != null && _last != null) {
      final moved = (local - _last!).distance;
      if (moved < _sampleSpacing) return;
    }
    final type = widget.brush.type;
    final Offset disp;
    if (type == kWarpPush) {
      disp = delta != null ? _deltaToSource(delta) : Offset.zero;
      if (disp.distance < 1e-5) return;
    } else {
      // Radial / rotational brushes only use the vector magnitude.
      disp = Offset(widget.strength.clamp(0.05, 1.0), 0);
    }
    working.add(WarpImpulse(
      center.dx,
      center.dy,
      disp.dx,
      disp.dy,
      _impulseRadius,
      type.toDouble(),
    ));
    if (working.length > kMaxWarp) {
      working.removeRange(0, working.length - kMaxWarp); // drop oldest
    }
    widget.onChanged(List<WarpImpulse>.of(working));
    _last = local;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final guide = widget.facePts.map(_sourceToDisplay).toList(growable: false);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: CustomPaint(
        painter: _BrushPainter(
          cursor: _cursor,
          radiusPx: _impulseRadius *
              math.min(widget.boxSize.width, widget.boxSize.height),
          color: accent,
          facePts: guide,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BrushPainter extends CustomPainter {
  const _BrushPainter({
    required this.cursor,
    required this.radiusPx,
    required this.color,
    this.facePts = const <Offset>[],
  });
  final Offset? cursor;
  final double radiusPx;
  final Color color;
  final List<Offset> facePts;

  // The first [_kOvalPts] guide points form the face oval; the rest are loose
  // feature dots (eyes / nose / mouth / chin). Mirrors the native 45-point
  // order in color_pipeline.cpp `namespace face`.
  static const int _kOvalPts = 36;

  @override
  void paint(Canvas canvas, Size size) {
    // Face guide (drawn under the brush ring).
    if (facePts.length >= _kOvalPts) {
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = color.withValues(alpha: 0.5);
      final oval = Path()..moveTo(facePts[0].dx, facePts[0].dy);
      for (var i = 1; i < _kOvalPts; i++) {
        oval.lineTo(facePts[i].dx, facePts[i].dy);
      }
      oval.close();
      canvas.drawPath(oval, line);
      final dot = Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.8);
      for (var i = _kOvalPts; i < facePts.length; i++) {
        canvas.drawCircle(facePts[i], 2.0, dot);
      }
    }
    final c = cursor;
    if (c == null) return;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white;
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withValues(alpha: 0.9);
    final r = radiusPx
        .clamp(8.0, math.max(8.0, math.min(size.width, size.height)))
        .toDouble();
    canvas
      ..drawCircle(c, r, ring)
      ..drawCircle(c, r, inner);
  }

  @override
  bool shouldRepaint(_BrushPainter old) =>
      old.cursor != cursor ||
      old.radiusPx != radiusPx ||
      old.color != color ||
      old.facePts.length != facePts.length;
}

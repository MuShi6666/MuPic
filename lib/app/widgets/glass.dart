import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Ambient mesh-gradient backdrop shared by every top-level page.
///
/// Glassmorphism only reads as "glass" when there is something colorful behind
/// the translucent surfaces, so this paints the theme's [FluentTokens.bgBase]
/// plus three soft radial blobs ([FluentTokens.blobA]/[blobB]/[blobC]) that the
/// [GlassSurface] blur picks up through it. Mounted once in the app shell so
/// all three tabs share the same backdrop.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.fluent;
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(color: t.bgBase),
          child: LayoutBuilder(
            builder: (context, cons) {
              final blob = cons.maxWidth * 1.2;
              return Stack(
                children: [
                  _blob(t.blobA, Alignment(-0.9, -0.7), blob),
                  _blob(t.blobB, Alignment(0.95, -0.15), blob),
                  _blob(t.blobC, Alignment(-0.2, 0.95), blob),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _blob(Color color, Alignment align, double size) {
    return Align(
      alignment: align,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: 0.75), color.withValues(alpha: 0.0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// A reusable frosted-glass panel: backdrop blur + translucent tint + hairline
/// highlight border + soft drop shadow, all clipped to an arbitrary [radius].
///
/// Only use this for a handful of persistent chrome surfaces (nav bar, editor
/// toolbar, panel sheet, empty-state cards). Repeated in-list items should use
/// a lightweight translucent fill instead — a [BackdropFilter] per row is far
/// too expensive while scrolling.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius,
    this.blur = MuPicPalette.blurStrong,
    this.tint,
    this.showShadow = true,
    this.padding,
  });

  final Widget child;
  /// Corner radii; defaults to a uniform [MuPicPalette.radiusLg].
  final BorderRadius? radius;
  final double blur;
  /// Overrides the theme's glass tint (e.g. a lighter fill for a modal).
  final Color? tint;
  final bool showShadow;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final t = context.fluent;
    final r = radius ?? BorderRadius.circular(MuPicPalette.radiusLg);
    Widget result = ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tint ?? t.glassTint,
            borderRadius: r,
            border: Border.all(color: t.glassBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );
    if (showShadow) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [
            BoxShadow(
              color: t.glassShadow,
              blurRadius: blur,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: result,
      );
    }
    return result;
  }
}

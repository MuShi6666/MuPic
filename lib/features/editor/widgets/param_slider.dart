import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// A labeled slider bound to a single [Adjustments] field, styled as a soft
/// pastel card to match the anime theme.
///
/// While dragging, [onChanged] fires continuously (a small CPU preview is
/// requested); when the gesture ends [onCommit] records a history entry and
/// requests a larger preview. This two-tier behavior keeps dragging responsive.
class ParamSlider extends StatelessWidget {
  const ParamSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onCommit,
    this.divisions,
    this.format,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onCommit;
  final int? divisions;
  final String Function(double)? format;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = context.fluent;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      decoration: BoxDecoration(
        color: t.glassTint,
        borderRadius: BorderRadius.circular(MuPicPalette.radiusMd),
        border: Border.all(color: t.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  format?.call(value) ?? value.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: (_) => onCommit(),
          ),
        ],
      ),
    );
  }
}

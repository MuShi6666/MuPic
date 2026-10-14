import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_provider.dart';
import '../widgets/param_slider.dart';

/// Camera Raw "Color Grading" panel (formerly split toning).
///
/// Shadows / Midtones / Highlights each get a hue / saturation cast and a
/// luminance offset, blended by [Adjustments.gradeBlending] with the pivot
/// controlled by [Adjustments.gradeMidtoneRange]. Implemented analytically in
/// the native pipeline (gl_pipeline.cpp `applyGrade` + CPU mirror).
class GradingPanel extends ConsumerWidget {
  const GradingPanel({super.key});

  static const _regions = <(int, String)>[
    (0, '阴影'),
    (1, '中间调'),
    (2, '高光'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editorProvider.notifier);
    final adj = ref.watch(editorProvider).edit.adjustments;

    Widget norm(String label, double value, void Function(double) set,
        {double min = -1, double max = 1}) {
      return ParamSlider(
        label: label,
        value: value,
        min: min,
        max: max,
        onChanged: set,
        onCommit: controller.commit,
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        for (final (index, name) in _regions) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(name, style: Theme.of(context).textTheme.titleSmall),
            ),
          ),
          norm('$name 色相', adj.gradeHue[index],
              (v) => controller.updateAdjustment((a) => a.setGrade(index, 'hue', v))),
          norm('$name 饱和', adj.gradeSat[index],
              (v) => controller.updateAdjustment((a) => a.setGrade(index, 'sat', v)),
              min: 0),
          norm('$name 明度', adj.gradeLum[index],
              (v) => controller.updateAdjustment((a) => a.setGrade(index, 'lum', v))),
        ],
        const Divider(height: 24),
        norm('混合强度', adj.gradeBlending,
            (v) => controller.updateAdjustment(
                (a) => a.copyWith(gradeBlending: v.clamp(0, 1))),
            min: 0,
            max: 1),
        norm('中间调平衡', adj.gradeMidtoneRange,
            (v) => controller.updateAdjustment(
                (a) => a.copyWith(gradeMidtoneRange: v.clamp(0, 1))),
            min: 0,
            max: 1),
      ],
    );
  }
}

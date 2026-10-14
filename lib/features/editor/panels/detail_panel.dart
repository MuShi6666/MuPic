import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_provider.dart';
import '../widgets/param_slider.dart';

/// Camera Raw "Detail" panel — sharpening + noise reduction.
///
/// Drives [Adjustments]' sharpen / NR fields. The native pipeline applies these
/// with a 3x3 Gaussian of the *adjusted* neighborhood; the same math runs on the
/// GPU (gl_pipeline.cpp `applyDetail`) and CPU export (color_pipeline.cpp), so
/// preview and export match. Amounts are normalized 0..1.
class DetailPanel extends ConsumerWidget {
  const DetailPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editorProvider.notifier);
    final adj = ref.watch(editorProvider).edit.adjustments;

    Widget norm(String label, double value, void Function(double) set,
        {double min = 0, double max = 1}) {
      return ParamSlider(
        label: label,
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: set,
        onCommit: controller.commit,
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('锐化', style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        norm('数量', adj.sharpenAmount,
            (v) => controller.updateAdjustment((a) => a.copyWith(sharpenAmount: v))),
        norm('半径', adj.sharpenRadius,
            (v) => controller.updateAdjustment((a) => a.copyWith(sharpenRadius: v)),
            min: 0.5, max: 3),
        norm('细节', adj.sharpenDetail,
            (v) => controller.updateAdjustment((a) => a.copyWith(sharpenDetail: v))),
        norm('蒙版', adj.sharpenMasking,
            (v) => controller.updateAdjustment((a) => a.copyWith(sharpenMasking: v))),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('降噪', style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        norm('明亮度', adj.nrLuminance,
            (v) => controller.updateAdjustment((a) => a.copyWith(nrLuminance: v))),
        norm('明度细节', adj.nrLumDetail,
            (v) => controller.updateAdjustment((a) => a.copyWith(nrLumDetail: v))),
        norm('颜色', adj.nrColor,
            (v) => controller.updateAdjustment((a) => a.copyWith(nrColor: v))),
      ],
    );
  }
}

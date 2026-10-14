import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_provider.dart';
import '../widgets/param_slider.dart';

/// Camera Raw "Basic" panel (M1 subset wired to the native pipeline).
///
/// Each slider drives [Adjustments]; the controller sends the serialized params
/// to native on every change (coarse preview) and commits on release.
class BasicPanel extends ConsumerWidget {
  const BasicPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editorProvider.notifier);
    final adj = ref.watch(editorProvider).edit.adjustments;

    // Normalized sliders (-1..1) map their field through a shared helper.
    Widget norm(String label, double value, void Function(double) set,
        {double min = -1,
        double max = 1,
        int? divisions,
        String Function(double)? format}) {
      return ParamSlider(
        label: label,
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        format: format,
        onChanged: set,
        onCommit: controller.commit,
      );
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // --- White balance (色温 / 色调) ---
          // Drives Adjustments.colorTemp / .tint, applied natively as an
          // exponential R/B and G gain on top of the camera as-shot WB.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('白平衡', style: Theme.of(context).textTheme.titleSmall),
                TextButton(
                  onPressed: () {
                    controller.updateAdjustment(
                        (a) => a.copyWith(colorTemp: 0, tint: 0));
                    controller.commit();
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('原片'),
                ),
              ],
            ),
          ),
          norm('色温', adj.colorTemp,
              (v) =>
                  controller.updateAdjustment((a) => a.copyWith(colorTemp: v)),
              format: (v) => (v * 100).round().toString()),
          norm('色调', adj.tint,
              (v) => controller.updateAdjustment((a) => a.copyWith(tint: v)),
              format: (v) => (v * 100).round().toString()),
          norm('曝光', adj.exposure,
              (v) => controller.updateAdjustment((a) => a.copyWith(exposure: v)),
              min: -5, max: 5),
          norm('对比度', adj.contrast,
              (v) => controller.updateAdjustment((a) => a.copyWith(contrast: v))),
          norm('高光', adj.highlights,
              (v) => controller.updateAdjustment((a) => a.copyWith(highlights: v))),
          norm('阴影', adj.shadows,
              (v) => controller.updateAdjustment((a) => a.copyWith(shadows: v))),
          norm('白色', adj.whites,
              (v) => controller.updateAdjustment((a) => a.copyWith(whites: v))),
          norm('黑色', adj.blacks,
              (v) => controller.updateAdjustment((a) => a.copyWith(blacks: v))),
          norm('纹理', adj.texture,
              (v) => controller.updateAdjustment((a) => a.copyWith(texture: v))),
          norm('清晰度', adj.clarity,
              (v) => controller.updateAdjustment((a) => a.copyWith(clarity: v))),
          norm('去雾', adj.dehaze,
              (v) => controller.updateAdjustment((a) => a.copyWith(dehaze: v))),
          norm('自然饱和度', adj.vibrance,
              (v) => controller.updateAdjustment((a) => a.copyWith(vibrance: v))),
          norm('饱和度', adj.saturation,
              (v) => controller.updateAdjustment((a) => a.copyWith(saturation: v))),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_provider.dart';
import '../widgets/param_slider.dart';

/// Camera Raw "Lens Corrections" panel — remove chromatic aberration (RCA),
/// manual defringe (red/cyan, blue/yellow) and radial distortion.
///
/// These are geometric ops: the native pipeline resamples the source with a
/// radial warp (per-channel for lateral CA) *before* the color chain. The same
/// math runs on the GPU (gl_pipeline.cpp `sampleSource`) and CPU export
/// (color_pipeline.cpp), so preview and export match. Sliders are -1..1; the
/// RCA control is a 0/1 toggle.
class LensPanel extends ConsumerWidget {
  const LensPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editorProvider.notifier);
    final adj = ref.watch(editorProvider).edit.adjustments;

    Widget signed(String label, double value, void Function(double) set) {
      return ParamSlider(
        label: label,
        value: value.clamp(-1.0, 1.0),
        min: -1,
        max: 1,
        onChanged: set,
        onCommit: controller.commit,
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        SwitchListTile(
          title: const Text('移除色差'),
          subtitle: const Text('自动校正横向色彩边缘'),
          value: adj.lensRca > 0.5,
          onChanged: (on) {
            controller
                .updateAdjustment((a) => a.copyWith(lensRca: on ? 1.0 : 0.0));
            controller.commit();
          },
        ),
        const Divider(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('手动', style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        signed('去边 红/青', adj.lensDefringeRed,
            (v) => controller.updateAdjustment((a) => a.copyWith(lensDefringeRed: v))),
        signed('去边 蓝/黄', adj.lensDefringeBlue,
            (v) => controller.updateAdjustment((a) => a.copyWith(lensDefringeBlue: v))),
        signed('畸变校正', adj.lensDistortion,
            (v) => controller.updateAdjustment((a) => a.copyWith(lensDistortion: v))),
      ],
    );
  }
}

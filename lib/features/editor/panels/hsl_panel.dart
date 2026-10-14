import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_provider.dart';
import '../widgets/param_slider.dart';

/// Camera Raw "Color Mixer / HSL" panel.
///
/// Eight hue ranges (7 named + a global "All"); each drives hue / saturation /
/// luminance in [Adjustments.hslHue|Sat|Lum]. Applied analytically by the native
/// pipeline with a triangular hue falloff (gl_pipeline.cpp `applyHsl`, and its
/// CPU mirror in color_pipeline.cpp).
class HslPanel extends ConsumerStatefulWidget {
  const HslPanel({super.key});

  @override
  ConsumerState<HslPanel> createState() => _HslPanelState();
}

class _HslPanelState extends ConsumerState<HslPanel> {
  static const _ranges = <String>[
    '红', '橙', '黄', '绿', '青', '蓝', '紫', '全部',
  ];
  static const _kinds = ['hue', 'sat', 'lum'];
  static const _kindLabels = ['色相', '饱和度', '明亮度'];

  int _range = 0;
  int _kind = 1; // default to Saturation (most used)

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(editorProvider.notifier);
    final adj = ref.watch(editorProvider).edit.adjustments;
    final value = switch (_kind) {
      0 => adj.hslHue[_range],
      2 => adj.hslLum[_range],
      _ => adj.hslSat[_range],
    };

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              for (var i = 0; i < _ranges.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_ranges[i]),
                    selected: _range == i,
                    onSelected: (_) => setState(() => _range = i),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SegmentedButton<int>(
            segments: List.generate(
              _kindLabels.length,
              (i) => ButtonSegment(value: i, label: Text(_kindLabels[i])),
            ),
            selected: {_kind},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
        ),
        ParamSlider(
          label: '${_ranges[_range]} · ${_kindLabels[_kind]}',
          value: value,
          min: -1,
          max: 1,
          onChanged: (v) =>
              controller.updateAdjustment((a) => a.setHsl(_range, _kinds[_kind], v)),
          onCommit: controller.commit,
        ),
      ],
    );
  }
}

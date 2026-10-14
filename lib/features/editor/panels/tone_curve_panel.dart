import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/editor_provider.dart';
import '../widgets/param_slider.dart';

/// Camera Raw "Tone Curve" panel — parametric 4-region model per channel.
///
/// The four controls (shadows / mid1 / mid2 / highlights) drive
/// [Adjustments.curveRgb|Red|Green|Blue], which the native pipeline bakes into a
/// 1D LUT mirrored identically on CPU export (see gl/lut_builder.cpp).
class ToneCurvePanel extends ConsumerStatefulWidget {
  const ToneCurvePanel({super.key});

  @override
  ConsumerState<ToneCurvePanel> createState() => _ToneCurvePanelState();
}

class _ToneCurvePanelState extends ConsumerState<ToneCurvePanel> {
  static const _channels = <String, String>{
    'rgb': 'RGB',
    'red': '红',
    'green': '绿',
    'blue': '蓝',
  };
  static const _regions = ['阴影', '中间调 1', '中间调 2', '高光'];

  String _channel = 'rgb';

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(editorProvider.notifier);
    final adj = ref.watch(editorProvider).edit.adjustments;
    final curve = switch (_channel) {
      'red' => adj.curveRed,
      'green' => adj.curveGreen,
      'blue' => adj.curveBlue,
      _ => adj.curveRgb,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              const Text('通道'),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<String>(
                  segments: _channels.entries
                      .map((e) => ButtonSegment(value: e.key, label: Text(e.value)))
                      .toList(),
                  selected: {_channel},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _channel = s.first),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              for (var i = 0; i < _regions.length; i++)
                ParamSlider(
                  label: _regions[i],
                  value: curve[i],
                  min: -1,
                  max: 1,
                  onChanged: (v) => controller.updateAdjustment(
                      (a) => a.setCurve(_channel, i, v)),
                  onCommit: controller.commit,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

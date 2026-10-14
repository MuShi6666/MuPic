import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/models/adjustments.dart';
import '../../../state/editor_provider.dart';
import '../widgets/liquify_overlay.dart';
import '../widgets/param_slider.dart';

/// 液化 panel: five PS-style brushes (向前变形 / 复位 / 膨胀 / 收缩 / 旋转)
/// plus brush size and strength sliders.
///
/// The selected tool and the two brush parameters are *transient UI state*
/// owned by [EditorScreen] (they never enter [EditState] / history); only the
/// impulses they generate are serialized (via [Adjustments.warp]). The panel
/// just reads / writes those through the callbacks handed in by the screen.
class LiquifyPanel extends ConsumerWidget {
  const LiquifyPanel({
    super.key,
    required this.brush,
    required this.onBrushChanged,
    required this.brushSize,
    required this.onBrushSizeChanged,
    required this.strength,
    required this.onStrengthChanged,
  });

  final LiquifyBrush brush;
  final ValueChanged<LiquifyBrush> onBrushChanged;
  final double brushSize; // 0..1
  final ValueChanged<double> onBrushSizeChanged;
  final double strength; // 0..1
  final ValueChanged<double> onStrengthChanged;

  static const _tools = <_LiquifyTool>[
    _LiquifyTool(LiquifyBrush.push, '向前变形', PhosphorIconsRegular.hand),
    _LiquifyTool(
        LiquifyBrush.reconstruct, '复位', PhosphorIconsRegular.arrowCounterClockwise),
    _LiquifyTool(LiquifyBrush.twirl, '旋转', PhosphorIconsRegular.arrowsClockwise),
    _LiquifyTool(LiquifyBrush.bloat, '膨胀', PhosphorIconsRegular.plusCircle),
    _LiquifyTool(LiquifyBrush.pucker, '收缩', PhosphorIconsRegular.minusCircle),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fluent;
    final controller = ref.read(editorProvider.notifier);
    final state = ref.watch(editorProvider);
    final adj = state.edit.adjustments;
    final warpCount = adj.warp.length;
    // 45 = the fixed face-mesh point count the native engine needs.
    final faceDetected = state.faceCount >= 45;

    String pct(double v) => (v * 100).round().toString();

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('画笔',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                warpCount == 0 ? '尚无形变' : '$warpCount / $kMaxWarp 笔触',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final tool in _tools)
                Expanded(
                  child: _ToolButton(
                    tool: tool,
                    selected: brush == tool.brush,
                    accent: t.accent,
                    onAccent: t.onAccent,
                    onTap: () => onBrushChanged(tool.brush),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ParamSlider(
          label: '画笔大小',
          value: brushSize.clamp(0.0, 1.0),
          min: 0,
          max: 1,
          format: pct,
          onChanged: onBrushSizeChanged,
          onCommit: () {},
        ),
        ParamSlider(
          label: '强度',
          value: strength.clamp(0.0, 1.0),
          min: 0,
          max: 1,
          format: pct,
          onChanged: onStrengthChanged,
          onCommit: () {},
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
          child: Text(
            '在画面上拖动即可形变；“复位”擦除笔刷下的形变。导出一比一还原。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: t.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('人脸液化',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              Text(
                faceDetected ? '已识别人脸' : '未检测到人脸',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
        if (faceDetected) ...[
          ParamSlider(
            label: '瘦脸',
            value: adj.faceSlim.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            format: pct,
            onChanged: (v) => controller.updateAdjustment((a) => a.copyWith(faceSlim: v)),
            onCommit: controller.commit,
          ),
          ParamSlider(
            label: '大眼',
            value: adj.faceEye.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            format: pct,
            onChanged: (v) => controller.updateAdjustment((a) => a.copyWith(faceEye: v)),
            onCommit: controller.commit,
          ),
          ParamSlider(
            label: '塑鼻',
            value: adj.faceNose.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            format: pct,
            onChanged: (v) => controller.updateAdjustment((a) => a.copyWith(faceNose: v)),
            onCommit: controller.commit,
          ),
          ParamSlider(
            label: '尖下巴',
            value: adj.faceChin.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            format: pct,
            onChanged: (v) => controller.updateAdjustment((a) => a.copyWith(faceChin: v)),
            onCommit: controller.commit,
          ),
        ] else
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
            child: Text(
              '进入本面板会自动检测人脸；未检测到时可继续用上方手动画笔。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: t.textSecondary),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: OutlinedButton.icon(
            onPressed: warpCount == 0
                ? null
                : () {
                    controller.updateAdjustment((a) => a.withWarp(const []));
                    controller.commit();
                  },
            icon: const Icon(PhosphorIconsRegular.trash, size: 18),
            label: const Text('清空液化'),
          ),
        ),
      ],
    );
  }
}

/// A single tool entry (brush enum + Chinese label + icon) for the panel row.
class _LiquifyTool {
  const _LiquifyTool(this.brush, this.label, this.icon);
  final LiquifyBrush brush;
  final String label;
  final IconData icon;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.selected,
    required this.accent,
    required this.onAccent,
    required this.onTap,
  });

  final _LiquifyTool tool;
  final bool selected;
  final Color accent;
  final Color onAccent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fluent;
    final fg = selected ? onAccent : t.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(MuPicPalette.radiusMd),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? accent : t.glassTint,
          borderRadius: BorderRadius.circular(MuPicPalette.radiusMd),
          border: Border.all(color: selected ? accent : t.glassBorder),
        ),
        child: Column(
          children: [
            Icon(tool.icon, size: 22, color: fg),
            const SizedBox(height: 5),
            Text(
              tool.label,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

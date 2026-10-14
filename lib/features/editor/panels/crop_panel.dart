import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/theme.dart';
import '../../../state/app_state.dart';
import '../../../state/editor_provider.dart';

/// Camera-Raw style "Crop" panel: aspect-ratio presets, 90° rotation and a
/// reset. The crop rectangle itself is dragged on the canvas via [CropOverlay]
/// (wired up in EditorScreen); this panel only constrains / transforms it.
///
/// Semantics (mirrors the native pipeline): the normalized rect lives in
/// *source* space and `cropTurns` quarter-turns are applied to the cropped
/// region. A rotate press therefore bumps the turn count AND rotates the rect
/// so the exported result keeps matching what the user framed.
class CropPanel extends ConsumerWidget {
  const CropPanel({super.key});

  static const List<(String, double?)> _presets = [
    ('自由', null),
    ('原始', 0), // 0 = "use the source aspect"
    ('1:1', 1),
    ('4:3', 4 / 3),
    ('3:2', 3 / 2),
    ('16:9', 16 / 9),
    ('9:16', 9 / 16),
    ('4:5', 4 / 5),
  ];

  /// Largest box with pixel ratio [aspect] centered in the frame.
  static Rect centeredRatio(double aspect, double sourceAspect) {
    final double wn, hn;
    if (aspect >= sourceAspect) {
      wn = 1;
      hn = sourceAspect / aspect;
    } else {
      hn = 1;
      wn = aspect / sourceAspect;
    }
    final l = (1 - wn) / 2, t = (1 - hn) / 2;
    return Rect.fromLTRB(l, t, l + wn, t + hn);
  }

  void _applyPreset(WidgetRef ref, double? raw) {
    final controller = ref.read(editorProvider.notifier);
    final state = ref.read(editorProvider);
    final sourceAspect = state.sourceAspect > 0 ? state.sourceAspect : 1.0;
    final aspect = raw == null ? null : (raw == 0 ? sourceAspect : raw);
    ref.read(cropAspectProvider.notifier).state = aspect;
    if (aspect == null) return; // free: keep the current box untouched
    final box = centeredRatio(aspect, sourceAspect);
    controller.updateAdjustment((a) => a.copyWith(
          cropLeft: box.left,
          cropTop: box.top,
          cropRight: box.right,
          cropBottom: box.bottom,
        ));
    controller.commit();
  }

  void _rotate(WidgetRef ref) {
    final controller = ref.read(editorProvider.notifier);
    controller.updateAdjustment((a) {
      // Rotate the framed rect 90° clockwise together with the output.
      final rotated = Rect.fromLTRB(
        1 - a.cropBottom,
        a.cropLeft,
        1 - a.cropTop,
        a.cropRight,
      );
      return a.copyWith(
        cropTurns: (a.cropTurns + 1).remainder(4),
        cropLeft: rotated.left,
        cropTop: rotated.top,
        cropRight: rotated.right,
        cropBottom: rotated.bottom,
      );
    });
    controller.commit();
  }

  void _reset(WidgetRef ref) {
    final controller = ref.read(editorProvider.notifier);
    ref.read(cropAspectProvider.notifier).state = null;
    controller.updateAdjustment((a) => a.withCropNeutralized());
    controller.commit();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fluent;
    final scheme = Theme.of(context).colorScheme;
    final selected = ref.watch(cropAspectProvider);
    final state = ref.watch(editorProvider);
    final adj = state.edit.adjustments;
    final sourceAspect = state.sourceAspect > 0 ? state.sourceAspect : 1.0;
    double? presetAspect(double? raw) =>
        raw == null ? null : (raw == 0 ? sourceAspect : raw);
    final cropped = adj.cropLeft > 1e-6 ||
        adj.cropTop > 1e-6 ||
        adj.cropRight < 1 - 1e-6 ||
        adj.cropBottom < 1 - 1e-6 ||
        adj.cropTurns > 0;

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
          child: Text(
            '拖动画面上的裁切框调整范围，点击下方比例锁定形状。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: t.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, value) in _presets)
                ChoiceChip(
                  label: Text(label),
                  selected: selected == presetAspect(value),
                  onSelected: (_) => _applyPreset(ref, value),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected == presetAspect(value)
                        ? scheme.onPrimary
                        : t.textPrimary,
                  ),
                  backgroundColor: t.subtle,
                  selectedColor: scheme.primary,
                  showCheckmark: false,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(MuPicPalette.radiusMd),
                    side: BorderSide(color: t.divider),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rotate(ref),
                  icon: const Icon(PhosphorIconsRegular.arrowClockwise,
                      size: 20),
                  label: const Text('旋转 90°'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: cropped
                      ? () => _reset(ref)
                      : null,
                  icon: const Icon(PhosphorIconsRegular.arrowsClockwise,
                      size: 20),
                  label: const Text('重置裁切'),
                ),
              ),
            ],
          ),
        ),
        if (adj.cropTurns > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: Text(
              '已旋转 ${(adj.cropTurns * 90).round()}°，离开本页后画面生效。',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: t.textSecondary),
            ),
          ),
      ],
    );
  }
}

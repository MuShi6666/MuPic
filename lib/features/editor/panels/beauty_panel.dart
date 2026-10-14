import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app/theme.dart';
import '../../../core/models/adjustments.dart';
import '../../../state/editor_provider.dart';
import '../widgets/param_slider.dart';

/// 美颜 panel: edge-preserving skin smoothing (磨皮) + whitening lift (美白)
/// + tap-to-place blemish retouching (祛瑕).
///
/// The native CPU pipeline blurs the graded image, then pulls only *flat*
/// regions toward the blur, so skin evens out while eyes / lips / hairline
/// edges stay sharp. Retouch spots are normalized (x, y, r) triples: double
/// taps on the canvas add them (handled by EditorScreen); each is filled with
/// the median of a ring sampled just outside its radius.
class BeautyPanel extends ConsumerWidget {
  const BeautyPanel({super.key});

  static const double defaultSpotR = 0.02; // 2% of the shorter image edge

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.fluent;
    final controller = ref.read(editorProvider.notifier);
    final adj = ref.watch(editorProvider).edit.adjustments;

    String pct(double v) => (v * 100).round().toString();

    Widget norm(String label, double value, void Function(double) set,
        {double min = 0, double max = 1}) {
      return ParamSlider(
        label: label,
        value: value.clamp(min, max),
        min: min,
        max: max,
        format: pct,
        onChanged: set,
        onCommit: controller.commit,
      );
    }

    final spots = adj.spots;

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        norm(
          '磨皮',
          adj.beautySmooth,
          (v) => controller.updateAdjustment((a) => a.copyWith(beautySmooth: v)),
        ),
        norm(
          '磨皮范围',
          adj.beautyRadius,
          (v) => controller.updateAdjustment((a) => a.copyWith(beautyRadius: v)),
        ),
        norm(
          '美白',
          adj.beautyWhitening,
          (v) =>
              controller.updateAdjustment((a) => a.copyWith(beautyWhitening: v)),
        ),
        norm(
          '美白仅肤色',
          adj.beautyWhiteSkin,
          (v) =>
              controller.updateAdjustment((a) => a.copyWith(beautyWhiteSkin: v)),
        ),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
          child: Row(
            children: [
              Icon(PhosphorIconsRegular.sparkle, size: 18, color: t.accent),
              const SizedBox(width: 6),
              Text('祛瑕',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                spots.isEmpty ? '暂无瑕点' : '${spots.length} / $kMaxRetouchSpots',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Text(
            '在本页时，双击画面上的痘点 / 瑕疵即可就地修复。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: t.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: spots.isEmpty
                      ? null
                      : () {
                          controller.updateAdjustment((a) => a.withSpots(
                              List<RetouchSpot>.of(a.spots)..removeLast()));
                          controller.commit();
                        },
                  icon: const Icon(PhosphorIconsRegular.arrowUUpLeft,
                      size: 18),
                  label: const Text('撤销上一点'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: spots.isEmpty
                      ? null
                      : () {
                          controller
                              .updateAdjustment((a) => a.withSpots(const []));
                          controller.commit();
                        },
                  icon: const Icon(PhosphorIconsRegular.trash, size: 18),
                  label: const Text('清空'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'dart:ui' as ui;

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme.dart';
import '../../app/widgets/glass.dart';
import '../../core/models/presets.dart';
import '../../state/app_state.dart';
import '../../state/editor_provider.dart';

/// Filters page: one-tap presets applied to the image currently open on the
/// Edit tab. Shows the live preview on top so the effect reads as connected.
class FiltersScreen extends ConsumerWidget {
  const FiltersScreen({super.key});

  void _apply(BuildContext context, WidgetRef ref, FilterPreset preset) {
    ref.read(editorProvider.notifier).applyAdjustments(preset.adjustments);
    ref.read(navIndexProvider.notifier).state = 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已应用「${preset.name}」滤镜')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorProvider);
    final hasImage = state.imageId != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('滤镜'),
        actions: [
          if (hasImage)
            IconButton(
              tooltip: '保存',
              icon: const Icon(PhosphorIconsRegular.floppyDisk),
              onPressed: () async {
                await ref.read(editorProvider.notifier).saveToDisk();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已保存，切回编辑不丢失')),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: hasImage
            ? Column(
                children: [
                  _previewBanner(state.preview),
                  Expanded(
                    child: CarouselSlider.builder(
                      itemCount: kFilterPresets.length,
                      options: CarouselOptions(
                        height: 220,
                        viewportFraction: 0.62,
                        enableInfiniteScroll: false,
                        enlargeCenterPage: true,
                      ),
                      itemBuilder: (context, i, _) {
                        final preset = kFilterPresets[i];
                        return _presetCard(context, ref, preset);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 96),
                    child: Text(
                      '左右滑动挑选滤镜，点卡片即可应用',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: context.fluent.textSecondary),
                    ),
                  ),
                ],
              )
            : _noImage(context, ref),
      ),
    );
  }

  Widget _previewBanner(ui.Image? image) {
    return Container(
      height: 200,
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: MuPicPalette.canvasDark,
        borderRadius: BorderRadius.circular(MuPicPalette.radiusLg),
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? const Center(
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
          : RawImage(image: image, fit: BoxFit.contain),
    );
  }

  Widget _presetCard(BuildContext context, WidgetRef ref, FilterPreset preset) {
    final t = context.fluent;
    return GestureDetector(
      onTap: () => _apply(context, ref, preset),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: preset.colors,
          ),
          borderRadius: BorderRadius.circular(MuPicPalette.radiusLg),
        ),
        alignment: Alignment.bottomLeft,
        child: Stack(
          children: [
            Positioned(
              left: 16,
              bottom: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: t.glassTint,
                  borderRadius:
                      BorderRadius.circular(MuPicPalette.radiusPill),
                  border: Border.all(color: t.glassBorder),
                ),
                child: Text(
                  preset.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: t.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _noImage(BuildContext context, WidgetRef ref) {
    final t = context.fluent;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        child: GlassSurface(
          blur: MuPicPalette.blurStrong,
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.sparkle,
                  size: 56, color: t.accent),
              const SizedBox(height: 14),
              Text('先打开一张图片',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('滤镜会应用到当前编辑的图片上。去相册挑一张照片试试吧。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => ref.read(navIndexProvider.notifier).state = 0,
                icon: const Icon(PhosphorIconsRegular.images),
                label: const Text('去相册'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

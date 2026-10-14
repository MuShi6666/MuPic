import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../app/theme.dart';
import '../../app/widgets/glass.dart';
import '../../bridge/preview_texture.dart';
import '../../core/models/adjustments.dart';
import '../../state/app_state.dart';
import '../../state/editor_provider.dart';
import 'panels/basic_panel.dart';
import 'panels/beauty_panel.dart';
import 'panels/crop_panel.dart';
import 'panels/detail_panel.dart';
import 'panels/grading_panel.dart';
import 'panels/hsl_panel.dart';
import 'panels/lens_panel.dart';
import 'panels/liquify_panel.dart';
import 'panels/tone_curve_panel.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/liquify_overlay.dart';

/// Edit page: a neutral dark canvas (accurate color judgment) hosting the CPU
/// preview, a floating pastel pill toolbar, and the Camera Raw panels docked in
/// a rounded sheet. Reacts to [currentImagePathProvider] to open images chosen
/// on the Album page.
class EditorScreen extends ConsumerStatefulWidget {
  const EditorScreen({super.key});

  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen>
    with SingleTickerProviderStateMixin {
  static const int _beautyTab = 6;
  static const int _liquifyTab = 8;
  static const int _cropTab = 7;

  String? _openedPath;
  late final TabController _tab;

  // Pinch-zoom transform for the preview canvas. Shared so entering crop /
  // beauty tabs or opening a new image can reset it to 1:1 (those tabs drive
  // their own gestures and rely on un-zoomed imgRect coordinates).
  final TransformationController _tfc = TransformationController();

  // Transient liquify brush settings — deliberately NOT part of EditState /
  // history (only the impulses they emit are). Reset when leaving the tab.
  LiquifyBrush _liquifyBrush = LiquifyBrush.push;
  double _liquifySize = 0.5;
  double _liquifyStrength = 0.5;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 9, vsync: this);
    _tab.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIfChanged());
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    _tfc.dispose();
    super.dispose();
  }

  /// Entering the crop tab shows the *full* frame (crop neutralized in the
  /// native preview) so the overlay can be dragged against the whole image;
  /// leaving it re-renders the cropped result.
  void _onTabChanged() {
    if (!_tab.indexIsChanging) return; // fire once per committed switch
    _tfc.value = Matrix4.identity();
    setState(() {});
    ref.read(editorProvider.notifier).setCropEditing(_tab.index == _cropTab);
    // Entering the liquify tab auto-runs FaceMesh so the guide + 4 auto sliders
    // light up (and so a restored session re-seeds the recomputable keypoints).
    if (_tab.index == _liquifyTab) {
      ref.read(editorProvider.notifier).detectFace();
    }
  }

  void _openIfChanged() {
    final path = ref.read(currentImagePathProvider);
    if (path != null && path != _openedPath) {
      _openedPath = path;
      _tfc.value = Matrix4.identity();
      ref.read(editorProvider.notifier).openImage(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentImagePathProvider, (prev, next) => _openIfChanged());
    final state = ref.watch(editorProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: state.imageId == null ? _EmptyState() : _editor(state),
      ),
    );
  }

  Widget _editor(EditorUiState state) {
    final controller = ref.read(editorProvider.notifier);
    return Column(
      children: [
        _Toolbar(
          state: state,
          onUndo: controller.undo,
          onRedo: controller.redo,
          onReset: controller.reset,
          onSave: _save,
          onExport: _export,
        ),
        Expanded(
          child: Container(
            color: MuPicPalette.canvasDark,
            child: _canvas(state),
          ),
        ),
        if (state.error != null)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.all(10),
            child: Text(
              state.error!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer),
            ),
          ),
        _panelSheet(),
      ],
    );
  }

  /// Persist the current edit set for the open image; survives a relaunch and
  /// is restored automatically the next time this exact image is opened.
  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(editorProvider.notifier).saveToDisk();
    messenger.showSnackBar(
      const SnackBar(content: Text('已保存，重开此图会自动恢复')), );
  }

  /// Asks for an output format, then renders at full resolution and saves the
  /// result to the gallery (Pictures/MuPic). Reports the outcome via a snack bar.
  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(editorProvider.notifier);
    final t = context.fluent;
    final format = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text('导出图片',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(PhosphorIconsRegular.fileImage, color: t.accent),
              title: const Text('JPEG（高质量，体积小）'),
              onTap: () => Navigator.pop(ctx, 'jpeg'),
            ),
            ListTile(
              leading: Icon(PhosphorIconsRegular.fileImage, color: t.accent2),
              title: const Text('PNG（无损，体积大）'),
              onTap: () => Navigator.pop(ctx, 'png'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (format == null) return;

    messenger.showSnackBar(const SnackBar(content: Text('正在全分辨率导出…')));
    final saved = await controller.exportImage(format: format);
    messenger.showSnackBar(SnackBar(
      content: Text(saved != null
          ? '已导出到相册 Pictures/MuPic'
          : '导出失败，请重试'),
    ));
  }

  /// The preview canvas. Normally just the preview frame centered; while the
  /// crop tab is open it shows the uncropped frame plus a [CropOverlay], and
  /// while the beauty tab is open it accepts double-taps as retouch spots.
  Widget _canvas(EditorUiState state) {
    final controller = ref.read(editorProvider.notifier);
    final adj = state.edit.adjustments;
    final cropping = _tab.index == _cropTab;
    final beautying = _tab.index == _beautyTab;
    final liquifying = _tab.index == _liquifyTab;
    // During crop editing the native frame is the full source; pin the canvas
    // to the source aspect so the overlay stays put even mid-re-render.
    final aspect = cropping && state.sourceAspect > 0
        ? state.sourceAspect
        : (state.aspectRatio > 0 ? state.aspectRatio : 1.0);

    return LayoutBuilder(builder: (context, cons) {
      var w = cons.maxWidth;
      var h = w / aspect;
      if (h > cons.maxHeight) {
        h = cons.maxHeight;
        w = h * aspect;
      }
      final imgRect = Rect.fromLTWH(
        cons.maxWidth / 2 - w / 2,
        cons.maxHeight / 2 - h / 2,
        w,
        h,
      );

      final image = Positioned.fromRect(
        rect: imgRect,
        child: (state.busy && state.preview == null)
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : PreviewImage(image: state.preview, aspectRatio: aspect),
      );

      // Crop / beauty / liquify tabs drive their own gestures against an
      // un-zoomed imgRect, so they keep the plain stacked layout (no pinch) and
      // pin the overlay to the same rect as the frame.
      if (cropping || beautying || liquifying) {
        return Stack(children: [
          image,
          if (cropping)
            Positioned.fromRect(
              rect: imgRect,
              child: CropOverlay(
                rect: Rect.fromLTRB(adj.cropLeft, adj.cropTop, adj.cropRight,
                    adj.cropBottom),
                aspect: ref.watch(cropAspectProvider),
                onChanged: (r) => controller.updateAdjustment((a) => a.copyWith(
                      cropLeft: r.left,
                      cropTop: r.top,
                      cropRight: r.right,
                      cropBottom: r.bottom,
                    )),
                onCommit: controller.commit,
              ),
            ),
          if (beautying)
            Positioned.fromRect(
              rect: imgRect,
              child: _SpotLayer(
                adj: adj,
                boxSize: imgRect.size,
                onAddSpot: (srcNorm) {
                  controller.updateAdjustment((a) => a.withSpots(
                      [...a.spots,
                        RetouchSpot(srcNorm.dx, srcNorm.dy,
                            BeautyPanel.defaultSpotR)]));
                  controller.commit();
                },
              ),
            ),
          if (liquifying)
            Positioned.fromRect(
              rect: imgRect,
              child: LiquifyOverlay(
                adj: adj,
                boxSize: imgRect.size,
                srcAspect: state.sourceAspect > 0
                    ? state.sourceAspect
                    : aspect,
                brush: _liquifyBrush,
                brushSize: _liquifySize,
                strength: _liquifyStrength,
                warp: adj.warp,
                facePts: state.facePts,
                onChanged: (list) =>
                    controller.updateAdjustment((a) => a.withWarp(list)),
                onCommit: controller.commit,
              ),
            ),
        ]);
      }

      // All other tabs: the canvas is inspection-only, so let two fingers
      // pinch-zoom / pan the preview for close-up retouching.
      return InteractiveViewer(
        transformationController: _tfc,
        minScale: 1.0,
        maxScale: 6.0,
        child: Stack(children: [image]),
      );
    });
  }

  Widget _panelSheet() {
    final scheme = Theme.of(context).colorScheme;
    final t = context.fluent;
    return GlassSurface(
      radius: const BorderRadius.vertical(
          top: Radius.circular(MuPicPalette.radiusLg)),
      blur: MuPicPalette.blurStrong,
      child: SizedBox(
        height: 300,
        child: Column(
          children: [
            const SizedBox(height: 6),
            TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: scheme.primary,
              unselectedLabelColor: t.textSecondary,
              indicatorColor: scheme.primary,
              indicatorWeight: 3,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
              tabs: const [
                Tab(text: '基础'),
                Tab(text: '曲线'),
                Tab(text: '颜色'),
                Tab(text: '调色'),
                Tab(text: '细节'),
                Tab(text: '镜头'),
                Tab(text: '美颜'),
                Tab(text: '裁剪'),
                Tab(text: '液化'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  const BasicPanel(),
                  const ToneCurvePanel(),
                  const HslPanel(),
                  const GradingPanel(),
                  const DetailPanel(),
                  const LensPanel(),
                  const BeautyPanel(),
                  const CropPanel(),
                  LiquifyPanel(
                    brush: _liquifyBrush,
                    onBrushChanged: (b) => setState(() => _liquifyBrush = b),
                    brushSize: _liquifySize,
                    onBrushSizeChanged: (v) => setState(() => _liquifySize = v),
                    strength: _liquifyStrength,
                    onStrengthChanged: (v) =>
                        setState(() => _liquifyStrength = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Beauty-tab layer: double-tap adds a retouch spot; existing spots render as
/// rings. Display (cropped / rotated) coordinates are mapped back into source
/// space so the native spot semantics (normalized to the *source* image) hold
/// regardless of the current crop / turns.
class _SpotLayer extends StatelessWidget {
  const _SpotLayer({
    required this.adj,
    required this.boxSize,
    required this.onAddSpot,
  });

  final Adjustments adj;
  final Size boxSize;
  final void Function(Offset srcNorm) onAddSpot;

  int get _turns => (adj.cropTurns.round() % 4 + 4) % 4;

  Offset _displayToSource(Offset pq) {
    final p = pq.dx.clamp(0.0, 1.0);
    final q = pq.dy.clamp(0.0, 1.0);
    final (a, b) = switch (_turns) {
      1 => (q, 1 - p),
      2 => (1 - p, 1 - q),
      3 => (1 - q, p),
      _ => (p, q),
    };
    return Offset(
      adj.cropLeft + a * (adj.cropRight - adj.cropLeft),
      adj.cropTop + b * (adj.cropBottom - adj.cropTop),
    );
  }

  Offset _sourceToDisplay(Offset xy) {
    final wSpan = adj.cropRight - adj.cropLeft;
    final hSpan = adj.cropBottom - adj.cropTop;
    if (wSpan <= 0 || hSpan <= 0) return const Offset(-1, -1);
    final a = (xy.dx - adj.cropLeft) / wSpan;
    final b = (xy.dy - adj.cropTop) / hSpan;
    return switch (_turns) {
      1 => Offset(1 - b, a),
      2 => Offset(1 - a, 1 - b),
      3 => Offset(b, 1 - a),
      _ => Offset(a, b),
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fluent;
    final marks = <Offset>[];
    for (final s in adj.spots) {
      final d = _sourceToDisplay(Offset(s.x, s.y));
      if (d.dx < 0 || d.dx > 1 || d.dy < 0 || d.dy > 1) continue;
      marks.add(Offset(d.dx * boxSize.width, d.dy * boxSize.height));
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTapDown: (d) => onAddSpot(_displayToSource(Offset(
        d.localPosition.dx / boxSize.width,
        d.localPosition.dy / boxSize.height,
      ))),
      child: CustomPaint(
        painter: _SpotPainter(marks: marks, color: t.accent),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SpotPainter extends CustomPainter {
  const _SpotPainter({required this.marks, required this.color});
  final List<Offset> marks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color.withValues(alpha: 0.18);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    for (final m in marks) {
      const r = 16.0;
      canvas
        ..drawCircle(m, r, fill)
        ..drawCircle(m, r, ring);
    }
  }

  @override
  bool shouldRepaint(_SpotPainter old) =>
      old.marks != marks || old.color != color;
}

/// Floating rounded toolbar with undo / redo / reset / export actions.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.state,
    required this.onUndo,
    required this.onRedo,
    required this.onReset,
    required this.onSave,
    required this.onExport,
  });

  final EditorUiState state;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onReset;
  final VoidCallback onSave;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: GlassSurface(
          radius: BorderRadius.circular(MuPicPalette.radiusPill),
          blur: MuPicPalette.blurStrong,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            children: [
              _icon(PhosphorIconsRegular.arrowCounterClockwise,
                  enabled: state.canUndo, onTap: onUndo),
              _icon(PhosphorIconsRegular.arrowClockwise,
                  enabled: state.canRedo, onTap: onRedo),
              _icon(PhosphorIconsRegular.arrowsClockwise,
                  enabled: !state.edit.isNeutral, onTap: onReset),
              const Spacer(),
              Text('MuPic 编辑',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              _icon(PhosphorIconsRegular.floppyDisk,
                  enabled: !state.edit.isNeutral, onTap: onSave),
              _icon(PhosphorIconsRegular.downloadSimple,
                  enabled: true, onTap: onExport),
            ],
          ),
        ),
      ),
    );
  }

  Widget _icon(IconData icon, {required bool enabled, required VoidCallback onTap}) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 22),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Shown on the Edit tab before any image is chosen.
class _EmptyState extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              Icon(PhosphorIconsRegular.magicWand,
                  size: 56, color: t.accent),
              const SizedBox(height: 14),
              Text('还没有打开图片',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('去相册选一张照片，或导入 JPG / PNG / RAW 开始编辑。',
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

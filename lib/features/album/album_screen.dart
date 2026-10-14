import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme.dart';
import '../../app/widgets/glass.dart';
import '../../state/app_state.dart';

/// Album page: device photo grid (photo_manager) plus a reliable "import"
/// entry (file_picker) that also covers RAW files not indexed by MediaStore.
/// Tapping any image opens it in the Edit tab.
class AlbumScreen extends ConsumerStatefulWidget {
  const AlbumScreen({super.key});

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  static const _extensions = [
    'jpg', 'jpeg', 'png', //
    'cr2', 'cr3', 'nef', 'arw', 'raf', 'orf', 'rw2', 'dng', 'pef', 'srw', 'raw'
  ];

  List<AssetEntity> _assets = const [];
  bool _loading = true;
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final perm = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    final granted = perm.isAuth || perm.hasAccess;
    setState(() => _granted = granted);
    if (!granted) {
      setState(() => _loading = false);
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
    );
    if (albums.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final list = await albums.first.getAssetListPaged(page: 0, size: 120);
    if (!mounted) return;
    setState(() {
      _assets = list;
      _loading = false;
    });
  }

  void _openPath(String path) {
    ref.read(currentImagePathProvider.notifier).state = path;
    ref.read(navIndexProvider.notifier).state = 1;
  }

  Future<void> _importViaPicker() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _extensions,
    );
    final path = result?.files.first.path;
    if (path != null) _openPath(path);
  }

  Future<void> _openAsset(AssetEntity e) async {
    final file = await e.originFile ?? await e.file;
    if (file == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法读取该图片文件')),
        );
      }
      return;
    }
    _openPath(file.path);
  }

  IconData _themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.light => PhosphorIconsRegular.sun,
        ThemeMode.dark => PhosphorIconsRegular.moon,
        _ => PhosphorIconsRegular.monitor,
      };

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
        _ => '跟随系统',
      };

  /// Update the in-memory theme and persist the choice across launches.
  Future<void> _setTheme(ThemeMode mode) async {
    ref.read(themeModeProvider.notifier).state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(themeModeStorageKey, mode.name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importViaPicker,
        icon: const Icon(PhosphorIconsRegular.plus),
        label: const Text('导入图片'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final t = context.fluent;
    final mode = ref.watch(themeModeProvider);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      decoration: BoxDecoration(
        gradient: t.banner,
        borderRadius: BorderRadius.circular(MuPicPalette.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MuPic',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700, color: Colors.white)),
                const SizedBox(height: 6),
                Text('挑一张照片，开始你的调色之旅',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92))),
              ],
            ),
          ),
          PopupMenuButton<ThemeMode>(
            color: t.layer,
            icon: Icon(_themeIcon(mode), color: Colors.white),
            tooltip: '主题：${_themeLabel(mode)}',
            position: PopupMenuPosition.under,
            onSelected: _setTheme,
            itemBuilder: (ctx) => [
              for (final m in ThemeMode.values)
                PopupMenuItem<ThemeMode>(
                  value: m,
                  child: Row(
                    children: [
                      Icon(_themeIcon(m),
                          color: m == mode ? t.accent : t.textSecondary),
                      const SizedBox(width: 12),
                      Text(
                        _themeLabel(m),
                        style: TextStyle(
                            color: t.textPrimary,
                            fontWeight: m == mode
                                ? FontWeight.w700
                                : FontWeight.w400),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.15, curve: Curves.easeOutCubic);
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_granted) {
      return _emptyCard(
        icon: PhosphorIconsRegular.camera,
        title: '还没有相册权限',
        desc: '授权后可浏览本机照片，或直接用右下角「导入图片」选择照片。',
      );
    }
    if (_assets.isEmpty) {
      return _emptyCard(
        icon: PhosphorIconsRegular.imageSquare,
        title: '相册是空的',
        desc: '这台设备暂时没有照片。点右下角「导入图片」选择 JPG / PNG / RAW 开始编辑。',
      );
    }
    return MasonryGridView.count(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      itemCount: _assets.length,
      itemBuilder: (context, i) {
        final e = _assets[i];
        return GestureDetector(
          onTap: () => _openAsset(e),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MuPicPalette.radiusMd),
            child: AspectRatio(
              aspectRatio: 1,
              child: _thumb(e),
            ),
          ),
        );
      },
    );
  }

  Widget _thumb(AssetEntity e) {
    final t = context.fluent;
    return FutureBuilder<Uint8List?>(
      future: e.thumbnailDataWithSize(const ThumbnailSize(320, 320)),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(color: t.subtle);
        }
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            color: t.layerAlt,
            child: Icon(PhosphorIconsRegular.image, color: t.textSecondary),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }

  Widget _emptyCard({required IconData icon, required String title, required String desc}) {
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
              Icon(icon, size: 56, color: t.accent),
              const SizedBox(height: 14),
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(desc,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

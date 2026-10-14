import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../features/album/album_screen.dart';
import '../features/editor/editor_screen.dart';
import '../features/filters/filters_screen.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets/glass.dart';

/// App shell: three pages (Album / Edit / Filters) held in an [IndexedStack] so
/// each keeps its state, with a cute pastel [GNav] bubble bottom bar.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(navIndexProvider);
    final t = context.fluent;

    return Stack(
      children: [
        // One shared ambient mesh backdrop for all three tabs; the glass
        // surfaces blur whatever shows through them from this layer.
        const AmbientBackground(),
        Positioned.fill(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: IndexedStack(
              index: index,
              children: const [
                AlbumScreen(),
                EditorScreen(),
                FiltersScreen(),
              ],
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: GlassSurface(
                radius: BorderRadius.circular(MuPicPalette.radiusLg),
                blur: MuPicPalette.blurStrong,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: GNav(
                  backgroundColor: Colors.transparent,
                  rippleColor: t.glassBorder,
                  hoverColor: t.glassBorder,
                  color: t.textSecondary,
                  activeColor: t.onAccent,
                  iconSize: 22,
                  gap: 8,
                  tabBackgroundColor: t.accent,
                  tabBorderRadius: MuPicPalette.radiusMd,
                  curve: Curves.easeOutCubic,
                  duration: const Duration(milliseconds: 260),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  selectedIndex: index,
                  onTabChange: (i) =>
                      ref.read(navIndexProvider.notifier).state = i,
                  tabs: [
                    GButton(
                      icon: PhosphorIconsRegular.images,
                      text: '相册',
                    ),
                    GButton(
                      icon: PhosphorIconsRegular.magicWand,
                      text: '编辑',
                    ),
                    GButton(
                      icon: PhosphorIconsRegular.sparkle,
                      text: '滤镜',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

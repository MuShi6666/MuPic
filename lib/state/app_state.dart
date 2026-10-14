import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Selected bottom-navigation index for the app shell.
/// 0 = Album (相册), 1 = Edit (编辑), 2 = Filters (滤镜).
final navIndexProvider = StateProvider<int>((_) => 0);

/// The image currently open for editing, as an absolute file path, or null.
/// The Album / Filters pages set this; the Editor page reacts to it.
final currentImagePathProvider = StateProvider<String?>((_) => null);

/// Locked pixel aspect ratio (width / height) for the crop overlay while the
/// crop tab is open; null = free-form. Pure UI state (the render model only
/// stores the rect itself).
final cropAspectProvider = StateProvider<double?>((_) => null);

/// App theme mode. Persisted by the album header toggle via shared_preferences
/// (see main.dart bootstrap + `themeModeStorageKey`). Defaults to follow-system.
final themeModeProvider = StateProvider<ThemeMode>((_) => ThemeMode.system);

/// shared_preferences key for the persisted [themeModeProvider] value.
const String themeModeStorageKey = 'mupic.themeMode';

/// shared_preferences key prefix for per-image persisted edit states; the full
/// key is `editStoragePrefix + <absolute image path>` (see edit_persistence).
const String editStoragePrefix = 'mupic.edit.';

/// Parse a persisted theme-mode string back into a [ThemeMode].
ThemeMode themeModeFromName(String? name) => switch (name) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

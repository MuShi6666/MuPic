import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_shell.dart';
import 'app/theme.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the persisted theme choice before the first frame to avoid a flash.
  final prefs = await SharedPreferences.getInstance();
  final initialTheme = themeModeFromName(prefs.getString(themeModeStorageKey));

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith((_) => initialTheme),
      ],
      child: const MuPicApp(),
    ),
  );
}

/// Root of the MuPic image editor.
class MuPicApp extends ConsumerWidget {
  const MuPicApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'MuPic',
      debugShowCheckedModeBanner: false,
      theme: MuPicTheme.light,
      darkTheme: MuPicTheme.dark,
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/edit_state.dart';
import 'app_state.dart';

/// Per-image edit persistence for the explicit "保存" action.
///
/// The full [EditState] is serialized to JSON and stored in shared_preferences
/// keyed by the absolute image path, so reopening an image restores the last
/// saved look. This complements the additive filter merge: switching tabs never
/// loses in-memory edits, and saving makes them survive a relaunch.

/// Write [edit] for [path] to persistent storage.
Future<void> saveEdits(String path, EditState edit) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('$editStoragePrefix$path', jsonEncode(edit.toJson()));
}

/// Load the persisted [EditState] for [path], or null when none / unreadable.
Future<EditState?> loadEdits(String path) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('$editStoragePrefix$path');
  if (raw == null) return null;
  try {
    return EditState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

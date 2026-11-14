import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shortcut.dart';

class StoredSettings {
  const StoredSettings({required this.adBlockEnabled, required this.shortcuts});

  final bool adBlockEnabled;
  final List<Shortcut> shortcuts;
}

class SettingsRepository {
  static const String _kAdBlock = 'adblock_enabled';
  static const String _kShortcuts = 'shortcuts_json';

  Future<StoredSettings> load() async {
    final prefs = await SharedPreferences.getInstance();

    final shortcuts = <Shortcut>[];
    final raw = prefs.getString(_kShortcuts);
    if (raw != null) {
      try {
        for (final item in jsonDecode(raw) as List<dynamic>) {
          shortcuts.add(Shortcut.fromJson(Map<String, dynamic>.from(item as Map)));
        }
      } catch (e) {
        debugPrint('Could not read saved shortcuts: $e');
        shortcuts.clear();
      }
    }

    return StoredSettings(
      adBlockEnabled: prefs.getBool(_kAdBlock) ?? true, // ON by default
      shortcuts: shortcuts,
    );
  }

  Future<void> saveAdBlock(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAdBlock, value);
  }

  Future<void> saveShortcuts(List<Shortcut> shortcuts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kShortcuts,
      jsonEncode(shortcuts.map((s) => s.toJson()).toList()),
    );
  }
}
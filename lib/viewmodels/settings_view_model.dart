import 'package:flutter/foundation.dart';

import '../models/shortcut.dart';
import '../services/settings_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._repo);

  final SettingsRepository _repo;

  bool _isLoaded = false;
  bool _adBlockEnabled = true;
  List<Shortcut> _shortcuts = const [];
  int _webViewRevision = 0;

  bool get isLoaded => _isLoaded;
  bool get adBlockEnabled => _adBlockEnabled;
  List<Shortcut> get shortcuts => _shortcuts;

  /// Increases whenever a setting needs a fresh WebView (ad blocking on/off).
  int get webViewRevision => _webViewRevision;

  Future<void> load() async {
    final stored = await _repo.load();
    _adBlockEnabled = stored.adBlockEnabled;
    _shortcuts = stored.shortcuts;
    _isLoaded = true;
    notifyListeners();
  }

  Future<void> setAdBlock(bool value) async {
    if (value == _adBlockEnabled) return;
    _adBlockEnabled = value;
    _webViewRevision++; // HomePage rebuilds the WebView with/without the blocker
    notifyListeners();
    await _repo.saveAdBlock(value);
  }

  /// Returns false when the shortcut is already in the list.
  Future<bool> addShortcut(Shortcut shortcut) async {
    if (_shortcuts.any((s) => s.url == shortcut.url)) return false;
    _shortcuts = [..._shortcuts, shortcut];
    notifyListeners();
    await _repo.saveShortcuts(_shortcuts);
    return true;
  }

  Future<void> removeShortcut(Shortcut shortcut) async {
    _shortcuts = _shortcuts.where((s) => s.url != shortcut.url).toList();
    notifyListeners();
    await _repo.saveShortcuts(_shortcuts);
  }
}
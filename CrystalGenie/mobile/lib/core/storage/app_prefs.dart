import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-sensitive settings (SharedPreferences). Tokens never go here — see TokenStorage.
class AppPrefs {
  AppPrefs(this._prefs);
  final SharedPreferences _prefs;

  static const _kBaseUrl = 'base_url_override';
  static const _kSavedGrid = 'saved_grid_view';
  static const _kSeenScanTips = 'seen_scan_tips';
  static const _kLanguage = 'ui_language';

  String? get baseUrlOverride => _prefs.getString(_kBaseUrl);
  Future<void> setBaseUrlOverride(String? value) async {
    if (value == null) {
      await _prefs.remove(_kBaseUrl);
    } else {
      await _prefs.setString(_kBaseUrl, value);
    }
  }

  bool get savedGridView => _prefs.getBool(_kSavedGrid) ?? false;
  Future<void> setSavedGridView(bool v) => _prefs.setBool(_kSavedGrid, v);

  bool get seenScanTips => _prefs.getBool(_kSeenScanTips) ?? false;
  Future<void> setSeenScanTips(bool v) => _prefs.setBool(_kSeenScanTips, v);

  String? get language => _prefs.getString(_kLanguage);
  Future<void> setLanguage(String code) => _prefs.setString(_kLanguage, code);
}

/// Overridden in main() with the real SharedPreferences instance.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));
final appPrefsProvider = Provider<AppPrefs>((ref) => AppPrefs(ref.watch(sharedPreferencesProvider)));

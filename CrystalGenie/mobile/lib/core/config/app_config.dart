import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_prefs.dart';

/// Backend address.
///
/// * Android emulator: the default `http://10.0.2.2:8000` reaches the PC's localhost.
/// * Physical phone: run the backend with `--host 0.0.0.0` and use the PC's LAN IP, e.g.
///   `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000`
///   or change it in the app: Login screen → "Server settings".
abstract final class AppConfig {
  static const String defaultApiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
  static const Duration connectTimeout = Duration(seconds: 6);
  static const Duration receiveTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 90);
  static const int maxUploadBytes = 10 * 1024 * 1024;

  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return defaultApiBaseUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api')) url = url.substring(0, url.length - 4);
    return url;
  }

  static bool isValidBaseUrl(String raw) {
    final uri = Uri.tryParse(normalizeBaseUrl(raw));
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }
}

/// Current server origin (without `/api`). Persisted in SharedPreferences.
class BaseUrlNotifier extends StateNotifier<String> {
  BaseUrlNotifier(this._prefs) : super(_prefs.baseUrlOverride ?? AppConfig.defaultApiBaseUrl);
  final AppPrefs _prefs;

  Future<void> set(String raw) async {
    final url = AppConfig.normalizeBaseUrl(raw);
    await _prefs.setBaseUrlOverride(url == AppConfig.defaultApiBaseUrl ? null : url);
    state = url;
  }

  Future<void> reset() => set(AppConfig.defaultApiBaseUrl);
}

final baseUrlProvider = StateNotifierProvider<BaseUrlNotifier, String>((ref) => BaseUrlNotifier(ref.watch(appPrefsProvider)));

/// Resolves relative URLs returned by the API (e.g. `/static/gemstones/garnet.jpg`).
String resolveUrl(String baseUrl, String? path) {
  if (path == null || path.isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '$baseUrl${path.startsWith('/') ? '' : '/'}$path';
}

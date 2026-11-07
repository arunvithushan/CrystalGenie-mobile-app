import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_prefs.dart';
import 'translations.dart';

/// App languages (same codes the backend stores in user_settings.language).
const supportedLanguages = {'en': 'English', 'si': 'සිංහල (Sinhala)', 'ta': 'தமிழ் (Tamil)'};

/// Current UI language. Persisted on the device so the app starts in the right language,
/// and synced with the account setting after sign-in (see CrystalGenieApp).
class LanguageNotifier extends StateNotifier<String> {
  LanguageNotifier(this._prefs) : super(_valid(_prefs.language));
  final AppPrefs _prefs;

  static String _valid(String? code) => supportedLanguages.containsKey(code) ? code! : 'en';

  Future<void> set(String code) async {
    final c = _valid(code);
    if (c == state) return;
    state = c;
    await _prefs.setLanguage(c);
  }
}

final languageProvider = StateNotifierProvider<LanguageNotifier, String>((ref) => LanguageNotifier(ref.watch(appPrefsProvider)));

/// Makes the language available to every widget; widgets that call [BuildContext.tr] rebuild when it changes.
class L10nScope extends InheritedWidget {
  const L10nScope({super.key, required this.language, required super.child});
  final String language;

  static String of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<L10nScope>()?.language ?? 'en';

  @override
  bool updateShouldNotify(L10nScope oldWidget) => oldWidget.language != language;
}

/// Looks up the translation of an English UI string. Missing translations fall back to English.
/// Placeholders like {name} are filled from [args].
String translate(String language, String english, [Map<String, Object?> args = const {}]) {
  var s = language == 'en' ? english : (translations[language]?[english] ?? english);
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

extension TrX on BuildContext {
  String tr(String english, [Map<String, Object?> args = const {}]) => translate(L10nScope.of(this), english, args);
}

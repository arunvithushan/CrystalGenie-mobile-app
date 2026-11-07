import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/l10n.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/profile/data/user_repository.dart';
import 'router.dart';
import 'theme.dart';

class CrystalGenieApp extends ConsumerWidget {
  const CrystalGenieApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final language = ref.watch(languageProvider);

    // After sign-in, apply the language saved on the account (so it follows the user to a new phone).
    ref.listen<AuthState>(authControllerProvider, (prev, next) async {
      if (next.isAuthenticated && prev?.isAuthenticated != true) {
        try {
          final settings = await ref.read(userRepositoryProvider).getSettings();
          await ref.read(languageProvider.notifier).set(settings.language);
        } catch (_) {
          // Offline or server error: keep the language stored on this device.
        }
      }
    });

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      child: MaterialApp.router(
        title: 'Crystal Genie',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        routerConfig: router,
        locale: Locale(language),
        supportedLocales: [for (final code in supportedLanguages.keys) Locale(code)],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (context, child) {
          // Respect user font scaling but cap it so the Figma layout stays intact.
          final mq = MediaQuery.of(context);
          return L10nScope(
            language: language,
            child: MediaQuery(
              data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.25)),
              child: child ?? const SizedBox(),
            ),
          );
        },
      ),
    );
  }
}

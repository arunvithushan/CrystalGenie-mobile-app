import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/reset_password_screen.dart';
import '../features/camera/presentation/camera_screen.dart';
import '../features/camera/presentation/preview_screen.dart';
import '../features/explore/presentation/explore_screen.dart';
import '../features/explore/presentation/gemstone_detail_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/pc_files/presentation/pc_browser_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/profile/presentation/settings_screens.dart';
import '../features/results/presentation/result_screen.dart';
import '../features/saved/presentation/saved_screen.dart';
import '../features/splash/splash_screen.dart';
import '../shared/models/models.dart';
import '../shared/widgets/bottom_nav.dart';
import '../shared/widgets/glass.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const register = '/register';
  static const forgot = '/forgot-password';
  static const reset = '/reset-password';
  static const home = '/home';
  static const explore = '/explore';
  static const saved = '/saved';
  static const scan = '/scan';
  static const preview = '/scan/preview';
  static const computer = '/scan/computer';
  static const profile = '/profile';
  static const notifications = '/profile/notifications';
  static const security = '/profile/security';
  static const language = '/profile/language';

  static String gem(String id) => '/explore/$id';
  static String result(String id) => '/result/$id';

  static const authRoutes = {login, register, forgot, reset};
}

/// Bridges Riverpod auth state to GoRouter's refreshListenable.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (prev?.status != next.status) notifyListeners();
    });
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);
  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final loc = state.matchedLocation;
      final isSplash = loc == Routes.splash;
      final isAuthRoute = Routes.authRoutes.contains(loc);
      if (auth.status == AuthStatus.unknown) return isSplash ? null : Routes.splash;
      if (!auth.isAuthenticated) return isAuthRoute ? null : Routes.login;
      if (isSplash || isAuthRoute) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: Routes.register, builder: (_, __) => const RegisterScreen()),
      GoRoute(path: Routes.forgot, builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: Routes.reset,
        builder: (_, s) => ResetPasswordScreen(email: s.uri.queryParameters['email'] ?? '', devCode: s.extra as String?),
      ),
      GoRoute(path: Routes.scan, builder: (_, __) => const CameraScreen()),
      GoRoute(path: Routes.preview, builder: (_, s) => PreviewScreen(imagePath: s.extra as String)),
      GoRoute(path: Routes.computer, builder: (_, __) => const PcBrowserScreen()),
      GoRoute(path: Routes.profile, builder: (_, __) => const ProfileScreen()),
      GoRoute(path: Routes.notifications, builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: Routes.security, builder: (_, __) => const SecurityScreen()),
      GoRoute(path: Routes.language, builder: (_, __) => const LanguageScreen()),
      ShellRoute(
        builder: (context, state, child) => MainShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: Routes.home, pageBuilder: (_, s) => _fade(s, const HomeScreen())),
          GoRoute(path: Routes.explore, pageBuilder: (_, s) => _fade(s, const ExploreScreen())),
          GoRoute(
            path: '/explore/:id',
            builder: (_, s) => GemstoneDetailScreen(gemstoneId: s.pathParameters['id']!),
          ),
          GoRoute(path: Routes.saved, pageBuilder: (_, s) => _fade(s, const SavedScreen())),
          GoRoute(
            path: '/result/:id',
            builder: (_, s) {
              final extra = s.extra;
              return ResultScreen(
                predictionId: s.pathParameters['id']!,
                initial: extra is ResultArgs ? extra.prediction : (extra is Prediction ? extra : null),
                localImagePath: extra is ResultArgs ? extra.localImagePath : null,
              );
            },
          ),
        ],
      ),
    ],
    errorBuilder: (_, state) => Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
});

CustomTransitionPage<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
    );

class ResultArgs {
  const ResultArgs(this.prediction, {this.localImagePath});
  final Prediction prediction;
  final String? localImagePath;
}

/// Screens with the floating bottom navigation (Home, Explore, Saved, Result, Gem detail).
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  NavTab get _tab {
    if (location.startsWith(Routes.explore)) return NavTab.explore;
    if (location.startsWith(Routes.home) || location.startsWith(Routes.saved)) return NavTab.home;
    return NavTab.none;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: AppBackground(child: child),
      bottomNavigationBar: CgBottomNav(
        current: _tab,
        onHome: () => context.go(Routes.home),
        onScan: () => context.push(Routes.scan),
        onExplore: () => context.go(Routes.explore),
        orange: true, // whole app uses the orange theme (Oct 2026)
      ),
    );
  }
}

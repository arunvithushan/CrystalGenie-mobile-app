// End-to-end test against the REAL FastAPI backend and REAL model.
//
// Start the backend first, then run on an emulator / phone:
//   flutter test integration_test/app_e2e_test.dart --dart-define=API_BASE_URL=http://10.0.2.2:8000
//
// The camera is replaced by a gallery pick of assets/test/sample_gem.jpg (a held-out Rose Quartz
// photo) because a physical shutter press cannot be automated; everything else is the real app.
import 'dart:io';
import 'dart:math';

import 'package:crystal_genie/app/app.dart';
import 'package:crystal_genie/app/theme.dart';
import 'package:crystal_genie/core/storage/app_prefs.dart';
import 'package:crystal_genie/core/storage/token_storage.dart';
import 'package:crystal_genie/features/camera/data/media_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _AssetImageService implements ImageService {
  @override
  Future<String?> pickFromGallery() async {
    final bytes = await rootBundle.load('assets/test/sample_gem.jpg');
    final file = File('${Directory.systemTemp.path}/e2e_sample_gem.jpg');
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return file.path;
  }

  @override
  Future<String?> pickFile() => pickFromGallery();

  @override
  Future<String?> crop(String path) async => path;
}

class _DeniedPermission implements PermissionService {
  @override
  Future<CamPermission> cameraStatus() async => CamPermission.denied;
  @override
  Future<CamPermission> requestCamera() async => CamPermission.denied;
  @override
  Future<bool> openSettings() async => false;
}

Future<void> _waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('register → scan → real prediction → save → favorite → logout/login → persisted', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = SecureTokenStorage();
    await storage.clear();
    final email = 'e2e${Random().nextInt(1 << 30)}@example.com';
    const password = 'E2eCrystal123';

    AppColors.animatedImages = false; // the rotating diamond would keep pumpAndSettle busy forever
    await tester.pumpWidget(ProviderScope(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      tokenStorageProvider.overrideWithValue(storage),
      imageServiceProvider.overrideWithValue(_AssetImageService()),
      permissionServiceProvider.overrideWithValue(_DeniedPermission()),
    ], child: const CrystalGenieApp()));
    await _waitFor(tester, find.text('Welcome back'));

    // 1. Register
    await tester.tap(find.byKey(const Key('go_register')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('register_name')), 'E2E Tester');
    await tester.enterText(find.byKey(const Key('register_email')), email);
    await tester.enterText(find.byKey(const Key('register_password')), password);
    await tester.enterText(find.byKey(const Key('register_confirm')), password);
    await tester.ensureVisible(find.byKey(const Key('register_submit')));
    await tester.tap(find.byKey(const Key('register_submit')));
    await _waitFor(tester, find.text('Hi welcome,'));
    expect(find.byKey(const Key('home_empty')), findsOneWidget);

    // 3-4. "Take" a photo (gallery pick) and upload it
    await tester.tap(find.byKey(const Key('nav_scan')));
    await _waitFor(tester, find.byKey(const Key('camera_gallery')));
    await tester.tap(find.byKey(const Key('camera_gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_phone')));
    await _waitFor(tester, find.byKey(const Key('preview_identify')));
    await tester.tap(find.byKey(const Key('preview_identify')));

    // 5-6. Real prediction + details
    await _waitFor(tester, find.byKey(const Key('result_title')), timeout: const Duration(seconds: 120));
    expect(find.text('Top 3 matches'), findsOneWidget);
    expect(find.textContaining('cg-effv2b0-'), findsOneWidget); // produced by the trained model, not a stub

    // 7. Save  8. Favorite
    await tester.scrollUntilVisible(find.byKey(const Key('result_save')), 400);
    await tester.ensureVisible(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('result_save')));
    await _waitFor(tester, find.text('Saved to My Finds'));
    final fav = find.byKey(const Key('result_favorite'));
    if (fav.evaluate().isNotEmpty) {
      await tester.tap(fav);
      await _waitFor(tester, find.text('In Favorites'));
    }

    // 9. My Finds
    await tester.tap(find.byKey(const Key('nav_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_profile_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_saved')));
    await _waitFor(tester, find.text('Learn more'));

    // 10. Logout and login again
    await tester.tap(find.byKey(const Key('nav_home')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_profile_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_logout')));
    await _waitFor(tester, find.text('Welcome back'));
    await tester.enterText(find.byKey(const Key('login_email')), email);
    await tester.enterText(find.byKey(const Key('login_password')), password);
    await tester.tap(find.byKey(const Key('login_submit')));
    await _waitFor(tester, find.text('Recent Finds'));

    // 11. Data persisted
    await tester.tap(find.byKey(const Key('home_profile_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('menu_saved')));
    await _waitFor(tester, find.text('Learn more'));
    expect(find.byIcon(Icons.bookmark), findsWidgets);
  });
}

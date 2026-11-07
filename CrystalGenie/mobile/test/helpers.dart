import 'dart:async';

import 'package:camera/camera.dart';
import 'package:crystal_genie/app/app.dart';
import 'package:crystal_genie/app/theme.dart';
import 'package:crystal_genie/core/network/api_exception.dart';
import 'package:crystal_genie/core/storage/app_prefs.dart';
import 'package:crystal_genie/core/storage/token_storage.dart';
import 'package:crystal_genie/features/auth/data/auth_repository.dart';
import 'package:crystal_genie/features/camera/data/link_image_service.dart';
import 'package:crystal_genie/features/camera/data/media_services.dart';
import 'package:crystal_genie/features/explore/data/gemstone_repository.dart';
import 'package:crystal_genie/features/home/data/model_info_repository.dart';
import 'package:crystal_genie/features/pc_files/data/pc_files_repository.dart';
import 'package:crystal_genie/features/profile/data/user_repository.dart';
import 'package:crystal_genie/features/results/data/prediction_repository.dart';
import 'package:crystal_genie/features/saved/data/collection_repository.dart';
import 'package:crystal_genie/shared/models/models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ----------------------------------------------------------------------------- sample data
const testUser = AppUser(id: 'u1', email: 'jon@example.com', fullName: 'Jon Doe');

GemstoneDetail gem({String id = 'g1', String name = 'Rose Quartz', bool fav = false}) => GemstoneDetail(
      id: id,
      slug: name.toLowerCase().replaceAll(' ', '-'),
      name: name,
      tagline: 'Soft pink quartz',
      category: 'Quartz variety',
      shortDescription: '$name is a test gemstone.',
      description: '$name is a test gemstone used in widget tests.',
      colors: const ['pink'],
      mineralFamily: 'Quartz (tectosilicate)',
      chemicalFormula: 'SiO₂',
      hardnessMin: 7,
      hardnessMax: 7,
      hardnessLabel: '7',
      characteristics: const {'Luster': 'Vitreous'},
      sources: const ['Brazil', 'Madagascar'],
      traditionalMeanings: 'Called the stone of love. These are cultural beliefs, not scientific properties.',
      careInstructions: 'Mild soap and water.',
      isFavorite: fav,
    );

Prediction prediction({
  String id = 'p1',
  String cls = 'Rose_Quartz',
  String display = 'Rose Quartz',
  double conf = 0.93,
  bool uncertain = false,
  bool saved = false,
  GemstoneDetail? g,
}) =>
    Prediction(
      id: id,
      predictedClass: cls,
      displayName: display,
      confidence: conf,
      isUncertain: uncertain,
      uncertaintyMessage: uncertain ? 'Uncertain identification.' : null,
      threshold: 0.6,
      topPredictions: [
        TopPrediction(className: cls, displayName: display, confidence: conf, gemstoneId: 'g1'),
        const TopPrediction(className: 'Garnet', displayName: 'Garnet', confidence: 0.04, gemstoneId: 'g2'),
        const TopPrediction(className: 'Obsidian', displayName: 'Obsidian', confidence: 0.03, gemstoneId: 'g3'),
      ],
      modelVersion: 'cg-effv2b0-test',
      latencyMs: 120,
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      gemstone: g ?? gem(),
      isSaved: saved,
      savedId: saved ? 's_$id' : null,
    );

PageResult<T> page<T>(List<T> items) =>
    PageResult(items: items, total: items.length, page: 1, pageSize: 20, hasMore: false);

// ----------------------------------------------------------------------------- fakes
class FakeAuthRepository implements AuthRepository {
  int loginCalls = 0;
  bool failLogin = false;
  AppUser user = testUser;
  bool loggedOut = false;

  AuthResult _result() => AuthResult(accessToken: 'access', refreshToken: 'refresh-token-value-123456', user: user);

  @override
  Future<AuthResult> login(String email, String password) async {
    loginCalls++;
    if (failLogin) {
      throw const ApiException(code: 'invalid_credentials', message: 'Incorrect e-mail or password.', statusCode: 401);
    }
    return _result();
  }

  @override
  Future<AuthResult> register(String fullName, String email, String password) async {
    user = AppUser(id: 'u2', email: email, fullName: fullName);
    return _result();
  }

  @override
  Future<void> logout(String? refreshToken, {bool allDevices = false}) async => loggedOut = true;
  @override
  Future<String?> forgotPassword(String email) async => 'ABCD2345';
  @override
  Future<void> resetPassword(String email, String code, String newPassword) async {}
  @override
  Future<AuthResult> changePassword(String current, String newPassword) async => _result();
  @override
  Future<AppUser> me() async => user;
}

class FakePredictionRepository implements PredictionRepository {
  List<Prediction> history_ = [];
  Object? historyError;
  Completer<Prediction>? predictCompleter;
  Object? predictError;
  Prediction next = prediction();
  int predictCalls = 0;

  @override
  Future<Prediction> predict(String filePath, {void Function(double progress)? onProgress, CancelToken? cancelToken}) async {
    predictCalls++;
    onProgress?.call(1);
    if (predictError != null) throw predictError!;
    if (predictCompleter != null) return predictCompleter!.future;
    return next;
  }

  @override
  Future<PageResult<Prediction>> history({int page = 1, int pageSize = 20}) async {
    if (historyError != null) throw historyError!;
    return PageResult(items: history_, total: history_.length, page: 1, pageSize: pageSize, hasMore: false);
  }

  @override
  Future<Prediction> getById(String id) async => history_.firstWhere((p) => p.id == id, orElse: () => next);
  @override
  Future<void> delete(String id) async => history_.removeWhere((p) => p.id == id);
}

class FakeGemstoneRepository implements GemstoneRepository {
  List<GemstoneSummary> gems = [gem(), gem(id: 'g2', name: 'Garnet'), gem(id: 'g3', name: 'Obsidian')];
  GemQuery? lastQuery;

  @override
  Future<PageResult<GemstoneSummary>> list(GemQuery query, {int page = 1, int pageSize = 20}) async {
    lastQuery = query;
    final q = query.search.toLowerCase();
    final items = gems.where((g) => g.name.toLowerCase().contains(q)).toList()
      ..sort((a, b) => query.descending ? b.name.compareTo(a.name) : a.name.compareTo(b.name));
    return PageResult(items: items, total: items.length, page: 1, pageSize: pageSize, hasMore: false);
  }

  @override
  Future<GemstoneDetail> get(String id) async => gem(id: id, name: gems.firstWhere((g) => g.id == id).name);
  @override
  Future<List<GemCategory>> categories() async => const [GemCategory('Quartz variety', 1), GemCategory('Natural glass', 1)];
  @override
  Future<List<String>> colors() async => const ['pink', 'red'];
}

class FakeCollectionRepository implements CollectionRepository {
  List<SavedCrystal> savedItems = [];
  List<FavoriteItem> favoriteItems = [];
  final List<String> calls = [];

  @override
  Future<PageResult<SavedCrystal>> saved({int page = 1, int pageSize = 20, String? search}) async => page_(savedItems);
  @override
  Future<SavedCrystal> save(String predictionId, {String? note}) async {
    calls.add('save:$predictionId');
    final s = SavedCrystal(id: 's_$predictionId', prediction: prediction(id: predictionId, saved: true));
    savedItems = [...savedItems, s];
    return s;
  }

  @override
  Future<void> unsave(String savedId) async {
    calls.add('unsave:$savedId');
    savedItems = savedItems.where((s) => s.id != savedId).toList();
  }

  @override
  Future<PageResult<FavoriteItem>> favorites({int page = 1, int pageSize = 20, String? search}) async => page_(favoriteItems);
  @override
  Future<FavoriteItem> addFavorite(String gemstoneId) async {
    calls.add('fav:$gemstoneId');
    final f = FavoriteItem(id: 'f_$gemstoneId', gemstone: gem(id: gemstoneId, fav: true));
    favoriteItems = [...favoriteItems, f];
    return f;
  }

  @override
  Future<void> removeFavorite(String id) async {
    calls.add('unfav:$id');
    favoriteItems = favoriteItems.where((f) => f.id != id && f.gemstone.id != id).toList();
  }

  PageResult<T> page_<T>(List<T> items) => page(items);
}

class FakeUserRepository implements UserRepository {
  String? lastName;
  bool deleted = false;
  UserSettings settings =
      const UserSettings(notificationsEnabled: true, scanTipsEnabled: true, newCrystalAlerts: false, language: 'en');

  @override
  Future<AppUser> updateProfile({String? fullName, String? email}) async {
    lastName = fullName;
    return AppUser(id: testUser.id, email: email ?? testUser.email, fullName: fullName ?? testUser.fullName);
  }

  @override
  Future<AppUser> uploadAvatar(String filePath) async => testUser;
  @override
  Future<void> deleteAccount(String password) async => deleted = true;
  @override
  Future<UserSettings> getSettings() async => settings;
  @override
  Future<UserSettings> updateSettings(Map<String, dynamic> changes) async {
    settings = settings.copyWith(
      notificationsEnabled: changes['notifications_enabled'] as bool?,
      language: changes['language'] as String?,
    );
    return settings;
  }
}

class FakePermissionService implements PermissionService {
  FakePermissionService(this.status);
  CamPermission status;
  int requests = 0;
  bool openedSettings = false;

  @override
  Future<CamPermission> cameraStatus() async => status;
  @override
  Future<CamPermission> requestCamera() async {
    requests++;
    return status;
  }

  @override
  Future<bool> openSettings() async => openedSettings = true;
}

class NoCameraSource implements CameraSource {
  @override
  Future<List<CameraDescription>> cameras() async => const [];
}

class FakeImageService implements ImageService {
  FakeImageService([this.pickPath]);
  String? pickPath;
  @override
  Future<String?> pickFromGallery() async => pickPath;
  String? filePath;
  @override
  Future<String?> pickFile() async => filePath ?? pickPath;
  @override
  Future<String?> crop(String path) async => path;
}

class FakeLinkImageService implements LinkImageService {
  String? path;
  final links = <String>[];
  @override
  Future<String> download(String link, {bool driveOnly = false}) async {
    links.add(link);
    resolveImageLink(link, driveOnly: driveOnly);
    if (path == null) throw const LinkImageException('This link is not a JPEG, PNG or WEBP photo.');
    return path!;
  }
}

class FakeModelInfoRepository implements ModelInfoRepository {
  Object? error;
  ModelInfo info = const ModelInfo(
      loaded: true, numClasses: 13, modelVersion: 'cg-test', testAccuracy: 0.869, top3Accuracy: 0.966, f1Macro: 0.865, testSamples: 145);
  @override
  Future<ModelInfo> status() async {
    if (error != null) throw error!;
    return info;
  }
}

class FakePcFilesRepository extends PcFilesRepository {
  Object? error;
  String? downloadPath;
  final opened = <String>[];
  @override
  Future<List<PcFolder>> roots() async {
    if (error != null) throw error!;
    return const [PcFolder(name: 'ASUS', path: r'C:\Users\ASUS')];
  }

  @override
  Future<PcListing> list(String path) async {
    opened.add(path);
    if (path == r'C:\Users\ASUS') {
      return const PcListing(path: r'C:\Users\ASUS', name: 'ASUS', folders: [PcFolder(name: 'Pictures', path: r'C:\Users\ASUS\Pictures')]);
    }
    return PcListing(path: path, name: 'Pictures', parent: r'C:\Users\ASUS', images: const [
      PcImage(name: 'garnet.jpg', path: r'C:\Users\ASUS\Pictures\garnet.jpg', size: 1000),
    ]);
  }

  @override
  Future<String> download(PcImage image) async => downloadPath!;

  @override
  String thumbnailPath(String path) => ''; // placeholder in widget tests (no network)
}

class Fakes {
  final auth = FakeAuthRepository();
  final predictions = FakePredictionRepository();
  final gems = FakeGemstoneRepository();
  final collections = FakeCollectionRepository();
  final users = FakeUserRepository();
  final permissions = FakePermissionService(CamPermission.denied);
  final images = FakeImageService();
  final modelInfo = FakeModelInfoRepository();
  final pcFiles = FakePcFilesRepository();
  final links = FakeLinkImageService();
  final storage = MemoryTokenStorage();
}

Future<List<Override>> testOverrides(Fakes f) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    tokenStorageProvider.overrideWithValue(f.storage),
    authRepositoryProvider.overrideWithValue(f.auth),
    predictionRepositoryProvider.overrideWithValue(f.predictions),
    gemstoneRepositoryProvider.overrideWithValue(f.gems),
    collectionRepositoryProvider.overrideWithValue(f.collections),
    userRepositoryProvider.overrideWithValue(f.users),
    permissionServiceProvider.overrideWithValue(f.permissions),
    cameraSourceProvider.overrideWithValue(NoCameraSource()),
    imageServiceProvider.overrideWithValue(f.images),
    modelInfoRepositoryProvider.overrideWithValue(f.modelInfo),
    pcFilesRepositoryProvider.overrideWithValue(f.pcFiles),
    linkImageServiceProvider.overrideWithValue(f.links),
  ];
}

/// Pumps the full app (router, theme, splash → auth → screens) with fake repositories.
Future<void> pumpApp(WidgetTester tester, Fakes f, {bool signedIn = false}) async {
  AppText.useGoogleFonts = false;
  AppColors.animatedImages = false;
  tester.view.physicalSize = const Size(1290, 2796); // 430 x 932 logical @3x (Figma frame size)
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  if (signedIn) {
    f.storage.tokens = const AuthTokens(accessToken: 'access', refreshToken: 'refresh-token-value-123456');
  }
  await tester.pumpWidget(ProviderScope(overrides: await testOverrides(f), child: const CrystalGenieApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1300)); // splash minimum duration
  await tester.pumpAndSettle();
}

/// Pumps a single widget inside a MaterialApp + ProviderScope.
Future<ProviderContainer> pumpScreen(WidgetTester tester, Fakes f, Widget child) async {
  AppText.useGoogleFonts = false;
  AppColors.animatedImages = false;
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: await testOverrides(f));
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child)),
  ));
  await tester.pump();
  return container;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;
}

/// Sensitive values live in the platform keystore (Android Keystore / iOS Keychain).
abstract class TokenStorage {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
  Future<String?> readCachedUser();
  Future<void> writeCachedUser(String json);
}

class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final FlutterSecureStorage _s;

  static const _kAccess = 'cg_access_token';
  static const _kRefresh = 'cg_refresh_token';
  static const _kUser = 'cg_cached_user';

  AuthTokens? _cache;
  bool _loaded = false;

  @override
  Future<AuthTokens?> read() async {
    if (_loaded) return _cache;
    final a = await _s.read(key: _kAccess);
    final r = await _s.read(key: _kRefresh);
    _cache = (a == null || r == null) ? null : AuthTokens(accessToken: a, refreshToken: r);
    _loaded = true;
    return _cache;
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    _cache = tokens;
    _loaded = true;
    await _s.write(key: _kAccess, value: tokens.accessToken);
    await _s.write(key: _kRefresh, value: tokens.refreshToken);
  }

  @override
  Future<void> clear() async {
    _cache = null;
    _loaded = true;
    await _s.delete(key: _kAccess);
    await _s.delete(key: _kRefresh);
    await _s.delete(key: _kUser);
  }

  @override
  Future<String?> readCachedUser() => _s.read(key: _kUser);

  @override
  Future<void> writeCachedUser(String json) => _s.write(key: _kUser, value: json);
}

/// In-memory implementation used by tests.
class MemoryTokenStorage implements TokenStorage {
  AuthTokens? tokens;
  String? user;

  @override
  Future<AuthTokens?> read() async => tokens;
  @override
  Future<void> write(AuthTokens t) async => tokens = t;
  @override
  Future<void> clear() async {
    tokens = null;
    user = null;
  }

  @override
  Future<String?> readCachedUser() async => user;
  @override
  Future<void> writeCachedUser(String json) async => user = json;
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => SecureTokenStorage());

/// Current access token (used for protected images). Invalidated whenever tokens change.
final accessTokenProvider = FutureProvider<String?>((ref) async => (await ref.watch(tokenStorageProvider).read())?.accessToken);

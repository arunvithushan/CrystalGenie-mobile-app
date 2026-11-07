import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/token_storage.dart';
import '../../../shared/models/models.dart';
import '../data/auth_repository.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  const AuthState({this.status = AuthStatus.unknown, this.user, this.message, this.offline = false});
  final AuthStatus status;
  final AppUser? user;
  final String? message; // e.g. "Session expired"
  final bool offline;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref, this._storage, SessionEvents events) : super(const AuthState()) {
    _sub = events.onExpired.listen((_) {
      state = const AuthState(status: AuthStatus.unauthenticated, message: 'Your session has expired. Please sign in again.');
    });
  }

  final Ref _ref;
  final TokenStorage _storage;

  // Read lazily so changing the server address does not reset the session state.
  AuthRepository get _repo => _ref.read(authRepositoryProvider);
  late final StreamSubscription<void> _sub;

  /// Called by the splash screen. Throws [ApiException] only for unexpected server errors.
  Future<void> bootstrap() async {
    final tokens = await _storage.read();
    if (tokens == null) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _repo.me();
      await _storage.writeCachedUser(jsonEncode(user.toJson()));
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _storage.clear();
        state = const AuthState(status: AuthStatus.unauthenticated);
      } else if (e.isNetwork) {
        final cached = await _storage.readCachedUser();
        if (cached == null) rethrow;
        state = AuthState(
            status: AuthStatus.authenticated, user: AppUser.fromJson(jsonDecode(cached) as Map<String, dynamic>), offline: true);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _signedIn(AuthResult r) async {
    await _storage.write(AuthTokens(accessToken: r.accessToken, refreshToken: r.refreshToken));
    await _storage.writeCachedUser(jsonEncode(r.user.toJson()));
    _ref.invalidate(accessTokenProvider);
    state = AuthState(status: AuthStatus.authenticated, user: r.user);
  }

  Future<void> login(String email, String password) async => _signedIn(await _repo.login(email, password));

  Future<void> register(String name, String email, String password) async =>
      _signedIn(await _repo.register(name, email, password));

  Future<void> changePassword(String current, String newPassword) async =>
      _signedIn(await _repo.changePassword(current, newPassword));

  Future<void> logout({bool allDevices = false}) async {
    final tokens = await _storage.read();
    try {
      await _repo.logout(tokens?.refreshToken, allDevices: allDevices);
    } catch (_) {
      // Signing out locally must always work, even offline.
    }
    await _storage.clear();
    _ref.invalidate(accessTokenProvider);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  /// After account deletion the server has already revoked everything.
  Future<void> clearLocalSession({String? message}) async {
    await _storage.clear();
    state = AuthState(status: AuthStatus.unauthenticated, message: message);
  }

  Future<void> updateUser(AppUser user) async {
    await _storage.writeCachedUser(jsonEncode(user.toJson()));
    state = AuthState(status: AuthStatus.authenticated, user: user);
  }

  void clearMessage() {
    if (state.message != null) state = AuthState(status: state.status, user: state.user, offline: state.offline);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) => AuthController(
      ref,
      ref.watch(tokenStorageProvider),
      ref.watch(sessionEventsProvider),
    ));

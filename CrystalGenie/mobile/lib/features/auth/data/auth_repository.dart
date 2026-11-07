import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/models.dart';

abstract class AuthRepository {
  Future<AuthResult> login(String email, String password);
  Future<AuthResult> register(String fullName, String email, String password);
  Future<void> logout(String? refreshToken, {bool allDevices = false});
  Future<String?> forgotPassword(String email);
  Future<void> resetPassword(String email, String code, String newPassword);
  Future<AuthResult> changePassword(String current, String newPassword);
  Future<AppUser> me();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._api);
  final ApiClient _api;

  @override
  Future<AuthResult> login(String email, String password) => _api.post('/auth/login',
      body: {'email': email.trim(), 'password': password}, auth: false, parse: (d) => AuthResult.fromJson(d));

  @override
  Future<AuthResult> register(String fullName, String email, String password) => _api.post('/auth/register',
      body: {'full_name': fullName.trim(), 'email': email.trim(), 'password': password},
      auth: false,
      parse: (d) => AuthResult.fromJson(d));

  @override
  Future<void> logout(String? refreshToken, {bool allDevices = false}) =>
      _api.post('/auth/logout', body: {'refresh_token': refreshToken, 'all_devices': allDevices}, parse: (_) {});

  /// Returns the reset code only when the server runs in development mode with
  /// EXPOSE_RESET_CODE_IN_RESPONSE=true (so the flow can be tested without e-mail).
  @override
  Future<String?> forgotPassword(String email) => _api.post('/auth/forgot-password',
      body: {'email': email.trim()}, auth: false, parse: (d) => (d as Map)['dev_reset_code'] as String?);

  @override
  Future<void> resetPassword(String email, String code, String newPassword) => _api.post('/auth/reset-password',
      body: {'email': email.trim(), 'code': code.trim(), 'new_password': newPassword}, auth: false, parse: (_) {});

  @override
  Future<AuthResult> changePassword(String current, String newPassword) => _api.post('/auth/change-password',
      body: {'current_password': current, 'new_password': newPassword}, parse: (d) => AuthResult.fromJson(d));

  @override
  Future<AppUser> me() => _api.get('/users/me', parse: (d) => AppUser.fromJson(d));
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => ApiAuthRepository(ref.watch(apiClientProvider)));

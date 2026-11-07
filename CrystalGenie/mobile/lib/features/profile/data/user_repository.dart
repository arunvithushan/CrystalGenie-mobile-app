import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/models.dart';

abstract class UserRepository {
  Future<AppUser> updateProfile({String? fullName, String? email});
  Future<AppUser> uploadAvatar(String filePath);
  Future<void> deleteAccount(String password);
  Future<UserSettings> getSettings();
  Future<UserSettings> updateSettings(Map<String, dynamic> changes);
}

class ApiUserRepository implements UserRepository {
  ApiUserRepository(this._api);
  final ApiClient _api;

  @override
  Future<AppUser> updateProfile({String? fullName, String? email}) => _api.patch('/users/me',
      body: {if (fullName != null) 'full_name': fullName.trim(), if (email != null) 'email': email.trim()},
      parse: (d) => AppUser.fromJson(d));

  @override
  Future<AppUser> uploadAvatar(String filePath) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(filePath, filename: 'avatar.jpg')});
    return _api.post('/users/avatar', body: form, parse: (d) => AppUser.fromJson(d));
  }

  @override
  Future<void> deleteAccount(String password) =>
      _api.delete('/users/me', body: {'password': password, 'confirm': 'DELETE'}, parse: (_) {});

  @override
  Future<UserSettings> getSettings() => _api.get('/users/settings', parse: (d) => UserSettings.fromJson(d));

  @override
  Future<UserSettings> updateSettings(Map<String, dynamic> changes) =>
      _api.patch('/users/settings', body: changes, parse: (d) => UserSettings.fromJson(d));
}

final userRepositoryProvider = Provider<UserRepository>((ref) => ApiUserRepository(ref.watch(apiClientProvider)));

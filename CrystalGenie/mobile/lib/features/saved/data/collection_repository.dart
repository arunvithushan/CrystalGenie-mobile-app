import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../shared/models/models.dart';

abstract class CollectionRepository {
  Future<PageResult<SavedCrystal>> saved({int page = 1, int pageSize = 20, String? search});
  Future<SavedCrystal> save(String predictionId, {String? note});
  Future<void> unsave(String savedId);
  Future<PageResult<FavoriteItem>> favorites({int page = 1, int pageSize = 20, String? search});
  Future<FavoriteItem> addFavorite(String gemstoneId);

  /// Accepts a favourite id or a gemstone id.
  Future<void> removeFavorite(String id);
}

class ApiCollectionRepository implements CollectionRepository {
  ApiCollectionRepository(this._api);
  final ApiClient _api;

  @override
  Future<PageResult<SavedCrystal>> saved({int page = 1, int pageSize = 20, String? search}) => _api.get('/saved',
      query: {'page': page, 'page_size': pageSize, 'q': search}, parse: (d) => PageResult.fromJson(d, SavedCrystal.fromJson));

  @override
  Future<SavedCrystal> save(String predictionId, {String? note}) =>
      _api.post('/saved', body: {'prediction_id': predictionId, 'note': note}, parse: (d) => SavedCrystal.fromJson(d));

  @override
  Future<void> unsave(String savedId) => _api.delete('/saved/$savedId', parse: (_) {});

  @override
  Future<PageResult<FavoriteItem>> favorites({int page = 1, int pageSize = 20, String? search}) => _api.get('/favorites',
      query: {'page': page, 'page_size': pageSize, 'q': search}, parse: (d) => PageResult.fromJson(d, FavoriteItem.fromJson));

  @override
  Future<FavoriteItem> addFavorite(String gemstoneId) =>
      _api.post('/favorites', body: {'gemstone_id': gemstoneId}, parse: (d) => FavoriteItem.fromJson(d));

  @override
  Future<void> removeFavorite(String id) => _api.delete('/favorites/$id', parse: (_) {});
}

final collectionRepositoryProvider =
    Provider<CollectionRepository>((ref) => ApiCollectionRepository(ref.watch(apiClientProvider)));

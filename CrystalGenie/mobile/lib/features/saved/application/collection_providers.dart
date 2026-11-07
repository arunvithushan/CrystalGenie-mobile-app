import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/models.dart';
import '../../../shared/state/paged_controller.dart';
import '../../explore/application/explore_providers.dart' show gemstoneDetailProvider;
import '../../home/application/home_providers.dart';
import '../../results/application/result_providers.dart';
import '../data/collection_repository.dart';

final savedSearchProvider = StateProvider.autoDispose<String>((ref) => '');

final savedListProvider = StateNotifierProvider.autoDispose<PagedController<SavedCrystal>, PagedState<SavedCrystal>>((ref) {
  final repo = ref.watch(collectionRepositoryProvider);
  final q = ref.watch(savedSearchProvider);
  return PagedController<SavedCrystal>((page, size) => repo.saved(page: page, pageSize: size, search: q));
});

final favoritesListProvider = StateNotifierProvider.autoDispose<PagedController<FavoriteItem>, PagedState<FavoriteItem>>((ref) {
  final repo = ref.watch(collectionRepositoryProvider);
  final q = ref.watch(savedSearchProvider);
  return PagedController<FavoriteItem>((page, size) => repo.favorites(page: page, pageSize: size, search: q));
});

/// Save / favourite mutations, keeping every screen that shows them in sync.
class CollectionActions {
  CollectionActions(this._ref);
  final Ref _ref;

  CollectionRepository get _repo => _ref.read(collectionRepositoryProvider);

  /// Returns the new saved id (or null when removed).
  Future<String?> toggleSaved(Prediction p) async {
    if (p.id == null) throw StateError('prediction not stored');
    final removing = p.isSaved && p.savedId != null;
    String? newId;
    if (removing) {
      await _repo.unsave(p.savedId!);
    } else {
      newId = (await _repo.save(p.id!)).id;
    }
    _afterSavedChange(p.id!, newId);
    return newId;
  }

  Future<void> unsave(String savedId, {required String predictionId}) async {
    await _repo.unsave(savedId);
    _afterSavedChange(predictionId, null);
  }

  void _afterSavedChange(String predictionId, String? newSavedId) {
    if (_ref.exists(recentFindsProvider)) {
      _ref.read(recentFindsProvider.notifier).replaceWhere(
            (x) => x.id == predictionId,
            (x) => newSavedId == null ? x.copyWith(clearSaved: true) : x.copyWith(isSaved: true, savedId: newSavedId),
          );
    }
    if (_ref.exists(savedListProvider)) {
      if (newSavedId == null) {
        _ref.read(savedListProvider.notifier).removeWhere((s) => s.prediction.id == predictionId);
      } else {
        _ref.invalidate(savedListProvider);
      }
    }
    _ref.invalidate(predictionByIdProvider(predictionId));
  }

  /// Returns the new favourite state.
  Future<bool> toggleFavorite(String gemstoneId, {required bool currentlyFavorite}) async {
    if (currentlyFavorite) {
      await _repo.removeFavorite(gemstoneId);
    } else {
      await _repo.addFavorite(gemstoneId);
    }
    if (_ref.exists(favoritesListProvider)) {
      if (currentlyFavorite) {
        _ref.read(favoritesListProvider.notifier).removeWhere((f) => f.gemstone.id == gemstoneId);
      } else {
        _ref.invalidate(favoritesListProvider);
      }
    }
    _ref.invalidate(gemstoneDetailProvider(gemstoneId));
    return !currentlyFavorite;
  }
}

final collectionActionsProvider = Provider<CollectionActions>((ref) => CollectionActions(ref));

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../models/models.dart';

class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.page = 0,
    this.total = 0,
    this.hasMore = true,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
  });

  final List<T> items;
  final int page;
  final int total;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final String? error;
  final String? loadMoreError;

  bool get isInitialLoading => loading && items.isEmpty;
  bool get isEmpty => !loading && error == null && items.isEmpty;

  PagedState<T> copyWith({
    List<T>? items,
    int? page,
    int? total,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    String? error,
    String? loadMoreError,
    bool clearError = false,
  }) =>
      PagedState<T>(
        items: items ?? this.items,
        page: page ?? this.page,
        total: total ?? this.total,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
        loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
      );
}

typedef PageFetcher<T> = Future<PageResult<T>> Function(int page, int pageSize);

/// Generic "first page + lazy load more + pull to refresh" controller.
class PagedController<T> extends StateNotifier<PagedState<T>> {
  PagedController(this._fetch, {this.pageSize = 20, bool autoLoad = true}) : super(PagedState<T>(loading: autoLoad)) {
    if (autoLoad) refresh();
  }

  PageFetcher<T> _fetch;
  final int pageSize;
  int _generation = 0;

  /// Replace the fetcher (e.g. new search text / filters) and reload from page 1.
  Future<void> reset(PageFetcher<T> fetch) {
    _fetch = fetch;
    return refresh();
  }

  Future<void> refresh() async {
    final gen = ++_generation;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final r = await _fetch(1, pageSize);
      if (!mounted || gen != _generation) return;
      state = PagedState<T>(items: r.items, page: 1, total: r.total, hasMore: r.hasMore);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(loading: false, error: errorMessage(e));
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore || state.error != null) return;
    final gen = _generation;
    state = state.copyWith(loadingMore: true, clearError: true);
    try {
      final r = await _fetch(state.page + 1, pageSize);
      if (!mounted || gen != _generation) return;
      state = state.copyWith(
          items: [...state.items, ...r.items], page: state.page + 1, total: r.total, hasMore: r.hasMore, loadingMore: false);
    } catch (e) {
      if (!mounted || gen != _generation) return;
      state = state.copyWith(loadingMore: false, loadMoreError: errorMessage(e));
    }
  }

  /// Optimistic local edits (e.g. remove an item after deleting it on the server).
  void removeWhere(bool Function(T) test) {
    final items = state.items.where((e) => !test(e)).toList();
    state = state.copyWith(items: items, total: state.total - (state.items.length - items.length));
  }

  void replaceWhere(bool Function(T) test, T Function(T) update) {
    state = state.copyWith(items: [for (final e in state.items) test(e) ? update(e) : e]);
  }
}

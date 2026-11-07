import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/storage/app_prefs.dart';
import '../../../shared/models/models.dart';
import '../../../shared/state/paged_controller.dart';
import '../../../shared/widgets/gem_cards.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/headers.dart';
import '../../../shared/widgets/state_views.dart';
import '../application/collection_providers.dart';

/// Figma "Saved List page" (My finds / Favorites, list or tiles layout).
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  late int _tab = widget.initialTab;
  late bool _grid = ref.read(appPrefsProvider).savedGridView;
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => ref.read(savedSearchProvider.notifier).state = v.trim());
  }

  void _toggleGrid() {
    setState(() => _grid = !_grid);
    ref.read(appPrefsProvider).setSavedGridView(_grid);
  }

  Future<void> _removeFind(SavedCrystal s) async {
    try {
      await ref.read(collectionActionsProvider).unsave(s.id, predictionId: s.prediction.id!);
      if (!mounted) return;
      showSnack(context, 'Removed from My Finds',
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppColors.mint,
            onPressed: () => ref.read(collectionActionsProvider).toggleSaved(s.prediction.copyWith(clearSaved: true)),
          ));
    } catch (e) {
      ref.invalidate(savedListProvider);
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _removeFavorite(FavoriteItem f) async {
    try {
      await ref.read(collectionActionsProvider).toggleFavorite(f.gemstone.id, currentlyFavorite: true);
      if (!mounted) return;
      showSnack(context, 'Removed from Favorites',
          action: SnackBarAction(
            label: 'Undo',
            textColor: AppColors.mint,
            onPressed: () => ref.read(collectionActionsProvider).toggleFavorite(f.gemstone.id, currentlyFavorite: false),
          ));
    } catch (e) {
      ref.invalidate(favoritesListProvider);
      if (mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<bool> _confirmDelete(String what) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Remove item?'),
          content: Text('Remove $what from your collection?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              children: [
                BigTitleHeader(
                  title: 'Saved Crystals',
                  pill: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 34,
                          child: TextField(
                            key: const Key('saved_search'),
                            controller: _search,
                            onChanged: _onSearch,
                            style: AppText.montserrat(size: 14),
                            decoration: InputDecoration(
                              hintText: 'Search saved crystals',
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              fillColor: Colors.white.withValues(alpha: 0.7),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.mint)),
                              suffixIcon: const Icon(Icons.search, color: AppColors.ink),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('saved_layout_toggle'),
                        tooltip: _grid ? 'List view' : 'Grid view',
                        onPressed: _toggleGrid,
                        icon: Icon(_grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 34),
                _Tabs(index: _tab, onChanged: (i) => setState(() => _tab = i)),
                const SizedBox(height: 14),
              ],
            ),
          ),
          Expanded(child: _tab == 0 ? _findsTab() : _favoritesTab()),
        ],
      ),
    );
  }

  Widget _findsTab() {
    final state = ref.watch(savedListProvider);
    final c = ref.read(savedListProvider.notifier);
    return _PagedBody<SavedCrystal>(
      key: const Key('saved_finds'),
      state: state,
      controller: c,
      grid: _grid,
      emptyMessage: 'No saved finds yet.\nScan a crystal and tap “Save to My Finds”.',
      emptyAction: 'Scan a crystal',
      onEmptyAction: () => context.push(Routes.scan),
      itemBuilder: (s, grid) {
        final p = s.prediction;
        final title = p.gemstone?.name ?? p.displayName;
        final subtitle = p.gemstone?.shortDescription ?? '';
        void open() => context.push(Routes.result(p.id!), extra: p);
        if (grid) {
          return TileCard(
              title: title, subtitle: subtitle, imagePath: p.imageUrl, bookmarked: true, onBookmark: () => _removeFind(s), onLearnMore: open);
        }
        return Dismissible(
          key: ValueKey('saved_${s.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(title),
          onDismissed: (_) => _removeFind(s),
          background: _dismissBg(),
          child: FindListCard(
            title: title,
            subtitle: subtitle,
            caption: timeAgo(s.createdAt),
            imagePath: p.imageUrl,
            bookmarked: true,
            onBookmark: () => _removeFind(s),
            onLearnMore: open,
          ),
        );
      },
    );
  }

  Widget _favoritesTab() {
    final state = ref.watch(favoritesListProvider);
    final c = ref.read(favoritesListProvider.notifier);
    return _PagedBody<FavoriteItem>(
      key: const Key('saved_favorites'),
      state: state,
      controller: c,
      grid: _grid,
      emptyMessage: 'No favorites yet.\nTap the bookmark on any crystal to add it here.',
      emptyAction: 'Explore the library',
      onEmptyAction: () => context.go(Routes.explore),
      itemBuilder: (f, grid) {
        final g = f.gemstone;
        void open() => context.push(Routes.gem(g.id));
        if (grid) {
          return TileCard(
              title: g.name, subtitle: g.shortDescription, imagePath: g.imageUrl, bookmarked: true,
              onBookmark: () => _removeFavorite(f), onLearnMore: open);
        }
        return Dismissible(
          key: ValueKey('fav_${f.id}'),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmDelete(g.name),
          onDismissed: (_) => _removeFavorite(f),
          background: _dismissBg(),
          child: FindListCard(
            title: g.name,
            subtitle: g.shortDescription,
            imagePath: g.imageUrl,
            bookmarked: true,
            onBookmark: () => _removeFavorite(f),
            onLearnMore: open,
          ),
        );
      },
    );
  }

  Widget _dismissBg() => Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: AppColors.error.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
        child: const Icon(Icons.delete_outline, color: AppColors.error),
      );
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.index, required this.onChanged});
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(int i, String label) => Expanded(
          child: Semantics(
            selected: index == i,
            button: true,
            child: GestureDetector(
              key: Key('saved_tab_$i'),
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: index == i ? AppColors.buttonGradient : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(label,
                    style: AppText.montserrat(size: 17, color: index == i ? AppColors.navy : AppColors.teal)),
              ),
            ),
          ),
        );
    return GlassCard(
      radius: 16,
      padding: const EdgeInsets.all(8),
      child: Row(children: [tab(0, 'My finds'), const SizedBox(width: 8), tab(1, 'Favorites')]),
    );
  }
}

class _PagedBody<T> extends StatelessWidget {
  const _PagedBody({
    super.key,
    required this.state,
    required this.controller,
    required this.grid,
    required this.itemBuilder,
    required this.emptyMessage,
    required this.emptyAction,
    required this.onEmptyAction,
  });

  final PagedState<T> state;
  final PagedController<T> controller;
  final bool grid;
  final Widget Function(T item, bool grid) itemBuilder;
  final String emptyMessage;
  final String emptyAction;
  final VoidCallback onEmptyAction;

  @override
  Widget build(BuildContext context) {
    if (state.isInitialLoading) return const LoadingView();
    if (state.error != null && state.items.isEmpty) return ErrorView(message: state.error!, onRetry: controller.refresh);
    if (state.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 10, 24, 130),
        children: [
          EmptyStateCard(message: emptyMessage, actionLabel: emptyAction, onAction: onEmptyAction),
        ],
      );
    }
    final footer = state.loadingMore ? const Padding(padding: EdgeInsets.all(12), child: LoadingView()) : const SizedBox(height: 4);
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) controller.loadMore();
        return false;
      },
      child: RefreshIndicator(
        onRefresh: controller.refresh,
        child: grid
            ? GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 130),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2, mainAxisSpacing: 16, crossAxisSpacing: 14, childAspectRatio: 0.48),
                itemCount: state.items.length,
                itemBuilder: (_, i) => itemBuilder(state.items[i], true),
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 130),
                itemCount: state.items.length + 1,
                itemBuilder: (_, i) => i == state.items.length
                    ? footer
                    : Padding(padding: const EdgeInsets.only(bottom: 18), child: itemBuilder(state.items[i], false)),
              ),
      ),
    );
  }
}

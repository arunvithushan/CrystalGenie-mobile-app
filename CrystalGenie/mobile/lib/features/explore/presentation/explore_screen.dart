import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gem_cards.dart';
import '../../../shared/widgets/headers.dart';
import '../../../shared/widgets/state_views.dart';
import '../application/explore_providers.dart';
import '../data/gemstone_repository.dart';

/// Figma "Explore" / "Explore - Filtered": searchable, filterable crystal library.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  late final TextEditingController _search = TextEditingController(text: ref.read(exploreQueryProvider).search);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(exploreQueryProvider.notifier).update((q) => q.copyWith(search: v));
    });
  }

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _FilterSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(exploreQueryProvider);
    final state = ref.watch(exploreControllerProvider);
    final controller = ref.read(exploreControllerProvider.notifier);

    final chips = <Widget>[
      if (!query.hasFilters && !query.descending) _chip('All', null),
      if (query.category != null)
        _chip(query.category!, () => ref.read(exploreQueryProvider.notifier).update((q) => q.copyWith(clearCategory: true))),
      if (query.color != null)
        _chip(_cap(query.color!), () => ref.read(exploreQueryProvider.notifier).update((q) => q.copyWith(clearColor: true))),
      if (query.natural != null)
        _chip(query.natural! ? 'Natural' : 'Man-made',
            () => ref.read(exploreQueryProvider.notifier).update((q) => q.copyWith(clearNatural: true))),
      if (query.descending)
        _chip('Z–A', () => ref.read(exploreQueryProvider.notifier).update((q) => q.copyWith(descending: false))),
    ];

    return SafeArea(
      bottom: false,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) controller.loadMore();
          return false;
        },
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: CustomScrollView(
            key: const Key('explore_list'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BigTitleHeader(
                        title: 'Crystal library',
                        pill: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 34,
                                child: TextField(
                                  key: const Key('explore_search'),
                                  controller: _search,
                                  onChanged: _onSearchChanged,
                                  textInputAction: TextInputAction.search,
                                  style: AppText.montserrat(size: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Search for crystals',
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                                    fillColor: Colors.white.withValues(alpha: 0.7),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    enabledBorder:
                                        OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.mint)),
                                    suffixIcon: const Icon(Icons.search, color: AppColors.ink),
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              key: const Key('explore_filters'),
                              tooltip: 'Filter & sort',
                              onPressed: _openFilters,
                              icon: const Icon(Icons.tune, color: AppColors.ink),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Text('Filters:', style: AppText.montserrat(size: 14, color: AppColors.slate, weight: FontWeight.w500)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: [for (final c in chips) Padding(padding: const EdgeInsets.only(right: 6), child: c)]),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
              if (state.isInitialLoading)
                const SliverFillRemaining(hasScrollBody: false, child: LoadingView(message: 'Loading crystals…'))
              else if (state.error != null && state.items.isEmpty)
                SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: state.error!, onRetry: controller.refresh))
              else if (state.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverToBoxAdapter(
                    child: EmptyStateCard(
                      key: const Key('explore_empty'),
                      icon: const Icon(Icons.search_off, size: 34, color: AppColors.slate),
                      message: 'No crystals match your search.',
                      actionLabel: 'Clear filters',
                      onAction: () {
                        _search.clear();
                        ref.read(exploreQueryProvider.notifier).state = const GemQuery();
                      },
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 130),
                  sliver: SliverList.builder(
                    itemCount: state.items.length + 1,
                    itemBuilder: (context, i) {
                      if (i == state.items.length) {
                        if (state.loadingMore) return const Padding(padding: EdgeInsets.all(16), child: LoadingView());
                        if (state.loadMoreError != null) {
                          return TintButton(label: 'Load more', icon: Icons.refresh, onPressed: controller.loadMore);
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('${state.total} crystal${state.total == 1 ? '' : 's'} in the library',
                              textAlign: TextAlign.center, style: AppText.montserrat(size: 12, color: AppColors.slate)),
                        );
                      }
                      final g = state.items[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: LibraryCard(
                          key: ValueKey('gem_${g.slug}'),
                          name: g.name,
                          tagline: g.tagline,
                          description: g.shortDescription,
                          imagePath: g.imageUrl,
                          onTap: () => context.push(Routes.gem(g.id)),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _chip(String label, VoidCallback? onRemove) => Container(
        padding: EdgeInsets.fromLTRB(10, 4, onRemove == null ? 10 : 4, 4),
        decoration: onRemove == null
            ? null
            : BoxDecoration(color: Colors.white.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppText.montserrat(size: 14, weight: FontWeight.w500)),
            if (onRemove != null)
              InkResponse(
                onTap: onRemove,
                radius: 14,
                child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close, size: 15)),
              ),
          ],
        ),
      );
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(exploreQueryProvider);
    final cats = ref.watch(categoriesProvider);
    final colors = ref.watch(colorsProvider);
    void update(GemQuery Function(GemQuery) f) => ref.read(exploreQueryProvider.notifier).update(f);

    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppText.montserrat(size: 15, weight: FontWeight.w600, color: AppColors.navy)),
            const SizedBox(height: 8),
            child,
          ]),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: Text('Filter & sort', style: AppText.montserrat(size: 19, weight: FontWeight.w600))),
                TextButton(
                    onPressed: () => update((x) => GemQuery(search: x.search)), child: const Text('Reset')),
              ]),
              section(
                'Sort',
                Wrap(spacing: 8, children: [
                  ChoiceChip(label: const Text('A–Z'), selected: !q.descending, onSelected: (_) => update((x) => x.copyWith(descending: false))),
                  ChoiceChip(label: const Text('Z–A'), selected: q.descending, onSelected: (_) => update((x) => x.copyWith(descending: true))),
                ]),
              ),
              section(
                'Category',
                cats.when(
                  data: (list) => Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final c in list)
                      ChoiceChip(
                        key: Key('filter_category_${c.name}'),
                        label: Text('${c.name} (${c.count})'),
                        selected: q.category == c.name,
                        onSelected: (s) => update((x) => s ? x.copyWith(category: c.name) : x.copyWith(clearCategory: true)),
                      ),
                  ]),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('Could not load categories', style: AppText.montserrat(size: 13, color: AppColors.error)),
                ),
              ),
              section(
                'Colour',
                colors.when(
                  data: (list) => Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final c in list)
                      ChoiceChip(
                        label: Text(c[0].toUpperCase() + c.substring(1)),
                        selected: q.color == c,
                        onSelected: (s) => update((x) => s ? x.copyWith(color: c) : x.copyWith(clearColor: true)),
                      ),
                  ]),
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => const SizedBox(),
                ),
              ),
              section(
                'Origin',
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: const Text('Natural'),
                      selected: q.natural == true,
                      onSelected: (s) => update((x) => s ? x.copyWith(natural: true) : x.copyWith(clearNatural: true))),
                  ChoiceChip(
                      label: const Text('Man-made'),
                      selected: q.natural == false,
                      onSelected: (s) => update((x) => s ? x.copyWith(natural: false) : x.copyWith(clearNatural: true))),
                ]),
              ),
              const SizedBox(height: 22),
              GradientButton(label: 'Show results', onPressed: () => Navigator.pop(context)),
            ],
          ),
        ),
      ),
    );
  }
}

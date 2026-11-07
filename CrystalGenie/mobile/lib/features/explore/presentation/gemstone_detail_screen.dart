import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/headers.dart';
import '../../../shared/widgets/images.dart';
import '../../../shared/widgets/state_views.dart';
import '../../results/presentation/gem_info.dart';
import '../../saved/application/collection_providers.dart';
import '../application/explore_providers.dart';

class GemstoneDetailScreen extends ConsumerStatefulWidget {
  const GemstoneDetailScreen({super.key, required this.gemstoneId});
  final String gemstoneId;

  @override
  ConsumerState<GemstoneDetailScreen> createState() => _GemstoneDetailScreenState();
}

class _GemstoneDetailScreenState extends ConsumerState<GemstoneDetailScreen> {
  bool? _fav;
  bool _busy = false;

  Future<void> _toggle(GemstoneDetail g) async {
    setState(() => _busy = true);
    try {
      final v = await ref.read(collectionActionsProvider).toggleFavorite(g.id, currentlyFavorite: _fav ?? g.isFavorite);
      if (!mounted) return;
      setState(() => _fav = v);
      showSnack(context, v ? 'Added to Favorites' : 'Removed from Favorites');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(gemstoneDetailProvider(widget.gemstoneId));
    return SafeArea(
      bottom: false,
      child: async.when(
        loading: () => const LoadingView(message: 'Loading crystal…'),
        error: (e, _) =>
            ErrorView(message: errorMessage(e), onRetry: () => ref.invalidate(gemstoneDetailProvider(widget.gemstoneId))),
        data: (g) {
          final fav = _fav ?? g.isFavorite;
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 130),
            children: [
              BigTitleHeader(
                title: 'Crystal library',
                pill: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => context.canPop() ? context.pop() : context.go(Routes.explore),
                      icon: const Icon(Icons.chevron_left, size: 26),
                    ),
                    Expanded(
                      child: Text(g.name,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.playfair(size: 22, weight: FontWeight.w700)),
                    ),
                    IconButton(
                      key: const Key('gem_favorite_icon'),
                      tooltip: fav ? 'Remove from Favorites' : 'Add to Favorites',
                      onPressed: _busy ? null : () => _toggle(g),
                      icon: Icon(fav ? Icons.bookmark : Icons.bookmark_border, size: 28, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              AspectRatio(aspectRatio: 1, child: ApiImage(g.imageUrl, radius: 18)),
              Transform.translate(
                offset: const Offset(0, -36),
                child: GlassCard(
                  opacity: 0.72,
                  blur: 18,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(g.name, style: AppText.playfair(size: 28, weight: FontWeight.w700)),
                      Text(g.tagline,
                          style: AppText.montserrat(size: 14, style: FontStyle.italic, color: AppColors.grey.withValues(alpha: 0.8))),
                      const SizedBox(height: 10),
                      GemAttributeRow(gem: g),
                      const SizedBox(height: 16),
                      GemInfoSections(gem: g),
                      const SizedBox(height: 22),
                      GradientButton(
                        key: const Key('gem_favorite_button'),
                        label: fav ? 'In Favorites' : 'Add to Favorites',
                        icon: fav ? Icons.favorite : Icons.favorite_border,
                        loading: _busy,
                        onPressed: () => _toggle(g),
                      ),
                      const SizedBox(height: 10),
                      TintButton(
                        label: 'Scan a crystal',
                        icon: Icons.document_scanner_outlined,
                        onPressed: () => context.push(Routes.scan),
                        expand: true,
                        height: 44,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

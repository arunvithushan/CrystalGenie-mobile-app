import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/gem_cards.dart';
import '../../../shared/widgets/images.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../camera/presentation/upload_source.dart';
import '../../saved/application/collection_providers.dart';
import '../application/home_providers.dart';
import '../data/model_info_repository.dart';

/// Home: header + bell, swipeable banner (AI accuracy · scan · library), quick actions,
/// "My collection" totals and the user's real Recent Finds.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final finds = ref.watch(recentFindsProvider);
    final controller = ref.read(recentFindsProvider.notifier);

    Future<void> toggleSave(Prediction p) async {
      try {
        final id = await ref.read(collectionActionsProvider).toggleSaved(p);
        if (context.mounted) showSnack(context, context.tr(id == null ? 'Removed from My Finds' : 'Saved to My Finds'));
      } catch (e) {
        if (context.mounted) showSnack(context, errorMessage(e), error: true);
      }
    }

    Future<void> refresh() async {
      ref.invalidate(modelInfoProvider);
      ref.invalidate(savedListProvider);
      await controller.refresh();
    }

    return ColoredBox(
      color: AppColors.homeBg,
      child: SafeArea(
        bottom: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) controller.loadMore();
            return false;
          },
          child: RefreshIndicator(
            color: AppColors.orangeDeep,
            onRefresh: refresh,
            child: ListView(
              key: const Key('home_list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 130),
              children: [
                _Header(user: auth.user),
                if (auth.offline)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Pill(context.tr('Offline — showing your account from this device'),
                        color: AppColors.warning, icon: Icons.wifi_off),
                  ),
                const SizedBox(height: 14),
                const _BannerCarousel(),
                const SizedBox(height: 18),
                const _QuickActions(),
                const SizedBox(height: 18),
                _CollectionCard(totalScans: finds.isInitialLoading ? null : finds.total),
                const SizedBox(height: 22),
                if (finds.isInitialLoading)
                  Padding(
                      padding: const EdgeInsets.only(top: 30), child: LoadingView(message: context.tr('Loading your finds…')))
                else if (finds.error != null && finds.items.isEmpty)
                  ErrorView(message: finds.error!, onRetry: controller.refresh)
                else if (finds.isEmpty)
                  Container(
                    key: const Key('home_empty'),
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                    decoration: _cardDecoration,
                    child: Column(children: [
                      const Icon(Icons.diamond_outlined, size: 40, color: AppColors.orangeDeep),
                      const SizedBox(height: 10),
                      Text(context.tr('No crystals uncovered yet!'),
                          textAlign: TextAlign.center,
                          style: AppText.montserrat(size: 17, weight: FontWeight.w600, color: AppColors.ink)),
                      const SizedBox(height: 14),
                      Material(
                        borderRadius: BorderRadius.circular(24),
                        clipBehavior: Clip.antiAlias,
                        child: Ink(
                          decoration: const BoxDecoration(gradient: AppColors.orangeGradient),
                          child: InkWell(
                            onTap: () => context.push(Routes.scan),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.document_scanner_outlined, size: 18, color: Colors.white),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(context.tr('Try scanning your first crystal'),
                                      style: AppText.montserrat(size: 14, weight: FontWeight.w700, color: Colors.white)),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(context.tr('Recent Finds'),
                            style: AppText.montserrat(size: 19, weight: FontWeight.w700, color: AppColors.ink)),
                      ),
                      TextButton(
                        onPressed: () => context.go(Routes.saved),
                        child: Text(context.tr('See all'),
                            style: AppText.montserrat(size: 13.5, weight: FontWeight.w600, color: AppColors.orangeDeep)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final p in finds.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FindListCard(
                        key: ValueKey('find_${p.id}'),
                        title: p.isUncertain ? context.tr('Uncertain') : p.displayName,
                        subtitle: p.isUncertain
                            ? context.tr('Best guess: {name} ({pct}%). Try a clearer photo.',
                                {'name': p.displayName, 'pct': p.confidencePercent})
                            : (p.gemstone?.tagline.isNotEmpty == true
                                ? p.gemstone!.tagline
                                : p.gemstone?.shortDescription ?? ''),
                        caption: timeAgo(p.createdAt),
                        imagePath: p.imageUrl,
                        bookmarked: p.isSaved,
                        badge: p.isUncertain ? Pill(context.tr('Uncertain'), color: AppColors.warning, filled: true) : null,
                        onBookmark: () => toggleSave(p),
                        onLearnMore: () => context.push(Routes.result(p.id!), extra: p),
                      ),
                    ),
                  if (finds.loadingMore) const Padding(padding: EdgeInsets.all(16), child: LoadingView()),
                  if (finds.loadMoreError != null)
                    TextButton(
                        onPressed: controller.loadMore,
                        child: Text(context.tr('Could not load more — tap to retry'),
                            style: AppText.montserrat(size: 13, color: AppColors.orangeDeep))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------- header
class _Header extends StatelessWidget {
  const _Header({required this.user});
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.orangeGradient),
              child: Image.asset('assets/images/logo_mark.png', fit: BoxFit.contain),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Crystal Genie',
                  maxLines: 1, style: AppText.playfair(size: 22, weight: FontWeight.w700, color: AppColors.orangeDeep)),
            ),
            IconButton(
              key: const Key('home_notifications'),
              tooltip: context.tr('Notifications'),
              onPressed: () => context.push(Routes.notifications),
              icon: const Icon(Icons.notifications_none_rounded, size: 28, color: AppColors.orangeDeep),
            ),
            Semantics(
              button: true,
              label: context.tr('Profile & settings'),
              child: InkWell(
                key: const Key('home_profile_button'),
                customBorder: const CircleBorder(),
                onTap: () => context.push(Routes.profile),
                child: Padding(padding: const EdgeInsets.all(2), child: UserAvatar(user: user, size: 36)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(context.tr('Hi welcome,'), style: AppText.montserrat(size: 14, color: AppColors.darkGrey)),
        Text(user?.firstName ?? '',
            key: const Key('home_user_name'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.playfair(size: 26, weight: FontWeight.w700, color: AppColors.ink)),
      ],
    );
  }
}

// ----------------------------------------------------------------------------- banner carousel
class _BannerCarousel extends ConsumerStatefulWidget {
  const _BannerCarousel();
  @override
  ConsumerState<_BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<_BannerCarousel> {
  static const _slideCount = 3;
  static const _autoPlayEvery = Duration(seconds: 4);
  final _page = PageController();
  int _index = 0;
  Timer? _timer;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    _restartAutoPlay();
  }

  /// Slides advance by themselves every 4 s (pauses while the user is swiping). Tests turn animations off.
  void _restartAutoPlay() {
    _timer?.cancel();
    if (!AppColors.animatedImages) return;
    _timer = Timer.periodic(_autoPlayEvery, (_) {
      if (!mounted || _touching || !_page.hasClients) return;
      _goTo((_index + 1) % _slideCount);
    });
  }

  void _goTo(int i) {
    if (!_page.hasClients) return;
    _page.animateToPage(i, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = ref.watch(modelInfoProvider);
    final slides = <Widget>[
      _AccuracySlide(info: info, onRetry: () => ref.invalidate(modelInfoProvider)),
      _BannerSlide(
        title: context.tr('Identify any crystal in seconds'),
        body: context.tr('Point your camera at a gemstone and our AI tells you what it is.'),
        action: context.tr('Scan now'),
        icon: Icons.document_scanner_outlined,
        onAction: () => context.push(Routes.scan),
      ),
      _BannerSlide(
        title: context.tr('Explore the crystal library'),
        body: info.valueOrNull?.numClasses != null && info.valueOrNull!.numClasses > 0
            ? context.tr('{n} gemstones with verified facts', {'n': info.valueOrNull!.numClasses})
            : '',
        action: context.tr('Open library'),
        icon: Icons.diamond_outlined,
        onAction: () => context.go(Routes.explore),
      ),
    ];
    return Column(
      children: [
        SizedBox(
          height: 196,
          child: Listener(
            onPointerDown: (_) => _touching = true,
            onPointerUp: (_) {
              _touching = false;
              _restartAutoPlay();
            },
            onPointerCancel: (_) => _touching = false,
            child: PageView(
              key: const Key('home_banner'),
              controller: _page,
              physics: const PageScrollPhysics(parent: BouncingScrollPhysics()),
              onPageChanged: (i) => setState(() => _index = i),
              children: [for (final s in slides) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: s)],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < slides.length; i++)
              GestureDetector(
                key: Key('banner_dot_$i'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _goTo(i);
                  _restartAutoPlay();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _index ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? AppColors.orangeDeep : AppColors.orange.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Orange gradient card with the white Crystal Genie mark on the right (banner style of the reference).
/// Width of the diamond in the banner's bottom-right corner; lower text keeps clear of it.
const double _diamondWidth = 128;
const EdgeInsets _clearOfDiamond = EdgeInsets.only(right: _diamondWidth - 6);

class _OrangePanel extends StatelessWidget {
  const _OrangePanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: AppColors.orangeGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: AppColors.orangeDeep.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              right: 10,
              bottom: 12,
              // Rotating diamond in the bottom-right corner (from the client's GIF, black background removed → animated WebP with alpha).
              child: Image.asset(AppColors.animatedImages ? 'assets/images/diamond.webp' : 'assets/images/diamond.png',
                  key: const Key('banner_diamond'),
                  width: _diamondWidth,
                  height: _diamondWidth * 229 / 330,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(18, 16, 18, 14), child: child),
          ],
        ),
      );
}

class _BannerSlide extends StatelessWidget {
  const _BannerSlide({required this.title, required this.body, required this.action, required this.icon, required this.onAction});
  final String title;
  final String body;
  final String action;
  final IconData icon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => _OrangePanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.montserrat(size: 16, weight: FontWeight.w800, color: Colors.white, height: 1.2)),
            const SizedBox(height: 6),
            Expanded(
              child: Padding(
                padding: _clearOfDiamond,
                child: Text(body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.montserrat(size: 12.5, color: Colors.white, height: 1.35)),
              ),
            ),
            _WhitePillButton(label: action, icon: icon, onTap: onAction),
          ],
        ),
      );
}

class _AccuracySlide extends StatelessWidget {
  const _AccuracySlide({required this.info, required this.onRetry});
  final AsyncValue<ModelInfo> info;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final white = AppText.montserrat(size: 11, color: Colors.white, weight: FontWeight.w600);
    return _OrangePanel(
      child: info.when(
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (_, __) => Row(children: [
          Expanded(
            child: Text(context.tr('Model info unavailable — start the backend to see the accuracy.'),
                style: AppText.montserrat(size: 13, color: Colors.white, weight: FontWeight.w600)),
          ),
          IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh, color: Colors.white)),
        ]),
        data: (m) => Column(
          key: const Key('home_model_accuracy'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('AI model accuracy').toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.montserrat(size: 13, weight: FontWeight.w800, color: Colors.white)),
            Text(ModelInfo.pct(m.testAccuracy),
                key: const Key('home_accuracy_value'),
                style: AppText.montserrat(size: 32, weight: FontWeight.w800, color: Colors.white, height: 1.1)),
            if (m.testSamples != null)
              Text(context.tr('Tested on {n} photos the model never saw', {'n': m.testSamples}),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.montserrat(size: 11.5, color: Colors.white, height: 1.25)),
            const SizedBox(height: 6),
            // Chips sit at the bottom-left, beside the diamond; they shrink a little if a language needs more room.
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Align(
                  alignment: Alignment.bottomLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.bottomLeft,
                    child: SizedBox(
                      width: c.maxWidth - _clearOfDiamond.right,
                      child: Wrap(spacing: 6, runSpacing: 5, children: [
                        _StatChip('${context.tr('Top-3 accuracy')} ${ModelInfo.pct(m.top3Accuracy)}', style: white),
                        _StatChip('${context.tr('Macro F1')} ${m.f1Macro?.toStringAsFixed(2) ?? '—'}', style: white),
                        _StatChip('${context.tr('Gemstone types')} ${m.numClasses}', style: white),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(this.text, {required this.style});
  final String text;
  final TextStyle style;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: style),
      );
}

class _WhitePillButton extends StatelessWidget {
  const _WhitePillButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: AppColors.orangeDeep),
              const SizedBox(width: 6),
              Text(label, style: AppText.montserrat(size: 13, weight: FontWeight.w700, color: AppColors.orangeDeep)),
            ]),
          ),
        ),
      );
}

// ----------------------------------------------------------------------------- quick actions
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> upload() => chooseUploadSource(context, ref);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: _cardDecoration,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _QuickAction(key: const Key('quick_scan'), icon: Icons.document_scanner_outlined, label: context.tr('Scan'),
              onTap: () => context.push(Routes.scan)),
          _QuickAction(key: const Key('quick_upload'), icon: Icons.photo_library_outlined, label: context.tr('Upload'),
              onTap: upload),
          _QuickAction(key: const Key('quick_explore'), icon: Icons.diamond_outlined, label: context.tr('Explore'),
              onTap: () => context.go(Routes.explore)),
          _QuickAction(key: const Key('quick_saved'), icon: Icons.collections_bookmark_outlined, label: context.tr('Saved'),
              onTap: () => context.go(Routes.saved)),
        ],
      ),
    );
  }
}

final _cardDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
);

class _QuickAction extends StatelessWidget {
  const _QuickAction({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 76,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.sand, width: 1.4),
                ),
                child: Icon(icon, size: 26, color: AppColors.ink),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: AppText.montserrat(size: 12.5, weight: FontWeight.w600, color: AppColors.darkGrey)),
              ),
            ]),
          ),
        ),
      );
}

// ----------------------------------------------------------------------------- my collection
class _CollectionCard extends ConsumerWidget {
  const _CollectionCard({required this.totalScans});
  final int? totalScans;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedListProvider);
    final savedTotal = saved.isInitialLoading || (saved.error != null && saved.items.isEmpty) ? null : saved.total;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: _cardDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('My collection'),
              style: AppText.montserrat(size: 15.5, weight: FontWeight.w700, color: AppColors.darkGrey)),
          const SizedBox(height: 10),
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const Key('home_collection'),
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.go(Routes.saved),
              child: Ink(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                decoration: BoxDecoration(gradient: AppColors.orangeGradient, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Expanded(child: _Stat(label: context.tr('Total scans'), value: totalScans)),
                    Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.4)),
                    const SizedBox(width: 14),
                    Expanded(child: _Stat(label: context.tr('Saved crystals'), value: savedTotal)),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.chevron_right, color: AppColors.orangeDeep),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final int? value;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppText.montserrat(size: 12, weight: FontWeight.w600, color: Colors.white)),
          Text(value == null ? '—' : '$value',
              style: AppText.montserrat(size: 24, weight: FontWeight.w800, color: Colors.white)),
        ],
      );
}

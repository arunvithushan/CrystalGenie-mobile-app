import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/gem_cards.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/headers.dart';
import '../../../shared/widgets/images.dart';
import '../../../shared/widgets/state_views.dart';
import '../../saved/application/collection_providers.dart';
import '../application/result_providers.dart';
import 'gem_info.dart';
import '../../../core/l10n/l10n.dart';

/// Figma "Result" / "Result - saved" / "Result - Scrolled".
class ResultScreen extends ConsumerStatefulWidget {
  const ResultScreen({super.key, required this.predictionId, this.initial, this.localImagePath});
  final String predictionId;
  final Prediction? initial;
  final String? localImagePath;

  @override
  ConsumerState<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends ConsumerState<ResultScreen> {
  bool? _savedOverride;
  String? _savedIdOverride;
  bool? _favOverride;
  bool _busySave = false;
  bool _busyFav = false;

  bool get _isStored => widget.predictionId != 'local';

  Future<void> _toggleSave(Prediction p) async {
    if (!_isStored || p.id == null) return;
    setState(() => _busySave = true);
    final current = p.copyWith(isSaved: _savedOverride ?? p.isSaved, savedId: _savedIdOverride ?? p.savedId);
    try {
      final newId = await ref.read(collectionActionsProvider).toggleSaved(current);
      if (!mounted) return;
      setState(() {
        _savedOverride = newId != null;
        _savedIdOverride = newId;
      });
      showSnack(context, newId != null ? context.tr('Saved to My Finds') : context.tr('Removed from My Finds'));
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busySave = false);
    }
  }

  Future<void> _toggleFavorite(GemstoneDetail gem) async {
    setState(() => _busyFav = true);
    try {
      final fav = await ref
          .read(collectionActionsProvider)
          .toggleFavorite(gem.id, currentlyFavorite: _favOverride ?? gem.isFavorite);
      if (!mounted) return;
      setState(() => _favOverride = fav);
      showSnack(context, fav ? context.tr('Added {name} to Favorites', {'name': gem.name}) : context.tr('Removed from Favorites'));
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busyFav = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = _isStored ? ref.watch(predictionByIdProvider(widget.predictionId)) : null;
    final p = async?.valueOrNull ?? widget.initial;

    Widget body;
    if (p == null) {
      body = async?.hasError == true
          ? ErrorView(
              message: errorMessage(async!.error!),
              onRetry: () => ref.invalidate(predictionByIdProvider(widget.predictionId)))
          : LoadingView(message: context.tr('Loading result…'));
    } else {
      body = _content(p);
    }
    return PopScope(
      canPop: context.canPop(),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(Routes.home);
      },
      child: SafeArea(bottom: false, child: body),
    );
  }

  Widget _content(Prediction p) {
    final saved = _savedOverride ?? p.isSaved;
    final gem = p.gemstone;
    final fav = _favOverride ?? gem?.isFavorite ?? false;
    final title = p.isUncertain ? context.tr('Uncertain identification') : p.displayName;

    return ListView(
      key: const Key('result_list'),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 130),
      children: [
        BigTitleHeader(
          title: p.isUncertain ? context.tr('Hmm, not sure') : context.tr("You've got a"),
          pill: Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(title,
                    key: const Key('result_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.playfair(size: p.isUncertain ? 19 : 24, weight: FontWeight.w700)),
              ),
              if (_isStored)
                IconButton(
                  key: const Key('result_bookmark'),
                  tooltip: saved ? context.tr('Remove from My Finds') : context.tr('Save to My Finds'),
                  onPressed: _busySave ? null : () => _toggleSave(p),
                  icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, size: 28, color: AppColors.ink),
                ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        // Uploaded photo with the info panel overlapping its lower edge (Figma).
        Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: AspectRatio(
                aspectRatio: 0.9,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                  ),
                  child: ApiImage(p.imageUrl, localFile: widget.localImagePath, radius: 17),
                ),
              ),
            ),
          ],
        ),
        Transform.translate(
          offset: const Offset(0, -36),
          child: GlassCard(
            radius: 18,
            opacity: 0.72,
            blur: 18,
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (p.isUncertain) _uncertainBlock(p) else ...[
                  Text(gem?.name ?? p.displayName, style: AppText.playfair(size: 28, weight: FontWeight.w700)),
                  if (gem != null && gem.tagline.isNotEmpty)
                    Text(gem.tagline,
                        style: AppText.montserrat(size: 14, style: FontStyle.italic, color: AppColors.grey.withValues(alpha: 0.8))),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    Pill(context.tr('{pct}% confidence', {'pct': p.confidencePercent}),
                        key: const Key('result_confidence'), icon: Icons.verified_outlined, filled: true),
                    for (final w in p.qualityWarnings) Pill(context.tr(_warningText(w)), color: AppColors.warning, icon: Icons.info_outline),
                  ]),
                  const SizedBox(height: 12),
                  if (gem != null) GemAttributeRow(gem: gem),
                ],
                const SizedBox(height: 16),
                Text(context.tr('Top 3 matches'), style: AppText.montserrat(size: 16, weight: FontWeight.w700, color: AppColors.navy)),
                const SizedBox(height: 4),
                TopPredictionsList(
                  items: p.topPredictions,
                  onTap: (t) => context.push(Routes.gem(t.gemstoneId!)),
                ),
                const SizedBox(height: 14),
                if (!p.isUncertain && gem != null) GemInfoSections(gem: gem),
                if (!p.isUncertain && gem == null)
                  Text(context.tr('No library information is available for this crystal yet.'),
                      style: AppText.montserrat(size: 14, color: AppColors.grey)),
                const SizedBox(height: 22),
                if (_isStored)
                  GradientButton(
                    key: const Key('result_save'),
                    label: saved ? context.tr('Saved to My Finds') : context.tr('Save to My Finds'),
                    icon: saved ? Icons.bookmark : Icons.bookmark_add_outlined,
                    loading: _busySave,
                    onPressed: () => _toggleSave(p),
                  ),
                if (gem != null && !p.isUncertain) ...[
                  const SizedBox(height: 10),
                  TintButton(
                    key: const Key('result_favorite'),
                    label: fav ? context.tr('In Favorites') : context.tr('Add to Favorites'),
                    icon: fav ? Icons.favorite : Icons.favorite_border,
                    onPressed: _busyFav ? null : () => _toggleFavorite(gem),
                    expand: true,
                    height: 44,
                  ),
                ],
                const SizedBox(height: 10),
                TintButton(
                  key: const Key('result_scan_again'),
                  label: context.tr('Scan again'),
                  icon: Icons.document_scanner_outlined,
                  onPressed: () => context.push(Routes.scan),
                  expand: true,
                  height: 44,
                ),
                const SizedBox(height: 12),
                Text('Model ${p.modelVersion} · ${p.latencyMs.toStringAsFixed(0)} ms',
                    style: AppText.montserrat(size: 10.5, color: AppColors.slate)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _uncertainBlock(Prediction p) => Column(
        key: const Key('result_uncertain'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.help_outline, color: AppColors.warning, size: 26),
            const SizedBox(width: 8),
            Expanded(child: Text(context.tr('Uncertain identification'), style: AppText.playfair(size: 24, weight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),
          Text(
            p.uncertaintyReason == 'unlike_training_data'
                ? context.tr("This photo does not look like any of the gemstones the model was trained on, so we won't guess. "
                    'Make sure a single crystal fills most of the frame.')
                : context.tr('The model is only {pct}% confident, which is below its reliability threshold '
                    "({thr}%). We won't pretend to know — please take a clearer photograph.",
                    {'pct': p.confidencePercent, 'thr': (p.threshold * 100).round()}),
            key: const Key('uncertain_explanation'),
            style: AppText.montserrat(size: 14, height: 1.45),
          ),
          const SizedBox(height: 12),
          for (final tip in const [
            'Use bright, even daylight — avoid strong shadows and flash glare',
            'Place one stone on a plain, neutral background',
            'Fill most of the frame with the crystal and keep it in focus',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle_outline, size: 16, color: AppColors.teal),
                const SizedBox(width: 6),
                Expanded(child: Text(context.tr(tip), style: AppText.montserrat(size: 13, color: AppColors.darkGrey))),
              ]),
            ),
          if (p.qualityWarnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final w in p.qualityWarnings) Pill(context.tr(_warningText(w)), color: AppColors.warning, icon: Icons.info_outline)
            ]),
          ],
        ],
      );

  String _warningText(String code) => switch (code) {
        'blurry' => 'Photo looks blurry',
        'too_dark' => 'Photo is too dark',
        'overexposed' => 'Photo is overexposed',
        _ => code,
      };
}

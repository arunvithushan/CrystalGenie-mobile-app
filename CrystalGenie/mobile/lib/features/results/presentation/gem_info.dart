import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/gem_cards.dart';
import '../../../core/l10n/l10n.dart';

/// Icon + value row under the gem name (Figma shows two attributes with small line icons).
class GemAttributeRow extends StatelessWidget {
  const GemAttributeRow({super.key, required this.gem});
  final GemstoneDetail gem;

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String text, String semantics) => Semantics(
          label: semantics,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: AppColors.ink),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: AppText.montserrat(size: 14, weight: FontWeight.w600))),
          ]),
        );
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        item(Icons.diamond_outlined, gem.hardnessLabel == null ? context.tr('Mohs N/A') : 'Mohs ${gem.hardnessLabel}', context.tr('Hardness')),
        item(Icons.hub_outlined, gem.category, context.tr('Category')),
        if (!gem.isNatural) Pill(context.tr('Man-made'), color: AppColors.info),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.icon, this.note});
  final String title;
  final Widget child;
  final IconData? icon;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (icon != null) ...[Icon(icon, size: 18, color: AppColors.teal), const SizedBox(width: 6)],
              Expanded(child: Text(title, style: AppText.montserrat(size: 16, weight: FontWeight.w700, color: AppColors.navy))),
            ]),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(note!,
                    style: AppText.montserrat(size: 11.5, style: FontStyle.italic, color: AppColors.grey)),
              ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

TextStyle get _body => AppText.montserrat(size: 14.5, height: 1.45, color: AppColors.ink);

/// Every verified fact we have about a gemstone, plus clearly-labelled cultural beliefs.
class GemInfoSections extends StatelessWidget {
  const GemInfoSections({super.key, required this.gem});
  final GemstoneDetail gem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(gem.description, style: _body),
        if (gem.colors.isNotEmpty || gem.characteristics.isNotEmpty)
          _Section(
            title: context.tr('Colour & physical characteristics'),
            icon: Icons.palette_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (gem.colors.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final c in gem.colors) Pill(c[0].toUpperCase() + c.substring(1))],
                    ),
                  ),
                for (final e in gem.characteristics.entries) _kv(e.key, e.value),
              ],
            ),
          ),
        _Section(
          title: context.tr('Mineral family & hardness'),
          icon: Icons.science_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (gem.mineralFamily != null) _kv(context.tr('Family'), gem.mineralFamily!),
              if (gem.chemicalFormula != null) _kv(context.tr('Composition'), gem.chemicalFormula!),
              _kv(context.tr('Mohs hardness'), gem.hardnessLabel ?? context.tr('Not available')),
              _kv(context.tr('Category'), gem.category),
            ],
          ),
        ),
        if (gem.sources.isNotEmpty)
          _Section(
            title: context.tr('Typical sources'),
            icon: Icons.public,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final s in gem.sources)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('•  ', style: _body),
                      Expanded(child: Text(s, style: _body)),
                    ]),
                  ),
              ],
            ),
          ),
        if (gem.traditionalMeanings != null)
          _Section(
            title: context.tr('Traditional meanings'),
            icon: Icons.auto_awesome_outlined,
            note: context.tr('Cultural beliefs and folklore — not scientific or medical claims.'),
            child: Text(gem.traditionalMeanings!, key: const Key('traditional_meanings'), style: _body),
          ),
        if (gem.careInstructions != null)
          _Section(title: context.tr('Care instructions'), icon: Icons.spa_outlined, child: Text(gem.careInstructions!, style: _body)),
        if (gem.references.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(context.tr('Reference: {refs}', {'refs': gem.references.join(' · ')}),
                style: AppText.montserrat(size: 11, color: AppColors.slate)),
          ),
      ],
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k, style: AppText.montserrat(size: 13.5, color: AppColors.grey))),
            Expanded(child: Text(v, style: AppText.montserrat(size: 13.5, weight: FontWeight.w500))),
          ],
        ),
      );
}

/// Top-k bars ("Top three predicted classes").
class TopPredictionsList extends StatelessWidget {
  const TopPredictionsList({super.key, required this.items, this.onTap});
  final List<TopPrediction> items;
  final void Function(TopPrediction)? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            key: Key('top_prediction_$i'),
            onTap: onTap == null || items[i].gemstoneId == null ? null : () => onTap!(items[i]),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${i + 1}. ', style: AppText.montserrat(size: 14, color: AppColors.grey)),
                      Expanded(
                        child: Text(items[i].displayName,
                            style: AppText.montserrat(size: 14.5, weight: i == 0 ? FontWeight.w700 : FontWeight.w500)),
                      ),
                      Text('${(items[i].confidence * 100).toStringAsFixed(1)}%',
                          style: AppText.montserrat(size: 14, weight: FontWeight.w600, color: AppColors.teal)),
                      if (onTap != null && items[i].gemstoneId != null)
                        const Icon(Icons.chevron_right, size: 18, color: AppColors.slate),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: items[i].confidence.clamp(0, 1),
                      minHeight: 6,
                      backgroundColor: AppColors.mint.withValues(alpha: 0.25),
                      color: i == 0 ? AppColors.teal : AppColors.mint,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

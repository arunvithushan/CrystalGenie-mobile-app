import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'buttons.dart';
import 'glass.dart';
import 'images.dart';
import '../../core/l10n/l10n.dart';

/// List card used on Home "Recent Finds" and Saved "My finds" (image left, name, text, bookmark + Learn more).
class FindListCard extends StatelessWidget {
  const FindListCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.caption,
    required this.imagePath,
    required this.bookmarked,
    required this.onBookmark,
    required this.onLearnMore,
    this.badge,
    this.localImage,
  });

  final String title;
  final String subtitle;
  final String? caption;
  final String? imagePath;
  final String? localImage;
  final bool bookmarked;
  final VoidCallback? onBookmark;
  final VoidCallback onLearnMore;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(5),
      onTap: onLearnMore,
      child: SizedBox(
        height: 136, // room for title, 3-line subtitle, date and buttons without overflow
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ApiImage(imagePath, localFile: localImage, radius: 14),
                  if (badge != null) Positioned(left: 6, top: 6, child: badge!),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.playfair(size: 23, height: 1.15)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.montserrat(size: 10, color: AppColors.darkGrey, height: 1.3)),
                    if (caption != null) ...[
                      const SizedBox(height: 4),
                      Text(caption!, style: AppText.montserrat(size: 9, color: AppColors.grey.withValues(alpha: 0.8))),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        TintButton(
                          icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
                          tooltip: bookmarked ? 'Remove' : 'Save',
                          onPressed: onBookmark,
                          height: 34,
                          fontSize: 16,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GradientButton(
                            label: context.tr('Learn more'),
                            icon: Icons.chevron_right,
                            onPressed: onLearnMore,
                            height: 34,
                            fontSize: 15,
                            radius: 8,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explore "Crystal library" card: image, Playfair name, grey tagline, description.
class LibraryCard extends StatelessWidget {
  const LibraryCard({
    super.key,
    required this.name,
    required this.tagline,
    required this.description,
    required this.imagePath,
    required this.onTap,
    this.isFavorite = false,
  });

  final String name;
  final String tagline;
  final String description;
  final String? imagePath;
  final VoidCallback onTap;
  final bool isFavorite;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(5),
      onTap: onTap,
      child: SizedBox(
        height: 128,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 1, child: ApiImage(imagePath, radius: 14)),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.playfair(size: 23, height: 1.15)),
                        ),
                        if (isFavorite) const Icon(Icons.bookmark, size: 16, color: AppColors.teal),
                      ],
                    ),
                    Text(tagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.montserrat(size: 9.5, color: AppColors.grey.withValues(alpha: 0.75))),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(description,
                          overflow: TextOverflow.fade,
                          style: AppText.montserrat(size: 10, color: AppColors.ink, height: 1.3)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Saved "Tiles layout" card.
class TileCard extends StatelessWidget {
  const TileCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.bookmarked,
    required this.onBookmark,
    required this.onLearnMore,
  });

  final String title;
  final String subtitle;
  final String? imagePath;
  final bool bookmarked;
  final VoidCallback? onBookmark;
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      radius: 18,
      padding: const EdgeInsets.all(5),
      onTap: onLearnMore,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: 1, child: ApiImage(imagePath, radius: 14)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.playfair(size: 21)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(subtitle,
                  overflow: TextOverflow.fade, style: AppText.montserrat(size: 9.5, color: AppColors.darkGrey, height: 1.3)),
            ),
          ),
          const SizedBox(height: 6),
          TintButton(
            icon: bookmarked ? Icons.bookmark : Icons.bookmark_border,
            onPressed: onBookmark,
            expand: true,
            height: 32,
            tooltip: bookmarked ? 'Remove' : 'Save',
          ),
          const SizedBox(height: 6),
          GradientButton(label: context.tr('Learn more'), icon: Icons.chevron_right, onPressed: onLearnMore, height: 34, fontSize: 15, radius: 8),
        ],
      ),
    );
  }
}

/// Small rounded label (e.g. "Uncertain", confidence).
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = AppColors.teal, this.filled = false, this.icon});
  final String text;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: filled ? color : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 13, color: filled ? Colors.white : color), const SizedBox(width: 4)],
            Text(text, style: AppText.montserrat(size: 11, weight: FontWeight.w600, color: filled ? Colors.white : color)),
          ],
        ),
      );
}

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'glass.dart';

/// The Figma header pattern: a large teal title that sits *behind* a frosted pill,
/// so the lower half of the title is softly blurred (e.g. "Hi welcome," / "Crystal library").
class BigTitleHeader extends StatelessWidget {
  const BigTitleHeader({super.key, required this.title, required this.pill, this.pillHeight = 50});

  final String title;
  final Widget pill;
  final double pillHeight;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28 + pillHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.visible,
              style: AppText.montserrat(size: 34, weight: FontWeight.w500, color: AppColors.teal, height: 1.1),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 22,
            height: pillHeight,
            child: GlassCard(
              radius: 16,
              opacity: 0.45,
              blur: 6,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Center(child: pill),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section heading ("Recent Finds").
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(text, style: AppText.montserrat(size: 24, weight: FontWeight.w600, color: AppColors.ink))),
          if (trailing != null) trailing!,
        ],
      );
}

/// "< Back" text button used on Profile.
class BackTextButton extends StatelessWidget {
  const BackTextButton({super.key, required this.onPressed, this.label = 'Back'});
  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        onPressed: onPressed,
        style: TextButton.styleFrom(foregroundColor: AppColors.ink, padding: const EdgeInsets.symmetric(horizontal: 4)),
        icon: const Icon(Icons.chevron_left, size: 22),
        label: Text(label, style: AppText.montserrat(size: 17, weight: FontWeight.w500)),
      );
}

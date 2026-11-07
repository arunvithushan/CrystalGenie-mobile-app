import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Orange gradient button (Figma "Learn more", "Logout", "Save").
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 44,
    this.fontSize = 16,
    this.loading = false,
    this.expand = true,
    this.radius = 10,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;
  final double fontSize;
  final bool loading;
  final bool expand;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    final r = BorderRadius.circular(radius);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          height: height,
          width: expand ? double.infinity : null,
          decoration: BoxDecoration(
            gradient: AppColors.buttonGradient,
            borderRadius: r,
            boxShadow: [BoxShadow(color: AppColors.teal.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: r,
              onTap: enabled ? onPressed : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (loading)
                      const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    else ...[
                      Flexible(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.montserrat(size: fontSize, weight: FontWeight.w600, color: Colors.white)),
                      ),
                      if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: fontSize + 2, color: Colors.white)],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Light mint, bordered button (Figma "Edit profile", "Try scanning your first crystal", bookmark square).
class TintButton extends StatelessWidget {
  const TintButton({
    super.key,
    this.label,
    this.icon,
    required this.onPressed,
    this.height = 40,
    this.fontSize = 15,
    this.iconAfter = false,
    this.expand = false,
    this.tooltip,
  });

  final String? label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;
  final double fontSize;
  final bool iconAfter;
  final bool expand;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(8);
    final iconW = icon == null ? null : Icon(icon, size: fontSize + 3, color: AppColors.teal);
    final btn = Material(
      color: AppColors.mint.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(borderRadius: r, side: const BorderSide(color: AppColors.mint)),
      child: InkWell(
        borderRadius: r,
        onTap: onPressed,
        child: SizedBox(
          height: height,
          width: expand ? double.infinity : (label == null ? height * 1.3 : null),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (iconW != null && !iconAfter) iconW,
                if (iconW != null && label != null) const SizedBox(width: 8),
                if (label != null)
                  Flexible(
                    child: Text(label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.montserrat(size: fontSize, color: AppColors.teal)),
                  ),
                if (iconW != null && iconAfter) iconW,
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Muted red button (Figma "Delete account").
class DangerButton extends StatelessWidget {
  const DangerButton({super.key, required this.label, required this.onPressed, this.icon = Icons.delete_outline});
  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(10);
    return Material(
      color: AppColors.error.withValues(alpha: 0.16),
      shape: RoundedRectangleBorder(borderRadius: r, side: BorderSide(color: AppColors.error.withValues(alpha: 0.35))),
      child: InkWell(
        borderRadius: r,
        onTap: onPressed,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: AppText.montserrat(size: 17, color: AppColors.error.withValues(alpha: 0.85))),
              const SizedBox(width: 8),
              Icon(icon, size: 19, color: AppColors.error.withValues(alpha: 0.85)),
            ],
          ),
        ),
      ),
    );
  }
}

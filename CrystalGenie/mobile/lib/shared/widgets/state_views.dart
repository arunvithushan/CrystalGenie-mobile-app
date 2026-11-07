import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'app_icons.dart';
import 'buttons.dart';
import 'glass.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (message != null) ...[
                const SizedBox(height: 14),
                Text(message!, textAlign: TextAlign.center, style: AppText.montserrat(size: 14, color: AppColors.darkGrey)),
              ],
            ],
          ),
        ),
      );
}

/// Glass card with an icon, a message and an optional action (Figma "Home - Empty").
class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.message, this.actionLabel, this.onAction, this.actionIcon, this.icon});
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => GlassCard(
        radius: 18,
        borderColor: AppColors.mint,
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              icon ?? const CgIcon(CgIconType.emptyBox, size: 32, color: AppColors.ink),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center, style: AppText.montserrat(size: 16, color: AppColors.ink)),
              if (actionLabel != null) ...[
                const SizedBox(height: 18),
                TintButton(label: actionLabel, icon: actionIcon, iconAfter: true, onPressed: onAction, fontSize: 16),
              ],
            ],
          ),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.compact = false});
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off_rounded, size: compact ? 28 : 40, color: AppColors.slate),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center, style: AppText.montserrat(size: 14.5, color: AppColors.darkGrey)),
        if (onRetry != null) ...[
          const SizedBox(height: 14),
          TintButton(label: 'Try again', icon: Icons.refresh_rounded, onPressed: onRetry),
        ],
      ],
    );
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: GlassCard(padding: const EdgeInsets.all(20), borderColor: AppColors.mint, child: content),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {bool error = false, SnackBarAction? action}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.error : AppColors.deepTeal,
    action: action,
    duration: Duration(seconds: error ? 4 : 2),
  ));
}

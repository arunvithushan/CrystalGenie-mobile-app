import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'app_icons.dart';
import 'glass.dart';
import '../../core/l10n/l10n.dart';

enum NavTab { home, explore, none }

/// Floating frosted pill with Home · Scan · Explore (Figma bottom navigation).
class CgBottomNav extends StatelessWidget {
  const CgBottomNav(
      {super.key, required this.current, required this.onHome, required this.onScan, required this.onExplore, this.orange = false});

  final NavTab current;
  final VoidCallback onHome;
  final VoidCallback onScan;
  final VoidCallback onExplore;

  /// Orange accents on the redesigned Home page; teal everywhere else (Figma).
  final bool orange;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          height: 78,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                top: 8,
                bottom: 2,
                child: GlassCard(radius: 40, opacity: 0.62, blur: 18, padding: EdgeInsets.zero, child: SizedBox()),
              ),
              Positioned.fill(
                top: 8,
                bottom: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _NavItem(
                        key: const Key('nav_home'),
                        label: context.tr('Home'),
                        icon: CgIconType.home,
                        active: current == NavTab.home,
                        orange: orange,
                        onTap: onHome,
                      ),
                      _NavItem(
                        key: const Key('nav_explore'),
                        label: context.tr('Explore crystal library'),
                        icon: CgIconType.gem,
                        active: current == NavTab.explore,
                        orange: orange,
                        onTap: onExplore,
                      ),
                    ],
                  ),
                ),
              ),
              _ScanButton(onTap: onScan, orange: orange),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({super.key, required this.label, required this.icon, required this.active, required this.onTap, this.orange = false});
  final bool orange;
  final String label;
  final CgIconType icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 30,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? (orange ? AppColors.orange : AppColors.mint.withValues(alpha: 0.75)) : Colors.transparent,
            border: active ? Border.all(color: orange ? AppColors.orangeDeep : AppColors.mint) : null,
          ),
          alignment: Alignment.center,
          child: CgIcon(icon, size: 30, color: active ? Colors.white : (orange ? AppColors.orangeDeep : AppColors.navy)),
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onTap, this.orange = false});
  final VoidCallback onTap;
  final bool orange;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.tr('Scan a crystal'),
      child: GestureDetector(
        key: const Key('nav_scan'),
        onTap: onTap,
        child: Container(
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: orange
                ? const RadialGradient(colors: [Color(0xFFF7A35C), AppColors.orangeDeep], radius: 0.75)
                : const RadialGradient(colors: [Color(0xFFF7A35C), AppColors.teal], radius: 0.75),
            boxShadow: [BoxShadow(color: (orange ? AppColors.orangeDeep : AppColors.teal).withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))],
          ),
          alignment: Alignment.center,
          child: const CgIcon(CgIconType.scan, size: 38),
        ),
      ),
    );
  }
}

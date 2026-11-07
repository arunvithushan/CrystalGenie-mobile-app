import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Soft mint/white background with blurred colour blobs, as used on every Figma screen.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgTop, Color(0xFFFBF3EE), AppColors.bgBottom],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: CustomPaint(painter: _BlobPainter())),
          child,
        ],
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  const _BlobPainter();

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset c, double r, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, paint);
    }

    blob(Offset(size.width * 0.15, size.height * 0.62), size.width * 0.75, const Color(0x33F7A35C));
    blob(Offset(size.width * 0.95, size.height * 0.35), size.width * 0.6, const Color(0x26F6C29B));
    blob(Offset(size.width * 0.9, size.height * 0.88), size.width * 0.55, const Color(0x22EF7D10));
    blob(Offset(size.width * 0.5, size.height * 0.05), size.width * 0.7, const Color(0x1FF6C29B));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Frosted-glass card (BackdropFilter blur + translucent white + hairline border).
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(6),
    this.radius = 18,
    this.border = true,
    this.opacity = 0.55,
    this.blur = 14,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool border;
  final double opacity;
  final double blur;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) content = InkWell(borderRadius: r, onTap: onTap, child: content);
    // A transparent Material inside the tinted box so ListTiles / ink splashes paint on top of it.
    content = Material(type: MaterialType.transparency, child: content);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: r,
            color: Colors.white.withValues(alpha: opacity),
            border: border ? Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.7), width: 1) : null,
          ),
          child: content,
        ),
      ),
    );
  }
}

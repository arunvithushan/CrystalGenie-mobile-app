import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/config/app_config.dart';
import '../../core/storage/token_storage.dart';
import '../models/models.dart';

/// Network image that resolves API-relative URLs and adds the bearer token for `/api/...` paths.
class ApiImage extends ConsumerWidget {
  const ApiImage(this.path, {super.key, this.fit = BoxFit.cover, this.radius = 14, this.width, this.height, this.localFile});

  final String? path;
  final BoxFit fit;
  final double radius;
  final double? width;
  final double? height;

  /// Show a local file instead (e.g. the photo the user just took) — avoids a round trip.
  final String? localFile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget child;
    if (localFile != null && File(localFile!).existsSync()) {
      child = Image.file(File(localFile!), fit: fit, width: width, height: height);
    } else if (path == null || path!.isEmpty) {
      child = const _Placeholder();
    } else {
      final base = ref.watch(baseUrlProvider);
      final url = resolveUrl(base, path);
      final needsAuth = path!.startsWith('/api/');
      final token = needsAuth ? ref.watch(accessTokenProvider).valueOrNull : null;
      if (needsAuth && token == null) {
        child = const _Placeholder(loading: true);
      } else {
        child = CachedNetworkImage(
          imageUrl: url,
          cacheKey: url,
          httpHeaders: token == null ? null : {'Authorization': 'Bearer $token'},
          fit: fit,
          width: width,
          height: height,
          fadeInDuration: const Duration(milliseconds: 180),
          placeholder: (_, __) => const _Placeholder(loading: true),
          errorWidget: (_, __, ___) => const _Placeholder(),
        );
      }
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox(width: width, height: height, child: child));
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.loading = false});
  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.mint.withValues(alpha: 0.25),
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.diamond_outlined, color: AppColors.slate, size: 34),
      );
}

/// Round avatar: uploaded photo or initials.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 36});
  final AppUser? user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final u = user;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: size > 60 ? 3 : 1.5),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 6)],
      ),
      child: ClipOval(
        child: (u?.avatarUrl != null)
            ? ApiImage(u!.avatarUrl, radius: size, width: size, height: size)
            : Container(
                color: AppColors.teal,
                alignment: Alignment.center,
                child: Text(u?.initials ?? '', style: AppText.montserrat(size: size * 0.38, weight: FontWeight.w600, color: Colors.white)),
              ),
      ),
    );
  }
}

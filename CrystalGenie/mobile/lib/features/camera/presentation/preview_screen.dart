import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/app_icons.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/state_views.dart';
import '../../home/application/home_providers.dart';
import '../../results/data/prediction_repository.dart';
import '../data/media_services.dart';
import '../../../core/l10n/l10n.dart';

/// Preview the photo, optionally crop it, then upload it for identification.
class PreviewScreen extends ConsumerStatefulWidget {
  const PreviewScreen({super.key, required this.imagePath});
  final String imagePath;

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> {
  late String _path = widget.imagePath;
  bool _uploading = false;
  double _progress = 0;
  String? _error;
  CancelToken? _cancel;

  Future<void> _crop() async {
    try {
      final cropped = await ref.read(imageServiceProvider).crop(_path);
      if (cropped != null && mounted) setState(() => _path = cropped);
    } catch (_) {
      if (mounted) showSnack(context, context.tr('Cropping is not available on this device.'), error: true);
    }
  }

  Future<void> _replace() async {
    final picked = await ref.read(imageServiceProvider).pickFromGallery();
    if (picked != null && mounted) setState(() => _path = picked);
  }

  Future<void> _identify() async {
    final invalid = await validateImageFile(_path);
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }
    setState(() {
      _uploading = true;
      _error = null;
      _progress = 0;
      _cancel = CancelToken();
    });
    try {
      final prediction = await ref.read(predictionRepositoryProvider).predict(
            _path,
            cancelToken: _cancel,
            onProgress: (p) {
              if (mounted) setState(() => _progress = p);
            },
          );
      ref.invalidate(recentFindsProvider);
      if (!mounted) return;
      final id = prediction.id ?? 'local';
      // Replace the whole camera flow with the result screen.
      context.go(Routes.result(id), extra: ResultArgs(prediction, localImagePath: _path));
    } on ApiException catch (e) {
      if (e.code == 'cancelled') return;
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_uploading,
      child: Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: context.tr('Retake'),
                            onPressed: _uploading ? null : () => context.pop(),
                            icon: const Icon(Icons.chevron_left, size: 30),
                          ),
                          Expanded(
                            child: Text(context.tr('Looks good?'),
                                textAlign: TextAlign.center, style: AppText.montserrat(size: 18, weight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 40),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                        child: GlassCard(
                          padding: const EdgeInsets.all(6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(File(_path), key: ValueKey(_path), fit: BoxFit.cover, width: double.infinity,
                                errorBuilder: (_, __, ___) => Center(child: Text(context.tr('Cannot display this image')))),
                          ),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Container(
                          key: const Key('preview_error'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                          ),
                          child: Text(_error!, style: AppText.montserrat(size: 13.5, color: AppColors.error)),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TintButton(
                                  key: const Key('preview_retake'),
                                  label: context.tr('Retake'),
                                  icon: Icons.replay,
                                  onPressed: _uploading ? null : () => context.pop(),
                                  height: 44,
                                  expand: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TintButton(
                                  label: context.tr('Replace'),
                                  icon: Icons.photo_library_outlined,
                                  onPressed: _uploading ? null : _replace,
                                  height: 44,
                                  expand: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TintButton(
                                  key: const Key('preview_crop'),
                                  label: context.tr('Crop'),
                                  icon: Icons.crop,
                                  onPressed: _uploading ? null : _crop,
                                  height: 44,
                                  expand: true,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          GradientButton(
                            key: const Key('preview_identify'),
                            label: context.tr('Identify crystal'),
                            icon: Icons.auto_awesome,
                            onPressed: _uploading ? null : _identify,
                            height: 50,
                            fontSize: 17,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_uploading)
                  Positioned.fill(
                    child: ProcessingOverlay(
                      progress: _progress,
                      onCancel: () => _cancel?.cancel(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated "identifying" overlay: a rotating, pulsing gem while the upload + inference run.
class ProcessingOverlay extends StatefulWidget {
  const ProcessingOverlay({super.key, required this.progress, this.onCancel});
  final double progress;
  final VoidCallback? onCancel;

  @override
  State<ProcessingOverlay> createState() => _ProcessingOverlayState();
}

class _ProcessingOverlayState extends State<ProcessingOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uploading = widget.progress < 0.999;
    return Container(
      key: const Key('processing_overlay'),
      color: Colors.white.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: GlassCard(
        borderColor: AppColors.mint,
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, child) {
                final t = _c.value;
                final scale = 1 + 0.08 * math.sin(t * 2 * math.pi);
                return Transform.scale(
                  scale: scale,
                  child: Transform.rotate(angle: t * 2 * math.pi, child: child),
                );
              },
              child: Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Color(0xFFF7A35C), AppColors.teal]),
                ),
                alignment: Alignment.center,
                child: const CgIcon(CgIconType.gem, size: 44, color: Colors.white),
              ),
            ),
            const SizedBox(height: 18),
            Text(uploading ? 'Uploading photo…' : 'Identifying your crystal…',
                style: AppText.montserrat(size: 16, weight: FontWeight.w600, color: AppColors.navy)),
            const SizedBox(height: 10),
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: uploading ? widget.progress : null,
                  minHeight: 6,
                  backgroundColor: AppColors.mint.withValues(alpha: 0.35),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: widget.onCancel, child: Text(context.tr('Cancel'))),
          ],
        ),
      ),
    );
  }
}

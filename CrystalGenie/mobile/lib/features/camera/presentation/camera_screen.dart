import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/media_services.dart';
import '../../../core/l10n/l10n.dart';
import 'upload_source.dart';

/// Figma "Take photo or upload": live camera, framing guide, gallery · shutter · switch camera.
class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

enum _CamState { checking, needsPermission, permanentlyDenied, noCamera, ready, error }

class _CameraScreenState extends ConsumerState<CameraScreen> with WidgetsBindingObserver {
  _CamState _state = _CamState.checking;
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkPermission(request: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      if (c != null && c.value.isInitialized) {
        _controller = null;
        c.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      // Returning from system settings or another app.
      if (_state == _CamState.ready || _state == _CamState.needsPermission || _state == _CamState.permanentlyDenied) {
        _checkPermission(request: false);
      }
    }
  }

  Future<void> _checkPermission({required bool request}) async {
    final perms = ref.read(permissionServiceProvider);
    var status = await perms.cameraStatus();
    if (status == CamPermission.denied && request) status = await perms.requestCamera();
    if (!mounted) return;
    switch (status) {
      case CamPermission.granted:
        await _initCamera();
      case CamPermission.denied:
        setState(() => _state = _CamState.needsPermission);
      case CamPermission.permanentlyDenied:
        setState(() => _state = _CamState.permanentlyDenied);
    }
  }

  Future<void> _initCamera() async {
    try {
      if (_cameras.isEmpty) _cameras = await ref.read(cameraSourceProvider).cameras();
      if (_cameras.isEmpty) {
        if (mounted) setState(() => _state = _CamState.noCamera);
        return;
      }
      final back = _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (_controller == null && back >= 0 && _cameraIndex == 0) _cameraIndex = back;
      final old = _controller;
      _controller = null;
      await old?.dispose();
      final controller = CameraController(_cameras[_cameraIndex], ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off).catchError((_) {});
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _state = _CamState.ready;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = e.code == 'CameraAccessDenied' ? _CamState.needsPermission : _CamState.error;
        _error = e.description ?? 'The camera could not be started.';
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initCamera();
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      if (mounted) context.push(Routes.preview, extra: file.path);
    } on CameraException catch (e) {
      if (mounted) showSnack(context, e.description ?? context.tr('Could not take the photo.'), error: true);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Same file picker as Home > Upload (device, link, Google Drive, This computer); "Camera" there just closes it.
  Future<void> _pickFromGallery() => chooseUploadSource(context, ref, fromCamera: true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFCFC3C1),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreview(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('camera_back'),
                        tooltip: context.tr('Back'),
                        onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home),
                        icon: const Icon(Icons.chevron_left, size: 30, color: AppColors.ink),
                      ),
                      Expanded(
                        child: Text(context.tr('Keep your crystal within the frame'),
                            textAlign: TextAlign.center,
                            style: AppText.montserrat(size: 16, weight: FontWeight.w500, color: AppColors.ink)),
                      ),
                      IconButton(
                        key: const Key('camera_computer'),
                        tooltip: context.tr('This computer'),
                        onPressed: () => context.push(Routes.computer),
                        icon: const Icon(Icons.computer_outlined, size: 26, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
                if (_state == _CamState.ready)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        key: const Key('camera_frame'),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.6),
                        ),
                      ),
                    ),
                  ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                  child: GlassCard(
                    radius: 40,
                    opacity: 0.35,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          key: const Key('camera_gallery'),
                          tooltip: context.tr('Choose from gallery'),
                          onPressed: _pickFromGallery,
                          icon: const Icon(Icons.photo_library_outlined, size: 30, color: AppColors.navy),
                        ),
                        _Shutter(onTap: _state == _CamState.ready ? _capture : null, busy: _capturing),
                        IconButton(
                          key: const Key('camera_switch'),
                          tooltip: context.tr('Switch camera'),
                          onPressed: _state == _CamState.ready && _cameras.length > 1 ? _switchCamera : null,
                          icon: const Icon(Icons.cameraswitch_outlined, size: 30, color: AppColors.navy),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    switch (_state) {
      case _CamState.checking:
        return LoadingView(message: context.tr('Starting camera…'));
      case _CamState.ready:
        final c = _controller;
        if (c == null || !c.value.isInitialized) return const LoadingView();
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.previewSize?.height ?? 1080,
              height: c.value.previewSize?.width ?? 1920,
              child: CameraPreview(c),
            ),
          ),
        );
      case _CamState.needsPermission:
      case _CamState.permanentlyDenied:
        return _Message(
          key: const Key('camera_permission_message'),
          icon: Icons.no_photography_outlined,
          title: context.tr('Camera access needed'),
          text: context.tr('Crystal Genie needs your camera to photograph crystals. You can also choose a photo from your gallery.'),
          actionLabel: _state == _CamState.permanentlyDenied ? context.tr('Open settings') : context.tr('Allow camera'),
          onAction: _state == _CamState.permanentlyDenied
              ? () => ref.read(permissionServiceProvider).openSettings()
              : () => _checkPermission(request: true),
        );
      case _CamState.noCamera:
        return _Message(
          key: const Key('camera_none_message'),
          icon: Icons.videocam_off_outlined,
          title: context.tr('No camera found'),
          text: context.tr('This device has no available camera. Choose a photo from your gallery instead.'),
        );
      case _CamState.error:
        return _Message(
          icon: Icons.error_outline,
          title: context.tr('Camera unavailable'),
          text: _error ?? context.tr('The camera could not be started.'),
          actionLabel: context.tr('Try again'),
          onAction: _initCamera,
        );
    }
  }
}

class _Shutter extends StatelessWidget {
  const _Shutter({required this.onTap, required this.busy});
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: context.tr('Take photo'),
        child: GestureDetector(
          key: const Key('camera_shutter'),
          onTap: busy ? null : onTap,
          child: Container(
            width: 72,
            height: 72,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.teal, width: 3)),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onTap == null ? AppColors.slate : (busy ? AppColors.sky : AppColors.teal),
              ),
            ),
          ),
        ),
      );
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.title, required this.text, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => AppBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: GlassCard(
              borderColor: AppColors.mint,
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 42, color: AppColors.teal),
                  const SizedBox(height: 12),
                  Text(title, style: AppText.montserrat(size: 18, weight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(text, textAlign: TextAlign.center, style: AppText.montserrat(size: 14, color: AppColors.darkGrey)),
                  if (actionLabel != null) ...[
                    const SizedBox(height: 16),
                    GradientButton(label: actionLabel!, onPressed: onAction, expand: false),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

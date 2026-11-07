import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/link_image_service.dart';
import '../data/media_services.dart';

/// "Upload" file picker: a tap area on top, then From device / From link / Camera / Google Drive, and Cancel.
/// "From device" then asks: this phone (file picker) or this computer (folders on the PC).
///
/// [fromCamera] is true when opened on the camera screen, where "Camera" just closes the picker.
Future<void> chooseUploadSource(BuildContext context, WidgetRef ref, {bool fromCamera = false}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true, // above the bottom navigation bar
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheet) => const _UploadSheet(),
  );
  if (!context.mounted || choice == null) return;

  switch (choice) {
    case 'camera':
      if (!fromCamera) context.go(Routes.scan);
      return;
    case 'device':
      final where = await showModalBottomSheet<String>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheet) => const _DeviceSheet(),
      );
      if (!context.mounted || where == null) return;
      if (where == 'computer') {
        context.push(Routes.computer);
      } else {
        await _pickPhoneFile(context, ref);
      }
      return;
    case 'link':
    case 'drive':
      final drive = choice == 'drive';
      final link = await _askForLink(context, drive: drive);
      if (link == null || !context.mounted) return;
      await _downloadLink(context, ref, link, drive: drive);
      return;
    default: // 'phone' — the tap area on top
      await _pickPhoneFile(context, ref);
  }
}

Future<void> _pickPhoneFile(BuildContext context, WidgetRef ref) async {
  try {
    final path = await ref.read(imageServiceProvider).pickFile();
    if (path != null && context.mounted) context.push(Routes.preview, extra: path);
  } catch (_) {
    if (context.mounted) showSnack(context, context.tr('Could not open the file picker.'), error: true);
  }
}

Future<void> _downloadLink(BuildContext context, WidgetRef ref, String link, {required bool drive}) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (d) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('link_downloading'),
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.teal)),
          const SizedBox(width: 18),
          Expanded(child: Text(d.tr('Downloading the photo…'))),
        ]),
      ),
    ),
  );
  String? path;
  String? error;
  try {
    path = await ref.read(linkImageServiceProvider).download(link, driveOnly: drive);
  } on LinkImageException catch (e) {
    error = e.message;
  } catch (_) {
    error = 'Could not download from this link. Check the link and your internet connection.';
  }
  nav.pop(); // close the progress dialog
  if (!context.mounted) return;
  if (path != null) {
    context.push(Routes.preview, extra: path);
  } else {
    showSnack(context, context.tr(error!), error: true);
  }
}

Future<String?> _askForLink(BuildContext context, {required bool drive}) {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _LinkDialog(drive: drive),
  );
}

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({required this.drive});
  final bool drive;
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      resolveImageLink(_ctrl.text, driveOnly: widget.drive); // quick check before closing
      Navigator.pop(context, _ctrl.text.trim());
    } on LinkImageException catch (e) {
      setState(() => _error = context.tr(e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final drive = widget.drive;
    return AlertDialog(
      title: Text(context.tr(drive ? 'Photo from Google Drive' : 'Photo from a link'),
          style: AppText.montserrat(size: 18, weight: FontWeight.w700, color: AppColors.navy)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          context.tr(drive
              ? "Paste the photo's share link. In Drive set it to 'Anyone with the link' first."
              : 'Paste a link to a JPEG, PNG or WEBP photo.'),
          style: AppText.montserrat(size: 13, color: AppColors.darkGrey),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('link_field'),
          controller: _ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: drive ? 'https://drive.google.com/file/d/…' : 'https://…',
            errorText: _error,
            errorMaxLines: 3,
            prefixIcon: Icon(drive ? Icons.cloud_outlined : Icons.link, color: AppColors.slate),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(
          key: const Key('link_ok'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.orangeDeep, foregroundColor: Colors.white),
          onPressed: _submit,
          child: Text(context.tr('Get photo')),
        ),
      ],
    );
  }
}

class _UploadSheet extends StatelessWidget {
  const _UploadSheet();

  @override
  Widget build(BuildContext context) {
    Widget option(String key, Widget icon, String label, String value) => InkWell(
          key: Key(key),
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.pop(context, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              SizedBox(width: 24, height: 24, child: Center(child: icon)),
              const SizedBox(width: 18),
              Expanded(child: Text(context.tr(label), style: AppText.montserrat(size: 15, weight: FontWeight.w500, color: AppColors.ink))),
            ]),
          ),
        );
    const iconColor = AppColors.darkGrey;
    Icon ic(IconData d) => Icon(d, size: 22, color: iconColor);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _DropZone(onTap: () => Navigator.pop(context, 'phone')),
              const SizedBox(height: 12),
              option('upload_from_device', ic(Icons.folder_outlined), 'From device', 'device'),
              option('upload_from_link', ic(Icons.link), 'From link', 'link'),
              option('upload_from_camera', ic(Icons.photo_camera_outlined), 'Camera', 'camera'),
              option('upload_from_drive', const _DriveIcon(color: iconColor), 'Google Drive', 'drive'),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: TextButton(
                  key: const Key('upload_cancel'),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F1F1),
                    foregroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('Cancel'), style: AppText.montserrat(size: 15, weight: FontWeight.w500)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Second step of "From device": files on this phone, or folders on the computer.
class _DeviceSheet extends StatelessWidget {
  const _DeviceSheet();

  @override
  Widget build(BuildContext context) {
    Widget row(String key, IconData icon, String title, String subtitle, String value) => InkWell(
          key: Key(key),
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pop(context, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.bgTop, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppColors.orangeDeep, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr(title), style: AppText.montserrat(size: 15, weight: FontWeight.w600, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(context.tr(subtitle), style: AppText.montserrat(size: 12, color: AppColors.darkGrey)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: AppColors.slate),
            ]),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Text(context.tr('From device'),
                    style: AppText.montserrat(size: 17, weight: FontWeight.w700, color: AppColors.navy)),
              ),
              row('device_phone', Icons.smartphone_outlined, 'This phone', 'Photos, Downloads, SD card', 'phone'),
              row('device_computer', Icons.computer_outlined, 'This computer', 'Desktop, Pictures, Downloads, Documents', 'computer'),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: TextButton(
                  key: const Key('device_cancel'),
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F1F1),
                    foregroundColor: AppColors.ink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.tr('Cancel'), style: AppText.montserrat(size: 15, weight: FontWeight.w500)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The big tap area at the top. Phones can't receive files dragged from other apps here, so it opens the file picker.
class _DropZone extends StatelessWidget {
  const _DropZone({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgTop,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const Key('upload_dropzone'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: CustomPaint(
          painter: const _DashedBorderPainter(color: AppColors.mint, radius: 14),
          child: SizedBox(
            height: 190,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const SizedBox(width: 74, height: 74, child: CustomPaint(painter: _PhotoGlyphPainter())),
              const SizedBox(height: 18),
              Text(context.tr('Tap to choose a photo'),
                  style: AppText.montserrat(size: 15, weight: FontWeight.w600, color: AppColors.navy)),
              const SizedBox(height: 4),
              Text(context.tr('JPG, PNG or WEBP · up to 10 MB'),
                  style: AppText.montserrat(size: 12, color: AppColors.darkGrey)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)).deflate(0.7));
    for (final metric in path.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 5, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

/// A simple "picture" glyph: rounded tile, sun and two hills.
class _PhotoGlyphPainter extends CustomPainter {
  const _PhotoGlyphPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final tile = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.16));
    canvas.save();
    canvas.clipRRect(tile);
    canvas.drawRRect(tile, Paint()..color = const Color(0xFFE2A27A));
    canvas.drawCircle(Offset(s.width * 0.70, s.height * 0.28), s.width * 0.11, Paint()..color = Colors.white);
    final back = Path()
      ..moveTo(s.width * 0.30, s.height)
      ..lineTo(s.width * 0.66, s.height * 0.50)
      ..lineTo(s.width * 1.05, s.height)
      ..close();
    canvas.drawPath(back, Paint()..color = const Color(0xFFF7F1EC));
    final front = Path()
      ..moveTo(-s.width * 0.05, s.height)
      ..lineTo(s.width * 0.32, s.height * 0.46)
      ..lineTo(s.width * 0.75, s.height)
      ..close();
    canvas.drawPath(front, Paint()..color = const Color(0xFFDCD3CC));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PhotoGlyphPainter old) => false;
}

/// Outline triangle used for the "Google Drive" row (a plain shape, not the Drive logo).
class _DriveIcon extends StatelessWidget {
  const _DriveIcon({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(width: 22, height: 20, child: CustomPaint(painter: _TrianglePainter(color)));
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    final top = Offset(s.width * 0.5, 1), left = Offset(1, s.height - 1), right = Offset(s.width - 1, s.height - 1);
    canvas.drawPath(Path()..addPolygon([top, left, right], true), p);
    // inner lines, like the three folded panels of a drive shape
    canvas.drawLine(Offset(s.width * 0.34, s.height * 0.30), Offset(s.width * 0.66, s.height - 1), p);
    canvas.drawLine(Offset(s.width * 0.20, s.height * 0.68), Offset(s.width * 0.80, s.height * 0.68), p);
  }

  @override
  bool shouldRepaint(_TrianglePainter old) => old.color != color;
}

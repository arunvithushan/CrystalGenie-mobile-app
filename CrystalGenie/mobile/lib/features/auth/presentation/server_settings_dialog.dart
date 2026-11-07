import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';

/// Lets developers point the app at the backend (emulator 10.0.2.2 or the PC's LAN IP on a phone).
Future<void> showServerSettingsDialog(BuildContext context, WidgetRef ref) {
  return showDialog<void>(context: context, builder: (_) => const _ServerSettingsDialog());
}

class _ServerSettingsDialog extends ConsumerStatefulWidget {
  const _ServerSettingsDialog();

  @override
  ConsumerState<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends ConsumerState<_ServerSettingsDialog> {
  late final TextEditingController _ctrl = TextEditingController(text: ref.read(baseUrlProvider));
  String? _status;
  bool _ok = false;
  bool _testing = false;

  Future<void> _test() async {
    if (!AppConfig.isValidBaseUrl(_ctrl.text)) {
      setState(() {
        _status = 'Enter a valid address, e.g. http://192.168.1.20:8000';
        _ok = false;
      });
      return;
    }
    setState(() => _testing = true);
    final url = AppConfig.normalizeBaseUrl(_ctrl.text);
    try {
      final res = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)))
          .get('$url/api/health');
      final model = res.data is Map && res.data['model_loaded'] == true ? 'model loaded' : 'model NOT loaded';
      setState(() {
        _ok = true;
        _status = 'Connected ✓ ($model)';
      });
    } catch (_) {
      setState(() {
        _ok = false;
        _status = 'Could not reach $url/api/health';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Emulator: http://10.0.2.2:8000\nPhone: http://<your PC LAN IP>:8000',
              style: AppText.montserrat(size: 12.5, color: AppColors.darkGrey)),
          const SizedBox(height: 12),
          TextField(
            key: const Key('server_url_field'),
            controller: _ctrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Backend address'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 10),
            Text(_status!, style: AppText.montserrat(size: 12.5, color: _ok ? AppColors.success : AppColors.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref.read(baseUrlProvider.notifier).reset();
            _ctrl.text = ref.read(baseUrlProvider);
          },
          child: const Text('Default'),
        ),
        TextButton(onPressed: _testing ? null : _test, child: Text(_testing ? 'Testing…' : 'Test')),
        FilledButton(
          onPressed: () async {
            if (!AppConfig.isValidBaseUrl(_ctrl.text)) return _test();
            await ref.read(baseUrlProvider.notifier).set(_ctrl.text);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

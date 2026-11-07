import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/network/api_exception.dart';
import '../auth/application/auth_controller.dart';
import '../auth/presentation/server_settings_dialog.dart';

/// Splash: Crystal Genie artwork while the stored session is checked.
/// Navigation happens automatically through the router redirect once auth state is known.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.minimumDuration = const Duration(milliseconds: 1200)});
  final Duration minimumDuration;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Future.wait([
        ref.read(authControllerProvider.notifier).bootstrap(),
        Future<void>.delayed(widget.minimumDuration),
      ]);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/splash_bg.jpg', fit: BoxFit.cover),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                Semantics(
                  label: 'Crystal Genie',
                  image: true,
                  child: Image.asset('assets/images/logo.png', width: 170),
                ),
                const Spacer(flex: 2),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(_error!, textAlign: TextAlign.center, style: AppText.montserrat(size: 14, color: Colors.white)),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.navy),
                                onPressed: _start,
                                child: const Text('Retry'),
                              ),
                              const SizedBox(width: 10),
                              TextButton(
                                style: TextButton.styleFrom(foregroundColor: Colors.white),
                                onPressed: () => showServerSettingsDialog(context, ref),
                                child: const Text('Server settings'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 48),
                    child: SizedBox(
                        width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

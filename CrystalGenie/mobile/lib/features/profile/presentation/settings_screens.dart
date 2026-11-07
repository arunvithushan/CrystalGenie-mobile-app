import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/headers.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../auth/presentation/validators.dart';
import '../data/user_repository.dart';

final userSettingsProvider = FutureProvider.autoDispose<UserSettings>((ref) => ref.watch(userRepositoryProvider).getSettings());

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: AppBackground(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Align(alignment: Alignment.centerLeft, child: BackTextButton(onPressed: () => context.pop())),
                const SizedBox(height: 4),
                Text(title,
                    textAlign: TextAlign.center,
                    style: AppText.montserrat(size: 30, weight: FontWeight.w500, color: AppColors.teal)),
                const SizedBox(height: 22),
                child,
              ],
            ),
          ),
        ),
      );
}

/// Keeps a local copy of settings and PATCHes each change to the backend.
mixin _SettingsEditor<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  UserSettings? local;

  Future<void> patch(Map<String, dynamic> changes, UserSettings optimistic) async {
    final before = local;
    setState(() => local = optimistic);
    try {
      final saved = await ref.read(userRepositoryProvider).updateSettings(changes);
      if (mounted) setState(() => local = saved);
    } catch (e) {
      if (mounted) {
        setState(() => local = before);
        showSnack(context, errorMessage(e), error: true);
      }
    }
  }
}

// --------------------------------------------------------------------------- Notifications
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> with _SettingsEditor<NotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userSettingsProvider);
    return _SettingsScaffold(
      title: 'Notifications',
      child: async.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(message: errorMessage(e), onRetry: () => ref.invalidate(userSettingsProvider)),
        data: (server) {
          final s = local ?? server;
          return GlassCard(
            borderColor: AppColors.mint,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(children: [
              SwitchListTile(
                key: const Key('notif_all'),
                title: Text('Allow notifications', style: AppText.montserrat(size: 16, weight: FontWeight.w600)),
                subtitle: const Text('Master switch for all Crystal Genie notifications'),
                value: s.notificationsEnabled,
                onChanged: (v) => patch({'notifications_enabled': v}, s.copyWith(notificationsEnabled: v)),
              ),
              SwitchListTile(
                title: Text('Scanning tips', style: AppText.montserrat(size: 16, weight: FontWeight.w600)),
                subtitle: const Text('Helpful tips for taking clearer crystal photos'),
                value: s.scanTipsEnabled,
                onChanged: s.notificationsEnabled ? (v) => patch({'scan_tips_enabled': v}, s.copyWith(scanTipsEnabled: v)) : null,
              ),
              SwitchListTile(
                title: Text('New crystals in the library', style: AppText.montserrat(size: 16, weight: FontWeight.w600)),
                subtitle: const Text('Hear when new gemstones become identifiable'),
                value: s.newCrystalAlerts,
                onChanged: s.notificationsEnabled ? (v) => patch({'new_crystal_alerts': v}, s.copyWith(newCrystalAlerts: v)) : null,
              ),
            ]),
          );
        },
      ),
    );
  }
}

// --------------------------------------------------------------------------- Language
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});
  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> with _SettingsEditor<LanguageScreen> {
  @override
  Widget build(BuildContext context) {
    final current = ref.watch(languageProvider);
    final async = ref.watch(userSettingsProvider);
    return _SettingsScaffold(
      title: context.tr('Language'),
      child: Column(children: [
        GlassCard(
          borderColor: AppColors.mint,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: RadioGroupCompat(
            value: current,
            options: supportedLanguages,
            onChanged: (code) async {
              // Switch the UI at once (stored on this device), then save it to the account.
              await ref.read(languageProvider.notifier).set(code);
              final s = local ?? async.valueOrNull;
              if (s != null) await patch({'language': code}, s.copyWith(language: code));
            },
          ),
        ),
        const SizedBox(height: 14),
        Text(
          context.tr('The app switches language immediately. Gemstone names and library facts are shown in English.'),
          style: AppText.montserrat(size: 12.5, color: AppColors.darkGrey),
        ),
      ]),
    );
  }
}

/// Simple radio list (avoids API differences between Flutter versions' Radio widgets).
class RadioGroupCompat extends StatelessWidget {
  const RadioGroupCompat({super.key, required this.value, required this.options, required this.onChanged});
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final e in options.entries)
            ListTile(
              key: Key('lang_${e.key}'),
              title: Text(e.value, style: AppText.montserrat(size: 16, weight: FontWeight.w500)),
              trailing: Icon(value == e.key ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: value == e.key ? AppColors.teal : AppColors.slate),
              onTap: () => onChanged(e.key),
            ),
        ],
      );
}

// --------------------------------------------------------------------------- Security
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});
  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_current, _new, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _change() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).changePassword(_current.text, _new.text);
      if (!mounted) return;
      _current.clear();
      _new.clear();
      _confirm.clear();
      showSnack(context, 'Password changed. Other devices have been signed out.');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOutEverywhere() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out of all devices?'),
        content: const Text('You will be signed out here and on every other device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out everywhere')),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).logout(allDevices: true);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsScaffold(
      title: 'Security',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassCard(
            borderColor: AppColors.mint,
            padding: const EdgeInsets.all(18),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Change password', style: AppText.montserrat(size: 17, weight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  if (_error != null) ErrorBanner(_error!),
                  PasswordField(controller: _current, validator: Validators.loginPassword, hint: 'Current password'),
                  const SizedBox(height: 12),
                  PasswordField(controller: _new, validator: Validators.newPassword, hint: 'New password'),
                  const SizedBox(height: 12),
                  PasswordField(controller: _confirm, validator: Validators.confirm(() => _new.text), hint: 'Confirm new password'),
                  const SizedBox(height: 18),
                  GradientButton(label: 'Update password', onPressed: _change, loading: _busy),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          TintButton(
            label: 'Sign out of all devices',
            icon: Icons.devices_other,
            onPressed: _signOutEverywhere,
            expand: true,
            height: 46,
          ),
          const SizedBox(height: 14),
          Text(
            'Your password is stored only as an Argon2 hash. Sessions use short-lived access tokens and rotating refresh '
            'tokens kept in your device’s secure keystore.',
            style: AppText.montserrat(size: 12.5, color: AppColors.darkGrey),
          ),
        ],
      ),
    );
  }
}

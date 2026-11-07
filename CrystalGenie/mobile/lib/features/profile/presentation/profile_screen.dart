import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/models.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/glass.dart';
import '../../../shared/widgets/headers.dart';
import '../../../shared/widgets/images.dart';
import '../../../shared/widgets/state_views.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/presentation/auth_widgets.dart';
import '../../auth/presentation/validators.dart';
import '../../camera/data/media_services.dart';
import '../data/user_repository.dart';
import '../../../core/l10n/l10n.dart';

/// Figma "Profile" and "Profile - edit".
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final path = await ref.read(imageServiceProvider).pickFromGallery();
    if (path == null) return;
    final invalid = await validateImageFile(path);
    if (invalid != null) {
      if (context.mounted) showSnack(context, invalid, error: true);
      return;
    }
    try {
      final user = await ref.read(userRepositoryProvider).uploadAvatar(path);
      await ref.read(authControllerProvider.notifier).updateUser(user);
      if (context.mounted) showSnack(context, context.tr('Profile photo updated'));
    } catch (e) {
      if (context.mounted) showSnack(context, errorMessage(e), error: true);
    }
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(context.tr('Log out?')),
        content: Text(context.tr('You can sign in again at any time — your saved crystals stay in your account.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(context.tr('Cancel'))),
          FilledButton(key: const Key('confirm_logout'), onPressed: () => Navigator.pop(c, true), child: Text(context.tr('Log out'))),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: BackTextButton(onPressed: () => context.canPop() ? context.pop() : context.go(Routes.home)),
              ),
              const SizedBox(height: 6),
              // "Profile" title partially behind the profile card (Figma).
              SizedBox(
                height: 182,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Text(context.tr('Profile'),
                          textAlign: TextAlign.center,
                          style: AppText.montserrat(size: 34, weight: FontWeight.w500, color: AppColors.teal)),
                    ),
                    Positioned.fill(
                      top: 26,
                      child: GlassCard(
                        radius: 18,
                        opacity: 0.45,
                        blur: 6,
                        borderColor: AppColors.mint,
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Semantics(
                              button: true,
                              label: context.tr('Change profile photo'),
                              child: GestureDetector(
                                key: const Key('profile_avatar'),
                                onTap: () => _changePhoto(context, ref),
                                child: Stack(
                                  children: [
                                    UserAvatar(user: user, size: 112),
                                    Positioned(
                                      right: 2,
                                      bottom: 2,
                                      child: Container(
                                        padding: const EdgeInsets.all(5),
                                        decoration: const BoxDecoration(color: AppColors.teal, shape: BoxShape.circle),
                                        child: const Icon(Icons.photo_camera_outlined, size: 16, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user?.fullName ?? '',
                                      key: const Key('profile_name'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.playfair(size: 24, weight: FontWeight.w700)),
                                  Text(user?.email ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.montserrat(size: 14, color: AppColors.slate)),
                                  const SizedBox(height: 12),
                                  TintButton(
                                    key: const Key('edit_profile_button'),
                                    label: context.tr('Edit profile'),
                                    icon: Icons.edit_outlined,
                                    onPressed: user == null ? null : () => showEditProfileSheet(context, user),
                                    height: 38,
                                    fontSize: 15,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GradientButton(
                key: const Key('logout_button'),
                label: context.tr('Logout'),
                icon: Icons.logout,
                height: 50,
                fontSize: 17,
                onPressed: () => _logout(context, ref),
              ),
              const SizedBox(height: 26),
              GlassCard(
                radius: 18,
                borderColor: AppColors.mint,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  children: [
                    _MenuRow(
                        key: const Key('menu_saved'),
                        icon: Icons.bookmark_border,
                        label: context.tr('Saved Crystals'),
                        onTap: () => context.go(Routes.saved)),
                    const _Divider(),
                    _MenuRow(icon: Icons.notifications_none, label: context.tr('Notifications'), onTap: () => context.push(Routes.notifications)),
                    const _Divider(),
                    _MenuRow(icon: Icons.verified_user_outlined, label: context.tr('Security'), onTap: () => context.push(Routes.security)),
                    const _Divider(),
                    _MenuRow(icon: Icons.translate, label: context.tr('Language'), onTap: () => context.push(Routes.language)),
                  ],
                ),
              ),
              const SizedBox(height: 60),
              DangerButton(
                key: const Key('delete_account_button'),
                label: context.tr('Delete account'),
                onPressed: () => showDialog<void>(context: context, builder: (_) => const DeleteAccountDialog()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({super.key, required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              Icon(icon, size: 26, color: AppColors.ink),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: AppText.montserrat(size: 17, weight: FontWeight.w600))),
              const Icon(Icons.chevron_right, color: AppColors.ink),
            ],
          ),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Divider(height: 1, color: AppColors.mint.withValues(alpha: 0.8));
}

// --------------------------------------------------------------------------- Edit profile sheet
Future<void> showEditProfileSheet(BuildContext context, AppUser user) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => EditProfileSheet(user: user),
    );

class EditProfileSheet extends ConsumerStatefulWidget {
  const EditProfileSheet({super.key, required this.user});
  final AppUser user;

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.fullName);
  late final _email = TextEditingController(text: widget.user.email);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final name = _name.text.trim() == widget.user.fullName ? null : _name.text;
      final email = _email.text.trim().toLowerCase() == widget.user.email ? null : _email.text;
      if (name != null || email != null) {
        final user = await ref.read(userRepositoryProvider).updateProfile(fullName: name, email: email);
        await ref.read(authControllerProvider.notifier).updateUser(user);
      }
      if (mounted) {
        showSnack(context, context.tr('Profile updated'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 40),
                    Expanded(
                      child: Text(context.tr('Edit your profile details'),
                          textAlign: TextAlign.center, style: AppText.montserrat(size: 18, weight: FontWeight.w500)),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close), tooltip: context.tr('Close')),
                  ],
                ),
                const SizedBox(height: 18),
                if (_error != null) ErrorBanner(_error!),
                FieldLabel(context.tr('Name')),
                TextFormField(key: const Key('edit_name'), controller: _name, validator: Validators.name),
                const SizedBox(height: 16),
                FieldLabel(context.tr('Email')),
                TextFormField(
                    key: const Key('edit_email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    validator: Validators.email),
                const SizedBox(height: 26),
                GradientButton(key: const Key('edit_save'), label: 'Save', onPressed: _save, loading: _saving, height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------------- Delete account
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  ConsumerState<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _ready => _confirm.text.trim().toUpperCase() == 'DELETE' && _password.text.isNotEmpty;

  Future<void> _delete() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(userRepositoryProvider).deleteAccount(_password.text);
      if (!mounted) return;
      Navigator.pop(context);
      await ref.read(authControllerProvider.notifier).clearLocalSession(message: 'Your account has been deleted.');
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('Delete account?')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('This permanently deletes your profile, scan history, saved crystals, favorites and photos. '
                'This cannot be undone.')),
            const SizedBox(height: 14),
            if (_error != null) ErrorBanner(_error!),
            PasswordField(fieldKey: const Key('delete_password'), controller: _password, hint: 'Your password'),
            const SizedBox(height: 10),
            TextField(
              key: const Key('delete_confirm'),
              controller: _confirm,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: context.tr('Type DELETE to confirm')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(context.tr('Cancel'))),
        FilledButton(
          key: const Key('delete_submit'),
          style: FilledButton.styleFrom(backgroundColor: AppColors.error),
          onPressed: _ready && !_busy ? _delete : null,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(context.tr('Delete forever')),
        ),
      ],
    );
  }
}

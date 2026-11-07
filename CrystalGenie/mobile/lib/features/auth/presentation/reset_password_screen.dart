import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/buttons.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/auth_repository.dart';
import 'auth_widgets.dart';
import 'validators.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email, this.devCode});
  final String email;

  /// Only present when the backend runs in development mode (no e-mail server configured).
  final String? devCode;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  late final _code = TextEditingController(text: widget.devCode ?? '');
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).resetPassword(_email.text, _code.text, _password.text);
      if (!mounted) return;
      showSnack(context, 'Password updated. Please sign in.');
      context.go(Routes.login);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset password',
      subtitle: 'Enter the code we sent to your e-mail and choose a new password',
      onBack: () => context.go(Routes.forgot),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ErrorBanner(_error!),
            if (widget.devCode != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Development server: the reset code was filled in automatically.',
                    style: AppText.montserrat(size: 12, color: AppColors.info)),
              ),
            const FieldLabel('Email'),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, validator: Validators.email),
            const SizedBox(height: 14),
            const FieldLabel('Reset code'),
            TextFormField(
              key: const Key('reset_code'),
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              validator: Validators.resetCode,
              decoration: const InputDecoration(hintText: 'e.g. 7KQ2M9XA'),
            ),
            const SizedBox(height: 14),
            const FieldLabel('New password'),
            PasswordField(controller: _password, validator: Validators.newPassword, hint: 'New password'),
            const SizedBox(height: 14),
            const FieldLabel('Confirm new password'),
            PasswordField(controller: _confirm, validator: Validators.confirm(() => _password.text), hint: 'Repeat password'),
            const SizedBox(height: 20),
            GradientButton(label: 'Update password', onPressed: _submit, loading: _loading, height: 48),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/buttons.dart';
import '../application/auth_controller.dart';
import 'auth_widgets.dart';
import 'server_settings_dialog.dart';
import 'validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final msg = ref.read(authControllerProvider).message;
    if (msg != null) {
      _error = msg;
      WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(authControllerProvider.notifier).clearMessage());
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).login(_email.text, _password.text);
      // Router redirect takes the user to Home.
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to identify and collect crystals',
      footer: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('New to Crystal Genie?', style: AppText.montserrat(size: 14, color: AppColors.ink)),
              TextButton(
                key: const Key('go_register'),
                onPressed: () => context.go(Routes.register),
                child: Text('Create account', style: AppText.montserrat(size: 14, weight: FontWeight.w600, color: AppColors.linkTeal).copyWith(decoration: TextDecoration.underline, decorationColor: AppColors.linkTeal)),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: () => showServerSettingsDialog(context, ref),
            icon: const Icon(Icons.dns_outlined, size: 16, color: AppColors.slate),
            label: Text('Server settings', style: AppText.montserrat(size: 12.5, color: AppColors.slate)),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ErrorBanner(_error!),
              const FieldLabel('Email'),
              TextFormField(
                key: const Key('login_email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                validator: Validators.email,
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
              const SizedBox(height: 16),
              const FieldLabel('Password'),
              PasswordField(
                fieldKey: const Key('login_password'),
                controller: _password,
                validator: Validators.loginPassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.go(Routes.forgot),
                  child: Text('Forgot password?', style: AppText.montserrat(size: 13, weight: FontWeight.w600, color: AppColors.linkTeal).copyWith(decoration: TextDecoration.underline, decorationColor: AppColors.linkTeal)),
                ),
              ),
              const SizedBox(height: 4),
              GradientButton(key: const Key('login_submit'), label: 'Sign in', onPressed: _submit, loading: _loading, height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

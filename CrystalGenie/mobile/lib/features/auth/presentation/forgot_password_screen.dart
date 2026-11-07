import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/buttons.dart';
import '../data/auth_repository.dart';
import 'auth_widgets.dart';
import 'validators.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devCode = await ref.read(authRepositoryProvider).forgotPassword(_email.text);
      if (!mounted) return;
      context.go('${Routes.reset}?email=${Uri.encodeQueryComponent(_email.text.trim())}', extra: devCode);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Forgot password',
      subtitle: "Enter your e-mail and we'll send you a reset code",
      onBack: () => context.go(Routes.login),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ErrorBanner(_error!),
            const FieldLabel('Email'),
            TextFormField(
              key: const Key('forgot_email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              validator: Validators.email,
              onFieldSubmitted: (_) => _submit(),
              decoration: const InputDecoration(hintText: 'you@example.com'),
            ),
            const SizedBox(height: 20),
            GradientButton(label: 'Send reset code', onPressed: _submit, loading: _loading, height: 48),
          ],
        ),
      ),
    );
  }
}

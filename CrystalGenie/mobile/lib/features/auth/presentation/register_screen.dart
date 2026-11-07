import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/buttons.dart';
import '../application/auth_controller.dart';
import 'auth_widgets.dart';
import 'validators.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _fieldErrors = {});
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).register(_name.text, _email.text, _password.text);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _fieldErrors = e.fieldErrors;
        });
        _form.currentState!.validate();
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? Function(String?) _withServer(String field, String? Function(String?) local) =>
      (v) => local(v) ?? _fieldErrors[field];

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create account',
      subtitle: 'Save your finds and build your crystal collection',
      onBack: () => context.go(Routes.login),
      footer: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Already have an account?', style: AppText.montserrat(size: 14, color: AppColors.ink)),
          TextButton(
            onPressed: () => context.go(Routes.login),
            child: Text('Sign in', style: AppText.montserrat(size: 14, weight: FontWeight.w600, color: AppColors.linkTeal).copyWith(decoration: TextDecoration.underline, decorationColor: AppColors.linkTeal)),
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
              const FieldLabel('Name'),
              TextFormField(
                key: const Key('register_name'),
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                validator: _withServer('full_name', Validators.name),
                decoration: const InputDecoration(hintText: 'Jon Doe'),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Email'),
              TextFormField(
                key: const Key('register_email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                validator: _withServer('email', Validators.email),
                decoration: const InputDecoration(hintText: 'you@example.com'),
              ),
              const SizedBox(height: 14),
              const FieldLabel('Password'),
              PasswordField(
                fieldKey: const Key('register_password'),
                controller: _password,
                validator: _withServer('password', Validators.newPassword),
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                hint: 'At least 8 characters, letters & numbers',
              ),
              const SizedBox(height: 14),
              const FieldLabel('Confirm password'),
              PasswordField(
                fieldKey: const Key('register_confirm'),
                controller: _confirm,
                validator: Validators.confirm(() => _password.text),
                textInputAction: TextInputAction.done,
                hint: 'Repeat password',
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              GradientButton(
                  key: const Key('register_submit'), label: 'Create account', onPressed: _submit, loading: _loading, height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

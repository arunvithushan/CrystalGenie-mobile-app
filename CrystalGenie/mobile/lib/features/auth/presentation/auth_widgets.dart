import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/glass.dart';

/// Shared layout for login / register / password screens, in the Figma glass style.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.child, this.footer, this.onBack});

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 40,
                      child: onBack == null
                          ? null
                          : Align(
                              alignment: Alignment.centerLeft,
                              child: IconButton(
                                  onPressed: onBack, icon: const Icon(Icons.chevron_left, size: 28), tooltip: 'Back'),
                            ),
                    ),
                    Center(
                      child: Container(
                        width: 92,
                        height: 92,
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                              colors: [AppColors.teal, AppColors.sky], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          boxShadow: [BoxShadow(color: Color(0x33D2401A), blurRadius: 18, offset: Offset(0, 6))],
                        ),
                        child: Image.asset('assets/images/logo_mark.png', fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: AppText.montserrat(size: 30, weight: FontWeight.w500, color: AppColors.teal)),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        textAlign: TextAlign.center, style: AppText.montserrat(size: 14, color: AppColors.darkGrey)),
                    const SizedBox(height: 22),
                    GlassCard(
                      radius: 20,
                      opacity: 0.6,
                      borderColor: AppColors.mint,
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                      child: child,
                    ),
                    if (footer != null) ...[const SizedBox(height: 16), footer!],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(text, style: AppText.montserrat(size: 15, weight: FontWeight.w500, color: AppColors.navy)),
      );
}

class PasswordField extends StatefulWidget {
  const PasswordField({super.key, required this.controller, this.validator, this.hint = 'Password', this.textInputAction,
      this.onSubmitted, this.fieldKey, this.autofillHints});
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final String hint;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Key? fieldKey;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) => TextFormField(
        key: widget.fieldKey,
        controller: widget.controller,
        obscureText: _obscure,
        validator: widget.validator,
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onSubmitted,
        autofillHints: widget.autofillHints,
        enableSuggestions: false,
        autocorrect: false,
        decoration: InputDecoration(
          hintText: widget.hint,
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.slate),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      );
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: AppText.montserrat(size: 13, color: AppColors.error))),
          ],
        ),
      );
}

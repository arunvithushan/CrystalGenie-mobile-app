/// Form validators (mirror the backend rules so users get instant feedback).
abstract final class Validators {
  static final _email = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$");

  static String? email(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Please enter your e-mail';
    if (!_email.hasMatch(s)) return 'Please enter a valid e-mail address';
    return null;
  }

  static String? loginPassword(String? v) => (v ?? '').isEmpty ? 'Please enter your password' : null;

  static String? newPassword(String? v) {
    final s = v ?? '';
    if (s.isEmpty) return 'Please choose a password';
    if (s.length < 8) return 'Use at least 8 characters';
    if (s.length > 128) return 'Use at most 128 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(s) || !RegExp(r'\d').hasMatch(s)) return 'Use letters and numbers';
    return null;
  }

  static String? Function(String?) confirm(String Function() original) =>
      (v) => (v ?? '') != original() ? 'Passwords do not match' : null;

  static String? name(String? v) {
    final s = (v ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return 'Please enter your name';
    if (s.length < 2) return 'Name is too short';
    if (s.length > 120) return 'Name is too long';
    return null;
  }

  static String? resetCode(String? v) {
    final s = (v ?? '').trim().replaceAll('-', '').replaceAll(' ', '');
    if (s.isEmpty) return 'Enter the code from the e-mail';
    if (s.length < 6 || s.length > 12) return 'The code looks incomplete';
    return null;
  }
}

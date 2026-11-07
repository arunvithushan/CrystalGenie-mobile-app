import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('signed-out user lands on Login after splash', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
  });

  testWidgets('login validation shows field errors and does not call the API', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f);
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();
    expect(find.text('Please enter your e-mail'), findsOneWidget);
    expect(find.text('Please enter your password'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('login_email')), 'not-an-email');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pump();
    expect(find.text('Please enter a valid e-mail address'), findsOneWidget);
    expect(f.auth.loginCalls, 0);
  });

  testWidgets('wrong credentials show the server error', (tester) async {
    final f = Fakes()..auth.failLogin = true;
    await pumpApp(tester, f);
    await tester.enterText(find.byKey(const Key('login_email')), 'jon@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'whatever1');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect e-mail or password.'), findsOneWidget);
  });

  testWidgets('successful login navigates to Home and persists tokens', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f);
    await tester.enterText(find.byKey(const Key('login_email')), 'jon@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'Crystal123');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Hi welcome,'), findsOneWidget);
    expect(find.byKey(const Key('home_user_name')), findsOneWidget);
    expect(find.text('Jon'), findsOneWidget);
    expect(f.storage.tokens?.refreshToken, isNotNull);
  });

  testWidgets('register validation: password rules and mismatch', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f);
    await tester.tap(find.byKey(const Key('go_register')));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);

    await tester.enterText(find.byKey(const Key('register_name')), 'A');
    await tester.enterText(find.byKey(const Key('register_email')), 'ann@example.com');
    await tester.enterText(find.byKey(const Key('register_password')), 'short');
    await tester.enterText(find.byKey(const Key('register_confirm')), 'different');
    await tester.ensureVisible(find.byKey(const Key('register_submit')));
    await tester.tap(find.byKey(const Key('register_submit')));
    await tester.pump();
    expect(find.text('Name is too short'), findsOneWidget);
    expect(find.text('Use at least 8 characters'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('register_name')), 'Ann Lee');
    await tester.enterText(find.byKey(const Key('register_password')), 'Crystal123');
    await tester.enterText(find.byKey(const Key('register_confirm')), 'Crystal123');
    await tester.ensureVisible(find.byKey(const Key('register_submit')));
    await tester.tap(find.byKey(const Key('register_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Hi welcome,'), findsOneWidget);
    expect(find.text('Ann'), findsOneWidget);
  });

  testWidgets('stored session skips login; protected routes need auth', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    expect(find.text('Hi welcome,'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });

  testWidgets('bottom navigation: Explore and Scan', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('nav_explore')));
    await tester.pumpAndSettle();
    expect(find.text('Crystal library'), findsOneWidget);
    expect(find.text('Garnet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav_scan')));
    await tester.pumpAndSettle();
    expect(find.text('Keep your crystal within the frame'), findsOneWidget);
  });

  testWidgets('logout returns to Login and clears tokens', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('home_profile_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_logout')));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(f.storage.tokens, isNull);
    expect(f.auth.loggedOut, isTrue);
  });
}

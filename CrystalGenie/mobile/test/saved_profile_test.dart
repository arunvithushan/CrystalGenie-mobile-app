import 'package:crystal_genie/shared/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<void> _openSaved(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home_profile_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('menu_saved')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Saved: My finds and Favorites tabs, list/grid, remove', (tester) async {
    final f = Fakes()
      ..collections.savedItems = [SavedCrystal(id: 's1', prediction: prediction(id: 'p1', saved: true))]
      ..collections.favoriteItems = [FavoriteItem(id: 'f1', gemstone: gem(id: 'g2', name: 'Garnet', fav: true))];
    await pumpApp(tester, f, signedIn: true);
    await _openSaved(tester);

    expect(find.text('Saved Crystals'), findsOneWidget);
    expect(find.text('My finds'), findsOneWidget);
    expect(find.text('Rose Quartz'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saved_layout_toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(GridView), findsOneWidget);
    await tester.tap(find.byKey(const Key('saved_layout_toggle')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('saved_tab_1')));
    await tester.pumpAndSettle();
    expect(find.text('Garnet'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark).first);
    await tester.pumpAndSettle();
    expect(f.collections.calls, contains('unfav:g2'));
    expect(find.text('Garnet'), findsNothing);
    expect(find.textContaining('No favorites yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saved_tab_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmark).first);
    await tester.pumpAndSettle();
    expect(f.collections.calls, contains('unsave:s1'));
    expect(find.textContaining('No saved finds yet'), findsOneWidget);
  });

  testWidgets('Profile shows user and edits the name', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('home_profile_button')));
    await tester.pumpAndSettle();
    expect(find.text('Jon Doe'), findsOneWidget);
    expect(find.text('jon@example.com'), findsOneWidget);
    expect(find.text('Saved Crystals'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);

    await tester.tap(find.byKey(const Key('edit_profile_button')));
    await tester.pumpAndSettle();
    expect(find.text('Edit your profile details'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('edit_name')), 'Jonathan Doe');
    await tester.tap(find.byKey(const Key('edit_save')));
    await tester.pumpAndSettle();
    expect(f.users.lastName, 'Jonathan Doe');
    expect(find.text('Jonathan Doe'), findsOneWidget);
  });

  testWidgets('Delete account requires password and typing DELETE', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('home_profile_button')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('delete_account_button')));
    await tester.tap(find.byKey(const Key('delete_account_button')));
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('delete_submit'));
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('delete_password')), 'Crystal123');
    await tester.enterText(find.byKey(const Key('delete_confirm')), 'DELETE');
    await tester.pump();
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(f.users.deleted, isTrue);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Your account has been deleted.'), findsOneWidget);
  });

  testWidgets('Notification and language settings sync to backend', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('home_profile_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notif_all')));
    await tester.pumpAndSettle();
    expect(f.users.settings.notificationsEnabled, isFalse);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lang_ta')));
    await tester.pumpAndSettle();
    expect(f.users.settings.language, 'ta');
    // The UI switches immediately: the screen title is now Tamil.
    expect(find.text('மொழி'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lang_si')));
    await tester.pumpAndSettle();
    expect(find.text('භාෂාව'), findsOneWidget);
    expect(f.users.settings.language, 'si');
  });
}

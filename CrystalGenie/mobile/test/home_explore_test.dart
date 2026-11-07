import 'package:crystal_genie/core/network/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('Home shows the empty state when there are no scans', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    expect(find.byKey(const Key('home_empty')), findsOneWidget);
    expect(find.text('No crystals uncovered yet!'), findsOneWidget);
    expect(find.text('Try scanning your first crystal'), findsOneWidget);
  });

  testWidgets('Home lists real prediction history (Recent Finds)', (tester) async {
    final f = Fakes()
      ..predictions.history_ = [
        prediction(id: 'p1'),
        prediction(id: 'p2', cls: 'Garnet', display: 'Garnet', g: gem(id: 'g2', name: 'Garnet')),
        prediction(id: 'p3', conf: 0.31, uncertain: true),
      ];
    await pumpApp(tester, f, signedIn: true);
    expect(find.text('Recent Finds'), findsOneWidget);
    expect(find.text('Rose Quartz'), findsOneWidget);
    expect(find.text('Garnet'), findsOneWidget);
    expect(find.text('2 days ago'), findsWidgets);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('find_p3')), 200,
        scrollable: find.descendant(of: find.byKey(const Key('home_list')), matching: find.byType(Scrollable)).first);
    expect(find.text('Uncertain'), findsWidgets);
  });

  testWidgets('Home shows the real model accuracy from the backend', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    expect(find.byKey(const Key('home_model_accuracy')), findsOneWidget);
    expect(find.text('86.9%'), findsOneWidget);
    expect(find.text('Tested on 145 photos the model never saw'), findsOneWidget);
    expect(find.byKey(const Key('banner_diamond')), findsWidgets); // diamond replaces the old logo watermark
  });

  testWidgets('Home banner can be swiped and moved with the dots', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    expect(find.byKey(const Key('diamond_glow')), findsNothing); // no background behind the diamond
    await tester.drag(find.byKey(const Key('home_banner')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('IDENTIFY ANY CRYSTAL IN SECONDS'), findsOneWidget);
    await tester.tap(find.byKey(const Key('banner_dot_2')));
    await tester.pumpAndSettle();
    expect(find.text('EXPLORE THE CRYSTAL LIBRARY'), findsOneWidget);
  });

  testWidgets('Home explains when model info is unavailable', (tester) async {
    final f = Fakes()..modelInfo.error = const ApiException(code: 'network_error', message: 'offline');
    await pumpApp(tester, f, signedIn: true);
    expect(find.text('Model info unavailable — start the backend to see the accuracy.'), findsOneWidget);
  });

  testWidgets('Home shows an error with retry', (tester) async {
    final f = Fakes()..predictions.historyError = const ApiException(code: 'network_error', message: "Can't reach the server");
    await pumpApp(tester, f, signedIn: true);
    expect(find.text("Can't reach the server"), findsOneWidget);
    f.predictions.historyError = null;
    f.predictions.history_ = [prediction()];
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Rose Quartz'), findsOneWidget);
  });

  testWidgets('bookmark on a Recent Find saves it to My Finds', (tester) async {
    final f = Fakes()..predictions.history_ = [prediction(id: 'p1')];
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byIcon(Icons.bookmark_border).first);
    await tester.pumpAndSettle();
    expect(f.collections.calls, contains('save:p1'));
    expect(find.byIcon(Icons.bookmark), findsWidgets);
  });

  testWidgets('Explore search, sort and open detail', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('nav_explore')));
    await tester.pumpAndSettle();
    expect(find.text('Filters:'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('explore_search')), 'gar');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Garnet'), findsOneWidget);
    expect(find.text('Obsidian'), findsNothing);

    await tester.enterText(find.byKey(const Key('explore_search')), 'zzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('explore_empty')), findsOneWidget);

    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obsidian'));
    await tester.pumpAndSettle();
    expect(find.text('Traditional meanings'), findsOneWidget);
    expect(find.textContaining('not scientific'), findsWidgets);
    await tester.tap(find.byKey(const Key('gem_favorite_icon')));
    await tester.pumpAndSettle();
    expect(f.collections.calls, contains('fav:g3'));
  });
}

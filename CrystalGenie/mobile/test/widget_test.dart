import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  testWidgets('app starts on the Crystal Genie splash artwork, then shows Login', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });
}

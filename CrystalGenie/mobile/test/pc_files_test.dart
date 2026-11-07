import 'dart:io';

import 'package:crystal_genie/core/network/api_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<String> _tempPng() async {
  final dir = await Directory.systemTemp.createTemp('cg_pc');
  final f = File('${dir.path}/garnet.png');
  await f.writeAsBytes(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
  return f.path;
}

void main() {
  testWidgets('Upload > This computer: browse PC folders, pick a photo, open the preview', (tester) async {
    final f = Fakes();
    f.pcFiles.downloadPath = await tester.runAsync(_tempPng);
    await pumpApp(tester, f, signedIn: true);

    await tester.tap(find.byKey(const Key('quick_upload')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device_phone')), findsOneWidget);
    await tester.tap(find.byKey(const Key('device_computer')));
    await tester.pumpAndSettle();

    expect(find.text('This computer'), findsOneWidget);
    await tester.tap(find.text('ASUS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pc_folder_Pictures')));
    await tester.pumpAndSettle();
    expect(find.text('Photos (1)'), findsOneWidget);

    // back goes up one folder, not out of the screen
    await tester.tap(find.byKey(const Key('pc_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pc_folder_Pictures')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pc_folder_Pictures')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('pc_image_garnet.jpg')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview_identify')), findsOneWidget);
  });

  testWidgets('Upload > From device opens the system file picker and then the preview', (tester) async {
    final f = Fakes();
    f.images.filePath = await tester.runAsync(_tempPng);
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('quick_upload')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_phone')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview_identify')), findsOneWidget);
  });

  testWidgets('This computer shows a clear message when browsing is off', (tester) async {
    final f = Fakes()..pcFiles.error = const ApiException(code: 'pc_browse_disabled', statusCode: 404, message: 'Browsing this computer is turned off.');
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('nav_scan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('camera_computer')));
    await tester.pumpAndSettle();
    expect(find.text('Browsing this computer is turned off.'), findsOneWidget);
  });
}

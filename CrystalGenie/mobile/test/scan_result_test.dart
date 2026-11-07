import 'dart:async';
import 'dart:io';

import 'package:crystal_genie/core/network/api_exception.dart';
import 'package:crystal_genie/features/camera/data/media_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

Future<String> _tempImage(String name) async {
  final dir = await Directory.systemTemp.createTemp('cg_test');
  final f = File('${dir.path}/$name');
  // 1x1 PNG
  await f.writeAsBytes(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
    0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
  return f.path;
}

Future<void> _openCamera(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('nav_scan')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('camera permission denied shows explanation and gallery option', (tester) async {
    final f = Fakes();
    await pumpApp(tester, f, signedIn: true);
    await _openCamera(tester);
    expect(find.byKey(const Key('camera_permission_message')), findsOneWidget);
    expect(find.text('Allow camera'), findsOneWidget);
    expect(f.permissions.requests, 1);
    expect(find.byKey(const Key('camera_gallery')), findsOneWidget);
  });

  testWidgets('permanently denied permission offers system settings', (tester) async {
    final f = Fakes()..permissions.status = CamPermission.permanentlyDenied;
    await pumpApp(tester, f, signedIn: true);
    await _openCamera(tester);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(f.permissions.openedSettings, isTrue);
  });

  testWidgets('granted permission on a device with no camera falls back to gallery', (tester) async {
    final f = Fakes()..permissions.status = CamPermission.granted;
    await pumpApp(tester, f, signedIn: true);
    await _openCamera(tester);
    expect(find.byKey(const Key('camera_none_message')), findsOneWidget);
  });

  testWidgets('Home Upload → From device → identify ends on the result (not the camera)', (tester) async {
    final f = Fakes();
    f.images.pickPath = await tester.runAsync(() => _tempImage('gem.png'));
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.byKey(const Key('quick_upload')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_phone')));
    await tester.pumpAndSettle();
    expect(find.text('Looks good?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('preview_identify')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result_title')), findsOneWidget);
    expect(find.text('Keep your crystal within the frame'), findsNothing);
    expect(f.predictions.predictCalls, 1);
  });

  testWidgets('upload workflow: gallery → preview → processing → result', (tester) async {
    final f = Fakes();
    final path = await tester.runAsync(() => _tempImage('gem.png'));
    f.images.pickPath = path;
    f.predictions.predictCompleter = Completer();
    await pumpApp(tester, f, signedIn: true);
    await _openCamera(tester);
    await tester.tap(find.byKey(const Key('camera_gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_phone')));
    await tester.pumpAndSettle();
    expect(find.text('Looks good?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('preview_identify')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byKey(const Key('processing_overlay')), findsOneWidget);
    expect(find.text('Identifying your crystal…'), findsOneWidget);

    f.predictions.predictCompleter!.complete(prediction());
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result_title')), findsOneWidget);
    expect(find.text("You've got a"), findsOneWidget);
    expect(find.text('93% confidence'), findsOneWidget);
    expect(find.text('Top 3 matches'), findsOneWidget);
    expect(f.predictions.predictCalls, 1);
  });

  testWidgets('upload errors are shown and the user can retry', (tester) async {
    final f = Fakes();
    f.images.pickPath = await tester.runAsync(() => _tempImage('gem.jpg'));
    f.predictions.predictError =
        const ApiException(code: 'network_error', message: "Can't reach the Crystal Genie server.");
    await pumpApp(tester, f, signedIn: true);
    await _openCamera(tester);
    await tester.tap(find.byKey(const Key('camera_gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_phone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview_identify')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview_error')), findsOneWidget);
    expect(find.text("Can't reach the Crystal Genie server."), findsOneWidget);
    expect(find.text('Looks good?'), findsOneWidget);
  });

  testWidgets('unsupported files are rejected before upload', (tester) async {
    final f = Fakes();
    f.images.pickPath = await tester.runAsync(() => _tempImage('notes.gif'));
    await pumpApp(tester, f, signedIn: true);
    await _openCamera(tester);
    await tester.tap(find.byKey(const Key('camera_gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_phone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('preview_identify')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unsupported file type'), findsOneWidget);
    expect(f.predictions.predictCalls, 0);
  });

  testWidgets('result page renders gem details, beliefs label, save and favorite', (tester) async {
    final f = Fakes()..predictions.history_ = [prediction(id: 'p1')];
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.text('Learn more').first);
    await tester.pumpAndSettle();
    expect(find.text('Rose Quartz'), findsWidgets);
    expect(find.text('Mineral family & hardness'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('traditional_meanings')), 300);
    await tester.ensureVisible(find.byKey(const Key('traditional_meanings')));
    await tester.pumpAndSettle();
    expect(find.text('Cultural beliefs and folklore — not scientific or medical claims.'), findsOneWidget);
    expect(find.text('Typical sources'), findsOneWidget);

    await tester.scrollUntilVisible(find.byKey(const Key('result_save')), 300);
    await tester.ensureVisible(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('result_save')));
    await tester.pumpAndSettle();
    expect(f.collections.calls, contains('save:p1'));
    expect(find.text('Saved to My Finds'), findsWidgets);

    await tester.tap(find.byKey(const Key('result_favorite')));
    await tester.pumpAndSettle();
    expect(f.collections.calls, contains('fav:g1'));
    expect(find.text('In Favorites'), findsOneWidget);
  });

  testWidgets('low confidence is shown as "Uncertain identification"', (tester) async {
    final f = Fakes()..predictions.history_ = [prediction(id: 'p9', conf: 0.34, uncertain: true)];
    await pumpApp(tester, f, signedIn: true);
    await tester.tap(find.text('Learn more').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('result_uncertain')), findsOneWidget);
    expect(find.text('Uncertain identification'), findsWidgets);
    expect(find.textContaining('only 34% confident'), findsOneWidget);
    expect(find.byKey(const Key('result_confidence')), findsNothing);
  });
}

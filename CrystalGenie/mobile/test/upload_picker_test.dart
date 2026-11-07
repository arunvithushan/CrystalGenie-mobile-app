import 'dart:io';
import 'dart:typed_data';

import 'package:crystal_genie/features/camera/data/link_image_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

Future<String> _tempPng() async {
  final dir = await Directory.systemTemp.createTemp('cg_up');
  final f = File('${dir.path}/gem.png');
  await f.writeAsBytes(_png);
  return f.path;
}

/// Answers every request with fixed bytes and content type, and records the URLs asked for.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bytes, {this.type = 'image/png'});
  final List<int> bytes;
  final String type;
  final urls = <Uri>[];
  final headers = <Map<String, dynamic>>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    urls.add(o.uri);
    headers.add(o.headers);
    return ResponseBody.fromBytes(bytes, 200, headers: {
      Headers.contentTypeHeader: [type],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('quick_upload')));
  await tester.pumpAndSettle();
}

void main() {
  group('link helpers', () {
    test('Drive share links become direct-download links', () {
      const id = '1AbCdEfGhIjKlMnOpQrStUv';
      for (final link in [
        'https://drive.google.com/file/d/$id/view?usp=sharing',
        'https://drive.google.com/open?id=$id',
        'https://drive.google.com/uc?id=$id&export=download',
      ]) {
        final u = resolveImageLink(link, driveOnly: true);
        expect(u.toString(), 'https://drive.google.com/uc?export=download&id=$id', reason: link);
      }
    });

    test('bad links are refused with a clear message', () {
      expect(() => resolveImageLink('not a link'), throwsA(isA<LinkImageException>()));
      expect(() => resolveImageLink('ftp://example.com/a.jpg'), throwsA(isA<LinkImageException>()));
      expect(() => resolveImageLink('https://example.com/a.jpg', driveOnly: true),
          throwsA(predicate((e) => e.toString() == 'This is not a Google Drive file link.')));
      expect(() => resolveImageLink('https://drive.google.com/drive/folders/1AbCdEfGhIjKlMnOp'),
          throwsA(predicate((e) => e.toString().startsWith("That's a folder link"))));
      expect(resolveImageLink(' https://example.com/a.jpg ').host, 'example.com');
    });

    test('image type is read from the bytes', () {
      expect(sniffImageExtension(_png), 'png');
      expect(sniffImageExtension(const [0xFF, 0xD8, 0xFF, 0xE0]), 'jpg');
      expect(sniffImageExtension('RIFF\x00\x00\x00\x00WEBPVP8 '.codeUnits), 'webp');
      expect(sniffImageExtension('<html>'.codeUnits), isNull);
      expect(sniffImageExtension('GIF89a'.codeUnits), isNull);
    });
  });

  group('DioLinkImageService', () {
    test('downloads a photo to a temp file without sending any sign-in token', () async {
      final adapter = _FakeAdapter(_png);
      final dio = Dio(BaseOptions(responseType: ResponseType.bytes))..httpClientAdapter = adapter;
      final path = await DioLinkImageService(dio).download('https://example.com/gem');
      expect(path, endsWith('.png'));
      expect(await File(path).readAsBytes(), _png);
      expect(adapter.headers.single.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    });

    test('a Drive photo that is not shared gives the sharing hint', () async {
      final dio = Dio(BaseOptions(responseType: ResponseType.bytes))
        ..httpClientAdapter = _FakeAdapter('<html>Sign in</html>'.codeUnits, type: 'text/html');
      await expectLater(
        DioLinkImageService(dio).download('https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQ/view', driveOnly: true),
        throwsA(predicate((e) => e.toString().contains('Anyone with the link'))),
      );
    });

    test('a web page instead of a photo is refused', () async {
      final dio = Dio(BaseOptions(responseType: ResponseType.bytes))
        ..httpClientAdapter = _FakeAdapter('<html></html>'.codeUnits, type: 'text/html');
      await expectLater(DioLinkImageService(dio).download('https://example.com/page'),
          throwsA(predicate((e) => e.toString() == 'This link is not a JPEG, PNG or WEBP photo.')));
    });
  });

  testWidgets('Upload opens the file picker with all options and Cancel closes it', (tester) async {
    await pumpApp(tester, Fakes(), signedIn: true);
    await _openPicker(tester);
    for (final k in [
      'upload_dropzone',
      'upload_from_device',
      'upload_from_link',
      'upload_from_camera',
      'upload_from_drive',
      'upload_cancel',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.text('From device'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.byKey(const Key('upload_from_computer')), findsNothing);
    await tester.tap(find.byKey(const Key('upload_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upload_dropzone')), findsNothing);
  });

  testWidgets('tapping the top area opens the device file picker', (tester) async {
    final f = Fakes();
    f.images.filePath = await tester.runAsync(_tempPng);
    await pumpApp(tester, f, signedIn: true);
    await _openPicker(tester);
    await tester.tap(find.byKey(const Key('upload_dropzone')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview_identify')), findsOneWidget);
  });

  testWidgets('From link downloads the photo and opens the preview', (tester) async {
    final f = Fakes();
    f.links.path = await tester.runAsync(_tempPng);
    await pumpApp(tester, f, signedIn: true);
    await _openPicker(tester);
    await tester.tap(find.byKey(const Key('upload_from_link')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('link_field')), 'https://example.com/garnet.jpg');
    await tester.tap(find.byKey(const Key('link_ok')));
    await tester.pumpAndSettle();
    expect(f.links.links, ['https://example.com/garnet.jpg']);
    expect(find.byKey(const Key('preview_identify')), findsOneWidget);
  });

  testWidgets('Google Drive asks for a Drive link and explains a wrong one', (tester) async {
    final f = Fakes();
    f.links.path = await tester.runAsync(_tempPng);
    await pumpApp(tester, f, signedIn: true);
    await _openPicker(tester);
    await tester.tap(find.byKey(const Key('upload_from_drive')));
    await tester.pumpAndSettle();
    expect(find.text('Photo from Google Drive'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('link_field')), 'https://example.com/garnet.jpg');
    await tester.tap(find.byKey(const Key('link_ok')));
    await tester.pumpAndSettle();
    expect(find.text('This is not a Google Drive file link.'), findsOneWidget);
    expect(f.links.links, isEmpty);

    await tester.enterText(find.byKey(const Key('link_field')), 'https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQ/view');
    await tester.tap(find.byKey(const Key('link_ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview_identify')), findsOneWidget);
  });

  testWidgets('a link that is not a photo shows an error and stays on Home', (tester) async {
    final f = Fakes(); // links.path is null → the fake reports "not a photo"
    await pumpApp(tester, f, signedIn: true);
    await _openPicker(tester);
    await tester.tap(find.byKey(const Key('upload_from_link')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('link_field')), 'https://example.com/page');
    await tester.tap(find.byKey(const Key('link_ok')));
    await tester.pumpAndSettle();
    expect(find.text('This link is not a JPEG, PNG or WEBP photo.'), findsOneWidget);
    expect(find.byKey(const Key('preview_identify')), findsNothing);
    expect(find.byKey(const Key('link_downloading')), findsNothing);
  });

  testWidgets('Camera in the picker opens the scan screen', (tester) async {
    await pumpApp(tester, Fakes(), signedIn: true);
    await _openPicker(tester);
    await tester.tap(find.byKey(const Key('upload_from_camera')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('camera_gallery')), findsOneWidget);
  });

  testWidgets('From device asks: this phone or this computer', (tester) async {
    final f = Fakes();
    f.images.filePath = await tester.runAsync(_tempPng);
    await pumpApp(tester, f, signedIn: true);
    await _openPicker(tester);
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('device_phone')), findsOneWidget);
    expect(find.byKey(const Key('device_computer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('device_phone')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preview_identify')), findsOneWidget);
  });

  testWidgets('From device → This computer opens the PC folders', (tester) async {
    await pumpApp(tester, Fakes(), signedIn: true);
    await _openPicker(tester);
    await tester.tap(find.byKey(const Key('upload_from_device')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device_computer')));
    await tester.pumpAndSettle();
    expect(find.text('This computer'), findsOneWidget);
    expect(find.byKey(const Key('pc_back')), findsOneWidget);
  });
}

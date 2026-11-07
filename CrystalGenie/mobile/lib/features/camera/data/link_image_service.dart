import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';

/// A link the user pasted could not be turned into a photo. [message] is English; the UI translates it.
class LinkImageException implements Exception {
  const LinkImageException(this.message);
  final String message;
  @override
  String toString() => message;
}

final _driveIdPatterns = [
  RegExp(r'/file/d/([A-Za-z0-9_-]{10,})'), // drive.google.com/file/d/<id>/view
  RegExp(r'[?&]id=([A-Za-z0-9_-]{10,})'), // drive.google.com/open?id=<id>, /uc?id=<id>
];

bool isGoogleDriveHost(Uri uri) =>
    uri.host == 'drive.google.com' || uri.host == 'docs.google.com' || uri.host == 'drive.usercontent.google.com';

/// The file id in a Google Drive share link, or null when it is not a Drive *file* link.
String? driveFileId(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || !isGoogleDriveHost(uri)) return null;
  for (final p in _driveIdPatterns) {
    final m = p.firstMatch(link);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Turns a pasted link into the URL to download. Drive share links become Drive's direct-download URL.
/// Throws [LinkImageException] for anything that is not an http(s) link to a single file.
Uri resolveImageLink(String link, {bool driveOnly = false}) {
  final text = link.trim();
  final uri = Uri.tryParse(text);
  if (text.isEmpty || uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
    throw const LinkImageException('Please paste a full link that starts with http:// or https://');
  }
  if (isGoogleDriveHost(uri)) {
    if (uri.path.contains('/folders/') || uri.path.contains('/drive/')) {
      throw const LinkImageException("That's a folder link. Open the photo in Drive and copy the link of the photo itself.");
    }
    final id = driveFileId(text);
    if (id == null) throw const LinkImageException('This is not a Google Drive file link.');
    return Uri.https('drive.google.com', '/uc', {'export': 'download', 'id': id});
  }
  if (driveOnly) throw const LinkImageException('This is not a Google Drive file link.');
  return uri;
}

/// File extension for JPEG / PNG / WEBP bytes, or null for anything else (checked by content, not by the link).
String? sniffImageExtension(List<int> b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'jpg';
  if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'png';
  if (b.length >= 12 &&
      String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
    return 'webp';
  }
  return null;
}

/// Downloads a photo from a web or Google Drive link into a temporary file and returns its path.
abstract class LinkImageService {
  Future<String> download(String link, {bool driveOnly = false});
}

class DioLinkImageService implements LinkImageService {
  DioLinkImageService([Dio? dio])
      // A separate client on purpose: the API client adds the user's sign-in token, which must never go to other sites.
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              followRedirects: true,
              maxRedirects: 5,
              responseType: ResponseType.bytes,
              validateStatus: (s) => s != null && s < 500,
            ));

  final Dio _dio;

  @override
  Future<String> download(String link, {bool driveOnly = false}) async {
    final url = resolveImageLink(link, driveOnly: driveOnly);
    final isDrive = isGoogleDriveHost(url);
    final cancel = CancelToken();
    Response<List<int>> res;
    try {
      res = await _dio.getUri<List<int>>(url, cancelToken: cancel, onReceiveProgress: (got, total) {
        if (got > AppConfig.maxUploadBytes) cancel.cancel('too_big');
      });
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw const LinkImageException('This photo is larger than 10 MB. Please choose a smaller one.');
      }
      throw const LinkImageException('Could not download from this link. Check the link and your internet connection.');
    }
    final status = res.statusCode ?? 0;
    final bytes = res.data ?? const <int>[];
    if (status == 401 || status == 403 || (isDrive && status == 404)) {
      throw LinkImageException(isDrive ? _driveNotShared : 'This link needs a sign-in, so the photo could not be downloaded.');
    }
    if (status >= 400) throw const LinkImageException('Could not download from this link. Check the link and your internet connection.');
    if (bytes.length > AppConfig.maxUploadBytes) {
      throw const LinkImageException('This photo is larger than 10 MB. Please choose a smaller one.');
    }
    final ext = sniffImageExtension(bytes);
    if (ext == null) {
      final type = res.headers.value(Headers.contentTypeHeader) ?? '';
      if (isDrive && type.contains('text/html')) throw const LinkImageException(_driveNotShared);
      throw const LinkImageException('This link is not a JPEG, PNG or WEBP photo.');
    }
    final dir = await Directory.systemTemp.createTemp('cg_link');
    final file = File('${dir.path}/linked_photo.$ext');
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    return file.path;
  }

  static const _driveNotShared =
      "This Drive photo isn't shared publicly. In Drive choose Share → General access → Anyone with the link, then try again.";
}

final linkImageServiceProvider = Provider<LinkImageService>((ref) => DioLinkImageService());

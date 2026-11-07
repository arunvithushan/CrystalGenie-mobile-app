import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

class PcFolder {
  const PcFolder({required this.name, required this.path, this.kind = 'folder'});
  final String name;
  final String path;

  /// 'place' (Desktop, Pictures, Downloads, Documents), 'root' (user folder / drive) or 'folder'.
  final String kind;
  factory PcFolder.fromJson(Map<String, dynamic> j) =>
      PcFolder(name: '${j['name']}', path: '${j['path']}', kind: '${j['kind'] ?? 'folder'}');
}

class PcImage {
  const PcImage({required this.name, required this.path, this.size = 0});
  final String name;
  final String path;
  final int size;
  factory PcImage.fromJson(Map<String, dynamic> j) =>
      PcImage(name: '${j['name']}', path: '${j['path']}', size: (j['size'] as num?)?.toInt() ?? 0);
}

class PcListing {
  const PcListing({required this.path, required this.name, this.parent, this.folders = const [], this.images = const [], this.truncated = false});
  final String path;
  final String name;
  final String? parent;
  final List<PcFolder> folders;
  final List<PcImage> images;
  final bool truncated;

  factory PcListing.fromJson(Map<String, dynamic> j) => PcListing(
        path: '${j['path']}',
        name: '${j['name']}',
        parent: j['parent'] as String?,
        folders: [for (final f in (j['folders'] as List? ?? const [])) PcFolder.fromJson((f as Map).cast<String, dynamic>())],
        images: [for (final f in (j['images'] as List? ?? const [])) PcImage.fromJson((f as Map).cast<String, dynamic>())],
        truncated: j['truncated'] == true,
      );
}

/// Photos on the PC that runs the backend ("Browse this computer", development feature — see
/// backend/app/api/routes/pc_files.py). Read-only.
abstract class PcFilesRepository {
  Future<List<PcFolder>> roots();
  Future<PcListing> list(String path);

  /// Copies the picture to a temporary file on this device and returns its path (for the normal preview → identify flow).
  Future<String> download(PcImage image);

  /// API path of a small preview (for [ApiImage], which adds the sign-in token).
  String thumbnailPath(String path) => '/api/pc/image?thumb=true&path=${Uri.encodeQueryComponent(path)}';
}

class ApiPcFilesRepository extends PcFilesRepository {
  ApiPcFilesRepository(this._api);
  final ApiClient _api;

  @override
  Future<List<PcFolder>> roots() => _api.get('/pc/roots',
      parse: (d) => [for (final r in ((d as Map)['roots'] as List)) PcFolder.fromJson((r as Map).cast<String, dynamic>())]);

  @override
  Future<PcListing> list(String path) =>
      _api.get('/pc/list', query: {'path': path}, parse: (d) => PcListing.fromJson((d as Map).cast<String, dynamic>()));

  @override
  Future<String> download(PcImage image) async {
    try {
      final res = await _api.dio.get<List<int>>('/pc/image',
          queryParameters: {'path': image.path},
          options: Options(responseType: ResponseType.bytes, extra: {'auth': true}, receiveTimeout: const Duration(seconds: 60)));
      final dot = image.name.lastIndexOf('.');
      final ext = dot >= 0 ? image.name.substring(dot).toLowerCase() : '.jpg';
      final file = File('${Directory.systemTemp.path}/cg_pc_${DateTime.now().millisecondsSinceEpoch}$ext');
      await file.writeAsBytes(res.data ?? const []);
      return file.path;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}

final pcFilesRepositoryProvider = Provider<PcFilesRepository>((ref) => ApiPcFilesRepository(ref.watch(apiClientProvider)));

final pcRootsProvider = FutureProvider.autoDispose<List<PcFolder>>((ref) => ref.watch(pcFilesRepositoryProvider).roots());
final pcListingProvider =
    FutureProvider.autoDispose.family<PcListing, String>((ref, path) => ref.watch(pcFilesRepositoryProvider).list(path));

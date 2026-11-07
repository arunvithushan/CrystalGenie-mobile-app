import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme.dart';
import '../../../core/config/app_config.dart';

enum CamPermission { granted, denied, permanentlyDenied }

/// Camera permission (wrapped so it can be faked in tests).
abstract class PermissionService {
  Future<CamPermission> cameraStatus();
  Future<CamPermission> requestCamera();
  Future<bool> openSettings();
}

class DevicePermissionService implements PermissionService {
  CamPermission _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return CamPermission.granted;
    if (s.isPermanentlyDenied || s.isRestricted) return CamPermission.permanentlyDenied;
    return CamPermission.denied;
  }

  @override
  Future<CamPermission> cameraStatus() async => _map(await Permission.camera.status);
  @override
  Future<CamPermission> requestCamera() async => _map(await Permission.camera.request());
  @override
  Future<bool> openSettings() => openAppSettings();
}

/// Lists cameras (wrapped so tests can return none).
abstract class CameraSource {
  Future<List<CameraDescription>> cameras();
}

class DeviceCameraSource implements CameraSource {
  @override
  Future<List<CameraDescription>> cameras() => availableCameras();
}

/// Gallery picking and optional cropping.
abstract class ImageService {
  Future<String?> pickFromGallery();

  /// System file picker (Android "Files"): any JPG/PNG/WEBP from Downloads, SD card, Google Drive, USB …
  Future<String?> pickFile();
  Future<String?> crop(String path);
}

class DeviceImageService implements ImageService {
  final _picker = ImagePicker();

  @override
  Future<String?> pickFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 2048, maxHeight: 2048, imageQuality: 90);
    return x?.path;
  }

  @override
  Future<String?> pickFile() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
    );
    return r?.files.single.path;
  }

  @override
  Future<String?> crop(String path) async {
    final f = await ImageCropper().cropImage(
      sourcePath: path,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 92,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop your crystal',
          toolbarColor: AppColors.teal,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: AppColors.teal,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: false,
          aspectRatioPresets: const [CropAspectRatioPreset.square, CropAspectRatioPreset.original],
        ),
        IOSUiSettings(title: 'Crop your crystal'),
      ],
    );
    return f?.path;
  }
}

/// Checks a picked file before upload. Returns an error message or null when OK.
Future<String?> validateImageFile(String path) async {
  final stat = File(path).statSync(); // a single metadata lookup; fast enough for the UI thread
  if (stat.type == FileSystemEntityType.notFound) return 'The photo could not be found. Please take it again.';
  final lower = path.toLowerCase();
  const ok = ['.jpg', '.jpeg', '.png', '.webp'];
  if (!ok.any(lower.endsWith)) return 'Unsupported file type. Please choose a JPEG, PNG or WEBP photo.';
  final size = stat.size;
  if (size == 0) return 'The selected file is empty.';
  if (size > AppConfig.maxUploadBytes) return 'This photo is larger than 10 MB. Please choose a smaller one.';
  return null;
}

final permissionServiceProvider = Provider<PermissionService>((ref) => DevicePermissionService());
final cameraSourceProvider = Provider<CameraSource>((ref) => DeviceCameraSource());
final imageServiceProvider = Provider<ImageService>((ref) => DeviceImageService());

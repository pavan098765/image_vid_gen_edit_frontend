import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/media_upload_service.dart';

/// Uploads a still so a video job can use it as a start or end frame.
class StudioMedia {
  StudioMedia({this.uploadOverride});

  final Future<String?> Function(String path)? uploadOverride;

  Future<String?> uploadImage(String path) async {
    if (uploadOverride != null) return uploadOverride!(path);
    final bytes = await File(path).readAsBytes();
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) return null;
    final keys = await MediaUploadService.uploadMediaBatch(
      files: [bytes],
      mediaType: 'image',
      authToken: token,
    );
    if (keys == null || keys.isEmpty) return null;
    return keys.first;
  }
}

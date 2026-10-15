import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/studio/studio_api.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/state/editor_providers.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/video_editor_page.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:video_player/video_player.dart';

Future<void> openStudioInEditor(BuildContext context, String jobId) async {
  final board = await StudioApi.instance.getStoryboard(jobId);
  final dir = await getTemporaryDirectory();
  final paths = <String>[];
  var index = 0;
  for (final scene in board.scenes) {
    final url = scene.previewUrl;
    if (url == null || url.isEmpty) continue;
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode >= 400) continue;
    final file = File('${dir.path}/studio_${jobId}_$index.mp4');
    await file.writeAsBytes(resp.bodyBytes);
    paths.add(file.path);
    index += 1;
  }
  if (paths.isEmpty) {
    final result = await StudioApi.instance.getResult(jobId);
    final url = result['url'] as String?;
    if (url != null) {
      final resp = await http.get(Uri.parse(url));
      final file = File('${dir.path}/studio_$jobId.mp4');
      await file.writeAsBytes(resp.bodyBytes);
      paths.add(file.path);
    }
  }
  if (!context.mounted) return;
  if (paths.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No scene files to open in Editor')),
    );
    return;
  }

  final usable = <String>[];
  final durations = <Duration>[];
  for (final path in paths) {
    Duration? duration;
    try {
      final metadata = await ProVideoEditor.instance.getMetadata(
        EditorVideo.file(File(path)),
      );
      duration = metadata.duration;
    } catch (_) {
      try {
        final controller = VideoPlayerController.file(File(path));
        await controller.initialize();
        duration = controller.value.duration;
        await controller.dispose();
      } catch (_) {
        duration = null;
      }
    }
    if (duration == null || duration <= Duration.zero) continue;
    usable.add(path);
    durations.add(duration);
  }

  if (!context.mounted) return;
  if (usable.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No scene files to open in Editor')),
    );
    return;
  }

  final container = ProviderScope.containerOf(context);
  container.read(projectProvider.notifier).createFromScenePaths(
        usable,
        durations: durations,
      );

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => VideoEditorPage(
        initialVideoPath: usable.first,
        useExistingProject: true,
        jobId: jobId,
      ),
    ),
  );
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';

/// Opens a photo or video in the Editor tab that already lives under the
/// bottom navigation, instead of pushing a second editor route.
class EditorTabLaunch {
  final int id;
  final File? image;
  final String? videoPath;
  final String? historyId;
  final String? jobId;
  final bool returnToResultManager;
  final int restoreTabIndex;

  const EditorTabLaunch({
    required this.id,
    this.image,
    this.videoPath,
    this.historyId,
    this.jobId,
    this.returnToResultManager = false,
    this.restoreTabIndex = 0,
  });
}

final ValueNotifier<EditorTabLaunch?> editorTabLaunchNotifier =
    ValueNotifier<EditorTabLaunch?>(null);

int _editorTabLaunchSeq = 0;

void requestEditorTabLaunch({
  File? image,
  String? videoPath,
  String? historyId,
  String? jobId,
  bool returnToResultManager = false,
  int restoreTabIndex = 0,
}) {
  editorTabLaunchNotifier.value = EditorTabLaunch(
    id: ++_editorTabLaunchSeq,
    image: image,
    videoPath: videoPath,
    historyId: historyId,
    jobId: jobId,
    returnToResultManager: returnToResultManager,
    restoreTabIndex: restoreTabIndex,
  );
}

/// Creations is a bottom-nav tab, so leaving the editor switches back to that
/// tab directly. Pushing another results page left a route whose completion
/// cleared the next photo the user opened.
void returnEditorSessionToResultManager({
  required int restoreTabIndex,
  VoidCallback? onCovered,
}) {
  selectedIndexNotifier.value = restoreTabIndex;
  onCovered?.call();
}

// lib/features/video_editor/state/editor_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clip_model.dart';
import '../models/project_model.dart';
import '../utils/playback_mapping.dart';
import 'playback_notifier.dart';
import 'project_notifier.dart';
import 'timeline_notifier.dart';
import 'tool_notifier.dart';

// ─── Project ─────────────────────────────────────────────────────────────────
final projectProvider =
    StateNotifierProvider<ProjectNotifier, VideoProject?>((ref) {
  return ProjectNotifier();
});

// ─── Playback ────────────────────────────────────────────────────────────────
final playbackProvider =
    StateNotifierProvider<PlaybackNotifier, PlaybackState>((ref) {
  return PlaybackNotifier();
});

// ─── Timeline ────────────────────────────────────────────────────────────────
final timelineProvider =
    StateNotifierProvider<TimelineNotifier, TimelineState>((ref) {
  return TimelineNotifier();
});

// ─── Tool / Panel ────────────────────────────────────────────────────────────
final toolProvider =
    StateNotifierProvider<ToolNotifier, ToolState>((ref) {
  return ToolNotifier();
});

// ─── Export trigger ───────────────────────────────────────────────────────────
/// Incremented by ExportPanel to signal the parent page to start export.
final exportTriggerProvider = StateProvider<int>((ref) => 0);

// ─── Derived / convenience providers ─────────────────────────────────────────

/// Total project duration.
final totalDurationProvider = Provider<Duration>((ref) {
  final project = ref.watch(projectProvider);
  return project?.totalDuration ?? Duration.zero;
});

/// Currently selected clip (the primary one, when several are selected).
final selectedClipProvider = Provider((ref) {
  final project = ref.watch(projectProvider);
  final tlState = ref.watch(timelineProvider);
  if (project == null || tlState.selectedClipId == null) return null;
  return project.findClipById(tlState.selectedClipId!);
});

/// Select the clip under the playhead, or the first video clip, when none is selected.
bool ensureDefaultVideoSelection(WidgetRef ref) {
  if (ref.read(selectedClipProvider) is VideoClip) return true;
  final project = ref.read(projectProvider);
  if (project == null) return false;
  final position = ref.read(playbackProvider).position;
  final clips = sortedVideoClips(project);
  final pick =
      activeVideoClipAt(project, position) ?? (clips.isEmpty ? null : clips.first);
  if (pick == null) return false;
  final track = project.findTrackForClip(pick.id);
  ref.read(timelineProvider.notifier).selectClip(pick.id, trackId: track?.id);
  ref.read(projectProvider.notifier).selectClip(pick.id);
  return true;
}

/// Write [updater] onto every selected video clip. Returns how many were updated.
int applyToSelectedVideoClips(
  WidgetRef ref,
  VideoClip Function(VideoClip clip) updater,
) {
  final project = ref.read(projectProvider);
  if (project == null) return 0;
  final timeline = ref.read(timelineProvider);
  final ids = timeline.selectedClipIds.isNotEmpty
      ? timeline.selectedClipIds
      : <String>[
          if (timeline.selectedClipId != null) timeline.selectedClipId!,
        ];
  final videoIds = <String>[
    for (final id in ids)
      if (project.findClipById(id) is VideoClip) id,
  ];
  if (videoIds.isEmpty) return 0;
  ref.read(projectProvider.notifier).updateMany(videoIds, (clip) {
    if (clip is! VideoClip) return clip;
    return updater(clip);
  });
  return videoIds.length;
}

/// Whether the editor can undo.
final canUndoProvider = Provider<bool>((ref) {
  // Watch the project state so this re-evaluates on every state change
  ref.watch(projectProvider);
  return ref.read(projectProvider.notifier).canUndo;
});

/// Whether the editor can redo.
final canRedoProvider = Provider<bool>((ref) {
  // Watch the project state so this re-evaluates on every state change
  ref.watch(projectProvider);
  return ref.read(projectProvider.notifier).canRedo;
});

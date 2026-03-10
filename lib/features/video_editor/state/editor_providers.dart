// lib/features/video_editor/state/editor_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/project_model.dart';
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

/// Currently selected clip.
final selectedClipProvider = Provider((ref) {
  final project = ref.watch(projectProvider);
  final tlState = ref.watch(timelineProvider);
  if (project == null || tlState.selectedClipId == null) return null;
  return project.findClipById(tlState.selectedClipId!);
});

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

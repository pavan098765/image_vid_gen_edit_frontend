// lib/features/video_editor/state/project_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clip_model.dart';
import '../models/project_model.dart';

/// Manages the full [VideoProject] state — tracks, clips, effects, etc.
class ProjectNotifier extends StateNotifier<VideoProject?> {
  ProjectNotifier() : super(null);

  // ─── Undo / Redo ──────────────────────────────────────────────────────────
  final List<VideoProject> _undoStack = [];
  final List<VideoProject> _redoStack = [];
  static const int _maxUndoSteps = 50;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void _pushUndo() {
    if (state == null) return;
    _undoStack.add(state!);
    if (_undoStack.length > _maxUndoSteps) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (!canUndo) return;
    if (state != null) _redoStack.add(state!);
    state = _undoStack.removeLast();
  }

  void redo() {
    if (!canRedo) return;
    if (state != null) _undoStack.add(state!);
    state = _redoStack.removeLast();
  }

  // ─── Project lifecycle ────────────────────────────────────────────────────

  /// Create a new project from a picked video.
  void createProject({
    required String projectId,
    required String videoPath,
    required Duration videoDuration,
    required double width,
    required double height,
  }) {
    _undoStack.clear();
    _redoStack.clear();
    state = VideoProject.fromVideo(
      projectId: projectId,
      videoPath: videoPath,
      videoDuration: videoDuration,
      width: width,
      height: height,
    );
  }

  void clearProject() {
    _undoStack.clear();
    _redoStack.clear();
    state = null;
  }

  // ─── Track operations ─────────────────────────────────────────────────────

  void addTrack(Track track) {
    if (state == null) return;
    _pushUndo();
    state = state!.copyWith(
      tracks: [...state!.tracks, track],
      totalDuration: state!.copyWith(tracks: [...state!.tracks, track]).computeTotalDuration(),
    );
  }

  void removeTrack(String trackId) {
    if (state == null) return;
    _pushUndo();
    final tracks = state!.tracks.where((t) => t.id != trackId).toList();
    state = state!.copyWith(
      tracks: tracks,
      totalDuration: state!.copyWith(tracks: tracks).computeTotalDuration(),
    );
  }

  void updateTrack(String trackId, Track Function(Track) updater) {
    if (state == null) return;
    _pushUndo();
    final tracks = state!.tracks.map((t) {
      if (t.id == trackId) return updater(t);
      return t;
    }).toList();
    state = state!.copyWith(
      tracks: tracks,
      totalDuration: state!.copyWith(tracks: tracks).computeTotalDuration(),
    );
  }

  // ─── Clip operations ──────────────────────────────────────────────────────

  void addClipToTrack(String trackId, Clip clip) {
    updateTrack(trackId, (t) => t.copyWith(clips: [...t.clips, clip]));
  }

  void removeClip(String clipId) {
    if (state == null) return;
    _pushUndo();
    final tracks = state!.tracks.map((t) {
      final filtered = t.clips.where((c) => c.id != clipId).toList();
      return t.copyWith(clips: filtered);
    }).toList();
    state = state!.copyWith(
      tracks: tracks,
      totalDuration: state!.copyWith(tracks: tracks).computeTotalDuration(),
    );
  }

  void updateClip(String clipId, Clip Function(Clip) updater) {
    if (state == null) return;
    _pushUndo();
    final tracks = state!.tracks.map((t) {
      final clips = t.clips.map((c) {
        if (c.id == clipId) return updater(c);
        return c;
      }).toList();
      return t.copyWith(clips: clips);
    }).toList();
    state = state!.copyWith(
      tracks: tracks,
      totalDuration: state!.copyWith(tracks: tracks).computeTotalDuration(),
    );
  }

  /// Select a single clip (deselect all others).
  void selectClip(String clipId) {
    if (state == null) return;
    final tracks = state!.tracks.map((t) {
      final clips = t.clips.map((c) {
        return c.copyWith(isSelected: c.id == clipId);
      }).toList();
      return t.copyWith(clips: clips);
    }).toList();
    state = state!.copyWith(tracks: tracks);
  }

  /// Deselect all clips.
  void deselectAll() {
    if (state == null) return;
    final tracks = state!.tracks.map((t) {
      final clips = t.clips.map((c) => c.copyWith(isSelected: false)).toList();
      return t.copyWith(clips: clips);
    }).toList();
    state = state!.copyWith(tracks: tracks);
  }

  // ─── Clip splitting ───────────────────────────────────────────────────────

  /// Split a video clip at the given time (relative to clip start).
  void splitVideoClipAt(String clipId, Duration splitPoint) {
    if (state == null) return;
    final clip = state!.findClipById(clipId);
    if (clip == null || clip is! VideoClip) return;
    final track = state!.findTrackForClip(clipId);
    if (track == null) return;

    final relSplit = splitPoint - clip.startTime;
    if (relSplit <= Duration.zero || relSplit >= clip.duration) return;

    _pushUndo();

    // First half
    final clip1 = clip.copyWith(
      duration: relSplit,
      trimEnd: clip.trimStart + relSplit,
    );

    // Second half
    final clip2 = VideoClip(
      id: '${clip.id}_split_${DateTime.now().microsecondsSinceEpoch}',
      startTime: clip.startTime + relSplit,
      duration: clip.duration - relSplit,
      sourcePath: clip.sourcePath,
      trimStart: clip.trimStart + relSplit,
      trimEnd: clip.trimEnd,
      originalDuration: clip.originalDuration,
      resolution: clip.resolution,
      speedEffect: clip.speedEffect,
      colorAdjustment: clip.colorAdjustment,
      volume: clip.volume,
      isMuted: clip.isMuted,
    );

    final newClips = <Clip>[];
    for (final c in track.clips) {
      if (c.id == clipId) {
        newClips.add(clip1);
        newClips.add(clip2);
      } else {
        newClips.add(c);
      }
    }

    final tracks = state!.tracks.map((t) {
      if (t.id == track.id) return t.copyWith(clips: newClips);
      return t;
    }).toList();

    state = state!.copyWith(tracks: tracks);
  }

  /// Duplicate a clip (placed right after the original).
  void duplicateClip(String clipId) {
    if (state == null) return;
    final clip = state!.findClipById(clipId);
    if (clip == null) return;
    final track = state!.findTrackForClip(clipId);
    if (track == null) return;

    _pushUndo();

    final dupe = clip.copyWith(
      startTime: clip.endTime,
      isSelected: false,
    );
    // Assign new id via type-specific copy
    Clip dupeWithNewId;
    if (dupe is VideoClip) {
      dupeWithNewId = VideoClip(
        id: '${clip.id}_dup_${DateTime.now().microsecondsSinceEpoch}',
        startTime: dupe.startTime,
        duration: dupe.duration,
        sourcePath: dupe.sourcePath,
        trimStart: dupe.trimStart,
        trimEnd: dupe.trimEnd,
        originalDuration: dupe.originalDuration,
        resolution: dupe.resolution,
        speedEffect: dupe.speedEffect,
        colorAdjustment: dupe.colorAdjustment,
        volume: dupe.volume,
        isMuted: dupe.isMuted,
      );
    } else if (dupe is AudioClip) {
      dupeWithNewId = AudioClip(
        id: '${clip.id}_dup_${DateTime.now().microsecondsSinceEpoch}',
        startTime: dupe.startTime,
        duration: dupe.duration,
        sourcePath: dupe.sourcePath,
        trimStart: dupe.trimStart,
        trimEnd: dupe.trimEnd,
        originalDuration: dupe.originalDuration,
        volume: dupe.volume,
        fadeIn: dupe.fadeIn,
        fadeOut: dupe.fadeOut,
        name: dupe.name,
      );
    } else if (dupe is TextClip) {
      dupeWithNewId = TextClip(
        id: '${clip.id}_dup_${DateTime.now().microsecondsSinceEpoch}',
        startTime: dupe.startTime,
        duration: dupe.duration,
        text: dupe.text,
        fontFamily: dupe.fontFamily,
        fontSize: dupe.fontSize,
        color: dupe.color,
        backgroundColor: dupe.backgroundColor,
        isBold: dupe.isBold,
        isItalic: dupe.isItalic,
        position: dupe.position,
        textAlign: dupe.textAlign,
        animation: dupe.animation,
        animationDuration: dupe.animationDuration,
      );
    } else if (dupe is StickerClip) {
      dupeWithNewId = StickerClip(
        id: '${clip.id}_dup_${DateTime.now().microsecondsSinceEpoch}',
        startTime: dupe.startTime,
        duration: dupe.duration,
        stickerData: dupe.stickerData,
        isEmoji: dupe.isEmoji,
        position: dupe.position,
        scale: dupe.scale,
        rotation: dupe.rotation,
      );
    } else if (dupe is PipClip) {
      dupeWithNewId = PipClip(
        id: '${clip.id}_dup_${DateTime.now().microsecondsSinceEpoch}',
        startTime: dupe.startTime,
        duration: dupe.duration,
        sourcePath: dupe.sourcePath,
        trimStart: dupe.trimStart,
        trimEnd: dupe.trimEnd,
        originalDuration: dupe.originalDuration,
        position: dupe.position,
        scale: dupe.scale,
        opacity: dupe.opacity,
        borderRadius: dupe.borderRadius,
        volume: dupe.volume,
      );
    } else {
      return; // Unknown type
    }

    addClipToTrack(track.id, dupeWithNewId);
  }

  // ─── Export settings ──────────────────────────────────────────────────────

  void updateExportSettings(ExportSettings settings) {
    if (state == null) return;
    state = state!.copyWith(exportSettings: settings);
  }
}

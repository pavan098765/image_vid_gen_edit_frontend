// lib/features/video_editor/state/project_notifier.dart

import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clip_model.dart';
import '../models/project_model.dart';
import '../services/thumbnail_cache_service.dart';

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

  void createFromScenePaths(List<String> paths, {Size resolution = const Size(1920, 1080)}) {
    if (paths.isEmpty) return;
    _undoStack.clear();
    _redoStack.clear();
    final projectId = 'studio_${DateTime.now().microsecondsSinceEpoch}';
    final clips = <Clip>[];
    var cursor = Duration.zero;
    for (var i = 0; i < paths.length; i++) {
      const dur = Duration(seconds: 5);
      clips.add(
        VideoClip(
          id: '${projectId}_clip_$i',
          startTime: cursor,
          duration: dur,
          sourcePath: paths[i],
          trimStart: Duration.zero,
          trimEnd: dur,
          originalDuration: dur,
          resolution: resolution,
        ),
      );
      cursor += dur;
    }
    final track = Track(
      id: '${projectId}_video_0',
      type: TrackType.video,
      name: 'Studio scenes',
      clips: clips,
    );
    state = VideoProject(
      id: projectId,
      name: 'Studio',
      tracks: [track],
      totalDuration: cursor,
    );
  }

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

    List<Uint8List>? tn1;
    List<Uint8List>? tn2;
    final tnl = clip.thumbnails;
    if (tnl != null && tnl.isNotEmpty) {
      tn1 = ThumbnailCacheService.sliceThumbnailsToFileRange(
        source: tnl,
        fileDuration: clip.originalDuration,
        rangeStart: clip.trimStart,
        rangeEnd: clip.trimStart + relSplit,
      );
      tn2 = ThumbnailCacheService.sliceThumbnailsToFileRange(
        source: tnl,
        fileDuration: clip.originalDuration,
        rangeStart: clip.trimStart + relSplit,
        rangeEnd: clip.trimEnd,
      );
    }

    // First half
    final clip1 = clip.copyWith(
      duration: relSplit,
      trimEnd: clip.trimStart + relSplit,
      thumbnails: tn1 ?? tnl,
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
      transitionIn: clip.transitionIn,
      volume: clip.volume,
      isMuted: clip.isMuted,
      thumbnails: tn2 ?? tnl,
      keyframeTracks: clip.keyframeTracks,
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

    var tracks = state!.tracks.map((t) {
      if (t.id == track.id) return t.copyWith(clips: newClips);
      return t;
    }).toList();

    tracks = tracks
        .map((t) => _splitPairedEmbeddedAudio(t, clip, splitPoint))
        .toList();

    final proj = state!.copyWith(tracks: tracks);
    state = proj.copyWith(
      totalDuration: proj.computeTotalDuration(),
    );
  }

  /// When the user splits a [VideoClip], split the matching embedded [AudioClip]
  /// (same file + same timeline segment) so preview audio stays aligned.
  Track _splitPairedEmbeddedAudio(
    Track audioTrack,
    VideoClip videoBeforeSplit,
    Duration splitPoint,
  ) {
    final newClips = <Clip>[];
    var changed = false;
    for (final c in audioTrack.clips) {
      if (c is! AudioClip) {
        newClips.add(c);
        continue;
      }
      final ac = c;
      final sameSegment = ac.sourcePath == videoBeforeSplit.sourcePath &&
          ac.startTime == videoBeforeSplit.startTime &&
          ac.duration == videoBeforeSplit.duration;
      if (!sameSegment) {
        newClips.add(c);
        continue;
      }
      final relSplit = splitPoint - videoBeforeSplit.startTime;
      if (relSplit <= Duration.zero || relSplit >= ac.duration) {
        newClips.add(c);
        continue;
      }
      changed = true;
      final ac1 = ac.copyWith(
        duration: relSplit,
        trimEnd: ac.trimStart + relSplit,
      );
      final ac2 = AudioClip(
        id: '${ac.id}_split_${DateTime.now().microsecondsSinceEpoch}',
        startTime: ac.startTime + relSplit,
        duration: ac.duration - relSplit,
        sourcePath: ac.sourcePath,
        trimStart: ac.trimStart + relSplit,
        trimEnd: ac.trimEnd,
        originalDuration: ac.originalDuration,
        volume: ac.volume,
        fadeIn: ac.fadeIn,
        fadeOut: ac.fadeOut,
        name: ac.name,
      );
      newClips.add(ac1);
      newClips.add(ac2);
    }
    if (!changed) return audioTrack;
    return audioTrack.copyWith(clips: newClips);
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
    AudioClip? pairedAudioDupe;
    String? pairedAudioTrackId;

    if (dupe is VideoClip) {
      final v = clip as VideoClip;
      for (final t in state!.tracks) {
        if (t.type != TrackType.audio) continue;
        for (final c in t.clips) {
          if (c is AudioClip &&
              c.sourcePath == v.sourcePath &&
              c.startTime == v.startTime &&
              c.endTime == v.endTime) {
            pairedAudioTrackId = t.id;
            pairedAudioDupe = AudioClip(
              id: '${c.id}_dup_${DateTime.now().microsecondsSinceEpoch}',
              startTime: dupe.startTime,
              duration: dupe.duration,
              sourcePath: c.sourcePath,
              trimStart: c.trimStart,
              trimEnd: c.trimEnd,
              originalDuration: c.originalDuration,
              volume: c.volume,
              fadeIn: c.fadeIn,
              fadeOut: c.fadeOut,
              name: c.name,
            );
            break;
          }
        }
        if (pairedAudioDupe != null) break;
      }
    }

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
        transitionIn: dupe.transitionIn,
        volume: dupe.volume,
        isMuted: dupe.isMuted,
        thumbnails: dupe.thumbnails,
        keyframeTracks: dupe.keyframeTracks,
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
        thumbnails: dupe.thumbnails,
      );
    } else {
      return; // Unknown type
    }

    final newTracks = state!.tracks.map((t) {
      if (t.id == track.id) {
        return t.copyWith(clips: [...t.clips, dupeWithNewId]);
      }
      if (pairedAudioTrackId != null &&
          pairedAudioDupe != null &&
          t.id == pairedAudioTrackId) {
        return t.copyWith(clips: [...t.clips, pairedAudioDupe]);
      }
      return t;
    }).toList();

    final proj = state!.copyWith(tracks: newTracks);
    state = proj.copyWith(totalDuration: proj.computeTotalDuration());
  }

  // ─── Export settings ──────────────────────────────────────────────────────

  void updateExportSettings(ExportSettings settings) {
    if (state == null) return;
    state = state!.copyWith(exportSettings: settings);
  }
}

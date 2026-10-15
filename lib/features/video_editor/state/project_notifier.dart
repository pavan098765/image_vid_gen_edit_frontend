// lib/features/video_editor/state/project_notifier.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart' hide ClipTransition;

import '../models/clip_model.dart';
import '../models/effect_model.dart';
import '../models/project_model.dart';
import '../services/audio_service.dart';
import '../services/native_compositor.dart';
import '../services/thumbnail_cache_service.dart';
import '../services/waveform_service.dart';

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

  void createFromScenePaths(
    List<String> paths, {
    Size resolution = const Size(1920, 1080),
    List<Duration>? durations,
  }) {
    if (paths.isEmpty) return;
    _undoStack.clear();
    _redoStack.clear();
    final projectId = 'studio_${DateTime.now().microsecondsSinceEpoch}';
    final clips = <Clip>[];
    var cursor = Duration.zero;
    for (var i = 0; i < paths.length; i++) {
      final dur = (durations != null &&
              i < durations.length &&
              durations[i] > Duration.zero)
          ? durations[i]
          : const Duration(seconds: 5);
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

  void replaceProject(VideoProject project) {
    _undoStack.clear();
    _redoStack.clear();
    state = project;
  }

  // ─── Track operations ─────────────────────────────────────────────────────

  void addImageSticker(
    String path, {
    Duration? startTime,
    Duration duration = const Duration(seconds: 3),
  }) {
    if (state == null) return;
    var stickerTrack = state!.stickerTracks.firstOrNull;
    if (stickerTrack == null) {
      stickerTrack = Track(
        id: '${state!.id}_sticker_${DateTime.now().microsecondsSinceEpoch}',
        type: TrackType.sticker,
        name: 'Sticker 1',
      );
      addTrack(stickerTrack);
    }
    final clip = StickerClip(
      id: '${state!.id}_stickerclip_${DateTime.now().microsecondsSinceEpoch}',
      startTime: startTime ?? Duration.zero,
      duration: duration,
      stickerData: path,
      isEmoji: false,
    );
    addClipToTrack(stickerTrack.id, clip);
  }

  void addTrack(Track track) {
    if (state == null) return;
    _pushUndo();
    state = state!.copyWith(
      tracks: [...state!.tracks, track],
      totalDuration: state!
          .copyWith(tracks: [...state!.tracks, track]).computeTotalDuration(),
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
  Future<void> splitVideoClipAt(String clipId, Duration splitPoint) async {
    if (state == null) return;
    final clip = state!.findClipById(clipId);
    if (clip == null || clip is! VideoClip) return;
    final track = state!.findTrackForClip(clipId);
    if (track == null) return;

    final relSplit = splitPoint - clip.startTime;
    if (relSplit <= Duration.zero || relSplit >= clip.duration) return;

    if (NativeCompositor.isSupported && clip.trimStart == Duration.zero) {
      final ok = await _nativeSplit(clip, track, relSplit);
      if (ok) return;
    }

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
      reverse: clip.reverse,
      rotateQuarterTurns: clip.rotateQuarterTurns,
      cropNorm: clip.cropNorm,
      look: clip.look,
      chroma: clip.chroma,
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

  Future<bool> _nativeSplit(
    VideoClip clip,
    Track track,
    Duration relSplit,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final startOut = '${dir.path}/split_${stamp}_a.mp4';
      final endOut = '${dir.path}/split_${stamp}_b.mp4';
      final paths = await ProVideoEditor.instance.splitVideo(
        SplitVideoModel(
          video: EditorVideo.file(File(clip.sourcePath)),
          splitPosition: relSplit,
          startOutputPath: startOut,
          endOutputPath: endOut,
        ),
      );
      if (paths.length < 2) return false;
      if (!File(paths[0]).existsSync() || !File(paths[1]).existsSync()) {
        return false;
      }
      _pushUndo();
      final clip1 = clip.copyWith(
        duration: relSplit,
        sourcePath: paths[0],
        trimStart: Duration.zero,
        trimEnd: relSplit,
        originalDuration: relSplit,
      );
      final clip2 = VideoClip(
        id: '${clip.id}_split_$stamp',
        startTime: clip.startTime + relSplit,
        duration: clip.duration - relSplit,
        sourcePath: paths[1],
        trimStart: Duration.zero,
        trimEnd: clip.duration - relSplit,
        originalDuration: clip.duration - relSplit,
        resolution: clip.resolution,
        speedEffect: clip.speedEffect,
        colorAdjustment: clip.colorAdjustment,
        transitionIn: const ClipTransition(),
        volume: clip.volume,
        isMuted: clip.isMuted,
        keyframeTracks: clip.keyframeTracks,
        reverse: clip.reverse,
        rotateQuarterTurns: clip.rotateQuarterTurns,
        cropNorm: clip.cropNorm,
        look: clip.look,
        chroma: clip.chroma,
      );
      final newClips = <Clip>[];
      for (final c in track.clips) {
        if (c.id == clip.id) {
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
          .map((t) => _splitPairedEmbeddedAudio(
                t,
                clip,
                clip.startTime + relSplit,
              ))
          .toList();
      final proj = state!.copyWith(tracks: tracks);
      state = proj.copyWith(totalDuration: proj.computeTotalDuration());
      return true;
    } catch (e) {
      debugPrint('Native split failed: $e');
      return false;
    }
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
        reverse: dupe.reverse,
        rotateQuarterTurns: dupe.rotateQuarterTurns,
        cropNorm: dupe.cropNorm,
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

  void reorderTracks(int oldIndex, int newIndex) {
    if (state == null) return;
    _pushUndo();
    final tracks = [...state!.tracks];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = tracks.removeAt(oldIndex);
    tracks.insert(newIndex, item);
    state = state!.copyWith(tracks: tracks);
  }

  void rippleDelete(String clipId) {
    if (state == null) return;
    final clip = state!.findClipById(clipId);
    final track = state!.findTrackForClip(clipId);
    if (clip == null || track == null) return;
    _pushUndo();
    final gap = clip.duration;
    final start = clip.startTime;
    final clips = track.clips.where((c) => c.id != clipId).map((c) {
      if (c.startTime >= start) {
        return c.copyWith(startTime: c.startTime - gap);
      }
      return c;
    }).toList();
    updateTrack(track.id, (t) => t.copyWith(clips: clips));
  }

  void closeGapOnTrack(String trackId) {
    if (state == null) return;
    final track = state!.tracks.where((t) => t.id == trackId).firstOrNull;
    if (track == null) return;
    _pushUndo();
    final sorted = [...track.clips]..sort((a, b) => a.startTime.compareTo(b.startTime));
    var cursor = Duration.zero;
    final packed = <Clip>[];
    for (final c in sorted) {
      packed.add(c.copyWith(startTime: cursor));
      cursor += c.duration;
    }
    final tracks = state!.tracks.map((t) {
      if (t.id == trackId) return t.copyWith(clips: packed);
      return t;
    }).toList();
    final proj = state!.copyWith(tracks: tracks);
    state = proj.copyWith(totalDuration: proj.computeTotalDuration());
  }

  Future<void> freezeFrame(String clipId, Duration at, Duration hold) async {
    if (state == null) return;
    final clip = state!.findClipById(clipId);
    if (clip is! VideoClip) return;
    await splitVideoClipAt(clipId, at);
    final left = state!.findClipById(clipId);
    if (left is! VideoClip) return;
    final track = state!.findTrackForClip(clipId);
    if (track == null) return;
    final freezeStart = left.endTime;
    final shifted = track.clips.map((c) {
      if (c.id == clipId) return c;
      if (c.startTime >= freezeStart) {
        return c.copyWith(startTime: c.startTime + hold);
      }
      return c;
    }).toList();
    updateTrack(track.id, (t) => t.copyWith(clips: shifted));
    addClipToTrack(
      track.id,
      VideoClip(
        id: '${clipId}_freeze_${at.inMilliseconds}',
        startTime: freezeStart,
        duration: hold,
        sourcePath: left.sourcePath,
        trimStart: left.trimEnd,
        trimEnd: left.trimEnd + const Duration(milliseconds: 40),
        originalDuration: left.originalDuration,
        resolution: left.resolution,
        volume: 0,
        isMuted: true,
        look: left.look,
        chroma: left.chroma,
      ),
    );
  }

  Future<void> detachAudio(String clipId) async {
    if (state == null) return;
    final clip = state!.findClipById(clipId);
    if (clip is! VideoClip) return;
    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/detach_${clip.id}.m4a';
    try {
      if (NativeCompositor.isSupported) {
        await ProVideoEditor.instance.extractAudioToFile(
          out,
          AudioExtractConfigs(video: EditorVideo.file(File(clip.sourcePath))),
        );
      } else {
        final session = await FFmpegKit.executeWithArguments(
          AudioService.extractAudioCommand(
            videoPath: clip.sourcePath,
            outputPath: out,
          ),
        );
        final code = await session.getReturnCode();
        if (!ReturnCode.isSuccess(code)) return;
      }
    } catch (e) {
      debugPrint('Detach audio failed: $e');
      return;
    }
    if (!File(out).existsSync()) return;
    final samples = await WaveformService.samplesForPath(out);
    updateClip(clipId, (c) => (c as VideoClip).copyWith(isMuted: true, volume: 0));
    var audioTrack = state!.audioTracks.firstOrNull;
    if (audioTrack == null) {
      audioTrack = Track(
        id: '${state!.id}_audio_detach',
        type: TrackType.audio,
        name: 'Audio',
      );
      state = state!.copyWith(tracks: [...state!.tracks, audioTrack]);
    }
    addClipToTrack(
      audioTrack.id,
      AudioClip(
        id: '${clip.id}_audio',
        startTime: clip.startTime,
        duration: clip.duration,
        sourcePath: out,
        trimStart: clip.trimStart,
        trimEnd: clip.trimEnd,
        originalDuration: clip.originalDuration,
        waveform: samples,
        name: 'Detached',
      ),
    );
  }
}

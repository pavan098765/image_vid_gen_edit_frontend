// lib/features/video_editor/models/project_model.dart

import 'dart:ui' show Size;

import 'clip_model.dart';

/// Type of a track in the project.
enum TrackType { video, audio, text, sticker, pip }

/// A single track containing clips of the same type.
class Track {
  final String id;
  final TrackType type;
  final String name;
  final List<Clip> clips;
  final bool isVisible;
  final bool isLocked;
  final bool isMuted;

  const Track({
    required this.id,
    required this.type,
    required this.name,
    this.clips = const [],
    this.isVisible = true,
    this.isLocked = false,
    this.isMuted = false,
  });

  Track copyWith({
    String? id,
    TrackType? type,
    String? name,
    List<Clip>? clips,
    bool? isVisible,
    bool? isLocked,
    bool? isMuted,
  }) {
    return Track(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      clips: clips ?? this.clips,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      isMuted: isMuted ?? this.isMuted,
    );
  }

  /// Total duration = end of the last clip.
  Duration get duration {
    if (clips.isEmpty) return Duration.zero;
    Duration longest = Duration.zero;
    for (final c in clips) {
      if (c.endTime > longest) longest = c.endTime;
    }
    return longest;
  }
}

/// Export quality preset.
enum ExportQuality {
  low480p,
  medium720p,
  high1080p,
  ultra4k,
}

extension ExportQualityX on ExportQuality {
  String get label {
    switch (this) {
      case ExportQuality.low480p:
        return '480p';
      case ExportQuality.medium720p:
        return '720p';
      case ExportQuality.high1080p:
        return '1080p';
      case ExportQuality.ultra4k:
        return '4K';
    }
  }

  int get height {
    switch (this) {
      case ExportQuality.low480p:
        return 480;
      case ExportQuality.medium720p:
        return 720;
      case ExportQuality.high1080p:
        return 1080;
      case ExportQuality.ultra4k:
        return 2160;
    }
  }

  int get bitrate {
    switch (this) {
      case ExportQuality.low480p:
        return 2500000;
      case ExportQuality.medium720p:
        return 5000000;
      case ExportQuality.high1080p:
        return 8000000;
      case ExportQuality.ultra4k:
        return 20000000;
    }
  }
}

/// Aspect ratio presets for export / canvas.
enum AspectRatioPreset {
  landscape16x9,
  portrait9x16,
  square1x1,
  classic4x3,
  cinema21x9,
  original,
}

extension AspectRatioPresetX on AspectRatioPreset {
  String get label {
    switch (this) {
      case AspectRatioPreset.landscape16x9:
        return '16:9';
      case AspectRatioPreset.portrait9x16:
        return '9:16';
      case AspectRatioPreset.square1x1:
        return '1:1';
      case AspectRatioPreset.classic4x3:
        return '4:3';
      case AspectRatioPreset.cinema21x9:
        return '21:9';
      case AspectRatioPreset.original:
        return 'Original';
    }
  }

  String get platformHint {
    switch (this) {
      case AspectRatioPreset.landscape16x9:
        return 'YouTube';
      case AspectRatioPreset.portrait9x16:
        return 'TikTok / Reels';
      case AspectRatioPreset.square1x1:
        return 'Instagram';
      case AspectRatioPreset.classic4x3:
        return 'Classic TV';
      case AspectRatioPreset.cinema21x9:
        return 'Cinema';
      case AspectRatioPreset.original:
        return 'As source';
    }
  }

  double? get ratio {
    switch (this) {
      case AspectRatioPreset.landscape16x9:
        return 16 / 9;
      case AspectRatioPreset.portrait9x16:
        return 9 / 16;
      case AspectRatioPreset.square1x1:
        return 1;
      case AspectRatioPreset.classic4x3:
        return 4 / 3;
      case AspectRatioPreset.cinema21x9:
        return 21 / 9;
      case AspectRatioPreset.original:
        return null; // use source aspect
    }
  }
}

/// Export settings.
class ExportSettings {
  final ExportQuality quality;
  final AspectRatioPreset aspectRatio;
  final int fps;
  final String format; // 'mp4' or 'mov'

  const ExportSettings({
    this.quality = ExportQuality.high1080p,
    this.aspectRatio = AspectRatioPreset.original,
    this.fps = 30,
    this.format = 'mp4',
  });

  ExportSettings copyWith({
    ExportQuality? quality,
    AspectRatioPreset? aspectRatio,
    int? fps,
    String? format,
  }) {
    return ExportSettings(
      quality: quality ?? this.quality,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      fps: fps ?? this.fps,
      format: format ?? this.format,
    );
  }
}

/// The full video editing project.
class VideoProject {
  final String id;
  final String name;
  final List<Track> tracks;
  final ExportSettings exportSettings;
  final Duration totalDuration;

  const VideoProject({
    required this.id,
    this.name = 'Untitled Project',
    this.tracks = const [],
    this.exportSettings = const ExportSettings(),
    this.totalDuration = Duration.zero,
  });

  VideoProject copyWith({
    String? id,
    String? name,
    List<Track>? tracks,
    ExportSettings? exportSettings,
    Duration? totalDuration,
  }) {
    return VideoProject(
      id: id ?? this.id,
      name: name ?? this.name,
      tracks: tracks ?? this.tracks,
      exportSettings: exportSettings ?? this.exportSettings,
      totalDuration: totalDuration ?? this.totalDuration,
    );
  }

  /// Compute total project duration from all tracks.
  Duration computeTotalDuration() {
    Duration max = Duration.zero;
    for (final t in tracks) {
      final td = t.duration;
      if (td > max) max = td;
    }
    return max;
  }

  /// Get all video tracks.
  List<Track> get videoTracks =>
      tracks.where((t) => t.type == TrackType.video).toList();

  /// Get all audio tracks.
  List<Track> get audioTracks =>
      tracks.where((t) => t.type == TrackType.audio).toList();

  /// Get all text tracks.
  List<Track> get textTracks =>
      tracks.where((t) => t.type == TrackType.text).toList();

  /// Get all sticker tracks.
  List<Track> get stickerTracks =>
      tracks.where((t) => t.type == TrackType.sticker).toList();

  /// Get all PiP tracks.
  List<Track> get pipTracks =>
      tracks.where((t) => t.type == TrackType.pip).toList();

  /// Find a clip by ID across all tracks.
  Clip? findClipById(String clipId) {
    for (final track in tracks) {
      for (final clip in track.clips) {
        if (clip.id == clipId) return clip;
      }
    }
    return null;
  }

  /// Find the track containing a clip.
  Track? findTrackForClip(String clipId) {
    for (final track in tracks) {
      if (track.clips.any((c) => c.id == clipId)) return track;
    }
    return null;
  }

  /// Get all selected clips.
  List<Clip> get selectedClips {
    final result = <Clip>[];
    for (final t in tracks) {
      for (final c in t.clips) {
        if (c.isSelected) result.add(c);
      }
    }
    return result;
  }

  /// Create an initial project from a single video file.
  factory VideoProject.fromVideo({
    required String projectId,
    required String videoPath,
    required Duration videoDuration,
    required double width,
    required double height,
  }) {
    final clipId = '${projectId}_clip_0';
    final trackId = '${projectId}_video_0';

    final videoClip = VideoClip(
      id: clipId,
      startTime: Duration.zero,
      duration: videoDuration,
      sourcePath: videoPath,
      trimStart: Duration.zero,
      trimEnd: videoDuration,
      originalDuration: videoDuration,
      resolution: Size(width, height),
    );

    final videoTrack = Track(
      id: trackId,
      type: TrackType.video,
      name: 'Video 1',
      clips: [videoClip],
    );

    return VideoProject(
      id: projectId,
      tracks: [videoTrack],
      totalDuration: videoDuration,
    );
  }
}

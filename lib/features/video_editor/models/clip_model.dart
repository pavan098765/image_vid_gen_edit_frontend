// lib/features/video_editor/models/clip_model.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'effect_model.dart';
import 'keyframe_model.dart';

/// Base type for all clips on a track.
enum ClipType { video, audio, text, sticker, pip }

/// Base class for all clips.
abstract class Clip {
  /// Unique clip ID.
  final String id;

  /// Type discriminator.
  ClipType get type;

  /// Start time of this clip on the global timeline.
  final Duration startTime;

  /// Duration this clip occupies on the timeline.
  final Duration duration;

  /// Whether this clip is currently selected.
  final bool isSelected;

  /// Keyframe animation tracks for this clip.
  final List<KeyframeTrack> keyframeTracks;

  const Clip({
    required this.id,
    required this.startTime,
    required this.duration,
    this.isSelected = false,
    this.keyframeTracks = const [],
  });

  /// The end time of this clip on the timeline.
  Duration get endTime => startTime + duration;

  /// Create a copy with changed properties.
  Clip copyWith({
    Duration? startTime,
    Duration? duration,
    bool? isSelected,
    List<KeyframeTrack>? keyframeTracks,
  });
}

// =============================================================================
//  VIDEO CLIP
// =============================================================================

class VideoClip extends Clip {
  @override
  ClipType get type => ClipType.video;

  /// Path to the source video file.
  final String sourcePath;

  /// Trim start within the source video.
  final Duration trimStart;

  /// Trim end within the source video.
  final Duration trimEnd;

  /// Original (untrimmed) duration of the source video.
  final Duration originalDuration;

  /// Resolution of the source video.
  final Size resolution;

  /// Speed effect.
  final SpeedEffect speedEffect;

  /// Color / filter adjustment.
  final ColorAdjustment colorAdjustment;

  /// Transition at the beginning of this clip (coming FROM previous clip).
  final ClipTransition transitionIn;

  /// Volume of the video's own audio track [0..1].
  final double volume;

  /// Whether the video audio is muted.
  final bool isMuted;

  /// Cached thumbnail images for the timeline strip.
  final List<Uint8List>? thumbnails;

  const VideoClip({
    required super.id,
    required super.startTime,
    required super.duration,
    super.isSelected,
    super.keyframeTracks,
    required this.sourcePath,
    required this.trimStart,
    required this.trimEnd,
    required this.originalDuration,
    this.resolution = const Size(1920, 1080),
    this.speedEffect = const SpeedEffect(),
    this.colorAdjustment = const ColorAdjustment(),
    this.transitionIn = const ClipTransition(),
    this.volume = 1.0,
    this.isMuted = false,
    this.thumbnails,
  });

  @override
  VideoClip copyWith({
    Duration? startTime,
    Duration? duration,
    bool? isSelected,
    List<KeyframeTrack>? keyframeTracks,
    String? sourcePath,
    Duration? trimStart,
    Duration? trimEnd,
    Duration? originalDuration,
    Size? resolution,
    SpeedEffect? speedEffect,
    ColorAdjustment? colorAdjustment,
    ClipTransition? transitionIn,
    double? volume,
    bool? isMuted,
    List<Uint8List>? thumbnails,
  }) {
    return VideoClip(
      id: id,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      isSelected: isSelected ?? this.isSelected,
      keyframeTracks: keyframeTracks ?? this.keyframeTracks,
      sourcePath: sourcePath ?? this.sourcePath,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      originalDuration: originalDuration ?? this.originalDuration,
      resolution: resolution ?? this.resolution,
      speedEffect: speedEffect ?? this.speedEffect,
      colorAdjustment: colorAdjustment ?? this.colorAdjustment,
      transitionIn: transitionIn ?? this.transitionIn,
      volume: volume ?? this.volume,
      isMuted: isMuted ?? this.isMuted,
      thumbnails: thumbnails ?? this.thumbnails,
    );
  }
}

// =============================================================================
//  AUDIO CLIP
// =============================================================================

class AudioClip extends Clip {
  @override
  ClipType get type => ClipType.audio;

  /// Path to the audio file.
  final String sourcePath;

  /// Trim start within the source.
  final Duration trimStart;

  /// Trim end within the source.
  final Duration trimEnd;

  /// Original duration of the source audio.
  final Duration originalDuration;

  /// Volume [0..1].
  final double volume;

  /// Fade in duration.
  final Duration fadeIn;

  /// Fade out duration.
  final Duration fadeOut;

  /// Cached waveform data (normalised 0..1 amplitude samples).
  final List<double>? waveform;

  /// Display name (file name).
  final String name;

  const AudioClip({
    required super.id,
    required super.startTime,
    required super.duration,
    super.isSelected,
    super.keyframeTracks,
    required this.sourcePath,
    required this.trimStart,
    required this.trimEnd,
    required this.originalDuration,
    this.volume = 1.0,
    this.fadeIn = Duration.zero,
    this.fadeOut = Duration.zero,
    this.waveform,
    this.name = '',
  });

  @override
  AudioClip copyWith({
    Duration? startTime,
    Duration? duration,
    bool? isSelected,
    List<KeyframeTrack>? keyframeTracks,
    String? sourcePath,
    Duration? trimStart,
    Duration? trimEnd,
    Duration? originalDuration,
    double? volume,
    Duration? fadeIn,
    Duration? fadeOut,
    List<double>? waveform,
    String? name,
  }) {
    return AudioClip(
      id: id,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      isSelected: isSelected ?? this.isSelected,
      keyframeTracks: keyframeTracks ?? this.keyframeTracks,
      sourcePath: sourcePath ?? this.sourcePath,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      originalDuration: originalDuration ?? this.originalDuration,
      volume: volume ?? this.volume,
      fadeIn: fadeIn ?? this.fadeIn,
      fadeOut: fadeOut ?? this.fadeOut,
      waveform: waveform ?? this.waveform,
      name: name ?? this.name,
    );
  }
}

// =============================================================================
//  TEXT CLIP
// =============================================================================

class TextClip extends Clip {
  @override
  ClipType get type => ClipType.text;

  /// The text content.
  final String text;

  /// Font family name.
  final String fontFamily;

  /// Font size.
  final double fontSize;

  /// Text colour.
  final Color color;

  /// Background colour (transparent = no bg).
  final Color backgroundColor;

  /// Bold / italic / underline.
  final bool isBold;
  final bool isItalic;

  /// Position on the preview as fraction [0..1, 0..1].
  final Offset position;

  /// Text alignment.
  final TextAlign textAlign;

  /// Text animation effect.
  final TextAnimation animation;

  /// Animation duration (in from start, out before end).
  final Duration animationDuration;

  const TextClip({
    required super.id,
    required super.startTime,
    required super.duration,
    super.isSelected,
    super.keyframeTracks,
    required this.text,
    this.fontFamily = 'Inter',
    this.fontSize = 28,
    this.color = Colors.white,
    this.backgroundColor = const Color(0x00000000),
    this.isBold = true,
    this.isItalic = false,
    this.position = const Offset(0.5, 0.5),
    this.textAlign = TextAlign.center,
    this.animation = TextAnimation.none,
    this.animationDuration = const Duration(milliseconds: 400),
  });

  @override
  TextClip copyWith({
    Duration? startTime,
    Duration? duration,
    bool? isSelected,
    List<KeyframeTrack>? keyframeTracks,
    String? text,
    String? fontFamily,
    double? fontSize,
    Color? color,
    Color? backgroundColor,
    bool? isBold,
    bool? isItalic,
    Offset? position,
    TextAlign? textAlign,
    TextAnimation? animation,
    Duration? animationDuration,
  }) {
    return TextClip(
      id: id,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      isSelected: isSelected ?? this.isSelected,
      keyframeTracks: keyframeTracks ?? this.keyframeTracks,
      text: text ?? this.text,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      isBold: isBold ?? this.isBold,
      isItalic: isItalic ?? this.isItalic,
      position: position ?? this.position,
      textAlign: textAlign ?? this.textAlign,
      animation: animation ?? this.animation,
      animationDuration: animationDuration ?? this.animationDuration,
    );
  }
}

// =============================================================================
//  STICKER CLIP
// =============================================================================

class StickerClip extends Clip {
  @override
  ClipType get type => ClipType.sticker;

  /// Emoji character or asset path.
  final String stickerData;

  /// True if [stickerData] is an emoji string, false if an asset path.
  final bool isEmoji;

  /// Position on the preview as fraction [0..1, 0..1].
  final Offset position;

  /// Scale factor.
  final double scale;

  /// Rotation in radians.
  final double rotation;

  const StickerClip({
    required super.id,
    required super.startTime,
    required super.duration,
    super.isSelected,
    super.keyframeTracks,
    required this.stickerData,
    this.isEmoji = true,
    this.position = const Offset(0.5, 0.5),
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  @override
  StickerClip copyWith({
    Duration? startTime,
    Duration? duration,
    bool? isSelected,
    List<KeyframeTrack>? keyframeTracks,
    String? stickerData,
    bool? isEmoji,
    Offset? position,
    double? scale,
    double? rotation,
  }) {
    return StickerClip(
      id: id,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      isSelected: isSelected ?? this.isSelected,
      keyframeTracks: keyframeTracks ?? this.keyframeTracks,
      stickerData: stickerData ?? this.stickerData,
      isEmoji: isEmoji ?? this.isEmoji,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }
}

// =============================================================================
//  PIP (PICTURE-IN-PICTURE) CLIP
// =============================================================================

class PipClip extends Clip {
  @override
  ClipType get type => ClipType.pip;

  /// Path to the overlay video file.
  final String sourcePath;

  /// Trim start within the overlay video.
  final Duration trimStart;

  /// Trim end within the overlay video.
  final Duration trimEnd;

  /// Original duration of the overlay video.
  final Duration originalDuration;

  /// Position of the PiP on the preview as fraction [0..1, 0..1].
  final Offset position;

  /// Scale (fraction of screen width).
  final double scale;

  /// Opacity [0..1].
  final double opacity;

  /// Corner radius.
  final double borderRadius;

  /// Volume of the PiP video audio [0..1].
  final double volume;

  /// Cached thumbnail for the timeline strip.
  final List<Uint8List>? thumbnails;

  const PipClip({
    required super.id,
    required super.startTime,
    required super.duration,
    super.isSelected,
    super.keyframeTracks,
    required this.sourcePath,
    required this.trimStart,
    required this.trimEnd,
    required this.originalDuration,
    this.position = const Offset(0.75, 0.75),
    this.scale = 0.3,
    this.opacity = 1.0,
    this.borderRadius = 8.0,
    this.volume = 0.0,
    this.thumbnails,
  });

  @override
  PipClip copyWith({
    Duration? startTime,
    Duration? duration,
    bool? isSelected,
    List<KeyframeTrack>? keyframeTracks,
    String? sourcePath,
    Duration? trimStart,
    Duration? trimEnd,
    Duration? originalDuration,
    Offset? position,
    double? scale,
    double? opacity,
    double? borderRadius,
    double? volume,
    List<Uint8List>? thumbnails,
  }) {
    return PipClip(
      id: id,
      startTime: startTime ?? this.startTime,
      duration: duration ?? this.duration,
      isSelected: isSelected ?? this.isSelected,
      keyframeTracks: keyframeTracks ?? this.keyframeTracks,
      sourcePath: sourcePath ?? this.sourcePath,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      originalDuration: originalDuration ?? this.originalDuration,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      opacity: opacity ?? this.opacity,
      borderRadius: borderRadius ?? this.borderRadius,
      volume: volume ?? this.volume,
      thumbnails: thumbnails ?? this.thumbnails,
    );
  }
}

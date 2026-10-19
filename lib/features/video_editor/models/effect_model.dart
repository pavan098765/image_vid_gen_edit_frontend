// lib/features/video_editor/models/effect_model.dart

/// Types of transitions between clips.
enum TransitionType {
  none,
  fade,
  dissolve,
  slideLeft,
  slideRight,
  slideUp,
  slideDown,
  zoomIn,
  zoomOut,
  wipeLeft,
  wipeRight,
  wipeUp,
  wipeDown,
}

extension TransitionTypeX on TransitionType {
  String get label {
    switch (this) {
      case TransitionType.none:
        return 'None';
      case TransitionType.fade:
        return 'Fade';
      case TransitionType.dissolve:
        return 'Dissolve';
      case TransitionType.slideLeft:
        return 'Slide Left';
      case TransitionType.slideRight:
        return 'Slide Right';
      case TransitionType.slideUp:
        return 'Slide Up';
      case TransitionType.slideDown:
        return 'Slide Down';
      case TransitionType.zoomIn:
        return 'Zoom In';
      case TransitionType.zoomOut:
        return 'Zoom Out';
      case TransitionType.wipeLeft:
        return 'Wipe Left';
      case TransitionType.wipeRight:
        return 'Wipe Right';
      case TransitionType.wipeUp:
        return 'Wipe Up';
      case TransitionType.wipeDown:
        return 'Wipe Down';
    }
  }

  String get icon {
    switch (this) {
      case TransitionType.none:
        return '✕';
      case TransitionType.fade:
        return '◐';
      case TransitionType.dissolve:
        return '◑';
      case TransitionType.slideLeft:
        return '←';
      case TransitionType.slideRight:
        return '→';
      case TransitionType.slideUp:
        return '↑';
      case TransitionType.slideDown:
        return '↓';
      case TransitionType.zoomIn:
        return '⊕';
      case TransitionType.zoomOut:
        return '⊖';
      case TransitionType.wipeLeft:
        return '⇐';
      case TransitionType.wipeRight:
        return '⇒';
      case TransitionType.wipeUp:
        return '⇑';
      case TransitionType.wipeDown:
        return '⇓';
    }
  }
}

/// A transition effect placed between two clips.
class ClipTransition {
  final TransitionType type;
  final Duration duration;

  const ClipTransition({
    this.type = TransitionType.none,
    this.duration = const Duration(milliseconds: 500),
  });

  ClipTransition copyWith({
    TransitionType? type,
    Duration? duration,
  }) {
    return ClipTransition(
      type: type ?? this.type,
      duration: duration ?? this.duration,
    );
  }

  bool get isNone => type == TransitionType.none;
}

/// Types of text animation.
enum TextAnimation {
  none,
  fadeIn,
  fadeOut,
  fadeInOut,
  typewriter,
  slideInLeft,
  slideInRight,
  slideInUp,
  slideInDown,
  scaleIn,
  bounceIn,
}

extension TextAnimationX on TextAnimation {
  String get label {
    switch (this) {
      case TextAnimation.none:
        return 'None';
      case TextAnimation.fadeIn:
        return 'Fade In';
      case TextAnimation.fadeOut:
        return 'Fade Out';
      case TextAnimation.fadeInOut:
        return 'Fade In/Out';
      case TextAnimation.typewriter:
        return 'Typewriter';
      case TextAnimation.slideInLeft:
        return 'Slide Left';
      case TextAnimation.slideInRight:
        return 'Slide Right';
      case TextAnimation.slideInUp:
        return 'Slide Up';
      case TextAnimation.slideInDown:
        return 'Slide Down';
      case TextAnimation.scaleIn:
        return 'Scale In';
      case TextAnimation.bounceIn:
        return 'Bounce In';
    }
  }
}

/// Speed change mode.
enum SpeedMode {
  /// Constant speed across the whole clip.
  constant,

  /// Ramp from one speed to another.
  ramp,

  /// Custom curve (list of speed points).
  curve,
}

/// Speed effect applied to a video clip.
class SpeedEffect {
  final SpeedMode mode;

  /// Used when mode == constant.
  final double speed;

  /// Used when mode == ramp (start speed, end speed).
  final double rampStart;
  final double rampEnd;

  /// Used when mode == curve. Each entry: (normalised position 0-1, speed multiplier).
  final List<SpeedPoint> curvePoints;

  const SpeedEffect({
    this.mode = SpeedMode.constant,
    this.speed = 1.0,
    this.rampStart = 1.0,
    this.rampEnd = 1.0,
    this.curvePoints = const [],
  });

  SpeedEffect copyWith({
    SpeedMode? mode,
    double? speed,
    double? rampStart,
    double? rampEnd,
    List<SpeedPoint>? curvePoints,
  }) {
    return SpeedEffect(
      mode: mode ?? this.mode,
      speed: speed ?? this.speed,
      rampStart: rampStart ?? this.rampStart,
      rampEnd: rampEnd ?? this.rampEnd,
      curvePoints: curvePoints ?? this.curvePoints,
    );
  }

  bool get isDefault => mode == SpeedMode.constant && speed == 1.0;
}

/// A point on a speed curve.
class SpeedPoint {
  /// Normalised position in the clip [0..1].
  final double position;

  /// Speed multiplier at this point.
  final double speed;

  const SpeedPoint({required this.position, required this.speed});
}

/// Colour adjustment values.
class ColorAdjustment {
  /// Brightness offset [-100..100], default 0.
  final double brightness;

  /// Contrast factor [0.5..2.0], default 1.0.
  final double contrast;

  /// Saturation factor [0.0..2.0], default 1.0.
  final double saturation;

  /// ID of a filter preset from [ColorMatrixPresets], or null.
  final String? filterPresetId;

  /// How strongly [filterPresetId] is mixed in. 1 is the full look, 0 is none.
  final double filterStrength;

  const ColorAdjustment({
    this.brightness = 0,
    this.contrast = 1.0,
    this.saturation = 1.0,
    this.filterPresetId,
    this.filterStrength = 1,
  });

  ColorAdjustment copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    String? filterPresetId,
    double? filterStrength,
  }) {
    return ColorAdjustment(
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      filterPresetId: filterPresetId ?? this.filterPresetId,
      filterStrength: filterStrength ?? this.filterStrength,
    );
  }

  bool get isDefault =>
      brightness == 0 &&
      contrast == 1.0 &&
      saturation == 1.0 &&
      filterPresetId == null;
}

/// Named look sent to pro_video_editor [VideoEffect].
enum VideoLook {
  clean,
  vhs,
  film,
  crt,
  grain,
  glitch,
}

extension VideoLookX on VideoLook {
  String get label {
    switch (this) {
      case VideoLook.clean:
        return 'Clean';
      case VideoLook.vhs:
        return 'VHS';
      case VideoLook.film:
        return 'Film';
      case VideoLook.crt:
        return 'CRT';
      case VideoLook.grain:
        return 'Grain';
      case VideoLook.glitch:
        return 'Glitch';
    }
  }
}

enum VoiceEq { none, warm, radio, voice }

extension VoiceEqX on VoiceEq {
  String get label {
    switch (this) {
      case VoiceEq.none:
        return 'Flat';
      case VoiceEq.warm:
        return 'Warm';
      case VoiceEq.radio:
        return 'Radio';
      case VoiceEq.voice:
        return 'Voice';
    }
  }
}

class ChromaSettings {
  final bool enabled;
  final int color;
  final double similarity;
  final double smoothness;
  final double spill;

  const ChromaSettings({
    this.enabled = false,
    this.color = 0xFF00B140,
    this.similarity = 0.20,
    this.smoothness = 0.08,
    this.spill = 0.5,
  });

  ChromaSettings copyWith({
    bool? enabled,
    int? color,
    double? similarity,
    double? smoothness,
    double? spill,
  }) {
    return ChromaSettings(
      enabled: enabled ?? this.enabled,
      color: color ?? this.color,
      similarity: similarity ?? this.similarity,
      smoothness: smoothness ?? this.smoothness,
      spill: spill ?? this.spill,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'color': color,
        'similarity': similarity,
        'smoothness': smoothness,
        'spill': spill,
      };

  factory ChromaSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ChromaSettings();
    return ChromaSettings(
      enabled: json['enabled'] == true,
      color: (json['color'] as num?)?.toInt() ?? 0xFF00B140,
      similarity: (json['similarity'] as num?)?.toDouble() ?? 0.20,
      smoothness: (json['smoothness'] as num?)?.toDouble() ?? 0.08,
      spill: (json['spill'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

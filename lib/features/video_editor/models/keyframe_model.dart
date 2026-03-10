// lib/features/video_editor/models/keyframe_model.dart

import 'dart:ui';

/// A single keyframe value at a point in time.
class Keyframe<T> {
  final Duration time;
  final T value;

  /// Easing curve between this keyframe and the next.
  final KeyframeEasing easing;

  const Keyframe({
    required this.time,
    required this.value,
    this.easing = KeyframeEasing.linear,
  });

  Keyframe<T> copyWith({
    Duration? time,
    T? value,
    KeyframeEasing? easing,
  }) {
    return Keyframe<T>(
      time: time ?? this.time,
      value: value ?? this.value,
      easing: easing ?? this.easing,
    );
  }
}

/// Easing types for keyframe interpolation.
enum KeyframeEasing {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  spring,
}

/// An animatable property tracked by keyframes.
enum KeyframeProperty {
  positionX,
  positionY,
  scale,
  rotation,
  opacity,
}

/// A set of keyframes for a single property on a clip/layer.
class KeyframeTrack {
  final String clipId;
  final KeyframeProperty property;
  final List<Keyframe<double>> keyframes;

  const KeyframeTrack({
    required this.clipId,
    required this.property,
    this.keyframes = const [],
  });

  KeyframeTrack copyWith({
    String? clipId,
    KeyframeProperty? property,
    List<Keyframe<double>>? keyframes,
  }) {
    return KeyframeTrack(
      clipId: clipId ?? this.clipId,
      property: property ?? this.property,
      keyframes: keyframes ?? this.keyframes,
    );
  }

  /// Add or update a keyframe at the given time.
  KeyframeTrack setKeyframe(Duration time, double value,
      {KeyframeEasing easing = KeyframeEasing.linear}) {
    final newKfs = List<Keyframe<double>>.from(keyframes);
    final idx = newKfs.indexWhere((k) => k.time == time);
    final kf = Keyframe(time: time, value: value, easing: easing);
    if (idx >= 0) {
      newKfs[idx] = kf;
    } else {
      newKfs.add(kf);
      newKfs.sort((a, b) => a.time.compareTo(b.time));
    }
    return copyWith(keyframes: newKfs);
  }

  /// Remove the keyframe at the given time.
  KeyframeTrack removeKeyframe(Duration time) {
    return copyWith(
      keyframes: keyframes.where((k) => k.time != time).toList(),
    );
  }

  /// Interpolate the value at a given time.
  double valueAt(Duration time) {
    if (keyframes.isEmpty) return _defaultForProperty(property);
    if (keyframes.length == 1) return keyframes.first.value;

    // Before first keyframe
    if (time <= keyframes.first.time) return keyframes.first.value;
    // After last keyframe
    if (time >= keyframes.last.time) return keyframes.last.value;

    // Find surrounding keyframes
    for (int i = 0; i < keyframes.length - 1; i++) {
      final a = keyframes[i];
      final b = keyframes[i + 1];
      if (time >= a.time && time <= b.time) {
        final totalMs = (b.time - a.time).inMilliseconds.toDouble();
        if (totalMs == 0) return a.value;
        final t = (time - a.time).inMilliseconds / totalMs;
        final easedT = _applyEasing(t, a.easing);
        return lerpDouble(a.value, b.value, easedT) ?? a.value;
      }
    }
    return keyframes.last.value;
  }

  static double _defaultForProperty(KeyframeProperty prop) {
    switch (prop) {
      case KeyframeProperty.positionX:
      case KeyframeProperty.positionY:
        return 0.0;
      case KeyframeProperty.scale:
        return 1.0;
      case KeyframeProperty.rotation:
        return 0.0;
      case KeyframeProperty.opacity:
        return 1.0;
    }
  }

  static double _applyEasing(double t, KeyframeEasing easing) {
    switch (easing) {
      case KeyframeEasing.linear:
        return t;
      case KeyframeEasing.easeIn:
        return t * t;
      case KeyframeEasing.easeOut:
        return 1 - (1 - t) * (1 - t);
      case KeyframeEasing.easeInOut:
        return t < 0.5 ? 2 * t * t : 1 - ((-2 * t + 2) * (-2 * t + 2)) / 2;
      case KeyframeEasing.spring:
        return 1 - ((1 - t) * (1 - t) * (1 - t));
    }
  }
}

// lib/features/video_editor/utils/speed_timeline_mapping.dart

import 'dart:math' as math;

import '../models/clip_model.dart';
import '../models/effect_model.dart';

const double _kMinSpeed = 0.25;
const int _kIntegrationSteps = 128;

/// Instantaneous playback multiplier v(u), u ∈ [0,1] along the clip timeline.
double speedAtNormalizedU(SpeedEffect e, double u) {
  final x = u.clamp(0.0, 1.0);
  switch (e.mode) {
    case SpeedMode.constant:
      return e.speed.clamp(_kMinSpeed, 5.0);
    case SpeedMode.ramp:
      return (e.rampStart + (e.rampEnd - e.rampStart) * x).clamp(_kMinSpeed, 5.0);
    case SpeedMode.curve:
      return _speedCurveAt(e.curvePoints, x).clamp(_kMinSpeed, 5.0);
  }
}

double _speedCurveAt(List<SpeedPoint> points, double u) {
  if (points.isEmpty) return 1.0;
  final sorted = List<SpeedPoint>.from(points)
    ..sort((a, b) => a.position.compareTo(b.position));
  if (u <= sorted.first.position) return sorted.first.speed;
  if (u >= sorted.last.position) return sorted.last.speed;
  for (int i = 0; i < sorted.length - 1; i++) {
    final a = sorted[i];
    final b = sorted[i + 1];
    if (u >= a.position && u <= b.position) {
      final span = b.position - a.position;
      if (span <= 1e-9) return a.speed;
      final t = (u - a.position) / span;
      return a.speed + (b.speed - a.speed) * t;
    }
  }
  return sorted.last.speed;
}

/// ∫₀¹ v(τ) dτ (τ normalized 0..1).
double integrateSpeedDenominator(SpeedEffect e) {
  return _integrateSpeedFromTo(e, 0.0, 1.0);
}

double _integrateSpeedFromTo(SpeedEffect e, double ua, double ub) {
  if (ub <= ua) return 0.0;
  const n = _kIntegrationSteps;
  double sum = 0.0;
  final h = (ub - ua) / n;
  for (int i = 0; i < n; i++) {
    final t0 = ua + h * i;
    final t1 = ua + h * (i + 1);
    final v0 = speedAtNormalizedU(e, t0);
    final v1 = speedAtNormalizedU(e, t1);
    sum += 0.5 * (v0 + v1) * h;
  }
  return sum;
}

/// r(u) = (∫₀^u v) / (∫₀¹ v) — maps normalized timeline position to normalized source consumption.
double rAtNormalizedU(SpeedEffect e, double u) {
  final den = integrateSpeedDenominator(e);
  if (den <= 1e-12) return u.clamp(0.0, 1.0);
  final numerator = _integrateSpeedFromTo(e, 0.0, u.clamp(0.0, 1.0));
  return (numerator / den).clamp(0.0, 1.0);
}

/// Source file position for a global [timelinePos] inside [clip].
Duration filePositionForTimelineInClip(VideoClip clip, Duration timelinePos) {
  final S = clip.trimEnd - clip.trimStart;
  if (S <= Duration.zero) return clip.trimStart;

  if (timelinePos <= clip.startTime) return clip.trimStart;
  if (timelinePos >= clip.endTime) return clip.trimEnd - const Duration(microseconds: 1);

  final rel = timelinePos - clip.startTime;
  final uDen = clip.duration.inMicroseconds;
  if (uDen <= 0) return clip.trimStart;
  final u = rel.inMicroseconds / uDen;

  final r = rAtNormalizedU(clip.speedEffect, clip.reverse ? 1.0 - u : u);
  final off = (S.inMicroseconds * r).round();
  return Duration(microseconds: clip.trimStart.inMicroseconds + off);
}

/// Inverse: timeline position for [filePos] within clip's trim (binary search on u).
Duration timelinePositionForFileInClip(
  VideoClip clip,
  Duration filePos,
  Duration hintTimeline,
) {
  final S = clip.trimEnd - clip.trimStart;
  if (S <= Duration.zero) return clip.startTime;

  if (filePos <= clip.trimStart) return clip.startTime;
  if (filePos >= clip.trimEnd) {
    return clip.endTime - const Duration(microseconds: 1);
  }

  final targetR = (filePos - clip.trimStart).inMicroseconds / S.inMicroseconds;
  final r = targetR.clamp(0.0, 1.0);

  // Monotone binary search u ∈ [0,1] with rAtNormalizedU(e,u) ≈ r
  double lo = 0.0;
  double hi = 1.0;
  for (int i = 0; i < 40; i++) {
    final mid = (lo + hi) / 2.0;
    final rm = rAtNormalizedU(clip.speedEffect, mid);
    if (rm < r) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  var u = (lo + hi) / 2.0;

  // Nudge toward hint if ambiguous (duplicate segments)
  if ((hintTimeline - clip.startTime).inMicroseconds >= 0 &&
      hintTimeline < clip.endTime) {
    final hintU = (hintTimeline - clip.startTime).inMicroseconds /
        math.max(1, clip.duration.inMicroseconds);
    if (hintU >= 0 && hintU <= 1) {
      final dr = (rAtNormalizedU(clip.speedEffect, hintU) - r).abs();
      if (dr < 0.02) u = hintU;
    }
  }

  final rel = Duration(
    microseconds: (clip.duration.inMicroseconds * u).round(),
  );
  return clip.startTime + rel;
}

/// v(u) at current playback for [timelinePos] on [clip].
double instantaneousPlaybackSpeed(VideoClip clip, Duration timelinePos) {
  if (timelinePos < clip.startTime || timelinePos >= clip.endTime) {
    return clip.speedEffect.speed.clamp(_kMinSpeed, 5.0);
  }
  final uDen = clip.duration.inMicroseconds;
  if (uDen <= 0) return clip.speedEffect.speed.clamp(_kMinSpeed, 5.0);
  final u = (timelinePos - clip.startTime).inMicroseconds / uDen;
  return speedAtNormalizedU(clip.speedEffect, u);
}

bool useUnifiedSpeedMapping(VideoClip clip) {
  final e = clip.speedEffect;
  if (e.mode != SpeedMode.constant) return true;
  return (e.speed - 1.0).abs() > 0.005;
}

/// Number of source sub-segments for ramp/curve export (FFmpeg trim + setpts per piece).
const int exportSegmentedSpeedSegments = 24;

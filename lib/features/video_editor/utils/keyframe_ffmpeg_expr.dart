// lib/features/video_editor/utils/keyframe_ffmpeg_expr.dart

import '../models/keyframe_model.dart';

/// Piecewise-linear interpolation of [t] (global seconds) from sorted knots.
/// Commas escaped for use inside FFmpeg `-vf` / `drawtext` argument lists.
String ffmpegPiecewiseLinearExpr(
  List<double> knotT,
  List<double> knotV,
  double fallback,
) {
  if (knotT.isEmpty) return _num(fallback);
  if (knotT.length == 1) return _num(knotV.first);
  assert(knotT.length == knotV.length);

  String inner = _num(knotV.last);
  for (int i = knotT.length - 2; i >= 0; i--) {
    final t0 = knotT[i];
    final t1 = knotT[i + 1];
    final v0 = knotV[i];
    final v1 = knotV[i + 1];
    final dt = t1 - t0;
    final lerp = dt.abs() < 1e-9
        ? _num(v0)
        : '(${_num(v0)}+(t-${_num(t0)})*${_num((v1 - v0) / dt)})';
    inner =
        'if(between(t\\,${_num(t0)}\\,${_num(t1)})\\,$lerp\\,$inner)';
  }
  var expr =
      'if(lt(t\\,${_num(knotT.first)})\\,${_num(knotV.first)}\\,$inner)';
  expr =
      'if(gt(t\\,${_num(knotT.last)})\\,${_num(knotV.last)}\\,$expr)';
  return expr;
}

String _num(double x) => x.toStringAsFixed(6);

/// Samples [track] on [clipStart]…[clipEnd] using [KeyframeTrack.valueAt]
/// with keyframe times relative to the clip (same as preview).
List<(double, double)> _sampleKnots(
  KeyframeTrack track,
  Duration clipStart,
  Duration clipEnd,
) {
  final times = <double>{};
  times.add(clipStart.inMicroseconds / 1e6);
  times.add(clipEnd.inMicroseconds / 1e6);
  for (final k in track.keyframes) {
    final abs = clipStart + k.time;
    if (abs >= clipStart && abs <= clipEnd) {
      times.add(abs.inMicroseconds / 1e6);
    }
  }
  final sorted = times.toList()..sort();
  final out = <(double, double)>[];
  for (final t in sorted) {
    final relUs = ((t * 1e6) - clipStart.inMicroseconds).round();
    final rel = Duration(microseconds: relUs);
    final v = track.valueAt(rel);
    out.add((t, v));
  }
  return out;
}

/// Scalar expression for a keyframe track, or [constant] if no track / empty.
String scalarExprForTrack({
  KeyframeTrack? track,
  required Duration clipStart,
  required Duration clipEnd,
  required double constant,
}) {
  if (track == null || track.keyframes.isEmpty) {
    return _num(constant);
  }
  final knots = _sampleKnots(track, clipStart, clipEnd);
  if (knots.isEmpty) {
    return _num(constant);
  }
  if (knots.length < 2) {
    return _num(knots.first.$2);
  }
  return ffmpegPiecewiseLinearExpr(
    knots.map((e) => e.$1).toList(),
    knots.map((e) => e.$2).toList(),
    constant,
  );
}

/// `W*(baseX+offsetExpr)-tw/2` with offset from keyframe position X (normalized).
String drawtextXExpr({
  required double baseX,
  required KeyframeTrack? offsetTrack,
  required Duration clipStart,
  required Duration clipEnd,
}) {
  final off = scalarExprForTrack(
    track: offsetTrack,
    clipStart: clipStart,
    clipEnd: clipEnd,
    constant: 0.0,
  );
  return 'W*(${_num(baseX)}+($off))-tw/2';
}

/// `H*(baseY+offsetExpr)-th/2`
String drawtextYExpr({
  required double baseY,
  required KeyframeTrack? offsetTrack,
  required Duration clipStart,
  required Duration clipEnd,
}) {
  final off = scalarExprForTrack(
    track: offsetTrack,
    clipStart: clipStart,
    clipEnd: clipEnd,
    constant: 0.0,
  );
  return 'H*(${_num(baseY)}+($off))-th/2';
}

/// Font size multiplier (1 = base font / sticker size).
String fontsizeScaleExpr({
  required double baseSize,
  required KeyframeTrack? scaleTrack,
  required Duration clipStart,
  required Duration clipEnd,
}) {
  final s = scalarExprForTrack(
    track: scaleTrack,
    clipStart: clipStart,
    clipEnd: clipEnd,
    constant: 1.0,
  );
  return '(${_num(baseSize)})*($s)';
}

/// Alpha 0..1 for `colorchannelmixer=aa=...` after drawtext on rgba, or overlay.
String opacityAlphaExpr({
  required KeyframeTrack? opacityTrack,
  required Duration clipStart,
  required Duration clipEnd,
}) {
  return scalarExprForTrack(
    track: opacityTrack,
    clipStart: clipStart,
    clipEnd: clipEnd,
    constant: 1.0,
  );
}

KeyframeTrack? trackFor(
  List<KeyframeTrack> tracks,
  KeyframeProperty prop,
) {
  for (final t in tracks) {
    if (t.property == prop) return t;
  }
  return null;
}

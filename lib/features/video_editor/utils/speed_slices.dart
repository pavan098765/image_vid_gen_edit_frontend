import '../models/clip_model.dart';
import '../models/effect_model.dart';
import 'speed_timeline_mapping.dart';

class SpeedSlice {
  final Duration fileStart;
  final Duration fileEnd;
  final Duration timelineDuration;
  final double speed;

  const SpeedSlice({
    required this.fileStart,
    required this.fileEnd,
    required this.timelineDuration,
    required this.speed,
  });
}

/// Split a ramp/curve clip into constant-speed slices whose timeline lengths
/// sum to the clip duration.
List<SpeedSlice> speedSlicesForClip(
  VideoClip clip, {
  int segments = exportSegmentedSpeedSegments,
}) {
  final e = clip.speedEffect;
  if (e.mode == SpeedMode.constant) {
    return [
      SpeedSlice(
        fileStart: clip.trimStart,
        fileEnd: clip.trimEnd,
        timelineDuration: clip.duration,
        speed: e.speed,
      ),
    ];
  }
  final S = clip.trimEnd - clip.trimStart;
  if (S <= Duration.zero || clip.duration <= Duration.zero) return const [];
  final n = segments < 2 ? 2 : segments;
  final out = <SpeedSlice>[];
  for (var i = 0; i < n; i++) {
    final u0 = i / n;
    final u1 = (i + 1) / n;
    final r0 = rAtNormalizedU(e, u0);
    final r1 = rAtNormalizedU(e, u1);
    final f0 = Duration(
      microseconds: clip.trimStart.inMicroseconds + (S.inMicroseconds * r0).round(),
    );
    final f1 = Duration(
      microseconds: clip.trimStart.inMicroseconds + (S.inMicroseconds * r1).round(),
    );
    if (f1 <= f0) continue;
    final dTus = (clip.duration.inMicroseconds * (u1 - u0)).round();
    if (dTus <= 0) continue;
    final dFus = (f1 - f0).inMicroseconds;
    final vEff = dFus / dTus;
    out.add(SpeedSlice(
      fileStart: f0,
      fileEnd: f1,
      timelineDuration: Duration(microseconds: dTus),
      speed: vEff.clamp(0.05, 20.0),
    ));
  }
  return out;
}

Duration sumSliceTimeline(List<SpeedSlice> slices) {
  var us = 0;
  for (final s in slices) {
    us += s.timelineDuration.inMicroseconds;
  }
  return Duration(microseconds: us);
}

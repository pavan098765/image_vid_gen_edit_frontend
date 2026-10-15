import 'package:pro_video_editor/pro_video_editor.dart' as pve;

import '../models/clip_model.dart';
import '../models/effect_model.dart';

List<pve.VideoEffect> looksForClips(List<VideoClip> clips) {
  final out = <pve.VideoEffect>[];
  for (final clip in clips) {
    final effect = lookToEffect(clip.look);
    if (effect == null) continue;
    out.add(effect.copyWith(
      startTime: clip.startTime,
      endTime: clip.endTime,
    ));
  }
  return out;
}

pve.VideoEffect? lookToEffect(VideoLook look) {
  switch (look) {
    case VideoLook.clean:
      return null;
    case VideoLook.vhs:
      return const pve.VideoEffect.vhs();
    case VideoLook.film:
      return const pve.VideoEffect.oldFilm();
    case VideoLook.crt:
      return const pve.VideoEffect.crt();
    case VideoLook.grain:
      return const pve.VideoEffect.filmGrain();
    case VideoLook.glitch:
      return const pve.VideoEffect.glitch();
  }
}

/// PVE flattens a transparent chroma key to black on the single-track path.
bool chromaRequiresComposition(bool chromaEnabled, {bool hasPip = false}) =>
    chromaEnabled || hasPip;

pve.AudioEqualizer? equalizerFor(VoiceEq eq) {
  switch (eq) {
    case VoiceEq.none:
      return null;
    case VoiceEq.warm:
      return const pve.AudioEqualizer(bands: [
        pve.AudioEqualizerBand(
            type: pve.AudioEqualizerBandType.peak, frequency: 120, gain: 3, q: 0.8),
        pve.AudioEqualizerBand(
            type: pve.AudioEqualizerBandType.peak, frequency: 4000, gain: -2, q: 1.0),
      ]);
    case VoiceEq.radio:
      return const pve.AudioEqualizer(bands: [
        pve.AudioEqualizerBand(
            type: pve.AudioEqualizerBandType.lowShelf, frequency: 80, gain: -6, q: 0.7),
        pve.AudioEqualizerBand(
            type: pve.AudioEqualizerBandType.peak, frequency: 1800, gain: 4, q: 1.2),
        pve.AudioEqualizerBand(
            type: pve.AudioEqualizerBandType.highShelf, frequency: 8000, gain: -4, q: 0.8),
      ]);
    case VoiceEq.voice:
      return const pve.AudioEqualizer(bands: [
        pve.AudioEqualizerBand(
            type: pve.AudioEqualizerBandType.peak, frequency: 250, gain: -2, q: 0.8),
        pve.AudioEqualizerBand(
            type: pve.AudioEqualizerBandType.peak, frequency: 3000, gain: 4, q: 1.0),
      ]);
  }
}

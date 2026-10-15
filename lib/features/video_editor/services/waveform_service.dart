import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

import 'native_compositor.dart';

/// Real waveform samples from the native package, with a quiet fallback.
class WaveformService {
  WaveformService._();

  static Future<List<double>> samplesForPath(
    String path, {
    int count = 80,
  }) async {
    if (NativeCompositor.isSupported) {
      try {
        final data = await ProVideoEditor.instance.getWaveform(
          WaveformConfigs(
            video: EditorVideo.file(File(path)),
            resolution: WaveformResolution.medium,
          ),
        );
        final raw = _extract(data);
        if (raw.isNotEmpty) return _resample(raw, count);
      } catch (e) {
        debugPrint('Waveform extract failed: $e');
      }
    }
    return List<double>.filled(count, 0.15);
  }

  static List<double> _extract(WaveformData data) {
    return data.leftChannel;
  }

  static List<double> _resample(List<double> source, int count) {
    if (source.isEmpty) return List<double>.filled(count, 0.15);
    if (source.length == count) return source;
    final out = <double>[];
    for (var i = 0; i < count; i++) {
      final t = i / math.max(1, count - 1);
      final idx = (t * (source.length - 1)).clamp(0, source.length - 1);
      final lo = idx.floor();
      final hi = idx.ceil().clamp(0, source.length - 1);
      final u = idx - lo;
      out.add(source[lo] * (1 - u) + source[hi] * u);
    }
    return out;
  }
}

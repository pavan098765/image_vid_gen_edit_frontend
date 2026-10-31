import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

const int kMusicVideoSampleRate = 44100;
const int kMusicVideoFps = 24;
const int kFeatureBins = 64;
const int kWaveformPoints = 48;

class FrameFeatures {
  final Float64List waveform;
  final Float64List bins;
  final double bass;
  final double mid;
  final double high;
  final double rms;

  const FrameFeatures({
    required this.waveform,
    required this.bins,
    required this.bass,
    required this.mid,
    required this.high,
    required this.rms,
  });

  static final FrameFeatures preview = _previewFeatures();

  static final FrameFeatures silent = FrameFeatures(
    waveform: Float64List(kWaveformPoints),
    bins: Float64List(kFeatureBins),
    bass: 0,
    mid: 0,
    high: 0,
    rms: 0,
  );
}

class AudioFeatureTable {
  final int sampleRate;
  final int fps;
  final List<FrameFeatures> frames;

  const AudioFeatureTable({
    required this.sampleRate,
    required this.fps,
    required this.frames,
  });

  double get durationSeconds => frames.isEmpty ? 0 : frames.length / fps;

  FrameFeatures atTime(double seconds) {
    if (frames.isEmpty) return FrameFeatures.silent;
    final index = (seconds * fps).floor();
    if (index < 0) return frames.first;
    if (index >= frames.length) return frames.last;
    return frames[index];
  }
}

FrameFeatures _previewFeatures() {
  final wave = Float64List(kWaveformPoints);
  final bins = Float64List(kFeatureBins);
  for (var i = 0; i < wave.length; i++) {
    final t = i / (wave.length - 1);
    wave[i] = 0.62 * math.sin(t * math.pi * 3.5) * math.sin(t * math.pi);
  }
  for (var i = 0; i < bins.length; i++) {
    final t = i / (bins.length - 1);
    final shape = 0.22 + 0.78 * math.sin(t * math.pi);
    final ripple = 0.55 + 0.45 * math.sin(i * 0.85).abs();
    final value = shape * ripple;
    bins[i] = value > 1 ? 1 : value;
  }
  return FrameFeatures(
    waveform: wave,
    bins: bins,
    bass: 0.74,
    mid: 0.5,
    high: 0.32,
    rms: 0.42,
  );
}

AudioFeatureTable audioFeatureTableFromPcm(
  Float64List samples, {
  int sampleRate = kMusicVideoSampleRate,
  int fps = kMusicVideoFps,
}) {
  if (samples.isEmpty || sampleRate < 1000 || fps < 1) {
    return AudioFeatureTable(sampleRate: sampleRate, fps: fps, frames: const []);
  }
  const fftSize = 2048;
  final hop = math.max(1, sampleRate ~/ fps);
  final fft = FFT(fftSize);
  final window = Float64List(fftSize);
  for (var i = 0; i < fftSize; i++) {
    window[i] = 0.5 * (1 - math.cos(2 * math.pi * i / (fftSize - 1)));
  }
  final edges = _logEdges(fftSize, sampleRate);
  final frameCount = math.max(1, (samples.length / hop).ceil());
  final frames = <FrameFeatures>[];
  final previous = Float64List(kFeatureBins);
  final chunk = Float64List(fftSize);

  for (var frame = 0; frame < frameCount; frame++) {
    final origin = frame * hop;
    var energy = 0.0;
    var counted = 0;
    for (var i = 0; i < fftSize; i++) {
      final index = origin + i - fftSize ~/ 2;
      final sample = index >= 0 && index < samples.length ? samples[index] : 0.0;
      chunk[i] = sample * window[i];
      if (index >= origin && index < origin + hop && index < samples.length) {
        energy += sample * sample;
        counted++;
      }
    }
    final rms = counted == 0 ? 0.0 : math.sqrt(energy / counted);
    final freq = fft.realFft(chunk).discardConjugates();
    final mags = freq.magnitudes();
    final bins = _bands(mags, edges, previous, fftSize);
    final waveform = Float64List(kWaveformPoints);
    for (var i = 0; i < kWaveformPoints; i++) {
      final index = origin + (i * hop ~/ kWaveformPoints);
      final sample = index >= 0 && index < samples.length ? samples[index] : 0.0;
      waveform[i] = (sample * 2.4).clamp(-1.0, 1.0).toDouble();
    }
    final bass = _average(bins, 0, 8);
    final mid = _average(bins, 8, 32);
    final high = _average(bins, 32, kFeatureBins);
    frames.add(FrameFeatures(
      waveform: waveform,
      bins: Float64List.fromList(bins),
      bass: bass,
      mid: mid,
      high: high,
      rms: rms.clamp(0.0, 1.0),
    ));
  }
  return AudioFeatureTable(sampleRate: sampleRate, fps: fps, frames: frames);
}

List<int> _logEdges(int fftSize, int sampleRate) {
  final edges = List<int>.filled(kFeatureBins + 1, 1);
  final nyquist = fftSize ~/ 2;
  for (var i = 0; i <= kFeatureBins; i++) {
    final hz = 40 * math.pow(16000 / 40, i / kFeatureBins);
    var bin = (hz * fftSize / sampleRate).round();
    if (bin < 1) bin = 1;
    if (bin > nyquist) bin = nyquist;
    edges[i] = bin;
  }
  for (var i = 1; i < edges.length; i++) {
    if (edges[i] <= edges[i - 1]) edges[i] = edges[i - 1] + 1;
    if (edges[i] > nyquist) edges[i] = nyquist;
  }
  return edges;
}

Float64List _bands(
  Float64List magnitudes,
  List<int> edges,
  Float64List previous,
  int fftSize,
) {
  final bins = Float64List(kFeatureBins);
  final limit = magnitudes.length;
  for (var i = 0; i < kFeatureBins; i++) {
    final start = edges[i].clamp(0, limit - 1);
    var end = edges[i + 1].clamp(start + 1, limit);
    var sum = 0.0;
    for (var bin = start; bin < end; bin++) {
      sum += magnitudes[bin];
    }
    final mag = sum / (end - start) / fftSize;
    final db = 20 * math.log(mag + 1e-8) / math.ln10;
    final norm = ((db + 55) / 55).clamp(0.0, 1.0);
    final smooth = previous[i] * 0.62 + norm * 0.38;
    previous[i] = smooth;
    bins[i] = smooth;
  }
  return bins;
}

double _average(Float64List bins, int start, int end) {
  final last = end.clamp(0, bins.length);
  final first = start.clamp(0, last);
  if (last <= first) return 0;
  var sum = 0.0;
  for (var i = first; i < last; i++) {
    sum += bins[i];
  }
  return sum / (last - first);
}

Float64List pcmFromFloat32Bytes(Uint8List bytes) {
  final aligned = Uint8List.fromList(bytes);
  final data = aligned.buffer.asByteData();
  final samples = Float64List(aligned.length ~/ 4);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = data.getFloat32(i * 4, Endian.little);
  }
  return samples;
}

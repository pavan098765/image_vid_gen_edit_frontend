// lib/features/video_editor/state/playback_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Playback state model.
class PlaybackState {
  final bool isPlaying;
  final Duration position;
  final Duration totalDuration;
  final bool isMuted;
  final double volume;
  final bool isLooping;

  const PlaybackState({
    this.isPlaying = false,
    this.position = Duration.zero,
    this.totalDuration = Duration.zero,
    this.isMuted = false,
    this.volume = 1.0,
    this.isLooping = false,
  });

  PlaybackState copyWith({
    bool? isPlaying,
    Duration? position,
    Duration? totalDuration,
    bool? isMuted,
    double? volume,
    bool? isLooping,
  }) {
    return PlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      totalDuration: totalDuration ?? this.totalDuration,
      isMuted: isMuted ?? this.isMuted,
      volume: volume ?? this.volume,
      isLooping: isLooping ?? this.isLooping,
    );
  }

  /// Fraction of progress [0..1].
  double get progress {
    if (totalDuration.inMilliseconds == 0) return 0;
    return position.inMilliseconds / totalDuration.inMilliseconds;
  }
}

/// Manages video playback state.
class PlaybackNotifier extends StateNotifier<PlaybackState> {
  PlaybackNotifier() : super(const PlaybackState());

  void play() => state = state.copyWith(isPlaying: true);
  void pause() => state = state.copyWith(isPlaying: false);
  void togglePlayPause() =>
      state = state.copyWith(isPlaying: !state.isPlaying);

  void seekTo(Duration pos) => state = state.copyWith(position: pos);

  void setPosition(Duration pos) => state = state.copyWith(position: pos);

  void setTotalDuration(Duration d) =>
      state = state.copyWith(totalDuration: d);

  void setMuted(bool muted) => state = state.copyWith(isMuted: muted);
  void toggleMute() => state = state.copyWith(isMuted: !state.isMuted);

  void setVolume(double v) => state = state.copyWith(volume: v.clamp(0, 1));

  void setLooping(bool loop) => state = state.copyWith(isLooping: loop);

  void reset() => state = const PlaybackState();
}

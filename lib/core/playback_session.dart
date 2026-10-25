import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

/// What the system media notification needs from the live player.
class PlaybackSnapshot {
  final String title;
  final String artist;
  final String? artUrl;
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool ready;
  final int index;
  final bool canSkip;

  const PlaybackSnapshot({
    required this.title,
    required this.artist,
    required this.position,
    required this.duration,
    required this.playing,
    required this.ready,
    required this.index,
    required this.canSkip,
    this.artUrl,
  });
}

/// System media controls for the song that keeps playing after the player closes.
class PlaybackSession {
  static PlaybackSnapshot? Function()? read;
  static Future<void> Function()? onPlay;
  static Future<void> Function()? onPause;
  static Future<void> Function()? onStop;
  static Future<void> Function(int delta)? onSkip;

  static _KalaPlaybackHandler? _handler;
  static bool closing = false;

  static Future<_KalaPlaybackHandler?>? _starting;

  static Future<void> prepare() {
    return _ensure();
  }

  static Future<_KalaPlaybackHandler?> _ensure() {
    return _starting ??= _start();
  }

  static Future<_KalaPlaybackHandler?> _start() async {
    try {
      final handler = await AudioService.init(
        builder: _KalaPlaybackHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.shambhutech.kalaai.playback',
          androidNotificationChannelName: 'Playback',
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'drawable/ic_notification',
        ),
      );
      _handler = handler;
      return handler;
    } catch (error, stack) {
      debugPrint('Playback notification unavailable: $error');
      debugPrint('$stack');
      return null;
    }
  }

  static Future<void> activate() async {
    final snapshot = read?.call();
    if (snapshot == null) return;
    final handler = await _ensure();
    handler?.publish(snapshot);
  }

  static Future<void> sync() async {
    final snapshot = read?.call();
    final handler = _handler;
    if (snapshot == null || handler == null) return;
    handler.publish(snapshot);
  }

  static Future<void> deactivate() async {
    closing = true;
    try {
      _handler?.publishIdle();
    } finally {
      closing = false;
    }
  }
}

class _KalaPlaybackHandler extends BaseAudioHandler {
  void publish(PlaybackSnapshot snapshot) {
    final art = _artUri(snapshot.artUrl);
    mediaItem.add(MediaItem(
      id: '${snapshot.index}:${snapshot.title}',
      title: snapshot.title,
      artist: snapshot.artist.isEmpty ? 'Kala AI' : snapshot.artist,
      artUri: art,
      duration: snapshot.duration > Duration.zero ? snapshot.duration : null,
    ));
    final controls = <MediaControl>[
      if (snapshot.canSkip) MediaControl.skipToPrevious,
      snapshot.playing ? MediaControl.pause : MediaControl.play,
      MediaControl.stop,
      if (snapshot.canSkip) MediaControl.skipToNext,
    ];
    playbackState.add(playbackState.value.copyWith(
      controls: controls,
      androidCompactActionIndices:
          snapshot.canSkip ? const [0, 1, 3] : const [0, 1],
      processingState: snapshot.ready
          ? AudioProcessingState.ready
          : AudioProcessingState.buffering,
      playing: snapshot.playing,
      updatePosition: snapshot.position,
      queueIndex: snapshot.index,
    ));
  }

  void publishIdle() {
    playbackState.add(playbackState.value.copyWith(
      controls: const [],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  Uri? _artUri(String? url) {
    if (url == null || url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return null;
    }
    return uri;
  }

  @override
  Future<void> play() async {
    await PlaybackSession.onPlay?.call();
  }

  @override
  Future<void> pause() async {
    await PlaybackSession.onPause?.call();
  }

  @override
  Future<void> stop() async {
    if (PlaybackSession.closing) return;
    await PlaybackSession.onStop?.call();
  }

  @override
  Future<void> skipToNext() async {
    await PlaybackSession.onSkip?.call(1);
  }

  @override
  Future<void> skipToPrevious() async {
    await PlaybackSession.onSkip?.call(-1);
  }
}

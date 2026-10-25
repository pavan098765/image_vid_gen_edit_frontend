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
  String? _publishedId;

  void publish(PlaybackSnapshot snapshot) {
    try {
      final art = _artUri(snapshot.artUrl);
      final id = '${snapshot.index}:${snapshot.title}';
      final item = MediaItem(
        id: id,
        title: snapshot.title,
        artist: snapshot.artist.isEmpty ? 'Kala AI' : snapshot.artist,
        artUri: art,
        duration: snapshot.duration > Duration.zero ? snapshot.duration : null,
      );
      if (_publishedId != id) {
        _publishedId = id;
        mediaItem.add(item);
        queue.add([item]);
      }
      final controls = <MediaControl>[
        if (snapshot.canSkip) MediaControl.skipToPrevious,
        snapshot.playing ? MediaControl.pause : MediaControl.play,
        MediaControl.stop,
        if (snapshot.canSkip) MediaControl.skipToNext,
      ];
      playbackState.add(playbackState.value.copyWith(
        controls: controls,
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
          MediaAction.seek,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
        },
        androidCompactActionIndices:
            snapshot.canSkip ? const [0, 1, 3] : const [0, 1],
        processingState: snapshot.ready
            ? AudioProcessingState.ready
            : AudioProcessingState.buffering,
        playing: snapshot.playing,
        // Speed lets the notification advance the clock between updates.
        // Position is sent only when playback actually jumps or pauses.
        speed: snapshot.playing ? 1.0 : 0.0,
        updatePosition: snapshot.position,
        queueIndex: snapshot.index,
      ));
    } catch (error, stack) {
      debugPrint('Playback notification update failed: $error');
      debugPrint('$stack');
    }
  }

  void publishIdle() {
    _publishedId = null;
    playbackState.add(playbackState.value.copyWith(
      controls: const [],
      processingState: AudioProcessingState.idle,
      playing: false,
      speed: 0.0,
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
    try {
      await PlaybackSession.onPlay?.call();
    } catch (error, stack) {
      debugPrint('Notification play failed: $error');
      debugPrint('$stack');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await PlaybackSession.onPause?.call();
    } catch (error, stack) {
      debugPrint('Notification pause failed: $error');
      debugPrint('$stack');
    }
  }

  @override
  Future<void> stop() async {
    if (PlaybackSession.closing) return;
    try {
      await PlaybackSession.onStop?.call();
    } catch (error, stack) {
      debugPrint('Notification stop failed: $error');
      debugPrint('$stack');
    }
  }

  @override
  Future<void> skipToNext() async {
    try {
      await PlaybackSession.onSkip?.call(1);
    } catch (error, stack) {
      debugPrint('Notification skip failed: $error');
      debugPrint('$stack');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      await PlaybackSession.onSkip?.call(-1);
    } catch (error, stack) {
      debugPrint('Notification skip failed: $error');
      debugPrint('$stack');
    }
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    switch (button) {
      case MediaButton.media:
        if (playbackState.value.playing) {
          await pause();
        } else {
          await play();
        }
        return;
      case MediaButton.next:
        await skipToNext();
        return;
      case MediaButton.previous:
        await skipToPrevious();
        return;
    }
  }
}

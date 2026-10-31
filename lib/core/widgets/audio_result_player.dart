import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/model_display_name.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/playback_session.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One playable audio result, with the words and style saved on the job.
class AudioTrackDetails {
  final String filePath;
  final String title;
  final String artist;
  final String style;
  final String? lyrics;
  final bool instrumental;
  final bool wordsAreScript;
  final DateTime? createdAt;
  final String? modelId;
  final int coverSeed;
  final String? coverUrl;
  final String? networkUrl;
  final Duration? knownDuration;
  final bool streaming;
  final String? sourceJobId;
  final String? sourceTrackId;

  const AudioTrackDetails({
    required this.filePath,
    required this.title,
    required this.artist,
    required this.style,
    required this.coverSeed,
    this.lyrics,
    this.instrumental = false,
    this.wordsAreScript = false,
    this.createdAt,
    this.modelId,
    this.coverUrl,
    this.networkUrl,
    this.knownDuration,
    this.streaming = false,
    this.sourceJobId,
    this.sourceTrackId,
  });

  factory AudioTrackDetails.fromPath(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final bare = name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ');
    return AudioTrackDetails(
      filePath: path,
      title: bare.trim().isEmpty ? 'Audio' : bare.trim(),
      artist: 'Kala AI',
      style: '',
      coverSeed: path.hashCode,
    );
  }

  factory AudioTrackDetails.fromJob(JobModel job) {
    final fromMusic = audioTracksFromJob(job);
    if (fromMusic.isNotEmpty) return fromMusic.first;
    final snap = job.settingsSnapshot ?? const <String, dynamic>{};
    final prompt = _clean(job.originalPrompt) ?? _clean(snap['prompt']);
    final lyrics = _clean(snap['lyrics']);
    final music = job.capabilityId == 'create_music' ||
        job.model.contains('music') ||
        job.model.contains('suno');
    final speech = job.capabilityId == 'create_speech' ||
        job.model.contains('tts') ||
        job.model.contains('voice');
    final vocalsOff = snap['vocals'] == false;
    return AudioTrackDetails(
      filePath: job.localFilePath ?? '',
      title: _displayTitle(job.title, prompt),
      artist: displayNameForModel(
        preferInternalModelId(snap['modelId']?.toString(), job.model),
      ),
      style: _clean(snap['style']) ?? prompt ?? '',
      lyrics: lyrics,
      instrumental: music && (vocalsOff || snap['instrumental'] == true),
      wordsAreScript: speech && !music,
      createdAt: job.createdAt,
      modelId: job.model,
      coverSeed: job.jobId.hashCode,
    );
  }

  factory AudioTrackDetails.fromMusicTrack(
    MusicTrack track, {
    required String jobId,
    String? artist,
    bool instrumental = false,
    DateTime? createdAt,
    String? modelId,
  }) {
    return AudioTrackDetails(
      filePath: '',
      title: track.title,
      artist: artist ?? 'Kala HitMaker',
      style: track.tags ?? '',
      lyrics: track.lyrics,
      instrumental: instrumental,
      createdAt: createdAt,
      modelId: modelId ?? kSunoV6ModelId,
      coverSeed: (track.id.isEmpty ? jobId : track.id).hashCode,
      coverUrl: track.coverUrl,
      networkUrl: track.playUrl,
      knownDuration: track.knownDuration,
      streaming: track.isStreaming,
      sourceJobId: jobId,
      sourceTrackId: track.id,
    );
  }

  AudioTrackDetails copyWith({
    String? filePath,
    String? title,
    String? lyrics,
    String? style,
    String? coverUrl,
    String? networkUrl,
    Duration? knownDuration,
    bool? streaming,
    bool clearKnownDuration = false,
  }) {
    return AudioTrackDetails(
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      artist: artist,
      style: style ?? this.style,
      lyrics: lyrics ?? this.lyrics,
      instrumental: instrumental,
      wordsAreScript: wordsAreScript,
      createdAt: createdAt,
      modelId: modelId,
      coverSeed: coverSeed,
      coverUrl: coverUrl ?? this.coverUrl,
      networkUrl: networkUrl ?? this.networkUrl,
      knownDuration: clearKnownDuration ? null : knownDuration ?? this.knownDuration,
      streaming: streaming ?? this.streaming,
      sourceJobId: sourceJobId,
      sourceTrackId: sourceTrackId,
    );
  }
}

List<AudioTrackDetails> audioTracksFromMusic(
  MusicResult music, {
  required String jobId,
  String? artist,
  DateTime? createdAt,
  String? modelId,
}) {
  final playable = [for (final track in music.tracks) if (track.isPlayable) track];
  return [
    for (var i = 0; i < playable.length; i++)
        AudioTrackDetails.fromMusicTrack(
          MusicTrack(
            id: playable[i].id,
            title: playable[i].title,
            lyrics: fullerLyrics(playable[i], music.lyrics),
            tags: playable[i].tags,
            duration: playable[i].duration,
            audioUrl: playable[i].streamsDuring(music.phase) ? null : playable[i].audioUrl,
            streamUrl: playable[i].streamUrl,
            coverUrl: _coverForTrack(playable[i], music.covers, i),
            downloadUrl: playable[i].streamsDuring(music.phase) ? null : playable[i].downloadUrl,
          ),
          jobId: jobId,
          artist: artist,
          instrumental: music.instrumental,
          createdAt: createdAt,
          modelId: modelId,
        ),
  ];
}

String? _coverForTrack(MusicTrack track, List<String> covers, int index) {
  final own = track.coverUrl;
  if (own != null && own.isNotEmpty) return own;
  if (index >= 0 && index < covers.length && covers[index].isNotEmpty) {
    return covers[index];
  }
  if (covers.isNotEmpty) return covers.first;
  return null;
}

List<AudioTrackDetails> audioTracksFromJob(JobModel job) {
  final snap = job.settingsSnapshot ?? const <String, dynamic>{};
  final prompt = _clean(job.originalPrompt) ?? _clean(snap['prompt']);
  final title = _displayTitle(job.title, prompt);
  final lyricsFallback = _clean(snap['lyrics']);
  final styleFallback = _clean(snap['style']) ?? prompt;
  final raw = job.music;
  if (raw == null) {
    return _audioFallbackFromJob(
      job,
      title: title,
      lyrics: lyricsFallback,
      style: styleFallback,
    );
  }
  final music = MusicResult.fromJson(raw);
  final tracks = audioTracksFromMusic(
    music,
    jobId: job.jobId,
    artist: displayNameForModel(
      preferInternalModelId(job.settingsSnapshot?['modelId']?.toString(), job.model),
    ),
    createdAt: job.createdAt,
    modelId: job.model,
  );
  final prepared = [
    for (final track in _attachSavedFile(job, tracks))
      track.copyWith(
        title: _songTitle(track.title, title),
        style: track.style.trim().isEmpty ? styleFallback : null,
        lyrics: (track.lyrics == null || track.lyrics!.trim().isEmpty)
            ? lyricsFallback
            : null,
      ),
  ];
  if (prepared.isNotEmpty) return prepared;
  return _audioFallbackFromJob(
    job,
    title: title,
    lyrics: lyricsFallback,
    style: styleFallback,
  );
}

/// A finished music job whose track list was never stored still has one file.
List<AudioTrackDetails> _audioFallbackFromJob(
  JobModel job, {
  required String title,
  String? lyrics,
  String? style,
}) {
  if (job.status != 'completed') return const [];
  final musicJob = job.isAudioOutput ||
      job.capabilityId == 'create_music' ||
      job.model == kSunoV6ModelId;
  if (!musicJob) return const [];
  final path = job.localFilePath;
  final localOk = path != null && path.isNotEmpty && File(path).existsSync();
  final url = job.downloadUrl;
  if (!localOk && (url == null || url.isEmpty)) return const [];
  return [
    AudioTrackDetails(
      filePath: localOk ? path : '',
      title: title,
      artist: displayNameForModel(
        preferInternalModelId(job.settingsSnapshot?['modelId']?.toString(), job.model),
      ),
      style: style ?? '',
      lyrics: lyrics,
      networkUrl: localOk ? null : url,
      createdAt: job.createdAt,
      modelId: job.model,
      coverSeed: job.jobId.hashCode,
      sourceJobId: job.jobId,
    ),
  ];
}

List<AudioTrackDetails> _attachSavedFile(
  JobModel job,
  List<AudioTrackDetails> tracks,
) {
  if (tracks.isEmpty) return tracks;
  final path = job.localFilePath;
  if (path == null || path.isEmpty || !File(path).existsSync()) return tracks;
  final lower = path.toLowerCase();
  final audio = job.isAudioOutput ||
      lower.endsWith('.mp3') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.aac') ||
      lower.endsWith('.ogg');
  if (!audio) return tracks;
  if (tracks.any((track) => track.filePath == path)) return tracks;
  // The saved job file is the first version. Every other version keeps its own URL.
  return [
    tracks.first.copyWith(filePath: path, streaming: false),
    ...tracks.skip(1),
  ];
}

String audioModelLabel(String modelId) {
  final name = displayNameForModel(modelId);
  if (name.isEmpty || name == 'unknown') return 'Kala AI';
  return name;
}

String? _clean(Object? raw) {
  if (raw is! String) return null;
  final text = raw.trim();
  return text.isEmpty ? null : text;
}

bool _isBareId(String value) {
  final text = value.trim();
  if (text.isEmpty ||
      text.toLowerCase() == 'untitled' ||
      text.toLowerCase() == 'audio') {
    return true;
  }
  final bare = text.replaceAll(
    RegExp(r'\.(mp3|wav|m4a|aac|flac|ogg)$', caseSensitive: false),
    '',
  );
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(bare);
}

String _songTitle(String title, String? fallback) {
  if (!_isBareId(title)) return title.trim();
  final next = fallback?.trim() ?? '';
  if (next.isNotEmpty && !_isBareId(next)) return next;
  return 'Untitled';
}

String _displayTitle(String title, String? prompt) {
  if (!_isBareId(title)) return title.trim();
  if (prompt == null) return 'Untitled';
  final line = prompt.split('\n').first.trim();
  if (line.isEmpty) return 'Untitled';
  if (line.length <= 48) return line;
  return '${line.substring(0, 48).trim()}…';
}

const _versionLetters = ['A', 'B', 'C', 'D'];

/// Version A, Version B, matching the chips on a HitMaker song card.
String audioVersionLabel(int index) {
  if (index >= 0 && index < _versionLetters.length) {
    return 'Version ${_versionLetters[index]}';
  }
  return 'Version ${index + 1}';
}

/// File name without an extension. Uses the title the player shows.
String savedAudioFileBaseName(JobModel job) {
  final tracks = audioTracksFromJob(job);
  if (tracks.isEmpty) {
    final snap = job.settingsSnapshot ?? const <String, dynamic>{};
    final prompt = _clean(job.originalPrompt) ?? _clean(snap['prompt']);
    final title = _displayTitle(job.title, prompt);
    return title.trim().isEmpty ? 'Audio' : title.trim();
  }
  final title = tracks.first.title.trim().isEmpty
      ? 'Audio'
      : tracks.first.title.trim();
  if (tracks.length == 1) return title;
  return '$title - ${audioVersionLabel(0)}';
}

class CoverPalette {
  final List<Color> inks;
  final Color glow;
  final Color warm;

  const CoverPalette({
    required this.inks,
    required this.glow,
    required this.warm,
  });

  static const List<CoverPalette> sets = [
    CoverPalette(
      inks: [
        Color(0xFFE23B3B),
        Color(0xFF2F6BFF),
        Color(0xFFF0A202),
        Color(0xFF7A3E9D),
        Color(0xFF1FA37A),
      ],
      glow: Color(0xFF7A3E9D),
      warm: Color(0xFFE07A3D),
    ),
    CoverPalette(
      inks: [
        Color(0xFF2457D6),
        Color(0xFFE4572E),
        Color(0xFF1B9AAA),
        Color(0xFFF4D35E),
        Color(0xFF7B2D8E),
      ],
      glow: Color(0xFF2457D6),
      warm: Color(0xFFE4572E),
    ),
    CoverPalette(
      inks: [
        Color(0xFF0E7C66),
        Color(0xFFF2A541),
        Color(0xFFD64550),
        Color(0xFF3D5AFE),
        Color(0xFF6A4C93),
      ],
      glow: Color(0xFF0E7C66),
      warm: Color(0xFFF2A541),
    ),
    CoverPalette(
      inks: [
        Color(0xFFC73E66),
        Color(0xFF3A86FF),
        Color(0xFFFFBE0B),
        Color(0xFF2EC4B6),
        Color(0xFF8338EC),
      ],
      glow: Color(0xFF8338EC),
      warm: Color(0xFFFFBE0B),
    ),
  ];

  static CoverPalette of(int seed) => sets[seed.abs() % sets.length];
}

typedef AudioRemixHandler = Future<void> Function(
  BuildContext context,
  AudioTrackDetails track,
);

/// Playback that stays alive after the player screen closes.
///
/// One [AudioPlayer] is reused for every song. A seek only moves the playhead.
class AudioNowPlaying extends ChangeNotifier {
  AudioNowPlaying() {
    player.playerStateStream.listen(_onState);
    player.positionStream.listen(_rememberPosition);
    player.durationStream.listen((_) {
      notifyListeners();
      _syncNotification(force: true);
    });
    player.errorStream.listen((cause) {
      debugPrint('Audio playback error: $cause');
    });
    unawaited(_prepareSession());
  }

  /// ExoPlayer's default back buffer is zero, so a backward seek has to reload
  /// audio it already played. That reload is what stops the song and leaves
  /// the controls on the loading spinner. Keep the played audio instead.
  final AudioPlayer player = AudioPlayer(
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        prioritizeTimeOverSizeThresholds: true,
        backBufferDuration: Duration(minutes: 30),
      ),
    ),
  );

  List<AudioTrackDetails> tracks = const [];
  int index = 0;
  bool sheetOpen = false;
  bool finished = false;
  bool userPaused = false;
  String? error;
  Future<void> Function(int delta)? onSkip;

  Future<void> _loadChain = Future<void>.value();
  int _loadGeneration = 0;
  String? _sourceKey;
  bool _seeking = false;
  bool _loading = false;
  bool _resuming = false;
  bool _advancing = false;
  bool _playWhenReady = false;
  bool _heardReady = false;
  int _seekTicket = 0;
  Duration? _pendingSeek;
  bool _lastPlaying = false;
  DateTime _lastSync = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastGoodPosition = Duration.zero;

  bool get seeking => _seeking;

  bool get advancing => _advancing;

  bool get hasAudio => tracks.isNotEmpty && _sourceKey != null;

  bool get playing => player.playing;

  bool get completed => player.processingState == ProcessingState.completed;

  /// The play button follows playback, not a seek rebuffer.
  /// A backward seek can report loading or idle for a moment. That is not a new song.
  bool get ready {
    if (_sourceKey == null) return false;
    switch (player.processingState) {
      case ProcessingState.buffering:
      case ProcessingState.ready:
      case ProcessingState.completed:
        return true;
      case ProcessingState.idle:
      case ProcessingState.loading:
        return _heardReady;
    }
  }

  Duration get position => player.position;

  Duration get reportedDuration => player.duration ?? Duration.zero;

  Duration get duration {
    final reported = reportedDuration;
    if (reported > Duration.zero) return reported;
    if (tracks.isEmpty) return Duration.zero;
    return tracks[index.clamp(0, tracks.length - 1)].knownDuration ??
        Duration.zero;
  }

  Future<void> _prepareSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (cause, stack) {
      debugPrint('Audio session failed: $cause');
      debugPrint('$stack');
    }
  }

  /// Only song loads are serialized. play() is not awaited: its future lasts
  /// until the song ends, and waiting on it blocks pause, seek, and notifications.
  Future<void> _chainLoad(Future<void> Function() action) {
    final run = _loadChain.then((_) => action());
    _loadChain = run.then<void>((_) {}, onError: (Object cause, StackTrace stack) {
      debugPrint('Audio load failed: $cause');
      debugPrint('$stack');
    });
    return run;
  }

  void _startPlayback() {
    final pending = player.play();
    unawaited(
      pending.then<void>((_) {}, onError: (Object cause, StackTrace stack) {
        debugPrint('Playback play failed: $cause');
        debugPrint('$stack');
        error = 'Could not play this audio';
        notifyListeners();
      }),
    );
  }

  void bindSkip(Future<void> Function(int delta)? skip) {
    onSkip = skip;
  }

  bool matches(List<AudioTrackDetails> next) {
    if (!hasAudio || tracks.length != next.length) return false;
    for (var i = 0; i < tracks.length; i++) {
      if (tracks[i].sourceJobId != next[i].sourceJobId) return false;
      if (tracks[i].sourceTrackId != next[i].sourceTrackId) return false;
      if (tracks[i].networkUrl != next[i].networkUrl) return false;
    }
    return true;
  }

  bool isCurrentSource(AudioTrackDetails track) {
    final key = _keyFor(track);
    return key != null && key == _sourceKey;
  }

  String? _keyFor(AudioTrackDetails track) {
    if (track.filePath.isNotEmpty && File(track.filePath).existsSync()) {
      return 'file:${track.filePath}';
    }
    final url = track.networkUrl;
    if (url != null && url.isNotEmpty) return 'url:$url';
    return null;
  }

  void _rememberPosition(Duration position) {
    if (_seeking || _loading) return;
    if (position > Duration.zero) _lastGoodPosition = position;
    // The notification moves its own thumb from the last position and speed.
    // Pushing the position on every tick pulls that thumb back while dragging.
  }

  void _onState(PlayerState state) {
    final processing = state.processingState;
    if (processing == ProcessingState.ready ||
        processing == ProcessingState.buffering ||
        processing == ProcessingState.completed) {
      _heardReady = true;
    }
    final ended = processing == ProcessingState.completed;
    // A seek can still be reported as completed until the new position lands.
    if (ended && !_seeking && !_loading && !_resuming) _handleCompleted();
    final playingNow = state.playing;
    notifyListeners();
    _syncNotification(force: playingNow != _lastPlaying || ended);
    _lastPlaying = playingNow;
  }

  void _handleCompleted() {
    if (_loading || _resuming || sheetOpen || userPaused || finished || _advancing) {
      return;
    }
    if (tracks.length > 1) {
      _advancing = true;
      unawaited(skip(1).whenComplete(() => _advancing = false));
      return;
    }
    finished = true;
    _syncNotification(force: true);
  }

  void _syncNotification({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastSync) < const Duration(seconds: 1)) {
      return;
    }
    _lastSync = now;
    unawaited(PlaybackSession.sync());
  }

  Future<void> load({
    required List<AudioTrackDetails> tracks,
    required int index,
    bool autoplay = false,
    Duration? startAt,
  }) {
    return _chainLoad(
      () => _loadNow(
        tracks: tracks,
        index: index,
        autoplay: autoplay,
        startAt: startAt,
      ),
    );
  }

  Future<void> _loadNow({
    required List<AudioTrackDetails> tracks,
    required int index,
    required bool autoplay,
    Duration? startAt,
  }) async {
    if (tracks.isEmpty || index < 0 || index >= tracks.length) return;
    final track = tracks[index];
    final key = _keyFor(track);
    this.tracks = List<AudioTrackDetails>.from(tracks);
    this.index = index;
    if (key == null) {
      error = 'Could not play this audio';
      notifyListeners();
      return;
    }
    final same = key == _sourceKey &&
        player.processingState != ProcessingState.idle;
    if (same) {
      error = null;
      if (startAt != null) await _seekNow(startAt);
      if (autoplay || _playWhenReady) {
        _playWhenReady = false;
        userPaused = false;
        finished = false;
        await _playFromCurrent();
      }
      notifyListeners();
      unawaited(PlaybackSession.activate());
      _syncNotification(force: true);
      return;
    }
    final generation = ++_loadGeneration;
    final replacing = key != _sourceKey;
    _sourceKey = key;
    // A new song is the only time the button should become a spinner.
    // Reloading the same song after a failed seek must keep the controls.
    if (replacing) _heardReady = false;
    finished = false;
    error = null;
    userPaused = !autoplay;
    _loading = true;
    notifyListeners();
    try {
      final start = startAt != null && startAt > Duration.zero ? startAt : null;
      if (key.startsWith('file:')) {
        await player.setFilePath(track.filePath, initialPosition: start);
      } else {
        final url = track.networkUrl;
        if (url == null || url.isEmpty) {
          throw StateError('no audio source');
        }
        await player.setUrl(url, initialPosition: start);
      }
      if (generation != _loadGeneration) return;
      if (player.position > Duration.zero) {
        _lastGoodPosition = player.position;
      }
      error = null;
    } catch (cause, stack) {
      debugPrint('Audio load failed: $cause');
      debugPrint('$stack');
      if (generation != _loadGeneration) return;
      _sourceKey = null;
      error = 'Could not play this audio';
    } finally {
      _loading = false;
    }
    notifyListeners();
    if (generation != _loadGeneration || _sourceKey == null) return;
    final pending = _pendingSeek;
    if (pending != null) {
      _pendingSeek = null;
      await _seekNow(pending);
    }
    if ((autoplay || _playWhenReady) && !userPaused) {
      _playWhenReady = false;
      finished = false;
      _startPlayback();
    } else {
      _playWhenReady = false;
    }
    unawaited(PlaybackSession.activate());
    _syncNotification(force: true);
  }

  Future<void> _playFromCurrent() async {
    _resuming = true;
    try {
      if (player.processingState == ProcessingState.completed) {
        await player.seek(Duration.zero);
      }
      finished = false;
      userPaused = false;
      _startPlayback();
    } finally {
      _resuming = false;
    }
    notifyListeners();
    _syncNotification(force: true);
  }

  Future<void> seekTo(Duration position) {
    return _seekNow(position);
  }

  Future<void> _seekNow(Duration position) async {
    if (_sourceKey == null) return;
    var target = position < Duration.zero ? Duration.zero : position;
    if (!_heardReady ||
        player.processingState == ProcessingState.loading ||
        player.processingState == ProcessingState.idle) {
      _pendingSeek = target;
      return;
    }
    final total = player.duration;
    final backward = target < player.position;
    if (total != null && total > Duration.zero && target >= total) {
      // Landing on the exact end marks the song completed and reloads it.
      final beforeEnd = total - const Duration(milliseconds: 300);
      target = beforeEnd > Duration.zero ? beforeEnd : Duration.zero;
    }
    _pendingSeek = null;
    _seeking = true;
    finished = false;
    _lastGoodPosition = target;
    final wasPlaying = player.playing || !userPaused;
    final ticket = ++_seekTicket;
    notifyListeners();
    _syncNotification(force: true);
    try {
      await player.seek(target).timeout(const Duration(seconds: 2));
    } catch (cause, stack) {
      debugPrint('Playback seek failed: $cause');
      debugPrint('$stack');
    }
    // A failed backward seek leaves ExoPlayer idle and silent. Load the same
    // song at the target instead of treating that as the end of the track.
    if (player.processingState == ProcessingState.idle && _sourceKey != null) {
      _seeking = false;
      await load(
        tracks: tracks,
        index: index,
        autoplay: wasPlaying,
        startAt: target,
      );
      return;
    }
    if (wasPlaying &&
        !player.playing &&
        player.processingState != ProcessingState.completed) {
      _startPlayback();
    }
    notifyListeners();
    _syncNotification(force: true);
    // Keep ignoring "completed" until a backward seek has settled.
    final settle = backward
        ? const Duration(milliseconds: 700)
        : const Duration(milliseconds: 300);
    Future<void>.delayed(settle, () {
      if (_seekTicket != ticket) return;
      _seeking = false;
      final length = player.duration;
      final atEnd = length != null &&
          length > Duration.zero &&
          target >= length - const Duration(milliseconds: 400);
      if (player.processingState == ProcessingState.completed && atEnd) {
        _handleCompleted();
      }
      notifyListeners();
    });
  }

  Future<void> resume() async {
    userPaused = false;
    finished = false;
    error = null;
    if (_loading) {
      _playWhenReady = true;
      notifyListeners();
      _syncNotification(force: true);
      return;
    }
    try {
      await _resumeNow();
    } catch (cause, stack) {
      debugPrint('Playback resume failed: $cause');
      debugPrint('$stack');
      error = 'Could not play this audio';
      notifyListeners();
    }
  }

  Future<void> _resumeNow() async {
    final state = player.processingState;
    if (_sourceKey == null || state == ProcessingState.idle) {
      if (tracks.isEmpty) return;
      final where = _lastGoodPosition;
      await load(
        tracks: tracks,
        index: index,
        autoplay: true,
        startAt: where > const Duration(seconds: 1) ? where : null,
      );
      return;
    }
    await _playFromCurrent();
  }

  Future<void> pause() async {
    _playWhenReady = false;
    userPaused = true;
    try {
      if (player.playing) await player.pause();
    } catch (cause, stack) {
      debugPrint('Playback pause failed: $cause');
      debugPrint('$stack');
    }
    notifyListeners();
    _syncNotification(force: true);
  }

  /// Moves to another version. The open player handles this itself.
  Future<void> skip(int delta) {
    final bound = onSkip;
    if (bound != null) return bound(delta);
    return _skipNow(delta);
  }

  Future<void> _skipNow(int delta) async {
    if (tracks.length < 2) {
      if (delta >= 0) return;
      final restart = player.playing ||
          player.processingState == ProcessingState.completed;
      await _seekNow(Duration.zero);
      if (!restart) return;
      userPaused = false;
      finished = false;
      await _playFromCurrent();
      return;
    }
    final count = tracks.length;
    final raw = (index + delta) % count;
    final next = raw < 0 ? raw + count : raw;
    await load(tracks: tracks, index: next, autoplay: true);
  }

  void replaceTracks(List<AudioTrackDetails> next, int nextIndex) {
    if (next.isEmpty) return;
    tracks = List<AudioTrackDetails>.from(next);
    index = nextIndex.clamp(0, next.length - 1);
    notifyListeners();
    _syncNotification(force: true);
  }

  void markSheet(bool open) {
    sheetOpen = open;
    notifyListeners();
  }

  Future<void> stop() {
    return _stopNow();
  }

  Future<void> _stopNow() async {
    _loadGeneration++;
    _playWhenReady = false;
    _heardReady = false;
    _seekTicket++;
    _sourceKey = null;
    tracks = const [];
    index = 0;
    sheetOpen = false;
    finished = false;
    userPaused = false;
    error = null;
    onSkip = null;
    _seeking = false;
    _loading = false;
    _resuming = false;
    _advancing = false;
    _pendingSeek = null;
    _lastGoodPosition = Duration.zero;
    notifyListeners();
    try {
      if (player.playing) await player.pause();
      await player.stop();
    } catch (cause, stack) {
      debugPrint('Playback stop failed: $cause');
      debugPrint('$stack');
    }
    await PlaybackSession.deactivate();
  }

  void bindPlaybackSession() {
    PlaybackSession.read = () {
      if (!hasAudio || tracks.isEmpty) return null;
      final currentIndex = index.clamp(0, tracks.length - 1);
      final track = tracks[currentIndex];
      return PlaybackSnapshot(
        title: track.title,
        artist: track.artist,
        artUrl: track.coverUrl,
        position: _seeking ? _lastGoodPosition : position,
        duration: duration > Duration.zero
            ? duration
            : (track.knownDuration ?? Duration.zero),
        playing: playing && !finished,
        ready: ready,
        index: currentIndex,
        canSkip: tracks.length > 1,
      );
    };
    PlaybackSession.onPlay = resume;
    PlaybackSession.onPause = pause;
    PlaybackSession.onStop = stop;
    PlaybackSession.onSkip = skip;
    PlaybackSession.onSeek = seekTo;
  }
}

final audioNowPlaying = AudioNowPlaying()..bindPlaybackSession();

/// Full-screen player for a finished audio job.
class AudioResultPlayer extends StatefulWidget {
  final List<AudioTrackDetails> tracks;
  final int initialIndex;
  final VoidCallback onClose;
  final AudioRemixHandler? onRemix;

  const AudioResultPlayer({
    super.key,
    required this.tracks,
    required this.onClose,
    this.initialIndex = 0,
    this.onRemix,
  });

  @override
  State<AudioResultPlayer> createState() => _AudioResultPlayerState();
}

class _AudioResultPlayerState extends State<AudioResultPlayer> {
  late List<AudioTrackDetails> _playlist;
  int _index = 0;
  int _loadGeneration = 0;
  bool _ready = false;
  bool _shuffle = false;
  bool _showReady = false;
  bool _styleExpanded = false;
  bool _wordsExpanded = false;
  bool _handledEnd = false;
  bool _continuePlayback = false;
  int _advanceTicket = 0;
  bool _opening = false;
  Duration? _scrub;
  bool _draggingScrub = false;
  bool _playing = false;
  bool _syncQueued = false;
  bool _adopting = false;
  bool _dismissed = false;
  bool _openedSheet = false;
  String? _error;
  String? _reaction;
  int _reactionToken = 0;
  final Random _random = Random();
  final Set<String> _reloadedUrls = {};
  late final PageController _coverController;

  AudioTrackDetails get _track => _playlist[_index];

  @override
  void initState() {
    super.initState();
    _playlist = _withSavedLibrary(
      _withJobVersions(List<AudioTrackDetails>.of(widget.tracks)),
    );
    final maxIndex = _playlist.length - 1;
    _index = widget.initialIndex.clamp(0, maxIndex < 0 ? 0 : maxIndex);
    _coverController = PageController(
      initialPage: _index,
      viewportFraction: 0.72,
    );
    jobListNotifier.addListener(_syncFromJobs);
    if (!audioNowPlaying.sheetOpen) {
      _openedSheet = true;
      audioNowPlaying.markSheet(true);
    }
    audioNowPlaying.addListener(_onSession);
    audioNowPlaying.bindSkip(_skipFromSession);
    final current = _playlist.isEmpty ? null : _playlist[_index];
    final resume = current != null &&
        audioNowPlaying.isCurrentSource(current) &&
        widget.initialIndex == audioNowPlaying.index;
    if (resume) {
      _ready = audioNowPlaying.ready;
      _playing = audioNowPlaying.playing;
      _error = audioNowPlaying.error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        audioNowPlaying.replaceTracks(
          List<AudioTrackDetails>.from(_playlist),
          _index,
        );
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_open(_index));
      });
    }
    _loadReaction();
  }

  void _syncFromJobs() {
    if (!mounted || _syncQueued) return;
    _syncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncQueued = false;
      if (mounted) unawaited(_applyJobTracks());
    });
  }

  AudioTrackDetails? _trackFromJobs(AudioTrackDetails current) {
    final jobId = current.sourceJobId;
    if (jobId == null || jobId.isEmpty) return null;
    JobModel? job;
    for (final item in jobListNotifier.value) {
      if (item.jobId == jobId) {
        job = item;
        break;
      }
    }
    if (job == null) return null;
    final tracks = audioTracksFromJob(job);
    for (final track in tracks) {
      if (current.sourceTrackId != null &&
          current.sourceTrackId!.isNotEmpty &&
          track.sourceTrackId == current.sourceTrackId) {
        return track;
      }
    }
    if (tracks.length == 1 && _playlist.length == 1) return tracks.first;
    return null;
  }

  bool _clockIsShort(Duration? known) {
    if (!audioNowPlaying.ready || !audioNowPlaying.isCurrentSource(_track)) {
      return false;
    }
    final full = known ?? Duration.zero;
    if (full < const Duration(seconds: 5)) return false;
    final reported = audioNowPlaying.reportedDuration;
    if (reported <= Duration.zero) return false;
    return reported + const Duration(seconds: 2) < full;
  }

  Future<void> _applyJobTracks() async {
    if (!mounted || _adopting || _opening) return;
    final before = _playlist.length;
    _playlist = _withSavedLibrary(_withJobVersions(_playlist));
    var changed = _playlist.length != before;
    var reloadIndex = -1;
    var announceReady = false;
    for (var i = 0; i < _playlist.length; i++) {
      final previous = _playlist[i];
      final fresh = _trackFromJobs(previous);
      if (fresh == null) continue;
      final kept = fresh.filePath.isEmpty && previous.filePath.isNotEmpty
          ? fresh.copyWith(filePath: previous.filePath)
          : fresh;
      final playingFile =
          kept.filePath.isNotEmpty && File(kept.filePath).existsSync();
      final urlChanged = kept.networkUrl != previous.networkUrl;
      final finished = previous.streaming && !kept.streaming;
      final durationGrew = (kept.knownDuration ?? Duration.zero) >
          (previous.knownDuration ?? Duration.zero) + const Duration(seconds: 1);
      final stuckOnStream = i == _index &&
          !playingFile &&
          !kept.streaming &&
          kept.networkUrl != null &&
          _clockIsShort(kept.knownDuration) &&
          _reloadedUrls.add(kept.networkUrl!);
      final reload = finished ||
          (!playingFile &&
              (urlChanged ||
                  (durationGrew && !kept.streaming) ||
                  stuckOnStream));
      final sameWords = kept.lyrics == previous.lyrics &&
          kept.coverUrl == previous.coverUrl &&
          kept.knownDuration == previous.knownDuration &&
          kept.streaming == previous.streaming &&
          kept.networkUrl == previous.networkUrl &&
          kept.filePath == previous.filePath;
      if (sameWords && !reload) continue;
      _playlist[i] = kept;
      changed = true;
      if (finished && i == _index && !_playing) announceReady = true;
      if (reload && i == _index && !audioNowPlaying.seeking) reloadIndex = i;
    }
    if (reloadIndex >= 0) {
      final keep = audioNowPlaying.position;
      final wasPlaying = _playing;
      _adopting = true;
      await _open(
        reloadIndex,
        announceReady: announceReady,
        autoplay: false,
        startAt: keep > const Duration(seconds: 1) ? keep : null,
      );
      _adopting = false;
      if (!mounted) return;
      if (wasPlaying && !announceReady && !audioNowPlaying.playing) {
        await audioNowPlaying.resume();
      }
      return;
    }
    if (changed && mounted) {
      setState(() {});
      audioNowPlaying.replaceTracks(
        List<AudioTrackDetails>.from(_playlist),
        _index,
      );
    }
  }

  Future<void> _loadReaction() async {
    final token = ++_reactionToken;
    final track = _track;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_reactionKey(track));
    if (!mounted || token != _reactionToken) return;
    setState(() => _reaction = value);
  }

  Future<void> _setReaction(String value) async {
    final track = _track;
    final next = _reaction == value ? null : value;
    setState(() => _reaction = next);
    final prefs = await SharedPreferences.getInstance();
    final key = _reactionKey(track);
    if (next == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, next);
    }
  }

  String _reactionKey(AudioTrackDetails track) {
    final job = track.sourceJobId ?? '';
    final id = track.sourceTrackId ?? '';
    if (job.isNotEmpty || id.isNotEmpty) return 'audio_mark_$job|$id';
    if (track.filePath.isNotEmpty) return 'audio_mark_${track.filePath.hashCode}';
    return 'audio_mark_${track.networkUrl.hashCode}';
  }

  Future<void> _open(
    int index, {
    bool announceReady = false,
    bool? autoplay,
    Duration? startAt,
  }) async {
    if (index < 0 || index >= _playlist.length) return;
    final generation = ++_loadGeneration;
    final track = _playlist[index];
    final changing = index != _index;
    final sameSource = audioNowPlaying.isCurrentSource(track);
    final keepPlaying =
        autoplay ?? (_continuePlayback || (_playing && !announceReady));
    _continuePlayback = false;
    if (mounted && (changing || announceReady || !sameSource)) {
      setState(() {
        _index = index;
        if (!sameSource) {
          _ready = false;
          _playing = false;
          _error = null;
        }
        _styleExpanded = false;
        _wordsExpanded = true;
        if (changing) _reaction = null;
        _showReady = announceReady && !track.streaming;
      });
      if (changing) unawaited(_loadReaction());
    }
    if (!mounted || generation != _loadGeneration) return;
    _opening = true;
    try {
      await audioNowPlaying.load(
        tracks: List<AudioTrackDetails>.from(_playlist),
        index: index,
        autoplay: keepPlaying,
        startAt: startAt,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _index = index;
        _ready = audioNowPlaying.ready;
        _playing = audioNowPlaying.playing;
        _error = audioNowPlaying.error;
        _handledEnd = audioNowPlaying.completed;
        _showReady = announceReady && !track.streaming && audioNowPlaying.ready;
      });
    } finally {
      _opening = false;
    }
  }

  void _onSession() {
    if (!mounted || _dismissed || _opening) return;
    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onSession());
      return;
    }
    final ended = audioNowPlaying.completed &&
        audioNowPlaying.sheetOpen &&
        !_handledEnd &&
        !audioNowPlaying.userPaused &&
        !audioNowPlaying.seeking &&
        !audioNowPlaying.advancing &&
        _playlist.length > 1;
    if (ended) {
      _handledEnd = true;
      _continuePlayback = true;
      final ticket = ++_advanceTicket;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _dismissed || ticket != _advanceTicket) return;
        _goNext();
      });
    }
    final playing = audioNowPlaying.playing;
    final ready = audioNowPlaying.ready;
    final failed = audioNowPlaying.error;
    if (playing == _playing &&
        ready == _ready &&
        failed == _error &&
        !(playing && _showReady)) {
      return;
    }
    setState(() {
      _playing = playing;
      _ready = ready;
      _error = failed;
      if (playing) _showReady = false;
    });
  }

  Future<void> _skipFromSession(int delta) async {
    if (delta < 0) {
      _goPrevious();
    } else {
      _goNext();
    }
  }

  void _releaseSheet() {
    audioNowPlaying.bindSkip(null);
    if (_playlist.isNotEmpty) {
      audioNowPlaying.replaceTracks(
        List<AudioTrackDetails>.from(_playlist),
        _index,
      );
    }
    if (_openedSheet) audioNowPlaying.markSheet(false);
  }

  void _dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    audioNowPlaying.removeListener(_onSession);
    _releaseSheet();
    widget.onClose();
  }

  @override
  void dispose() {
    jobListNotifier.removeListener(_syncFromJobs);
    audioNowPlaying.removeListener(_onSession);
    _coverController.dispose();
    if (!_dismissed) {
      _dismissed = true;
      _releaseSheet();
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!audioNowPlaying.ready || !audioNowPlaying.isCurrentSource(_track)) {
      await _open(_index);
      if (!audioNowPlaying.ready) return;
    }
    if (audioNowPlaying.playing) {
      await audioNowPlaying.pause();
    } else {
      _handledEnd = false;
      await audioNowPlaying.resume();
      if (_showReady && mounted) setState(() => _showReady = false);
    }
    HapticFeedback.lightImpact();
    if (mounted) setState(() {});
  }

  void _markContinue() {
    _continuePlayback = _playing ||
        (audioNowPlaying.completed && !audioNowPlaying.userPaused);
  }

  void _goPrevious() {
    _advanceTicket++;
    if (_playlist.length < 2) {
      final restart = audioNowPlaying.playing ||
          (audioNowPlaying.completed && !audioNowPlaying.userPaused);
      _handledEnd = false;
      unawaited(() async {
        await audioNowPlaying.seekTo(Duration.zero);
        if (restart) await audioNowPlaying.resume();
      }());
      return;
    }
    _markContinue();
    final next = (_index - 1) < 0 ? _playlist.length - 1 : _index - 1;
    unawaited(_slideTo(next));
  }

  void _goNext() {
    _advanceTicket++;
    if (_playlist.length < 2) return;
    _markContinue();
    if (_shuffle) {
      var next = _random.nextInt(_playlist.length);
      if (next == _index) next = (next + 1) % _playlist.length;
      unawaited(_slideTo(next));
      return;
    }
    unawaited(_slideTo((_index + 1) % _playlist.length));
  }

  Future<void> _slideTo(int index) async {
    if (index == _index || index < 0 || index >= _playlist.length) return;
    if (!_coverController.hasClients) {
      await _open(index);
      return;
    }
    final distance = (index - _index).abs();
    if (distance == 1) {
      await _coverController.animateToPage(
        index,
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _coverController.jumpToPage(index);
  }


  String _trackKey(AudioTrackDetails track) {
    final job = track.sourceJobId ?? '';
    final id = track.sourceTrackId ?? '';
    if (job.isNotEmpty && id.isNotEmpty) return '$job|$id';
    if (track.filePath.isNotEmpty) return 'file:${track.filePath}';
    final url = track.networkUrl;
    if (url != null && url.isNotEmpty) return 'url:$url';
    return 'title:$job|${track.title}';
  }

  List<AudioTrackDetails> _withJobVersions(List<AudioTrackDetails> tracks) {
    final out = List<AudioTrackDetails>.of(tracks);
    final seen = out.map(_trackKey).toSet();
    final jobIds = <String>{
      for (final track in out)
        if (track.sourceJobId != null && track.sourceJobId!.isNotEmpty)
          track.sourceJobId!,
    };
    for (final jobId in jobIds) {
      JobModel? job;
      for (final item in jobListNotifier.value) {
        if (item.jobId == jobId) {
          job = item;
          break;
        }
      }
      if (job == null) continue;
      for (final track in audioTracksFromJob(job)) {
        if (seen.add(_trackKey(track))) out.add(track);
      }
    }
    return out;
  }

  List<AudioTrackDetails> _withSavedLibrary(List<AudioTrackDetails> own) {
    final out = List<AudioTrackDetails>.of(own);
    final seen = out.map(_trackKey).toSet();
    final ownJobs = <String>{
      for (final track in out)
        if (track.sourceJobId != null && track.sourceJobId!.isNotEmpty)
          track.sourceJobId!,
    };
    final ownFiles = <String>{
      for (final track in out)
        if (track.filePath.isNotEmpty) track.filePath,
    };
    for (final job in jobListNotifier.value) {
      if (ownJobs.contains(job.jobId)) continue;
      final path = job.localFilePath;
      if (path == null || path.isEmpty || !File(path).existsSync()) continue;
      if (!job.isAudioOutput && job.music == null) continue;
      final tracks = audioTracksFromJob(job);
      final rows = tracks.isEmpty ? [AudioTrackDetails.fromJob(job)] : tracks;
      for (final track in rows) {
        if (track.filePath.isNotEmpty && ownFiles.contains(track.filePath)) {
          continue;
        }
        if (seen.add(_trackKey(track))) out.add(track);
      }
    }
    return out;
  }

  JobModel? _sourceJob(AudioTrackDetails track) {
    final id = track.sourceJobId;
    if (id == null || id.isEmpty) return null;
    for (final job in jobListNotifier.value) {
      if (job.jobId == id) return job;
    }
    return null;
  }

  String _visibleTitle(AudioTrackDetails track) {
    final job = _sourceJob(track);
    if (job != null) return _songTitle(track.title, _displayTitle(job.title, job.originalPrompt));
    return _songTitle(track.title, null);
  }

  String _visibleArtist(AudioTrackDetails track) {
    final job = _sourceJob(track);
    if (job == null) return track.artist;
    return displayNameForModel(
      preferInternalModelId(job.settingsSnapshot?['modelId']?.toString(), job.model),
    );
  }

  String _resolvedStyle(AudioTrackDetails track) {
    if (track.style.trim().isNotEmpty) return track.style;
    final job = _sourceJob(track);
    if (job == null) return '';
    final snap = job.settingsSnapshot ?? const <String, dynamic>{};
    return _clean(snap['style']) ??
        _clean(job.originalPrompt) ??
        _clean(snap['prompt']) ??
        '';
  }

  String? _resolvedLyrics(AudioTrackDetails track) {
    final own = track.lyrics?.trim();
    if (own != null && own.isNotEmpty) return track.lyrics;
    final job = _sourceJob(track);
    if (job == null) return track.lyrics;
    final snap = job.settingsSnapshot ?? const <String, dynamic>{};
    final model = snap['modelId']?.toString();
    final hitMaker = model == kSunoV6ModelId || job.model == kSunoV6ModelId;
    final music = job.music;
    if (music != null) {
      final result = MusicResult.fromJson(music);
      // Easy mode sings the words that come back on the clip, not the draft.
      if (hitMaker && result.easy && result.isComplete) return null;
      final text = result.lyrics.isEmpty ? null : result.lyrics.first.text;
      final kept = _clean(text);
      if (kept != null) return kept;
    }
    return _clean(snap['lyrics']) ?? track.lyrics;
  }

  String _exportBaseName(AudioTrackDetails track) {
    final title = _visibleTitle(track);
    final jobId = track.sourceJobId;
    if (jobId == null || jobId.isEmpty) return title;
    final siblings = [
      for (final item in _playlist)
        if (item.sourceJobId == jobId) item,
    ];
    if (siblings.length <= 1) return title;
    var index = -1;
    final trackId = track.sourceTrackId;
    if (trackId != null && trackId.isNotEmpty) {
      index = siblings.indexWhere((item) => item.sourceTrackId == trackId);
    }
    if (index < 0) index = siblings.indexOf(track);
    if (index < 0) index = 0;
    return '$title - ${audioVersionLabel(index)}';
  }

  String _shareFileName(String base, String path) {
    final ext = path.split('.').last.toLowerCase();
    const known = {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'};
    final suffix = known.contains(ext) ? ext : 'mp3';
    final clean = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return '${clean.isEmpty ? 'Audio' : clean}.$suffix';
  }

  String _shareMime(String path) {
    switch (path.split('.').last.toLowerCase()) {
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      default:
        return 'audio/mpeg';
    }
  }

  Future<void> _rememberSharedFile(String path) async {
    final jobId = _track.sourceJobId;
    if (jobId == null || jobId.isEmpty) return;
    final siblings = [
      for (final item in _playlist)
        if (item.sourceJobId == jobId) item,
    ];
    var index = -1;
    final trackId = _track.sourceTrackId;
    if (trackId != null && trackId.isNotEmpty) {
      index = siblings.indexWhere((item) => item.sourceTrackId == trackId);
    }
    if (siblings.length > 1 && index != 0) return;
    final jobs = List<JobModel>.from(jobListNotifier.value);
    final idx = jobs.indexWhere((job) => job.jobId == jobId);
    if (idx == -1) return;
    final job = jobs[idx];
    if (job.localFilePath == path) return;
    job.localFilePath = path;
    job.autoDownloaded = true;
    jobs[idx] = job;
    jobListNotifier.value = jobs;
    await saveJobsToPrefs();
  }

  Future<void> _shareTrack() async {
    final title = _visibleTitle(_track);
    final base = _exportBaseName(_track);
    var path = _track.filePath;
    if (path.isEmpty || !File(path).existsSync()) {
      final url = _track.networkUrl;
      if (url == null || url.isEmpty) {
        _toast('Nothing to share yet');
        return;
      }
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode != 200 || !mounted) {
          _toast('Could not share this song');
          return;
        }
        final saved = await FileService.saveFile(
          context,
          response.bodyBytes,
          extension: 'mp3',
          customFileName: base,
          showPreview: false,
          jobId: _track.sourceJobId,
        );
        if (saved != null && File(saved).existsSync()) {
          path = saved;
          await _rememberSharedFile(saved);
        } else {
          final dir = await getTemporaryDirectory();
          final file = File('${dir.path}/${_shareFileName(base, 'song.mp3')}');
          await file.writeAsBytes(response.bodyBytes, flush: true);
          path = file.path;
        }
      } catch (_) {
        if (mounted) _toast('Could not share this song');
        return;
      }
    }
    if (!mounted) return;
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await Share.shareXFiles(
      [
        XFile(
          path,
          name: _shareFileName(base, path),
          mimeType: _shareMime(path),
        ),
      ],
      text: title,
      sharePositionOrigin: origin,
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _previewSeek(double fraction, Duration total) {
    if (total <= Duration.zero) return;
    final next = Duration(
      milliseconds: (total.inMilliseconds * fraction).round(),
    );
    if (_scrub == next) return;
    setState(() => _scrub = next);
  }

  void _commitSeek() {
    final target = _scrub;
    _draggingScrub = false;
    if (mounted) {
      setState(() => _scrub = null);
    } else {
      _scrub = null;
    }
    if (target == null) return;
    unawaited(audioNowPlaying.seekTo(target).then((_) {
      if (!mounted || audioNowPlaying.completed) return;
      _handledEnd = false;
    }));
  }

  void _cancelScrub() {
    if (_draggingScrub) return;
    if (_scrub == null) return;
    setState(() => _scrub = null);
  }

  Future<void> _remix() async {
    final handler = widget.onRemix;
    if (handler == null) return;
    final track = _track;
    final navigator = Navigator.of(context);
    navigator.pop();
    final host = navigator.context;
    await Future<void>.delayed(Duration.zero);
    if (!host.mounted) return;
    await handler(host, track);
  }

  Future<void> _copy(String label, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $label'), behavior: SnackBarBehavior.floating),
    );
  }

  void _showQueue() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1224),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _playlist.length,
            itemBuilder: (context, index) {
              final track = _playlist[index];
              final selected = index == _index;
              return ListTile(
                leading: _ScribbleCover(
                  seed: track.coverSeed,
                  size: 44,
                  imageUrl: track.coverUrl,
                ),
                title: Text(
                  _visibleTitle(track),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _visibleArtist(track),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
                trailing: selected
                    ? const Icon(Icons.graphic_eq_rounded, color: Colors.white)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_slideTo(index));
                },
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = CoverPalette.of(_track.coverSeed);
    final playing = _playing;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _dismiss();
      },
      child: Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFF120C16))),
          Positioned.fill(
            child: BacklitWash(
              glow: palette.glow,
              warm: palette.warm,
              forceDark: true,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: _dismiss,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white, size: 32),
                  ),
                ),
                if (_showReady) _readyBanner(playing),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    children: [
                      _coverRow(),
                      const SizedBox(height: 22),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _visibleTitle(_track),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          if (_track.streaming) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Streaming',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _visibleArtist(_track),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _iconAction(
                            icon: Icons.ios_share_rounded,
                            tooltip: 'Share',
                            onPressed: () {
                              unawaited(_shareTrack());
                            },
                          ),
                          const SizedBox(width: 8),
                          _iconAction(
                            icon: Icons.more_horiz_rounded,
                            tooltip: 'More',
                            onPressed: _more,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pill(
                            icon: _reaction == 'like'
                                ? Icons.thumb_up_alt
                                : Icons.thumb_up_alt_outlined,
                            selected: _reaction == 'like',
                            onTap: () => _setReaction('like'),
                            tooltip: 'Like',
                          ),
                          _pill(
                            icon: _reaction == 'dislike'
                                ? Icons.thumb_down_alt
                                : Icons.thumb_down_alt_outlined,
                            selected: _reaction == 'dislike',
                            onTap: () => _setReaction('dislike'),
                            tooltip: 'Dislike',
                          ),
                          if (widget.onRemix != null)
                            _pill(
                              icon: Icons.refresh_rounded,
                              label: 'Remix',
                              onTap: _remix,
                              tooltip: 'Remix in Music',
                            ),
                          if (_playlist.isNotEmpty)
                            _pill(
                              icon: Icons.queue_music_rounded,
                              label: 'Playlist',
                              onTap: _showQueue,
                              tooltip: 'Playlist',
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AudioPlayClock(
                        source: audioNowPlaying,
                        readPosition: () => audioNowPlaying.isCurrentSource(_track)
                            ? audioNowPlaying.position
                            : Duration.zero,
                        readDuration: () => audioNowPlaying.isCurrentSource(_track)
                            ? audioNowPlaying.reportedDuration
                            : Duration.zero,
                        knownDuration: _track.knownDuration ?? Duration.zero,
                        builder: (context, position, total) =>
                            _seekRow(_scrub ?? position, total),
                      ),
                      const SizedBox(height: 8),
                      _transport(playing),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _infoCard(
                        title: 'About the song',
                        body: _aboutLine(),
                      ),
                      const SizedBox(height: 12),
                      _infoCard(
                        title: 'Style Description',
                        body: _resolvedStyle(_track).isEmpty
                            ? 'No description was saved with this audio.'
                            : _resolvedStyle(_track),
                        expanded: _styleExpanded,
                        onToggle: () =>
                            setState(() => _styleExpanded = !_styleExpanded),
                        onCopy: _resolvedStyle(_track).isEmpty
                            ? null
                            : () => _copy('style', _resolvedStyle(_track)),
                      ),
                      const SizedBox(height: 12),
                      _infoCard(
                        title: _track.wordsAreScript ? 'Script' : 'Lyrics',
                        body: _wordsBody(),
                        expanded: _wordsExpanded,
                        onToggle: () =>
                            setState(() => _wordsExpanded = !_wordsExpanded),
                        onCopy: _wordsCopy(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _readyBanner(bool playing) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: FrostedPane(
        radius: 28,
        blur: true,
        forceDark: true,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            _ScribbleCover(
              seed: _track.coverSeed,
              size: 36,
              imageUrl: _track.coverUrl,
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Song ready, tap to play',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: _toggle,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFB347), Color(0xFFFF5A36)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coverRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth * 0.72, 300.0);
        return SizedBox(
          height: size,
          child: PageView.builder(
            controller: _coverController,
            itemCount: _playlist.length,
            onPageChanged: (index) {
              if (index != _index) unawaited(_open(index));
            },
            itemBuilder: (context, index) {
              final track = _playlist[index];
              return Center(
                child: _ScribbleCover(
                  seed: track.coverSeed,
                  size: size * 0.92,
                  imageUrl: track.coverUrl,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _seekRow(Duration position, Duration duration) {
    final total = duration.inMilliseconds;
    final progress = total <= 0 ? 0.0 : position.inMilliseconds / total;
        return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            _clock(position),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) {
                  final width = constraints.maxWidth;
                  if (width <= 0) return;
                  _previewSeek(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                    duration,
                  );
                },
                onTapUp: (_) => _commitSeek(),
                onTapCancel: _cancelScrub,
                onHorizontalDragStart: (_) => _draggingScrub = true,
                onHorizontalDragUpdate: (details) {
                  final width = constraints.maxWidth;
                  if (width <= 0) return;
                  _previewSeek(
                    (details.localPosition.dx / width).clamp(0.0, 1.0),
                    duration,
                  );
                },
                onHorizontalDragEnd: (_) => _commitSeek(),
                onHorizontalDragCancel: () {
                  _draggingScrub = false;
                  _cancelScrub();
                },
                child: SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 3,
                          width: constraints.maxWidth,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.28),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Container(
                          height: 3,
                          width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Text(
          total <= 0 ? '--:--' : _clock(duration),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _transport(bool playing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
          tooltip: 'Shuffle',
          onPressed: () => setState(() => _shuffle = !_shuffle),
          icon: Icon(
            Icons.shuffle_rounded,
            color: _shuffle ? Colors.white : Colors.white54,
          ),
        ),
        IconButton(
          tooltip: 'Previous',
          onPressed: _goPrevious,
          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 34),
        ),
        GestureDetector(
          onTap: _ready || _error != null ? _toggle : null,
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: _ready || _error != null
                ? Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 36,
                  )
                : const Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  ),
          ),
        ),
        IconButton(
          tooltip: 'Next',
          onPressed: _playlist.length < 2 ? null : _goNext,
          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 34),
        ),
        IconButton(
          tooltip: 'Queue',
          onPressed: _playlist.isEmpty ? null : _showQueue,
          icon: const Icon(Icons.queue_music_rounded, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _infoCard({
    required String title,
    required String body,
    bool expanded = true,
    VoidCallback? onToggle,
    VoidCallback? onCopy,
  }) {
    final long = body.length > 160;
    final shown = long && !expanded ? '${body.substring(0, 160).trim()}…' : body;
    return FrostedPane(
      forceDark: true,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onCopy != null)
                IconButton(
                  tooltip: 'Copy',
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            shown,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              height: 1.4,
              fontSize: 14,
            ),
          ),
          if (long && onToggle != null)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: onToggle,
                child: Text(expanded ? 'See less' : 'See more'),
              ),
            ),
        ],
      ),
    );
  }

  String _aboutLine() {
    final created = _track.createdAt;
    final when = created == null ? null : _formatDate(created);
    final artist = _visibleArtist(_track);
    if (when == null) return 'Made with $artist';
    return 'Created on $when with $artist';
  }

  String _wordsBody() {
    if (_track.instrumental) return '[Instrumental]';
    final lyrics = _resolvedLyrics(_track);
    if (lyrics != null && lyrics.isNotEmpty) return lyrics;
    final style = _resolvedStyle(_track);
    if (_track.wordsAreScript && style.isNotEmpty) return style;
    if (_track.wordsAreScript) return 'No script was saved with this audio.';
    return 'Lyrics were not kept with this creation.';
  }

  VoidCallback? _wordsCopy() {
    if (_track.instrumental) return () => _copy('lyrics', '[Instrumental]');
    final lyrics = _resolvedLyrics(_track);
    if (lyrics != null && lyrics.isNotEmpty) return () => _copy('lyrics', lyrics);
    final style = _resolvedStyle(_track);
    if (_track.wordsAreScript && style.isNotEmpty) {
      return () => _copy('script', style);
    }
    return null;
  }

  void _more() {
    final lyrics = _resolvedLyrics(_track);
    final style = _resolvedStyle(_track);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1224),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (style.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: Colors.white),
                  title: const Text('Copy style', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _copy('style', style);
                  },
                ),
              if (lyrics != null && lyrics.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.lyrics_outlined, color: Colors.white),
                  title: const Text('Copy lyrics', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _copy('lyrics', lyrics);
                  },
                ),
              if (widget.onRemix != null)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded, color: Colors.white),
                  title: const Text('Remix in Music', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _remix();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white.withValues(alpha: 0.85)),
    );
  }

  Widget _pill({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    String? label,
    bool selected = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: label == null ? 14 : 16,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? Colors.white.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _clock(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = duration.inHours;
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  String _formatDate(DateTime date) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

/// Height of the mini player row, without the system gesture inset.
const double kNowPlayingBarHeight = 64;

/// Navigator context from the tab shell. The floating mini player is built
/// beside the navigator, so a tap there has no navigator of its own.
BuildContext? _miniPlayerNavigatorContext;

void bindMiniPlayerNavigator(BuildContext context) {
  _miniPlayerNavigatorContext = context;
}

BuildContext? _audioSheetContext(BuildContext context) {
  if (Navigator.maybeOf(context) != null) return context;
  final host = _miniPlayerNavigatorContext;
  if (host != null && host.mounted) return host;
  return null;
}

/// Compact controls shown after the full player is closed.
class NowPlayingBar extends StatelessWidget {
  final bool includeSafeArea;

  const NowPlayingBar({super.key, this.includeSafeArea = false});

  @override
  Widget build(BuildContext context) {
    final bar = ListenableBuilder(
      listenable: audioNowPlaying,
      builder: (context, _) {
        final tracks = audioNowPlaying.tracks;
        if (!audioNowPlaying.hasAudio ||
            audioNowPlaying.sheetOpen ||
            tracks.isEmpty) {
          return const SizedBox.shrink();
        }
        final index = audioNowPlaying.index.clamp(0, tracks.length - 1);
        final track = tracks[index];
        final playing = audioNowPlaying.playing;
        return Material(
          color: const Color(0xFF1A1224),
          child: InkWell(
            onTap: () {
              final host = _audioSheetContext(context);
              if (host == null) return;
              FileService.openAudioTracks(
                host,
                tracks: tracks,
                initialIndex: index,
              );
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  _ScribbleCover(
                    seed: track.coverSeed,
                    size: 36,
                    imageUrl: track.coverUrl,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    tooltip: playing ? 'Pause' : 'Play',
                    onPressed: () {
                      if (playing) {
                        unawaited(audioNowPlaying.pause());
                      } else {
                        unawaited(audioNowPlaying.resume());
                      }
                    },
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Stop',
                    onPressed: audioNowPlaying.stop,
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (!includeSafeArea) return bar;
    return SafeArea(top: false, child: bar);
  }
}

class _ScribbleCover extends StatelessWidget {
  final int seed;
  final double size;
  final String? imageUrl;

  const _ScribbleCover({
    required this.seed,
    required this.size,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final palette = CoverPalette.of(seed);
    final radius = BorderRadius.circular(size < 60 ? 10 : 18);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: palette.glow.withValues(alpha: 0.45),
            blurRadius: size < 60 ? 8 : 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: imageUrl == null || imageUrl!.isEmpty
            ? CustomPaint(
                painter: _ScribblePainter(seed),
                size: Size.square(size),
              )
            : Image.network(
                imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => CustomPaint(
                  painter: _ScribblePainter(seed),
                  size: Size.square(size),
                ),
              ),
      ),
    );
  }
}

class _ScribblePainter extends CustomPainter {
  final int seed;

  _ScribblePainter(this.seed);

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    final palette = CoverPalette.of(seed);
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFFF7F4EE));

    for (var i = 0; i < 46; i++) {
      final paint = Paint()
        ..color = palette.inks[i % palette.inks.length].withValues(alpha: 0.85)
        ..strokeWidth = 1.4 + random.nextDouble() * 3.2
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      final start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final end = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      if (random.nextBool()) {
        canvas.drawLine(start, end, paint);
      } else {
        final path = Path()..moveTo(start.dx, start.dy);
        path.quadraticBezierTo(
          random.nextDouble() * size.width,
          random.nextDouble() * size.height,
          end.dx,
          end.dy,
        );
        canvas.drawPath(path, paint);
      }
    }

    final ink = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = max(2.2, size.width * 0.012)
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    final arm = size.width * 0.34;
    for (var i = 0; i < 6; i++) {
      final angle = (pi / 6) * i;
      canvas.drawLine(
        center + Offset(cos(angle), sin(angle)) * (arm * 0.15),
        center + Offset(cos(angle), sin(angle)) * arm,
        ink,
      );
      canvas.drawLine(
        center - Offset(cos(angle), sin(angle)) * (arm * 0.15),
        center - Offset(cos(angle), sin(angle)) * arm,
        ink,
      );
    }
  }

  @override
  bool shouldRepaint(_ScribblePainter oldDelegate) => oldDelegate.seed != seed;
}

/// Reads playback time on a short timer so a stream does not rebuild the player.
class AudioPlayClock extends StatefulWidget {
  final Listenable? source;
  final Duration Function() readPosition;
  final Duration Function() readDuration;
  final Duration knownDuration;
  final Widget Function(BuildContext context, Duration position, Duration total)
      builder;

  const AudioPlayClock({
    super.key,
    required this.readPosition,
    required this.readDuration,
    required this.builder,
    this.source,
    this.knownDuration = Duration.zero,
  });

  @override
  State<AudioPlayClock> createState() => _AudioPlayClockState();
}

class _AudioPlayClockState extends State<AudioPlayClock> {
  Timer? _timer;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  @override
  void initState() {
    super.initState();
    widget.source?.addListener(_read);
    _capture(notify: false);
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _read());
  }

  @override
  void didUpdateWidget(AudioPlayClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      oldWidget.source?.removeListener(_read);
      widget.source?.addListener(_read);
    }
    if (!identical(oldWidget.source, widget.source) ||
        oldWidget.knownDuration != widget.knownDuration) {
      _capture(notify: false);
    }
  }

  Duration _fullLength(Duration reported, Duration known) {
    if (reported > Duration.zero) return reported;
    return known;
  }

  void _read() => _capture(notify: true);

  void _capture({required bool notify}) {
    final reported = widget.readDuration();
    final total = _fullLength(reported, widget.knownDuration);
    final position = widget.readPosition();
    if (!mounted) return;
    if (position == _position && total == _total) return;
    if (!notify) {
      _position = position;
      _total = total;
      return;
    }
    setState(() {
      _position = position;
      _total = total;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.source?.removeListener(_read);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _position, _total);
  }
}

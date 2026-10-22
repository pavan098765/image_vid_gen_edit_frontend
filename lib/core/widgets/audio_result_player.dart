import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/model_display_name.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

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
  return [
    for (final track in music.tracks)
      if (track.isPlayable)
        AudioTrackDetails.fromMusicTrack(
          MusicTrack(
            id: track.id,
            title: track.title,
            lyrics: fullerLyrics(track, music.lyrics),
            tags: track.tags,
            duration: track.duration,
            audioUrl: track.audioUrl,
            streamUrl: track.streamUrl,
            coverUrl: track.coverUrl ??
                (music.covers.isNotEmpty ? music.covers.first : null),
            downloadUrl: track.downloadUrl,
          ),
          jobId: jobId,
          artist: artist,
          instrumental: music.instrumental,
          createdAt: createdAt,
          modelId: modelId,
        ),
  ];
}

List<AudioTrackDetails> audioTracksFromJob(JobModel job) {
  final raw = job.music;
  if (raw == null) return const [];
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
  return _attachSavedFile(job, tracks);
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
  return [tracks.first.copyWith(filePath: path), ...tracks.skip(1)];
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

String _displayTitle(String title, String? prompt) {
  final trimmed = title.trim();
  if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'untitled') {
    return trimmed;
  }
  if (prompt == null) return 'Untitled';
  final line = prompt.split('\n').first.trim();
  if (line.length <= 48) return line;
  return '${line.substring(0, 48).trim()}…';
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
  VideoPlayerController? _controller;
  late List<AudioTrackDetails> _playlist;
  int _index = 0;
  int _loadGeneration = 0;
  bool _ready = false;
  bool _shuffle = false;
  bool _showReady = true;
  bool _styleExpanded = false;
  bool _wordsExpanded = false;
  bool _handledEnd = false;
  bool _playing = false;
  bool _syncQueued = false;
  bool _adopting = false;
  String? _error;
  String? _reaction;
  final Random _random = Random();
  final Set<String> _reloadedUrls = {};

  AudioTrackDetails get _track => _playlist[_index];

  @override
  void initState() {
    super.initState();
    _playlist = List<AudioTrackDetails>.of(widget.tracks);
    final maxIndex = _playlist.length - 1;
    _index = widget.initialIndex.clamp(0, maxIndex < 0 ? 0 : maxIndex);
    jobListNotifier.addListener(_syncFromJobs);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(_index);
    });
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
    final reported = _controller?.value.duration ?? Duration.zero;
    final full = known ?? Duration.zero;
    if (full < const Duration(seconds: 5)) return false;
    return reported + const Duration(seconds: 2) < full;
  }

  Future<void> _applyJobTracks() async {
    if (!mounted || _adopting) return;
    var changed = false;
    var reloadIndex = -1;
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
      final reload = !playingFile &&
          (urlChanged || finished || (durationGrew && !kept.streaming) || stuckOnStream);
      final sameWords = kept.lyrics == previous.lyrics &&
          kept.coverUrl == previous.coverUrl &&
          kept.knownDuration == previous.knownDuration &&
          kept.streaming == previous.streaming &&
          kept.networkUrl == previous.networkUrl &&
          kept.filePath == previous.filePath;
      if (sameWords && !reload) continue;
      _playlist[i] = kept;
      changed = true;
      if (reload && i == _index) reloadIndex = i;
    }
    if (reloadIndex >= 0) {
      final keep = _controller?.value.position ?? Duration.zero;
      final wasPlaying = _playing;
      _adopting = true;
      await _open(reloadIndex);
      _adopting = false;
      if (!mounted) return;
      if (keep > const Duration(seconds: 1)) {
        await _controller?.seekTo(keep);
      }
      if (wasPlaying) await _controller?.play();
      return;
    }
    if (changed && mounted) setState(() {});
  }

  Future<void> _loadReaction() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_reactionKey(_track.filePath));
    if (!mounted) return;
    setState(() => _reaction = value);
  }

  Future<void> _setReaction(String value) async {
    final next = _reaction == value ? null : value;
    setState(() => _reaction = next);
    final prefs = await SharedPreferences.getInstance();
    final key = _reactionKey(_track.filePath);
    if (next == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, next);
    }
  }

  String _reactionKey(String path) => 'audio_mark_${path.hashCode}';

  VideoPlayerController? _controllerFor(AudioTrackDetails track) {
    if (track.filePath.isNotEmpty && File(track.filePath).existsSync()) {
      return VideoPlayerController.file(File(track.filePath));
    }
    final url = track.networkUrl;
    if (url != null && url.isNotEmpty) {
      return VideoPlayerController.networkUrl(Uri.parse(url));
    }
    return null;
  }

  Future<void> _open(int index) async {
    final generation = ++_loadGeneration;
    final previous = _controller;
    _controller = null;
    previous?.removeListener(_onPlaybackSignal);
    await previous?.dispose();
    if (index < 0 || index >= _playlist.length) return;

    final track = _playlist[index];
    try {
      final controller = _controllerFor(track);
      if (controller == null) {
        throw StateError('no audio source');
      }
      await controller.initialize();
      if (!mounted || generation != _loadGeneration) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onPlaybackSignal);
      setState(() {
        _controller = controller;
        _index = index;
        _ready = true;
        _playing = false;
        _error = null;
        _handledEnd = false;
        _styleExpanded = false;
        _wordsExpanded = true;
      });
      _loadReaction();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _index = index;
        _ready = false;
        _error = 'Could not play this audio';
      });
    }
  }

  void _onPlaybackSignal() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final playing = controller.value.isPlaying;
    if (playing != _playing) setState(() => _playing = playing);
  }

  void _onClock(Duration position, Duration total) {
    final controller = _controller;
    if (controller == null || !mounted || _handledEnd) return;
    final atEnd = total > const Duration(milliseconds: 800) &&
        position >= total - const Duration(milliseconds: 250);
    if (!atEnd || !controller.value.isPlaying) return;
    _handledEnd = true;
    if (_playlist.length > 1) {
      _goNext();
      return;
    }
    controller.pause();
  }

  @override
  void dispose() {
    jobListNotifier.removeListener(_syncFromJobs);
    _controller?.removeListener(_onPlaybackSignal);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null || !_ready) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      if (_handledEnd) {
        _handledEnd = false;
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      if (_showReady && mounted) setState(() => _showReady = false);
    }
    HapticFeedback.lightImpact();
    if (mounted) setState(() {});
  }

  void _goPrevious() {
    if (_playlist.length < 2) {
      _controller?.seekTo(Duration.zero);
      return;
    }
    final next = (_index - 1) < 0 ? _playlist.length - 1 : _index - 1;
    _open(next);
  }

  void _goNext() {
    if (_playlist.length < 2) return;
    if (_shuffle) {
      var next = _random.nextInt(_playlist.length);
      if (next == _index) next = (next + 1) % _playlist.length;
      _open(next);
      return;
    }
    _open((_index + 1) % _playlist.length);
  }

  void _seek(double fraction) {
    final controller = _controller;
    if (controller == null || !_ready) return;
    final reported = controller.value.duration;
    final known = _track.knownDuration ?? Duration.zero;
    final total = (known > reported ? known : reported).inMilliseconds;
    if (total <= 0) return;
    _handledEnd = false;
    controller.seekTo(Duration(milliseconds: (total * fraction).round()));
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
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  track.artist,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
                trailing: selected
                    ? const Icon(Icons.graphic_eq_rounded, color: Colors.white)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  _open(index);
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

    return Material(
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
                    onPressed: widget.onClose,
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
                      Text(
                        _track.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _track.artist,
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
                            tooltip: 'Copy song details',
                            onPressed: () => _copy(
                              'song details',
                              '${_track.title}\n${_track.artist}\n${_track.style}',
                            ),
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
                            icon: Icons.thumb_up_alt_outlined,
                            selected: _reaction == 'like',
                            onTap: () => _setReaction('like'),
                            tooltip: 'Like',
                          ),
                          _pill(
                            icon: Icons.thumb_down_alt_outlined,
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
                          if (_playlist.length > 1)
                            _pill(
                              icon: Icons.queue_music_rounded,
                              label: 'Playlist',
                              onTap: _showQueue,
                              tooltip: 'Playlist',
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (_track.streaming)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Streaming. The full song replaces this when it is ready.',
                            style: TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      AudioPlayClock(
                        controller: _controller,
                        knownDuration: _track.knownDuration ?? Duration.zero,
                        onProgress: _onClock,
                        builder: (context, position, total) =>
                            _seekRow(position, total),
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
                        body: _track.style.isEmpty
                            ? 'No description was saved with this audio.'
                            : _track.style,
                        expanded: _styleExpanded,
                        onToggle: () =>
                            setState(() => _styleExpanded = !_styleExpanded),
                        onCopy: _track.style.isEmpty
                            ? null
                            : () => _copy('style', _track.style),
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
    final next = _playlist.length > 1
        ? _playlist[(_index + 1) % _playlist.length]
        : null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = min(constraints.maxWidth * 0.78, 320.0);
        return SizedBox(
          height: size,
          child: GestureDetector(
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -180) _goNext();
              if (velocity > 180) _goPrevious();
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                if (next != null)
                  Positioned(
                    right: 0,
                    top: 16,
                    child: GestureDetector(
                      onTap: _goNext,
                      child: Opacity(
                        opacity: 0.95,
                        child: _ScribbleCover(
                          seed: next.coverSeed,
                          size: size * 0.82,
                          imageUrl: next.coverUrl,
                        ),
                      ),
                    ),
                  ),
                _ScribbleCover(
                  seed: _track.coverSeed,
                  size: size,
                  imageUrl: _track.coverUrl,
                ),
              ],
            ),
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
                  _seek((details.localPosition.dx / width).clamp(0.0, 1.0));
                },
                onHorizontalDragUpdate: (details) {
                  final width = constraints.maxWidth;
                  if (width <= 0) return;
                  _seek((details.localPosition.dx / width).clamp(0.0, 1.0));
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
          onPressed: _playlist.length < 2
              ? null
              : () => setState(() => _shuffle = !_shuffle),
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
          onTap: _ready ? _toggle : null,
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: _ready
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
          onPressed: _playlist.length < 2 ? null : _showQueue,
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
    if (when == null) return 'Made with ${_track.artist}';
    return 'Created on $when with ${_track.artist}';
  }

  String _wordsBody() {
    if (_track.instrumental) return '[Instrumental]';
    final lyrics = _track.lyrics;
    if (lyrics != null && lyrics.isNotEmpty) return lyrics;
    if (_track.wordsAreScript && _track.style.isNotEmpty) return _track.style;
    if (_track.wordsAreScript) return 'No script was saved with this audio.';
    return 'Lyrics were not kept with this creation.';
  }

  VoidCallback? _wordsCopy() {
    if (_track.instrumental) return () => _copy('lyrics', '[Instrumental]');
    final lyrics = _track.lyrics;
    if (lyrics != null && lyrics.isNotEmpty) return () => _copy('lyrics', lyrics);
    if (_track.wordsAreScript && _track.style.isNotEmpty) {
      return () => _copy('script', _track.style);
    }
    return null;
  }

  void _more() {
    final lyrics = _track.lyrics;
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
              if (_track.style.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.copy_rounded, color: Colors.white),
                  title: const Text('Copy style', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    _copy('style', _track.style);
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
  final VideoPlayerController? controller;
  final Duration knownDuration;
  final void Function(Duration position, Duration total)? onProgress;
  final Widget Function(BuildContext context, Duration position, Duration total)
      builder;

  const AudioPlayClock({
    super.key,
    required this.controller,
    required this.builder,
    this.knownDuration = Duration.zero,
    this.onProgress,
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
    widget.controller?.addListener(_read);
    _capture(notify: false);
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _read());
  }

  @override
  void didUpdateWidget(AudioPlayClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_read);
      widget.controller?.addListener(_read);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.knownDuration != widget.knownDuration) {
      _capture(notify: false);
    }
  }

  Duration _fullLength(Duration reported, Duration known) {
    if (known <= Duration.zero) return reported;
    if (reported <= Duration.zero) return known;
    if (reported + const Duration(seconds: 2) < known) return known;
    return reported;
  }

  void _read() => _capture(notify: true);

  void _capture({required bool notify}) {
    final controller = widget.controller;
    final reported = controller?.value.duration ?? Duration.zero;
    final total = _fullLength(reported, widget.knownDuration);
    final position = controller?.value.position ?? Duration.zero;
    if (!mounted) return;
    if (notify) widget.onProgress?.call(position, total);
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
    widget.controller?.removeListener(_read);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _position, _total);
  }
}

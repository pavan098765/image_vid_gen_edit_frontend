import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/suno_v6_client.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/audio_features.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/lyric_captions.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_export.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_frame.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_template.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class MusicVideoPage extends StatefulWidget {
  final String parentJobId;
  final String title;
  final String artist;
  final String audioPath;
  final String? networkAudioUrl;
  final String? coverUrl;
  final double? durationSeconds;
  final String taskId;
  final String audioId;
  final bool instrumental;
  final List<AlignedWord> words;
  final double? lyricConfidence;
  final int? cloudGems;
  final Future<void> Function()? onCloudVideo;
  final Future<void> Function(TimestampedLyrics lyrics)? onLyrics;

  const MusicVideoPage({
    super.key,
    required this.parentJobId,
    required this.title,
    required this.artist,
    required this.audioPath,
    this.taskId = '',
    this.audioId = '',
    this.onCloudVideo,
    this.onLyrics,
    this.networkAudioUrl,
    this.coverUrl,
    this.durationSeconds,
    this.instrumental = false,
    this.words = const [],
    this.lyricConfidence,
    this.cloudGems,
  });

  @override
  State<MusicVideoPage> createState() => _MusicVideoPageState();
}

class _MusicVideoPageState extends State<MusicVideoPage> {
  final AudioPlayer _player = AudioPlayer();
  MusicVideoTemplate _template = kMusicVideoTemplates.first;
  MusicVideoAspect _aspect = MusicVideoAspect.landscape;
  bool _lyrics = false;
  bool _busy = false;
  bool _analyzing = false;
  bool _syncingLyrics = false;
  double _progress = 0;
  String _label = '';
  String? _audioPath;
  String? _loopPath;
  ui.Image? _cover;
  AudioFeatureTable? _features;
  List<AlignedWord> _words = const [];
  double? _confidence;
  double _position = 0;

  bool get _canSyncLyrics =>
      !widget.instrumental &&
      widget.taskId.trim().isNotEmpty &&
      widget.audioId.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _audioPath = widget.audioPath.trim().isEmpty ? null : widget.audioPath;
    _words = widget.words;
    _confidence = widget.lyricConfidence;
    _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() => _position = position.inMilliseconds / 1000);
    });
    _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _prepare();
  }

  @override
  void dispose() {
    _player.dispose();
    _cover?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final coverUrl = widget.coverUrl;
    if (coverUrl != null && coverUrl.isNotEmpty) {
      try {
        final bytes = await _readBytes(coverUrl);
        final image = await _decode(bytes);
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() => _cover = image);
      } catch (_) {}
    }
    final path = _audioPath;
    if (path != null && File(path).existsSync()) {
      try {
        await _player.setFilePath(path);
      } catch (_) {}
    }
  }

  Future<void> _ensureFeatures() async {
    if (!_template.needsAudioAnalysis || _features != null || _analyzing) return;
    setState(() => _analyzing = true);
    try {
      final path = await _ensureAudio();
      final temp = await getTemporaryDirectory();
      final table = audioFeatureTableFromPcm(
        await decodeMusicVideoPcm(path, '${temp.path}/music_video_preview'),
      );
      if (!mounted) return;
      setState(() => _features = table);
    } on MusicVideoException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (_player.playing) {
        await _player.pause();
        return;
      }
      final path = await _ensureAudio();
      if (_player.audioSource == null) await _player.setFilePath(path);
      await _player.play();
    } on MusicVideoException catch (error) {
      _toast(error.message);
    }
  }

  Future<String> _ensureAudio() async {
    final existing = _audioPath;
    if (existing != null && File(existing).existsSync()) return existing;
    final url = widget.networkAudioUrl;
    if (url == null || url.isEmpty) {
      throw const MusicVideoException('Save the song on this phone before making a video.');
    }
    final bytes = await _readBytes(url);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/music_video_song.mp3');
    await file.writeAsBytes(bytes);
    _audioPath = file.path;
    return file.path;
  }

  Future<Uint8List> _readBytes(String source) async {
    if (!source.startsWith('http')) return File(source).readAsBytes();
    final response = await http.get(Uri.parse(source)).timeout(const Duration(minutes: 2));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw const MusicVideoException('Could not download the song.');
    }
    return response.bodyBytes;
  }

  Future<void> _syncLyrics() async {
    if (_syncingLyrics || !_canSyncLyrics) return;
    setState(() => _syncingLyrics = true);
    try {
      final lyrics = await fetchTimestampedLyrics(
        taskId: widget.taskId,
        audioId: widget.audioId,
      );
      await widget.onLyrics?.call(lyrics);
      if (!mounted) return;
      setState(() {
        _words = lyrics.words;
        _confidence = lyrics.confidence;
        _lyrics = lyricSyncFor(words: lyrics.words, confidence: lyrics.confidence) !=
            LyricSync.hidden;
      });
    } on SunoFormException catch (error) {
      _toast(error.message);
    } finally {
      if (mounted) setState(() => _syncingLyrics = false);
    }
  }

  Future<void> _pickLoop() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _loopPath = path);
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = 0;
      _label = 'Starting';
    });
    try {
      final audioPath = await _ensureAudio();
      Uint8List? coverBytes;
      final coverUrl = widget.coverUrl;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        try {
          coverBytes = await _readBytes(coverUrl);
        } catch (_) {}
      }
      final rendered = await exportMusicVideo(
        MusicVideoExportRequest(
          template: _template,
          aspect: _aspect,
          audioPath: audioPath,
          coverBytes: coverBytes,
          loopVideoPath: _loopPath,
          words: _words,
          lyricConfidence: _confidence,
          lyricsEnabled: _lyrics,
          title: widget.title,
          artist: widget.artist,
          durationSeconds: widget.durationSeconds,
        ),
        onProgress: (progress, label) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _label = label;
          });
        },
      );
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory('${docs.path}/saved_results');
      if (!folder.existsSync()) folder.createSync(recursive: true);
      final name = FileService.generateTimestampFilename('music_video', 'mp4');
      final saved = File('${folder.path}/$name');
      await File(rendered).copy(saved.path);
      final job = JobModel(
        jobId: const Uuid().v4(),
        title: widget.title.trim().isEmpty ? 'Music video' : widget.title.trim(),
        model: kLocalMusicVideoModelId,
        outputType: 'video',
        status: 'completed',
        localFilePath: saved.path,
        capabilityId: 'create_music',
        parentJobId: widget.parentJobId,
        originalPrompt: widget.title,
        creditsCharged: 0,
        settingsSnapshot: {
          'modelId': kLocalMusicVideoModelId,
          'template': _template.id,
          'aspect': _aspect.label,
          'lyrics': _lyrics,
        },
      );
      await addOrUpdateJob(job);
      if (!mounted) return;
      await FileService.saveExistingToGallery(
        context,
        saved.path,
        customFileName: name,
        jobId: job.jobId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on MusicVideoException catch (error) {
      _toast(error.message);
    } catch (_) {
      _toast('Could not build the video.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lyricLine = _lyrics ? activeLyricLine(_words, _position) : null;
    final features = _template.needsAudioAnalysis ? _features?.atTime(_position) : null;
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E14),
        foregroundColor: Colors.white,
        title: const Text('Music video'),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: _aspect.ratio,
            child: ColoredBox(
              color: Colors.black,
              child: CustomPaint(
                painter: MusicVideoFramePainter(
                  template: _template,
                  cover: _cover,
                  features: features,
                  lyricLine: lyricLine,
                  title: widget.title,
                  artist: widget.artist,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _busy ? null : _togglePlay,
                  icon: Icon(
                    _player.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                  ),
                ),
                Expanded(
                  child: Text(
                    _busy
                        ? _label
                        : _analyzing
                            ? 'Reading the song'
                            : widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _section('Aspect'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final aspect in MusicVideoAspect.values)
                      ChoiceChip(
                        label: Text(aspect.label),
                        selected: aspect == _aspect,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _aspect = aspect),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _section('Style'),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kMusicVideoTemplates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final template = kMusicVideoTemplates[index];
                      final selected = template.id == _template.id;
                      return ChoiceChip(
                        label: Text(template.title),
                        selected: selected,
                        onSelected: _busy
                            ? null
                            : (_) async {
                                setState(() => _template = template);
                                if (template.needsAudioAnalysis) await _ensureFeatures();
                              },
                      );
                    },
                  ),
                ),
                if (_template.needsLoopVideo) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _pickLoop,
                    child: Text(
                      _loopPath == null ? 'Choose looping video' : 'Looping video chosen',
                    ),
                  ),
                ],
                if (_canSyncLyrics) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Time-synced lyrics', style: TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'Uses the sung word times from HitMaker.',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    value: _lyrics,
                    onChanged: _busy
                        ? null
                        : (value) async {
                            if (value && _words.isEmpty) await _syncLyrics();
                            if (!mounted) return;
                            setState(() => _lyrics = value && _words.isNotEmpty);
                          },
                  ),
                  if (!_lyrics && _words.isEmpty)
                    TextButton(
                      onPressed: _busy || _syncingLyrics ? null : _syncLyrics,
                      child: Text(_syncingLyrics ? 'Reading lyrics…' : 'Load timed lyrics'),
                    ),
                ],
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _export,
                  child: const Text('Create on this phone'),
                ),
                if (widget.onCloudVideo != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () async {
                            final cloud = widget.onCloudVideo;
                            if (cloud == null) return;
                            Navigator.of(context).pop();
                            await cloud();
                          },
                    child: Text(
                      widget.cloudGems == null
                          ? 'Cloud music video'
                          : 'Cloud music video · ${widget.cloudGems} gems',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
    );
  }
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

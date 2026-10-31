import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/suno_v6_client.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/audio_features.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/lyric_captions.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_cover.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_export.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_frame.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_template.dart';
import 'package:path_provider/path_provider.dart';

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
  final String lyricSheet;
  final String style;
  final double? lyricConfidence;
  final int? cloudGems;
  final Future<bool> Function()? onCloudVideo;
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
    this.lyricSheet = '',
    this.style = '',
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
  final double _progress = 0;
  String _label = '';
  String? _audioPath;
  String? _loopPath;
  ui.Image? _cover;
  Uint8List? _generatedCover;
  bool _makingCover = false;
  AudioFeatureTable? _features;
  List<AlignedWord> _words = const [];
  double? _confidence;
  double _position = 0;
  bool _evenLyrics = false;
  Color? _meterTint;

  MusicVideoTemplate get _drawn {
    final tint = _meterTint;
    if (tint == null) return _template;
    return _template.copyWith(meterColor: tint);
  }

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
    final saved = await savedMusicVideoCover(widget.parentJobId);
    if (saved != null) {
      await _showCover(saved, generated: true);
    } else {
      final coverUrl = widget.coverUrl;
      if (coverUrl != null && coverUrl.isNotEmpty) {
        try {
          await _showCover(await _readBytes(coverUrl), generated: false);
        } catch (_) {}
      }
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
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
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
      final sync = lyricSyncFor(words: lyrics.words, confidence: lyrics.confidence);
      if (sync == LyricSync.hidden) {
        if (!await _useEvenLyrics()) {
          _toast(lyricLookupMessage('Timed lyrics are not available for this song yet.'));
        }
        return;
      }
      await widget.onLyrics?.call(lyrics);
      if (!mounted) return;
      setState(() {
        _words = lyrics.words;
        _confidence = lyrics.confidence;
        _lyrics = true;
        _evenLyrics = false;
      });
    } on SunoFormException catch (error) {
      if (!await _useEvenLyrics()) _toast(lyricLookupMessage(error.message));
    } catch (error) {
      debugPrint('Timed lyrics failed: $error');
      if (!await _useEvenLyrics()) {
        _toast('Timed lyrics are not available for this song yet.');
      }
    } finally {
      if (mounted) setState(() => _syncingLyrics = false);
    }
  }

  Future<bool> _useEvenLyrics() async {
    final duration = (_features != null && _features!.durationSeconds > 1)
        ? _features!.durationSeconds
        : _songSeconds();
    final energy = [
      for (final frame in _features?.frames ?? const <FrameFeatures>[]) frame.mid,
    ];
    final window = sungWindow(energy, duration);
    final words = evenLyricWords(
      widget.lyricSheet,
      window.end - window.start,
      startSeconds: window.start,
    );
    if (lyricSyncFor(words: words, confidence: 0) == LyricSync.hidden) return false;
    if (!mounted) return false;
    setState(() {
      _words = words;
      _confidence = 0;
      _lyrics = true;
      _evenLyrics = true;
    });
    return true;
  }

  double _songSeconds() {
    final known = widget.durationSeconds;
    if (known != null && known > 1) return known;
    final playing = _player.duration;
    if (playing != null && playing.inMilliseconds > 1000) {
      return playing.inMilliseconds / 1000;
    }
    return 0;
  }

  Future<void> _showCover(Uint8List bytes, {required bool generated}) async {
    final image = await _decode(bytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    final previous = _cover;
    setState(() {
      if (generated) _generatedCover = bytes;
      _cover = image;
    });
    previous?.dispose();
  }

  Future<void> _makeCover() async {
    if (_makingCover || _busy) return;
    setState(() => _makingCover = true);
    try {
      final bytes = await generateMusicVideoCover(
        parentJobId: widget.parentJobId,
        title: widget.title,
        artist: widget.artist,
        lyricSheet: widget.lyricSheet,
        style: widget.style,
      );
      await _showCover(bytes, generated: true);
    } on MusicVideoCoverException catch (error) {
      _toast(error.message);
    } catch (_) {
      _toast('The cover could not be made.');
    } finally {
      if (mounted) setState(() => _makingCover = false);
    }
  }

  Future<void> _pickLoop() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _loopPath = path);
  }

  Future<void> _startOnPhone() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _label = 'Starting';
    });
    var left = false;
    try {
      final audioPath = await _ensureAudio();
      Uint8List? coverBytes = _generatedCover;
      final coverUrl = widget.coverUrl;
      if (coverBytes == null && coverUrl != null && coverUrl.isNotEmpty) {
        try {
          coverBytes = await _readBytes(coverUrl);
        } catch (_) {}
      }
      final reserved = await reserveOnDeviceMusicVideo(
        title: widget.title,
        templateId: _drawn.id,
        aspect: _aspect.label,
      );
      final request = MusicVideoExportRequest(
        template: _drawn,
        aspect: _aspect,
        audioPath: audioPath,
        coverBytes: coverBytes,
        loopVideoPath: _loopPath,
        words: List<AlignedWord>.from(_words),
        lyricConfidence: _confidence,
        lyricsEnabled: _lyrics,
        title: widget.title,
        artist: widget.artist,
        durationSeconds: widget.durationSeconds,
      );
      final job = JobModel(
        jobId: reserved.jobId,
        title: widget.title.trim().isEmpty ? 'Music video' : widget.title.trim(),
        model: kLocalMusicVideoModelId,
        outputType: 'video',
        status: 'processing',
        capabilityId: 'create_music',
        parentJobId: widget.parentJobId,
        originalPrompt: widget.title,
        creditsCharged: kOnDeviceMusicVideoGems,
        settingsSnapshot: {
          'modelId': kLocalMusicVideoModelId,
          'template': _drawn.id,
          'aspect': _aspect.label,
          'lyrics': _lyrics,
        },
      );
      await addOrUpdateJob(job);
      left = true;
      if (mounted) _leaveForCreations(context);
      unawaited(finishOnDeviceMusicVideo(
        jobId: reserved.jobId,
        token: reserved.token,
        request: request,
        job: job,
      ));
    } on MusicVideoJobException catch (error) {
      _toast(error.message);
    } on MusicVideoException catch (error) {
      _toast(error.message);
    } catch (_) {
      _toast('Could not start the video.');
    } finally {
      if (mounted && !left) setState(() => _busy = false);
    }
  }

  void _leaveForCreations(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    selectedIndexNotifier.value = AppTabs.creations;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lyricLine = _lyrics ? previewLyricLine(_words, _position) : null;
    final features = _template.needsAudioAnalysis
        ? (_features?.atTime(_position) ?? FrameFeatures.preview)
        : null;
    final screen = MediaQuery.sizeOf(context);
    final maxPreview = screen.height * 0.32;
    final natural = screen.width / _aspect.ratio;
    final previewHeight = natural < maxPreview ? natural : maxPreview;
    final previewWidth = previewHeight * _aspect.ratio;
    final lyricSubtitle = _syncingLyrics
        ? 'Reading the sung words'
        : _evenLyrics
            ? 'Lines follow the louder part of the song'
            : 'Sung word times from this HitMaker version';
    return Scaffold(
      backgroundColor: const Color(0xFF0E0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E0E14),
        foregroundColor: Colors.white,
        title: const Text('Music video'),
      ),
      body: Column(
        children: [
          ColoredBox(
            color: Colors.black,
            child: SizedBox(
              width: double.infinity,
              height: previewHeight,
              child: Center(
                child: SizedBox(
                  width: previewWidth,
                  height: previewHeight,
                  child: CustomPaint(
                    painter: MusicVideoFramePainter(
                      template: _drawn,
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              children: [
                _section('Aspect'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final aspect in MusicVideoAspect.values)
                      ChoiceChip(
                        label: Text(aspect.label),
                        selected: aspect == _aspect,
                        onSelected: _busy ? null : (_) => setState(() => _aspect = aspect),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _section('Cover'),
                OutlinedButton(
                  onPressed: _busy || _makingCover ? null : _makeCover,
                  child: Text(_makingCover ? 'Making a cover' : 'New cover · $kMusicVideoCoverGems gems'),
                ),
                const SizedBox(height: 16),
                _section('Style'),
                SizedBox(
                  height: 168,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kMusicVideoTemplates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final template = kMusicVideoTemplates[index];
                      return _StyleCard(
                        template: template,
                        selected: template.id == _template.id,
                        cover: _cover,
                        onTap: _busy
                            ? null
                            : () async {
                                setState(() => _template = template);
                                if (template.needsAudioAnalysis) await _ensureFeatures();
                              },
                      );
                    },
                  ),
                ),
                if (_template.needsAudioAnalysis) ...[
                  const SizedBox(height: 14),
                  _section('Color'),
                  _HueBar(
                    color: _drawn.meterColor,
                    onChanged: _busy ? null : (color) => setState(() => _meterTint = color),
                  ),
                ],
                if (_template.needsLoopVideo) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _pickLoop,
                    child: Text(_loopPath == null ? 'Choose looping video' : 'Looping video chosen'),
                  ),
                ],
                if (_canSyncLyrics) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lyrics', style: TextStyle(color: Colors.white)),
                    subtitle: Text(lyricSubtitle, style: TextStyle(color: cs.onSurfaceVariant)),
                    value: _lyrics,
                    onChanged: _busy || _syncingLyrics
                        ? null
                        : (value) async {
                            if (!value) {
                              setState(() => _lyrics = false);
                              return;
                            }
                            if (_words.isEmpty || _evenLyrics) {
                              final placed = await _useEvenLyrics();
                              if (!placed && _words.isEmpty) {
                                _toast('This song has no lyric sheet to place on the video.');
                                return;
                              }
                            }
                            if (!mounted) return;
                            setState(() => _lyrics = true);
                            if (_evenLyrics && _canSyncLyrics) unawaited(_syncLyrics());
                          },
                  ),
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _busy ? null : _startOnPhone,
                    child: const Text('On this phone · $kOnDeviceMusicVideoGems gems'),
                  ),
                  if (widget.onCloudVideo != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final cloud = widget.onCloudVideo;
                              if (cloud == null) return;
                              final started = await cloud();
                              if (!started || !context.mounted) return;
                              _leaveForCreations(context);
                            },
                      child: Text(
                        'Cloud · ${widget.cloudGems ?? 20} gems · 480p',
                      ),
                    ),
                  ],
                ],
              ),
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

class _HueBar extends StatelessWidget {
  const _HueBar({required this.color, required this.onChanged});

  final Color color;
  final ValueChanged<Color>? onChanged;

  @override
  Widget build(BuildContext context) {
    final hue = HSVColor.fromColor(color).hue;
    return Semantics(
      label: 'Visualization color',
      slider: true,
      child: SizedBox(
        height: 36,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              onTapDown: onChanged == null
                  ? null
                  : (details) => onChanged!(_colorAt(details.localPosition.dx, width)),
              onHorizontalDragUpdate: onChanged == null
                  ? null
                  : (details) => onChanged!(_colorAt(details.localPosition.dx, width)),
              child: CustomPaint(
                painter: _HueBarPainter(hue: hue),
                child: const SizedBox.expand(),
              ),
            );
          },
        ),
      ),
    );
  }

  Color _colorAt(double dx, double width) {
    final t = width <= 0 ? 0.0 : (dx / width).clamp(0.0, 1.0);
    return HSVColor.fromAHSV(1, t * 360, 0.9, 1).toColor();
  }
}

class _HueBarPainter extends CustomPainter {
  const _HueBarPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18));
    final colors = [
      for (var i = 0; i <= 12; i++) HSVColor.fromAHSV(1, i * 30, 0.9, 1).toColor(),
    ];
    canvas.drawRRect(
      rect,
      Paint()
        ..shader = LinearGradient(colors: colors).createShader(Offset.zero & size),
    );
    final x = (hue / 360) * size.width;
    canvas.drawCircle(
      Offset(x.clamp(10, size.width - 10), size.height / 2),
      10,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(x.clamp(10, size.width - 10), size.height / 2),
      7,
      Paint()..color = HSVColor.fromAHSV(1, hue, 0.9, 1).toColor(),
    );
  }

  @override
  bool shouldRepaint(_HueBarPainter oldDelegate) => oldDelegate.hue != hue;
}

class _StyleCard extends StatelessWidget {
  const _StyleCard({
    required this.template,
    required this.selected,
    required this.cover,
    required this.onTap,
  });

  final MusicVideoTemplate template;
  final bool selected;
  final ui.Image? cover;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final features = template.needsAudioAnalysis ? FrameFeatures.preview : null;
    return Semantics(
      button: true,
      selected: selected,
      label: template.title,
      child: Material(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 124,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? const Color(0xFF8B6CFF) : const Color(0x33FFFFFF),
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                    child: CustomPaint(
                      painter: MusicVideoFramePainter(
                        template: template,
                        cover: cover,
                        features: features,
                        title: 'Title',
                        artist: 'Artist',
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                  child: Text(
                    template.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xCCFFFFFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

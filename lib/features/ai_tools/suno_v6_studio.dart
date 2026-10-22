import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    hide userCreditsNotifier;
import 'package:kala_ai_create_images_videos_with_ai/core/suno_v6_client.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/audio_result_player.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/credits/credits_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

class SunoV6Studio extends StatefulWidget {
  final String? initialPrompt;
  final String? initialAudioPath;
  final String? initialLyrics;
  final String selectedModelId;
  final List<({String id, String name, String description})> models;
  final VoidCallback onOpenSettings;

  const SunoV6Studio({
    super.key,
    this.initialPrompt,
    this.initialAudioPath,
    this.initialLyrics,
    required this.selectedModelId,
    required this.models,
    required this.onOpenSettings,
  });

  @override
  State<SunoV6Studio> createState() => SunoV6StudioState();
}

class SunoV6StudioState extends State<SunoV6Studio> {
  final _idea = TextEditingController();
  final _title = TextEditingController();
  final _lyrics = TextEditingController();
  final _style = TextEditingController();
  final _negative = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _advanced = false;
  bool _soundsMode = false;
  String? _vocalGender;
  bool _instrumental = false;
  bool _useCover = false;
  int? _duration;
  bool _soundLoop = true;
  int? _soundTempo;
  String _soundKey = 'Any';

  final List<XFile> _images = [];
  XFile? _video;
  String? _audioPath;
  String? _audioName;

  List<MusicPersona> _personas = const [];
  MusicPersona? _persona;

  bool _busy = false;
  String? _error;
  String? _jobId;
  MusicResult? _music;
  int _trackIndex = 0;
  VideoPlayerController? _player;
  bool _playerReady = false;
  bool _shownPlaying = false;
  bool _lyricsOpen = false;
  String? _playingUrl;
  Timer? _pollTimer;

  bool get _easy => !_soundsMode && !_advanced;
  bool get _custom => !_soundsMode && _advanced;
  bool get _sounds => _soundsMode;
  String get _modeName => _sounds ? 'sounds' : (_advanced ? 'custom' : 'easy');

  MusicTrack? get _track {
    final tracks = _music?.tracks ?? const <MusicTrack>[];
    if (tracks.isEmpty) return null;
    final i = _trackIndex.clamp(0, tracks.length - 1);
    return tracks[i];
  }

  @override
  void initState() {
    super.initState();
    final prompt = widget.initialPrompt?.trim();
    if (prompt != null && prompt.isNotEmpty) _idea.text = prompt;
    final lyrics = widget.initialLyrics?.trim();
    if (lyrics != null && lyrics.isNotEmpty) {
      _lyrics.text = lyrics;
      _advanced = true;
    }
    final audio = widget.initialAudioPath;
    if (audio != null && audio.isNotEmpty) {
      _audioPath = audio;
      _audioName = audio.split(RegExp(r'[\\/]')).last;
      _advanced = false;
      _soundsMode = false;
    }
    loadSavedPersonas().then((list) {
      if (!mounted) return;
      setState(() => _personas = list);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _player?.dispose();
    _idea.dispose();
    _title.dispose();
    _lyrics.dispose();
    _style.dispose();
    _negative.dispose();
    super.dispose();
  }

  int get _songCost => sunoV6CreditCost(action: _sounds ? 'sounds' : 'song');

  String get _prompt {
    if (_custom) {
      if (_instrumental) {
        return _style.text.trim().isNotEmpty
            ? _style.text.trim()
            : _idea.text.trim();
      }
      if (_lyrics.text.trim().isNotEmpty) return _lyrics.text.trim();
    }
    return _idea.text.trim();
  }

  bool get _canSubmit {
    if (_busy) return false;
    if (_sounds) return _idea.text.trim().isNotEmpty;
    if (_custom) {
      if (_instrumental) return _style.text.trim().isNotEmpty;
      return _lyrics.text.trim().isNotEmpty;
    }
    return _idea.text.trim().isNotEmpty;
  }

  int get _attachmentCount {
    var n = _images.length;
    if (_video != null) n += 1;
    if (_audioPath != null) n += 1;
    return n;
  }

  bool get _referencesAttached => _easy && _attachmentCount > 0;

  Future<void> _submit({
    String action = 'song',
    Map<String, dynamic>? extra,
    int? costOverride,
    String? promptOverride,
    bool followUp = false,
  }) async {
    if (_busy) return;
    final cost = costOverride ??
        sunoV6CreditCost(
          action: action,
          stemType: extra?['stem_type']?.toString(),
        );
    if (!AuthService().isSignedIn) {
      final ok = await requireSignIn(context, feature: 'Music');
      if (!ok) return;
    }
    final limit = checkRateLimitForSubmission(1);
    if (limit != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(limit)));
      return;
    }
    if (!UserService().hasEnoughCredits(cost)) {
      if (!mounted) return;
      await _needCredits(cost);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      if (!followUp) {
        _music = null;
        _trackIndex = 0;
      }
    });
    await _stopPlayer();

    try {
      final params = <String, dynamic>{
        'action': action,
        'variant': 'V6',
        ...?extra,
      };

      var prompt = promptOverride ?? _prompt;
      List<String>? imageKeys;
      String? videoKey;

      if (!followUp) {
        if (_sounds) {
          params['sound_loop'] = _soundLoop;
          if (_soundTempo != null) params['sound_tempo'] = _soundTempo;
          if (_soundKey != 'Any') params['sound_key'] = _soundKey;
          params['grab_lyrics'] = false;
          prompt = _idea.text.trim();
          if (prompt.length > 500) prompt = prompt.substring(0, 500);
        } else {
          params['mode'] = _custom ? 'custom' : 'easy';
          if (_instrumental) params['instrumental'] = true;
          final style = _style.text.trim();
          if (style.isNotEmpty) params['style'] = style;
          final lyrics = _lyrics.text.trim();
          if (!_instrumental && lyrics.isNotEmpty) params['lyrics'] = lyrics;
          if (_custom) {
            final title = _title.text.trim();
            if (title.isNotEmpty) params['title'] = title;
          }
          final avoid = _negative.text.trim();
          if (avoid.isNotEmpty) params['negative_tags'] = avoid;
          final hasRef = _easy && _attachmentCount > 0;
          if (!hasRef && _duration != null) params['duration'] = _duration;
          if (!hasRef && !_instrumental && _vocalGender != null) {
            params['vocal_gender'] = _vocalGender;
          }
          if (_persona != null) {
            params['persona_id'] = _persona!.id;
            params['persona_model'] = _persona!.model ?? 'style_persona';
          }
          if (_easy && _useCover && _images.isNotEmpty) {
            final files = <Uint8List>[];
            for (final file in _images.take(5)) {
              files.add(await file.readAsBytes());
            }
            imageKeys = await uploadSunoImages(files);
            params['init_image_r2_keys'] = imageKeys;
          }
          if (_easy && _video != null) {
            videoKey = await uploadSunoVideo(await _video!.readAsBytes());
            params['input_video_r2_key'] = videoKey;
          }
          if (_easy && _audioPath != null) {
            final bytes = await File(_audioPath!).readAsBytes();
            params['reference_audio_r2_key'] = await uploadSunoAudio(
              bytes,
              mime: guessAudioMime(_audioPath!),
            );
          }
        }
      }

      final submitted = await submitSunoV6(
        prompt: prompt,
        params: params,
        imageR2Keys: imageKeys,
        videoR2Key: videoKey,
      );

      final title = _title.text.trim().isNotEmpty
          ? _title.text.trim()
          : (prompt.split('\n').first.trim().isEmpty
              ? await generateFriendlyJobName()
              : prompt.split('\n').first.trim());
      final job = JobModel(
        jobId: submitted.jobId,
        title: title.length > 80 ? '${title.substring(0, 80).trim()}…' : title,
        model: kSunoV6ModelId,
        outputType: action == 'video' ? 'video' : 'audio',
        status: 'processing',
        capabilityId: 'create_music',
        originalPrompt: prompt,
        variations: 1,
        creditsCharged: cost,
        parentJobId: followUp ? _jobId : null,
        settingsSnapshot: sanitizeSettingsSnapshot({
          'prompt': prompt,
          'modelId': kSunoV6ModelId,
          'lyrics': _lyrics.text.trim().isEmpty ? null : _lyrics.text.trim(),
          'style': _style.text.trim().isEmpty ? null : _style.text.trim(),
          'instrumental': _instrumental,
          'vocalGender': _vocalGender,
          'musicAction': action,
          'variant': 'V6',
          'sunoTitle': _title.text.trim().isEmpty ? null : _title.text.trim(),
          'musicMode': _modeName,
          'coverEnabled': !_sounds && _useCover,
          if (!_sounds && _useCover && _images.isNotEmpty)
            'coverPath': _images.first.path,
          if (_negative.text.trim().isNotEmpty)
            'negativePrompt': _negative.text.trim(),
        }),
      );
      await addOrUpdateJob(job);
      recordBatchSubmission(1);
      unawaited(UserService().refreshCredits());

      if (!followUp) _jobId = submitted.jobId;
      _startPolling(submitted.jobId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('SunoFormException: ', '');
      });
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      unawaited(_poll(jobId));
    });
    unawaited(_poll(jobId));
  }

  Future<void> _poll(String jobId) async {
    try {
      final status = await pollSunoV6Job(jobId);
      if (!mounted) return;
      JobModel? existing;
      for (final job in jobListNotifier.value) {
        if (job.jobId == jobId) {
          existing = job;
          break;
        }
      }
      if (existing != null) {
        final updated = existing.copyWith(
          status: status.status == 'completed' || status.status == 'failed'
              ? status.status
              : existing.status,
          downloadUrl: status.downloadUrl ?? existing.downloadUrl,
          music: preferRicherMusic(existing.music, status.music?.toJson()),
        );
        await addOrUpdateJob(updated);
      }
      setState(() {
        if (status.music != null) {
          if (_jobId != null && jobId != _jobId && _music != null) {
            _music = _music!.mergeFollowUp(status.music!);
          } else {
            _music = status.music;
          }
        }
        if (status.music?.persona != null) {
          unawaited(savePersonaLocally(status.music!.persona!));
          _personas = [
            status.music!.persona!,
            ..._personas.where((p) => p.id != status.music!.persona!.id),
          ];
        }
        if (status.music?.hasPlayableTrack == true) {
          _busy = false;
        }
        if (status.status == 'failed') {
          _busy = false;
          _error = status.error ?? 'Generation failed. Credits were refunded.';
          _pollTimer?.cancel();
        }
        if (status.status == 'completed' || status.music?.isComplete == true) {
          _busy = false;
          _pollTimer?.cancel();
        }
      });
      await _ensurePlayer();
    } catch (e) {
      debugPrint('suno poll: $e');
    }
  }

  Future<void> _stopPlayer() async {
    final previous = _player;
    _player = null;
    _playerReady = false;
    _shownPlaying = false;
    _playingUrl = null;
    await previous?.dispose();
  }

  Future<void> _ensurePlayer() async {
    final track = _track;
    final url = track?.playUrl;
    if (url == null) return;
    if (_playingUrl == url && _playerReady) return;
    await _stopPlayer();
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(() {
        final playing = controller.value.isPlaying;
        if (!mounted || playing == _shownPlaying) return;
        setState(() => _shownPlaying = playing);
      });
      setState(() {
        _player = controller;
        _playerReady = true;
        _shownPlaying = false;
        _playingUrl = url;
      });
    } catch (e) {
      debugPrint('suno player: $e');
    }
  }

  Future<void> _needCredits(int cost) async {
    final credits = userCreditsNotifier.value;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Not enough gems',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'This needs $cost gems. You have $credits.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Get gems',
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreditsPage()),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCover() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() {
      _images
        ..clear()
        ..add(file);
      _useCover = true;
    });
  }

  Future<void> _pickVideo() async {
    if (_attachmentCount >= 10) return;
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _video = file);
  }

  Future<void> _pickAudio() async {
    if (_attachmentCount >= 10) return;
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _audioPath = path;
      _audioName = result!.files.single.name;
    });
  }

  Future<void> _singSheet(MusicLyricSheet sheet) async {
    _lyrics.text = sheet.text;
    _title.text = sheet.title;
    _advanced = true;
    _soundsMode = false;
    await _submit(
      action: 'song',
      extra: {
        'mode': 'custom',
        'lyrics': sheet.text,
        if (sheet.title.isNotEmpty) 'title': sheet.title,
        if (_style.text.trim().isNotEmpty) 'style': _style.text.trim(),
      },
      promptOverride: sheet.text,
    );
  }

  Future<void> _followUp(
    String action, {
    Map<String, dynamic>? extra,
    String prompt = '',
  }) async {
    final music = _music;
    final track = _track;
    if (music == null || track == null || music.taskId == null) {
      setState(() => _error = 'Wait until a version is ready.');
      return;
    }
    await _submit(
      action: action,
      promptOverride: prompt,
      extra: {
        'source_task_id': music.taskId,
        'audio_id': track.id,
        ...?extra,
      },
      followUp: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            children: [
              _modeBar(cs),
              const SizedBox(height: 8),
              Text(
                _caption(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 8),
              if (_sounds) _soundsForm(cs) else _songForm(cs),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: cs.error, fontSize: 13)),
              ],
              if (_music != null || _jobId != null) ...[
                const SizedBox(height: 16),
                _livePanel(cs),
              ],
            ],
          ),
        ),
        _footer(cs),
      ],
    );
  }

  void _leaveEasy() {
    _images.clear();
    _video = null;
    _audioPath = null;
    _audioName = null;
    _useCover = false;
  }

  String _caption() {
    if (_sounds) {
      return _advanced
          ? 'Describe the sound. Set the loop, tempo, and key underneath.'
          : 'Describe a sound or a loop.';
    }
    return _advanced
        ? 'Lyrics lead. Add the style, and what to leave out.'
        : 'A song idea is enough. We write the rest.';
  }

  Widget _modeBar(ColorScheme cs) {
    return Column(
      children: [
        _pills(
          cs,
          items: [
            (id: 'easy', label: 'Easy', selected: !_advanced),
            (id: 'advanced', label: 'Advanced', selected: _advanced),
          ],
          onPick: (id) {
            if (_busy) return;
            setState(() {
              final next = id == 'advanced';
              if (next && !_advanced) _leaveEasy();
              _advanced = next;
            });
          },
        ),
        const SizedBox(height: 8),
        _pills(
          cs,
          items: [
            (id: 'song', label: 'Song', selected: !_soundsMode),
            (id: 'sounds', label: 'Sounds', selected: _soundsMode),
          ],
          onPick: (id) {
            if (_busy) return;
            setState(() {
              final sounds = id == 'sounds';
              if (sounds && !_soundsMode) _leaveEasy();
              _soundsMode = sounds;
            });
          },
        ),
      ],
    );
  }

  Widget _choiceCard(
    ColorScheme cs, {
    required String title,
    required String subtitle,
    required bool enabled,
    required String selected,
    required List<(String, String)> options,
    required ValueChanged<String> onPick,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: AppStyles.cardDecoration(cs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final option in options)
                  GestureDetector(
                    onTap: !enabled || _busy ? null : () => onPick(option.$1),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: selected == option.$1
                            ? const LinearGradient(
                                colors: KalaColors.brandGradient,
                              )
                            : null,
                        color: selected == option.$1
                            ? null
                            : cs.surfaceContainerHigh.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected == option.$1
                              ? Colors.transparent
                              : cs.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(
                        option.$2,
                        style: TextStyle(
                          color: selected == option.$1
                              ? Colors.white
                              : cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pills(
    ColorScheme cs, {
    required List<({String id, String label, bool selected})> items,
    required ValueChanged<String> onPick,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onPick(item.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: item.selected
                        ? const LinearGradient(
                            colors: KalaColors.brandGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(AppStyles.radiusMd - 2),
                  ),
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: item.selected ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight:
                          item.selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _songForm(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_easy)
          _field(
            controller: _idea,
            label: 'Song idea',
            hint: 'A hopeful acoustic song about coming home',
            maxLength: 3000,
            minLines: 4,
            maxLines: 8,
          ),
        if (_custom && !_instrumental)
          _field(
            controller: _lyrics,
            label: 'Lyrics',
            hint: '[Verse]\n...\n[Chorus]\n...',
            maxLength: 5000,
            minLines: 8,
            maxLines: 14,
          ),
        if (_custom) ...[
          _field(
            controller: _style,
            label: _instrumental ? 'Prompt' : 'Style',
            hint: _instrumental
                ? 'Style, instruments, mood, and how the song moves'
                : 'Genre or mood',
            maxLength: 1000,
            minLines: _instrumental ? 4 : 2,
            maxLines: 6,
          ),
          _field(
            controller: _negative,
            label: 'Avoid',
            hint: 'What should stay out of the track',
            maxLength: 500,
            minLines: 3,
            maxLines: 5,
          ),
        ],
        if (_easy) _referenceCard(cs),
      ],
    );
  }

  Widget _referenceCard(ColorScheme cs) {
    final clipName = _video?.name.trim();
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
      decoration: AppStyles.cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'References',
            style: TextStyle(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Easy mode. A clip or a track guides the song, and the model then chooses the voice and the length.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 6),
          _referenceRow(
            cs,
            icon: LucideIcons.video,
            title: (clipName == null || clipName.isEmpty) ? 'Video clip' : clipName,
            detail: 'One clip · mp4, mov, or webm · up to 4 min',
            added: _video != null,
            onAdd: _busy ? null : _pickVideo,
            onRemove: _busy ? null : () => setState(() => _video = null),
          ),
          _referenceRow(
            cs,
            icon: LucideIcons.music,
            title: _audioName ?? 'Audio track',
            detail: '6 seconds to 30 minutes',
            added: _audioPath != null,
            onAdd: _busy ? null : _pickAudio,
            onRemove: _busy
                ? null
                : () => setState(() {
                      _audioPath = null;
                      _audioName = null;
                    }),
          ),
        ],
      ),
    );
  }

  Widget _referenceRow(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required String detail,
    required bool added,
    required VoidCallback? onAdd,
    required VoidCallback? onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: added
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 16,
              color: added ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  added ? 'Added' : detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: added ? 'Remove' : 'Add',
            onPressed: added ? onRemove : onAdd,
            icon: Icon(
              added ? LucideIcons.x : LucideIcons.plus,
              size: 16,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverToggle(
    ColorScheme cs,
    void Function(VoidCallback change) refresh,
  ) {
    final cover = _images.isEmpty ? null : _images.first;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: AppStyles.cardDecoration(cs),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _useCover
                      ? cs.primary.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.image,
                  size: 18,
                  color: _useCover ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cover',
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Use a photo as the song cover',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _useCover,
                onChanged: _busy
                    ? null
                    : (on) => refresh(() {
                          _useCover = on;
                          if (!on) _images.clear();
                        }),
              ),
            ],
          ),
          if (_useCover) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: cover == null
                  ? TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await _pickCover();
                              refresh(() {});
                            },
                      icon: const Icon(LucideIcons.imagePlus, size: 16),
                      label: const Text('Add cover'),
                    )
                  : Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            File(cover.path),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  await _pickCover();
                                  refresh(() {});
                                },
                          child: const Text('Change'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => refresh(() {
                                    _images.clear();
                                    _useCover = false;
                                  }),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _soundsForm(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          controller: _idea,
          label: 'Sound',
          hint: 'Rain on a tin roof, a vinyl crackle loop, distant thunder',
          maxLength: 500,
          minLines: 4,
          maxLines: 6,
        ),
        if (_advanced) ...[
          _switchCard(
            cs,
            title: 'Loop',
            subtitle: 'Play the sound as a seamless loop',
            value: _soundLoop,
            onChanged: (v) => setState(() => _soundLoop = v),
          ),
          _menuCard(
            cs,
            label: 'Tempo',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _soundTempo,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Auto')),
                  for (final bpm in [60, 72, 80, 90, 100, 110, 120, 128, 140])
                    DropdownMenuItem(value: bpm, child: Text('$bpm')),
                ],
                onChanged: (v) => setState(() => _soundTempo = v),
              ),
            ),
          ),
          _menuCard(
            cs,
            label: 'Key',
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _soundKey,
                isExpanded: true,
                items: [
                  for (final key in kSunoV6SoundKeys)
                    DropdownMenuItem(value: key, child: Text(key)),
                ],
                onChanged: (v) => setState(() => _soundKey = v ?? 'Any'),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _livePanel(ColorScheme cs) {
    final music = _music;
    final tracks = music?.tracks ?? const <MusicTrack>[];
    return FrostedPane(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (_busy || (_jobId != null && music?.isComplete != true))
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              if (_busy) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  music?.statusLine ?? 'Queued',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (music?.commercialRights == true)
                Text(
                  'Commercial use',
                  style: TextStyle(color: cs.primary, fontSize: 12),
                ),
            ],
          ),
          if (music?.note != null) ...[
            const SizedBox(height: 6),
            Text(music!.note!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
          if (music != null && music.lyrics.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Lyric sheets', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            ...List.generate(music.lyrics.length, (i) {
              final sheet = music.lyrics[i];
              final used = i == music.lyricsUsed;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(sheet.title.isEmpty ? 'Sheet ${i + 1}' : sheet.title),
                subtitle: Text(
                  used ? 'Being sung' : 'Tap to sing this one · 260 gems',
                  style: TextStyle(color: used ? cs.primary : cs.onSurfaceVariant),
                ),
                onTap: used || _busy ? null : () => _singSheet(sheet),
              );
            }),
          ],
          if (tracks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 0; i < tracks.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tracks.length == 2
                          ? (i == 0 ? 'Version A' : 'Version B')
                          : 'Version ${i + 1}'),
                      selected: _trackIndex == i,
                      onSelected: (_) async {
                        setState(() => _trackIndex = i);
                        await _ensurePlayer();
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _playerCard(cs, tracks[_trackIndex.clamp(0, tracks.length - 1)]),
          ],
          if (music != null && music.covers.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final url in music.covers)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(url, width: 72, height: 72, fit: BoxFit.cover),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (music != null && music.stems.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final stem in music.stems)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(stem.name),
                trailing: stem.playUrl == null
                    ? null
                    : const Icon(LucideIcons.download, size: 16),
              ),
          ],
          if (music?.videoUrl != null) ...[
            const SizedBox(height: 8),
            Text('Video ready', style: TextStyle(color: cs.primary)),
          ],
          if (music?.canFollowUp == true) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Make video · 80'),
                  onPressed: _busy ? null : () => _videoSheet(),
                ),
                ActionChip(
                  label: const Text('Stems'),
                  onPressed: _busy ? null : () => _stemsSheet(),
                ),
                ActionChip(
                  label: const Text('Replace · 260'),
                  onPressed: _busy ? null : () => _replaceSheet(),
                ),
                ActionChip(
                  label: const Text('Persona · 40'),
                  onPressed: _busy ? null : () => _personaSheet(),
                ),
                ActionChip(
                  label: const Text('New covers · 40'),
                  onPressed: _busy
                      ? null
                      : () => _followUp('covers', extra: {'audio_id': null}),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _playerCard(ColorScheme cs, MusicTrack track) {
    final playing = _shownPlaying;
    final words = fullerLyrics(track, _music?.lyrics ?? const []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _cover(track, 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  if (track.tags != null)
                    Text(track.tags!, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            IconButton.filled(
              onPressed: !_playerReady
                  ? null
                  : () async {
                      final controller = _player;
                      if (controller == null) return;
                      if (controller.value.isPlaying) {
                        await controller.pause();
                        if (mounted) setState(() => _shownPlaying = false);
                      } else {
                        await controller.play();
                        if (mounted) setState(() => _shownPlaying = true);
                      }
                    },
              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            ),
          ],
        ),
        if (track.isStreaming)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Streaming. The full song replaces this when it is ready.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        AudioPlayClock(
          controller: _player,
          knownDuration: track.knownDuration ?? Duration.zero,
          builder: (context, position, total) {
            final ms = total.inMilliseconds;
            final progress = ms <= 0 ? 0.0 : position.inMilliseconds / ms;
            String clock(Duration value) {
              final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
              final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
              return '$minutes:$seconds';
            }

            return Column(
              children: [
                Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: !_playerReady || ms <= 0
                      ? null
                      : (v) {
                          _player?.seekTo(Duration(milliseconds: (ms * v).round()));
                        },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(clock(position), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    Text(
                      ms <= 0 ? '--:--' : clock(total),
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        if (words != null && words.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  words,
                  maxLines: _lyricsOpen ? null : 8,
                  overflow: _lyricsOpen ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
                ),
                if (words.length > 280)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => setState(() => _lyricsOpen = !_lyricsOpen),
                      child: Text(_lyricsOpen ? 'See less' : 'See all lyrics'),
                    ),
                  ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _openFullPlayer(),
            child: const Text('Open player'),
          ),
        ),
      ],
    );
  }

  void _openFullPlayer() {
    final music = _music;
    if (music == null || music.tracks.isEmpty) return;
    final tracks = audioTracksFromMusic(music, jobId: _jobId ?? '');
    if (tracks.isEmpty) return;
    unawaited(FileService.openAudioTracks(
      context,
      tracks: tracks,
      initialIndex: _trackIndex.clamp(0, tracks.length - 1),
    ));
  }

  Widget _cover(MusicTrack track, double size) {
    final url = track.coverUrl;
    final radius = BorderRadius.circular(12);
    if (url == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: const LinearGradient(colors: KalaColors.brandGradient),
        ),
        child: const Icon(LucideIcons.music, color: Colors.white),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(LucideIcons.music),
        ),
      ),
    );
  }

  String get _modelName {
    for (final model in widget.models) {
      if (model.id == widget.selectedModelId) return model.name;
    }
    return 'Kala HitMaker';
  }

  Widget _footer(ColorScheme cs) {
    final cost = _songCost;
    final enabled = _canSubmit;
    return Container(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 10,
        bottom: 10 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.15)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: _busy ? null : widget.onOpenSettings,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.info,
                    size: 14,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Icon(LucideIcons.cpu, size: 14, color: cs.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _modelName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 14,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Tooltip(
                message: 'Additional Settings',
                child: InkWell(
                  onTap: _busy ? null : widget.onOpenSettings,
                  borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      LucideIcons.settings,
                      size: 20,
                      color: cs.onSurfaceVariant,
                      semanticLabel: 'Additional Settings',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Opacity(
                  opacity: enabled ? 1 : 0.6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: enabled
                            ? KalaColors.brandGradient
                            : [
                                cs.onSurfaceVariant.withValues(alpha: 0.4),
                                cs.onSurfaceVariant.withValues(alpha: 0.3),
                              ],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: enabled
                            ? () => _submit(action: _sounds ? 'sounds' : 'song')
                            : null,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                LucideIcons.sparkles,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _busy ? 'Working' : 'Generate',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Container(
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 10),
                                height: 20,
                                width: 1,
                                color: Colors.white.withValues(alpha: 0.3),
                              ),
                              Icon(
                                LucideIcons.gem,
                                size: 14,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '$cost',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// HitMaker controls inside the shared Additional Settings sheet.
  List<Widget> settingsFields(
    ColorScheme cs,
    VoidCallback refreshSheet,
  ) {
    void refresh(VoidCallback change) {
      setState(change);
      refreshSheet();
    }

    return [
                          if (!_sounds) ...[
                            const SizedBox(height: 16),
                            _switchCard(
                              cs,
                              title: 'Instrumental',
                              subtitle: 'No vocals. Describe the piece instead.',
                              value: _instrumental,
                              onChanged: (v) =>
                                  refresh(() => _instrumental = v),
                            ),
                            if (!_instrumental)
                              _choiceCard(
                                cs,
                                title: 'Voice',
                                subtitle: _referencesAttached
                                    ? 'A reference is attached, so the model chooses the voice.'
                                    : 'A preference. The singer may still vary.',
                                enabled: !_referencesAttached,
                                selected: _vocalGender ?? 'auto',
                                options: const [
                                  ('auto', 'Auto'),
                                  ('female', 'Female'),
                                  ('male', 'Male'),
                                ],
                                onPick: (id) => refresh(
                                  () => _vocalGender = id == 'auto' ? null : id,
                                ),
                              ),
                            _choiceCard(
                              cs,
                              title: 'Length',
                              subtitle: _referencesAttached
                                  ? 'A reference is attached, so the model chooses the length.'
                                  : '10 seconds to 6 minutes. Auto lets the model decide.',
                              enabled: !_referencesAttached,
                              selected: _duration == null ? 'auto' : '$_duration',
                              options: const [
                                ('auto', 'Auto'),
                                ('30', '0:30'),
                                ('60', '1:00'),
                                ('120', '2:00'),
                                ('180', '3:00'),
                                ('240', '4:00'),
                                ('360', '6:00'),
                              ],
                              onPick: (id) => refresh(
                                () => _duration =
                                    id == 'auto' ? null : int.tryParse(id),
                              ),
                            ),
                            if (_custom)
                              _field(
                                controller: _title,
                                label: 'Title',
                                hint: 'Optional. Taken from the first line if empty.',
                                maxLength: 80,
                              ),
                            if (_personas.isNotEmpty)
                              _menuCard(
                                cs,
                                label: 'Persona',
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String?>(
                                    value: _persona?.id,
                                    isExpanded: true,
                                    hint: const Text('None'),
                                    items: [
                                      const DropdownMenuItem(
                                        value: null,
                                        child: Text('None'),
                                      ),
                                      for (final persona in _personas)
                                        DropdownMenuItem(
                                          value: persona.id,
                                          child: Text(persona.name ?? persona.id),
                                        ),
                                    ],
                                    onChanged: (id) => refresh(() {
                                      MusicPersona? next;
                                      for (final persona in _personas) {
                                        if (persona.id == id) {
                                          next = persona;
                                          break;
                                        }
                                      }
                                      _persona = next;
                                    }),
                                  ),
                                ),
                              ),
                            if (_easy) _coverToggle(cs, refresh),
                          ],
    ];
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    int? maxLength,
    int minLines = 1,
    int maxLines = 1,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: AppStyles.cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLength: maxLength,
            minLines: minLines,
            maxLines: maxLines,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.4),
            decoration: InputDecoration(
              isDense: true,
              counterText: '',
              hintText: hint,
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                fontSize: 14,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.45),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.22),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                borderSide: BorderSide(
                  color: cs.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchCard(
    ColorScheme cs, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: AppStyles.cardDecoration(cs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: _busy ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _menuCard(
    ColorScheme cs, {
    required String label,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: AppStyles.cardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child,
        ],
      ),
    );
  }

  Future<void> _videoSheet() async {
    final author = TextEditingController();
    final domain = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Music video · 80 gems'),
              const SizedBox(height: 12),
              TextField(
                controller: author,
                maxLength: 50,
                decoration: const InputDecoration(labelText: 'Artist watermark'),
              ),
              TextField(
                controller: domain,
                maxLength: 50,
                decoration: const InputDecoration(labelText: 'Domain watermark'),
              ),
              GradientButton(
                label: 'Make video · 80',
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
      },
    );
    if (go != true) return;
    await _followUp('video', extra: {
      if (author.text.trim().isNotEmpty) 'author': author.text.trim(),
      if (domain.text.trim().isNotEmpty) 'domain_name': domain.text.trim(),
    });
  }

  Future<void> _stemsSheet() async {
    var type = 'separate_vocal';
    String stemName = kSunoV6StemNames.first;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Separate stems'),
                  RadioListTile(
                    title: const Text('Vocals and accompaniment · 80'),
                    value: 'separate_vocal',
                    groupValue: type,
                    onChanged: (v) => setSheet(() => type = v!),
                  ),
                  RadioListTile(
                    title: const Text('Up to 12 stems · 160'),
                    value: 'split_stem',
                    groupValue: type,
                    onChanged: (v) => setSheet(() => type = v!),
                  ),
                  RadioListTile(
                    title: const Text('One instrument · 120'),
                    value: 'split_stem_advanced',
                    groupValue: type,
                    onChanged: (v) => setSheet(() => type = v!),
                  ),
                  if (type == 'split_stem_advanced')
                    DropdownButton<String>(
                      isExpanded: true,
                      value: stemName,
                      items: [
                        for (final name in kSunoV6StemNames)
                          DropdownMenuItem(value: name, child: Text(name)),
                      ],
                      onChanged: (v) => setSheet(() => stemName = v ?? stemName),
                    ),
                  GradientButton(
                    label:
                        'Separate · ${sunoV6CreditCost(action: 'stems', stemType: type)}',
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (go != true) return;
    await _followUp('stems', extra: {
      'stem_type': type,
      if (type == 'split_stem_advanced') 'stem_name': stemName,
    });
  }

  Future<void> _replaceSheet() async {
    final track = _track;
    if (track == null) return;
    final sourceDuration = track.duration ?? 120;
    final maxRange = sourceDuration / 2;
    var start = 0.0;
    var end = (10.0).clamp(10.0, maxRange);
    final prompt = TextEditingController();
    final section = TextEditingController(text: track.lyrics ?? '');
    final full = TextEditingController(text: track.lyrics ?? '');
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Replace a section · 260 gems'),
                    const SizedBox(height: 8),
                    Text(
                      'At least 10 seconds, and at most half of the song.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    RangeSlider(
                      values: RangeValues(start, end),
                      min: 0,
                      max: sourceDuration,
                      onChanged: (v) {
                        var nextStart = v.start;
                        var nextEnd = v.end;
                        if (nextEnd - nextStart < 10) {
                          nextEnd = nextStart + 10;
                        }
                        if (nextEnd - nextStart > maxRange) {
                          nextEnd = nextStart + maxRange;
                        }
                        setSheet(() {
                          start = nextStart.clamp(0, sourceDuration);
                          end = nextEnd.clamp(0, sourceDuration);
                        });
                      },
                    ),
                    Text('${start.toStringAsFixed(1)}s – ${end.toStringAsFixed(1)}s'),
                    TextField(
                      controller: prompt,
                      decoration: const InputDecoration(
                        labelText: 'What should this passage become?',
                      ),
                    ),
                    TextField(
                      controller: section,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(labelText: 'New section lyrics'),
                    ),
                    TextField(
                      controller: full,
                      minLines: 4,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        labelText: 'Full lyrics after the edit',
                      ),
                    ),
                    const SizedBox(height: 12),
                    GradientButton(
                      label: 'Replace · 260',
                      onPressed: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (go != true) return;
    await _followUp(
      'replace',
      prompt: prompt.text.trim(),
      extra: {
        'title': track.title,
        'tags': track.tags ?? _style.text.trim(),
        'full_lyrics': full.text.trim(),
        'lyrics': section.text.trim(),
        'infill_start_s': start,
        'infill_end_s': end,
        'source_duration': sourceDuration,
      },
    );
  }

  Future<void> _personaSheet() async {
    final name = TextEditingController();
    final description = TextEditingController(text: _style.text.trim());
    var start = 0.0;
    var end = 20.0;
    final duration = _track?.duration ?? 30;
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Save persona · 40 gems'),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  RangeSlider(
                    values: RangeValues(start, end.clamp(start + 10, start + 30)),
                    min: 0,
                    max: duration,
                    onChanged: (v) {
                      var nextStart = v.start;
                      var nextEnd = v.end;
                      if (nextEnd - nextStart < 10) nextEnd = nextStart + 10;
                      if (nextEnd - nextStart > 30) nextEnd = nextStart + 30;
                      setSheet(() {
                        start = nextStart;
                        end = nextEnd;
                      });
                    },
                  ),
                  Text('${start.toStringAsFixed(0)}s – ${end.toStringAsFixed(0)}s'),
                  GradientButton(
                    label: 'Save persona · 40',
                    onPressed: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (go != true || name.text.trim().isEmpty) return;
    await _followUp('persona', extra: {
      'name': name.text.trim(),
      'description': description.text.trim(),
      'style': _style.text.trim(),
      'vocal_start': start.round(),
      'vocal_end': end.round(),
    });
  }
}

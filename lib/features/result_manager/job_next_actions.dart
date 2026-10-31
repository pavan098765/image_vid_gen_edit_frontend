import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/cached_tool_config.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/model_display_name.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/media_upload_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/suno_v6_client.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/tool_launch.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/user_template_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/audio_result_player.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/media_editor/editor_tab_launch.dart';

class JobNextActions extends StatefulWidget {
  final JobModel job;

  const JobNextActions({super.key, required this.job});

  @override
  State<JobNextActions> createState() => _JobNextActionsState();
}

class _JobNextActionsState extends State<JobNextActions> {
  Map<String, dynamic>? _config;
  bool _busy = false;
  bool _optionsOpen = false;
  int _videoVersion = 0;
  int _extendVersion = 0;

  String get _nextActionsLabel {
    final job = widget.job;
    final name = friendlyModelName(job.model) ??
        friendlyModelName(job.settingsSnapshot?['modelId']?.toString());
    if (name == null) return 'Next actions';
    return '$name · Next actions';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await loadCachedToolConfig();
    if (mounted) setState(() => _config = config);
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _cost(String capabilityId, {String? modelId, bool upscale = false}) {
    final config = _config;
    if (config == null) return null;
    return liveCapabilityCost(
      config,
      capabilityId,
      modelId: modelId,
      upscaleEnabled: upscale,
    );
  }

  bool _capEnabled(String id) {
    final config = _config;
    if (config == null) return false;
    final cap = capabilityById(config, id);
    return cap != null && capabilityHasEnabledModel(cap);
  }

  File? get _resultFile {
    final p = widget.job.localFilePath;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  File? get _sourceFile {
    final p = widget.job.inputImagePath;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  String? get _prompt {
    final snap = widget.job.settingsSnapshot?['prompt'] as String?;
    if (snap != null && snap.trim().isNotEmpty) return snap;
    return widget.job.originalPrompt;
  }

  Future<void> _openCapability(
    String capabilityId, {
    List<String> paths = const [],
    String? prompt,
    Map<String, dynamic>? settings,
    bool emptyPrompt = false,
    bool inheritModel = true,
    String? modelId,
    Future<String?>? pendingPrompt,
  }) async {
    final config = _config;
    if (config == null) return;
    final cap = capabilityById(config, capabilityId);
    if (cap == null || !capabilityHasEnabledModel(cap)) return;
    if (!mounted) return;
    await openGenericTool(
      context,
      config: genericConfigFromCapability(
        cap,
        preferredModelId: modelId ??
            (inheritModel
                ? (settings?['modelId'] as String? ?? widget.job.model)
                : null),
      ),
      initialLocalPaths: paths,
      initialPrompt: prompt,
      initialSettings: settings,
      sourceJobId: widget.job.jobId,
      launchTemplateId: widget.job.templateId,
      launchTemplateTitle: widget.job.templateTitle,
      emptyPrompt: emptyPrompt,
      pendingPrompt: pendingPrompt,
    );
  }

  Future<void> _useAgain({required bool afterFailure}) async {
    final cost = _cost(
      widget.job.capabilityId ?? '',
      modelId: widget.job.model,
      upscale: widget.job.settingsSnapshot?['upscaleEnabled'] == true,
    );
    if (afterFailure && mounted && cost != null) {
      final go = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'The failed attempt was refunded. This new one costs $cost credits.',
                    style: TextStyle(color: cs.onSurface, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (go != true) return;
    }

    final capId = widget.job.capabilityId;
    if (capId == null || capId.isEmpty) {
      final resolved = await resolveRecipeLaunch(
        capabilityId: null,
        modelId: widget.job.model,
      );
      if (!mounted) return;
      if (resolved == null) {
        await showModelUnavailableDialog(context);
        return;
      }
      await openGenericTool(
        context,
        config: resolved.config,
        initialLocalPaths: launchPathsFromJob(widget.job),
        initialPrompt: _prompt,
        initialSettings: widget.job.settingsSnapshot,
        sourceJobId: widget.job.jobId,
      );
      return;
    }

    if (!_capEnabled(capId)) {
      if (mounted) await showModelUnavailableDialog(context);
      return;
    }

    await _openCapability(
      capId,
      paths: launchPathsFromJob(widget.job),
      prompt: _prompt,
      settings: widget.job.settingsSnapshot,
    );
  }

  bool _sameHitMakerAudio(String action) {
    return action == 'song' ||
        action == 'extend' ||
        action == 'upload_extend' ||
        action == 'mashup' ||
        action.isEmpty;
  }

  bool get _isMusicJob {
    final job = widget.job;
    if (job.capabilityId == 'create_music' || job.music != null) return true;
    final snap = job.settingsSnapshot?['modelId'];
    final model = snap is String && snap.isNotEmpty ? snap : job.model;
    return model == kSunoV6ModelId ||
        model == 'ace_step_music' ||
        model == 'minimax_music_26' ||
        model.contains('suno') ||
        model.contains('ace_step') ||
        model.contains('minimax_music');
  }

  String? _snapText(String key) {
    final raw = widget.job.settingsSnapshot?[key];
    if (raw is! String) return null;
    final text = raw.trim();
    return text.isEmpty ? null : text;
  }

  int _musicVideoGems() {
    final cap = _config == null ? null : capabilityById(_config!, 'create_music');
    final models = cap?['models'];
    if (models is List) {
      for (final model in models) {
        if (model is! Map || model['id'] != kSunoV6ModelId) continue;
        final costs = model['actionCosts'];
        final video = costs is Map ? costs['video'] : null;
        if (video is num) return video.toInt();
      }
    }
    return 20;
  }

  List<({String taskId, String audioId, String title, int index})>
      _hitMakerVideoTargets() {
    final job = widget.job;
    final snapModel = job.settingsSnapshot?['modelId'];
    final model = snapModel is String && snapModel.isNotEmpty ? snapModel : job.model;
    if (model != kSunoV6ModelId || job.music == null) return const [];
    final music = MusicResult.fromJson(job.music!);
    if (!_sameHitMakerAudio(music.action)) return const [];
    final taskId = music.taskId;
    if (taskId == null || taskId.isEmpty) return const [];
    final targets = <({String taskId, String audioId, String title, int index})>[];
    for (var i = 0; i < music.tracks.length; i++) {
      final track = music.tracks[i];
      if (track.id.isEmpty) continue;
      targets.add((
        taskId: taskId,
        audioId: track.id,
        title: track.title.trim().isEmpty ? 'Version' : track.title.trim(),
        index: i,
      ));
    }
    return targets;
  }

  List<({String audioId, String title, int index, double? duration})>
      _hitMakerExtendTargets() {
    final job = widget.job;
    final snapModel = job.settingsSnapshot?['modelId'];
    final model = snapModel is String && snapModel.isNotEmpty ? snapModel : job.model;
    if (model != kSunoV6ModelId || job.music == null || job.status != 'completed') {
      return const [];
    }
    final music = MusicResult.fromJson(job.music!);
    if (!_sameHitMakerAudio(music.action)) return const [];
    final targets =
        <({String audioId, String title, int index, double? duration})>[];
    for (var i = 0; i < music.tracks.length; i++) {
      final track = music.tracks[i];
      if (track.id.isEmpty) continue;
      targets.add((
        audioId: track.id,
        title: track.title.trim().isEmpty ? 'Version' : track.title.trim(),
        index: i,
        duration: track.duration,
      ));
    }
    return targets;
  }

  Future<void> _extendTrack(
    ({String audioId, String title, int index, double? duration}) target,
  ) async {
    AudioTrackDetails? source;
    for (final track in audioTracksFromJob(widget.job)) {
      if (track.sourceTrackId == target.audioId) {
        source = track;
        break;
      }
    }
    final known = source?.knownDuration;
    final music = widget.job.music == null
        ? null
        : MusicResult.fromJson(widget.job.music!);
    MusicTrack? sung;
    for (final track in music?.tracks ?? const <MusicTrack>[]) {
      if (track.id == target.audioId) {
        sung = track;
        break;
      }
    }
    final copiedStyle = _snapText('style') ?? sung?.tags?.trim() ?? '';
    final sourceLyrics = sung == null
        ? (_snapText('lyrics') ?? '')
        : (fullerLyrics(sung, music?.lyrics ?? const <MusicLyricSheet>[]) ??
            _snapText('lyrics') ??
            '');
    final instrumental = music?.instrumental == true ||
        widget.job.settingsSnapshot?['instrumental'] == true;
    final choice = await showModalBottomSheet<_ExtendChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ExtendTrackSheet(
        versionLabel: audioVersionLabel(target.index),
        title: target.title,
        filePath: source?.filePath ?? '',
        networkUrl: source?.networkUrl,
        durationSeconds: target.duration ??
            (known == null ? null : known.inMilliseconds / 1000),
        style: copiedStyle,
        sourceLyrics: sourceLyrics,
        instrumental: instrumental,
      ),
    );
    if (choice == null || !mounted) return;
    final song = widget.job;
    final params = <String, dynamic>{
      'action': 'extend',
      'audio_id': target.audioId,
      'title': target.title,
    };
    final style = choice.style.trim();
    if (style.isNotEmpty) params['style'] = style;
    final trimmed = choice.lyrics.trim();
    if (trimmed.isNotEmpty && !instrumental) params['lyrics'] = trimmed;
    final duration = choice.durationSeconds ?? target.duration;
    if (duration != null && duration > 1 && choice.continueAt > 0) {
      params['source_duration'] = duration;
      final latest = choice.continueAt >= duration
          ? duration - 0.5
          : choice.continueAt;
      params['continue_at'] = latest < 0.5 ? 0.5 : latest;
    }
    try {
      final result = await submitSunoV6(
        prompt: trimmed,
        params: params,
      );
      final created = JobModel(
        jobId: result.jobId,
        title: await generateFriendlyJobName(),
        model: kSunoV6ModelId,
        outputType: 'audio',
        status: 'processing',
        capabilityId: 'create_music',
        parentJobId: song.jobId,
        originalPrompt: trimmed.isEmpty ? _prompt : trimmed,
        creditsCharged: 65,
        settingsSnapshot: {
          'modelId': kSunoV6ModelId,
          'action': 'extend',
          'musicAction': 'extend',
          'audio_id': target.audioId,
          if (trimmed.isNotEmpty) 'lyrics': trimmed,
          if (style.isNotEmpty) 'style': style,
        },
      );
      await addOrUpdateJob(created);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Extension added to Creations.')),
      );
    } on SunoFormException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _createMusicVideo(
    ({String taskId, String audioId, String title, int index}) target,
  ) async {
    final song = widget.job;
    try {
      final result = await submitSunoV6(
        prompt: _prompt ?? target.title,
        params: {
          'action': 'video',
          'source_task_id': target.taskId,
          'audio_id': target.audioId,
        },
      );
      final created = JobModel(
        jobId: result.jobId,
        title: await generateFriendlyJobName(),
        model: kSunoV6ModelId,
        outputType: 'video',
        status: 'processing',
        capabilityId: 'create_music',
        parentJobId: song.jobId,
        originalPrompt: _prompt,
        creditsCharged: _musicVideoGems(),
        settingsSnapshot: {
          'modelId': kSunoV6ModelId,
          'action': 'video',
          'musicAction': 'video',
          'source_task_id': target.taskId,
          'audio_id': target.audioId,
          if (_prompt != null) 'prompt': _prompt,
        },
      );
      await addOrUpdateJob(created);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Music video added to Creations.')),
      );
    } on SunoFormException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _remixTrack() async {
    final file = _resultFile;
    if (file == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Save the song first, then remix it.')),
      );
      return;
    }
    final job = widget.job;
    final music = job.music == null ? null : MusicResult.fromJson(job.music!);
    final sheets = music?.lyrics ?? const <MusicLyricSheet>[];
    String? lyrics = _snapText('lyrics');
    for (final track in music?.tracks ?? const <MusicTrack>[]) {
      final text = fullerLyrics(track, sheets);
      if (text != null && text.length > (lyrics?.length ?? 0)) lyrics = text;
    }
    if (!mounted) return;
    await openMusicRemix(
      context,
      filePath: file.path,
      prompt: _prompt,
      lyrics: lyrics,
      modelId: job.model,
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final cs = Theme.of(context).colorScheme;
    final result = _resultFile;
    final expired = job.showsCloudExpiry;

    if (job.status == 'failed') {
      final amount = job.creditsCharged;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              amount != null
                  ? "This didn't finish. $amount credits were returned."
                  : "This didn't finish. Failed jobs are refunded.",
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            if (_prompt != null || _sourceFile != null) ...[
              const SizedBox(height: 8),
              _chip(
                cs,
                icon: Icons.refresh_rounded,
                label: 'Try again',
                detail: job.creditsCharged != null
                    ? '${_cost(job.capabilityId ?? '', modelId: job.model) ?? '—'} gems'
                    : null,
                onTap: () => _guard(() => _useAgain(afterFailure: true)),
              ),
            ],
          ],
        ),
      );
    }

    if (job.status != 'completed') return const SizedBox.shrink();

    if (expired) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.job.usesKieCloud
                  ? 'The cloud copy expired after 14 days on server then deleted.'
                  : 'The cloud copy expired after 24 hours on server then deleted.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            if (_isMusicJob) ...[
              const SizedBox(height: 8),
              _chip(
                cs,
                icon: Icons.library_music_outlined,
                label: 'Remix',
                onTap: () => _guard(_remixTrack),
              ),
            ],
            if (_prompt != null || _sourceFile != null) ...[
              const SizedBox(height: 8),
              Text('New generation',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              const SizedBox(height: 6),
              _chip(
                cs,
                icon: Icons.refresh_rounded,
                label: 'Regenerate',
                detail:
                    '${_cost(job.capabilityId ?? '', modelId: job.model) ?? '—'} gems',
                onTap: () => _guard(() => _useAgain(afterFailure: false)),
              ),
            ],
          ],
        ),
      );
    }

    final musicJob = _isMusicJob;
    if (result == null && !musicJob) return const SizedBox.shrink();

    final rows = <Widget>[];

    if (musicJob) {
      rows.add(_aiRow(
        cs,
        icon: Icons.library_music_outlined,
        label: 'Remix',
        onTap: () => _guard(_remixTrack),
      ));
      final videos = _hitMakerVideoTargets();
      final gems = _musicVideoGems();
      if (videos.isNotEmpty) {
        final picked = _versionIndex(_videoVersion, videos.length);
        rows.add(_aiRow(
          cs,
          icon: Icons.movie_creation_outlined,
          label: 'Create music video',
          detail: '$gems gems',
          versions: [for (final target in videos) audioVersionLabel(target.index)],
          versionIndex: picked,
          onVersion: (index) => setState(() => _videoVersion = index),
          onTap: () => _guard(() => _createMusicVideo(videos[picked])),
        ));
      }
      final extensions = _hitMakerExtendTargets();
      if (extensions.isNotEmpty) {
        final picked = _versionIndex(_extendVersion, extensions.length);
        rows.add(_aiRow(
          cs,
          icon: Icons.queue_music_rounded,
          label: 'Extend',
          detail: '65 gems',
          versions: [
            for (final target in extensions) audioVersionLabel(target.index),
          ],
          versionIndex: picked,
          onVersion: (index) => setState(() => _extendVersion = index),
          onTap: () => _guard(() => _extendTrack(extensions[picked])),
        ));
      }
    }

    if (job.isImageOutput && result != null) {
      rows.add(_aiRow(
        cs,
        icon: Icons.edit_rounded,
        label: 'Edit in Editor',
        onTap: () => _openInEditorTab(image: result),
      ));

      if (_capEnabled('upscale')) {
        final c = _cost('upscale');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.hd_rounded, label: 'Upscale', detail: '$c gems', onTap: () {
            _guard(() => _openCapability('upscale', paths: [result.path]));
          }));
        }
      }
      if (_capEnabled('remove_background')) {
        final c = _cost('remove_background');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.auto_fix_high_rounded, label: 'Remove background', detail: '$c gems', onTap: () {
            _guard(() =>
                _openCapability('remove_background', paths: [result.path]));
          }));
        }
      }
      if (_capEnabled('animate_image')) {
        final c = _cost('animate_image');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.play_circle_outline_rounded, label: 'Animate', detail: '$c gems', onTap: () {
            _guard(() => _openCapability('animate_image',
                paths: [result.path], prompt: ''));
          }));
        }
      }
      if (_capEnabled('edit_image')) {
        final c = _cost('edit_image');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.palette_outlined, label: 'Another style', detail: '$c gems', onTap: () {
            _guard(() => _openCapability(
                  'edit_image',
                  paths: [result.path],
                  emptyPrompt: true,
                ));
          }));
        }
      }
    } else if (job.isVideoOutput && result != null) {
      rows.add(_aiRow(
        cs,
        icon: Icons.movie_creation_outlined,
        label: 'Edit in Editor',
        onTap: () => _openInEditorTab(videoPath: result.path),
      ));
      final source = _sourceFile;
      if (source != null &&
          pathLooksLikeImage(source.path) &&
          _capEnabled('edit_image')) {
        final c = _cost('edit_image');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.photo_outlined, label: 'Use the photo', detail: '$c gems', onTap: () {
            _guard(() => _openCapability('edit_image', paths: [source.path]));
          }));
        }
      }
    }

    final againCost = _cost(job.capabilityId ?? '', modelId: job.model);
    if (job.capabilityId != null || job.model.isNotEmpty) {
      rows.add(_aiRow(
        cs,
        icon: Icons.refresh_rounded,
        label: 'Regenerate',
        detail: againCost != null ? '$againCost gems' : null,
        onTap: () => _guard(() => _useAgain(afterFailure: false)),
      ));
    }

    final canSaveSetup = _prompt != null && _prompt!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _optionsOpen = !_optionsOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _nextActionsLabel,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      _optionsOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_optionsOpen) ...[
            const SizedBox(height: 10),
            ...rows,
            if (canSaveSetup)
              TextButton(
                onPressed: _saveSetup,
                child: const Text('Save setup'),
              ),
          ],
        ],
      ),
    );
  }

  int _versionIndex(int selected, int length) {
    if (length <= 0) return 0;
    if (selected < 0 || selected >= length) return 0;
    return selected;
  }

  void _runRow(VoidCallback onTap) {
    if (_busy) return;
    HapticFeedback.lightImpact();
    onTap();
  }

  Widget _versionMenu({
    required ColorScheme cs,
    required List<String> versions,
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    final label = selected >= 0 && selected < versions.length
        ? versions[selected]
        : versions.first;
    return PopupMenuButton<int>(
      initialValue: selected,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (var index = 0; index < versions.length; index++)
          PopupMenuItem<int>(
            value: index,
            height: 40,
            child: Text(versions[index]),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 16, color: cs.primary),
          ],
        ),
      ),
    );
  }

  Widget _aiRow(
    ColorScheme cs, {
    required String label,
    required VoidCallback onTap,
    required IconData icon,
    String? detail,
    List<String> versions = const [],
    int versionIndex = 0,
    ValueChanged<int>? onVersion,
  }) {
    final showVersion = versions.length > 1 && onVersion != null;
    final action = _busy ? null : () => _runRow(onTap);
    final title = Text(
      label,
      style: TextStyle(
        color: cs.onSurface,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    );
    final gems = detail == null
        ? null
        : Text(
            detail,
            style: TextStyle(
              color: cs.primary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          );
    final mark = Icon(
      Icons.chevron_right_rounded,
      size: 18,
      color: cs.onSurfaceVariant,
    );
    final leading = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 16, color: cs.primary),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: action,
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: 12),
                      Expanded(child: title),
                    ],
                  ),
                ),
              ),
              if (showVersion) ...[
                const SizedBox(width: 8),
                _versionMenu(
                  cs: cs,
                  versions: versions,
                  selected: versionIndex,
                  onSelected: onVersion,
                ),
              ],
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: action,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (gems != null) ...[
                      const SizedBox(width: 8),
                      gems,
                    ],
                    mark,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(
    ColorScheme cs, {
    required String label,
    required VoidCallback onTap,
    IconData icon = Icons.arrow_forward_rounded,
    String? detail,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _busy
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  detail == null ? label : '$label · $detail',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openInEditorTab({File? image, String? videoPath}) {
    final previousTab = selectedIndexNotifier.value;
    requestEditorTabLaunch(
      image: image,
      videoPath: videoPath,
      historyId: widget.job.jobId,
      jobId: widget.job.jobId,
      returnToResultManager: true,
      restoreTabIndex: previousTab,
    );
    selectedIndexNotifier.value = AppTabs.editor;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _saveSetup() async {
    final nameController = TextEditingController(
      text: widget.job.templateTitle ?? widget.job.title,
    );
    nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: nameController.text.length,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surface,
          title: Text('Save setup', style: TextStyle(color: cs.onSurface)),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || nameController.text.trim().isEmpty) return;
    await appendUserTemplateRecord(
      UserTemplateRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameController.text.trim(),
        prompt: _prompt ?? '',
        modelId: widget.job.model,
        capabilityId: widget.job.capabilityId,
        toolTitle: widget.job.templateTitle,
        settings: settingsFromJobSnapshot(widget.job.settingsSnapshot),
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Setup saved')),
    );
  }
}

class _ExtendChoice {
  final double continueAt;
  final double? durationSeconds;
  final String style;
  final String lyrics;

  const _ExtendChoice({
    required this.continueAt,
    required this.durationSeconds,
    required this.style,
    required this.lyrics,
  });
}

class _ExtendTrackSheet extends StatefulWidget {
  const _ExtendTrackSheet({
    required this.versionLabel,
    required this.title,
    required this.filePath,
    required this.networkUrl,
    required this.durationSeconds,
    required this.style,
    required this.sourceLyrics,
    required this.instrumental,
  });

  final String versionLabel;
  final String title;
  final String filePath;
  final String? networkUrl;
  final double? durationSeconds;
  final String style;
  final String sourceLyrics;
  final bool instrumental;

  @override
  State<_ExtendTrackSheet> createState() => _ExtendTrackSheetState();
}

class _ExtendTrackSheetState extends State<_ExtendTrackSheet> {
  final AudioPlayer _player = AudioPlayer();
  late final TextEditingController _style;
  final TextEditingController _lyrics = TextEditingController();
  bool _writingLyrics = false;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _positionSub;
  double? _duration;
  double _continueAt = 1;
  bool _ready = false;
  bool _scrubbing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _style = TextEditingController(text: widget.style);
    _lyrics.addListener(_onLyricsChanged);
    final known = widget.durationSeconds;
    if (known != null && known > 1) {
      _duration = known;
      _continueAt = known - 1;
    }
    _stateSub = _player.playerStateStream.listen((_) {
      if (mounted) setState(() {});
    });
    _positionSub = _player.positionStream.listen((position) {
      if (!mounted || _scrubbing || !_ready || !_player.playing) return;
      final seconds = position.inMilliseconds / 1000;
      final length = _duration;
      if (length != null && seconds > length) return;
      if ((seconds - _continueAt).abs() < 0.35) return;
      setState(() => _continueAt = seconds);
    });
    unawaited(audioNowPlaying.pause());
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final path = widget.filePath;
      Duration? loaded;
      if (path.isNotEmpty && File(path).existsSync()) {
        loaded = await _player.setFilePath(path);
      } else {
        final url = widget.networkUrl;
        if (url == null || url.isEmpty) {
          throw StateError('This version has no audio yet.');
        }
        loaded = await _player.setUrl(url);
      }
      if (!mounted) return;
      final seconds = (loaded ?? _player.duration)?.inMilliseconds;
      final length = seconds == null || seconds <= 0
          ? _duration
          : seconds / 1000;
      setState(() {
        _duration = length;
        if (length != null && length > 1) {
          _continueAt = length - 1;
        }
        _ready = length != null && length > 1;
        _error = _ready ? null : 'Could not read the song length.';
      });
      if (_ready && _duration != null) {
        await _player.seek(Duration(milliseconds: (_continueAt * 1000).round()));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not play this audio');
    }
  }

  void _onLyricsChanged() {
    if (mounted) setState(() {});
  }

  String _tail(String text, int max) {
    final clean = text.trim();
    if (clean.length <= max) return clean;
    return clean.substring(clean.length - max);
  }

  String _continuationRequest() {
    final draft = _tail(_lyrics.text, 1200);
    final source = widget.sourceLyrics.trim();
    if (draft.isEmpty) return _tail(source, 4000);
    const header = 'Song so far:\n';
    const note = '\n\nNext section note:\n';
    final room = 4000 - header.length - note.length - draft.length;
    final kept = _tail(source, room > 200 ? room : 200);
    if (kept.isEmpty) return draft;
    return '$header$kept$note$draft';
  }

  Future<void> _continueLyrics() async {
    if (_writingLyrics || widget.instrumental) return;
    setState(() => _writingLyrics = true);
    try {
      final token = await AuthService().getIdToken();
      if (!mounted) return;
      if (token == null || token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to continue the lyrics.')),
        );
        return;
      }
      final style = _style.text.trim();
      final (next, error, _) = await MediaUploadService.suggestPrompt(
        baseUrl: kSunoV6ControllerUrl,
        authToken: token,
        modelId: kSunoV6ModelId,
        field: 'extend_lyrics',
        text: _continuationRequest(),
        context: {
          if (style.isNotEmpty) 'style': style,
          if (widget.title.trim().isNotEmpty) 'title': widget.title.trim(),
        },
      );
      if (!mounted) return;
      final lines = next?.trim() ?? '';
      if (lines.isEmpty || !lines.contains('[') || !lines.contains(']')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Could not write the next lines.')),
        );
        return;
      }
      _lyrics.text = lines;
      setState(() {});
    } finally {
      if (mounted) setState(() => _writingLyrics = false);
    }
  }

  String _clock(double seconds) {
    final total = seconds.round().clamp(0, 86400);
    final minutes = total ~/ 60;
    final remain = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$remain';
  }

  @override
  void dispose() {
    unawaited(_stateSub?.cancel());
    unawaited(_positionSub?.cancel());
    _lyrics.removeListener(_onLyricsChanged);
    _style.dispose();
    _lyrics.dispose();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final length = _duration;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.92 - bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Material(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: sheetHeight > 240 ? sheetHeight : 240),
            child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Extend ${widget.versionLabel}',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    IconButton(
                      onPressed: !_ready
                          ? null
                          : () async {
                              if (_player.playing) {
                                await _player.pause();
                              } else {
                                await _player.play();
                              }
                              if (mounted) setState(() {});
                            },
                      icon: Icon(
                        _player.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: length == null || length <= 1 ? 1 : length,
                        value: length == null || length <= 1
                            ? 0
                            : _continueAt.clamp(0, length - 0.5).toDouble(),
                        onChanged: !_ready || length == null
                            ? null
                            : (value) {
                                _scrubbing = true;
                                setState(() => _continueAt = value);
                              },
                        onChangeEnd: (value) {
                          _scrubbing = false;
                          unawaited(
                            _player.seek(
                              Duration(milliseconds: (value * 1000).round()),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                Text(
                  length == null
                      ? 'Finding the song length'
                      : 'Continue from ${_clock(_continueAt)} of ${_clock(length)}',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!, style: TextStyle(color: colors.error, fontSize: 12)),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _style,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Style',
                    hintText: 'Same style as this song',
                  ),
                ),
                if (!widget.instrumental) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _writingLyrics ? null : _continueLyrics,
                      icon: _writingLyrics
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(
                        _lyrics.text.trim().isEmpty
                            ? 'Continue the lyrics'
                            : 'Rewrite the next lines',
                      ),
                    ),
                  ),
                  TextField(
                    controller: _lyrics,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Lyrics',
                      hintText: 'Optional. The next section of the song.',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        _ExtendChoice(
                          continueAt: _continueAt,
                          durationSeconds: _duration,
                          style: _style.text,
                          lyrics: widget.instrumental ? '' : _lyrics.text,
                        ),
                      ),
                      child: const Text('Extend · 65'),
                    ),
                  ],
                ),
              ],
            ),
            ),
          ),
        ),
      ),
    );
  }
}

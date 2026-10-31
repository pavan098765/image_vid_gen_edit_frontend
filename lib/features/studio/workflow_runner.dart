import 'asset_use.dart';
import 'studio_director.dart';
import 'workflow_models.dart';
import 'workflow_quote.dart';
import 'workflow_rules.dart';

class WorkflowRunner {
  int submitCalls = 0;

  void ensureCanStart(WorkflowSpec spec, List<String> files) {
    if (spec.requiresFiles && files.isEmpty) {
      throw StateError('Add a video to start. A photo can come along as the look.');
    }
  }

  FilmDraft applyShots(FilmDraft draft, WorkflowSpec spec, List<ShotCard> shots) {
    draft.shots = shots;
    draft.lock = shots.map((s) => s.lock.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => draft.lock);
    for (final shot in draft.shots) {
      if (shot.lock.trim().isEmpty) shot.lock = draft.lock;
    }
    ensureVoiceLock(draft);
    ensureLookAnchors(draft);
    bindAssets(draft);
    _writePrompts(draft, spec);
    for (final shot in draft.shots) {
      if (shot.kind == 'image') shot.pushIn = true;
    }
    final reasons = [
      ...checkHook(draft.shots),
      ...checkShots(draft.shots, speechTrack: _hasSpeech(spec, draft)),
      ...checkSpokenLength(draft.shots, draft.durationSeconds),
      ...checkClaims(draft.shots, draft.findings),
      ...checkProduct(draft),
    ];
    if (reasons.isNotEmpty) draft.error = reasons.first;
    draft.stage = 'outline';
    return draft;
  }

  FilmQuote quote(FilmDraft draft, WorkflowSpec spec, CostTable costs) {
    final looks = draft.assets.where((a) => a.isMade && (a.r2Key ?? '').isEmpty).toList();
    return priceFilm(
      shots: draft.shots,
      costs: costs,
      speechTasks: speechTaskCount(spec, draft),
      music: draft.music && spec.music,
      musicBeds: musicBedCount(draft.durationSeconds, draft.music && spec.music),
      sfxCount: spec.sfx,
      lookGems: looks.length * costs.imageCost,
      lookLabel: _lookLabel(looks),
    );
  }

  String _lookLabel(List<UserAsset> looks) {
    final roles = looks.map((a) => a.role).toSet();
    if (roles.contains('character') && roles.contains('background')) return 'Character & set';
    if (roles.contains('character')) return 'Character';
    if (roles.contains('background')) return 'Set';
    return 'Look';
  }

  /// Builds the job list. Does not talk to the network.
  List<Map<String, dynamic>> jobsFor(FilmDraft draft, WorkflowSpec spec) {
    if (draft.stage != 'outline' && draft.stage != 'generating') {
      throw StateError('Accept the outline before making the film.');
    }
    ensureLookAnchors(draft);
    bindAssets(draft);
    final jobs = <Map<String, dynamic>>[];
    for (final asset in draft.assets.where((a) => a.isMade && a.prompt.trim().isNotEmpty && (a.r2Key ?? '').isEmpty)) {
      jobs.add({
        'model': 'qwen2_1_t2i',
        'prompt': asset.prompt,
        'shotId': 'anchor:${asset.path}',
      });
    }
    for (final shot in draft.shots.where((s) => !s.dropped && s.kind != 'user')) {
      if (shot.kind == 'video') {
        if (shot.makeKeyframe) {
          jobs.add({
            'model': 'qwen2_1_t2i',
            'prompt': shot.stillPrompt ?? shot.action,
            'shotId': 'key:${shot.id}',
          });
        }
        jobs.add({
          'model': shot.model.startsWith('ltx') ? 'ltx25_int8_t2v' : 'minimax_h3',
          'prompt': shot.videoPrompt ?? '',
          'shotId': shot.id,
        });
      } else {
        jobs.add({
          'model': 'qwen2_1_t2i',
          'prompt': shot.stillPrompt ?? shot.action,
          'shotId': shot.id,
        });
      }
    }
    if (speechTaskCount(spec, draft) > 0) {
      final chapters = draft.shots
          .where((s) => !s.dropped && s.line.trim().isNotEmpty && isNarrationLine(s))
          .map((s) => s.chapter)
          .toSet();
      for (final chapter in chapters) {
        final lines = draft.shots
            .where((s) => !s.dropped && s.chapter == chapter && s.line.trim().isNotEmpty && isNarrationLine(s))
            .map((s) => s.line)
            .join('\n');
        if (lines.trim().isEmpty) continue;
        jobs.add({
          'model': 'gemini_tts',
          'prompt': lines,
          'shotId': 'voice:$chapter',
        });
      }
    }
    if (draft.music && spec.music) {
      final beds = spec.id == 'song_video' ? 1 : musicBedCount(draft.durationSeconds, true);
      final musicJobs = <Map<String, dynamic>>[];
      for (var i = 0; i < beds; i++) {
        musicJobs.add({
          'model': 'suno_music',
          'prompt': spec.id == 'song_video' && draft.lyrics.trim().isNotEmpty ? draft.lyrics.trim() : spec.title,
          'shotId': i == 0 ? 'music' : 'music:${i + 1}',
        });
      }
      if (spec.id == 'song_video') {
        jobs.insertAll(0, musicJobs);
      } else {
        jobs.addAll(musicJobs);
      }
    }
    if (spec.sfx > 0) {
      jobs.add({'model': 'suno_sfx', 'prompt': sfxPrompt(spec.id), 'shotId': 'sfx'});
    }
    return jobs;
  }

  void _writePrompts(FilmDraft draft, WorkflowSpec spec) {
    final speech = _hasSpeech(spec, draft);
    final live = draft.shots.where((s) => !s.dropped).toList();
    var heard = 0;
    for (final shot in draft.shots) {
      if (shot.kind == 'user') {
        shot.stillPrompt = null;
        shot.videoPrompt = null;
        continue;
      }
      final reference = assetPrompt(draft, shot);
      final guides = guideAssets(draft, shot);
      final last = live.isNotEmpty && live.last.id == shot.id;
      if (shot.kind == 'video') {
        if (spec.id == 'song_video') {
          shot.durationSeconds = shot.durationSeconds.clamp(4, 10);
        }
        shot.model = chooseVideoModel(draft, shot, spec);
        shot.quality = draft.finish == 'finest' ? 'full_refine' : _tierFor(shot, live);
        final index = live.indexWhere((card) => card.id == shot.id);
        final previous = index > 0 ? live[index - 1] : null;
        shot.continuesFrom = _continuesFrom(draft, shot, previous);
        shot.makeKeyframe = shot.model.startsWith('ltx') || shot.quality == 'full_refine';
        shot.stillPrompt = shot.makeKeyframe
            ? composeKeyframePrompt(action: shot.action, lock: shot.lock, guides: guides)
            : null;
        shot.audioInSeconds = heard;
        heard += shot.durationSeconds;
        final next = index >= 0 && index + 1 < live.length ? live[index + 1] : null;
        final arrive = next != null && next.kind == 'video' && (spec.chainEndFrames || sharesSet(draft, shot, next));
        final sound = soundFor(spec.id, clipAudioIsMain: spec.clipAudioIsMain, lastShot: last);
        shot.videoPrompt = isNarrationLine(shot)
            ? worldVideoPrompt(
                lock: shot.lock,
                action: shot.model.startsWith('ltx') ? 'Camera: ${shot.action.trim()}' : shot.action,
                sound: sound,
                speechTrack: speech,
                reference: reference,
              )
            : performedClipPrompt(
                shot: shot,
                sound: sound,
                reference: reference,
                arriveOnEnd: arrive,
              );
        if (!shot.model.startsWith('ltx') && shot.durationSeconds > 15) {
          shot.durationSeconds = 15;
        }
      } else {
        shot.stillPrompt = [
          composeKeyframePrompt(action: shot.action, lock: shot.lock, guides: guides),
          shot.onScreen.trim(),
        ].where((s) => s.isNotEmpty).join('\n');
        shot.videoPrompt = null;
      }
    }
  }

  void applyEditPlan(FilmDraft draft, Map<String, dynamic> plan) {
    draft.editPlan = plan;
    final lead = ((plan['leadIn'] as List?) ?? const []).map((e) => e.toString()).toSet();
    final push = plan['pushIn'];
    final pushIds = push is List ? push.map((e) => e.toString()).toSet() : null;
    for (final shot in draft.shots) {
      if (lead.contains(shot.id)) shot.leadIn = true;
      if (pushIds != null) shot.pushIn = pushIds.contains(shot.id);
    }
    final reasons = checkEditPlan(plan, draft.durationSeconds);
    if (reasons.isNotEmpty) draft.error = reasons.first;
  }

  String _tierFor(ShotCard shot, List<ShotCard> live) {
    final index = live.indexWhere((card) => card.id == shot.id);
    final chapter = shot.chapter.toLowerCase();
    final hero = index <= 0 ||
        index == live.length - 1 ||
        chapter.contains('turn') ||
        chapter.contains('last') ||
        chapter.contains('claim');
    return hero ? 'full_refine' : 'fast_refine';
  }

  String? _continuesFrom(FilmDraft draft, ShotCard shot, ShotCard? previous) {
    if (previous == null || previous.kind != 'video' || shot.kind != 'video') return null;
    if (previous.chapter != shot.chapter) return null;
    if (!sharesSet(draft, previous, shot)) return null;
    return previous.id;
  }

  bool _hasSpeech(WorkflowSpec spec, FilmDraft draft) {
    if (spec.speech == 'none') return false;
    if (spec.speech == 'optional' && !draft.narratorOn) return false;
    return true;
  }
}

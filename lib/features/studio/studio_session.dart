import 'dart:async';

import 'package:flutter/foundation.dart';

import 'asset_use.dart';
import 'gemini_client.dart';
import 'studio_director.dart';
import 'studio_jobs.dart';
import 'studio_media.dart';
import 'studio_store.dart';
import 'studio_submit.dart';
import 'workflow_models.dart';
import 'workflow_quote.dart';
import 'workflow_rules.dart';
import 'workflow_runner.dart';
import 'workflow_steps.dart';

class StudioSession extends ChangeNotifier {
  StudioSession({
    WorkflowRunner? runner,
    GeminiDirector? director,
    StudioSubmit? submit,
    StudioDraftStore? store,
    StudioJobClient? jobs,
    StudioMedia? media,
    CostTable? costs,
  })  : _runner = runner ?? WorkflowRunner(),
        _director = director ?? GeminiDirector(),
        _submit = submit ?? StudioSubmit(),
        _store = store ?? StudioDraftStore(),
        _jobs = jobs ?? StudioJobClient(),
        _media = media ?? StudioMedia(),
        costs = costs ?? const CostTable() {
    _steps = CreativeSteps(_director);
  }

  final WorkflowRunner _runner;
  final GeminiDirector _director;
  final StudioSubmit _submit;
  final StudioDraftStore _store;
  final StudioJobClient _jobs;
  final StudioMedia _media;
  final CostTable costs;
  late final CreativeSteps _steps;
  Timer? _poll;

  List<String> pendingFiles = const [];
  WorkflowSpec? spec;
  FilmDraft? draft;
  FilmQuote? quote;
  bool busy = false;
  String? message;
  int? pickedAngle;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void open(WorkflowSpec next) {
    spec = next;
    draft = null;
    quote = null;
    message = null;
    pickedAngle = null;
    notifyListeners();
  }

  void restore(FilmDraft film) {
    draft = film;
    pickedAngle = film.chosenAngle;
    if (film.shots.isNotEmpty && spec != null) {
      quote = _runner.quote(film, spec!, costs);
    }
    if (film.stage == 'generating') _ensureWatch();
    notifyListeners();
  }

  Future<void> begin({
    required String topic,
    required int durationSeconds,
    required String aspect,
    required String language,
    required bool captions,
    required bool music,
    required bool narratorOn,
    required List<String> files,
    String? carryLock,
    String videoEngine = 'auto',
    List<({String path, String role, String label})>? labeledFiles,
    List<UserAsset>? preparedAssets,
    String musicNote = '',
    String voiceHint = '',
    String lyrics = '',
  }) async {
    final current = spec;
    if (current == null) return;
    final paths = preparedAssets?.map((asset) => asset.path).toList() ??
        labeledFiles?.map((file) => file.path).toList() ??
        files;
    try {
      _runner.ensureCanStart(current, paths);
    } catch (e) {
      message = 'Add at least one clip to start.';
      notifyListeners();
      return;
    }
    final voice = voiceHint.trim();
    draft = FilmDraft(
      id: 'film_${DateTime.now().millisecondsSinceEpoch}',
      workflowId: current.id,
      topic: topic.trim(),
      durationSeconds: durationSeconds,
      aspect: aspect,
      language: language,
      captions: captions,
      music: music,
      narratorOn: narratorOn,
      filePaths: paths,
      lock: carryLock ?? '',
      stage: 'research',
      assets: preparedAssets ??
          (labeledFiles == null ? classifyAssets(paths) : assetsFromLabels(labeledFiles)),
      videoEngine: videoEngine,
      musicNote: musicNote.trim(),
      lyrics: lyrics.trim(),
      voiceLock: voice,
      voicePinned: voice.isNotEmpty,
    );
    await _readAssets();
    message = null;
    busy = true;
    notifyListeners();
    try {
      if (current.requiresFiles && current.skips('generate')) {
        _boardFromFiles(current);
        return;
      }
      if (!current.skips('research') && current.research != 'none') {
        final research = await _steps.run(
          step: 'research',
          search: true,
          rubric: current.rubric,
          instruction: _researchPrompt(current, draft!),
          schema: {
            'type': 'object',
            'properties': {'findings': {'type': 'array'}},
          },
          hardCheck: (json) => checkResearch(
            json,
            minFindings: current.minFindings,
            full: current.research == 'full',
          ),
        );
        if (research.handedToUser) {
          _hand(research.failures);
          return;
        }
        draft!.findings = ((research.json['findings'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      if (!current.skips('angles')) {
        final angles = await _steps.run(
          step: 'angles',
          rubric: current.rubric,
          instruction: _anglePrompt(current, draft!),
          hardCheck: _checkAngles,
        );
        if (angles.handedToUser) {
          draft!.angles = _readAngles(angles.json);
          _hand(angles.failures);
          draft!.stage = 'angles';
          return;
        }
        draft!.angles = _readAngles(angles.json);
        draft!.stage = 'angles';
      } else {
        await _writeBoard(0);
      }
    } catch (e) {
      draft!.error = e is StateError ? e.message : 'The writing step failed. Try it again.';
      message = draft!.error;
    } finally {
      busy = false;
      await _persist();
      notifyListeners();
    }
  }

  void selectAngle(int index) {
    pickedAngle = index;
    notifyListeners();
  }

  Future<void> chooseAngle(int index) async {
    pickedAngle = index;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await _writeBoard(index);
    } catch (e) {
      message = e is StateError ? e.message : 'The writing step failed. Try it again.';
    } finally {
      busy = false;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _writeBoard(int angleIndex) async {
    final current = spec!;
    final film = draft!;
    film.chosenAngle = angleIndex;
    if (!current.skips('script')) {
      final words = (film.durationSeconds / 60 * 150).round();
      final script = await _steps.run(
        step: 'script',
        rubric: current.rubric,
        instruction: _scriptPrompt(current, film, words),
        hardCheck: (json) {
          final lines = _readScript(json);
          if (lines.isEmpty) return ['The script has no lines to say.'];
          final shots = [
            for (var i = 0; i < lines.length; i++)
              ShotCard(
                id: 'line$i',
                chapter: 'Hook',
                action: 'Hook',
                durationSeconds: 3,
                line: (lines[i]['text'] ?? '').toString(),
                speaker: (lines[i]['speaker'] ?? 'narrator').toString(),
                cites: ((lines[i]['cites'] as List?) ?? const []).map((e) => e.toString()).toList(),
              ),
          ];
          return [
            ...checkHook(shots),
            ...checkSpokenLength(shots, film.durationSeconds),
            ...checkClaims(shots, film.findings),
          ];
        },
      );
      film.script = _readScript(script.json);
      if (script.handedToUser) {
        _hand(script.failures);
        final rough = [
          for (var i = 0; i < film.script.length; i++)
            ShotCard(
              id: 'line$i',
              chapter: 'Hook',
              action: (film.script[i]['text'] ?? '').toString(),
              durationSeconds: 5,
              line: (film.script[i]['text'] ?? '').toString(),
              speaker: (film.script[i]['speaker'] ?? 'narrator').toString(),
              lock: film.lock,
              cites: ((film.script[i]['cites'] as List?) ?? const []).map((e) => e.toString()).toList(),
            ),
        ];
        if (rough.isNotEmpty) {
          _runner.applyShots(film, current, rough);
          quote = _runner.quote(film, current, costs);
          film.stage = 'outline';
        }
        return;
      }
    }
    if (!current.skips('scenes')) {
      final scenes = await _steps.run(
        step: 'scenes',
        rubric: current.rubric,
        instruction: _scenePrompt(current, film),
        hardCheck: (json) {
          final shots = _shotsFrom(json, film.lock);
          if (shots.isEmpty) return ['The outline came back empty.'];
          return [
            ...checkHook(shots),
            ...checkShots(shots, speechTrack: _speechOn(current, film)),
            ...checkClaims(shots, film.findings),
          ];
        },
      );
      final shots = _shotsFrom(scenes.json, film.lock);
      if (shots.isEmpty) throw StateError('The outline came back empty. Try again.');
      final voice = scenes.json['voiceLock'];
      if (!film.voicePinned && voice is String && voice.trim().isNotEmpty) {
        film.voiceLock = voice.trim();
      }
      applyPicturePolicy(shots, current.id);
      _runner.applyShots(film, current, shots);
      await _directCast(film, current);
      if (scenes.handedToUser) _hand(scenes.failures);
    }
    if (!current.skips('edit_plan')) {
      final plan = await _steps.run(
        step: 'edit_plan',
        rubric: current.rubric,
        instruction: _planPrompt(current, film),
        hardCheck: (json) => checkEditPlan(json, film.durationSeconds),
      );
      _runner.applyEditPlan(film, plan.json);
      if (plan.handedToUser) _hand(plan.failures);
    } else {
      _runner.applyShots(film, current, film.shots);
    }
    if (!current.skips('prompts')) {
      await _steps.run(
        step: 'prompts',
        rubric: current.rubric,
        instruction: _promptPrompt(current, film),
        hardCheck: (_) => checkShots(film.shots, speechTrack: _speechOn(current, film)),
      );
      _runner.applyShots(film, current, film.shots);
    }
    quote = _runner.quote(film, current, costs);
    film.stage = 'outline';
  }

  void _boardFromFiles(WorkflowSpec current) {
    final film = draft!;
    final clips = film.filePaths.where(isVideoAssetPath).toList();
    final each = (film.durationSeconds / (clips.isEmpty ? 1 : clips.length)).round().clamp(1, 20);
    final shots = [
      for (var i = 0; i < clips.length; i++)
        ShotCard(
          id: 'u$i',
          chapter: 'Clip ${i + 1}',
          action: 'Your clip',
          durationSeconds: each,
          kind: 'user',
          userFileId: clips[i],
          localPath: clips[i],
          line: '',
        ),
    ];
    _runner.applyShots(film, current, shots);
    quote = _runner.quote(film, current, costs);
    film.stage = 'outline';
  }

  void flipKind(String shotId) {
    final film = draft;
    final current = spec;
    if (film == null || current == null) return;
    final shot = film.shots.where((s) => s.id == shotId).firstOrNull;
    if (shot == null || shot.kind == 'user') return;
    shot.kind = shot.kind == 'video' ? 'image' : 'video';
    shot.kindSetByUser = true;
    _runner.applyShots(film, current, film.shots);
    quote = _runner.quote(film, current, costs);
    _persist();
    notifyListeners();
  }

  void dropShot(String shotId) {
    final film = draft;
    final current = spec;
    if (film == null || current == null) return;
    final shot = film.shots.where((s) => s.id == shotId).firstOrNull;
    if (shot == null) return;
    shot.dropped = true;
    quote = _runner.quote(film, current, costs);
    _persist();
    notifyListeners();
  }

  void setMusic(bool on) {
    final film = draft;
    final current = spec;
    if (film == null || current == null) return;
    film.music = on;
    quote = _runner.quote(film, current, costs);
    _persist();
    notifyListeners();
  }

  void setVideoEngine(String engine) {
    final film = draft;
    final current = spec;
    if (film == null || current == null) return;
    film.videoEngine = engine;
    if (film.shots.isNotEmpty) {
      _runner.applyShots(film, current, film.shots);
      quote = _runner.quote(film, current, costs);
    }
    _persist();
    notifyListeners();
  }

  void editLine(String shotId, String line) {
    final shot = draft?.shots.where((s) => s.id == shotId).firstOrNull;
    if (shot == null) return;
    shot.line = line;
    quote = _runner.quote(draft!, spec!, costs);
    _persist();
    notifyListeners();
  }

  Future<void> make() async {
    final film = draft;
    final current = spec;
    if (film == null || current == null) return;
    if (film.stage != 'outline') {
      message = 'Accept the outline before making the film.';
      notifyListeners();
      return;
    }
    busy = true;
    message = null;
    notifyListeners();
    try {
      await _submitJobs(_runner.jobsFor(film, current));
      film.stage = 'generating';
      _ensureWatch();
    } catch (e) {
      message = e is StateError ? e.message : 'That shot could not be started. Try it again.';
    } finally {
      busy = false;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> regenerateShot(String shotId) async {
    final film = draft;
    final current = spec;
    if (film == null || current == null) return;
    final shot = film.shots.where((s) => s.id == shotId).firstOrNull;
    if (shot == null || shot.kind == 'user') return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final kept = {for (final other in film.shots) other.id: other.jobId};
      shot.localPath = null;
      shot.jobId = null;
      shot.keyframePath = null;
      shot.keyframeR2Key = null;
      shot.endFrameR2Key = null;
      if (shot.kind == 'video') {
        shot.keyframeJobId = null;
        await _submitKeyframe(shot);
      } else {
        await _prepareShot(shot);
        shot.jobId = await _submit.submitPicture(shot, aspect: film.aspect, guides: _guideKeys(shot));
      }
      for (final other in film.shots) {
        if (other.id != shot.id) other.jobId = kept[other.id];
      }
      film.stage = 'generating';
      _ensureWatch();
    } catch (e) {
      message = e is StateError ? e.message : 'That shot could not be started. Try it again.';
    } finally {
      busy = false;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> regenerateVoice() async {
    final film = draft;
    final current = spec;
    if (film == null || current == null) return;
    busy = true;
    notifyListeners();
    try {
      final voice = _runner.jobsFor(film, current).where((job) => (job['shotId'] as String).startsWith('voice'));
      await _submitJobs(voice);
      for (final key in film.files.keys.where((k) => k.startsWith('voice')).toList()) {
        film.files.remove(key);
      }
      _ensureWatch();
    } catch (e) {
      message = e is StateError ? e.message : 'The voice could not be started. Try it again.';
    } finally {
      busy = false;
      await _persist();
      notifyListeners();
    }
  }

  Future<void> partTwo(String premise) {
    final film = draft;
    return begin(
      topic: premise,
      durationSeconds: film?.durationSeconds ?? 60,
      aspect: film?.aspect ?? '9:16',
      language: film?.language ?? 'English',
      captions: film?.captions ?? true,
      music: film?.music ?? true,
      narratorOn: film?.narratorOn ?? true,
      files: film?.filePaths ?? const [],
      carryLock: film?.lock,
      videoEngine: film?.videoEngine ?? 'auto',
      preparedAssets: film?.assets.where((asset) => !asset.isMade).toList(),
      musicNote: film?.musicNote ?? '',
      lyrics: film?.lyrics ?? '',
      voiceHint: (film?.voicePinned ?? false) ? (film?.voiceLock ?? '') : '',
    );
  }

  Future<void> pollOnce() => _pollOnce();

  Future<void> _submitJobs(Iterable<Map<String, dynamic>> jobs) async {
    final film = draft!;
    final list = jobs.toList();
    _runner.submitCalls += list.length;
    await _prepareAssets();
    for (final job in list) {
      final shotId = job['shotId'] as String;
      if (shotId.startsWith('anchor:')) {
        final path = shotId.substring('anchor:'.length);
        final asset = film.assets.where((a) => a.path == path).firstOrNull;
        if (asset != null) await _submitAnchor(asset);
      } else if (shotId.startsWith('key:')) {
        final shot = film.shots.firstWhere((s) => s.id == shotId.substring(4));
        if (shot.makeKeyframe && _looksReady(film)) await _submitKeyframe(shot);
      } else if (shotId.startsWith('voice') || shotId.startsWith('music') || shotId == 'sfx') {
        final id = await _submit.submit(
          model: job['model'] as String,
          prompt: job['prompt'] as String,
          params: _audioParams(job['model'] as String, film, shotId),
        );
        film.jobs = {...film.jobs, shotId: id};
      } else {
        final shot = film.shots.firstWhere((s) => s.id == shotId);
        if (shot.kind == 'video' || !_looksReady(film)) continue;
        await _prepareShot(shot);
        shot.jobId = await _submit.submitPicture(shot, aspect: film.aspect, guides: _guideKeys(shot));
      }
    }
    if (_looksReady(film)) await _releaseVideos();
  }

  Future<void> _submitAnchor(UserAsset asset) async {
    if ((asset.jobId ?? '').isNotEmpty || (asset.r2Key ?? '').isNotEmpty) return;
    final aspect = asset.role == 'character' ? '1:1' : (draft?.aspect ?? '16:9');
    asset.jobId = await _submit.submit(
      model: 'qwen2_1_t2i',
      prompt: asset.prompt,
      params: {'aspect_ratio': aspect, 'studio_shot': true},
    );
  }

  bool _looksReady(FilmDraft film) {
    return film.assets.where((a) => a.isMade).every((a) => (a.r2Key ?? '').trim().isNotEmpty);
  }

  List<String> _guideKeys(ShotCard shot) {
    final film = draft;
    if (film == null) return const [];
    final keys = <String>[];
    for (final asset in guideAssets(film, shot)) {
      final key = (asset.r2Key ?? '').trim();
      if (key.isEmpty || keys.contains(key)) continue;
      keys.add(key);
      if (keys.length == 4) break;
    }
    final primary = (shot.referenceR2Key ?? '').trim();
    if (keys.isEmpty && primary.isNotEmpty) keys.add(primary);
    return keys;
  }

  Future<void> _submitKeyframe(ShotCard shot) async {
    if ((shot.keyframeJobId ?? '').isNotEmpty) return;
    await _prepareShot(shot);
    final keys = _guideKeys(shot);
    shot.keyframeJobId = await _submit.submit(
      model: keys.isNotEmpty ? 'qwen2_1_i2i' : 'qwen2_1_t2i',
      prompt: _keyframePrompt(shot, keys),
      params: {
        'aspect_ratio': draft?.aspect ?? '16:9',
        'studio_shot': true,
        if (keys.length == 1) 'init_image_r2_key': keys.first,
        if (keys.length > 1) 'init_image_r2_keys': keys,
      },
    );
  }

  String _keyframePrompt(ShotCard shot, List<String> keys) {
    final film = draft;
    if (film == null) return (shot.stillPrompt ?? shot.action).trim();
    final guides = guideAssets(film, shot);
    if (guides.isEmpty && keys.isEmpty) return (shot.stillPrompt ?? shot.action).trim();
    final composed = composeKeyframePrompt(action: shot.action, lock: shot.lock, guides: guides);
    if (composed.trim().isNotEmpty) return composed;
    return (shot.stillPrompt ?? shot.action).trim();
  }

  void _ensureWatch() {
    _poll ??= Timer.periodic(const Duration(seconds: 6), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    final film = draft;
    if (film == null || film.stage != 'generating') return;
    var changed = false;
    changed = await _pollAnchors(film) || changed;
    for (final shot in film.shots) {
      final keyId = shot.keyframeJobId;
      if (keyId != null && keyId.isNotEmpty && (shot.keyframeR2Key ?? '').isEmpty) {
        final snap = await _jobs.status(keyId);
        if (snap.status == 'failed') {
          message = 'One keyframe failed. You can make that card again.';
        } else if (snap.status == 'completed' && snap.url != null) {
          final path = await _jobs.download(snap.url!, keyId);
          if (path != null) {
            shot.keyframePath = path;
            final key = await _media.uploadImage(path);
            if (key == null || key.isEmpty) {
              message = 'A keyframe could not be saved. Try that card again.';
            } else {
              shot.keyframeR2Key = key;
              changed = true;
            }
          }
        }
      }
      final id = shot.jobId;
      if (id == null || id.isEmpty || (shot.localPath ?? '').isNotEmpty) continue;
      final snap = await _jobs.status(id);
      if (snap.status == 'failed') {
        if (shot.kind == 'video' && !shot.retried) {
          shot.retried = true;
          shot.quality = 'full_refine';
          shot.jobId = null;
          changed = true;
          message = 'Making that shot again at a finer pass.';
        } else {
          message = 'One shot failed. You can make that card again.';
        }
      } else if (snap.status == 'completed' && snap.url != null) {
        final path = await _jobs.download(snap.url!, id);
        if (path != null) {
          shot.localPath = path;
          if ((snap.latentKey ?? '').isNotEmpty) {
            shot.continuationLatentR2Key = snap.latentKey;
          }
          changed = true;
        }
      }
    }
    for (final entry in film.jobs.entries) {
      if (!entry.key.startsWith('voice') && !entry.key.startsWith('music') && entry.key != 'sfx') continue;
      if ((film.files[entry.key] ?? '').isNotEmpty) continue;
      final snap = await _jobs.status(entry.value);
      if (snap.status == 'completed' && snap.url != null) {
        final path = await _jobs.download(snap.url!, entry.value);
        if (path != null) {
          film.files = {...film.files, entry.key: path};
          changed = true;
        }
      }
    }
    if (changed) {
      await _submitReadyPictures();
      await _releaseVideos();
    }
    if (changed || message != null) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> _releaseVideos() async {
    final current = spec;
    final film = draft;
    if (current == null || film == null) return;
    final videos = film.shots.where((s) => !s.dropped && s.kind == 'video').toList();
    for (var i = 0; i < videos.length; i++) {
      final shot = videos[i];
      if ((shot.jobId ?? '').isNotEmpty) continue;
      if (shot.makeKeyframe && (shot.keyframeR2Key ?? '').isEmpty) continue;
      final previous = i > 0 ? videos[i - 1] : null;
      if ((shot.continuesFrom ?? '').isNotEmpty && previous != null) {
        final latent = (previous.continuationLatentR2Key ?? '').trim();
        if ((previous.localPath ?? '').isEmpty && latent.isEmpty) continue;
        if (latent.isNotEmpty) {
          shot.continuationLatentR2Key = latent;
        } else {
          shot.continuesFrom = null;
        }
      }
      final next = i < videos.length - 1 ? videos[i + 1] : null;
      final wantsEnd = next != null &&
          (next.continuesFrom ?? '').isEmpty &&
          (current.chainEndFrames || sharesSet(film, shot, next));
      if (wantsEnd) {
        final nextKey = next.keyframeR2Key;
        if (nextKey == null || nextKey.isEmpty) continue;
        shot.endFrameR2Key = nextKey;
      }
      shot.jobId = await _submit.submitPicture(shot, aspect: film.aspect, guides: _guideKeys(shot));
    }
  }

  Future<bool> _pollAnchors(FilmDraft film) async {
    var changed = false;
    for (final asset in film.assets.where((a) => a.isMade)) {
      final id = asset.jobId;
      if (id == null || id.isEmpty || (asset.r2Key ?? '').isNotEmpty) continue;
      final snap = await _jobs.status(id);
      if (snap.status == 'failed') {
        message = 'The character sheet or set failed. Try the film again.';
      } else if (snap.status == 'completed' && snap.url != null) {
        final path = await _jobs.download(snap.url!, id);
        if (path == null) continue;
        final key = await _media.uploadImage(path);
        if (key == null || key.isEmpty) {
          message = 'The character sheet or set could not be saved. Try the film again.';
          continue;
        }
        asset.r2Key = key;
        for (final shot in film.shots) {
          if (shot.referencePath == asset.path) shot.referenceR2Key = key;
        }
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _submitReadyPictures() async {
    final film = draft;
    if (film == null || !_looksReady(film)) return;
    for (final shot in film.shots.where((s) => !s.dropped && s.kind != 'user')) {
      if (shot.kind == 'video') {
        if (shot.makeKeyframe) await _submitKeyframe(shot);
      } else if ((shot.jobId ?? '').isEmpty) {
        await _prepareShot(shot);
        shot.jobId = await _submit.submitPicture(shot, aspect: film.aspect, guides: _guideKeys(shot));
      }
    }
  }

  Future<void> _prepareAssets() async {
    final film = draft;
    if (film == null) return;
    for (final asset in film.assets) {
      if (asset.path.isEmpty || asset.isMade || asset.role == 'footage') continue;
      if ((asset.r2Key ?? '').trim().isNotEmpty) continue;
      final key = await _media.uploadImage(asset.path);
      if (key == null || key.isEmpty) {
        throw StateError('That reference could not be uploaded. Try it again.');
      }
      asset.r2Key = key;
      for (final shot in film.shots) {
        if (shot.referencePath == asset.path) shot.referenceR2Key = key;
      }
    }
  }

  Future<void> _prepareShot(ShotCard shot) async {
    final path = shot.referencePath;
    if (path == null || path.isEmpty || path.startsWith('look:') || (shot.referenceR2Key ?? '').isNotEmpty) return;
    final key = await _media.uploadImage(path);
    if (key == null || key.isEmpty) {
      throw StateError('That reference could not be uploaded. Try it again.');
    }
    shot.referenceR2Key = key;
  }

  Map<String, dynamic> _audioParams(String model, FilmDraft film, String shotId) {
    if (model == 'gemini_tts') {
      final chapter = shotId.contains(':') ? shotId.split(':').sublist(1).join(':') : null;
      final turns = film.shots
          .where((s) => !s.dropped && s.line.trim().isNotEmpty && isNarrationLine(s) && (chapter == null || s.chapter == chapter))
          .map((s) => {'speaker': s.speaker, 'text': s.line})
          .toList();
      return {
        'speakers': [
          {'name': 'narrator', 'voice': voiceDescription(film)},
        ],
        'dialogue_turns': turns,
        'filler_words': false,
      };
    }
    if (model == 'suno_music') {
      final beds = musicBedCount(film.durationSeconds, true);
      var seconds = film.durationSeconds;
      if (beds > 1 && shotId != 'music') {
        seconds = film.durationSeconds - 360;
      } else if (beds > 1) {
        seconds = 360;
      }
      final sung = spec?.id == 'song_video';
      final lyric = film.lyrics.trim().isNotEmpty ? film.lyrics.trim() : film.topic.trim();
      return {
        'customMode': true,
        'instrumental': !sung,
        'style': [
          musicStyle(spec?.id ?? ''),
          if ((film.musicNote).trim().isNotEmpty) film.musicNote.trim(),
        ].join(', '),
        'lyrics': sung ? lyric : '',
        'duration': seconds.clamp(30, 360),
        'title': film.topic,
      };
    }
    return {'duration': 4};
  }

  Future<void> _directCast(FilmDraft film, WorkflowSpec current) async {
    if (current.id == 'cut_my_clips' || film.shots.isEmpty) return;
    try {
      final raw = await _director.generate(
        step: 'cast',
        instruction: castInstruction(film),
      );
      installCast(film, raw);
      _runner.applyShots(film, current, film.shots);
    } catch (_) {}
  }

  Future<void> _readAssets() async {
    final current = spec;
    final film = draft;
    if (current == null || film == null || film.assets.isEmpty || current.id == 'cut_my_clips') return;
    if (film.assets.every((a) => a.role == 'footage')) return;
    try {
      final raw = await _director.generate(
        step: 'assets',
        instruction: 'Files:\n${film.assets.map((a) => '${a.path} (${a.role})').join('\n')}\n'
            'Return {"assets":[{"path":"...","role":"character|background|product|footage|reference","note":"how this file is used across the film"}]}. '
            'A character, set, or object is used on many shots. It is not pasted onto one card. '
            'Leave any file whose note already names a character, set, object, or reference unchanged.',
      );
      applyClassified(film, raw);
    } catch (_) {}
  }

  void _hand(List<String> failures) {
    final text = failures.isEmpty ? 'Edit this draft, then continue.' : failures.first;
    draft?.error = text;
    message = text;
  }

  Future<void> _persist() async {
    final film = draft;
    if (film != null) await _store.save(film);
  }

  List<Map<String, dynamic>> _readAngles(Map<String, dynamic> json) {
    final list = (json['angles'] as List?) ?? const [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  List<String> _checkAngles(Map<String, dynamic> json) {
    final angles = _readAngles(json);
    if (angles.length < 3) return ['Three different films are required.'];
    final hooks = angles.map((a) => (a['hook'] ?? '').toString().trim().toLowerCase()).toSet();
    if (hooks.length < 3) return ['Those three ideas are the same film.'];
    return [];
  }

  List<Map<String, dynamic>> _readScript(Map<String, dynamic> json) {
    final list = (json['lines'] as List?) ?? const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<ShotCard> _shotsFrom(Map<String, dynamic> json, String fallbackLock) {
    final raw = (json['shots'] as List?) ?? const [];
    final lock = (json['lock'] as String?) ?? fallbackLock;
    final shots = <ShotCard>[];
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] is! Map) continue;
      final map = Map<String, dynamic>.from(raw[i] as Map);
      map['id'] = (map['id'] as String?) ?? 's$i';
      if ((map['lock'] as String?)?.trim().isEmpty ?? true) map['lock'] = lock;
      shots.add(ShotCard.fromJson(map));
    }
    return shots;
  }

  bool _speechOn(WorkflowSpec spec, FilmDraft film) {
    if (spec.speech == 'none') return false;
    if (spec.speech == 'optional' && !film.narratorOn) return false;
    return true;
  }

  String _researchPrompt(WorkflowSpec spec, FilmDraft film) {
    final light = spec.research == 'light';
    return '${spec.rubric}\nTopic: ${film.topic}\nLanguage: ${film.language}\n'
        'Return findings. Each finding has id, fact, url'
        '${light ? '' : ', and disagrees'}. '
        'No vague lines. At least ${spec.minFindings} findings.'
        '${light ? '' : ' Two findings must disagree.'}';
  }

  String _anglePrompt(WorkflowSpec spec, FilmDraft film) {
    return '${spec.rubric}\nTopic: ${film.topic}\nLock so far: ${film.lock}\n'
        'Return {"angles":[{"hook":"...","ending":"..."}]} with three films that differ in hook, structure, and ending.';
  }

  String _scriptPrompt(WorkflowSpec spec, FilmDraft film, int words) {
    final angle = _angle(film);
    return '${spec.rubric}\nTopic: ${film.topic}\nLanguage: ${film.language}\n'
        'Write about $words words, within 10 percent.\nAngle: $angle\nFindings: ${film.findings}\n'
        'Return {"lines":[{"speaker":"narrator","text":"...","cites":["id"]}]}. '
        'Only lines a person can say aloud. The first line is the hook. Every fact cites a finding id.';
  }

  String _scenePrompt(WorkflowSpec spec, FilmDraft film) {
    return '${spec.rubric}\nTopic: ${film.topic}\nLanguage: ${film.language}\n'
        'Length: ${film.durationSeconds} seconds.\nScript: ${film.script}\nLock: ${film.lock}\n'
        'Return {"lock":"...","voiceLock":"one narrator, age and accent","shots":[{"id":"s0","chapter":"...","action":"...","durationSeconds":5,'
        '"kind":"image","line":"...","speaker":"narrator","lock":"...","onScreen":"","leadIn":false,"cites":[]}]}. '
        'speaker is narrator only for a voice that is not on screen. When a person on screen says the line, speaker is that person\'s name. '
        'voiceLock describes the voice only, never the picture. Copy the picture lock unchanged. '
        '${film.voicePinned ? 'Keep this voiceLock exactly: ${film.voiceLock}. ' : ''}'
        'Uploads: ${film.assets.map((a) => '${a.role}: ${a.note}').join('; ')}. '
        'A pinned upload already has its role. Do not rename a character, set, object, or reference. '
        'Use a character, set, or product across the film. Do not turn an uploaded image into the only shot. '
        'If no character sheet or set was uploaded, describe both in the picture lock. They are created from that lock and used on every generated shot. '
        'Copy the lock unchanged. A shot is at most 15 seconds, or 20 when it must land on an end frame. '
        'Do not invent a replacement for a file the user attached.';
  }

  String _planPrompt(WorkflowSpec spec, FilmDraft film) {
    final ids = film.shots.map((s) => s.id).join(', ');
    return '${spec.rubric}\nShots: $ids\nLength: ${film.durationSeconds} seconds.\n'
        'Return captionStyle, duckUnderVoice, pushIn as shot ids, leadIn as shot ids, '
        'chapters, look, and transitions. Use only cut, dissolve, dip, fade, or push. '
        'A film longer than 30 seconds is not all cuts.';
  }

  String _promptPrompt(WorkflowSpec spec, FilmDraft film) {
    return '${spec.rubric}\nLock: ${film.lock}\nShots: ${film.shots.map((s) => s.toJson()).toList()}\n'
        'Write a still prompt and, for video cards, a separate clip prompt. '
        'Prefix the lock. A narrator line stays out of the clip. A person on screen says their line in the clip, with the mouth moving. '
        'The clip names the sound of the place and says no music.';
  }

  Map<String, dynamic> _angle(FilmDraft film) {
    if (film.chosenAngle == null || film.chosenAngle! >= film.angles.length) return const {};
    return film.angles[film.chosenAngle!];
  }
}

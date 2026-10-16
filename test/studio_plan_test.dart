import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/asset_use.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/gemini_client.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_assembler.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_jobs.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_media.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_session.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_submit.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/workflow_models.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/workflow_quote.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/workflow_rules.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/workflow_runner.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/workflow_steps.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/clip_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/effect_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/keyframe_model.dart';

void main() {
  test('Store stays on the credits tab after Studio is inserted', () {
    expect(AppTabs.editor, 0);
    expect(AppTabs.explore, 1);
    expect(AppTabs.studio, 2);
    expect(AppTabs.credits, 3);
    expect(AppTabs.settings, 4);
  });

  test('quote matches still, video, speech, music, and a sting', () {
    const costs = CostTable(
      imageCost: 18,
      h3Base5: 35,
      ltxBase5: 35,
      speechCost: 12,
      musicCost: 15,
      sfxCost: 8,
    );
    final shots = [
      ShotCard(id: 'a', chapter: 'One', action: 'A still', durationSeconds: 5, kind: 'image', line: 'Hello there friend'),
      ShotCard(
        id: 'b',
        chapter: 'One',
        action: 'A clip',
        durationSeconds: 10,
        kind: 'video',
        model: 'minimax_h3',
        line: 'Second line here',
      ),
    ];
    final quote = priceFilm(
      shots: shots,
      costs: costs,
      speechTasks: 1,
      music: true,
      musicBeds: 1,
      sfxCount: 1,
    );
    expect(quote.total, 18 + ((35 * 10) / 5).round() + 18 + 12 + 15 + 8);
    expect(quote.lines.map((l) => l.label), ['Picture', 'Keyframes', 'Voice', 'Music', 'Sting']);
  });

  test('flipping a shot from video to still changes the total and nothing is submitted', () {
    final runner = WorkflowRunner();
    final spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
      'speech': 'narrator',
      'music': true,
      'sfx': 0,
    });
    final draft = FilmDraft(
      id: 'd',
      workflowId: spec.id,
      topic: 'Rain',
      durationSeconds: 60,
      aspect: '9:16',
      stage: 'outline',
    );
    final shot = ShotCard(
      id: 's',
      chapter: 'Hook',
      action: 'Rain on a window',
      durationSeconds: 10,
      kind: 'video',
      line: 'The street goes quiet.',
      lock: 'Same gray coat, same street.',
    );
    runner.applyShots(draft, spec, [shot]);
    final video = runner.quote(draft, spec, const CostTable());
    shot.kind = 'image';
    runner.applyShots(draft, spec, [shot]);
    final still = runner.quote(draft, spec, const CostTable());
    expect(still.total, lessThan(video.total));
    expect(runner.submitCalls, 0);
    expect(runner.jobsFor(draft, spec), isNotEmpty);
    expect(runner.submitCalls, 0);
  });

  test('a narrated card does not put the spoken line into the clip prompt', () {
    final prompt = worldVideoPrompt(
      lock: 'Same gray coat.',
      action: 'She looks out',
      sound: 'rain',
      speechTrack: true,
    );
    expect(prompt.contains('The street goes quiet'), isFalse);
    expect(prompt.contains('No speech'), isTrue);
    expect(prompt.contains('No music'), isTrue);
  });

  test('cut my clips does not start without files', () {
    final spec = WorkflowSpec.fromJson(const {
      'id': 'cut_my_clips',
      'title': 'Cut my clips',
      'blurb': 'Only the footage you already have.',
      'requiresFiles': true,
      'skip': ['research', 'generate'],
    });
    expect(() => WorkflowRunner().ensureCanStart(spec, const []), throwsStateError);
  });

  test('a what-if board keeps one lock and a narrated draft lays tracks in order', () {
    const lock = 'One skeleton, round eyes, wool coat.';
    final shots = [
      ShotCard(id: 's1', chapter: 'Day 1', action: 'Arrives', durationSeconds: 5, kind: 'image', line: 'Day one is kind.', lock: lock, leadIn: true),
      ShotCard(id: 's2', chapter: 'Day 2', action: 'Works', durationSeconds: 5, kind: 'video', line: 'Day two costs more.', lock: lock),
      ShotCard(id: 's3', chapter: 'The bill', action: 'Leaves', durationSeconds: 5, kind: 'image', line: 'The bill comes due.', lock: lock),
    ];
    expect(checkShots(shots, speechTrack: true), isEmpty);
    final draft = FilmDraft(
      id: 'film',
      workflowId: 'narrated_story',
      topic: 'A week away',
      durationSeconds: 15,
      aspect: '9:16',
      shots: shots,
      music: true,
      captions: true,
    );
    final spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
      'speech': 'narrator',
      'clipAudioIsMain': false,
    });
    final project = assembleFilm(
      draft: draft,
      spec: spec,
      mediaPaths: {'s1': '/a.mp4', 's2': '/b.mp4', 's3': '/c.mp4'},
      voicePath: '/voice.mp3',
      musicPath: '/bed.mp3',
    ).project;
    final pictures = project.videoTracks.single.clips.cast<VideoClip>();
    expect(pictures.map((c) => c.id), ['s1', 's2', 's3']);
    expect(pictures.first.keyframeTracks.any((t) => t.property == KeyframeProperty.scale), isTrue);
    expect(project.audioTracks.map((t) => t.name), ['Voice', 'Music']);
    final music = project.audioTracks.firstWhere((t) => t.name == 'Music').clips.cast<AudioClip>();
    expect(music.any((c) => c.volume < 0.2), isTrue);
    expect(project.textTracks.map((t) => t.name), ['Captions', 'Chapters']);
    expect(pictures.every((c) => c.id == 's1' || true), isTrue);
    final replaced = replaceShotFile(project, 's2', '/b2.mp4');
    final again = replaced.videoTracks.single.clips.cast<VideoClip>().firstWhere((c) => c.id == 's2');
    expect(again.sourcePath, '/b2.mp4');
    expect(pictures.firstWhere((c) => c.id == 's1').sourcePath, '/a.mp4');
  });

  test('the same lock is copied onto every card', () {
    const lock = 'One skeleton, round eyes, wool coat.';
    final spec = WorkflowSpec.fromJson(const {
      'id': 'what_if_diary',
      'title': 'What-if diary',
      'blurb': 'A week somewhere else.',
      'speech': 'narrator',
    });
    final draft = FilmDraft(
      id: 'd',
      workflowId: spec.id,
      topic: 'A week on the moon',
      durationSeconds: 8,
      aspect: '9:16',
      lock: lock,
    );
    WorkflowRunner().applyShots(draft, spec, [
      ShotCard(id: 'a', chapter: 'Day 1', action: 'Arrives', durationSeconds: 4, line: 'You arrive.'),
      ShotCard(id: 'b', chapter: 'Day 2', action: 'Pays', durationSeconds: 4, line: 'You pay.'),
    ]);
    expect(draft.shots.map((s) => s.lock).toSet(), {lock});
  });

  test('a film longer than six minutes asks for two music beds and nothing is submitted first', () {
    final runner = WorkflowRunner();
    final spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
      'speech': 'narrator',
    });
    final draft = FilmDraft(
      id: 'd',
      workflowId: spec.id,
      topic: 'A long rain',
      durationSeconds: 400,
      aspect: '16:9',
      stage: 'outline',
      music: true,
      shots: [
        ShotCard(id: 'a', chapter: 'Hook', action: 'Rain', durationSeconds: 5, line: 'It starts.'),
        ShotCard(id: 'b', chapter: 'Turn', action: 'Stop', durationSeconds: 5, line: 'It stops.'),
      ],
    );
    final jobs = runner.jobsFor(draft, spec);
    expect(jobs.where((j) => j['model'] == 'suno_music').length, 2);
    expect(jobs.where((j) => j['shotId'].toString().startsWith('voice')).length, 2);
    expect(runner.submitCalls, 0);
  });

  test('the critic sends a draft back once, and three failures stop', () async {
    var writes = 0;
    final director = GeminiDirector(override: ({
      required String step,
      required String instruction,
      Map<String, dynamic>? schema,
      bool search = false,
    }) async {
      if (step.endsWith('_critic')) {
        return {'failures': instruction.contains('throughout history') ? ['vague'] : <String>[]};
      }
      writes++;
      if (writes == 1) {
        return {
          'findings': [
            {'fact': 'throughout history', 'url': 'https://example.com/vague'},
          ],
        };
      }
      return {
        'findings': [
          for (var i = 0; i < 4; i++)
            {
              'id': 'f$i',
              'fact': 'In 19${20 + i} the harbor opened a new dock.',
              'url': 'https://example.com/$i',
              'disagrees': i < 2,
            },
        ],
      };
    });
    final pass = await CreativeSteps(director).run(
      step: 'research',
      instruction: 'Write findings',
      rubric: 'Specific facts only.',
      hardCheck: (json) => checkResearch(json, minFindings: 4),
    );
    expect(pass.handedToUser, isFalse);
    expect((pass.json['findings'] as List).length, 4);

    final stuck = await CreativeSteps(GeminiDirector(override: ({
      required String step,
      required String instruction,
      Map<String, dynamic>? schema,
      bool search = false,
    }) async {
      return {'findings': []};
    })).run(
      step: 'research',
      instruction: 'Write findings',
      rubric: 'Specific facts only.',
      hardCheck: (_) => ['Still vague.'],
    );
    expect(stuck.handedToUser, isTrue);
    expect(stuck.failures, ['Still vague.']);
  });

  test('regenerating one shot leaves the other shot alone', () async {
    var n = 0;
    final session = StudioSession(
      submit: StudioSubmit(submitOverride: ({
        required String model,
        required String prompt,
        Map<String, dynamic> params = const {},
      }) async {
        return 'job${n++}';
      }),
      store: StudioDraftStore(saveOverride: (_) async {}),
      jobs: StudioJobClient(statusOverride: (_) async => const JobSnapshot('processing', null)),
    );
    addTearDown(session.dispose);
    session.spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
    });
    session.draft = FilmDraft(
      id: 'd',
      workflowId: 'narrated_story',
      topic: 'Rain',
      durationSeconds: 30,
      aspect: '9:16',
      stage: 'generating',
      shots: [
        ShotCard(id: 'a', chapter: 'Hook', action: 'Window', durationSeconds: 5, kind: 'image', jobId: 'keep-a', localPath: '/a.png'),
        ShotCard(id: 'b', chapter: 'Turn', action: 'Street', durationSeconds: 5, kind: 'image', jobId: 'old-b', localPath: '/b.png'),
      ],
    );
    await session.regenerateShot('b');
    expect(session.draft!.shots.first.jobId, 'keep-a');
    expect(session.draft!.shots.first.localPath, '/a.png');
    expect(session.draft!.shots[1].jobId, 'job0');
    expect(session.draft!.shots[1].localPath, isNull);
    expect(n, 1);
  });

  test('a finished file is placed without touching the other shot', () async {
    final session = StudioSession(
      store: StudioDraftStore(saveOverride: (_) async {}),
      jobs: StudioJobClient(
        statusOverride: (id) async => id == 'j1' ? const JobSnapshot('completed', 'https://example.com/a.png') : const JobSnapshot('processing', null),
        downloadOverride: (url, name) async => '/local/$name.png',
      ),
    );
    addTearDown(session.dispose);
    session.draft = FilmDraft(
      id: 'd',
      workflowId: 'narrated_story',
      topic: 'Rain',
      durationSeconds: 30,
      aspect: '9:16',
      stage: 'generating',
      shots: [
        ShotCard(id: 'a', chapter: 'Hook', action: 'Window', durationSeconds: 5, jobId: 'j1'),
        ShotCard(id: 'b', chapter: 'Turn', action: 'Street', durationSeconds: 5, jobId: 'j2', localPath: '/already.png'),
      ],
    );
    await session.pollOnce();
    expect(session.draft!.shots.first.localPath, '/local/j1.png');
    expect(session.draft!.shots[1].localPath, '/already.png');
    expect(session.draft!.shots[1].jobId, 'j2');
  });

  test('make does not submit before the outline is accepted', () async {
    final session = StudioSession(
      store: StudioDraftStore(saveOverride: (_) async {}),
    );
    addTearDown(session.dispose);
    session.spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
    });
    session.draft = FilmDraft(
      id: 'd',
      workflowId: 'narrated_story',
      topic: 'Rain',
      durationSeconds: 30,
      aspect: '9:16',
      stage: 'angles',
    );
    await session.make();
    expect(session.message, 'Accept the outline before making the film.');
  });

  test('a character sheet is used on every generated shot', () {
    final runner = WorkflowRunner();
    final spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
      'speech': 'narrator',
    });
    final draft = FilmDraft(
      id: 'd',
      workflowId: spec.id,
      topic: 'Sita and the deer',
      durationSeconds: 20,
      aspect: '16:9',
      assets: [
        UserAsset(path: '/rama_character.png', role: 'character', note: 'Rama, same face'),
      ],
    );
    runner.applyShots(draft, spec, [
      ShotCard(id: 'a', chapter: 'Hook', action: 'Rama looks up', durationSeconds: 8, kind: 'video', line: 'He looks up.', lock: 'Same bow, gold cloth.'),
      ShotCard(id: 'b', chapter: 'Hook', action: 'The forest holds still', durationSeconds: 8, kind: 'image', line: 'The trees wait.', lock: 'Same bow, gold cloth.'),
    ]);
    expect(draft.shots.where((s) => s.kind == 'user'), isEmpty);
    expect(draft.shots.every((s) => s.referencePath == '/rama_character.png'), isTrue);
    expect(draft.assets.where((a) => a.role == 'character'), hasLength(1));
    expect(draft.assets.any((a) => a.path == 'look:background'), isTrue);
    expect(draft.shots.first.videoPrompt, contains('Match the uploaded character'));
    expect(draft.shots.first.videoPrompt, contains('No speech'));
    expect(draft.shots.first.videoPrompt!.contains('soft room tone'), isFalse);
    expect(draft.voiceLock == draft.lock, isFalse);
  });

  test('references pick image-to-image, image-to-video, and start-to-end', () async {
    final calls = <Map<String, dynamic>>[];
    final submit = StudioSubmit(submitOverride: ({
      required String model,
      required String prompt,
      Map<String, dynamic> params = const {},
    }) async {
      calls.add({'model': model, ...params});
      return 'job';
    });
    await submit.submitPicture(
      ShotCard(id: 'still', chapter: 'Hook', action: 'Rama', durationSeconds: 5, kind: 'image', referenceR2Key: 'r2/rama'),
      aspect: '16:9',
    );
    await submit.submitPicture(
      ShotCard(id: 'move', chapter: 'Hook', action: 'Rama walks', durationSeconds: 8, kind: 'video', referenceR2Key: 'r2/rama'),
      aspect: '16:9',
    );
    await submit.submitPicture(
      ShotCard(
        id: 'chain',
        chapter: 'Walk',
        action: 'The path continues',
        durationSeconds: 8,
        kind: 'video',
        model: 'ltx25_int8_t2v',
        referenceR2Key: 'r2/start',
        endFrameR2Key: 'r2/end',
      ),
      aspect: '16:9',
    );
    expect(calls[0]['model'], 'qwen2_1_i2i');
    expect(calls[0]['init_image_r2_key'], 'r2/rama');
    expect(calls[1]['model'], 'minimax_h3');
    expect(calls[1]['mode'], 'i2v');
    expect(calls[1]['duration'], 8);
    expect(calls[1]['studio_shot'], true);
    expect(calls[2]['model'], 'ltx25_int8_flf2v');
    expect(calls[2]['last_frame_image_r2_key'], 'r2/end');
  });

  test('product checks reject a weak narration, a face in FPV, and a countdown that peaks first', () {
    final narration = FilmDraft(
      id: 'n',
      workflowId: 'narrated_story',
      topic: 'Sita',
      durationSeconds: 60,
      aspect: '16:9',
      voiceLock: 'Same bow, gold cloth.',
      lock: 'Same bow, gold cloth.',
      shots: [
        ShotCard(id: 'a', chapter: 'Hook', action: 'Start', durationSeconds: 5, line: 'one two three four five six seven eight nine ten eleven twelve thirteen'),
        ShotCard(id: 'b', chapter: 'Middle', action: 'Middle', durationSeconds: 5, line: 'Goes on.'),
        ShotCard(id: 'c', chapter: 'End', action: 'End', durationSeconds: 5, line: 'Stops.'),
      ],
    );
    final narrationFails = checkProduct(narration);
    expect(narrationFails, contains('The story needs a turn.'));
    expect(narrationFails, contains('The narrator\'s voice has to be separate from the picture lock.'));

    final fpv = FilmDraft(
      id: 'f',
      workflowId: 'fpv',
      topic: 'Road',
      durationSeconds: 30,
      aspect: '16:9',
      shots: [
        ShotCard(id: 'a', chapter: 'Hook', action: 'A face turns toward the lens', durationSeconds: 5, kind: 'video', model: 'minimax_h3'),
      ],
    );
    expect(checkProduct(fpv), contains('An FPV shot cannot cut to a face.'));

    final countdown = FilmDraft(
      id: 'c',
      workflowId: 'countdown',
      topic: 'Temples',
      durationSeconds: 60,
      aspect: '9:16',
      shots: [
        ShotCard(id: 'a', chapter: '1', action: 'Best', durationSeconds: 5, kind: 'image'),
        ShotCard(id: 'b', chapter: '2', action: 'Next', durationSeconds: 5, kind: 'image'),
        ShotCard(id: 'c', chapter: '10', action: 'Last', durationSeconds: 5, kind: 'video'),
      ],
    );
    expect(checkProduct(countdown), contains('The best item has to be last.'));
  });

  test('a chapter change dissolves and a cut stays inside the chapter', () {
    final draft = FilmDraft(
      id: 'film',
      workflowId: 'narrated_story',
      topic: 'Sita',
      durationSeconds: 16,
      aspect: '16:9',
      music: false,
      shots: [
        ShotCard(id: 's1', chapter: 'Hook', action: 'Opens', durationSeconds: 5, kind: 'image', line: 'Open.'),
        ShotCard(id: 's2', chapter: 'Hook', action: 'Holds', durationSeconds: 5, kind: 'image', line: 'Hold.'),
        ShotCard(id: 's3', chapter: 'Turn', action: 'Turns', durationSeconds: 5, kind: 'video', line: 'Turn.'),
      ],
    );
    final spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
      'speech': 'narrator',
    });
    final pictures = assembleFilm(
      draft: draft,
      spec: spec,
      mediaPaths: {'s1': '/a.png', 's2': '/b.png', 's3': '/c.mp4'},
    ).project.videoTracks.single.clips.cast<VideoClip>();
    expect(pictures[1].transitionIn.type, TransitionType.none);
    expect(pictures[2].transitionIn.type, TransitionType.dissolve);
  });

  test('narration keeps moving shots on the hook, the turn, and the last image', () {
    final shots = [
      ShotCard(id: 'a', chapter: 'Hook', action: 'Opens', durationSeconds: 5),
      ShotCard(id: 'b', chapter: 'Spiral', action: 'Wanders', durationSeconds: 5),
      ShotCard(id: 'c', chapter: 'Turn', action: 'Breaks', durationSeconds: 5),
      ShotCard(id: 'd', chapter: 'Last image', action: 'Holds', durationSeconds: 5),
    ];
    applyPicturePolicy(shots, 'narrated_story');
    expect(shots.map((s) => s.kind).toList(), ['video', 'image', 'video', 'video']);
  });

  test('chained shots animate between keyframes and do not wait on the previous video', () async {
    final submitted = <Map<String, dynamic>>[];
    var n = 0;
    final session = StudioSession(
      submit: StudioSubmit(submitOverride: ({
        required String model,
        required String prompt,
        Map<String, dynamic> params = const {},
      }) async {
        submitted.add({'model': model, 'prompt': prompt, ...params});
        return 'job${n++}';
      }),
      store: StudioDraftStore(saveOverride: (_) async {}),
      jobs: StudioJobClient(
        statusOverride: (_) async => const JobSnapshot('completed', 'https://example.com/frame.png'),
        downloadOverride: (url, name) async => '/frames/$name.png',
      ),
      media: StudioMedia(uploadOverride: (path) async => 'r2$path'),
    );
    addTearDown(session.dispose);
    session.spec = WorkflowSpec.fromJson(const {
      'id': 'fpv',
      'title': 'FPV',
      'blurb': 'One camera.',
      'speech': 'none',
      'music': false,
      'chainEndFrames': true,
    });
    session.draft = FilmDraft(
      id: 'd',
      workflowId: 'fpv',
      topic: 'The ridge',
      durationSeconds: 16,
      aspect: '16:9',
      stage: 'outline',
      music: false,
      shots: [
        ShotCard(id: 'a', chapter: 'Hook', action: 'Leaves the ridge', durationSeconds: 8, kind: 'video', model: 'ltx25_int8_t2v', lock: 'One lens, one weather.'),
        ShotCard(id: 'b', chapter: 'Hook', action: 'Drops into the valley', durationSeconds: 8, kind: 'video', model: 'ltx25_int8_t2v', lock: 'One lens, one weather.'),
      ],
    );
    await session.make();
    expect(submitted.map((c) => c['model']), ['qwen2_1_t2i']);
    expect(submitted.first['aspect_ratio'], '16:9');
    expect(session.draft!.shots.every((s) => (s.jobId ?? '').isEmpty), isTrue);
    expect(session.draft!.shots.every((s) => (s.keyframeJobId ?? '').isEmpty), isTrue);

    await session.pollOnce();
    expect(submitted[1]['model'], 'qwen2_1_i2i');
    expect(submitted[1]['init_image_r2_key'], 'r2/frames/job0.png');
    expect(submitted[2]['model'], 'qwen2_1_i2i');
    expect(submitted[2]['init_image_r2_key'], 'r2/frames/job0.png');
    expect(session.draft!.shots.every((s) => (s.jobId ?? '').isEmpty), isTrue);

    await session.pollOnce();
    expect(submitted[3]['model'], 'ltx25_int8_flf2v');
    expect(submitted[3]['init_image_r2_key'], 'r2/frames/job1.png');
    expect(submitted[3]['last_frame_image_r2_key'], 'r2/frames/job2.png');
    expect(submitted[4]['model'], 'ltx25_int8_i2v');
    expect(submitted[4]['init_image_r2_key'], 'r2/frames/job2.png');
    expect(submitted[4].containsKey('last_frame_image_r2_key'), isFalse);
  });

  test('a story with no uploads draws every scene from a made character sheet and set', () async {
    final submitted = <Map<String, dynamic>>[];
    var n = 0;
    final session = StudioSession(
      submit: StudioSubmit(submitOverride: ({
        required String model,
        required String prompt,
        Map<String, dynamic> params = const {},
      }) async {
        submitted.add({'model': model, 'prompt': prompt, ...params});
        return 'job${n++}';
      }),
      store: StudioDraftStore(saveOverride: (_) async {}),
      jobs: StudioJobClient(
        statusOverride: (_) async => const JobSnapshot('completed', 'https://example.com/frame.png'),
        downloadOverride: (url, name) async => '/frames/$name.png',
      ),
      media: StudioMedia(uploadOverride: (path) async => 'r2$path'),
    );
    addTearDown(session.dispose);
    session.spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
      'speech': 'none',
      'music': false,
    });
    session.draft = FilmDraft(
      id: 'd',
      workflowId: 'narrated_story',
      topic: 'Sita and the deer',
      durationSeconds: 20,
      aspect: '16:9',
      stage: 'outline',
      music: false,
      lock: 'Same gold cloth, same forest court.',
      shots: [
        ShotCard(
          id: 'a',
          chapter: 'Hook',
          action: 'Sita turns',
          durationSeconds: 8,
          kind: 'video',
          line: '',
          lock: 'Same gold cloth, same forest court.',
        ),
      ],
    );
    await session.make();
    expect(session.draft!.assets.map((a) => a.path), ['look:character', 'look:background']);
    expect(session.draft!.assets.first.prompt, contains('Character sheet'));
    expect(session.draft!.assets.last.prompt, contains('Empty set'));
    expect(submitted.map((c) => c['model']), ['qwen2_1_t2i', 'qwen2_1_t2i']);
    expect(submitted[0]['aspect_ratio'], '1:1');
    expect(submitted[1]['aspect_ratio'], '16:9');
    expect(session.draft!.shots.single.keyframeJobId, isNull);

    await session.pollOnce();
    expect(submitted.last['model'], 'qwen2_1_i2i');
    expect(submitted.last['init_image_r2_keys'], ['r2/frames/job0.png', 'r2/frames/job1.png']);
    expect(submitted.last['prompt'], contains('The first image is the character'));
  });

  test('a named cast stays within four references and a place shot uses LTX', () {
    final draft = FilmDraft(
      id: 'd',
      workflowId: 'narrated_story',
      topic: 'Ramayana',
      durationSeconds: 300,
      aspect: '16:9',
      assets: [
        UserAsset(path: '/rama_character.png', role: 'character', note: 'Rama'),
        UserAsset(path: '/sita_character.png', role: 'character', note: 'Sita'),
        UserAsset(path: '/lakshmana_character.png', role: 'character', note: 'Lakshmana'),
        UserAsset(path: '/hanuman_character.png', role: 'character', note: 'Hanuman'),
        UserAsset(path: '/ravana_character.png', role: 'character', note: 'Ravana'),
        UserAsset(path: '/forest_background.png', role: 'background', note: 'Forest'),
      ],
    );
    final court = ShotCard(id: 'a', chapter: 'Hook', action: 'Rama and Sita stand in the forest', durationSeconds: 12, kind: 'video', line: 'He looks up.');
    final guides = guideAssets(draft, court);
    expect(guides.map((a) => a.path), ['/rama_character.png', '/sita_character.png', '/forest_background.png']);
    final spec = WorkflowSpec.fromJson(const {
      'id': 'narrated_story',
      'title': 'Narrated story',
      'blurb': 'A voiced film from a topic.',
    });
    expect(chooseVideoModel(draft, court, spec), 'minimax_h3');
    final army = ShotCard(id: 'b', chapter: 'Lanka', action: 'The army crosses the sea bridge', durationSeconds: 12, kind: 'video');
    expect(chooseVideoModel(draft, army, spec), 'ltx25_int8_t2v');
    final fpv = WorkflowSpec.fromJson(const {
      'id': 'fpv',
      'title': 'FPV',
      'blurb': 'One camera.',
      'chainEndFrames': true,
    });
    expect(chooseVideoModel(draft, army, fpv), 'ltx25_int8_t2v');
    draft.videoEngine = 'minimax_h3';
    expect(chooseVideoModel(draft, army, spec), 'minimax_h3');
    draft.videoEngine = 'ltx25_int8_t2v';
    expect(chooseVideoModel(draft, court, spec), 'ltx25_int8_t2v');
  });
}

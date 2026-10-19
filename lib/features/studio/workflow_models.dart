import 'dart:convert';

import 'package:flutter/services.dart';

class WorkflowSpec {
  final String id;
  final String title;
  final String blurb;
  final String research;
  final List<String> skip;
  final List<int> lengths;
  final int defaultLength;
  final List<String> aspects;
  final String defaultAspect;
  final String speech;
  final bool music;
  final int sfx;
  final bool clipAudioIsMain;
  final bool chainEndFrames;
  final bool requiresFiles;
  final int minFindings;
  final String rubric;

  const WorkflowSpec({
    required this.id,
    required this.title,
    required this.blurb,
    required this.research,
    required this.skip,
    required this.lengths,
    required this.defaultLength,
    required this.aspects,
    required this.defaultAspect,
    required this.speech,
    required this.music,
    required this.sfx,
    required this.clipAudioIsMain,
    required this.chainEndFrames,
    required this.requiresFiles,
    required this.minFindings,
    required this.rubric,
  });

  bool skips(String step) => skip.contains(step);

  factory WorkflowSpec.fromJson(Map<String, dynamic> json) {
    return WorkflowSpec(
      id: json['id'] as String,
      title: json['title'] as String,
      blurb: json['blurb'] as String,
      research: (json['research'] as String?) ?? 'full',
      skip: ((json['skip'] as List?) ?? const []).cast<String>(),
      lengths: ((json['lengths'] as List?) ?? const [60]).map((e) => (e as num).toInt()).toList(),
      defaultLength: (json['defaultLength'] as num?)?.toInt() ?? 60,
      aspects: ((json['aspects'] as List?) ?? const ['9:16']).cast<String>(),
      defaultAspect: (json['defaultAspect'] as String?) ?? '9:16',
      speech: (json['speech'] as String?) ?? 'narrator',
      music: json['music'] != false,
      sfx: (json['sfx'] as num?)?.toInt() ?? 0,
      clipAudioIsMain: json['clipAudioIsMain'] == true,
      chainEndFrames: json['chainEndFrames'] == true,
      requiresFiles: json['requiresFiles'] == true,
      minFindings: (json['minFindings'] as num?)?.toInt() ?? 4,
      rubric: (json['rubric'] as String?) ?? '',
    );
  }
}

class UserAsset {
  final String path;
  String role;
  String note;
  String prompt;
  String? jobId;
  String? r2Key;
  bool pinned;

  UserAsset({
    required this.path,
    required this.role,
    required this.note,
    this.prompt = '',
    this.jobId,
    this.r2Key,
    this.pinned = false,
  });

  bool get isMade => path.startsWith('look:');

  Map<String, dynamic> toJson() => {
        'path': path,
        'role': role,
        'note': note,
        'prompt': prompt,
        'jobId': jobId,
        'r2Key': r2Key,
        'pinned': pinned,
      };

  factory UserAsset.fromJson(Map<String, dynamic> json) {
    return UserAsset(
      path: (json['path'] as String?) ?? '',
      role: (json['role'] as String?) ?? 'other',
      note: (json['note'] as String?) ?? '',
      prompt: (json['prompt'] as String?) ?? '',
      jobId: json['jobId'] as String?,
      r2Key: json['r2Key'] as String?,
      pinned: json['pinned'] == true,
    );
  }
}

const kWorkflowIds = [
  'narrated_story',
  'explainer',
  'podcast',
  'what_if_diary',
  'time_travel_pov',
  'body',
  'fpv',
  'creature_eye',
  'cut_my_clips',
  'countdown',
  'song_video',
];

Future<List<WorkflowSpec>> loadWorkflows() async {
  final out = <WorkflowSpec>[];
  for (final id in kWorkflowIds) {
    final raw = await rootBundle.loadString('lib/features/studio/workflows/$id.json');
    out.add(WorkflowSpec.fromJson(jsonDecode(raw) as Map<String, dynamic>));
  }
  return out;
}

class ShotCard {
  final String id;
  String chapter;
  String action;
  int durationSeconds;
  String kind;
  bool dropped;
  String? userFileId;
  String? stillPrompt;
  String? videoPrompt;
  String line;
  String speaker;
  String lock;
  String? localPath;
  String? jobId;
  bool leadIn;
  String model;
  List<String> cites;
  bool pushIn;
  bool kindSetByUser;
  String? referencePath;
  String? referenceRole;
  String? referenceR2Key;
  String? endFrameR2Key;
  String? keyframeJobId;
  String? keyframePath;
  String? keyframeR2Key;
  String onScreen;
  String quality;
  bool makeKeyframe;
  String? continuesFrom;
  String? continuationLatentR2Key;
  bool retried;
  int audioInSeconds;

  ShotCard({
    required this.id,
    required this.chapter,
    required this.action,
    required this.durationSeconds,
    this.kind = 'image',
    this.dropped = false,
    this.userFileId,
    this.stillPrompt,
    this.videoPrompt,
    this.line = '',
    this.speaker = 'narrator',
    this.lock = '',
    this.localPath,
    this.jobId,
    this.leadIn = false,
    this.model = 'minimax_h3',
    this.cites = const [],
    this.pushIn = true,
    this.kindSetByUser = false,
    this.referencePath,
    this.referenceRole,
    this.referenceR2Key,
    this.endFrameR2Key,
    this.keyframeJobId,
    this.keyframePath,
    this.keyframeR2Key,
    this.onScreen = '',
    this.quality = 'draft',
    this.makeKeyframe = true,
    this.continuesFrom,
    this.continuationLatentR2Key,
    this.retried = false,
    this.audioInSeconds = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'chapter': chapter,
        'action': action,
        'durationSeconds': durationSeconds,
        'kind': kind,
        'dropped': dropped,
        'userFileId': userFileId,
        'stillPrompt': stillPrompt,
        'videoPrompt': videoPrompt,
        'line': line,
        'speaker': speaker,
        'lock': lock,
        'localPath': localPath,
        'jobId': jobId,
        'leadIn': leadIn,
        'model': model,
        'cites': cites,
        'pushIn': pushIn,
        'kindSetByUser': kindSetByUser,
        'referencePath': referencePath,
        'referenceRole': referenceRole,
        'referenceR2Key': referenceR2Key,
        'endFrameR2Key': endFrameR2Key,
        'keyframeJobId': keyframeJobId,
        'keyframePath': keyframePath,
        'keyframeR2Key': keyframeR2Key,
        'onScreen': onScreen,
        'quality': quality,
        'makeKeyframe': makeKeyframe,
        'continuesFrom': continuesFrom,
        'continuationLatentR2Key': continuationLatentR2Key,
        'retried': retried,
        'audioInSeconds': audioInSeconds,
      };

  factory ShotCard.fromJson(Map<String, dynamic> json) {
    return ShotCard(
      id: json['id'] as String,
      chapter: (json['chapter'] as String?) ?? '',
      action: (json['action'] as String?) ?? '',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 5,
      kind: (json['kind'] as String?) ?? 'image',
      dropped: json['dropped'] == true,
      userFileId: json['userFileId'] as String?,
      stillPrompt: json['stillPrompt'] as String?,
      videoPrompt: json['videoPrompt'] as String?,
      line: (json['line'] as String?) ?? '',
      speaker: (json['speaker'] as String?) ?? 'narrator',
      lock: (json['lock'] as String?) ?? '',
      localPath: json['localPath'] as String?,
      jobId: json['jobId'] as String?,
      leadIn: json['leadIn'] == true,
      model: (json['model'] as String?) ?? 'minimax_h3',
      cites: ((json['cites'] as List?) ?? const []).map((e) => e.toString()).toList(),
      pushIn: json['pushIn'] != false,
      kindSetByUser: json['kindSetByUser'] == true,
      referencePath: json['referencePath'] as String?,
      referenceRole: json['referenceRole'] as String?,
      referenceR2Key: json['referenceR2Key'] as String?,
      endFrameR2Key: json['endFrameR2Key'] as String?,
      keyframeJobId: json['keyframeJobId'] as String?,
      keyframePath: json['keyframePath'] as String?,
      keyframeR2Key: json['keyframeR2Key'] as String?,
      onScreen: (json['onScreen'] as String?) ?? '',
      quality: (json['quality'] as String?) ?? 'draft',
      makeKeyframe: json['makeKeyframe'] != false,
      continuesFrom: json['continuesFrom'] as String?,
      continuationLatentR2Key: json['continuationLatentR2Key'] as String?,
      retried: json['retried'] == true,
      audioInSeconds: (json['audioInSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

class FilmDraft {
  final String id;
  final String workflowId;
  String topic;
  int durationSeconds;
  String aspect;
  String language;
  bool captions;
  bool music;
  bool narratorOn;
  List<String> filePaths;
  String stage;
  String? error;
  List<Map<String, dynamic>> angles;
  int? chosenAngle;
  List<ShotCard> shots;
  String lock;
  Map<String, String> jobs;
  Map<String, String> files;
  List<Map<String, dynamic>> findings;
  List<Map<String, dynamic>> script;
  Map<String, dynamic> editPlan;
  String voiceLock;
  bool voicePinned;
  String musicNote;
  String lyrics;
  List<UserAsset> assets;
  String videoEngine;
  String finish;

  FilmDraft({
    required this.id,
    required this.workflowId,
    required this.topic,
    required this.durationSeconds,
    required this.aspect,
    this.language = 'English',
    this.captions = true,
    this.music = true,
    this.narratorOn = true,
    this.filePaths = const [],
    this.stage = 'intake',
    this.error,
    this.angles = const [],
    this.chosenAngle,
    this.shots = const [],
    this.lock = '',
    this.jobs = const {},
    this.files = const {},
    this.findings = const [],
    this.script = const [],
    this.editPlan = const {},
    this.voiceLock = '',
    this.voicePinned = false,
    this.musicNote = '',
    this.lyrics = '',
    this.assets = const [],
    this.videoEngine = 'auto',
    this.finish = 'balanced',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'workflowId': workflowId,
        'topic': topic,
        'durationSeconds': durationSeconds,
        'aspect': aspect,
        'language': language,
        'captions': captions,
        'music': music,
        'narratorOn': narratorOn,
        'filePaths': filePaths,
        'stage': stage,
        'error': error,
        'angles': angles,
        'chosenAngle': chosenAngle,
        'shots': shots.map((s) => s.toJson()).toList(),
        'lock': lock,
        'jobs': jobs,
        'files': files,
        'findings': findings,
        'script': script,
        'editPlan': editPlan,
        'voiceLock': voiceLock,
        'voicePinned': voicePinned,
        'musicNote': musicNote,
        'lyrics': lyrics,
        'assets': assets.map((a) => a.toJson()).toList(),
        'videoEngine': videoEngine,
        'finish': finish,
      };

  factory FilmDraft.fromJson(Map<String, dynamic> json) {
    return FilmDraft(
      id: json['id'] as String,
      workflowId: json['workflowId'] as String,
      topic: (json['topic'] as String?) ?? '',
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 60,
      aspect: (json['aspect'] as String?) ?? '9:16',
      language: (json['language'] as String?) ?? 'English',
      captions: json['captions'] != false,
      music: json['music'] != false,
      narratorOn: json['narratorOn'] != false,
      filePaths: ((json['filePaths'] as List?) ?? const []).cast<String>(),
      stage: (json['stage'] as String?) ?? 'intake',
      error: json['error'] as String?,
      angles: ((json['angles'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      chosenAngle: (json['chosenAngle'] as num?)?.toInt(),
      shots: ((json['shots'] as List?) ?? const [])
          .map((e) => ShotCard.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      lock: (json['lock'] as String?) ?? '',
      jobs: Map<String, String>.from((json['jobs'] as Map?) ?? const {}),
      files: Map<String, String>.from((json['files'] as Map?) ?? const {}),
      findings: ((json['findings'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      script: ((json['script'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
      editPlan: Map<String, dynamic>.from((json['editPlan'] as Map?) ?? const {}),
      voiceLock: (json['voiceLock'] as String?) ?? '',
      voicePinned: json['voicePinned'] == true,
      musicNote: (json['musicNote'] as String?) ?? '',
      lyrics: (json['lyrics'] as String?) ?? '',
      assets: ((json['assets'] as List?) ?? const [])
          .map((e) => UserAsset.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      videoEngine: (json['videoEngine'] as String?) ?? 'auto',
      finish: (json['finish'] as String?) ?? 'balanced',
    );
  }
}

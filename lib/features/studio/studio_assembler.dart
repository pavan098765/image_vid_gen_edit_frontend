import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/clip_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/effect_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/keyframe_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/project_model.dart';

import 'workflow_models.dart';

class AssembledFilm {
  final VideoProject project;
  const AssembledFilm(this.project);
}

AssembledFilm assembleFilm({
  required FilmDraft draft,
  required WorkflowSpec spec,
  required Map<String, String> mediaPaths,
  String? voicePath,
  Map<String, String> voiceByChapter = const {},
  String? musicPath,
  Duration? voiceDuration,
  Duration? musicDuration,
}) {
  final live = draft.shots.where((s) => !s.dropped).toList();
  final pictures = <VideoClip>[];
  final captions = <TextClip>[];
  final chapters = <TextClip>[];
  final voiceClips = <AudioClip>[];
  var cursor = Duration.zero;
  var voiceOffset = Duration.zero;
  String? lastChapter;
  String? voiceChapter;
  final speechWindows = <(Duration, Duration)>[];

  for (var i = 0; i < live.length; i++) {
    final shot = live[i];
    final path = mediaPaths[shot.id] ?? shot.localPath;
    final dur = Duration(seconds: shot.durationSeconds.clamp(1, 20));
    if (path != null && path.isNotEmpty) {
      final size = draft.aspect == '16:9' ? const Size(1280, 720) : const Size(720, 1280);
      final newChapter = shot.chapter.isNotEmpty && shot.chapter != lastChapter;
      pictures.add(VideoClip(
        id: shot.id,
        startTime: cursor,
        duration: dur,
        sourcePath: path,
        trimStart: Duration.zero,
        trimEnd: dur,
        originalDuration: dur,
        resolution: size,
        volume: spec.id == 'song_video' ? 0 : (spec.clipAudioIsMain ? 1 : 0.35),
        transitionIn: i == 0 || !newChapter
            ? const ClipTransition()
            : const ClipTransition(
                type: TransitionType.dissolve,
                duration: Duration(milliseconds: 400),
              ),
        keyframeTracks: shot.kind == 'image' && shot.pushIn
            ? [
                KeyframeTrack(
                  clipId: shot.id,
                  property: KeyframeProperty.scale,
                  keyframes: [
                    const Keyframe(time: Duration.zero, value: 1),
                    Keyframe(time: dur, value: 1.08),
                  ],
                ),
              ]
            : const [],
      ));
    }
    if (draft.captions && shot.line.trim().isNotEmpty) {
      captions.add(TextClip(
        id: '${shot.id}_cap',
        startTime: cursor,
        duration: dur,
        text: shot.line.trim(),
        fontSize: 22,
        position: const Offset(0.5, 0.86),
        backgroundColor: const Color(0x99000000),
      ));
    }
    if (shot.chapter.isNotEmpty && shot.chapter != lastChapter) {
      lastChapter = shot.chapter;
      chapters.add(TextClip(
        id: '${shot.id}_ch',
        startTime: cursor,
        duration: const Duration(seconds: 2),
        text: shot.chapter,
        fontSize: 32,
        position: const Offset(0.5, 0.18),
      ));
    }
    final chapterVoice = voiceByChapter[shot.chapter] ?? voicePath;
    if (shot.chapter != voiceChapter) {
      voiceChapter = shot.chapter;
      if (voiceByChapter.containsKey(shot.chapter)) voiceOffset = Duration.zero;
    }
    if (shot.line.trim().isNotEmpty && chapterVoice != null) {
      final lead = shot.leadIn ? const Duration(milliseconds: 200) : Duration.zero;
      final start = cursor - lead < Duration.zero ? Duration.zero : cursor - lead;
      final trimFrom = voiceByChapter.containsKey(shot.chapter) ? voiceOffset : cursor;
      speechWindows.add((start, cursor + dur));
      voiceClips.add(AudioClip(
        id: '${shot.id}_voice',
        startTime: start,
        duration: dur + lead,
        sourcePath: chapterVoice,
        trimStart: trimFrom,
        trimEnd: trimFrom + dur,
        originalDuration: voiceDuration ?? (trimFrom + dur),
        name: shot.speaker,
        volume: 1,
      ));
      voiceOffset += dur;
    }
    cursor += dur;
  }

  final tracks = <Track>[
    Track(id: '${draft.id}_v', type: TrackType.video, name: 'Picture', clips: pictures),
    if (voiceClips.isNotEmpty)
      Track(id: '${draft.id}_voice', type: TrackType.audio, name: 'Voice', clips: voiceClips),
    if (musicPath != null && draft.music)
      Track(
        id: '${draft.id}_music',
        type: TrackType.audio,
        name: 'Music',
        clips: _musicSegments(
          draftId: draft.id,
          path: musicPath,
          total: cursor,
          windows: speechWindows,
          onlyUnderTitle: spec.clipAudioIsMain,
          musicDuration: musicDuration,
        ),
      ),
    if (captions.isNotEmpty)
      Track(id: '${draft.id}_cap', type: TrackType.text, name: 'Captions', clips: captions),
    if (chapters.isNotEmpty)
      Track(id: '${draft.id}_ch', type: TrackType.text, name: 'Chapters', clips: chapters),
  ];

  return AssembledFilm(VideoProject(
    id: draft.id,
    name: draft.topic.isEmpty ? spec.title : draft.topic,
    tracks: tracks,
    totalDuration: cursor,
  ));
}

List<AudioClip> _musicSegments({
  required String draftId,
  required String path,
  required Duration total,
  required List<(Duration, Duration)> windows,
  required bool onlyUnderTitle,
  Duration? musicDuration,
}) {
  final base = onlyUnderTitle ? 0.45 : 0.4;
  final ducked = onlyUnderTitle ? 0.12 : 0.12;
  final events = <(Duration, double)>[
    (Duration.zero, onlyUnderTitle ? ducked : base),
  ];
  if (onlyUnderTitle) {
    events.add((const Duration(seconds: 3), base));
  } else {
    for (final window in windows) {
      events.add((window.$1, ducked));
      events.add((window.$2, base));
    }
  }
  events.sort((a, b) => a.$1.compareTo(b.$1));
  final points = <(Duration, double)>[];
  for (final event in events) {
    if (points.isNotEmpty && points.last.$1 == event.$1) {
      points[points.length - 1] = event;
    } else {
      points.add(event);
    }
  }
  if (points.last.$1 < total) {
    points.add((total, points.last.$2));
  }
  final clips = <AudioClip>[];
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i].$1;
    final end = points[i + 1].$1;
    if (end <= start) continue;
    clips.add(AudioClip(
      id: '${draftId}_bed_$i',
      startTime: start,
      duration: end - start,
      sourcePath: path,
      trimStart: start,
      trimEnd: end,
      originalDuration: musicDuration ?? total,
      name: 'Music',
      volume: points[i].$2,
    ));
  }
  return clips;
}

VideoProject replaceShotFile(VideoProject project, String shotId, String path) {
  final tracks = project.tracks.map((track) {
    final clips = track.clips.map((clip) {
      if (clip is VideoClip && clip.id == shotId) {
        return clip.copyWith(sourcePath: path);
      }
      return clip;
    }).toList();
    return track.copyWith(clips: clips);
  }).toList();
  return project.copyWith(tracks: tracks);
}

// lib/features/video_editor/utils/playback_mapping.dart

import '../models/clip_model.dart';
import '../models/project_model.dart';
import 'speed_timeline_mapping.dart';

/// Video clips sorted by timeline [startTime] (visible tracks only).
List<VideoClip> sortedVideoClips(VideoProject project) {
  final list = <VideoClip>[];
  for (final t in project.videoTracks) {
    if (!t.isVisible) continue;
    for (final c in t.clips) {
      if (c is VideoClip) list.add(c);
    }
  }
  list.sort((a, b) {
    final cmp = a.startTime.compareTo(b.startTime);
    if (cmp != 0) return cmp;
    return a.id.compareTo(b.id);
  });
  return list;
}

/// First visible video clip whose timeline range contains [timelinePos].
VideoClip? activeVideoClipAt(VideoProject project, Duration timelinePos) {
  for (final track in project.videoTracks) {
    if (!track.isVisible) continue;
    for (final clip in track.clips) {
      if (clip is VideoClip) {
        if (timelinePos >= clip.startTime && timelinePos < clip.endTime) {
          return clip;
        }
      }
    }
  }
  return null;
}

/// Source file time for a timeline position inside [clip].
Duration sourcePositionForTimeline(VideoClip clip, Duration timelinePos) {
  if (useUnifiedSpeedMapping(clip)) {
    return filePositionForTimelineInClip(clip, timelinePos);
  }
  return clip.trimStart + (timelinePos - clip.startTime);
}

/// Timeline position for a source file time [filePos], using [lastTimelinePos]
/// to disambiguate duplicate segments (same source range on the timeline twice).
Duration timelinePositionForSource(
  VideoProject project,
  Duration filePos,
  Duration lastTimelinePos,
) {
  final candidates = <VideoClip>[];
  for (final t in project.videoTracks) {
    if (!t.isVisible) continue;
    for (final c in t.clips) {
      if (c is VideoClip && filePos >= c.trimStart && filePos < c.trimEnd) {
        candidates.add(c);
      }
    }
  }

  if (candidates.isEmpty) {
    final all = sortedVideoClips(project);
    if (all.isEmpty) return lastTimelinePos;
    final last = all.last;
    if (filePos >= last.trimEnd) {
      return last.endTime - const Duration(microseconds: 1);
    }
    final first = all.first;
    if (filePos < first.trimStart) {
      return first.startTime;
    }
    return lastTimelinePos;
  }

  if (candidates.length == 1) {
    final c = candidates.first;
    if (useUnifiedSpeedMapping(c)) {
      return timelinePositionForFileInClip(c, filePos, lastTimelinePos);
    }
    return c.startTime + (filePos - c.trimStart);
  }

  for (final c in candidates) {
    if (lastTimelinePos >= c.startTime && lastTimelinePos < c.endTime) {
      if (useUnifiedSpeedMapping(c)) {
        return timelinePositionForFileInClip(c, filePos, lastTimelinePos);
      }
      return c.startTime + (filePos - c.trimStart);
    }
  }

  candidates.sort((a, b) => a.startTime.compareTo(b.startTime));
  final c = candidates.first;
  if (useUnifiedSpeedMapping(c)) {
    return timelinePositionForFileInClip(c, filePos, lastTimelinePos);
  }
  return c.startTime + (filePos - c.trimStart);
}

/// Next clip on the global timeline after [current], or null if none.
VideoClip? nextVideoClipAfter(VideoProject project, VideoClip current) {
  final sorted = sortedVideoClips(project);
  for (int i = 0; i < sorted.length; i++) {
    if (sorted[i].id == current.id && i + 1 < sorted.length) {
      return sorted[i + 1];
    }
  }
  return null;
}

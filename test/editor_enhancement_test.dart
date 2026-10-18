import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart' show TextAlign;
import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/image_editor/image_history_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/clip_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/effect_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/models/project_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/services/video_project_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/utils/crop_mapping.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/utils/speed_slices.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/utils/video_looks.dart';

void main() {
  test('crop-norm maps to source pixels, not canvas size', () {
    final mapped = mappedSegmentCrop(
      cropNorm: const Rect.fromLTWH(0.1, 0.2, 0.5, 0.4),
      source: const Size(1000, 800),
      canvas: const Size(1920, 1080),
    );
    expect(mapped.offset.dx, closeTo(100, 0.01));
    expect(mapped.offset.dy, closeTo(160, 0.01));
    expect(mapped.size.width, closeTo(500, 0.01));
    expect(mapped.size.height, closeTo(320, 0.01));
  });

  test('full-frame crop uses canvas size', () {
    final mapped = mappedSegmentCrop(
      cropNorm: null,
      source: const Size(1000, 800),
      canvas: const Size(1920, 1080),
    );
    expect(mapped.offset, Offset.zero);
    expect(mapped.size, const Size(1920, 1080));
  });

  test('speed ramp slices sum to clip duration', () {
    const clip = VideoClip(
      id: 'c1',
      startTime: Duration.zero,
      duration: const Duration(seconds: 4),
      sourcePath: '/tmp/a.mp4',
      trimStart: Duration.zero,
      trimEnd: const Duration(seconds: 4),
      originalDuration: const Duration(seconds: 4),
      speedEffect: const SpeedEffect(
        mode: SpeedMode.ramp,
        rampStart: 0.5,
        rampEnd: 2.0,
      ),
    );
    final slices = speedSlicesForClip(clip);
    expect(slices, isNotEmpty);
    expect(
      sumSliceTimeline(slices).inMicroseconds,
      closeTo(clip.duration.inMicroseconds, 24),
    );
  });

  test('project JSON round-trip keeps crop, look, text align', () {
    const project = VideoProject(
      id: 'job_abc',
      name: 'Roundtrip',
      totalDuration: const Duration(seconds: 3),
      tracks: [
        Track(
          id: 'v0',
          type: TrackType.video,
          name: 'Video',
          clips: [
            VideoClip(
              id: 'clip',
              startTime: Duration.zero,
              duration: const Duration(seconds: 3),
              sourcePath: '/tmp/src.mp4',
              trimStart: Duration.zero,
              trimEnd: const Duration(seconds: 3),
              originalDuration: const Duration(seconds: 3),
              cropNorm: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
              look: VideoLook.film,
              chroma: const ChromaSettings(enabled: true, similarity: 0.3),
            ),
          ],
        ),
        Track(
          id: 't0',
          type: TrackType.text,
          name: 'Text',
          clips: [
            TextClip(
              id: 'txt',
              startTime: Duration.zero,
              duration: const Duration(seconds: 2),
              text: 'Hello',
              textAlign: TextAlign.right,
            ),
          ],
        ),
      ],
    );
    final restored = VideoProjectStore.projectFromMap(
      VideoProjectStore.projectToMap(project),
    );
    expect(restored.id, 'job_abc');
    final video = restored.tracks.first.clips.first as VideoClip;
    expect(video.look, VideoLook.film);
    expect(video.chroma.enabled, isTrue);
    expect(video.cropNorm!.width, closeTo(0.8, 0.001));
    final text = restored.tracks[1].clips.first as TextClip;
    expect(text.textAlign, TextAlign.right);
  });

  test('image history is keyed by job id and sanitizes paths', () {
    expect(ImageHistoryStore.historyIdFor(jobId: 'job-1'), 'job-1');
    expect(
      ImageHistoryStore.historyIdFor(jobId: r'D:\tmp\file.png'),
      isNot(contains(r'\')),
    );
    expect(
      ImageHistoryStore.historyIdFor(image: File(r'D:\tmp\file.png')),
      hasLength(32),
    );
  });

  test('chroma requires composition (or a PiP layer)', () {
    expect(chromaRequiresComposition(true), isTrue);
    expect(chromaRequiresComposition(false, hasPip: true), isTrue);
    expect(chromaRequiresComposition(false), isFalse);
  });
}

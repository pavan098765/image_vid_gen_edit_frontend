import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/audio_features.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/lyric_captions.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_export.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_frame.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_template.dart';

void main() {
  test('karaoke strips section tags and highlights words', () {
    final words = [
      const AlignedWord(
        word: '[Verse]\nHello',
        success: true,
        startS: 1,
        endS: 1.4,
      ),
      const AlignedWord(word: 'there', success: true, startS: 1.4, endS: 1.9),
    ];
    final ass = buildAssSubtitles(
      words: words,
      confidence: 0.8,
      playResX: 1280,
      playResY: 720,
    );
    expect(ass, isNotNull);
    expect(ass, contains(r'\k'));
    expect(ass, contains('Hello'));
    expect(ass, isNot(contains('[Verse]')));
  });

  test('a weak alignment is one line at a time', () {
    final words = [
      const AlignedWord(word: 'Hello', success: true, startS: 0, endS: 0.4),
      const AlignedWord(word: 'there', success: true, startS: 0.4, endS: 0.8),
    ];
    final ass = buildAssSubtitles(
      words: words,
      confidence: 0.1,
      playResX: 720,
      playResY: 1280,
    );
    expect(ass, isNotNull);
    expect(ass, isNot(contains(r'\k')));
    expect(ass, contains('Hello there'));
  });

  test('failed words hide the lyrics', () {
    final ass = buildAssSubtitles(
      words: const [
        AlignedWord(word: 'nope', success: false, startS: 0, endS: 1),
        AlignedWord(word: 'nope', success: false, startS: 1, endS: 2),
      ],
      confidence: 0.9,
      playResX: 100,
      playResY: 100,
    );
    expect(ass, isNull);
    expect(
      lyricSyncFor(words: const [], confidence: null),
      LyricSync.hidden,
    );
  });

  test('a sung tone lands in the mid bands', () {
    const rate = 44100;
    final samples = Float64List(rate);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = 0.8 * math.sin(2 * math.pi * 440 * i / rate);
    }
    final table = audioFeatureTableFromPcm(samples, fps: 10);
    final frame = table.frames[table.frames.length ~/ 2];
    var peak = 0;
    var peakValue = -1.0;
    for (var i = 0; i < frame.bins.length; i++) {
      if (frame.bins[i] > peakValue) {
        peakValue = frame.bins[i];
        peak = i;
      }
    }
    expect(peak, inInclusiveRange(8, 40));
    expect(frame.mid, greaterThan(frame.high));
    expect(frame.waveform.any((sample) => sample.abs() > 0.2), isTrue);
  });

  test('still and canvas commands match the template families', () {
    final still = stillVideoArgs(
      stillPath: r'C:\clips\still.png',
      audioPath: r'C:\clips\song.mp3',
      outputPath: r'C:\clips\out.mp4',
      width: 1280,
      height: 720,
      frames: 48,
    );
    expect(still.join(' '), contains('zoompan'));
    expect(still, contains('1:a:0'));

    final canvas = canvasVideoArgs(
      loopPath: '/loop.mp4',
      artPath: '/art.png',
      audioPath: '/song.mp3',
      outputPath: '/out.mp4',
      width: 720,
      height: 1280,
      seconds: 12,
    );
    expect(canvas, contains('-stream_loop'));
    expect(canvas.join(' '), contains('overlay'));

    final burn = assBurnArgs(
      videoPath: r'C:\clips\silent.mp4',
      assPath: r'C:\clips\lyrics.ass',
      fontsDir: r'C:\clips',
      outputPath: r'C:\clips\final.mp4',
    );
    expect(burn.join(' '), contains('ass='));
    expect(ffmpegFilterPath(r'C:\clips\lyrics.ass'), contains(r'\:'));
  });

  test('the four meters are in the style list', () {
    final meters = kMusicVideoTemplates.map((template) => template.meter).toSet();
    expect(meters, contains(MusicVideoMeter.wave));
    expect(meters, contains(MusicVideoMeter.line));
    expect(meters, contains(MusicVideoMeter.bars));
    expect(meters, contains(MusicVideoMeter.circular));
    expect(
      kMusicVideoTemplates.any((template) => template.needsLoopVideo),
      isTrue,
    );
    expect(
      kMusicVideoTemplates.any((template) => template.family == MusicVideoFamily.still),
      isTrue,
    );
  });

  test('a still frame paints', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    MusicVideoFramePainter(
      template: musicVideoTemplateById('circular_bars'),
      features: FrameFeatures.silent,
      title: 'Song',
      artist: 'Artist',
      lyricLine: 'Hello there',
    ).paint(canvas, const Size(128, 72));
    final image = await recorder.endRecording().toImage(128, 72);
    expect(image.width, 128);
    expect(image.height, 72);
  });
}

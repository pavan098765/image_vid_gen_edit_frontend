import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/audio_features.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/lyric_captions.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_cover.dart';
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

  test('the visualizer styles include the refined meters', () {
    final meters = kMusicVideoTemplates.map((template) => template.meter).toSet();
    expect(meters, contains(MusicVideoMeter.wave));
    expect(meters, contains(MusicVideoMeter.line));
    expect(meters, contains(MusicVideoMeter.bars));
    expect(meters, contains(MusicVideoMeter.circular));
    expect(meters, contains(MusicVideoMeter.glowBars));
    expect(meters, contains(MusicVideoMeter.ribbon));
    expect(meters, contains(MusicVideoMeter.halo));
    expect(meters, contains(MusicVideoMeter.pillars));
    expect(meters, contains(MusicVideoMeter.neon));
    expect(meters, contains(MusicVideoMeter.orbit));
    expect(meters, contains(MusicVideoMeter.columns));
    expect(meters, contains(MusicVideoMeter.pulse));
    expect(meters, contains(MusicVideoMeter.horizon));
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
    for (final template in kMusicVideoTemplates.where((item) => item.needsAudioAnalysis)) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      MusicVideoFramePainter(
        template: template.copyWith(meterColor: const Color(0xFF3AD1FF)),
        features: FrameFeatures.preview,
        title: 'Song',
        artist: 'Artist',
        lyricLine: 'Hello there',
      ).paint(canvas, const Size(160, 90));
      final image = await recorder.endRecording().toImage(160, 90);
      expect(image.width, 160);
      expect(image.height, 90);
      image.dispose();
    }
  });

  test('a lyric sheet becomes evenly timed lines', () {
    final words = evenLyricWords('[Verse]\nHello there\nSecond line', 10);
    expect(words, hasLength(2));
    expect(words.first.word, 'Hello there');
    expect(words.first.startS, 0);
    expect(words.last.startS, 5);
    final window = sungWindow(
      [0, 0, 0, 0.9, 0.9, 0.9, 0.9, 0.9, 0, 0],
      100,
    );
    expect(window.start, 30);
    expect(window.end, 80);
    final placed = evenLyricWords(
      'Hello there\nSecond line',
      window.end - window.start,
      startSeconds: window.start,
    );
    expect(placed.first.startS, 30);
    expect(musicVideoCoverPrompt(title: 'Mumbai Hustle', artist: 'Kala', lyricSheet: 'city lights', style: 'night drive'), contains('No text'));
    expect(musicVideoCoverPrompt(title: 'Mumbai Hustle', artist: 'Kala', lyricSheet: 'city lights', style: 'night drive'), contains('night drive'));
    expect(musicVideoCoverPrompt(title: 'Mumbai Hustle', artist: 'Kala', lyricSheet: 'city lights', style: 'night drive'), isNot(contains('Mumbai Hustle')));
    expect(musicVideoCoverPrompt(title: 'Mumbai Hustle', artist: 'Kala', lyricSheet: 'city lights', style: 'night drive'), isNot(contains('city lights')));
    expect(
      lyricLookupMessage('Choose a music action: song, lyrics, video.'),
      'Timed lyrics are not available for this song yet.',
    );
  });
}

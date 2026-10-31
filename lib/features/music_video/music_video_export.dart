import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as im;
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/audio_features.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/lyric_captions.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_frame.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_template.dart';
import 'package:path_provider/path_provider.dart';

typedef MusicVideoProgress = void Function(double progress, String label);

class MusicVideoException implements Exception {
  final String message;

  const MusicVideoException(this.message);

  @override
  String toString() => message;
}

class MusicVideoExportRequest {
  final MusicVideoTemplate template;
  final MusicVideoAspect aspect;
  final String audioPath;
  final Uint8List? coverBytes;
  final String? loopVideoPath;
  final List<AlignedWord> words;
  final double? lyricConfidence;
  final bool lyricsEnabled;
  final String title;
  final String artist;
  final double? durationSeconds;

  const MusicVideoExportRequest({
    required this.template,
    required this.aspect,
    required this.audioPath,
    this.coverBytes,
    this.loopVideoPath,
    this.words = const [],
    this.lyricConfidence,
    this.lyricsEnabled = false,
    this.title = '',
    this.artist = '',
    this.durationSeconds,
  });
}

String ffmpegFilterPath(String path) {
  return path
      .replaceAll('\\', '/')
      .replaceAll(':', r'\:')
      .replaceAll("'", r"\'")
      .replaceAll(',', r'\,');
}

int musicVideoFrameCount(double seconds) {
  final frames = (seconds * kMusicVideoFps).round();
  if (frames < kMusicVideoFps) return kMusicVideoFps;
  const maxFrames = kMusicVideoFps * 60 * 8;
  if (frames > maxFrames) return maxFrames;
  return frames;
}

List<String> stillVideoArgs({
  required String stillPath,
  required String audioPath,
  required String outputPath,
  required int width,
  required int height,
  required int frames,
}) {
  return [
    '-y',
    '-loop',
    '1',
    '-i',
    stillPath,
    '-i',
    audioPath,
    '-filter_complex',
    "[0:v]zoompan=z='min(1+0.06*on/$frames,1.06)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$frames:s=${width}x$height:fps=$kMusicVideoFps[v]",
    '-map',
    '[v]',
    '-map',
    '1:a:0',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-shortest',
    '-movflags',
    '+faststart',
    outputPath,
  ];
}

List<String> canvasVideoArgs({
  required String loopPath,
  required String artPath,
  required String audioPath,
  required String outputPath,
  required int width,
  required int height,
  required double seconds,
}) {
  return [
    '-y',
    '-stream_loop',
    '-1',
    '-i',
    loopPath,
    '-loop',
    '1',
    '-i',
    artPath,
    '-i',
    audioPath,
    '-filter_complex',
    '[0:v]scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height,setsar=1[bg];'
        '[1:v]scale=$width:$height,format=rgba[art];'
        '[bg][art]overlay=0:0:shortest=1[v]',
    '-map',
    '[v]',
    '-map',
    '2:a:0',
    '-t',
    seconds.toStringAsFixed(3),
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-shortest',
    '-movflags',
    '+faststart',
    outputPath,
  ];
}

List<String> frameSequenceArgs({
  required String pattern,
  required String audioPath,
  required String outputPath,
}) {
  return [
    '-y',
    '-framerate',
    '$kMusicVideoFps',
    '-start_number',
    '0',
    '-i',
    pattern,
    '-i',
    audioPath,
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    '-shortest',
    '-movflags',
    '+faststart',
    outputPath,
  ];
}

List<String> assBurnArgs({
  required String videoPath,
  required String assPath,
  required String fontsDir,
  required String outputPath,
}) {
  final filter =
      "ass='${ffmpegFilterPath(assPath)}':fontsdir='${ffmpegFilterPath(fontsDir)}'";
  return [
    '-y',
    '-i',
    videoPath,
    '-vf',
    filter,
    '-c:a',
    'copy',
    outputPath,
  ];
}

Future<String> exportMusicVideo(
  MusicVideoExportRequest request, {
  MusicVideoProgress? onProgress,
}) async {
  final audio = File(request.audioPath);
  if (!audio.existsSync()) {
    throw const MusicVideoException('Save the song on this phone before making a video.');
  }
  if (request.template.needsLoopVideo) {
    final loop = request.loopVideoPath;
    if (loop == null || loop.isEmpty || !File(loop).existsSync()) {
      throw const MusicVideoException('Choose a looping video for this style.');
    }
  }

  final temp = await getTemporaryDirectory();
  final work = Directory(
    '${temp.path}/music_video_${DateTime.now().millisecondsSinceEpoch}',
  );
  await work.create(recursive: true);
  onProgress?.call(0.02, 'Preparing the picture');

  ui.Image? cover;
  final coverBytes = request.coverBytes;
  if (coverBytes != null && coverBytes.isNotEmpty) {
    cover = await _decodeImage(coverBytes);
  }
  final size = ui.Size(
    request.aspect.exportWidth.toDouble(),
    request.aspect.exportHeight.toDouble(),
  );

  AudioFeatureTable? features;
  var seconds = request.durationSeconds;
  if (request.template.needsAudioAnalysis) {
    onProgress?.call(0.08, 'Reading the song');
    final pcm = await decodeMusicVideoPcm(request.audioPath, work.path);
    features = audioFeatureTableFromPcm(pcm);
    if (features.frames.isEmpty) {
      throw const MusicVideoException('Could not read the song.');
    }
    seconds ??= features.durationSeconds;
  }
  seconds ??= await _probeDuration(request.audioPath);
  if (seconds == null || seconds < 0.4) {
    throw const MusicVideoException('Could not read how long the song is.');
  }
  final frames = musicVideoFrameCount(seconds);

  final captions = request.lyricsEnabled
      ? buildAssSubtitles(
          words: request.words,
          confidence: request.lyricConfidence,
          playResX: request.aspect.exportWidth,
          playResY: request.aspect.exportHeight,
        )
      : null;
  if (captions != null) {
    await File('${work.path}/lyrics.ass').writeAsString(captions);
    await _stageFont(work.path);
  }

  final silent = File('${work.path}/silent.mp4');
  if (request.template.family == MusicVideoFamily.canvas) {
    onProgress?.call(0.2, 'Placing the cover');
    final art = await rasterizeMusicVideoFrame(
      size: size,
      template: request.template,
      cover: cover,
      title: request.title,
      artist: request.artist,
      foregroundOnly: true,
    );
    final artPath = '${work.path}/art.png';
    await File(artPath).writeAsBytes(await _pngBytes(art));
    art.dispose();
    onProgress?.call(0.35, 'Building the video');
    final ok = await _run(canvasVideoArgs(
      loopPath: request.loopVideoPath!,
      artPath: artPath,
      audioPath: request.audioPath,
      outputPath: silent.path,
      width: request.aspect.exportWidth,
      height: request.aspect.exportHeight,
      seconds: seconds,
    ));
    if (!ok) throw const MusicVideoException('Could not build the video.');
  } else if (request.template.needsAudioAnalysis) {
    onProgress?.call(0.2, 'Drawing the cover');
    final base = await rasterizeMusicVideoFrame(
      size: size,
      template: request.template,
      cover: cover,
      title: request.title,
      artist: request.artist,
    );
    final table = features!;
    final count = frames.clamp(1, table.frames.length);
    for (var i = 0; i < count; i++) {
      final frame = await rasterizeMusicVideoFrame(
        size: size,
        template: request.template,
        base: base,
        features: table.frames[i],
      );
      final jpg = await _jpegBytes(frame);
      frame.dispose();
      final name = i.toString().padLeft(5, '0');
      await File('${work.path}/frame_$name.jpg').writeAsBytes(jpg);
      if (i % 6 == 0) {
        onProgress?.call(0.2 + 0.55 * (i / count), 'Drawing the visualizer');
        await Future<void>.delayed(Duration.zero);
      }
    }
    base.dispose();
    onProgress?.call(0.8, 'Encoding the video');
    final ok = await _run(frameSequenceArgs(
      pattern: '${work.path}/frame_%05d.jpg',
      audioPath: request.audioPath,
      outputPath: silent.path,
    ));
    if (!ok) throw const MusicVideoException('Could not encode the visualizer.');
  } else {
    onProgress?.call(0.25, 'Drawing the cover');
    final still = await rasterizeMusicVideoFrame(
      size: size,
      template: request.template,
      cover: cover,
      title: request.title,
      artist: request.artist,
    );
    final stillPath = '${work.path}/still.png';
    await File(stillPath).writeAsBytes(await _pngBytes(still));
    still.dispose();
    onProgress?.call(0.4, 'Building the video');
    final ok = await _run(stillVideoArgs(
      stillPath: stillPath,
      audioPath: request.audioPath,
      outputPath: silent.path,
      width: request.aspect.exportWidth,
      height: request.aspect.exportHeight,
      frames: frames,
    ));
    if (!ok) throw const MusicVideoException('Could not build the video.');
  }
  cover?.dispose();

  final finished = File('${work.path}/music.mp4');
  if (captions != null) {
    onProgress?.call(0.9, 'Adding lyrics');
    final ok = await _run(assBurnArgs(
      videoPath: silent.path,
      assPath: '${work.path}/lyrics.ass',
      fontsDir: work.path,
      outputPath: finished.path,
    ));
    if (!ok) throw const MusicVideoException('Could not add the lyrics.');
  } else {
    await silent.copy(finished.path);
  }
  onProgress?.call(1, 'Ready');
  return finished.path;
}

Future<ui.Image> _decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> _pngBytes(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw const MusicVideoException('Could not draw the cover.');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

Future<Uint8List> _jpegBytes(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw const MusicVideoException('Could not draw a frame.');
  final raw = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final copy = Uint8List.fromList(raw);
  final decoded = im.Image.fromBytes(
    width: image.width,
    height: image.height,
    bytes: copy.buffer,
    numChannels: 4,
    order: im.ChannelOrder.rgba,
  );
  return Uint8List.fromList(im.encodeJpg(decoded, quality: 82));
}

Future<Float64List> decodeMusicVideoPcm(String audioPath, String workDir) async {
  final folder = Directory(workDir);
  if (!folder.existsSync()) folder.createSync(recursive: true);
  final rawPath = '$workDir/song.f32le';
  final ok = await _run([
    '-y',
    '-i',
    audioPath,
    '-ac',
    '1',
    '-ar',
    '$kMusicVideoSampleRate',
    '-f',
    'f32le',
    rawPath,
  ]);
  if (!ok) throw const MusicVideoException('Could not read the song.');
  final bytes = await File(rawPath).readAsBytes();
  if (bytes.length < 4) throw const MusicVideoException('Could not read the song.');
  return pcmFromFloat32Bytes(bytes);
}

Future<double?> _probeDuration(String path) async {
  try {
    final session = await FFprobeKit.getMediaInformation(path);
    final raw = session.getMediaInformation()?.getDuration();
    return raw == null ? null : double.tryParse(raw);
  } catch (_) {
    return null;
  }
}

Future<void> _stageFont(String workDir) async {
  final data = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
  await File('$workDir/Roboto-Regular.ttf').writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
}

Future<bool> _run(List<String> args) async {
  final session = await FFmpegKit.executeWithArguments(args);
  final code = await session.getReturnCode();
  return ReturnCode.isSuccess(code);
}

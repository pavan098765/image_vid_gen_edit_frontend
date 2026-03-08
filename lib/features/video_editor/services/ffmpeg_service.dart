// lib/features/video_editor/services/ffmpeg_service.dart

import '../models/effect_model.dart';
import '../utils/time_utils.dart';

/// Builds FFmpeg commands for all video editing operations.
///
/// Note: This service constructs FFmpeg filter-graph strings.
/// The actual execution uses `ffmpeg_kit_flutter_new`.
class FFmpegService {
  FFmpegService._();

  // ─── Trim / Split ──────────────────────────────────────────────────────────

  /// Build command to trim a video clip.
  static List<String> trimCommand({
    required String inputPath,
    required String outputPath,
    required Duration start,
    required Duration end,
  }) {
    return [
      '-y',
      '-i', inputPath,
      '-ss', TimeUtils.toFfmpegTime(start),
      '-to', TimeUtils.toFfmpegTime(end),
      '-c', 'copy',
      outputPath,
    ];
  }

  // ─── Speed Change ──────────────────────────────────────────────────────────

  /// Build command for constant speed change.
  static List<String> speedCommand({
    required String inputPath,
    required String outputPath,
    required double speed,
  }) {
    final setpts = '${(1 / speed).toStringAsFixed(4)}*PTS';
    final atempo = _buildAtempoChain(speed);

    return [
      '-y',
      '-i', inputPath,
      '-filter_complex',
      '[0:v]setpts=$setpts[v];[0:a]$atempo[a]',
      '-map', '[v]',
      '-map', '[a]',
      outputPath,
    ];
  }

  /// Build command for speed ramp (linear ramp from startSpeed to endSpeed).
  static List<String> speedRampCommand({
    required String inputPath,
    required String outputPath,
    required double startSpeed,
    required double endSpeed,
    required Duration duration,
  }) {
    // Use setpts expression for smooth ramp
    // pts/tb gives time in seconds; interpolate speed linearly
    final totalSec = duration.inMilliseconds / 1000.0;
    final expr =
        '(1/$startSpeed + (1/$endSpeed - 1/$startSpeed) * (T/$totalSec)) * PTS / TB';

    return [
      '-y',
      '-i', inputPath,
      '-filter_complex',
      '[0:v]setpts=\'$expr\'[v]',
      '-map', '[v]',
      '-an', // audio not supported in ramp mode
      outputPath,
    ];
  }

  /// FFmpeg's atempo filter only accepts 0.5..2.0, so chain for bigger values.
  static String _buildAtempoChain(double speed) {
    final List<String> parts = [];
    var remaining = speed;

    while (remaining > 2.0) {
      parts.add('atempo=2.0');
      remaining /= 2.0;
    }
    while (remaining < 0.5) {
      parts.add('atempo=0.5');
      remaining /= 0.5;
    }
    parts.add('atempo=${remaining.toStringAsFixed(4)}');
    return parts.join(',');
  }

  // ─── Transitions ───────────────────────────────────────────────────────────

  /// Build command to apply a transition between two clips.
  static List<String> transitionCommand({
    required String input1Path,
    required String input2Path,
    required String outputPath,
    required TransitionType type,
    required Duration transitionDuration,
    required Duration clip1Duration,
  }) {
    final offsetSec = (clip1Duration - transitionDuration).inMilliseconds / 1000.0;
    final durSec = transitionDuration.inMilliseconds / 1000.0;

    String filter;
    switch (type) {
      case TransitionType.fade:
      case TransitionType.dissolve:
        filter = '[0:v][1:v]xfade=transition=fade:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.slideLeft:
        filter = '[0:v][1:v]xfade=transition=slideleft:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.slideRight:
        filter = '[0:v][1:v]xfade=transition=slideright:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.slideUp:
        filter = '[0:v][1:v]xfade=transition=slideup:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.slideDown:
        filter = '[0:v][1:v]xfade=transition=slidedown:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.zoomIn:
        filter = '[0:v][1:v]xfade=transition=circlecrop:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.zoomOut:
        filter = '[0:v][1:v]xfade=transition=circleopen:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.wipeLeft:
        filter = '[0:v][1:v]xfade=transition=wipeleft:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.wipeRight:
        filter = '[0:v][1:v]xfade=transition=wiperight:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.wipeUp:
        filter = '[0:v][1:v]xfade=transition=wipeup:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.wipeDown:
        filter = '[0:v][1:v]xfade=transition=wipedown:duration=$durSec:offset=$offsetSec[v]';
        break;
      case TransitionType.none:
        // Concatenate without transition
        filter = '[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[v][a]';
        return [
          '-y',
          '-i', input1Path,
          '-i', input2Path,
          '-filter_complex', filter,
          '-map', '[v]',
          '-map', '[a]',
          outputPath,
        ];
    }

    // Audio crossfade
    final audioFilter =
        '[0:a][1:a]acrossfade=d=$durSec:c1=tri:c2=tri[a]';

    return [
      '-y',
      '-i', input1Path,
      '-i', input2Path,
      '-filter_complex', '$filter;$audioFilter',
      '-map', '[v]',
      '-map', '[a]',
      outputPath,
    ];
  }

  // ─── Audio Mix ─────────────────────────────────────────────────────────────

  /// Build command to mix multiple audio tracks into a video.
  static List<String> audioMixCommand({
    required String videoPath,
    required List<AudioMixInput> audioInputs,
    required String outputPath,
  }) {
    final args = <String>['-y', '-i', videoPath];

    // Add audio inputs
    for (final ai in audioInputs) {
      args.addAll(['-i', ai.path]);
    }

    // Build amix filter
    final n = audioInputs.length + 1; // video audio + extra tracks
    final filterParts = <String>[];
    for (int i = 0; i < n; i++) {
      filterParts.add('[$i:a]');
    }
    final amix = '${filterParts.join()}amix=inputs=$n:normalize=0[a]';

    args.addAll([
      '-filter_complex', amix,
      '-map', '0:v',
      '-map', '[a]',
      '-c:v', 'copy',
      outputPath,
    ]);

    return args;
  }

  // ─── Color Filter ──────────────────────────────────────────────────────────

  /// Build command for colour adjustments.
  static List<String> colorAdjustmentCommand({
    required String inputPath,
    required String outputPath,
    required double brightness,
    required double contrast,
    required double saturation,
  }) {
    final br = brightness / 100; // normalize to -1..1
    return [
      '-y',
      '-i', inputPath,
      '-vf',
      'eq=brightness=$br:contrast=$contrast:saturation=$saturation',
      '-c:a', 'copy',
      outputPath,
    ];
  }

  // ─── Text Burn-In ──────────────────────────────────────────────────────────

  /// Build command to burn text overlays into video.
  static List<String> textOverlayCommand({
    required String inputPath,
    required String outputPath,
    required String text,
    required double fontSize,
    required String fontColor,
    required double x,
    required double y,
    required Duration startTime,
    required Duration endTime,
  }) {
    final enable = "between(t,${startTime.inMilliseconds / 1000},${endTime.inMilliseconds / 1000})";

    return [
      '-y',
      '-i', inputPath,
      '-vf',
      "drawtext=text='$text':fontsize=$fontSize:fontcolor=$fontColor:x=$x:y=$y:enable='$enable'",
      '-c:a', 'copy',
      outputPath,
    ];
  }

  // ─── PiP Overlay ───────────────────────────────────────────────────────────

  /// Build command for picture-in-picture overlay.
  static List<String> pipOverlayCommand({
    required String mainVideoPath,
    required String pipVideoPath,
    required String outputPath,
    required double scale,
    required double x,
    required double y,
    required double opacity,
  }) {
    final scaleStr = 'iw*$scale:ih*$scale';
    // overlay position as fraction of output size
    final ovX = 'W*$x-w/2';
    final ovY = 'H*$y-h/2';

    return [
      '-y',
      '-i', mainVideoPath,
      '-i', pipVideoPath,
      '-filter_complex',
      '[1:v]scale=$scaleStr,format=rgba,colorchannelmixer=aa=$opacity[pip];[0:v][pip]overlay=$ovX:$ovY:shortest=1[v]',
      '-map', '[v]',
      '-map', '0:a',
      '-c:a', 'copy',
      outputPath,
    ];
  }

  // ─── Final Export ──────────────────────────────────────────────────────────

  /// Build the final export command with quality settings.
  static List<String> finalExportCommand({
    required String inputPath,
    required String outputPath,
    required int height,
    required int bitrate,
    required int fps,
    required String format,
  }) {
    return [
      '-y',
      '-i', inputPath,
      '-vf', 'scale=-2:$height',
      '-c:v', 'libx264',
      '-b:v', '$bitrate',
      '-r', '$fps',
      '-c:a', 'aac',
      '-b:a', '192k',
      '-movflags', '+faststart',
      '-f', format,
      outputPath,
    ];
  }
}

/// Input descriptor for audio mixing.
class AudioMixInput {
  final String path;
  final double volume;
  final Duration offset;

  const AudioMixInput({
    required this.path,
    this.volume = 1.0,
    this.offset = Duration.zero,
  });
}

// lib/features/video_editor/services/export_service.dart

import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/clip_model.dart';
import '../models/effect_model.dart';
import '../models/project_model.dart';
import '../utils/color_matrix_presets.dart';

/// Orchestrates the full export pipeline using FFmpeg Kit.
///
/// **Keyframe animation** on clips is applied in the preview only; FFmpeg export
/// does not yet evaluate [KeyframeTrack]s.
///
/// Pipeline:
///   1. Gather & sort video clips
///   2. Trim + speed-adjust each clip
///   2b. Per-clip Pass A — color / filters / transition fade on each segment
///   3. Concatenate clips
///   4. Pass B — text + sticker overlays (separate so drawtext failures
///      don't kill colour effects)
///   5. PiP overlays
///   6. Audio mixing
///   7. Final encode (scale, bitrate, fps)
class ExportService {
  static Future<String?> exportProject({
    required VideoProject project,
    required Function(double progress) onProgress,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final workDir = Directory('${tempDir.path}/kala_export_$ts');
      await workDir.create(recursive: true);

      onProgress(0.05);

      // ─── 1. Gather video clips ──────────────────────────────────────
      final videoClips = <VideoClip>[];
      for (final track in project.videoTracks) {
        for (final clip in track.clips) {
          if (clip is VideoClip) videoClips.add(clip);
        }
      }
      if (videoClips.isEmpty) return null;
      videoClips.sort((a, b) => a.startTime.compareTo(b.startTime));

      onProgress(0.10);

      // ─── 2. Trim + speed ────────────────────────────────────────────
      final processedPaths = <String>[];
      for (int i = 0; i < videoClips.length; i++) {
        final clip = videoClips[i];
        final out = '${workDir.path}/clip_$i.mp4';
        final hasSpeed = (clip.speedEffect.speed - 1.0).abs() > 0.01;
        final hasTrim =
            clip.trimStart > Duration.zero || clip.trimEnd < clip.originalDuration;

        if (!hasTrim && !hasSpeed) {
          processedPaths.add(clip.sourcePath);
        } else {
          final args = <String>['-y'];
          if (hasTrim) {
            args.addAll(['-ss', _dur(clip.trimStart), '-to', _dur(clip.trimEnd)]);
          }
          args.addAll(['-i', clip.sourcePath]);
          if (hasSpeed) {
            final sp = clip.speedEffect.speed;
            final setpts = '${(1 / sp).toStringAsFixed(4)}*PTS';
            final withAudio = <String>[
              ...args,
              '-filter_complex',
              '[0:v]setpts=$setpts[v];[0:a]${_atempoChain(sp)}[a]',
              '-map', '[v]', '-map', '[a]',
              out,
            ];
            final videoOnly = <String>[
              ...args,
              '-filter_complex', '[0:v]setpts=$setpts[v]',
              '-map', '[v]', '-an',
              out,
            ];
            processedPaths.add(
              (await _run(withAudio) || await _run(videoOnly)) ? out : clip.sourcePath,
            );
          } else {
            args.addAll(['-c', 'copy']);
            args.add(out);
            processedPaths.add(await _run(args) ? out : clip.sourcePath);
          }
        }
        onProgress(0.10 + 0.15 * (i + 1) / videoClips.length);
      }

      // ─── 2b. Per-clip colour / transition (Pass A on each segment) ───
      final segmentPathsAfterFx = <String>[];
      for (int i = 0; i < videoClips.length; i++) {
        var segmentPath = processedPaths[i];
        final clip = videoClips[i];
        final vf = _videoFiltersPassA(clip);
        if (vf.isNotEmpty) {
          final vfStr = '${vf.join(',')},format=yuv420p';
          final outFx = '${workDir.path}/clip_${i}_passA.mp4';
          final ok = await _run([
                '-y',
                '-i',
                segmentPath,
                '-vf',
                vfStr,
                '-c:a',
                'copy',
                outFx,
              ]) ||
              await _run([
                '-y',
                '-i',
                segmentPath,
                '-vf',
                vfStr,
                '-map',
                '0:v',
                '-an',
                outFx,
              ]);
          if (ok) segmentPath = outFx;
        }
        segmentPathsAfterFx.add(segmentPath);
        onProgress(0.25 + 0.08 * (i + 1) / videoClips.length);
      }

      // ─── 3. Concatenate ─────────────────────────────────────────────
      String cur;
      if (segmentPathsAfterFx.length == 1) {
        cur = segmentPathsAfterFx.first;
      } else {
        cur = '${workDir.path}/concat.mp4';
        final listFile = File('${workDir.path}/concat_list.txt');
        await listFile.writeAsString(
          segmentPathsAfterFx
              .map((p) => "file '${p.replaceAll("'", "'\\''")}'")
              .join('\n'),
        );
        if (!await _run([
              '-y',
              '-f',
              'concat',
              '-safe',
              '0',
              '-i',
              listFile.path,
              '-c',
              'copy',
              cur,
            ])) {
          cur = segmentPathsAfterFx.first;
        }
      }
      onProgress(0.35);

      // ─── 4. Pass B — text + sticker overlays (drawtext) ─────────────
      // Separated so that if FFmpegKit was built without freetype/fontconfig
      // the colour effects from Pass A are still preserved.
      {
        final vf = <String>[];

        // Detect available font files
        const robotFont = '/system/fonts/Roboto-Regular.ttf';
        const emojiFont = '/system/fonts/NotoColorEmoji.ttf';
        final hasRobot = await File(robotFont).exists();
        final hasEmoji = await File(emojiFont).exists();

        // Text clips
        for (final track in project.textTracks) {
          if (!track.isVisible) continue;
          for (final clip in track.clips) {
            if (clip is TextClip) {
              final txt = _escDt(clip.text);
              final s = clip.startTime.inMilliseconds / 1000.0;
              final e = clip.endTime.inMilliseconds / 1000.0;
              final font = hasRobot ? ':fontfile=$robotFont' : '';
              vf.add(
                "drawtext=text='$txt'"
                ':fontsize=${clip.fontSize.toInt()}'
                ':fontcolor=${_colorHex(clip.color)}'
                '$font'
                ':x=(W*${clip.position.dx}-tw/2)'
                ':y=(H*${clip.position.dy}-th/2)'
                // ← escaped commas inside between()
                ":enable='between(t\\,$s\\,$e)'",
              );
            }
          }
        }

        // Sticker / emoji clips
        for (final track in project.stickerTracks) {
          if (!track.isVisible) continue;
          for (final clip in track.clips) {
            if (clip is StickerClip && clip.isEmoji) {
              final txt = _escDt(clip.stickerData);
              final s = clip.startTime.inMilliseconds / 1000.0;
              final e = clip.endTime.inMilliseconds / 1000.0;
              final sz = (64 * clip.scale).toInt().clamp(16, 256);
              final font = hasEmoji
                  ? ':fontfile=$emojiFont'
                  : (hasRobot ? ':fontfile=$robotFont' : '');
              vf.add(
                "drawtext=text='$txt'"
                ':fontsize=$sz'
                '$font'
                ':x=(W*${clip.position.dx}-tw/2)'
                ':y=(H*${clip.position.dy}-th/2)'
                ":enable='between(t\\,$s\\,$e)'",
              );
            }
          }
        }

        if (vf.isNotEmpty) {
          vf.add('format=yuv420p');
          final out = '${workDir.path}/text.mp4';
          if (await _run(['-y', '-i', cur, '-vf', vf.join(','), '-c:a', 'copy', out])) {
            cur = out;
          }
        }
      }
      onProgress(0.48);

      // ─── 4b. Raster sticker images (file paths) ─────────────────────
      {
        for (final track in project.stickerTracks) {
          if (!track.isVisible) continue;
          for (final clip in track.clips) {
            if (clip is! StickerClip || clip.isEmoji) continue;
            final path = clip.stickerData;
            if (!await File(path).exists()) continue;
            final out =
                '${workDir.path}/stk_img_${clip.id.hashCode & 0x7fffffff}.mp4';
            final s = clip.startTime.inMilliseconds / 1000.0;
            final e = clip.endTime.inMilliseconds / 1000.0;
            final px = clip.position.dx;
            final py = clip.position.dy;
            final w = (160 * clip.scale).clamp(16.0, 2048.0).round();
            final fc = '[1:v]scale=w=$w:h=-1,format=rgba[st];'
                '[0:v][st]overlay=W*$px-w/2:H*$py-h/2:'
                "enable='between(t\\,$s\\,$e)':eof_action=pass,"
                'format=yuv420p[v]';
            if (await _run([
                  '-y',
                  '-i',
                  cur,
                  '-loop',
                  '1',
                  '-i',
                  path,
                  '-filter_complex',
                  fc,
                  '-map',
                  '[v]',
                  '-map',
                  '0:a',
                  '-shortest',
                  '-c:a',
                  'copy',
                  out,
                ]) ||
                await _run([
                  '-y',
                  '-i',
                  cur,
                  '-loop',
                  '1',
                  '-i',
                  path,
                  '-filter_complex',
                  fc,
                  '-map',
                  '[v]',
                  '-an',
                  '-shortest',
                  out,
                ])) {
              cur = out;
            }
          }
        }
      }

      // ─── 5. PiP overlays ────────────────────────────────────────────
      {
        final pipClips = <PipClip>[];
        for (final track in project.pipTracks) {
          if (!track.isVisible) continue;
          for (final clip in track.clips) {
            if (clip is PipClip) pipClips.add(clip);
          }
        }
        for (int i = 0; i < pipClips.length; i++) {
          final pip = pipClips[i];
          var pipPath = pip.sourcePath;
          final pipNeedsTrim = pip.trimStart > Duration.zero ||
              pip.trimEnd < pip.originalDuration;
          if (pipNeedsTrim) {
            final pipCut = '${workDir.path}/pip_trim_$i.mp4';
            if (await _run([
                  '-y',
                  '-ss',
                  _dur(pip.trimStart),
                  '-to',
                  _dur(pip.trimEnd),
                  '-i',
                  pip.sourcePath,
                  '-c',
                  'copy',
                  pipCut,
                ])) {
              pipPath = pipCut;
            }
          }
          final out = '${workDir.path}/pip_$i.mp4';
          final sc = 'iw*${pip.scale}:ih*${pip.scale}';
          final ox = 'W*${pip.position.dx}-w/2';
          final oy = 'H*${pip.position.dy}-h/2';
          final s = pip.startTime.inMilliseconds / 1000.0;
          final e = pip.endTime.inMilliseconds / 1000.0;

          // eof_action=pass keeps main video going after PiP ends.
          // format=yuv420p at the end to guarantee libx264 compatibility.
          // Escaped commas inside between().
          final fc = '[1:v]scale=$sc,format=rgba,'
              'colorchannelmixer=aa=${pip.opacity}[pip];'
              '[0:v][pip]overlay=$ox:$oy:'
              "enable='between(t\\,$s\\,$e)':eof_action=pass,"
              'format=yuv420p[v]';

          if (await _run([
                '-y',
                '-i',
                cur,
                '-i',
                pipPath,
                '-filter_complex',
                fc,
                '-map',
                '[v]',
                '-map',
                '0:a',
                '-c:a',
                'copy',
                out,
              ]) ||
              await _run([
                '-y',
                '-i',
                cur,
                '-i',
                pipPath,
                '-filter_complex',
                fc,
                '-map',
                '[v]',
                '-an',
                out,
              ])) {
            cur = out;
          }
        }
      }
      onProgress(0.60);

      // ─── 6. Audio mixing ────────────────────────────────────────────
      {
        final extra = <AudioClip>[];
        AudioClip? embedded;
        for (final track in project.audioTracks) {
          if (track.isMuted) continue;
          for (final clip in track.clips) {
            if (clip is AudioClip) {
              if (clip.sourcePath == videoClips.first.sourcePath) {
                embedded = clip;
              } else {
                extra.add(clip);
              }
            }
          }
        }
        final mainVol = embedded?.volume ?? 0.0;

        if (extra.isNotEmpty || mainVol != 1.0) {
          final out = '${workDir.path}/audio.mp4';
          final args = <String>['-y', '-i', cur];
          for (final ac in extra) {
            args.addAll(['-i', ac.sourcePath]);
          }

          final filters = <String>[];
          final labels = <String>[];

          filters.add('[0:a]volume=${mainVol.toStringAsFixed(2)}[ma]');
          labels.add('[ma]');

          for (int i = 0; i < extra.length; i++) {
            final ac = extra[i];
            final delay = ac.startTime.inMilliseconds;
            filters.add(
              '[${i + 1}:a]volume=${ac.volume.toStringAsFixed(2)},'
              'adelay=$delay|$delay[a$i]',
            );
            labels.add('[a$i]');
          }
          filters.add('${labels.join()}amix=inputs=${labels.length}:normalize=0[oa]');

          args.addAll([
            '-filter_complex', filters.join(';'),
            '-map', '0:v', '-map', '[oa]', '-c:v', 'copy', out,
          ]);
          if (await _run(args)) cur = out;
        }
      }
      onProgress(0.75);

      // ─── 7. Final encode ────────────────────────────────────────────
      final settings = project.exportSettings;
      final ext = settings.format;
      final finalPath = '${workDir.path}/export_final.$ext';

      final ok = await _run([
        '-y', '-i', cur,
        '-vf', 'scale=-2:${settings.quality.height},format=yuv420p',
        '-c:v', 'libx264', '-preset', 'medium',
        '-b:v', '${settings.quality.bitrate}',
        '-r', '${settings.fps}',
        '-pix_fmt', 'yuv420p',
        '-c:a', 'aac', '-b:a', '192k',
        '-movflags', '+faststart',
        '-f', ext, finalPath,
      ]);

      onProgress(1.0);

      if (ok && await File(finalPath).exists()) return finalPath;

      // Fallback chain
      if (await File(cur).exists()) {
        if (cur != finalPath) await File(cur).copy(finalPath);
        return finalPath;
      }
      final src = File(videoClips.first.sourcePath);
      if (await src.exists()) {
        await src.copy(finalPath);
        return finalPath;
      }
      return null;
    } catch (e) {
      debugPrint('Export failed: $e');
      return null;
    }
  }

  // =========================================================================
  //  Pass A — per-clip video filters (colour + transition fade-in)
  // =========================================================================

  static List<String> _videoFiltersPassA(VideoClip clip) {
    final vf = <String>[];
    final adj = clip.colorAdjustment;
    final preset = _presetToVf(adj.filterPresetId);
    if (preset != null) vf.add(preset);
    if (adj.brightness != 0 || adj.contrast != 1.0 || adj.saturation != 1.0) {
      final br = (adj.brightness / 100).toStringAsFixed(3);
      vf.add(
        'eq=brightness=$br:contrast=${adj.contrast}:saturation=${adj.saturation}',
      );
    }
    final tr = clip.transitionIn;
    if (tr.type != TransitionType.none) {
      final frames =
          (tr.duration.inMilliseconds / 1000.0 * 30).round().clamp(1, 300);
      vf.add('fade=in:0:$frames');
    }
    return vf;
  }

  // =========================================================================
  //  Filter Preset → FFmpeg
  // =========================================================================

  /// Convert a [ColorMatrixPresets] filter ID to FFmpeg video-filter string.
  ///
  /// The 4×5 Flutter colour matrix is mapped to:
  ///   1. `colorchannelmixer` for the 4×4 mixing coefficients
  ///   2. `lutrgb` for the constant RGB offsets (5th column)
  static String? _presetToVf(String? id) {
    if (id == null || id == 'normal') return null;

    FilterPreset? preset;
    for (final p in ColorMatrixPresets.presets) {
      if (p.id == id) { preset = p; break; }
    }
    if (preset == null || preset.id == 'normal') return null;

    final m = preset.matrix;
    final parts = <String>[
      'colorchannelmixer='
      'rr=${m[0]}:rg=${m[1]}:rb=${m[2]}:ra=${m[3]}:'
      'gr=${m[5]}:gg=${m[6]}:gb=${m[7]}:ga=${m[8]}:'
      'br=${m[10]}:bg=${m[11]}:bb=${m[12]}:ba=${m[13]}:'
      'ar=${m[15]}:ag=${m[16]}:ab=${m[17]}:aa=${m[18]}',
    ];

    final rOff = m[4], gOff = m[9], bOff = m[14];
    if (rOff != 0 || gOff != 0 || bOff != 0) {
      parts.add('lutrgb=r=val+${rOff.toInt()}:g=val+${gOff.toInt()}:b=val+${bOff.toInt()}');
    }

    return parts.join(',');
  }

  // =========================================================================
  //  Helpers
  // =========================================================================

  static Future<bool> _run(List<String> args) async {
    try {
      debugPrint('FFmpeg ▶ ${args.join(' ')}');
      final session = await FFmpegKit.executeWithArguments(args);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) return true;
      final logs = await session.getAllLogsAsString();
      debugPrint('FFmpeg FAIL (${rc?.getValue()}): $logs');
      return false;
    } catch (e) {
      debugPrint('FFmpeg exception: $e');
      return false;
    }
  }

  static String _dur(Duration d) {
    final ms = d.inMilliseconds;
    final h = (ms ~/ 3600000).toString().padLeft(2, '0');
    final m = ((ms ~/ 60000) % 60).toString().padLeft(2, '0');
    final s = ((ms ~/ 1000) % 60).toString().padLeft(2, '0');
    final ml = (ms % 1000).toString().padLeft(3, '0');
    return '$h:$m:$s.$ml';
  }

  static String _atempoChain(double speed) {
    final parts = <String>[];
    var r = speed;
    while (r > 2.0) { parts.add('atempo=2.0'); r /= 2.0; }
    while (r < 0.5) { parts.add('atempo=0.5'); r /= 0.5; }
    parts.add('atempo=${r.toStringAsFixed(4)}');
    return parts.join(',');
  }

  /// Escape text for FFmpeg `drawtext`.
  static String _escDt(String text) {
    return text
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "'\\''")
        .replaceAll(':', '\\:')
        .replaceAll(';', '\\;')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]');
  }

  static String _colorHex(dynamic color) {
    if (color == null) return 'white';
    try {
      final r = ((color.value >> 16) & 0xFF).toRadixString(16).padLeft(2, '0');
      final g = ((color.value >> 8) & 0xFF).toRadixString(16).padLeft(2, '0');
      final b = (color.value & 0xFF).toRadixString(16).padLeft(2, '0');
      return '0x$r$g$b';
    } catch (_) {
      return 'white';
    }
  }
}

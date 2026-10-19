// lib/features/video_editor/services/export_service.dart

import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/clip_model.dart';
import '../models/effect_model.dart';
import '../models/keyframe_model.dart';
import '../models/project_model.dart';
import '../utils/color_matrix_presets.dart';
import '../utils/keyframe_ffmpeg_expr.dart';
import '../utils/speed_timeline_mapping.dart';
import '../utils/transition_ffmpeg.dart';
import 'native_compositor.dart';
import 'native_export_service.dart';

/// Orchestrates the full export pipeline using FFmpeg Kit.
///
/// **Keyframe animation** for text/emoji uses piecewise-linear FFmpeg expressions;
/// raster stickers use interval overlays. PiP keyframe motion uses overlay exprs.
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
    if (NativeCompositor.isSupported && !_needsKeyframedPicture(project)) {
      try {
        final path = await NativeExportService.exportProject(
          project: project,
          onProgress: onProgress,
        );
        if (path != null && path.isNotEmpty) return path;
      } catch (e, st) {
        debugPrint('Native compositor export failed, using FFmpeg: $e\n$st');
      }
    }
    return exportWithFfmpeg(project: project, onProgress: onProgress);
  }

  /// Desktop / fallback encoder. Phone and tablet prefer [NativeExportService].
  static Future<String?> exportWithFfmpeg({
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

        if (_needsSegmentedSpeed(clip)) {
          final segPath = await _exportSegmentedVariableSpeed(
            clip: clip,
            outPath: out,
            workDir: workDir,
            clipIndex: i,
          );
          processedPaths.add(segPath ?? clip.sourcePath);
          onProgress(0.10 + 0.15 * (i + 1) / videoClips.length);
          continue;
        }

        final sp = _effectiveConstantSpeed(clip);
        final hasSpeed = (sp - 1.0).abs() > 0.01;
        final hasTrim = clip.trimStart > Duration.zero ||
            clip.trimEnd < clip.originalDuration;
        final vfExtra = _clipGeometryFilters(clip);

        if (!hasTrim && !hasSpeed && vfExtra.isEmpty) {
          processedPaths.add(clip.sourcePath);
        } else {
          final args = <String>['-y'];
          if (hasTrim) {
            args.addAll(
                ['-ss', _dur(clip.trimStart), '-to', _dur(clip.trimEnd)]);
          }
          args.addAll(['-i', clip.sourcePath]);
          if (hasSpeed || vfExtra.isNotEmpty) {
            final vparts = <String>[
              ...vfExtra,
              if (hasSpeed) 'setpts=${(1 / sp).toStringAsFixed(4)}*PTS',
            ];
            final aParts = <String>[
              if (clip.reverse) 'areverse',
              if (hasSpeed) _atempoChain(sp),
            ];
            final vchain = vparts.join(',');
            final achain = aParts.isEmpty ? 'anull' : aParts.join(',');
            final withAudio = <String>[
              ...args,
              '-filter_complex',
              '[0:v]$vchain[v];[0:a]$achain[a]',
              '-map',
              '[v]',
              '-map',
              '[a]',
              out,
            ];
            final videoOnly = <String>[
              ...args,
              '-filter_complex',
              '[0:v]$vchain[v]',
              '-map',
              '[v]',
              '-an',
              out,
            ];
            processedPaths.add(
              (await _run(withAudio) || await _run(videoOnly))
                  ? out
                  : clip.sourcePath,
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
        var vf = _videoFiltersPassA(clip);
        if (vf.isNotEmpty) {
          Future<bool> runPassA(List<String> filters) async {
            final vfStr = '${filters.join(',')},format=yuv420p';
            final outFx = '${workDir.path}/clip_${i}_passA.mp4';
            return await _run([
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
          }

          var ok = await runPassA(vf);
          if (!ok &&
              clip.transitionIn.type != TransitionType.none &&
              clip.transitionIn.type != TransitionType.fade &&
              clip.transitionIn.type != TransitionType.dissolve) {
            logTransitionFallback(
                clip.transitionIn.type, 'Pass A failed; using fade');
            vf = _videoFiltersPassA(
              clip,
              transitionOverride: ClipTransition(
                type: TransitionType.fade,
                duration: clip.transitionIn.duration,
              ),
            );
            ok = await runPassA(vf);
          }
          if (ok) segmentPath = '${workDir.path}/clip_${i}_passA.mp4';
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

        const emojiFont = '/system/fonts/NotoColorEmoji.ttf';
        final hasEmoji = await File(emojiFont).exists();
        final fontPaths = <String, String>{};
        for (final track in project.textTracks) {
          if (!track.isVisible) continue;
          for (final clip in track.clips) {
            if (clip is TextClip) {
              fontPaths[clip.fontFamily] ??=
                  await bundledFontPath(clip.fontFamily, workDir);
            }
          }
        }
        final fallbackFont = await bundledFontPath('Roboto', workDir);
        final hasRobot = fallbackFont.isNotEmpty;

        // Text clips
        for (final track in project.textTracks) {
          if (!track.isVisible) continue;
          for (final clip in track.clips) {
            if (clip is TextClip) {
              _appendTextDrawtextVf(
                vf,
                clip,
                fontPaths[clip.fontFamily] ?? fallbackFont,
              );
            }
          }
        }

        // Sticker / emoji clips
        for (final track in project.stickerTracks) {
          if (!track.isVisible) continue;
          for (final clip in track.clips) {
            if (clip is StickerClip && clip.isEmoji) {
              _appendEmojiStickerDrawtextVf(
                vf,
                clip,
                hasEmoji,
                hasRobot,
                emojiFont,
                fallbackFont,
              );
            }
          }
        }

        if (vf.isNotEmpty) {
          vf.add('format=yuv420p');
          final out = '${workDir.path}/text.mp4';
          if (await _run(
              ['-y', '-i', cur, '-vf', vf.join(','), '-c:a', 'copy', out])) {
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
            final hasKf =
                clip.keyframeTracks.any((t) => t.keyframes.isNotEmpty);
            if (!hasKf) {
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
              continue;
            }

            final bounds = _allKeyframeBoundsSec(clip);
            for (int bi = 0; bi < bounds.length - 1; bi++) {
              final t0 = bounds[bi];
              final t1 = bounds[bi + 1];
              if (t1 <= t0) continue;
              final mid = (t0 + t1) / 2.0;
              final midRel = Duration(microseconds: (mid * 1000000).round()) -
                  clip.startTime;
              final ox =
                  trackFor(clip.keyframeTracks, KeyframeProperty.positionX)
                          ?.valueAt(midRel) ??
                      0.0;
              final oy =
                  trackFor(clip.keyframeTracks, KeyframeProperty.positionY)
                          ?.valueAt(midRel) ??
                      0.0;
              final sc = trackFor(clip.keyframeTracks, KeyframeProperty.scale)
                      ?.valueAt(midRel) ??
                  1.0;
              final px = (clip.position.dx + ox).clamp(0.0, 1.0);
              final py = (clip.position.dy + oy).clamp(0.0, 1.0);
              final w = (160 * clip.scale * sc).clamp(16.0, 2048.0).round();
              final intervalOut =
                  '${workDir.path}/stk_img_${clip.id.hashCode & 0x7fffffff}_$bi.mp4';
              final fc = '[1:v]scale=w=$w:h=-1,format=rgba[st];'
                  '[0:v][st]overlay=W*$px-w/2:H*$py-h/2:'
                  "enable='between(t\\,$t0\\,$t1)':eof_action=pass,"
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
                    intervalOut,
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
                    intervalOut,
                  ])) {
                cur = intervalOut;
              }
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
          final scaleTrack = pip.keyframeTracks
              .where((t) => t.property == KeyframeProperty.scale)
              .firstOrNull;
          final xTrack = pip.keyframeTracks
              .where((t) => t.property == KeyframeProperty.positionX)
              .firstOrNull;
          final yTrack = pip.keyframeTracks
              .where((t) => t.property == KeyframeProperty.positionY)
              .firstOrNull;
          final scaleExpr = scalarExprForTrack(
            track: scaleTrack,
            clipStart: pip.startTime,
            clipEnd: pip.endTime,
            constant: pip.scale,
          );
          final xFrac = scalarExprForTrack(
            track: xTrack,
            clipStart: pip.startTime,
            clipEnd: pip.endTime,
            constant: pip.position.dx,
          );
          final yFrac = scalarExprForTrack(
            track: yTrack,
            clipStart: pip.startTime,
            clipEnd: pip.endTime,
            constant: pip.position.dy,
          );
          final sc = 'iw*($scaleExpr):ih*($scaleExpr)';
          final ox = 'W*($xFrac)-w/2';
          final oy = 'H*($yFrac)-h/2';
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
        final mainSources = videoClips.map((c) => c.sourcePath).toSet();
        final embeddedClips = <AudioClip>[];
        final extra = <AudioClip>[];
        for (final track in project.audioTracks) {
          if (track.isMuted) continue;
          for (final clip in track.clips) {
            if (clip is AudioClip) {
              if (mainSources.contains(clip.sourcePath)) {
                embeddedClips.add(clip);
              } else {
                extra.add(clip);
              }
            }
          }
        }
        embeddedClips.sort((a, b) {
          final c = a.startTime.compareTo(b.startTime);
          if (c != 0) return c;
          return a.id.compareTo(b.id);
        });

        /// Embedded clips from the same source file can overlap; later clips in this
        /// sort order win (stable tie-break on id).
        String embeddedVolExpr() {
          if (embeddedClips.isEmpty) return '1.0';
          var expr = '1.0';
          for (final c in embeddedClips.reversed) {
            final s = c.startTime.inMilliseconds / 1000.0;
            final e = c.endTime.inMilliseconds / 1000.0;
            final v = c.volume.toStringAsFixed(6);
            expr = 'if(between(t\\,$s\\,$e)\\,$v\\,($expr))';
          }
          return expr;
        }

        final embExpr = embeddedVolExpr();
        final needsVol = extra.isNotEmpty || embExpr != '1.0';

        if (needsVol) {
          final out = '${workDir.path}/audio.mp4';
          final args = <String>['-y', '-i', cur];
          for (final ac in extra) {
            args.addAll(['-i', ac.sourcePath]);
          }

          final filters = <String>[];
          final labels = <String>[];

          filters.add('[0:a]volume=eval=frame:volume=\'$embExpr\'[ma]');
          labels.add('[ma]');

          for (int i = 0; i < extra.length; i++) {
            final ac = extra[i];
            final delay = ac.startTime.inMilliseconds;
            final fadeIn = ac.fadeIn.inMilliseconds / 1000.0;
            final fadeOut = ac.fadeOut.inMilliseconds / 1000.0;
            final fadeBits = StringBuffer();
            if (fadeIn > 0) fadeBits.write(',afade=t=in:st=0:d=$fadeIn');
            if (fadeOut > 0) {
              final st = (ac.duration.inMilliseconds / 1000.0) - fadeOut;
              fadeBits.write(',afade=t=out:st=${st.clamp(0, 1e6)}:d=$fadeOut');
            }
            filters.add(
              '[${i + 1}:a]${_audioVolumeFilter(ac)}'
              '${fadeBits.toString()},'
              'adelay=$delay|$delay[a$i]',
            );
            labels.add('[a$i]');
          }
          filters.add(
              '${labels.join()}amix=inputs=${labels.length}:normalize=0[oa]');

          args.addAll([
            '-filter_complex',
            filters.join(';'),
            '-map',
            '0:v',
            '-map',
            '[oa]',
            '-c:v',
            'copy',
            out,
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
        '-y',
        '-i',
        cur,
        '-vf',
        'scale=-2:${settings.quality.height},format=yuv420p',
        '-c:v',
        'libx264',
        '-preset',
        'medium',
        '-b:v',
        '${settings.quality.bitrate}',
        '-r',
        '${settings.fps}',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        '-movflags',
        '+faststart',
        '-f',
        ext,
        finalPath,
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
  //  Speed export — segmented ramp / curve
  // =========================================================================

  static bool _needsSegmentedSpeed(VideoClip c) {
    if (c.speedEffect.mode == SpeedMode.ramp) return true;
    if (c.speedEffect.mode == SpeedMode.curve &&
        c.speedEffect.curvePoints.isNotEmpty) {
      return true;
    }
    return false;
  }

  static double _effectiveConstantSpeed(VideoClip c) {
    switch (c.speedEffect.mode) {
      case SpeedMode.constant:
        return c.speedEffect.speed;
      case SpeedMode.ramp:
        return 1.0;
      case SpeedMode.curve:
        if (c.speedEffect.curvePoints.isEmpty) return c.speedEffect.speed;
        return 1.0;
    }
  }

  static Future<String?> _exportSegmentedVariableSpeed({
    required VideoClip clip,
    required String outPath,
    required Directory workDir,
    required int clipIndex,
  }) async {
    const n = exportSegmentedSpeedSegments;
    final e = clip.speedEffect;
    final S = clip.trimEnd - clip.trimStart;
    if (S <= Duration.zero) return null;

    final parts = <String>[];
    final base = '${workDir.path}/clip_${clipIndex}_seg';
    for (int i = 0; i < n; i++) {
      final u0 = i / n;
      final u1 = (i + 1) / n;
      final r0 = rAtNormalizedU(e, u0);
      final r1 = rAtNormalizedU(e, u1);
      final f0 = Duration(
        microseconds:
            clip.trimStart.inMicroseconds + (S.inMicroseconds * r0).round(),
      );
      final f1 = Duration(
        microseconds:
            clip.trimStart.inMicroseconds + (S.inMicroseconds * r1).round(),
      );
      if (f1 <= f0) continue;

      final dTus = (clip.duration.inMicroseconds * (u1 - u0)).round();
      if (dTus <= 0) continue;
      final dFus = (f1 - f0).inMicroseconds;
      final vEff = dFus / dTus;
      if (vEff < 0.05 || vEff > 20.0) continue;

      final segOut = '${base}_$i.mp4';
      final setpts = '${(1 / vEff).toStringAsFixed(6)}*PTS';
      final ok = await _run([
            '-y',
            '-ss',
            _dur(f0),
            '-to',
            _dur(f1),
            '-i',
            clip.sourcePath,
            '-filter_complex',
            '[0:v]setpts=$setpts[v];[0:a]${_atempoChain(vEff)}[a]',
            '-map',
            '[v]',
            '-map',
            '[a]',
            segOut,
          ]) ||
          await _run([
            '-y',
            '-ss',
            _dur(f0),
            '-to',
            _dur(f1),
            '-i',
            clip.sourcePath,
            '-filter_complex',
            '[0:v]setpts=$setpts[v]',
            '-map',
            '[v]',
            '-an',
            segOut,
          ]);
      if (ok) parts.add(segOut);
    }

    if (parts.isEmpty) return null;
    if (parts.length == 1) {
      await File(parts.first).copy(outPath);
      return outPath;
    }
    final listFile = File('${workDir.path}/clip_${clipIndex}_seglist.txt');
    await listFile.writeAsString(
      parts.map((p) => "file '${p.replaceAll("'", "'\\''")}'").join('\n'),
    );
    final ok = await _run([
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      listFile.path,
      '-c',
      'copy',
      outPath,
    ]);
    return ok ? outPath : null;
  }

  static List<String> _clipGeometryFilters(VideoClip clip) {
    final vf = <String>[];
    final crop = clip.cropNorm;
    if (crop != null) {
      vf.add(
        'crop=iw*${crop.width}:ih*${crop.height}:iw*${crop.left}:ih*${crop.top}',
      );
    }
    switch (clip.rotateQuarterTurns % 4) {
      case 1:
        vf.add('transpose=1');
        break;
      case 2:
        vf.add('transpose=1,transpose=1');
        break;
      case 3:
        vf.add('transpose=2');
        break;
    }
    if (clip.reverse) vf.add('reverse');
    if (clip.chroma.enabled) {
      final rgb = clip.chroma.color & 0xFFFFFF;
      final hex = rgb.toRadixString(16).padLeft(6, '0');
      vf.add(
        'chromakey=0x$hex:${clip.chroma.similarity}:${clip.chroma.smoothness}',
      );
    }
    return vf;
  }

  // =========================================================================
  //  Pass A — per-clip video filters (colour + transition fade-in)
  // =========================================================================

  static bool _needsKeyframedPicture(VideoProject project) {
    for (final track in project.videoTracks) {
      for (final clip in track.clips) {
        if (clip is! VideoClip) continue;
        for (final keys in clip.keyframeTracks) {
          if (keys.property == KeyframeProperty.scale && keys.keyframes.length >= 2) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static String _audioVolumeFilter(AudioClip ac) {
    final envelope = ac.keyframeTracks.where(
      (t) => t.property == KeyframeProperty.opacity && t.keyframes.length >= 2,
    );
    if (envelope.isEmpty) {
      return 'volume=${ac.volume.toStringAsFixed(2)}';
    }
    final frames = List<Keyframe<double>>.from(envelope.first.keyframes)
      ..sort((a, b) => a.time.compareTo(b.time));
    final knotsT = frames.map((k) => k.time.inMilliseconds / 1000.0).toList();
    final knotsV = frames.map((k) => (k.value * ac.volume).clamp(0.0, 1.0)).toList();
    final expr = ffmpegPiecewiseLinearExpr(knotsT, knotsV, ac.volume);
    return "volume=eval=frame:volume='$expr'";
  }

  static List<String> _videoFiltersPassA(VideoClip clip,
      {ClipTransition? transitionOverride}) {
    final vf = <String>[];
    final adj = clip.colorAdjustment;
    final preset = _presetToVf(adj);
    if (preset != null) vf.add(preset);
    if (adj.brightness != 0 || adj.contrast != 1.0 || adj.saturation != 1.0) {
      final br = (adj.brightness / 100).toStringAsFixed(3);
      vf.add(
        'eq=brightness=$br:contrast=${adj.contrast}:saturation=${adj.saturation}',
      );
    }
    final trIn = transitionOverride ?? clip.transitionIn;
    final trFilter = transitionInVideoFilter(trIn);
    if (trFilter != null) vf.add(trFilter);
    final push = clip.keyframeTracks.where(
      (t) => t.property == KeyframeProperty.scale && t.keyframes.length >= 2,
    );
    if (push.isNotEmpty) {
      final d = (clip.duration.inMilliseconds / 1000).clamp(0.2, 3600).toStringAsFixed(3);
      vf.add(
        "scale=trunc(iw*1.12/2)*2:trunc(ih*1.12/2)*2,"
        "crop=iw/1.12:ih/1.12:'(in_w-out_w)*min(t/$d\\,1)':'(in_h-out_h)*min(t/$d\\,1)'",
      );
    }
    return vf;
  }

  // =========================================================================
  //  Filter Preset → FFmpeg
  // =========================================================================

  /// Convert a color look to an FFmpeg video-filter string.
  ///
  /// The 4×5 Flutter colour matrix is mapped to:
  ///   1. `colorchannelmixer` for the 4×4 mixing coefficients
  ///   2. `lutrgb` for the constant RGB offsets (5th column)
  static String? _presetToVf(ColorAdjustment adj) {
    final m = ColorMatrixPresets.resolvedMatrix(
      adj.filterPresetId,
      adj.filterStrength,
    );
    if (m == null) return null;
    final parts = <String>[
      'colorchannelmixer='
          'rr=${m[0]}:rg=${m[1]}:rb=${m[2]}:ra=${m[3]}:'
          'gr=${m[5]}:gg=${m[6]}:gb=${m[7]}:ga=${m[8]}:'
          'br=${m[10]}:bg=${m[11]}:bb=${m[12]}:ba=${m[13]}:'
          'ar=${m[15]}:ag=${m[16]}:ab=${m[17]}:aa=${m[18]}',
    ];

    final rOff = m[4], gOff = m[9], bOff = m[14];
    if (rOff != 0 || gOff != 0 || bOff != 0) {
      parts.add(
          'lutrgb=r=val+${rOff.toInt()}:g=val+${gOff.toInt()}:b=val+${bOff.toInt()}');
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
    while (r > 2.0) {
      parts.add('atempo=2.0');
      r /= 2.0;
    }
    while (r < 0.5) {
      parts.add('atempo=0.5');
      r /= 0.5;
    }
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

  static String _fontColorWithAlpha(dynamic color, double opacity) {
    final o = opacity.clamp(0.0, 1.0);
    return '${_colorHex(color)}@${o.toStringAsFixed(4)}';
  }

  static bool _rotationKeyframeLogged = false;

  static void _logKeyframeRotationExportOnce() {
    if (_rotationKeyframeLogged) return;
    _rotationKeyframeLogged = true;
    debugPrint(
      'Export: keyframe rotation is not applied in FFmpeg drawtext/overlay (limitation).',
    );
  }

  static List<double> _intervalBoundsSec(
    Duration clipStart,
    Duration clipEnd,
    KeyframeTrack? track,
  ) {
    final times = <double>{};
    final s = clipStart.inMilliseconds / 1000.0;
    final e = clipEnd.inMilliseconds / 1000.0;
    times.add(s);
    times.add(e);
    if (track != null) {
      for (final k in track.keyframes) {
        final g = (clipStart + k.time).inMilliseconds / 1000.0;
        if (g >= s && g <= e) times.add(g);
      }
    }
    return times.toList()..sort();
  }

  static List<double> _allKeyframeBoundsSec(StickerClip clip) {
    final times = <double>{};
    final s = clip.startTime.inMilliseconds / 1000.0;
    final e = clip.endTime.inMilliseconds / 1000.0;
    times.add(s);
    times.add(e);
    for (final t in clip.keyframeTracks) {
      for (final k in t.keyframes) {
        final g = (clip.startTime + k.time).inMilliseconds / 1000.0;
        if (g >= s && g <= e) times.add(g);
      }
    }
    return times.toList()..sort();
  }

  static const Map<String, String> _fontAssets = {
    'Inter': 'assets/fonts/Inter-Regular.ttf',
    'Roboto': 'assets/fonts/Roboto-Regular.ttf',
    'Poppins': 'assets/fonts/Poppins-Regular.ttf',
    'Montserrat': 'assets/fonts/Montserrat-Regular.ttf',
    'Oswald': 'assets/fonts/Oswald-Regular.ttf',
  };

  static Future<String> bundledFontPath(
      String family, Directory workDir) async {
    const systemFallback = '/system/fonts/Roboto-Regular.ttf';
    Future<String?> extract(String asset) async {
      try {
        final data = await rootBundle.load(asset);
        final name = asset.split('/').last;
        final file = File('${workDir.path}/$name');
        await file.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        return file.path;
      } catch (_) {
        return null;
      }
    }

    final wanted = _fontAssets[family] ?? _fontAssets['Roboto']!;
    final path = await extract(wanted) ?? await extract(_fontAssets['Roboto']!);
    if (path != null) return path;
    if (await File(systemFallback).exists()) return systemFallback;
    return '';
  }

  static String _ffmpegFontArg(String path) {
    if (path.isEmpty) return '';
    final escaped = path
        .replaceAll('\\', '/')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'");
    return ':fontfile=$escaped';
  }

  static void _appendTextDrawtextVf(
    List<String> vf,
    TextClip clip,
    String robotFontPath,
  ) {
    final txt = _escDt(clip.text);
    final font = _ffmpegFontArg(robotFontPath);
    final s = clip.startTime.inMilliseconds / 1000.0;
    final e = clip.endTime.inMilliseconds / 1000.0;

    if (trackFor(clip.keyframeTracks, KeyframeProperty.rotation)
            ?.keyframes
            .isNotEmpty ??
        false) {
      _logKeyframeRotationExportOnce();
    }

    final kx = trackFor(clip.keyframeTracks, KeyframeProperty.positionX);
    final ky = trackFor(clip.keyframeTracks, KeyframeProperty.positionY);
    final ks = trackFor(clip.keyframeTracks, KeyframeProperty.scale);
    final kop = trackFor(clip.keyframeTracks, KeyframeProperty.opacity);

    final hasMotionKf = (kx?.keyframes.isNotEmpty ?? false) ||
        (ky?.keyframes.isNotEmpty ?? false) ||
        (ks?.keyframes.isNotEmpty ?? false);
    final hasOpKf = kop?.keyframes.isNotEmpty ?? false;

    late final String xExpr;
    late final String yExpr;
    late final String fsExpr;
    if (hasMotionKf) {
      xExpr = drawtextXExpr(
        baseX: clip.position.dx,
        offsetTrack: kx,
        clipStart: clip.startTime,
        clipEnd: clip.endTime,
      );
      yExpr = drawtextYExpr(
        baseY: clip.position.dy,
        offsetTrack: ky,
        clipStart: clip.startTime,
        clipEnd: clip.endTime,
      );
      fsExpr = fontsizeScaleExpr(
        baseSize: clip.fontSize,
        scaleTrack: ks,
        clipStart: clip.startTime,
        clipEnd: clip.endTime,
      );
    } else {
      xExpr = '(W*${clip.position.dx}-tw/2)';
      yExpr = '(H*${clip.position.dy}-th/2)';
      fsExpr = clip.fontSize.toString();
    }

    if (hasOpKf && kop != null) {
      final bounds = _intervalBoundsSec(clip.startTime, clip.endTime, kop);
      for (int i = 0; i < bounds.length - 1; i++) {
        final t0 = bounds[i];
        final t1 = bounds[i + 1];
        if (t1 <= t0) continue;
        final mid = (t0 + t1) / 2.0;
        final midRel =
            Duration(microseconds: (mid * 1000000).round()) - clip.startTime;
        final a = kop.valueAt(midRel).clamp(0.0, 1.0);
        final fc = _fontColorWithAlpha(clip.color, a);
        vf.add(
          "drawtext=text='$txt'"
          ':fontsize=$fsExpr'
          ':fontcolor=$fc'
          '$font'
          ':x=$xExpr'
          ':y=$yExpr'
          ":enable='between(t\\,${t0.toStringAsFixed(4)}\\,${t1.toStringAsFixed(4)})'",
        );
      }
    } else {
      vf.add(
        "drawtext=text='$txt'"
        ':fontsize=$fsExpr'
        ':fontcolor=${_colorHex(clip.color)}'
        '$font'
        ':x=$xExpr'
        ':y=$yExpr'
        ":enable='between(t\\,$s\\,$e)'",
      );
    }
  }

  static void _appendEmojiStickerDrawtextVf(
    List<String> vf,
    StickerClip clip,
    bool hasEmoji,
    bool hasRobot,
    String emojiFont,
    String robotFont,
  ) {
    final txt = _escDt(clip.stickerData);
    final s = clip.startTime.inMilliseconds / 1000.0;
    final e = clip.endTime.inMilliseconds / 1000.0;
    final baseSz = 64 * clip.scale;
    final font = hasEmoji
        ? _ffmpegFontArg(emojiFont)
        : (hasRobot ? _ffmpegFontArg(robotFont) : '');

    if (trackFor(clip.keyframeTracks, KeyframeProperty.rotation)
            ?.keyframes
            .isNotEmpty ??
        false) {
      _logKeyframeRotationExportOnce();
    }

    final kx = trackFor(clip.keyframeTracks, KeyframeProperty.positionX);
    final ky = trackFor(clip.keyframeTracks, KeyframeProperty.positionY);
    final ks = trackFor(clip.keyframeTracks, KeyframeProperty.scale);
    final kop = trackFor(clip.keyframeTracks, KeyframeProperty.opacity);

    final hasMotionKf = (kx?.keyframes.isNotEmpty ?? false) ||
        (ky?.keyframes.isNotEmpty ?? false) ||
        (ks?.keyframes.isNotEmpty ?? false);
    final hasOpKf = kop?.keyframes.isNotEmpty ?? false;

    late final String xExpr;
    late final String yExpr;
    late final String fsExpr;
    if (hasMotionKf) {
      xExpr = drawtextXExpr(
        baseX: clip.position.dx,
        offsetTrack: kx,
        clipStart: clip.startTime,
        clipEnd: clip.endTime,
      );
      yExpr = drawtextYExpr(
        baseY: clip.position.dy,
        offsetTrack: ky,
        clipStart: clip.startTime,
        clipEnd: clip.endTime,
      );
      fsExpr = fontsizeScaleExpr(
        baseSize: baseSz,
        scaleTrack: ks,
        clipStart: clip.startTime,
        clipEnd: clip.endTime,
      );
    } else {
      xExpr = '(W*${clip.position.dx}-tw/2)';
      yExpr = '(H*${clip.position.dy}-th/2)';
      fsExpr = baseSz.toInt().clamp(16, 256).toString();
    }

    if (hasOpKf && kop != null) {
      final bounds = _intervalBoundsSec(clip.startTime, clip.endTime, kop);
      for (int i = 0; i < bounds.length - 1; i++) {
        final t0 = bounds[i];
        final t1 = bounds[i + 1];
        if (t1 <= t0) continue;
        final mid = (t0 + t1) / 2.0;
        final midRel =
            Duration(microseconds: (mid * 1000000).round()) - clip.startTime;
        final a = kop.valueAt(midRel).clamp(0.0, 1.0);
        final fc = 'white@${a.toStringAsFixed(4)}';
        vf.add(
          "drawtext=text='$txt'"
          ':fontsize=$fsExpr'
          ':fontcolor=$fc'
          '$font'
          ':x=$xExpr'
          ':y=$yExpr'
          ":enable='between(t\\,${t0.toStringAsFixed(4)}\\,${t1.toStringAsFixed(4)})'",
        );
      }
    } else {
      vf.add(
        "drawtext=text='$txt'"
        ':fontsize=$fsExpr'
        ':fontcolor=white'
        '$font'
        ':x=$xExpr'
        ':y=$yExpr'
        ":enable='between(t\\,$s\\,$e)'",
      );
    }
  }
}

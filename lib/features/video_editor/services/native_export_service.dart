import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_video_editor/pro_video_editor.dart' as pve;

import '../models/clip_model.dart';
import '../models/effect_model.dart';
import '../models/keyframe_model.dart';
import '../models/project_model.dart';
import '../utils/color_matrix_presets.dart';
import '../utils/crop_mapping.dart';
import '../utils/speed_slices.dart';
import '../utils/video_looks.dart';
import 'text_layer_renderer.dart';

/// Maps a [VideoProject] onto the 2.x native compositor and writes a file.
class NativeExportService {
  NativeExportService._();

  static Future<String?> exportProject({
    required VideoProject project,
    required Function(double progress) onProgress,
  }) async {
    final videoClips = <VideoClip>[];
    for (final track in project.videoTracks) {
      if (!track.isVisible) continue;
      for (final clip in track.clips) {
        if (clip is VideoClip) videoClips.add(clip);
      }
    }
    if (videoClips.isEmpty) return null;
    videoClips.sort((a, b) => a.startTime.compareTo(b.startTime));

    onProgress(0.08);

    final canvas = _canvasSize(project, videoClips.first);
    final pipClips = <PipClip>[];
    for (final track in project.pipTracks) {
      if (!track.isVisible) continue;
      for (final clip in track.clips) {
        if (clip is PipClip) pipClips.add(clip);
      }
    }

    final imageLayers = await _imageLayers(project, canvas);
    onProgress(0.25);

    final colorFilters = _colorFilters(videoClips);
    final audioTracks = _audioTracks(project);
    final transform = _canvasTransform(canvas);
    final effects = looksForClips(videoClips);
    final needsComposition = chromaRequiresComposition(
      videoClips.any((c) => c.chroma.enabled),
      hasPip: pipClips.isNotEmpty,
    );

    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/kala_native_${DateTime.now().millisecondsSinceEpoch}.mp4';

    late final pve.VideoRenderData data;
    if (needsComposition) {
      data = pve.VideoRenderData(
        composition: pve.VideoComposition(
          canvasSize: canvas,
          backgroundColor: const Color(0xFF000000),
          layers: [
            pve.VideoLayer(
              clips: [
                for (final clip in videoClips) ..._segmentsForClip(clip, canvas),
              ],
            ),
            ...pipClips.map((pip) {
              final size = Size(
                canvas.width * pip.scale,
                canvas.height * pip.scale,
              );
              final offset = Offset(
                pip.position.dx * canvas.width - size.width / 2,
                pip.position.dy * canvas.height - size.height / 2,
              );
              return pve.VideoLayer(
                opacity: pip.opacity,
                transform: pve.SegmentTransform(
                  offset: offset,
                  size: size,
                  fit: pve.SegmentFit.cover,
                ),
                keyframes:
                    _layerKeyframes(pip.keyframeTracks, canvas, size, offset),
                clips: [
                  pve.VideoSegment(
                    video: pve.EditorVideo.file(File(pip.sourcePath)),
                    startTime: pip.trimStart,
                    endTime: pip.trimEnd,
                    volume: pip.volume,
                    timelineStart: pip.startTime,
                  ),
                ],
              );
            }),
          ],
        ),
        imageLayers: imageLayers,
        colorFilters: colorFilters,
        audioTracks: audioTracks,
        transform: transform,
        effects: effects,
        enableAudio: true,
        outputFormat: pve.VideoOutputFormat.mp4,
        bitrate: project.exportSettings.quality.bitrate,
        maxFrameRate: project.exportSettings.fps,
      );
    } else {
      data = pve.VideoRenderData(
        videoSegments: [
          for (final clip in videoClips) ..._segmentsForClip(clip, canvas),
        ],
        imageLayers: imageLayers,
        colorFilters: colorFilters,
        audioTracks: audioTracks,
        transform: transform,
        effects: effects,
        enableAudio: true,
        outputFormat: pve.VideoOutputFormat.mp4,
        bitrate: project.exportSettings.quality.bitrate,
        maxFrameRate: project.exportSettings.fps,
      );
    }

    onProgress(0.35);
    final sub = data.progressStream.listen((p) {
      onProgress(0.35 + 0.6 * (p.progress.clamp(0.0, 1.0)));
    });
    try {
      await pve.ProVideoEditor.instance.renderVideoToFile(outPath, data);
    } finally {
      await sub.cancel();
    }
    onProgress(1.0);
    return outPath;
  }

  static List<pve.VideoSegment> _segmentsForClip(VideoClip clip, Size canvas) {
    final volume = clip.isMuted ? 0.0 : clip.volume;
    final chroma = clip.chroma.enabled
        ? pve.ChromaKey(
            color: Color(clip.chroma.color),
            similarity: clip.chroma.similarity,
            smoothness: clip.chroma.smoothness,
            spill: clip.chroma.spill,
            backgroundColor: const Color(0xFF000000),
          )
        : null;
    final transform = _segmentTransform(clip, canvas);
    final slices = speedSlicesForClip(clip);
    var timeline = clip.startTime;
    final out = <pve.VideoSegment>[];
    for (var i = 0; i < slices.length; i++) {
      final slice = slices[i];
      out.add(pve.VideoSegment(
        video: pve.EditorVideo.file(File(clip.sourcePath)),
        startTime: slice.fileStart,
        endTime: slice.fileEnd,
        volume: volume,
        playbackSpeed: (slice.speed - 1.0).abs() > 0.01 ? slice.speed : null,
        reverseVideo: clip.reverse,
        transition: i == 0 ? _mapTransition(clip.transitionIn) : null,
        timelineStart: timeline,
        transform: transform,
        chromaKey: chroma,
      ));
      timeline += slice.timelineDuration;
    }
    return out;
  }

  static pve.SegmentTransform? _segmentTransform(VideoClip clip, Size canvas) {
    final turns = clip.rotateQuarterTurns % 4;
    if (clip.cropNorm == null && turns == 0) return null;
    final mapped = mappedSegmentCrop(
      cropNorm: clip.cropNorm,
      source: clip.resolution,
      canvas: canvas,
    );
    return pve.SegmentTransform(
      offset: mapped.offset,
      size: mapped.size,
      fit: pve.SegmentFit.cover,
      rotation: turns * 1.5707963267948966,
    );
  }

  static pve.ClipTransition? _mapTransition(ClipTransition t) {
    if (t.isNone) return null;
    switch (t.type) {
      case TransitionType.none:
        return null;
      case TransitionType.fade:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.fadeToBlack,
          duration: t.duration,
        );
      case TransitionType.dissolve:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.dissolve,
          duration: t.duration,
        );
      case TransitionType.slideLeft:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.slide,
          duration: t.duration,
          direction: pve.ClipTransitionDirection.left,
        );
      case TransitionType.slideRight:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.slide,
          duration: t.duration,
          direction: pve.ClipTransitionDirection.right,
        );
      case TransitionType.slideUp:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.slide,
          duration: t.duration,
          direction: pve.ClipTransitionDirection.up,
        );
      case TransitionType.slideDown:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.slide,
          duration: t.duration,
          direction: pve.ClipTransitionDirection.down,
        );
      case TransitionType.wipeLeft:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.wipe,
          duration: t.duration,
          direction: pve.ClipTransitionDirection.left,
        );
      case TransitionType.wipeRight:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.wipe,
          duration: t.duration,
          direction: pve.ClipTransitionDirection.right,
        );
      case TransitionType.wipeUp:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.wipe,
          duration: t.duration,
          direction: pve.ClipTransitionDirection.up,
        );
      case TransitionType.wipeDown:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.wipe,
          duration: t.duration,
          direction: pve.ClipTransitionDirection.down,
        );
      case TransitionType.zoomIn:
      case TransitionType.zoomOut:
        return pve.ClipTransition(
          type: pve.ClipTransitionType.dissolve,
          duration: t.duration,
        );
    }
  }

  static Size _canvasSize(VideoProject project, VideoClip first) {
    final src = first.resolution;
    final ar = project.exportSettings.aspectRatio;
    double ratio;
    switch (ar) {
      case AspectRatioPreset.landscape16x9:
        ratio = 16 / 9;
        break;
      case AspectRatioPreset.portrait9x16:
        ratio = 9 / 16;
        break;
      case AspectRatioPreset.square1x1:
        ratio = 1;
        break;
      case AspectRatioPreset.classic4x3:
        ratio = 4 / 3;
        break;
      case AspectRatioPreset.cinema21x9:
        ratio = 21 / 9;
        break;
      case AspectRatioPreset.original:
        return src;
    }
    final h = project.exportSettings.quality.height.toDouble();
    return Size(h * ratio, h);
  }

  static pve.ExportTransform _canvasTransform(Size canvas) {
    return pve.ExportTransform(
      width: canvas.width.round(),
      height: canvas.height.round(),
    );
  }

  static List<pve.ColorFilter> _colorFilters(List<VideoClip> clips) {
    final out = <pve.ColorFilter>[];
    for (final clip in clips) {
      final matrix = _matrixFor(clip);
      if (matrix == null) continue;
      out.add(pve.ColorFilter(
        matrix: matrix,
        startTime: clip.startTime,
        endTime: clip.endTime,
      ));
    }
    return out;
  }

  static List<double>? _matrixFor(VideoClip clip) {
    final adj = clip.colorAdjustment;
    if (adj.isDefault) return null;
    var matrix = List<double>.from(
      ColorMatrixPresets.resolvedMatrix(
            adj.filterPresetId,
            adj.filterStrength,
          ) ??
          ColorMatrixPresets.identity,
    );
    if (adj.brightness != 0) {
      final b = adj.brightness / 100 * 255;
      matrix[4] += b;
      matrix[9] += b;
      matrix[14] += b;
    }
    if (adj.contrast != 1.0) {
      final c = adj.contrast;
      final t = (1 - c) * 128;
      for (final i in [0, 6, 12]) {
        matrix[i] *= c;
      }
      matrix[4] += t;
      matrix[9] += t;
      matrix[14] += t;
    }
    if (adj.saturation != 1.0) {
      matrix = _multiplyMatrices(matrix, ColorMatrixPresets.saturation(adj.saturation));
    }
    return matrix;
  }

  static List<double> _multiplyMatrices(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = col == 4 ? a[row * 5 + 4] : 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        out[row * 5 + col] = sum;
      }
    }
    return out;
  }

  static List<pve.VideoAudioTrack> _audioTracks(VideoProject project) {
    final out = <pve.VideoAudioTrack>[];
    for (final track in project.audioTracks) {
      if (!track.isVisible || track.isMuted) continue;
      for (final clip in track.clips) {
        if (clip is! AudioClip) continue;
        if (clip.volume <= 0) continue;
        out.add(pve.VideoAudioTrack(
          path: clip.sourcePath,
          volume: clip.volume,
          audioStartTime: clip.trimStart,
          audioEndTime: clip.trimEnd,
          startTime: clip.startTime,
          endTime: clip.endTime,
          fadeInDuration: clip.fadeIn,
          fadeOutDuration: clip.fadeOut,
          equalizer: equalizerFor(clip.voiceEq),
        ));
      }
    }
    return out;
  }

  static Future<List<pve.ImageLayer>> _imageLayers(
    VideoProject project,
    Size canvas,
  ) async {
    final layers = <pve.ImageLayer>[];
    for (final track in project.textTracks) {
      if (!track.isVisible) continue;
      for (final clip in track.clips) {
        if (clip is! TextClip) continue;
        layers.addAll(await _textLayers(clip, canvas));
      }
    }
    for (final track in project.stickerTracks) {
      if (!track.isVisible) continue;
      for (final clip in track.clips) {
        if (clip is! StickerClip) continue;
        final layer = await _stickerLayer(clip, canvas);
        if (layer != null) layers.add(layer);
      }
    }
    return layers;
  }

  static Future<List<pve.ImageLayer>> _textLayers(
    TextClip clip,
    Size canvas,
  ) async {
    if (clip.animation == TextAnimation.typewriter && clip.text.isNotEmpty) {
      final n = math.min(clip.text.length, 12);
      final slice = clip.duration.inMilliseconds / n;
      final layers = <pve.ImageLayer>[];
      for (var i = 1; i <= n; i++) {
        final endIndex = ((clip.text.length * i) / n).ceil().clamp(1, clip.text.length);
        final bytes = await TextLayerRenderer.render(
          clip,
          textOverride: clip.text.substring(0, endIndex),
        );
        if (bytes.isEmpty) continue;
        final start = clip.startTime + Duration(milliseconds: (slice * (i - 1)).round());
        final end = i == n
            ? clip.endTime
            : clip.startTime + Duration(milliseconds: (slice * i).round());
        layers.add(_pngLayer(
          bytes,
          clip.position,
          canvas,
          start,
          end,
          const [],
          clip.keyframeTracks,
        ));
      }
      return layers;
    }

    final bytes = await TextLayerRenderer.render(clip);
    if (bytes.isEmpty) return const [];
    return [
      _pngLayer(
        bytes,
        clip.position,
        canvas,
        clip.startTime,
        clip.endTime,
        _textAnimation(clip),
        clip.keyframeTracks,
      ),
    ];
  }

  static List<pve.LayerAnimation> _textAnimation(TextClip clip) {
    switch (clip.animation) {
      case TextAnimation.none:
      case TextAnimation.typewriter:
        return const [];
      case TextAnimation.fadeIn:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.fade,
            phase: pve.AnimationPhase.animateIn,
            duration: clip.animationDuration,
          ),
        ];
      case TextAnimation.fadeOut:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.fade,
            phase: pve.AnimationPhase.animateOut,
            duration: clip.animationDuration,
          ),
        ];
      case TextAnimation.fadeInOut:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.fade,
            phase: pve.AnimationPhase.animateInOut,
            duration: clip.animationDuration,
          ),
        ];
      case TextAnimation.slideInLeft:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.slide,
            phase: pve.AnimationPhase.animateIn,
            duration: clip.animationDuration,
            slideDirection: pve.SlideDirection.left,
          ),
        ];
      case TextAnimation.slideInRight:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.slide,
            phase: pve.AnimationPhase.animateIn,
            duration: clip.animationDuration,
            slideDirection: pve.SlideDirection.right,
          ),
        ];
      case TextAnimation.slideInUp:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.slide,
            phase: pve.AnimationPhase.animateIn,
            duration: clip.animationDuration,
            slideDirection: pve.SlideDirection.top,
          ),
        ];
      case TextAnimation.slideInDown:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.slide,
            phase: pve.AnimationPhase.animateIn,
            duration: clip.animationDuration,
            slideDirection: pve.SlideDirection.bottom,
          ),
        ];
      case TextAnimation.scaleIn:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.scale,
            phase: pve.AnimationPhase.animateIn,
            duration: clip.animationDuration,
          ),
        ];
      case TextAnimation.bounceIn:
        return [
          pve.LayerAnimation(
            type: pve.LayerAnimationType.bounce,
            phase: pve.AnimationPhase.animateIn,
            duration: clip.animationDuration,
            curve: pve.AnimationCurve.bounceOut,
          ),
        ];
    }
  }

  static Future<pve.ImageLayer?> _stickerLayer(
    StickerClip clip,
    Size canvas,
  ) async {
    Uint8List? bytes;
    if (!clip.isEmoji) {
      final file = File(clip.stickerData);
      if (!await file.exists()) return null;
      bytes = await file.readAsBytes();
    } else {
      bytes = await TextLayerRenderer.render(
        TextClip(
          id: clip.id,
          startTime: clip.startTime,
          duration: clip.duration,
          text: clip.stickerData,
          fontSize: 64 * clip.scale,
        ),
      );
    }
    if (bytes.isEmpty) return null;
    final size = Size(160 * clip.scale, 160 * clip.scale);
    final offset = Offset(
      clip.position.dx * canvas.width - size.width / 2,
      clip.position.dy * canvas.height - size.height / 2,
    );
    return pve.ImageLayer(
      image: pve.EditorLayerImage.memory(bytes),
      offset: offset,
      size: size,
      rotation: clip.rotation,
      startTime: clip.startTime,
      endTime: clip.endTime,
      keyframes: _layerKeyframes(clip.keyframeTracks, canvas, size, offset),
    );
  }

  static pve.ImageLayer _pngLayer(
    Uint8List bytes,
    Offset position,
    Size canvas,
    Duration start,
    Duration end,
    List<pve.LayerAnimation> animations, [
    List<KeyframeTrack> tracks = const [],
  ]) {
    const w = 480.0;
    const h = 160.0;
    final offset = Offset(
      position.dx * canvas.width - w / 2,
      position.dy * canvas.height - h / 2,
    );
    return pve.ImageLayer(
      image: pve.EditorLayerImage.memory(bytes),
      offset: offset,
      size: const Size(w, h),
      startTime: start,
      endTime: end,
      animations: animations,
      keyframes: _layerKeyframes(tracks, canvas, const Size(w, h), offset),
    );
  }

  static List<pve.TimelineKeyframe> _layerKeyframes(
    List<KeyframeTrack> tracks,
    Size canvas,
    Size layerSize,
    Offset _,
  ) {
    if (tracks.every((t) => t.keyframes.isEmpty)) return const [];
    final times = <Duration>{};
    for (final t in tracks) {
      for (final k in t.keyframes) {
        times.add(k.time);
      }
    }
    if (times.isEmpty) return const [];
    final sorted = times.toList()..sort();
    return [
      for (final t in sorted)
        pve.TimelineKeyframe(
          time: t,
          offset: Offset(
            _kf(tracks, KeyframeProperty.positionX, t, 0.5) * canvas.width -
                layerSize.width / 2,
            _kf(tracks, KeyframeProperty.positionY, t, 0.5) * canvas.height -
                layerSize.height / 2,
          ),
          scale: _kf(tracks, KeyframeProperty.scale, t, 1),
          rotation: _kf(tracks, KeyframeProperty.rotation, t, 0),
          opacity: _kf(tracks, KeyframeProperty.opacity, t, 1),
          curve: _curveFor(tracks, t),
        ),
    ];
  }

  static double _kf(
    List<KeyframeTrack> tracks,
    KeyframeProperty prop,
    Duration time,
    double fallback,
  ) {
    for (final t in tracks) {
      if (t.property != prop || t.keyframes.isEmpty) continue;
      final kfs = List.of(t.keyframes)..sort((a, b) => a.time.compareTo(b.time));
      if (time <= kfs.first.time) return kfs.first.value;
      if (time >= kfs.last.time) return kfs.last.value;
      for (var i = 0; i < kfs.length - 1; i++) {
        if (time >= kfs[i].time && time <= kfs[i + 1].time) {
          final span = kfs[i + 1].time.inMilliseconds - kfs[i].time.inMilliseconds;
          if (span <= 0) return kfs[i + 1].value;
          final u = (time.inMilliseconds - kfs[i].time.inMilliseconds) / span;
          return kfs[i].value + (kfs[i + 1].value - kfs[i].value) * u;
        }
      }
    }
    return fallback;
  }

  static pve.AnimationCurve _curveFor(List<KeyframeTrack> tracks, Duration time) {
    for (final t in tracks) {
      for (final k in t.keyframes) {
        if (k.time == time) {
          switch (k.easing) {
            case KeyframeEasing.linear:
              return pve.AnimationCurve.linear;
            case KeyframeEasing.easeIn:
              return pve.AnimationCurve.easeIn;
            case KeyframeEasing.easeOut:
              return pve.AnimationCurve.easeOut;
            case KeyframeEasing.easeInOut:
              return pve.AnimationCurve.easeInOut;
            case KeyframeEasing.spring:
              return pve.AnimationCurve.elasticOut;
          }
        }
      }
    }
    return pve.AnimationCurve.linear;
  }
}

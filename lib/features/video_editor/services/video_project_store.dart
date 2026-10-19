import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../models/clip_model.dart';
import '../models/effect_model.dart';
import '../models/keyframe_model.dart';
import '../models/project_model.dart';

class VideoProjectStore {
  VideoProjectStore._();

  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/video_projects');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<File> _jsonFile(String id) async {
    final root = await _root();
    return File('${root.path}/$id.json');
  }

  static Future<void> save(VideoProject project) async {
    final file = await _jsonFile(project.id);
    await file.writeAsString(jsonEncode(projectToMap(project)));
  }

  static Future<VideoProject?> load(String id) async {
    final file = await _jsonFile(id);
    if (!file.existsSync()) return null;
    try {
      return projectFromMap(
          Map<String, dynamic>.from(jsonDecode(file.readAsStringSync())));
    } catch (_) {
      return null;
    }
  }

  static Future<VideoProject?> loadForJob(String jobId) => load(jobId);

  static Future<List<String>> listIds() async {
    final root = await _root();
    return [
      for (final e in root.listSync())
        if (e is File && e.path.toLowerCase().endsWith('.json'))
          e.uri.pathSegments.last.replaceAll(RegExp(r'\.json$'), ''),
    ];
  }

  static Map<String, dynamic> projectToMap(VideoProject p) => {
        'id': p.id,
        'name': p.name,
        'totalDurationUs': p.totalDuration.inMicroseconds,
        'export': {
          'quality': p.exportSettings.quality.name,
          'aspect': p.exportSettings.aspectRatio.name,
          'fps': p.exportSettings.fps,
          'format': p.exportSettings.format,
        },
        'tracks': p.tracks.map(_trackToMap).toList(),
      };

  static VideoProject projectFromMap(Map<String, dynamic> map) {
    final export = Map<String, dynamic>.from(map['export'] ?? {});
    return VideoProject(
      id: map['id'] as String? ?? 'proj',
      name: map['name'] as String? ?? 'Untitled Project',
      totalDuration:
          Duration(microseconds: (map['totalDurationUs'] as num?)?.toInt() ?? 0),
      exportSettings: ExportSettings(
        quality: ExportQuality.values.firstWhere(
          (e) => e.name == export['quality'],
          orElse: () => ExportQuality.high1080p,
        ),
        aspectRatio: AspectRatioPreset.values.firstWhere(
          (e) => e.name == export['aspect'],
          orElse: () => AspectRatioPreset.original,
        ),
        fps: (export['fps'] as num?)?.toInt() ?? 30,
        format: export['format'] as String? ?? 'mp4',
      ),
      tracks: [
        for (final t in (map['tracks'] as List? ?? []))
          _trackFromMap(Map<String, dynamic>.from(t as Map)),
      ],
    );
  }

  static Map<String, dynamic> _trackToMap(Track t) => {
        'id': t.id,
        'type': t.type.name,
        'name': t.name,
        'isVisible': t.isVisible,
        'isLocked': t.isLocked,
        'isMuted': t.isMuted,
        'clips': t.clips.map(_clipToMap).toList(),
      };

  static Track _trackFromMap(Map<String, dynamic> map) {
    return Track(
      id: map['id'] as String,
      type: TrackType.values.firstWhere((e) => e.name == map['type']),
      name: map['name'] as String? ?? '',
      isVisible: map['isVisible'] != false,
      isLocked: map['isLocked'] == true,
      isMuted: map['isMuted'] == true,
      clips: [
        for (final c in (map['clips'] as List? ?? []))
          _clipFromMap(Map<String, dynamic>.from(c as Map)),
      ],
    );
  }

  static Map<String, dynamic> _clipToMap(Clip c) {
    final base = <String, dynamic>{
      'id': c.id,
      'type': c.type.name,
      'startUs': c.startTime.inMicroseconds,
      'durationUs': c.duration.inMicroseconds,
      'keyframes': c.keyframeTracks.map(_kfTrackToMap).toList(),
    };
    if (c is VideoClip) {
      base.addAll(<String, dynamic>{
        'sourcePath': c.sourcePath,
        'trimStartUs': c.trimStart.inMicroseconds,
        'trimEndUs': c.trimEnd.inMicroseconds,
        'originalUs': c.originalDuration.inMicroseconds,
        'width': c.resolution.width,
        'height': c.resolution.height,
        'volume': c.volume,
        'isMuted': c.isMuted,
        'reverse': c.reverse,
        'rotate': c.rotateQuarterTurns,
        'crop': c.cropNorm == null
            ? null
            : [c.cropNorm!.left, c.cropNorm!.top, c.cropNorm!.width, c.cropNorm!.height],
        'look': c.look.name,
        'chroma': c.chroma.toJson(),
        'speed': {
          'mode': c.speedEffect.mode.name,
          'speed': c.speedEffect.speed,
          'rampStart': c.speedEffect.rampStart,
          'rampEnd': c.speedEffect.rampEnd,
        },
        'color': {
          'brightness': c.colorAdjustment.brightness,
          'contrast': c.colorAdjustment.contrast,
          'saturation': c.colorAdjustment.saturation,
          'filter': c.colorAdjustment.filterPresetId,
          'strength': c.colorAdjustment.filterStrength,
        },
        'transition': {
          'type': c.transitionIn.type.name,
          'durationUs': c.transitionIn.duration.inMicroseconds,
        },
      });
    } else if (c is AudioClip) {
      base.addAll(<String, dynamic>{
        'sourcePath': c.sourcePath,
        'trimStartUs': c.trimStart.inMicroseconds,
        'trimEndUs': c.trimEnd.inMicroseconds,
        'originalUs': c.originalDuration.inMicroseconds,
        'volume': c.volume,
        'fadeInUs': c.fadeIn.inMicroseconds,
        'fadeOutUs': c.fadeOut.inMicroseconds,
        'name': c.name,
        'voiceEq': c.voiceEq.name,
        'waveform': c.waveform,
      });
    } else if (c is TextClip) {
      base.addAll({
        'text': c.text,
        'fontFamily': c.fontFamily,
        'fontSize': c.fontSize,
        'color': c.color.toARGB32(),
        'background': c.backgroundColor.toARGB32(),
        'isBold': c.isBold,
        'isItalic': c.isItalic,
        'dx': c.position.dx,
        'dy': c.position.dy,
        'align': c.textAlign.name,
        'animation': c.animation.name,
        'animUs': c.animationDuration.inMicroseconds,
      });
    } else if (c is StickerClip) {
      base.addAll({
        'stickerData': c.stickerData,
        'isEmoji': c.isEmoji,
        'dx': c.position.dx,
        'dy': c.position.dy,
        'scale': c.scale,
        'rotation': c.rotation,
      });
    } else if (c is PipClip) {
      base.addAll({
        'sourcePath': c.sourcePath,
        'trimStartUs': c.trimStart.inMicroseconds,
        'trimEndUs': c.trimEnd.inMicroseconds,
        'originalUs': c.originalDuration.inMicroseconds,
        'dx': c.position.dx,
        'dy': c.position.dy,
        'scale': c.scale,
        'opacity': c.opacity,
        'borderRadius': c.borderRadius,
        'volume': c.volume,
      });
    }
    return base;
  }

  static Clip _clipFromMap(Map<String, dynamic> map) {
    final type = ClipType.values.firstWhere((e) => e.name == map['type']);
    final id = map['id'] as String;
    final start = Duration(microseconds: (map['startUs'] as num).toInt());
    final dur = Duration(microseconds: (map['durationUs'] as num).toInt());
    final kfs = [
      for (final k in (map['keyframes'] as List? ?? []))
        _kfTrackFromMap(Map<String, dynamic>.from(k as Map)),
    ];
    switch (type) {
      case ClipType.video:
        final crop = map['crop'] as List?;
        final speed = Map<String, dynamic>.from(map['speed'] ?? {});
        final color = Map<String, dynamic>.from(map['color'] ?? {});
        final tr = Map<String, dynamic>.from(map['transition'] ?? {});
        return VideoClip(
          id: id,
          startTime: start,
          duration: dur,
          keyframeTracks: kfs,
          sourcePath: map['sourcePath'] as String,
          trimStart:
              Duration(microseconds: (map['trimStartUs'] as num).toInt()),
          trimEnd: Duration(microseconds: (map['trimEndUs'] as num).toInt()),
          originalDuration:
              Duration(microseconds: (map['originalUs'] as num).toInt()),
          resolution: Size(
            (map['width'] as num?)?.toDouble() ?? 1920,
            (map['height'] as num?)?.toDouble() ?? 1080,
          ),
          volume: (map['volume'] as num?)?.toDouble() ?? 1,
          isMuted: map['isMuted'] == true,
          reverse: map['reverse'] == true,
          rotateQuarterTurns: (map['rotate'] as num?)?.toInt() ?? 0,
          cropNorm: crop == null
              ? null
              : Rect.fromLTWH(
                  (crop[0] as num).toDouble(),
                  (crop[1] as num).toDouble(),
                  (crop[2] as num).toDouble(),
                  (crop[3] as num).toDouble(),
                ),
          look: VideoLook.values.firstWhere(
            (e) => e.name == map['look'],
            orElse: () => VideoLook.clean,
          ),
          chroma: ChromaSettings.fromJson(
              map['chroma'] is Map ? Map<String, dynamic>.from(map['chroma']) : null),
          speedEffect: SpeedEffect(
            mode: SpeedMode.values.firstWhere(
              (e) => e.name == speed['mode'],
              orElse: () => SpeedMode.constant,
            ),
            speed: (speed['speed'] as num?)?.toDouble() ?? 1,
            rampStart: (speed['rampStart'] as num?)?.toDouble() ?? 1,
            rampEnd: (speed['rampEnd'] as num?)?.toDouble() ?? 1,
          ),
          colorAdjustment: ColorAdjustment(
            brightness: (color['brightness'] as num?)?.toDouble() ?? 0,
            contrast: (color['contrast'] as num?)?.toDouble() ?? 1,
            saturation: (color['saturation'] as num?)?.toDouble() ?? 1,
            filterPresetId: color['filter'] as String?,
            filterStrength: (color['strength'] as num?)?.toDouble() ?? 1,
          ),
          transitionIn: ClipTransition(
            type: TransitionType.values.firstWhere(
              (e) => e.name == tr['type'],
              orElse: () => TransitionType.none,
            ),
            duration: Duration(
                microseconds: (tr['durationUs'] as num?)?.toInt() ?? 500000),
          ),
        );
      case ClipType.audio:
        return AudioClip(
          id: id,
          startTime: start,
          duration: dur,
          keyframeTracks: kfs,
          sourcePath: map['sourcePath'] as String,
          trimStart:
              Duration(microseconds: (map['trimStartUs'] as num).toInt()),
          trimEnd: Duration(microseconds: (map['trimEndUs'] as num).toInt()),
          originalDuration:
              Duration(microseconds: (map['originalUs'] as num).toInt()),
          volume: (map['volume'] as num?)?.toDouble() ?? 1,
          fadeIn: Duration(microseconds: (map['fadeInUs'] as num?)?.toInt() ?? 0),
          fadeOut:
              Duration(microseconds: (map['fadeOutUs'] as num?)?.toInt() ?? 0),
          name: map['name'] as String? ?? '',
          voiceEq: VoiceEq.values.firstWhere(
            (e) => e.name == map['voiceEq'],
            orElse: () => VoiceEq.none,
          ),
          waveform: (map['waveform'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList(),
        );
      case ClipType.text:
        return TextClip(
          id: id,
          startTime: start,
          duration: dur,
          keyframeTracks: kfs,
          text: map['text'] as String? ?? '',
          fontFamily: map['fontFamily'] as String? ?? 'Inter',
          fontSize: (map['fontSize'] as num?)?.toDouble() ?? 28,
          color: Color(map['color'] as int? ?? 0xFFFFFFFF),
          backgroundColor: Color(map['background'] as int? ?? 0),
          isBold: map['isBold'] != false,
          isItalic: map['isItalic'] == true,
          position: Offset(
            (map['dx'] as num?)?.toDouble() ?? 0.5,
            (map['dy'] as num?)?.toDouble() ?? 0.5,
          ),
          textAlign: TextAlign.values.firstWhere(
            (e) => e.name == map['align'],
            orElse: () => TextAlign.center,
          ),
          animation: TextAnimation.values.firstWhere(
            (e) => e.name == map['animation'],
            orElse: () => TextAnimation.none,
          ),
          animationDuration:
              Duration(microseconds: (map['animUs'] as num?)?.toInt() ?? 400000),
        );
      case ClipType.sticker:
        return StickerClip(
          id: id,
          startTime: start,
          duration: dur,
          keyframeTracks: kfs,
          stickerData: map['stickerData'] as String? ?? '',
          isEmoji: map['isEmoji'] != false,
          position: Offset(
            (map['dx'] as num?)?.toDouble() ?? 0.5,
            (map['dy'] as num?)?.toDouble() ?? 0.5,
          ),
          scale: (map['scale'] as num?)?.toDouble() ?? 1,
          rotation: (map['rotation'] as num?)?.toDouble() ?? 0,
        );
      case ClipType.pip:
        return PipClip(
          id: id,
          startTime: start,
          duration: dur,
          keyframeTracks: kfs,
          sourcePath: map['sourcePath'] as String,
          trimStart:
              Duration(microseconds: (map['trimStartUs'] as num).toInt()),
          trimEnd: Duration(microseconds: (map['trimEndUs'] as num).toInt()),
          originalDuration:
              Duration(microseconds: (map['originalUs'] as num).toInt()),
          position: Offset(
            (map['dx'] as num?)?.toDouble() ?? 0.75,
            (map['dy'] as num?)?.toDouble() ?? 0.75,
          ),
          scale: (map['scale'] as num?)?.toDouble() ?? 0.3,
          opacity: (map['opacity'] as num?)?.toDouble() ?? 1,
          borderRadius: (map['borderRadius'] as num?)?.toDouble() ?? 8,
          volume: (map['volume'] as num?)?.toDouble() ?? 0,
        );
    }
  }

  static Map<String, dynamic> _kfTrackToMap(KeyframeTrack t) => {
        'clipId': t.clipId,
        'property': t.property.name,
        'keyframes': [
          for (final k in t.keyframes)
            {
              'timeUs': k.time.inMicroseconds,
              'value': k.value,
              'easing': k.easing.name,
            }
        ],
      };

  static KeyframeTrack _kfTrackFromMap(Map<String, dynamic> map) {
    return KeyframeTrack(
      clipId: map['clipId'] as String? ?? '',
      property: KeyframeProperty.values.firstWhere(
        (e) => e.name == map['property'],
        orElse: () => KeyframeProperty.opacity,
      ),
      keyframes: [
        for (final k in (map['keyframes'] as List? ?? []))
          Keyframe<double>(
            time: Duration(
                microseconds: ((k as Map)['timeUs'] as num).toInt()),
            value: (k['value'] as num).toDouble(),
            easing: KeyframeEasing.values.firstWhere(
              (e) => e.name == k['easing'],
              orElse: () => KeyframeEasing.linear,
            ),
          ),
      ],
    );
  }
}

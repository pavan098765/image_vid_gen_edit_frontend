// lib/features/video_editor/widgets/preview/preview_overlay.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../models/clip_model.dart' hide Clip;
import '../../models/effect_model.dart';
import '../../models/keyframe_model.dart';
import '../../state/editor_providers.dart';
import '../../state/tool_notifier.dart';

/// Renders text, sticker, and PiP overlay layers on top of the video preview.
/// Overlays are draggable to reposition them. Keyframe values are applied.
class PreviewOverlay extends ConsumerStatefulWidget {
  const PreviewOverlay({super.key});

  @override
  ConsumerState<PreviewOverlay> createState() => _PreviewOverlayState();
}

class _PreviewOverlayState extends ConsumerState<PreviewOverlay> {
  /// PiP video player controllers, keyed by clip ID.
  final Map<String, VideoPlayerController> _pipControllers = {};

  @override
  void dispose() {
    for (final c in _pipControllers.values) {
      c.dispose();
    }
    _pipControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider);
    final playback = ref.watch(playbackProvider);
    if (project == null) return const SizedBox.shrink();

    final pos = playback.position;

    // Collect visible overlays at current time
    final List<Widget> overlays = [];

    // Text overlays
    for (final track in project.textTracks) {
      if (!track.isVisible) continue;
      for (final clip in track.clips) {
        if (clip is TextClip && pos >= clip.startTime && pos < clip.endTime) {
          overlays.add(_buildTextOverlay(clip, pos));
        }
      }
    }

    // Sticker overlays
    for (final track in project.stickerTracks) {
      if (!track.isVisible) continue;
      for (final clip in track.clips) {
        if (clip is StickerClip && pos >= clip.startTime && pos < clip.endTime) {
          overlays.add(_buildStickerOverlay(clip, pos));
        }
      }
    }

    // PiP overlays
    for (final track in project.pipTracks) {
      if (!track.isVisible) continue;
      for (final clip in track.clips) {
        if (clip is PipClip && pos >= clip.startTime && pos < clip.endTime) {
          overlays.add(_buildPipOverlay(clip, pos, playback.isPlaying));
        }
      }
    }

    // Clean up PiP controllers for clips that are no longer visible
    _cleanupPipControllers(project, pos);

    return Stack(children: overlays);
  }

  void _cleanupPipControllers(dynamic project, Duration pos) {
    final activePipIds = <String>{};
    for (final track in project.pipTracks) {
      for (final clip in track.clips) {
        if (clip is PipClip && pos >= clip.startTime && pos < clip.endTime) {
          activePipIds.add(clip.id);
        }
      }
    }
    final toRemove = _pipControllers.keys
        .where((id) => !activePipIds.contains(id))
        .toList();
    for (final id in toRemove) {
      _pipControllers[id]?.dispose();
      _pipControllers.remove(id);
    }
  }

  // ─── Keyframe helpers ────────────────────────────────────────────────────

  double _getKeyframeValue(
    List<KeyframeTrack> tracks,
    KeyframeProperty prop,
    Duration relTime,
    double defaultVal,
  ) {
    final kfTrack = tracks.where((t) => t.property == prop).firstOrNull;
    if (kfTrack == null) return defaultVal;
    return kfTrack.valueAt(relTime);
  }

  // ─── Drag ────────────────────────────────────────────────────────────────

  void _writeOverlay(
    String clipId, {
    Offset? position,
    double? scale,
    double? rotation,
  }) {
    final playback = ref.read(playbackProvider);
    final clip = ref.read(projectProvider)?.findClipById(clipId);
    final recording = ref.read(toolProvider).activeTool == EditorTool.keyframe;
    if (recording && clip != null) {
      final rel = playback.position - clip.startTime;
      var tracks = List<KeyframeTrack>.from(clip.keyframeTracks);
      void setProp(KeyframeProperty p, double v) {
        final existing = tracks.where((t) => t.property == p).firstOrNull;
        if (existing == null) {
          tracks.add(KeyframeTrack(clipId: clipId, property: p)
              .setKeyframe(rel, v));
        } else {
          tracks = [
            for (final t in tracks)
              if (t.property == p) t.setKeyframe(rel, v) else t
          ];
        }
      }

      if (position != null) {
        setProp(KeyframeProperty.positionX, position.dx);
        setProp(KeyframeProperty.positionY, position.dy);
      }
      if (scale != null) setProp(KeyframeProperty.scale, scale);
      if (rotation != null) setProp(KeyframeProperty.rotation, rotation);
      ref.read(projectProvider.notifier).updateClip(
            clipId,
            (c) => c.copyWith(keyframeTracks: tracks),
          );
      return;
    }

    ref.read(projectProvider.notifier).updateClip(clipId, (c) {
      if (c is TextClip) {
        return c.copyWith(position: position ?? c.position);
      } else if (c is StickerClip) {
        return c.copyWith(
          position: position ?? c.position,
          scale: scale ?? c.scale,
          rotation: rotation ?? c.rotation,
        );
      } else if (c is PipClip) {
        return c.copyWith(
          position: position ?? c.position,
          scale: scale ?? c.scale,
        );
      }
      return c;
    });
  }

  void _onOverlayPanUpdate(String clipId, DragUpdateDetails details) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final dx = details.delta.dx / size.width;
    final dy = details.delta.dy / size.height;

    Offset pos;
    final project = ref.read(projectProvider);
    final clip = project?.findClipById(clipId);
    if (clip is TextClip) {
      pos = clip.position;
    } else if (clip is StickerClip) {
      pos = clip.position;
    } else if (clip is PipClip) {
      pos = clip.position;
    } else {
      return;
    }
    var next = Offset((pos.dx + dx).clamp(0.0, 1.0), (pos.dy + dy).clamp(0.0, 1.0));
    if ((next.dx - 0.5).abs() < 0.02) next = Offset(0.5, next.dy);
    if ((next.dy - 0.5).abs() < 0.02) next = Offset(next.dx, 0.5);
    _writeOverlay(clipId, position: next);
  }

  Widget _withHandles({
    required String clipId,
    required Widget child,
    required double scale,
    required double rotation,
    required bool selected,
  }) {
    if (!selected) return child;
    return GestureDetector(
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) return;
        var rot = rotation + details.rotation;
        const step = 0.785398; // 45 deg
        final snapped = (rot / step).round() * step;
        if ((rot - snapped).abs() < 0.12) rot = snapped;
        _writeOverlay(
          clipId,
          scale: (scale * details.scale).clamp(0.2, 4.0),
          rotation: rot,
        );
      },
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 1),
            ),
            child: child,
          ),
          Positioned(
            right: -8,
            bottom: -8,
            child: GestureDetector(
              onPanUpdate: (d) {
                final next = (scale + d.delta.dx / 120).clamp(0.2, 4.0);
                _writeOverlay(clipId, scale: next);
              },
              child: const CircleAvatar(radius: 7, backgroundColor: Colors.white),
            ),
          ),
          Positioned(
            top: -22,
            child: GestureDetector(
              onPanUpdate: (d) {
                var rot = rotation + d.delta.dx / 40;
                const step = 0.785398;
                final snapped = (rot / step).round() * step;
                if ((rot - snapped).abs() < 0.12) rot = snapped;
                _writeOverlay(clipId, rotation: rot);
              },
              child: const Icon(Icons.refresh, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Text overlay ────────────────────────────────────────────────────────

  Widget _buildTextOverlay(TextClip clip, Duration currentPos) {
    final relTime = currentPos - clip.startTime;

    // Get keyframe values
    final kfOpacity = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.opacity, relTime, 1.0,
    );
    final kfScale = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.scale, relTime, 1.0,
    );
    final kfPosX = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.positionX, relTime, 0.0,
    );
    final kfPosY = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.positionY, relTime, 0.0,
    );
    final kfRotation = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.rotation, relTime, 0.0,
    );

    // Calculate animation progress
    double animOpacity = 1.0;
    double translateX = 0.0;
    double translateY = 0.0;
    double animScale = 1.0;

    final elapsed = currentPos - clip.startTime;
    final remaining = clip.endTime - currentPos;
    final animDur = clip.animationDuration.inMilliseconds.toDouble();

    if (animDur > 0) {
      final inProgress = (elapsed.inMilliseconds / animDur).clamp(0.0, 1.0);
      final outProgress = (remaining.inMilliseconds / animDur).clamp(0.0, 1.0);

      switch (clip.animation) {
        case TextAnimation.fadeIn:
          animOpacity = inProgress;
          break;
        case TextAnimation.fadeOut:
          animOpacity = outProgress;
          break;
        case TextAnimation.fadeInOut:
          animOpacity = inProgress < 1.0 ? inProgress : outProgress;
          break;
        case TextAnimation.slideInLeft:
          translateX = (1.0 - inProgress) * -100;
          break;
        case TextAnimation.slideInRight:
          translateX = (1.0 - inProgress) * 100;
          break;
        case TextAnimation.slideInUp:
          translateY = (1.0 - inProgress) * 50;
          break;
        case TextAnimation.slideInDown:
          translateY = (1.0 - inProgress) * -50;
          break;
        case TextAnimation.scaleIn:
          animScale = 0.3 + 0.7 * inProgress;
          break;
        case TextAnimation.bounceIn:
          animScale = inProgress < 1.0 ? 0.3 + 0.7 * _bounceOut(inProgress) : 1.0;
          break;
        case TextAnimation.typewriter:
        case TextAnimation.none:
          break;
      }
    }

    // Combine keyframe + animation values
    final finalOpacity = (animOpacity * kfOpacity).clamp(0.0, 1.0);
    final finalScale = animScale * kfScale;

    // Calculate displayed text for typewriter effect
    String displayText = clip.text;
    if (clip.animation == TextAnimation.typewriter && animDur > 0) {
      final charProgress = (elapsed.inMilliseconds / (animDur * 2)).clamp(0.0, 1.0);
      final charCount = (charProgress * clip.text.length).round();
      displayText = clip.text.substring(0, charCount);
    }

    // Position: combine clip position + keyframe offset
    final posX = (clip.position.dx + kfPosX).clamp(0.0, 1.0);
    final posY = (clip.position.dy + kfPosY).clamp(0.0, 1.0);

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment(posX * 2 - 1, posY * 2 - 1),
        child: GestureDetector(
          onPanUpdate: (details) => _onOverlayPanUpdate(clip.id, details),
          child: _withHandles(
            clipId: clip.id,
            selected: clip.isSelected,
            scale: finalScale,
            rotation: kfRotation,
            child: Transform.translate(
            offset: Offset(translateX, translateY),
            child: Transform.rotate(
              angle: kfRotation,
              child: Transform.scale(
                scale: finalScale,
                child: Opacity(
                  opacity: finalOpacity,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: clip.backgroundColor.alpha > 0
                        ? BoxDecoration(
                            color: clip.backgroundColor,
                            borderRadius: BorderRadius.circular(6),
                          )
                        : null,
                    child: Text(
                      displayText,
                      textAlign: clip.textAlign,
                      style: TextStyle(
                        fontFamily: clip.fontFamily,
                        fontSize: clip.fontSize,
                        color: clip.color,
                        fontWeight: clip.isBold ? FontWeight.bold : FontWeight.normal,
                        fontStyle: clip.isItalic ? FontStyle.italic : FontStyle.normal,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.7),
                            blurRadius: 4,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Sticker overlay ─────────────────────────────────────────────────────

  Widget _buildStickerOverlay(StickerClip clip, Duration currentPos) {
    final relTime = currentPos - clip.startTime;

    final kfOpacity = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.opacity, relTime, 1.0,
    );
    final kfScale = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.scale, relTime, clip.scale,
    );
    final kfPosX = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.positionX, relTime, 0.0,
    );
    final kfPosY = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.positionY, relTime, 0.0,
    );
    final kfRotation = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.rotation, relTime, clip.rotation,
    );

    final posX = (clip.position.dx + kfPosX).clamp(0.0, 1.0);
    final posY = (clip.position.dy + kfPosY).clamp(0.0, 1.0);

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment(posX * 2 - 1, posY * 2 - 1),
        child: GestureDetector(
          onPanUpdate: (details) => _onOverlayPanUpdate(clip.id, details),
          child: _withHandles(
            clipId: clip.id,
            selected: clip.isSelected,
            scale: kfScale,
            rotation: kfRotation,
            child: Transform.rotate(
            angle: kfRotation,
            child: Transform.scale(
              scale: kfScale,
              child: Opacity(
                opacity: kfOpacity.clamp(0.0, 1.0),
                child: clip.isEmoji
                    ? Text(clip.stickerData, style: const TextStyle(fontSize: 48))
                    : Image.file(
                        File(clip.stickerData),
                        width: 48,
                        height: 48,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.image, size: 48),
                      ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  // ─── PiP overlay ─────────────────────────────────────────────────────────

  Widget _buildPipOverlay(PipClip clip, Duration currentPos, bool isPlaying) {
    final relTime = currentPos - clip.startTime;

    final kfOpacity = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.opacity, relTime, clip.opacity,
    );
    final kfScale = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.scale, relTime, clip.scale,
    );
    final kfPosX = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.positionX, relTime, 0.0,
    );
    final kfPosY = _getKeyframeValue(
      clip.keyframeTracks, KeyframeProperty.positionY, relTime, 0.0,
    );

    // Manage PiP video controller
    _ensurePipController(clip, isPlaying);

    final posX = (clip.position.dx + kfPosX).clamp(0.0, 1.0);
    final posY = (clip.position.dy + kfPosY).clamp(0.0, 1.0);

    final controller = _pipControllers[clip.id];
    final hasVideo = controller != null && controller.value.isInitialized;

    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment(posX * 2 - 1, posY * 2 - 1),
        child: GestureDetector(
          onPanUpdate: (details) => _onOverlayPanUpdate(clip.id, details),
          child: _withHandles(
            clipId: clip.id,
            selected: clip.isSelected,
            scale: kfScale,
            rotation: 0,
            child: Opacity(
            opacity: kfOpacity.clamp(0.0, 1.0),
            child: FractionallySizedBox(
              widthFactor: kfScale.clamp(0.1, 1.0),
              heightFactor: kfScale.clamp(0.1, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(clip.borderRadius),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(clip.borderRadius),
                  child: hasVideo
                      ? VideoPlayer(controller)
                      : Container(
                          color: Colors.black87,
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white54,
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }

  void _ensurePipController(PipClip clip, bool isPlaying) {
    if (!_pipControllers.containsKey(clip.id)) {
      final file = File(clip.sourcePath);
      if (!file.existsSync()) return;

      final controller = VideoPlayerController.file(file);
      _pipControllers[clip.id] = controller;
      controller.initialize().then((_) {
        if (mounted) {
          controller.setLooping(true);
          // Use the PiP clip's volume (default 0.0 so it doesn't
          // interfere with the main video audio)
          controller.setVolume(clip.volume.clamp(0.0, 1.0));
          if (isPlaying) controller.play();
          setState(() {});
        }
      });
    } else {
      final controller = _pipControllers[clip.id]!;
      if (controller.value.isInitialized) {
        // Sync volume from model every frame in case user changed it
        final targetVol = clip.volume.clamp(0.0, 1.0);
        if ((controller.value.volume - targetVol).abs() > 0.01) {
          controller.setVolume(targetVol);
        }
        // Sync play/pause state — do NOT touch the main video controller
        if (isPlaying && !controller.value.isPlaying) {
          controller.play();
        } else if (!isPlaying && controller.value.isPlaying) {
          controller.pause();
        }
      }
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  double _bounceOut(double t) {
    if (t < 1 / 2.75) {
      return 7.5625 * t * t;
    } else if (t < 2 / 2.75) {
      final t2 = t - 1.5 / 2.75;
      return 7.5625 * t2 * t2 + 0.75;
    } else if (t < 2.5 / 2.75) {
      final t2 = t - 2.25 / 2.75;
      return 7.5625 * t2 * t2 + 0.9375;
    } else {
      final t2 = t - 2.625 / 2.75;
      return 7.5625 * t2 * t2 + 0.984375;
    }
  }
}

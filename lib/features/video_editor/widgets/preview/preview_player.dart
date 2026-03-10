// lib/features/video_editor/widgets/preview/preview_player.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../models/clip_model.dart';
import '../../models/effect_model.dart';
import '../../models/project_model.dart';
import '../../state/editor_providers.dart';
import '../../utils/color_matrix_presets.dart';
import '../../utils/time_utils.dart';
import 'preview_overlay.dart';

/// The video preview area at the top of the editor.
class PreviewPlayer extends ConsumerStatefulWidget {
  /// The video player controller, managed by the parent page.
  final VideoPlayerController? controller;

  const PreviewPlayer({super.key, this.controller});

  @override
  ConsumerState<PreviewPlayer> createState() => _PreviewPlayerState();
}

class _PreviewPlayerState extends ConsumerState<PreviewPlayer> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playback = ref.watch(playbackProvider);
    final controller = widget.controller;

    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Column(
        children: [
          // Video + overlays
          Expanded(
            child: GestureDetector(
              onTap: () {
                ref.read(playbackProvider.notifier).togglePlayPause();
                if (playback.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Video (with color filter applied)
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: _buildFilteredVideo(ref, controller),
                    ),
                  ),

                  // Overlays (text, stickers)
                  Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: const PreviewOverlay(),
                    ),
                  ),

                  // Play/pause icon
                  AnimatedOpacity(
                    opacity: playback.isPlaying ? 0.0 : 0.85,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        playback.isPlaying
                            ? LucideIcons.pause
                            : LucideIcons.play,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Transport controls bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: cs.surface.withOpacity(0.95),
            child: Row(
              children: [
                // Time display
                Text(
                  TimeUtils.formatDuration(playback.position),
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.8),
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  ' / ${TimeUtils.formatDuration(playback.totalDuration)}',
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.4),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),

                const Spacer(),

                // Mute toggle
                _TransportButton(
                  icon: playback.isMuted
                      ? LucideIcons.volumeX
                      : LucideIcons.volume2,
                  onTap: () {
                    final willMute = !playback.isMuted;
                    ref.read(playbackProvider.notifier).toggleMute();
                    controller.setVolume(willMute ? 0.0 : playback.volume);
                    // Also update the selected video clip's mute state
                    final selected = ref.read(selectedClipProvider);
                    if (selected is VideoClip) {
                      ref.read(projectProvider.notifier).updateClip(
                        selected.id,
                        (c) => (c as VideoClip).copyWith(isMuted: willMute),
                      );
                    }
                  },
                ),
                const SizedBox(width: 4),

                // Undo
                _TransportButton(
                  icon: LucideIcons.undo2,
                  onTap: ref.watch(canUndoProvider)
                      ? () => ref.read(projectProvider.notifier).undo()
                      : null,
                ),
                const SizedBox(width: 4),

                // Redo
                _TransportButton(
                  icon: LucideIcons.redo2,
                  onTap: ref.watch(canRedoProvider)
                      ? () => ref.read(projectProvider.notifier).redo()
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build the video player widget, optionally wrapped in ColorFiltered.
  Widget _buildFilteredVideo(WidgetRef ref, VideoPlayerController controller) {
    final project = ref.watch(projectProvider);
    final playback = ref.watch(playbackProvider);
    Widget videoWidget = VideoPlayer(controller);

    if (project != null) {
      // Find the active video clip at the current playback position
      final activeVideoClip = _findActiveVideoClip(project, playback.position);
      if (activeVideoClip != null) {
        final adj = activeVideoClip.colorAdjustment;
        final hasFilter = adj.filterPresetId != null;
        final hasAdjustments = adj.brightness != 0 || adj.contrast != 1.0 || adj.saturation != 1.0;

        if (hasFilter || hasAdjustments) {
          // Build combined color matrix
          List<double> matrix = List<double>.from(
            ColorMatrixPresets.presets
                .firstWhere((p) => p.id == 'normal')
                .matrix,
          );

          if (hasFilter) {
            final preset = ColorMatrixPresets.presets
                .where((p) => p.id == adj.filterPresetId)
                .firstOrNull;
            if (preset != null) {
              matrix = List<double>.from(preset.matrix);
            }
          }

          // Apply brightness/contrast/saturation adjustments
          if (adj.brightness != 0) {
            matrix = _multiplyMatrices(matrix, ColorMatrixPresets.brightness(adj.brightness));
          }
          if (adj.contrast != 1.0) {
            matrix = _multiplyMatrices(matrix, ColorMatrixPresets.contrast(adj.contrast));
          }
          if (adj.saturation != 1.0) {
            matrix = _multiplyMatrices(matrix, ColorMatrixPresets.saturation(adj.saturation));
          }

          videoWidget = ColorFiltered(
            key: ValueKey('filter_${adj.filterPresetId}_${adj.brightness}_${adj.contrast}_${adj.saturation}'),
            colorFilter: ColorFilter.matrix(matrix),
            child: videoWidget,
          );
        }

        // Apply transition-in effect (fade, dissolve, slide, zoom, wipe)
        videoWidget = _applyTransitionEffect(
          videoWidget,
          activeVideoClip,
          playback.position,
        );
      }
    }

    return videoWidget;
  }

  /// Apply transition-in effect to the video widget based on the clip's transition setting.
  Widget _applyTransitionEffect(Widget child, VideoClip clip, Duration currentPos) {
    final transition = clip.transitionIn;
    if (transition.type == TransitionType.none) return child;

    // Calculate transition progress (0.0 = start, 1.0 = fully transitioned in)
    final elapsed = currentPos - clip.startTime;
    final transMs = transition.duration.inMilliseconds.toDouble();
    if (transMs <= 0 || elapsed.inMilliseconds >= transMs) return child;

    final progress = (elapsed.inMilliseconds / transMs).clamp(0.0, 1.0);

    switch (transition.type) {
      case TransitionType.fade:
      case TransitionType.dissolve:
        return Opacity(
          opacity: progress,
          child: child,
        );

      case TransitionType.slideLeft:
        return ClipRect(
          child: FractionalTranslation(
            translation: Offset(1.0 - progress, 0),
            child: child,
          ),
        );

      case TransitionType.slideRight:
        return ClipRect(
          child: FractionalTranslation(
            translation: Offset(progress - 1.0, 0),
            child: child,
          ),
        );

      case TransitionType.slideUp:
        return ClipRect(
          child: FractionalTranslation(
            translation: Offset(0, 1.0 - progress),
            child: child,
          ),
        );

      case TransitionType.slideDown:
        return ClipRect(
          child: FractionalTranslation(
            translation: Offset(0, progress - 1.0),
            child: child,
          ),
        );

      case TransitionType.zoomIn:
        final scale = 0.3 + 0.7 * progress;
        return Transform.scale(
          scale: scale,
          child: Opacity(opacity: progress, child: child),
        );

      case TransitionType.zoomOut:
        final scale = 1.0 + 0.5 * (1.0 - progress);
        return Transform.scale(
          scale: scale,
          child: Opacity(opacity: progress, child: child),
        );

      case TransitionType.wipeLeft:
        return ClipRect(
          clipper: _WipeClipper(progress: progress, direction: AxisDirection.left),
          child: child,
        );

      case TransitionType.wipeRight:
        return ClipRect(
          clipper: _WipeClipper(progress: progress, direction: AxisDirection.right),
          child: child,
        );

      case TransitionType.wipeUp:
        return ClipRect(
          clipper: _WipeClipper(progress: progress, direction: AxisDirection.up),
          child: child,
        );

      case TransitionType.wipeDown:
        return ClipRect(
          clipper: _WipeClipper(progress: progress, direction: AxisDirection.down),
          child: child,
        );

      case TransitionType.none:
        return child;
    }
  }

  VideoClip? _findActiveVideoClip(VideoProject project, Duration pos) {
    VideoClip? firstClip;
    for (final track in project.videoTracks) {
      if (!track.isVisible) continue;
      for (final clip in track.clips) {
        if (clip is VideoClip) {
          firstClip ??= clip;
          if (pos >= clip.startTime && pos < clip.endTime) {
            return clip;
          }
        }
      }
    }
    // Fallback: return the first video clip so filters always apply
    return firstClip;
  }

  /// Multiply two 4x5 color matrices.
  List<double> _multiplyMatrices(List<double> a, List<double> b) {
    final result = List<double>.filled(20, 0);
    for (int row = 0; row < 4; row++) {
      for (int col = 0; col < 5; col++) {
        double sum = 0;
        for (int k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        if (col == 4) {
          sum += a[row * 5 + 4]; // add the translation component
        }
        result[row * 5 + col] = sum;
      }
    }
    return result;
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _TransportButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 18,
          color: enabled
              ? cs.onSurface.withOpacity(0.8)
              : cs.onSurface.withOpacity(0.25),
        ),
      ),
    );
  }
}

/// Custom clipper for wipe transition effects.
class _WipeClipper extends CustomClipper<Rect> {
  final double progress;
  final AxisDirection direction;

  _WipeClipper({required this.progress, required this.direction});

  @override
  Rect getClip(Size size) {
    switch (direction) {
      case AxisDirection.right:
        return Rect.fromLTWH(0, 0, size.width * progress, size.height);
      case AxisDirection.left:
        final left = size.width * (1.0 - progress);
        return Rect.fromLTWH(left, 0, size.width - left, size.height);
      case AxisDirection.down:
        return Rect.fromLTWH(0, 0, size.width, size.height * progress);
      case AxisDirection.up:
        final top = size.height * (1.0 - progress);
        return Rect.fromLTWH(0, top, size.width, size.height - top);
    }
  }

  @override
  bool shouldReclip(_WipeClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.direction != direction;
}

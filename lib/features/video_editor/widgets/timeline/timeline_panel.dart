// lib/features/video_editor/widgets/timeline/timeline_panel.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

import '../../models/clip_model.dart';
import '../../models/effect_model.dart';
import '../../models/project_model.dart';
import '../../services/thumbnail_cache_service.dart';
import '../../state/editor_providers.dart';
import '../../state/tool_notifier.dart';
import '../../utils/editor_constants.dart';
import '../../utils/time_utils.dart';
import '../toolbar/bottom_toolbar.dart';
import 'timeline_controls.dart';
import 'timeline_playhead.dart';
import 'timeline_ruler.dart';
import 'timeline_track_row.dart';

/// Source span in the file = timeline duration × speed (constant-speed clips).
Duration _mediaSourceSpan(Duration timelineDur, double speed) {
  if (speed <= 0) return timelineDur;
  return Duration(
    microseconds: (timelineDur.inMicroseconds * speed).round(),
  );
}

/// Timeline duration from a source trim span and speed.
Duration _mediaTimelineFromSourceSpan(Duration sourceSpan, double speed) {
  if (speed <= 0) return sourceSpan;
  return Duration(
    microseconds: (sourceSpan.inMicroseconds / speed).round(),
  );
}

/// The multi-track timeline panel.
class TimelinePanel extends ConsumerStatefulWidget {
  const TimelinePanel({super.key});

  @override
  ConsumerState<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends ConsumerState<TimelinePanel> {
  final ScrollController _scrollController = ScrollController();
  double _lastScale = 1.0;
  bool _didInitialFit = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitOnce();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    ref
        .read(timelineProvider.notifier)
        .setScrollOffset(_scrollController.offset);
  }

  void _scrollToTime(Duration time) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pps = ref.read(timelineProvider).pixelsPerSecond;
      final x = time.inMilliseconds / 1000.0 * pps;
      final viewport = _scrollController.position.viewportDimension;
      final target = (x - viewport * 0.28)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _fitOnce() {
    if (_didInitialFit || !_scrollController.hasClients) return;
    final project = ref.read(projectProvider);
    if (project == null || project.totalDuration <= Duration.zero) return;
    if (_scrollController.position.viewportDimension < 80) return;
    _didInitialFit = true;
    _zoomToFit();
  }

  void _zoomToFit() {
    final project = ref.read(projectProvider);
    if (project == null || !_scrollController.hasClients) return;
    final seconds = project.totalDuration.inMilliseconds / 1000.0;
    if (seconds <= 0) return;
    final viewport = _scrollController.position.viewportDimension;
    final available = (viewport - EditorConstants.trackLabelWidth - 32)
        .clamp(64.0, viewport);
    final fit = available / (seconds * EditorConstants.pixelsPerSecondBase);
    ref.read(timelineProvider.notifier).setZoom(fit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(timelineProvider.select((s) => s.focusGeneration), (prev, next) {
      if (prev == next) return;
      final time = ref.read(timelineProvider).focusTime;
      if (time == null) return;
      _scrollToTime(time);
    });
    ref.listen<VideoProject?>(projectProvider, (prev, next) {
      if (next == null) {
        _didInitialFit = false;
        return;
      }
      if (prev == null || prev.id != next.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fitOnce();
        });
      }
    });

    final cs = Theme.of(context).colorScheme;
    final project = ref.watch(projectProvider);
    final tlState = ref.watch(timelineProvider);
    final playback = ref.watch(playbackProvider);

    if (project == null) return const SizedBox.shrink();

    final pps = tlState.pixelsPerSecond;
    final totalWidth = project.totalDuration.inMilliseconds / 1000.0 * pps +
        200; // extra padding

    // Playhead position in pixels
    final playheadPx =
        playback.position.inMilliseconds / 1000.0 * pps - tlState.scrollOffset;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.1)),
        ),
      ),
      child: Column(
        children: [
          // Timeline body (ruler + tracks + playhead)
          Expanded(
            child: GestureDetector(
              // Pinch to zoom
              onScaleStart: (d) => _lastScale = tlState.zoom,
              onScaleUpdate: (d) {
                if (d.pointerCount >= 2) {
                  ref
                      .read(timelineProvider.notifier)
                      .setZoom(_lastScale * d.scale);
                }
              },
              // Tap on empty area to deselect
              onTap: () {
                ref.read(timelineProvider.notifier).clearSelection();
                ref.read(projectProvider.notifier).deselectAll();
              },
              child: Stack(
                children: [
                  // Scrollable content – horizontal for time, vertical for tracks
                  SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: totalWidth + EditorConstants.trackLabelWidth,
                      child: Column(
                        children: [
                          // Ruler (stays at top)
                          TimelineRuler(
                            pixelsPerSecond: pps,
                            totalDuration: project.totalDuration,
                            scrollOffset: 0,
                          ),

                          // Tracks – vertically scrollable
                          Expanded(
                            child: ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const ClampingScrollPhysics(),
                              buildDefaultDragHandles: false,
                              itemCount: project.tracks.length,
                              onReorder: (oldIndex, newIndex) {
                                ref
                                    .read(projectProvider.notifier)
                                    .reorderTracks(oldIndex, newIndex);
                              },
                              itemBuilder: (context, i) {
                                  final track = project.tracks[i];
                                  return ReorderableDelayedDragStartListener(
                                    key: ValueKey(track.id),
                                    index: i,
                                    child: TimelineTrackRow(
                                    track: track,
                                    pixelsPerSecond: pps,
                                    scrollOffset: 0,
                                    selectedClipId: tlState.selectedClipId,
                                    selectedClipIds: tlState.selectedClipIds,
                                    onClipTap: (clipId) {
                                      ref
                                          .read(timelineProvider.notifier)
                                          .selectClip(clipId,
                                              trackId: track.id);
                                      ref
                                          .read(projectProvider.notifier)
                                          .selectClip(clipId);
                                      // Auto-open the correct tool panel
                                      _openPanelForClip(context, ref, clipId);
                                    },
                                    onClipLongPress: (clipId) {
                                      HapticFeedback.selectionClick();
                                      ref
                                          .read(timelineProvider.notifier)
                                          .toggleMultiSelect(clipId,
                                              trackId: track.id);
                                      final ids = ref
                                          .read(timelineProvider)
                                          .selectedClipIds;
                                      ref
                                          .read(projectProvider.notifier)
                                          .selectClips(ids.toSet());
                                    },
                                    onClipResizeLeft: (clipId, dx) =>
                                        _handleResizeLeft(clipId, dx, pps),
                                    onClipResizeRight: (clipId, dx) =>
                                        _handleResizeRight(clipId, dx, pps),
                                    onClipMove: (clipId, dx) =>
                                        _handleClipMove(clipId, dx, pps),
                                    onToggleVisible: () {
                                      ref.read(projectProvider.notifier).updateTrack(
                                            track.id,
                                            (t) => t.copyWith(isVisible: !t.isVisible),
                                          );
                                    },
                                    onToggleLock: () {
                                      ref.read(projectProvider.notifier).updateTrack(
                                            track.id,
                                            (t) => t.copyWith(isLocked: !t.isLocked),
                                          );
                                    },
                                    onToggleMute: () {
                                      ref.read(projectProvider.notifier).updateTrack(
                                            track.id,
                                            (t) => t.copyWith(isMuted: !t.isMuted),
                                          );
                                    },
                                  ),
                                  );
                                },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Playhead overlay
                  if (playheadPx > -EditorConstants.playheadKnobRadius * 2)
                    TimelinePlayhead(
                      positionPx: playheadPx,
                      height: EditorConstants.rulerHeight +
                          project.tracks.length * EditorConstants.trackHeight,
                    ),

                  // Playhead drag area – only covers ruler area so clip gestures work
                  Positioned(
                    left: EditorConstants.trackLabelWidth,
                    right: 0,
                    top: 0,
                    height: EditorConstants.rulerHeight,
                    child: GestureDetector(
                      onHorizontalDragStart: (_) {
                        ref
                            .read(timelineProvider.notifier)
                            .setDraggingPlayhead(true);
                      },
                      onHorizontalDragUpdate: (d) {
                        final localX = d.localPosition.dx;
                        final time =
                            TimeUtils.pxToDuration(localX + tlState.scrollOffset, pps);
                        final clamped = TimeUtils.clampDuration(
                          time,
                          Duration.zero,
                          project.totalDuration,
                        );
                        ref.read(playbackProvider.notifier).seekTo(clamped);
                      },
                      onHorizontalDragEnd: (_) {
                        ref
                            .read(timelineProvider.notifier)
                            .setDraggingPlayhead(false);
                      },
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),

                  // Draggable playhead knob – a narrow touch target around the playhead line
                  if (playheadPx > -EditorConstants.playheadKnobRadius * 2)
                    Positioned(
                      left: EditorConstants.trackLabelWidth + playheadPx - 12,
                      top: EditorConstants.rulerHeight,
                      bottom: 0,
                      width: 24,
                      child: GestureDetector(
                        onVerticalDragStart: (_) {},
                        onHorizontalDragStart: (_) {
                          ref
                              .read(timelineProvider.notifier)
                              .setDraggingPlayhead(true);
                        },
                        onHorizontalDragUpdate: (d) {
                          final renderBox =
                              context.findRenderObject() as RenderBox?;
                          if (renderBox == null) return;
                          final localPos =
                              renderBox.globalToLocal(d.globalPosition);
                          final localX =
                              localPos.dx - EditorConstants.trackLabelWidth;
                          final time = TimeUtils.pxToDuration(
                              localX + tlState.scrollOffset, pps);
                          final clamped = TimeUtils.clampDuration(
                            time,
                            Duration.zero,
                            project.totalDuration,
                          );
                          ref.read(playbackProvider.notifier).seekTo(clamped);
                        },
                        onHorizontalDragEnd: (_) {
                          ref
                              .read(timelineProvider.notifier)
                              .setDraggingPlayhead(false);
                        },
                        behavior: HitTestBehavior.translucent,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Bottom controls (zoom, add track)
          TimelineControls(
            zoom: tlState.zoom,
            onZoomIn: () => ref.read(timelineProvider.notifier).zoomIn(),
            onZoomOut: () => ref.read(timelineProvider.notifier).zoomOut(),
            onFit: _zoomToFit,
            onAddTrack: () => _showAddTrackSheet(context),
          ),
        ],
      ),
    );
  }

  void _openPanelForClip(BuildContext context, WidgetRef ref, String clipId) {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final clip = project.findClipById(clipId);
    if (clip == null) return;

    EditorTool tool;
    if (clip is VideoClip) {
      tool = EditorTool.trim;
    } else if (clip is TextClip) {
      tool = EditorTool.text;
    } else if (clip is AudioClip) {
      tool = EditorTool.audio;
    } else if (clip is StickerClip) {
      tool = EditorTool.sticker;
    } else if (clip is PipClip) {
      tool = EditorTool.pip;
    } else {
      return;
    }

    // Use the BottomToolbar's static helper to open the sheet
    BottomToolbar.openToolSheet(context, tool);
  }

  void _handleClipMove(String clipId, double dx, double pps) {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final clip = project.findClipById(clipId);
    final track = project.findTrackForClip(clipId);
    if (clip == null || track == null || track.isLocked) return;

    final deltaDuration = TimeUtils.pxToDuration(dx.abs(), pps);
    var next = dx > 0
        ? clip.startTime + deltaDuration
        : (clip.startTime >= deltaDuration
            ? clip.startTime - deltaDuration
            : Duration.zero);
    if (next < Duration.zero) next = Duration.zero;

    final snapUs = TimeUtils.pxToDuration(EditorConstants.snapThresholdPx, pps)
        .inMicroseconds;
    final playhead = ref.read(playbackProvider).position;
    final magnets = <int>[0, playhead.inMicroseconds];
    for (final c in track.clips) {
      if (c.id == clipId) continue;
      magnets.add(c.startTime.inMicroseconds);
      magnets.add(c.endTime.inMicroseconds);
    }
    for (final m in magnets) {
      if ((next.inMicroseconds - m).abs() <= snapUs) {
        next = Duration(microseconds: m);
        break;
      }
    }

    ref.read(projectProvider.notifier).updateClip(clipId, (c) {
      return c.copyWith(startTime: next);
    });
  }

  void _handleResizeLeft(String clipId, double dx, double pps) {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final clip = project.findClipById(clipId);
    if (clip == null) return;

    final deltaDuration = TimeUtils.pxToDuration(dx.abs(), pps);

    if (clip is VideoClip && clip.speedEffect.mode == SpeedMode.constant) {
      final v = clip;
      final s = v.speedEffect.speed;
      if (dx > 0) {
        if (v.duration <= deltaDuration + const Duration(milliseconds: 200)) {
          return;
        }
        final newStart = v.startTime + deltaDuration;
        final newDur = v.duration - deltaDuration;
        final newTrimStart = v.trimStart + _mediaSourceSpan(deltaDuration, s);
        if (newTrimStart >= v.trimEnd) return;
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final vc = c as VideoClip;
          return vc.copyWith(
            startTime: newStart,
            duration: newDur,
            trimStart: newTrimStart,
          );
        });
        return;
      }
      if (v.startTime >= deltaDuration) {
        final newStart = v.startTime - deltaDuration;
        final newDur = v.duration + deltaDuration;
        final newTrimStart = v.trimStart - _mediaSourceSpan(deltaDuration, s);
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final vc = c as VideoClip;
          return vc.copyWith(
            startTime: newStart,
            duration: newDur,
            trimStart: newTrimStart < Duration.zero ? Duration.zero : newTrimStart,
          );
        });
        return;
      }
    } else if (clip is AudioClip) {
      final a = clip;
      if (dx > 0) {
        if (a.duration <= deltaDuration + const Duration(milliseconds: 200)) {
          return;
        }
        final newStart = a.startTime + deltaDuration;
        final newDur = a.duration - deltaDuration;
        final newTrimStart = a.trimStart + deltaDuration;
        if (newTrimStart >= a.trimEnd) return;
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final ac = c as AudioClip;
          return ac.copyWith(
            startTime: newStart,
            duration: newDur,
            trimStart: newTrimStart,
          );
        });
        return;
      }
      if (a.startTime >= deltaDuration) {
        final newStart = a.startTime - deltaDuration;
        final newDur = a.duration + deltaDuration;
        final newTrimStart = a.trimStart - deltaDuration;
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final ac = c as AudioClip;
          return ac.copyWith(
            startTime: newStart,
            duration: newDur,
            trimStart: newTrimStart < Duration.zero ? Duration.zero : newTrimStart,
          );
        });
        return;
      }
    } else if (clip is PipClip) {
      final p = clip;
      const s = 1.0;
      if (dx > 0) {
        if (p.duration <= deltaDuration + const Duration(milliseconds: 200)) {
          return;
        }
        final newStart = p.startTime + deltaDuration;
        final newDur = p.duration - deltaDuration;
        final newTrimStart = p.trimStart + _mediaSourceSpan(deltaDuration, s);
        if (newTrimStart >= p.trimEnd) return;
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final pc = c as PipClip;
          return pc.copyWith(
            startTime: newStart,
            duration: newDur,
            trimStart: newTrimStart,
          );
        });
        return;
      }
      if (p.startTime >= deltaDuration) {
        final newStart = p.startTime - deltaDuration;
        final newDur = p.duration + deltaDuration;
        final newTrimStart = p.trimStart - _mediaSourceSpan(deltaDuration, s);
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final pc = c as PipClip;
          return pc.copyWith(
            startTime: newStart,
            duration: newDur,
            trimStart: newTrimStart < Duration.zero ? Duration.zero : newTrimStart,
          );
        });
        return;
      }
    }

    if (dx > 0) {
      // Shrink from left
      if (clip.duration > deltaDuration + const Duration(milliseconds: 200)) {
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          return c.copyWith(
            startTime: c.startTime + deltaDuration,
            duration: c.duration - deltaDuration,
          );
        });
      }
    } else {
      // Expand to left
      if (clip.startTime >= deltaDuration) {
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          return c.copyWith(
            startTime: c.startTime - deltaDuration,
            duration: c.duration + deltaDuration,
          );
        });
      }
    }
  }

  void _handleResizeRight(String clipId, double dx, double pps) {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final clip = project.findClipById(clipId);
    if (clip == null) return;

    final deltaDuration = TimeUtils.pxToDuration(dx.abs(), pps);

    if (clip is VideoClip && clip.speedEffect.mode == SpeedMode.constant) {
      final v = clip;
      final s = v.speedEffect.speed;
      if (dx > 0) {
        final newDur = v.duration + deltaDuration;
        final newSpan = _mediaSourceSpan(newDur, s);
        var newTrimEnd = v.trimStart + newSpan;
        if (newTrimEnd > v.originalDuration) {
          newTrimEnd = v.originalDuration;
        }
        if (newTrimEnd <= v.trimStart) return;
        final adjustedDur =
            _mediaTimelineFromSourceSpan(newTrimEnd - v.trimStart, s);
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final vc = c as VideoClip;
          return vc.copyWith(duration: adjustedDur, trimEnd: newTrimEnd);
        });
        return;
      }
      if (v.duration > deltaDuration + const Duration(milliseconds: 200)) {
        final newDur = v.duration - deltaDuration;
        final newSpan = _mediaSourceSpan(newDur, s);
        final newTrimEnd = v.trimStart + newSpan;
        if (newTrimEnd <= v.trimStart) return;
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final vc = c as VideoClip;
          return vc.copyWith(duration: newDur, trimEnd: newTrimEnd);
        });
        return;
      }
      return;
    } else if (clip is AudioClip) {
      final a = clip;
      if (dx > 0) {
        final newDur = a.duration + deltaDuration;
        var newTrimEnd = a.trimStart + newDur;
        if (newTrimEnd > a.originalDuration) {
          newTrimEnd = a.originalDuration;
        }
        if (newTrimEnd <= a.trimStart) return;
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final ac = c as AudioClip;
          return ac.copyWith(
            duration: newTrimEnd - ac.trimStart,
            trimEnd: newTrimEnd,
          );
        });
        return;
      }
      if (a.duration > deltaDuration + const Duration(milliseconds: 200)) {
        final newDur = a.duration - deltaDuration;
        final newTrimEnd = a.trimStart + newDur;
        if (newTrimEnd <= a.trimStart) return;
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final ac = c as AudioClip;
          return ac.copyWith(duration: newDur, trimEnd: newTrimEnd);
        });
        return;
      }
      return;
    } else if (clip is PipClip) {
      final p = clip;
      const s = 1.0;
      if (dx > 0) {
        final newDur = p.duration + deltaDuration;
        final newSpan = _mediaSourceSpan(newDur, s);
        var newTrimEnd = p.trimStart + newSpan;
        if (newTrimEnd > p.originalDuration) {
          newTrimEnd = p.originalDuration;
        }
        if (newTrimEnd <= p.trimStart) return;
        final adjustedDur =
            _mediaTimelineFromSourceSpan(newTrimEnd - p.trimStart, s);
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final pc = c as PipClip;
          return pc.copyWith(duration: adjustedDur, trimEnd: newTrimEnd);
        });
        return;
      }
      if (p.duration > deltaDuration + const Duration(milliseconds: 200)) {
        final newDur = p.duration - deltaDuration;
        final newSpan = _mediaSourceSpan(newDur, s);
        final newTrimEnd = p.trimStart + newSpan;
        if (newTrimEnd <= p.trimStart) return;
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          final pc = c as PipClip;
          return pc.copyWith(duration: newDur, trimEnd: newTrimEnd);
        });
        return;
      }
      return;
    }

    if (dx > 0) {
      // Expand to right
      ref.read(projectProvider.notifier).updateClip(clipId, (c) {
        return c.copyWith(duration: c.duration + deltaDuration);
      });
    } else {
      // Shrink from right
      if (clip.duration > deltaDuration + const Duration(milliseconds: 200)) {
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          return c.copyWith(duration: c.duration - deltaDuration);
        });
      }
    }
  }

  void _showAddTrackSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add Track',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _addTrackTile(
                  icon: Icons.video_file,
                  label: 'Video Clip',
                  color: EditorConstants.videoTrackColor,
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndAddVideoClip();
                  },
                ),
                _addTrackTile(
                  icon: Icons.music_note,
                  label: 'Audio Track',
                  color: EditorConstants.audioTrackColor,
                  onTap: () {
                    _addNewTrack(TrackType.audio, 'Audio');
                    Navigator.pop(context);
                  },
                ),
                _addTrackTile(
                  icon: Icons.text_fields,
                  label: 'Text Track',
                  color: EditorConstants.textTrackColor,
                  onTap: () {
                    _addNewTrack(TrackType.text, 'Text');
                    Navigator.pop(context);
                  },
                ),
                _addTrackTile(
                  icon: Icons.emoji_emotions,
                  label: 'Sticker Track',
                  color: EditorConstants.stickerTrackColor,
                  onTap: () {
                    _addNewTrack(TrackType.sticker, 'Sticker');
                    Navigator.pop(context);
                  },
                ),
                _addTrackTile(
                  icon: Icons.picture_in_picture,
                  label: 'PiP Track',
                  color: EditorConstants.pipTrackColor,
                  onTap: () {
                    _addNewTrack(TrackType.pip, 'PiP');
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _addTrackTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(
        label,
        style: TextStyle(color: cs.onSurface, fontSize: 15),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  /// Pick a video from gallery and add it as a new clip to the video track.
  Future<void> _pickAndAddVideoClip() async {
    try {
      final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
      if (picked == null) return;

      final file = File(picked.path);
      final video = EditorVideo.file(file);
      final metadata = await ProVideoEditor.instance.getMetadata(video);

      final project = ref.read(projectProvider);
      if (project == null) return;

      // Find the existing video track, or create one
      Track? videoTrack;
      for (final t in project.videoTracks) {
        videoTrack = t;
        break;
      }

      if (videoTrack == null) {
        // Create a new video track
        final trackId = '${project.id}_video_${DateTime.now().microsecondsSinceEpoch}';
        videoTrack = Track(
          id: trackId,
          type: TrackType.video,
          name: 'Video 1',
        );
        ref.read(projectProvider.notifier).addTrack(videoTrack);
      }

      // Calculate the start time: place after the last clip on this track
      Duration startTime = Duration.zero;
      for (final clip in videoTrack.clips) {
        if (clip.endTime > startTime) {
          startTime = clip.endTime;
        }
      }

      final clipId = '${project.id}_clip_${DateTime.now().microsecondsSinceEpoch}';
      final newClip = VideoClip(
        id: clipId,
        startTime: startTime,
        duration: metadata.duration,
        sourcePath: file.path,
        trimStart: Duration.zero,
        trimEnd: metadata.duration,
        originalDuration: metadata.duration,
        resolution: Size(metadata.resolution.width, metadata.resolution.height),
      );

      ref.read(projectProvider.notifier).addClipToTrack(videoTrack.id, newClip);

      // Update total duration
      ref.read(playbackProvider.notifier).setTotalDuration(
        project.computeTotalDuration() > startTime + metadata.duration
            ? project.computeTotalDuration()
            : startTime + metadata.duration,
      );

      // Select the new clip
      ref.read(timelineProvider.notifier).selectClip(clipId, trackId: videoTrack.id);
      ref.read(projectProvider.notifier).selectClip(clipId);

      // Generate thumbnails asynchronously for the new clip
      _generateThumbnailsForClip(file, metadata.duration, clipId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video clip added to timeline'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add video clip: $e')),
        );
      }
    }
  }

  /// Generate thumbnails for a newly added video clip.
  Future<void> _generateThumbnailsForClip(File file, Duration duration, String clipId) async {
    try {
      final thumbs = await ThumbnailCacheService.generateKeyFramesForFile(file);
      if (thumbs.isNotEmpty && mounted) {
        ref.read(projectProvider.notifier).updateClip(
              clipId,
              (c) => (c as VideoClip).copyWith(thumbnails: thumbs),
            );
      }
    } catch (e) {
      debugPrint('Thumbnail generation failed for clip $clipId: $e');
    }
  }

  void _addNewTrack(TrackType type, String prefix) {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final count =
        project.tracks.where((t) => t.type == type).length + 1;
    final trackId =
        '${project.id}_${type.name}_${DateTime.now().microsecondsSinceEpoch}';
    ref.read(projectProvider.notifier).addTrack(
          Track(
            id: trackId,
            type: type,
            name: '$prefix $count',
          ),
        );
  }
}

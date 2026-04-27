// lib/features/video_editor/widgets/timeline/timeline_panel.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

import '../../models/clip_model.dart';
import '../../models/project_model.dart';
import '../../state/editor_providers.dart';
import '../../state/tool_notifier.dart';
import '../../utils/editor_constants.dart';
import '../../utils/time_utils.dart';
import '../toolbar/bottom_toolbar.dart';
import 'timeline_controls.dart';
import 'timeline_playhead.dart';
import 'timeline_ruler.dart';
import 'timeline_track_row.dart';

/// The multi-track timeline panel.
class TimelinePanel extends ConsumerStatefulWidget {
  const TimelinePanel({super.key});

  @override
  ConsumerState<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends ConsumerState<TimelinePanel> {
  final ScrollController _scrollController = ScrollController();
  double _lastScale = 1.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
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

  @override
  Widget build(BuildContext context) {
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
          top: BorderSide(color: cs.onSurface.withOpacity(0.1)),
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
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              physics: const ClampingScrollPhysics(),
                              child: Column(
                                children: List.generate(project.tracks.length, (i) {
                                  final track = project.tracks[i];
                                  return TimelineTrackRow(
                                    track: track,
                                    pixelsPerSecond: pps,
                                    scrollOffset: 0,
                                    selectedClipId: tlState.selectedClipId,
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
                                    onClipResizeLeft: (clipId, dx) =>
                                        _handleResizeLeft(clipId, dx, pps),
                                    onClipResizeRight: (clipId, dx) =>
                                        _handleResizeRight(clipId, dx, pps),
                                    onClipMove: (clipId, dx) =>
                                        _handleClipMove(clipId, dx, pps),
                                  );
                                }),
                              ),
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
    BottomToolbar.openToolSheet(context, ref, tool);
  }

  void _handleClipMove(String clipId, double dx, double pps) {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final clip = project.findClipById(clipId);
    if (clip == null) return;

    final deltaDuration = TimeUtils.pxToDuration(dx.abs(), pps);
    if (dx > 0) {
      // Move right
      ref.read(projectProvider.notifier).updateClip(clipId, (c) {
        return c.copyWith(startTime: c.startTime + deltaDuration);
      });
    } else {
      // Move left
      if (clip.startTime >= deltaDuration) {
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          return c.copyWith(startTime: c.startTime - deltaDuration);
        });
      } else {
        // Clamp to zero
        ref.read(projectProvider.notifier).updateClip(clipId, (c) {
          return c.copyWith(startTime: Duration.zero);
        });
      }
    }
  }

  void _handleResizeLeft(String clipId, double dx, double pps) {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final clip = project.findClipById(clipId);
    if (clip == null) return;

    final deltaDuration = TimeUtils.pxToDuration(dx.abs(), pps);
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
                      color: cs.onSurface.withOpacity(0.2),
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
        backgroundColor: color.withOpacity(0.15),
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
      final video = EditorVideo.file(file);
      final thumbs = await ProVideoEditor.instance.getKeyFrames(
        KeyFramesConfigs(
          video: video,
          outputSize: const Size.square(48),
          boxFit: ThumbnailBoxFit.cover,
          maxOutputFrames: 10,
          outputFormat: ThumbnailFormat.jpeg,
        ),
      );
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

// lib/features/video_editor/widgets/timeline/timeline_track_row.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/project_model.dart';
import '../../utils/editor_constants.dart';
import 'timeline_clip_widget.dart';

/// A single horizontal track row in the timeline.
class TimelineTrackRow extends StatelessWidget {
  final Track track;
  final double pixelsPerSecond;
  final double scrollOffset;
  final String? selectedClipId;
  final List<String> selectedClipIds;
  final void Function(String clipId)? onClipTap;
  final void Function(String clipId)? onClipLongPress;
  final void Function(String clipId, double dx)? onClipResizeLeft;
  final void Function(String clipId, double dx)? onClipResizeRight;
  final void Function(String clipId, double dx)? onClipMove;
  final VoidCallback? onToggleVisible;
  final VoidCallback? onToggleLock;
  final VoidCallback? onToggleMute;

  const TimelineTrackRow({
    super.key,
    required this.track,
    required this.pixelsPerSecond,
    required this.scrollOffset,
    this.selectedClipId,
    this.selectedClipIds = const [],
    this.onClipTap,
    this.onClipLongPress,
    this.onClipResizeLeft,
    this.onClipResizeRight,
    this.onClipMove,
    this.onToggleVisible,
    this.onToggleLock,
    this.onToggleMute,
  });

  Color get _trackColor {
    switch (track.type) {
      case TrackType.video:
        return EditorConstants.videoTrackColor;
      case TrackType.audio:
        return EditorConstants.audioTrackColor;
      case TrackType.text:
        return EditorConstants.textTrackColor;
      case TrackType.sticker:
        return EditorConstants.stickerTrackColor;
      case TrackType.pip:
        return EditorConstants.pipTrackColor;
    }
  }

  IconData get _trackIcon {
    switch (track.type) {
      case TrackType.video:
        return LucideIcons.film;
      case TrackType.audio:
        return LucideIcons.music;
      case TrackType.text:
        return LucideIcons.type;
      case TrackType.sticker:
        return LucideIcons.smile;
      case TrackType.pip:
        return LucideIcons.pictureInPicture2;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: EditorConstants.trackHeight,
      child: Row(
        children: [
          // Track label gutter
          Container(
            width: EditorConstants.trackLabelWidth,
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                right: BorderSide(
                  color: cs.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _trackIcon,
                  size: 14,
                  color: _trackColor.withValues(alpha: track.isVisible ? 1 : 0.3),
                ),
                const SizedBox(height: 1),
                Text(
                  track.name.length > 4
                      ? track.name.substring(0, 4)
                      : track.name,
                  style: TextStyle(
                    fontSize: 8,
                    color: cs.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: onToggleVisible,
                      child: Icon(
                        track.isVisible
                            ? LucideIcons.eye
                            : LucideIcons.eyeOff,
                        size: 10,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onToggleLock,
                      child: Icon(
                        track.isLocked ? LucideIcons.lock : LucideIcons.unlock,
                        size: 10,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: onToggleMute,
                      child: Icon(
                        track.isMuted ? LucideIcons.volumeX : LucideIcons.volume2,
                        size: 10,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Clips area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: cs.onSurface.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Stack(
                children: [
                  // Background
                  Positioned.fill(
                    child: Container(
                      color: _trackColor.withValues(alpha: 0.04),
                    ),
                  ),

                  // Clips
                  ...track.clips.map((clip) => TimelineClipWidget(
                        clip: clip,
                        trackType: track.type,
                        pixelsPerSecond: pixelsPerSecond,
                        scrollOffset: scrollOffset,
                        isSelected: selectedClipIds.contains(clip.id) ||
                            clip.id == selectedClipId,
                        onTap: () => onClipTap?.call(clip.id),
                        onLongPress: () => onClipLongPress?.call(clip.id),
                        onResizeLeft: (dx) =>
                            onClipResizeLeft?.call(clip.id, dx),
                        onResizeRight: (dx) =>
                            onClipResizeRight?.call(clip.id, dx),
                        onMove: (dx) =>
                            onClipMove?.call(clip.id, dx),
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

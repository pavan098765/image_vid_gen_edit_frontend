// lib/features/video_editor/widgets/timeline/timeline_clip_widget.dart

import 'package:flutter/material.dart';

import '../../models/clip_model.dart';
import '../../models/effect_model.dart';
import '../../models/project_model.dart';
import '../../utils/editor_constants.dart';

/// Renders a single clip block in a timeline track row.
class TimelineClipWidget extends StatelessWidget {
  final Clip clip;
  final TrackType trackType;
  final double pixelsPerSecond;
  final double scrollOffset;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Function(double)? onResizeLeft;
  final Function(double)? onResizeRight;
  final Function(double)? onMove;

  const TimelineClipWidget({
    super.key,
    required this.clip,
    required this.trackType,
    required this.pixelsPerSecond,
    required this.scrollOffset,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.onResizeLeft,
    this.onResizeRight,
    this.onMove,
  });

  Color get _trackColor {
    switch (trackType) {
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

  @override
  Widget build(BuildContext context) {
    final startPx = clip.startTime.inMilliseconds / 1000.0 * pixelsPerSecond - scrollOffset;
    final widthPx = clip.duration.inMilliseconds / 1000.0 * pixelsPerSecond;

    if (startPx + widthPx < 0 || widthPx < 1) return const SizedBox.shrink();

    return Positioned(
      left: startPx,
      width: widthPx.clamp(EditorConstants.minClipWidthPx, double.infinity),
      top: 2,
      bottom: 2,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        onHorizontalDragUpdate: isSelected ? (d) => onMove?.call(d.delta.dx) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: _trackColor.withOpacity(isSelected ? 0.9 : 0.7),
            borderRadius: BorderRadius.circular(EditorConstants.clipBorderRadius),
            border: Border.all(
              color: isSelected
                  ? Colors.white.withOpacity(0.9)
                  : Colors.white.withOpacity(0.15),
              width: isSelected ? 2 : 0.5,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _trackColor.withOpacity(0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(EditorConstants.clipBorderRadius),
            child: Stack(
              children: [
                // Content
                Positioned.fill(child: _buildContent()),

                // Left resize handle
                if (isSelected)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: EditorConstants.clipResizeHandleWidth,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) => onResizeLeft?.call(d.delta.dx),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(EditorConstants.clipBorderRadius),
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 3,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Right resize handle
                if (isSelected)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: EditorConstants.clipResizeHandleWidth,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (d) => onResizeRight?.call(d.delta.dx),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(EditorConstants.clipBorderRadius),
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 3,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (trackType) {
      case TrackType.video:
        return _buildVideoContent();
      case TrackType.audio:
        return _buildAudioContent();
      case TrackType.text:
        return _buildTextContent();
      case TrackType.sticker:
        return _buildStickerContent();
      case TrackType.pip:
        return _buildPipContent();
    }
  }

  Widget _buildVideoContent() {
    final videoClip = clip as VideoClip;
    final thumbnails = videoClip.thumbnails;

    // Collect effect badges
    final badges = <Widget>[];
    if (videoClip.colorAdjustment.filterPresetId != null ||
        videoClip.colorAdjustment.brightness != 0 ||
        videoClip.colorAdjustment.contrast != 1.0 ||
        videoClip.colorAdjustment.saturation != 1.0) {
      badges.add(_effectBadge(Icons.auto_fix_high, 'FX'));
    }
    if ((videoClip.speedEffect.speed - 1.0).abs() > 0.01) {
      badges.add(_effectBadge(Icons.speed, '${videoClip.speedEffect.speed.toStringAsFixed(1)}x'));
    }
    if (videoClip.isMuted) {
      badges.add(_effectBadge(Icons.volume_off, 'Muted'));
    }
    if (videoClip.reverse) {
      badges.add(_effectBadge(Icons.replay, 'Rev'));
    }
    if (videoClip.rotateQuarterTurns != 0) {
      badges.add(_effectBadge(Icons.rotate_right, '${videoClip.rotateQuarterTurns * 90}°'));
    }
    if (videoClip.cropNorm != null) {
      badges.add(_effectBadge(Icons.crop, 'Crop'));
    }
    if (videoClip.transitionIn.type != TransitionType.none) {
      badges.add(_effectBadge(Icons.animation, 'TR'));
    }

    if (thumbnails != null && thumbnails.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final thumbWidth = constraints.maxHeight * (16.0 / 9.0);
          if (thumbWidth <= 0) return const SizedBox.shrink();
          final visibleCount = (constraints.maxWidth / thumbWidth).ceil().clamp(1, 50);
          return Stack(
            children: [
              Row(
                children: List.generate(visibleCount, (i) {
                  final thumbIdx = (i * thumbnails.length / visibleCount).floor().clamp(0, thumbnails.length - 1);
                  return SizedBox(
                    width: (constraints.maxWidth / visibleCount),
                    height: constraints.maxHeight,
                    child: Image.memory(
                      thumbnails[thumbIdx],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  );
                }),
              ),
              if (badges.isNotEmpty)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: badges,
                  ),
                ),
            ],
          );
        },
      );
    }

    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.centerLeft,
          child: const Row(
            children: [
              Icon(Icons.videocam, size: 14, color: Colors.white70),
              SizedBox(width: 4),
              Flexible(
                child: Text(
                  'Video',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (badges.isNotEmpty)
          Positioned(
            right: 2,
            top: 2,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: badges,
            ),
          ),
      ],
    );
  }

  Widget _effectBadge(IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(left: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 8, color: Colors.white70),
          const SizedBox(width: 1),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 7,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioContent() {
    final audioClip = clip as AudioClip;
    final waveform = audioClip.waveform;

    return Stack(
      children: [
        if (waveform != null && waveform.isNotEmpty)
          Positioned.fill(
            child: CustomPaint(
              painter: _WaveformMiniPainter(
                samples: waveform,
                color: Colors.white.withOpacity(0.5),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: [
              const Icon(Icons.music_note, size: 12, color: Colors.white70),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  audioClip.name.isNotEmpty ? audioClip.name : 'Audio',
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextContent() {
    final textClip = clip as TextClip;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      child: Text(
        textClip.text,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Widget _buildStickerContent() {
    final stickerClip = clip as StickerClip;
    return Center(
      child: Text(
        stickerClip.isEmoji ? stickerClip.stickerData : '🖼',
        style: const TextStyle(fontSize: 20),
      ),
    );
  }

  Widget _buildPipContent() {
    final pipClip = clip as PipClip;
    final thumbnails = pipClip.thumbnails;

    if (thumbnails != null && thumbnails.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final thumbWidth = constraints.maxHeight * (16.0 / 9.0);
          if (thumbWidth <= 0) return const SizedBox.shrink();
          final visibleCount = (constraints.maxWidth / thumbWidth).ceil().clamp(1, 20);
          return Stack(
            children: [
              Row(
                children: List.generate(visibleCount, (i) {
                  final thumbIdx = (i * thumbnails.length / visibleCount).floor().clamp(0, thumbnails.length - 1);
                  return SizedBox(
                    width: (constraints.maxWidth / visibleCount),
                    height: constraints.maxHeight,
                    child: Image.memory(
                      thumbnails[thumbIdx],
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  );
                }),
              ),
              // PiP label overlay
              Positioned(
                left: 4,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Text(
                    'PiP',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.centerLeft,
      child: const Row(
        children: [
          Icon(Icons.picture_in_picture, size: 14, color: Colors.white70),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              'PiP',
              style: TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini waveform painter for audio clips.
class _WaveformMiniPainter extends CustomPainter {
  final List<double> samples;
  final Color color;

  _WaveformMiniPainter({required this.samples, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    final centerY = size.height / 2;
    final maxAmp = size.height * 0.4;
    final step = size.width / samples.length;

    for (int i = 0; i < samples.length; i++) {
      final x = i * step;
      final amp = samples[i].clamp(0.0, 1.0) * maxAmp;
      canvas.drawLine(
        Offset(x, centerY - amp),
        Offset(x, centerY + amp),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformMiniPainter old) => old.samples != samples;
}

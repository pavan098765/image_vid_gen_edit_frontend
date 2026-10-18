// lib/features/video_editor/widgets/toolbar/panels/trim_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../state/editor_providers.dart';
import '../../../utils/time_utils.dart';

/// Panel for trim/split/delete/duplicate operations on the selected clip.
class TrimPanel extends ConsumerStatefulWidget {
  const TrimPanel({super.key});

  @override
  ConsumerState<TrimPanel> createState() => _TrimPanelState();
}

class _TrimPanelState extends ConsumerState<TrimPanel> {
  bool _detaching = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);
    final playback = ref.watch(playbackProvider);
    final video = selectedClip is VideoClip ? selectedClip : null;
    final playheadInside = selectedClip != null &&
        _strictlyInside(selectedClip, playback.position);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        Row(
          children: [
            Icon(LucideIcons.scissors, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Trim & Edit',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        if (video != null && _summary(video).isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            _summary(video),
            style: TextStyle(
              color: cs.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (selectedClip == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Tap a clip on the timeline to edit it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
          )
        else ...[
          _ActionGrid(
            tiles: [
              _TileData(
                icon: LucideIcons.splitSquareVertical,
                label: playheadInside ? 'Split' : 'Split half',
                color: cs.primary,
                onTap: () => _split(selectedClip, playback.position, playheadInside),
              ),
              _TileData(
                icon: LucideIcons.copy,
                label: 'Duplicate',
                color: cs.secondary,
                onTap: () => _duplicate(selectedClip),
              ),
              _TileData(
                icon: LucideIcons.trash2,
                label: 'Delete',
                color: Colors.redAccent,
                onTap: () => _ripple(selectedClip),
              ),
              _TileData(
                icon: LucideIcons.alignHorizontalSpaceAround,
                label: 'Close gap',
                color: cs.tertiary,
                onTap: () => _closeGap(selectedClip),
              ),
              if (video != null) ...[
                _TileData(
                  icon: LucideIcons.rotateCw,
                  label: video.rotateQuarterTurns == 0
                      ? 'Rotate'
                      : '${video.rotateQuarterTurns * 90}°',
                  color: cs.primary,
                  onTap: () => _rotate(video),
                ),
                _TileData(
                  icon: LucideIcons.rewind,
                  label: video.reverse ? 'Forward' : 'Reverse',
                  color: cs.secondary,
                  onTap: () => _reverse(video),
                ),
                _TileData(
                  icon: LucideIcons.unplug,
                  label: _detaching ? 'Working' : 'Detach',
                  color: cs.primary,
                  enabled: !_detaching,
                  onTap: () => _detach(video),
                ),
                _TileData(
                  icon: LucideIcons.snowflake,
                  label: 'Freeze',
                  color: cs.secondary,
                  onTap: () => _freeze(video, playback.position),
                ),
              ],
            ],
          ),
          if (video != null) ...[
            const SizedBox(height: 14),
            Text(
              'Frame',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _cropButton(video, cs, 'Full', null),
                _cropButton(video, cs, '9:16', 9 / 16),
                _cropButton(video, cs, '1:1', 1),
                _cropButton(video, cs, '16:9', 16 / 9),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            playheadInside
                ? 'Split and freeze use the playhead at ${TimeUtils.formatDuration(playback.position)}. Long-press clips on a track to select more than one.'
                : 'Playhead is outside this clip, so split cuts the middle. Long-press clips on a track to select more than one.',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: cs.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ],
    );
  }

  bool _strictlyInside(Clip clip, Duration pos) {
    return pos > clip.startTime + const Duration(milliseconds: 80) &&
        pos < clip.endTime - const Duration(milliseconds: 80);
  }

  String _summary(VideoClip video) {
    final bits = <String>[];
    if (video.reverse) bits.add('Reversed');
    if (video.rotateQuarterTurns != 0) {
      bits.add('Rotated ${video.rotateQuarterTurns * 90}°');
    }
    if (video.cropNorm != null) bits.add('Cropped');
    if (video.isMuted) bits.add('Muted');
    return bits.join(' · ');
  }

  Duration _halfPoint(Clip clip) {
    return clip.startTime +
        Duration(microseconds: clip.duration.inMicroseconds ~/ 2);
  }

  Future<void> _split(Clip clip, Duration playhead, bool atPlayhead) async {
    if (clip is! VideoClip) {
      _toast('Select a video clip to split');
      return;
    }
    final cut = atPlayhead ? playhead : _halfPoint(clip);
    HapticFeedback.mediumImpact();
    final newId =
        await ref.read(projectProvider.notifier).splitVideoClipAt(clip.id, cut);
    if (!mounted) return;
    if (newId == null) {
      _toast('Clip is too short to split');
      return;
    }
    ref.read(projectProvider.notifier).selectClip(newId);
    ref.read(timelineProvider.notifier).selectClip(newId);
    ref.read(timelineProvider.notifier).focusOn(cut);
    _toast(atPlayhead ? 'Split at the playhead' : 'Split in half');
    Navigator.of(context).pop();
  }

  void _duplicate(Clip clip) {
    HapticFeedback.mediumImpact();
    final newId = ref.read(projectProvider.notifier).duplicateClip(clip.id);
    if (newId == null) {
      _toast('Could not duplicate this clip');
      return;
    }
    final created = ref.read(projectProvider)?.findClipById(newId);
    ref.read(projectProvider.notifier).selectClip(newId);
    ref.read(timelineProvider.notifier).selectClip(newId);
    if (created != null) {
      ref.read(timelineProvider.notifier).focusOn(created.startTime);
    }
    _toast('Clip duplicated. Later clips moved forward.');
    Navigator.of(context).pop();
  }

  void _ripple(Clip clip) {
    HapticFeedback.mediumImpact();
    ref.read(projectProvider.notifier).rippleDelete(clip.id);
    ref.read(timelineProvider.notifier).clearSelection();
    _toast('Clip deleted');
    Navigator.of(context).pop();
  }

  void _closeGap(Clip clip) {
    final track = ref.read(projectProvider)?.findTrackForClip(clip.id);
    if (track == null) return;
    HapticFeedback.selectionClick();
    ref.read(projectProvider.notifier).closeGapOnTrack(track.id);
    _toast('Gaps closed');
    Navigator.of(context).pop();
  }

  void _rotate(VideoClip video) {
    HapticFeedback.selectionClick();
    final turns = (video.rotateQuarterTurns + 1) % 4;
    applyToSelectedVideoClips(
      ref,
      (c) => c.copyWith(rotateQuarterTurns: turns),
    );
  }

  void _reverse(VideoClip video) {
    HapticFeedback.selectionClick();
    applyToSelectedVideoClips(
      ref,
      (c) => c.copyWith(reverse: !video.reverse),
    );
  }

  Future<void> _detach(VideoClip video) async {
    if (_detaching) return;
    setState(() => _detaching = true);
    HapticFeedback.selectionClick();
    _toast('Separating audio…');
    await ref.read(projectProvider.notifier).detachAudio(video.id);
    if (!mounted) return;
    setState(() => _detaching = false);
    _toast('Audio moved to its own track');
  }

  Future<void> _freeze(VideoClip video, Duration playhead) async {
    final cut = _strictlyInside(video, playhead) ? playhead : _halfPoint(video);
    HapticFeedback.mediumImpact();
    await ref.read(projectProvider.notifier).freezeFrame(
          video.id,
          cut,
          const Duration(seconds: 1),
        );
    if (!mounted) return;
    ref.read(timelineProvider.notifier).focusOn(cut);
    _toast('Froze 1 second');
    Navigator.of(context).pop();
  }

  Widget _cropButton(VideoClip clip, ColorScheme cs, String label, double? ratio) {
    Rect? next;
    if (ratio != null && clip.resolution.width > 0 && clip.resolution.height > 0) {
      final src = clip.resolution.width / clip.resolution.height;
      double w;
      double h;
      if (src > ratio) {
        h = 1;
        w = ratio / src;
      } else {
        w = 1;
        h = src / ratio;
      }
      next = Rect.fromLTWH((1 - w) / 2, (1 - h) / 2, w, h);
    }
    final selected = (clip.cropNorm == null && ratio == null) ||
        (clip.cropNorm != null &&
            ratio != null &&
            (clip.cropNorm!.width / clip.cropNorm!.height - ratio).abs() < 0.02);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: selected ? cs.primary.withValues(alpha: 0.16) : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              HapticFeedback.selectionClick();
              applyToSelectedVideoClips(
                ref,
                (c) => c.copyWith(
                  cropNorm: next,
                  clearCrop: ratio == null,
                ),
              );
            },
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.08),
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 1600),
        ),
      );
  }
}

class _TileData {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;

  const _TileData({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });
}

class _ActionGrid extends StatelessWidget {
  final List<_TileData> tiles;

  const _ActionGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.92,
      children: [
        for (final tile in tiles)
          _ActionButton(
            icon: tile.icon,
            label: tile.label,
            color: tile.color,
            enabled: tile.enabled,
            onTap: tile.onTap,
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool enabled;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    return Material(
      color: color.withValues(alpha: active ? 0.12 : 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: active ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: active ? 0.28 : 0.1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color.withValues(alpha: active ? 1 : 0.35)),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color.withValues(alpha: active ? 1 : 0.35),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

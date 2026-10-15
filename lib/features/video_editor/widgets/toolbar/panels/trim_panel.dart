// lib/features/video_editor/widgets/toolbar/panels/trim_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../state/editor_providers.dart';

/// Panel for trim/split/delete/duplicate operations on the selected clip.
class TrimPanel extends ConsumerWidget {
  const TrimPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);
    final playback = ref.watch(playbackProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
          const SizedBox(height: 16),

          if (selectedClip == null)
            Center(
              child: Text(
                'Select a clip on the timeline to edit',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.5),
                  fontSize: 13,
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ActionButton(
                  icon: LucideIcons.splitSquareVertical,
                  label: 'Split',
                  color: cs.primary,
                  onTap: selectedClip is VideoClip
                      ? () {
                          ref
                              .read(projectProvider.notifier)
                              .splitVideoClipAt(
                                selectedClip.id,
                                playback.position,
                              );
                        }
                      : null,
                ),
                _ActionButton(
                  icon: LucideIcons.copy,
                  label: 'Duplicate',
                  color: cs.secondary,
                  onTap: () {
                    ref
                        .read(projectProvider.notifier)
                        .duplicateClip(selectedClip.id);
                  },
                ),
                _ActionButton(
                  icon: LucideIcons.trash2,
                  label: 'Ripple',
                  color: Colors.redAccent,
                  onTap: () {
                    ref
                        .read(projectProvider.notifier)
                        .rippleDelete(selectedClip.id);
                    ref.read(timelineProvider.notifier).clearSelection();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
            if (selectedClip is VideoClip) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ActionButton(
                    icon: LucideIcons.rotateCw,
                    label: 'Rotate',
                    color: cs.primary,
                    onTap: () {
                      ref.read(projectProvider.notifier).updateClip(
                            selectedClip.id,
                            (c) {
                              final v = c as VideoClip;
                              return v.copyWith(
                                rotateQuarterTurns:
                                    (v.rotateQuarterTurns + 1) % 4,
                              );
                            },
                          );
                    },
                  ),
                  _ActionButton(
                    icon: LucideIcons.rewind,
                    label: selectedClip.reverse ? 'Forward' : 'Reverse',
                    color: cs.secondary,
                    onTap: () {
                      ref.read(projectProvider.notifier).updateClip(
                            selectedClip.id,
                            (c) => (c as VideoClip)
                                .copyWith(reverse: !selectedClip.reverse),
                          );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Crop',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _cropChip(ref, selectedClip, cs, 'Full', null),
                  _cropChip(ref, selectedClip, cs, '9:16', 9 / 16),
                  _cropChip(ref, selectedClip, cs, '1:1', 1),
                  _cropChip(ref, selectedClip, cs, '16:9', 16 / 9),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _ActionButton(
                    icon: LucideIcons.unplug,
                    label: 'Detach',
                    color: cs.primary,
                    onTap: () {
                      ref
                          .read(projectProvider.notifier)
                          .detachAudio(selectedClip.id);
                    },
                  ),
                  _ActionButton(
                    icon: LucideIcons.snowflake,
                    label: 'Freeze',
                    color: cs.secondary,
                    onTap: () {
                      ref.read(projectProvider.notifier).freezeFrame(
                            selectedClip.id,
                            playback.position,
                            const Duration(seconds: 1),
                          );
                    },
                  ),
                  _ActionButton(
                    icon: LucideIcons.alignHorizontalSpaceAround,
                    label: 'Close gap',
                    color: cs.tertiary,
                    onTap: () {
                      final track = ref
                          .read(projectProvider)
                          ?.findTrackForClip(selectedClip.id);
                      if (track != null) {
                        ref
                            .read(projectProvider.notifier)
                            .closeGapOnTrack(track.id);
                      }
                    },
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

Widget _cropChip(
  WidgetRef ref,
  VideoClip clip,
  ColorScheme cs,
  String label,
  double? ratio,
) {
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
  return FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) {
      ref.read(projectProvider.notifier).updateClip(
            clip.id,
            (c) => (c as VideoClip).copyWith(
              cropNorm: next,
              clearCrop: ratio == null,
            ),
          );
    },
  );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
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

// lib/features/video_editor/widgets/toolbar/panels/trim_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
                  label: 'Delete',
                  color: Colors.redAccent,
                  onTap: () {
                    ref
                        .read(projectProvider.notifier)
                        .removeClip(selectedClip.id);
                    ref.read(timelineProvider.notifier).clearSelection();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }
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

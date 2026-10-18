// lib/features/video_editor/widgets/timeline/timeline_controls.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../utils/editor_constants.dart';

/// Zoom controls and add-track button below the timeline.
class TimelineControls extends StatelessWidget {
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onAddTrack;

  const TimelineControls({
    super.key,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onAddTrack,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          // Add track
          _ControlButton(
            icon: LucideIcons.plus,
            tooltip: 'Add Track',
            onTap: onAddTrack,
          ),
          const Spacer(),

          // Zoom controls
          _ControlButton(
            icon: LucideIcons.zoomOut,
            tooltip: 'Zoom Out',
            onTap: zoom > EditorConstants.minZoom + 0.001 ? onZoomOut : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${(zoom * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _ControlButton(
            icon: LucideIcons.zoomIn,
            tooltip: 'Zoom In',
            onTap: zoom < EditorConstants.maxZoom - 0.001 ? onZoomIn : null,
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onFit,
            style: TextButton.styleFrom(
              minimumSize: const Size(40, 32),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            child: Text(
              'Fit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = onTap != null;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? cs.onSurface.withValues(alpha: 0.7)
                : cs.onSurface.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }
}

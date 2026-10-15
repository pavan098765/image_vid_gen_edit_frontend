// lib/features/video_editor/widgets/timeline/timeline_controls.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../utils/editor_constants.dart';

/// Zoom controls and add-track button below the timeline.
class TimelineControls extends StatelessWidget {
  final double zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onAddTrack;

  const TimelineControls({
    super.key,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onAddTrack,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.onSurface.withOpacity(0.08)),
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
            onTap: zoom > EditorConstants.minZoom ? onZoomOut : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${(zoom * 100).round()}%',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withOpacity(0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          _ControlButton(
            icon: LucideIcons.zoomIn,
            tooltip: 'Zoom In',
            onTap: zoom < EditorConstants.maxZoom ? onZoomIn : null,
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
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: enabled
                ? cs.onSurface.withOpacity(0.7)
                : cs.onSurface.withOpacity(0.2),
          ),
        ),
      ),
    );
  }
}

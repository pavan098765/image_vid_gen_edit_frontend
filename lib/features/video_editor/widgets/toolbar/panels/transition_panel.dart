// lib/features/video_editor/widgets/toolbar/panels/transition_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../models/effect_model.dart';
import '../../../state/editor_providers.dart';

/// Panel for selecting transitions between clips.
class TransitionPanel extends ConsumerStatefulWidget {
  const TransitionPanel({super.key});

  @override
  ConsumerState<TransitionPanel> createState() => _TransitionPanelState();
}

class _TransitionPanelState extends ConsumerState<TransitionPanel> {
  TransitionType _selectedType = TransitionType.none;
  double _durationMs = 500;
  String? _lastClipId;

  void _syncFromClip(VideoClip clip) {
    _selectedType = clip.transitionIn.type;
    _durationMs = clip.transitionIn.duration.inMilliseconds.toDouble();
    _lastClipId = clip.id;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);

    // Only sync from model when clip selection changes
    if (selectedClip is VideoClip && selectedClip.id != _lastClipId) {
      _syncFromClip(selectedClip);
    } else if (selectedClip == null || selectedClip is! VideoClip) {
      _lastClipId = null;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(LucideIcons.layers, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Transitions',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select a video clip, then choose a transition',
            style: TextStyle(
              color: cs.onSurface.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),

          // Transition grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.85,
            ),
            itemCount: TransitionType.values.length,
            itemBuilder: (_, i) {
              final type = TransitionType.values[i];
              final selected = type == _selectedType;
              return GestureDetector(
                onTap: () => _applyTransition(type),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary.withOpacity(0.15)
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? cs.primary
                          : cs.onSurface.withOpacity(0.08),
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        type.icon,
                        style: TextStyle(
                          fontSize: 20,
                          color: selected ? cs.primary : cs.onSurface.withOpacity(0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 9,
                          color: selected ? cs.primary : cs.onSurface.withOpacity(0.5),
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // Duration slider
          Row(
            children: [
              Text(
                'Duration',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _durationMs.clamp(100, 3000),
                  min: 100,
                  max: 3000,
                  divisions: 29,
                  onChanged: (v) {
                    setState(() => _durationMs = v);
                    _updateTransitionDuration(v);
                  },
                ),
              ),
              Text(
                '${(_durationMs / 1000).toStringAsFixed(1)}s',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _applyTransition(TransitionType type) {
    setState(() => _selectedType = type);
    final selectedClip = ref.read(selectedClipProvider);
    if (selectedClip == null || selectedClip is! VideoClip) {
      _showNoClipWarning();
      return;
    }

    ref.read(projectProvider.notifier).updateClip(
          selectedClip.id,
          (c) => (c as VideoClip).copyWith(
            transitionIn: ClipTransition(
              type: type,
              duration: Duration(milliseconds: _durationMs.round()),
            ),
          ),
        );
    _showAppliedFeedback('Transition: ${type.label}');
  }

  void _showAppliedFeedback(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  void _showNoClipWarning() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Select a video clip first'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.orange.shade700,
      ),
    );
  }

  void _updateTransitionDuration(double ms) {
    final selectedClip = ref.read(selectedClipProvider);
    if (selectedClip == null || selectedClip is! VideoClip) return;

    ref.read(projectProvider.notifier).updateClip(
          selectedClip.id,
          (c) {
            final vc = c as VideoClip;
            return vc.copyWith(
            transitionIn: vc.transitionIn.copyWith(
              duration: Duration(milliseconds: ms.round()),
            ),
          );},
        );
  }
}

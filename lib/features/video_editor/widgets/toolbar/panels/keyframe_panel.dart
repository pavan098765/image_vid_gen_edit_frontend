// lib/features/video_editor/widgets/toolbar/panels/keyframe_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/keyframe_model.dart';
import '../../../state/editor_providers.dart';
import '../../../utils/time_utils.dart';

/// Panel for adding and editing keyframe animations on selected clips.
class KeyframePanel extends ConsumerStatefulWidget {
  const KeyframePanel({super.key});

  @override
  ConsumerState<KeyframePanel> createState() => _KeyframePanelState();
}

class _KeyframePanelState extends ConsumerState<KeyframePanel> {
  KeyframeProperty _selectedProp = KeyframeProperty.opacity;
  double _currentValue = 1.0;
  KeyframeEasing _easing = KeyframeEasing.linear;
  String? _lastClipId;

  void _syncFromClip(dynamic clip) {
    if (clip == null) return;
    final clipId = clip.id as String?;
    if (clipId == _lastClipId) return;
    _lastClipId = clipId;

    // Load current default
    _currentValue = _defaultValue(_selectedProp);
    _easing = KeyframeEasing.linear;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);
    final playback = ref.watch(playbackProvider);

    _syncFromClip(selectedClip);

    // Load current keyframe value for the selected property
    if (selectedClip != null) {
      final kfTrack = selectedClip.keyframeTracks
          .where((t) => t.property == _selectedProp)
          .firstOrNull;
      if (kfTrack != null) {
        final relTime = playback.position - selectedClip.startTime;
        _currentValue = kfTrack.valueAt(relTime);
      }
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
              Icon(LucideIcons.diamond, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Animate',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (selectedClip != null)
                FilledButton.icon(
                  onPressed: () => _addKeyframe(selectedClip, playback.position),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Add', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    minimumSize: Size.zero,
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Add keypoints to animate position, scale, rotation & opacity over time. '
            'Move the playhead to the desired time, set a value, then tap "Add".',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.5),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),

          if (selectedClip == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.diamond, size: 32, color: cs.onSurface.withValues(alpha: 0.2)),
                    const SizedBox(height: 8),
                    Text(
                      'Select a clip to add keyframes',
                      style: TextStyle(color: cs.onSurface.withValues(alpha: 0.4), fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Property picker
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: KeyframeProperty.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final prop = KeyframeProperty.values[i];
                  final selected = prop == _selectedProp;
                  return GestureDetector(
                    onTap: () => setState(() {
                      _selectedProp = prop;
                      _currentValue = _defaultValue(prop);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary.withValues(alpha: 0.15)
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                        border: selected
                            ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _propLabel(prop),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                          color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),

            // Current time indicator
            Row(
              children: [
                Icon(LucideIcons.clock, size: 12, color: cs.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Text(
                  'Time: ${TimeUtils.formatDurationMs(playback.position - selectedClip.startTime)}',
                  style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Value slider
            Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(
                    _propLabel(_selectedProp),
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: _currentValue.clamp(_minValue(_selectedProp), _maxValue(_selectedProp)),
                    min: _minValue(_selectedProp),
                    max: _maxValue(_selectedProp),
                    onChanged: (v) => setState(() => _currentValue = v),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    _currentValue.toStringAsFixed(2),
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),

            // Easing picker
            const SizedBox(height: 8),
            Text('Easing', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: KeyframeEasing.values.map((e) {
                final selected = e == _easing;
                return GestureDetector(
                  onTap: () => setState(() => _easing = e),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected ? cs.primary.withValues(alpha: 0.15) : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      e.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // Existing keyframes list
            const SizedBox(height: 16),
            _buildKeyframeList(selectedClip, cs),
          ],
        ],
      ),
    );
  }

  Widget _buildKeyframeList(dynamic clip, ColorScheme cs) {
    final List<KeyframeTrack> allTracks = List<KeyframeTrack>.from(clip.keyframeTracks);
    final kfTrack = allTracks.where((t) => t.property == _selectedProp).firstOrNull;

    if (kfTrack == null || kfTrack.keyframes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No keyframes for ${_propLabel(_selectedProp)}',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.4)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Keyframes (${kfTrack.keyframes.length})',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        ...kfTrack.keyframes.map((kf) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.diamond, size: 10, color: cs.primary),
                    const SizedBox(width: 6),
                    Text(
                      TimeUtils.formatDurationMs(kf.time),
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${kf.value.toStringAsFixed(2)} (${kf.easing.name})',
                      style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _removeKeyframe(clip, kf.time),
                      child: Icon(
                        LucideIcons.trash2,
                        size: 14,
                        color: Colors.redAccent.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  void _addKeyframe(dynamic clip, Duration pos) {
    final Duration relTime = pos - (clip.startTime as Duration);
    final tracks = List<KeyframeTrack>.from(clip.keyframeTracks);
    final idx = tracks.indexWhere((t) => t.property == _selectedProp);

    if (idx >= 0) {
      tracks[idx] = tracks[idx].setKeyframe(relTime, _currentValue, easing: _easing);
    } else {
      tracks.add(
        KeyframeTrack(
          clipId: clip.id as String,
          property: _selectedProp,
          keyframes: [Keyframe(time: relTime, value: _currentValue, easing: _easing)],
        ),
      );
    }

    ref.read(projectProvider.notifier).updateClip(
          clip.id as String,
          (c) => c.copyWith(keyframeTracks: tracks),
        );
  }

  void _removeKeyframe(dynamic clip, Duration time) {
    final tracks = List<KeyframeTrack>.from(clip.keyframeTracks);
    final idx = tracks.indexWhere((t) => t.property == _selectedProp);
    if (idx >= 0) {
      tracks[idx] = tracks[idx].removeKeyframe(time);
      ref.read(projectProvider.notifier).updateClip(
            clip.id as String,
            (c) => c.copyWith(keyframeTracks: tracks),
          );
    }
  }

  String _propLabel(KeyframeProperty p) {
    switch (p) {
      case KeyframeProperty.positionX:
        return 'Pos X';
      case KeyframeProperty.positionY:
        return 'Pos Y';
      case KeyframeProperty.scale:
        return 'Scale';
      case KeyframeProperty.rotation:
        return 'Rotation';
      case KeyframeProperty.opacity:
        return 'Opacity';
    }
  }

  double _defaultValue(KeyframeProperty p) {
    switch (p) {
      case KeyframeProperty.scale:
      case KeyframeProperty.opacity:
        return 1.0;
      default:
        return 0.0;
    }
  }

  double _minValue(KeyframeProperty p) {
    switch (p) {
      case KeyframeProperty.positionX:
      case KeyframeProperty.positionY:
        return -1.0;
      case KeyframeProperty.rotation:
        return -3.14159;
      case KeyframeProperty.scale:
      case KeyframeProperty.opacity:
        return 0.0;
    }
  }

  double _maxValue(KeyframeProperty p) {
    switch (p) {
      case KeyframeProperty.positionX:
      case KeyframeProperty.positionY:
        return 1.0;
      case KeyframeProperty.rotation:
        return 3.14159;
      case KeyframeProperty.scale:
        return 3.0;
      case KeyframeProperty.opacity:
        return 1.0;
    }
  }
}

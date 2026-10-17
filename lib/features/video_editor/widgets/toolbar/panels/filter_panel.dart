// lib/features/video_editor/widgets/toolbar/panels/filter_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../models/effect_model.dart';
import '../../../state/editor_providers.dart';
import '../../../utils/color_matrix_presets.dart';

/// Panel for color filters and adjustments.
class FilterPanel extends ConsumerStatefulWidget {
  const FilterPanel({super.key});

  @override
  ConsumerState<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends ConsumerState<FilterPanel> {
  String? _selectedFilter;
  double _brightness = 0;
  double _contrast = 1.0;
  double _saturation = 1.0;
  String? _lastClipId;

  void _syncFromClip(VideoClip clip) {
    final adj = clip.colorAdjustment;
    _selectedFilter = adj.filterPresetId;
    _brightness = adj.brightness;
    _contrast = adj.contrast;
    _saturation = adj.saturation;
    _lastClipId = clip.id;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);

    // Only sync local state from model when the selected clip changes
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
              Icon(LucideIcons.palette, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Filters & Adjustments',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _selectionHint(ref),
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: cs.onSurface.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 12),
          if (selectedClip is VideoClip) ...[
            Text('Looks',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final look in VideoLook.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(look.label),
                        selected: selectedClip.look == look,
                        onSelected: (_) {
                          applyToSelectedVideoClips(
                            ref,
                            (c) => c.copyWith(look: look),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Filter presets grid
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ColorMatrixPresets.presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final preset = ColorMatrixPresets.presets[i];
                final selected = _selectedFilter == preset.id ||
                    (preset.id == 'normal' && _selectedFilter == null);
                return GestureDetector(
                  onTap: () => _applyFilter(preset.id == 'normal' ? null : preset.id),
                  child: Container(
                    width: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? cs.primary
                            : cs.onSurface.withOpacity(0.1),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Preview swatch using the filter matrix
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: LinearGradient(
                              colors: [
                                _matrixPreviewColor(preset.matrix),
                                _matrixPreviewColor2(preset.matrix),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preset.name,
                          style: TextStyle(
                            fontSize: 9,
                            color: selected
                                ? cs.primary
                                : cs.onSurface.withOpacity(0.6),
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Adjustment sliders
          _adjustmentSlider(
            'Brightness',
            _brightness,
            -100,
            100,
            (v) {
              setState(() => _brightness = v);
              _updateAdjustment();
            },
          ),
          _adjustmentSlider(
            'Contrast',
            _contrast,
            0.5,
            2.0,
            (v) {
              setState(() => _contrast = v);
              _updateAdjustment();
            },
          ),
          _adjustmentSlider(
            'Saturation',
            _saturation,
            0.0,
            2.0,
            (v) {
              setState(() => _saturation = v);
              _updateAdjustment();
            },
          ),
        ],
      ),
    );
  }

  Widget _adjustmentSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withOpacity(0.6),
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  void _applyFilter(String? filterId) {
    setState(() => _selectedFilter = filterId);
    _updateAdjustment();
  }

  void _updateAdjustment() {
    if (!ensureDefaultVideoSelection(ref)) {
      _showNoClipWarning();
      return;
    }

    final count = applyToSelectedVideoClips(
      ref,
      (c) => c.copyWith(
        colorAdjustment: ColorAdjustment(
          brightness: _brightness,
          contrast: _contrast,
          saturation: _saturation,
          filterPresetId: _selectedFilter,
        ),
      ),
    );
    if (count == 0) {
      _showNoClipWarning();
      return;
    }
    _showAppliedFeedback(count);
  }

  String _selectionHint(WidgetRef ref) {
    final project = ref.watch(projectProvider);
    final ids = ref.watch(timelineProvider).selectedClipIds;
    var videos = 0;
    if (project != null) {
      for (final id in ids) {
        if (project.findClipById(id) is VideoClip) videos++;
      }
    }
    if (videos > 1) {
      return 'Applying to $videos selected clips. A split stays separate until you long-press the other piece.';
    }
    return 'Applies to the selected clip only. Long-press another clip on the same track to include it.';
  }

  void _showAppliedFeedback(int count) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(count > 1
                ? 'Filter applied to $count clips'
                : 'Filter applied to this clip'),
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

  Color _matrixPreviewColor(List<double> m) {
    final r = (m[0] * 200 + m[4]).clamp(0, 255).toInt();
    final g = (m[6] * 200 + m[9]).clamp(0, 255).toInt();
    final b = (m[12] * 200 + m[14]).clamp(0, 255).toInt();
    return Color.fromARGB(255, r, g, b);
  }

  Color _matrixPreviewColor2(List<double> m) {
    final r = (m[0] * 100 + m[4]).clamp(0, 255).toInt();
    final g = (m[6] * 150 + m[9]).clamp(0, 255).toInt();
    final b = (m[12] * 200 + m[14]).clamp(0, 255).toInt();
    return Color.fromARGB(255, r, g, b);
  }
}

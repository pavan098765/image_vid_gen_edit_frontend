import 'package:flutter/material.dart';

import 'package:kala_ai_create_images_videos_with_ai/core/utils/rife_interpolation.dart';

/// Discrete 2× / 4× / 8× control matching RIFE's native interpolation steps.
class RifeMultiplierControl extends StatelessWidget {
  const RifeMultiplierControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = kRifeSpeedMultipliers.contains(value) ? value : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interpolation strength',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle ??
              'Doubles frame count (2x or 4x FPS). '
              'Exact output FPS depends on source rate.',
          style: TextStyle(
            fontSize: 11,
            height: 1.35,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment<int>(
              value: 2,
              label: Text('2×'),
              tooltip: 'Double frame rate',
            ),
            ButtonSegment<int>(
              value: 4,
              label: Text('4×'),
              tooltip: 'Quadruple frame rate',
            ),
            // ButtonSegment<int>(
            //   value: 8,
            //   label: Text('8×'),
            //   tooltip: '8× frame rate',
            // ),
          ],
          selected: {v},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            onChanged(s.first);
          },
          showSelectedIcon: false,
        ),
      ],
    );
  }
}

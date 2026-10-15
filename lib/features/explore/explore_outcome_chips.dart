import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ExploreOutcomeChip {
  all,
  edit,
  createImage,
  createVideo,
  social,
  restore,
  favorites,
}

extension ExploreOutcomeChipX on ExploreOutcomeChip {
  String get label {
    switch (this) {
      case ExploreOutcomeChip.all:
        return 'All';
      case ExploreOutcomeChip.edit:
        return 'Edit a photo';
      case ExploreOutcomeChip.createImage:
        return 'Create an image';
      case ExploreOutcomeChip.createVideo:
        return 'Create a video';
      case ExploreOutcomeChip.social:
        return 'Social';
      case ExploreOutcomeChip.restore:
        return 'Restore';
      case ExploreOutcomeChip.favorites:
        return 'Favorites';
    }
  }
}

class ExploreOutcomeChips extends StatelessWidget {
  final ExploreOutcomeChip selected;
  final ValueChanged<ExploreOutcomeChip> onSelected;

  const ExploreOutcomeChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: ExploreOutcomeChip.values.map((chip) {
          final isOn = chip == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              label: Text(chip.label),
              selected: isOn,
              onSelected: (_) {
                HapticFeedback.lightImpact();
                onSelected(chip);
              },
              selectedColor: cs.primary.withValues(alpha: 0.18),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }
}

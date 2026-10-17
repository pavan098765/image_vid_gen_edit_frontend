import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../models/effect_model.dart';
import '../../../state/editor_providers.dart';

class ChromaPanel extends ConsumerWidget {
  const ChromaPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final clip = ref.watch(selectedClipProvider);
    if (clip is! VideoClip) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Select a video clip to key a green screen.'),
      );
    }
    final key = clip.chroma;
    void paint(ChromaSettings next) {
      applyToSelectedVideoClips(ref, (c) => c.copyWith(chroma: next));
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.aperture, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              const Text('Key',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch(
                value: key.enabled,
                onChanged: (v) => paint(key.copyWith(enabled: v)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(
                label: const Text('Green'),
                onPressed: () =>
                    paint(key.copyWith(enabled: true, color: 0xFF00B140)),
              ),
              ActionChip(
                label: const Text('Blue'),
                onPressed: () =>
                    paint(key.copyWith(enabled: true, color: 0xFF0044FF)),
              ),
            ],
          ),
          Slider(
            value: key.similarity,
            min: 0.05,
            max: 0.8,
            label: 'Similarity',
            onChanged: (v) => paint(key.copyWith(similarity: v)),
          ),
        ],
      ),
    );
  }
}

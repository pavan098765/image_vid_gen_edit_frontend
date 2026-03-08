// lib/features/video_editor/widgets/toolbar/panels/sticker_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../models/project_model.dart';
import '../../../state/editor_providers.dart';

/// Panel for browsing and adding emoji/sticker overlays.
/// When a StickerClip is selected, shows edit/delete options.
class StickerPanel extends ConsumerStatefulWidget {
  const StickerPanel({super.key});

  @override
  ConsumerState<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends ConsumerState<StickerPanel> {
  int _categoryIndex = 0;

  static const _categories = [
    (name: 'Smileys', emojis: ['😀', '😂', '🥹', '😍', '🥰', '😎', '🤩', '😤', '🤯', '😱', '🥳', '😈', '💀', '🤖', '👻', '🎃']),
    (name: 'Gestures', emojis: ['👍', '👎', '✌️', '🤞', '🤙', '👋', '🙌', '👏', '🤝', '💪', '🫶', '🤲', '👐', '🖐️', '✊', '👊']),
    (name: 'Hearts', emojis: ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💗', '💖', '💝', '💘', '💕', '💔', '❣️', '💓']),
    (name: 'Symbols', emojis: ['⭐', '🌟', '✨', '💫', '🔥', '💥', '💯', '🎯', '🏆', '🎨', '🎭', '🎬', '📸', '🎵', '🎶', '🎤']),
    (name: 'Nature', emojis: ['🌸', '🌺', '🌻', '🌹', '🌈', '☀️', '🌙', '⛅', '❄️', '🍀', '🌿', '🍂', '🌊', '⚡', '🦋', '🐝']),
    (name: 'Objects', emojis: ['💎', '👑', '🎀', '🎁', '🎈', '🎉', '🎊', '🏅', '🥇', '📌', '💡', '🔔', '📢', '💬', '💭', '🗯️']),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);
    final isEditing = selectedClip is StickerClip;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(LucideIcons.smile, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                isEditing ? 'Edit Sticker' : 'Stickers & Emoji',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (isEditing)
                IconButton(
                  onPressed: () => _deleteClip(selectedClip.id),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.redAccent,
                  tooltip: 'Delete Sticker',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
            ],
          ),
        ),

        // Show selected sticker when editing
        if (isEditing) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Text(
                    selectedClip.isEmoji ? selectedClip.stickerData : '🖼',
                    style: const TextStyle(fontSize: 36),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap a new emoji below to change',
                      style: TextStyle(
                        color: cs.onSurface.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Category tabs
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final selected = i == _categoryIndex;
              return GestureDetector(
                onTap: () => setState(() => _categoryIndex = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary.withOpacity(0.15)
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                    border: selected
                        ? Border.all(color: cs.primary.withOpacity(0.4))
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _categories[i].name,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? cs.primary : cs.onSurface.withOpacity(0.6),
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Emoji grid
        Flexible(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: _categories[_categoryIndex].emojis.length,
            itemBuilder: (_, i) {
              final emoji = _categories[_categoryIndex].emojis[i];
              return GestureDetector(
                onTap: () {
                  if (isEditing) {
                    _changeSticker(selectedClip.id, emoji);
                  } else {
                    _addSticker(emoji);
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: cs.surfaceContainerHigh.withOpacity(0.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 22)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _changeSticker(String clipId, String emoji) {
    ref.read(projectProvider.notifier).updateClip(
      clipId,
      (c) => (c as StickerClip).copyWith(stickerData: emoji),
    );
  }

  void _deleteClip(String clipId) {
    ref.read(projectProvider.notifier).removeClip(clipId);
    ref.read(timelineProvider.notifier).clearSelection();
    Navigator.of(context).pop();
  }

  void _addSticker(String emoji) {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final playback = ref.read(playbackProvider);

    // Find or create sticker track
    var stickerTrack = project.tracks
        .where((t) => t.type == TrackType.sticker)
        .firstOrNull;

    if (stickerTrack == null) {
      final trackId = '${project.id}_sticker_${DateTime.now().microsecondsSinceEpoch}';
      stickerTrack = Track(
        id: trackId,
        type: TrackType.sticker,
        name: 'Sticker 1',
      );
      ref.read(projectProvider.notifier).addTrack(stickerTrack);
    }

    final clipId = '${project.id}_stickerclip_${DateTime.now().microsecondsSinceEpoch}';
    final clip = StickerClip(
      id: clipId,
      startTime: playback.position,
      duration: const Duration(seconds: 3),
      stickerData: emoji,
      isEmoji: true,
    );

    ref.read(projectProvider.notifier).addClipToTrack(stickerTrack.id, clip);
    ref.read(timelineProvider.notifier).selectClip(clipId, trackId: stickerTrack.id);
  }
}

// lib/features/video_editor/widgets/toolbar/bottom_toolbar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/clip_model.dart';
import '../../state/editor_providers.dart';
import '../../state/tool_notifier.dart';
import '../../utils/editor_constants.dart';
import 'panels/audio_panel.dart';
import 'panels/chroma_panel.dart';
import 'panels/export_panel.dart';
import 'panels/filter_panel.dart';
import 'panels/keyframe_panel.dart';
import 'panels/pip_panel.dart';
import 'panels/speed_panel.dart';
import 'panels/sticker_panel.dart';
import 'panels/text_panel.dart';
import 'panels/transition_panel.dart';
import 'panels/trim_panel.dart';

/// The bottom toolbar that shows tool icons and opens modal bottom sheets.
class BottomToolbar extends ConsumerWidget {
  const BottomToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final toolState = ref.watch(toolProvider);

    return Container(
      height: EditorConstants.toolbarHeight,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.onSurface.withOpacity(0.1)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _toolButton(context, ref, EditorTool.trim, LucideIcons.scissors, toolState),
            _toolButton(context, ref, EditorTool.text, LucideIcons.type, toolState),
            _toolButton(context, ref, EditorTool.sticker, LucideIcons.smile, toolState),
            _toolButton(context, ref, EditorTool.audio, LucideIcons.music, toolState),
            _toolButton(context, ref, EditorTool.export, LucideIcons.download, toolState),
            _toolButton(context, ref, EditorTool.more, LucideIcons.moreHorizontal, toolState),
          ],
        ),
      ),
    );
  }

  Widget _toolButton(
    BuildContext context,
    WidgetRef ref,
    EditorTool tool,
    IconData icon,
    ToolState toolState,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isActive = toolState.activeTool == tool && toolState.isPanelOpen;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => _onToolTap(context, ref, tool),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? cs.primary.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isActive
                ? Border.all(color: cs.primary.withOpacity(0.3))
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isActive ? cs.primary : cs.onSurface.withOpacity(0.6),
              ),
              const SizedBox(height: 4),
              Text(
                tool.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? cs.primary : cs.onSurface.withOpacity(0.72),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onToolTap(BuildContext context, WidgetRef ref, EditorTool tool) {
    openToolSheet(context, ref, tool);
  }

  /// Opens the modal bottom sheet for the given tool.
  /// Can be called externally (e.g. from timeline clip tap).
  static void openToolSheet(BuildContext context, WidgetRef ref, EditorTool tool) {
    ref.read(toolProvider.notifier).openTool(tool);

    final panel = _buildPanelForTool(tool);
    if (panel == null) return;

    final cs = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return ProviderScope(
          parent: ProviderScope.containerOf(context),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Panel content
                  Flexible(child: panel),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      ref.read(toolProvider.notifier).closePanel();
    });
  }

  static Widget? _buildPanelForTool(EditorTool tool) {
    switch (tool) {
      case EditorTool.trim:
        return const TrimPanel();
      case EditorTool.text:
        return const TextPanel();
      case EditorTool.audio:
        return const AudioPanel();
      case EditorTool.filter:
        return const FilterPanel();
      case EditorTool.transition:
        return const TransitionPanel();
      case EditorTool.speed:
        return const SpeedPanel();
      case EditorTool.sticker:
        return const StickerPanel();
      case EditorTool.pip:
        return const PipPanel();
      case EditorTool.export:
        return const ExportPanel();
      case EditorTool.keyframe:
        return const KeyframePanel();
      case EditorTool.chroma:
        return const ChromaPanel();
      case EditorTool.more:
        return const _MoreToolsSheet();
      case EditorTool.none:
        return null;
    }
  }
}

class _MoreToolsSheet extends ConsumerWidget {
  const _MoreToolsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget chip(EditorTool tool, IconData icon) {
      return ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text(tool.label),
        onPressed: () {
          Navigator.pop(context);
          BottomToolbar.openToolSheet(context, ref, tool);
        },
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          chip(EditorTool.filter, LucideIcons.palette),
          chip(EditorTool.speed, LucideIcons.gauge),
          chip(EditorTool.keyframe, LucideIcons.diamond),
          chip(EditorTool.pip, LucideIcons.pictureInPicture2),
          chip(EditorTool.chroma, LucideIcons.aperture),
          ActionChip(
            avatar: const Icon(LucideIcons.snowflake, size: 16),
            label: const Text('Freeze'),
            onPressed: () {
              Navigator.pop(context);
              final clip = ref.read(selectedClipProvider);
              final pos = ref.read(playbackProvider).position;
              if (clip is VideoClip) {
                ref.read(projectProvider.notifier).freezeFrame(
                      clip.id,
                      pos,
                      const Duration(seconds: 1),
                    );
              }
            },
          ),
          chip(EditorTool.transition, LucideIcons.layers),
        ],
      ),
    );
  }
}

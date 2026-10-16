// lib/features/video_editor/widgets/toolbar/bottom_toolbar.dart

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/clip_model.dart' hide Clip;
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
        onTap: () => openToolSheet(context, tool),
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

  /// Bumped so a sheet that is being replaced does not clear the next one.
  static int _sheetToken = 0;

  static void invalidateOpenSheet() => _sheetToken++;

  /// Opens the modal bottom sheet for the given tool.
  /// Shares the editor's provider container so edits update the timeline.
  static void openToolSheet(BuildContext context, EditorTool tool) {
    final container = ProviderScope.containerOf(context, listen: false);
    final current = container.read(toolProvider);
    if (current.isPanelOpen && current.activeTool == tool) return;

    final panel = _buildPanelForTool(tool, context);
    if (panel == null) return;

    final token = ++_sheetToken;
    container.read(toolProvider.notifier).activate(tool);

    final cs = Theme.of(context).colorScheme;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = _sheetHeightFor(tool, screenHeight);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return UncontrolledProviderScope(
          container: container,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: cs.surface,
              elevation: 12,
              shadowColor: Colors.black54,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(22)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: sheetHeight,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(child: panel),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      if (token != _sheetToken) return;
      container.read(toolProvider.notifier).closePanel();
    });
  }

  static double _sheetHeightFor(EditorTool tool, double screenHeight) {
    final cap = switch (tool) {
      EditorTool.more => 300.0,
      EditorTool.trim => 360.0,
      EditorTool.export || EditorTool.text || EditorTool.filter => 440.0,
      _ => 380.0,
    };
    return math.min(screenHeight * 0.52, cap);
  }

  static Widget? _buildPanelForTool(EditorTool tool, BuildContext hostContext) {
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
        return _MoreToolsSheet(hostContext: hostContext);
      case EditorTool.none:
        return null;
    }
  }
}

class _MoreToolsSheet extends ConsumerWidget {
  final BuildContext hostContext;

  const _MoreToolsSheet({required this.hostContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tools = <(EditorTool, IconData, String)>[
      (EditorTool.filter, LucideIcons.palette, 'Filters'),
      (EditorTool.speed, LucideIcons.gauge, 'Speed'),
      (EditorTool.keyframe, LucideIcons.diamond, 'Animate'),
      (EditorTool.transition, LucideIcons.layers, 'Effects'),
      (EditorTool.pip, LucideIcons.pictureInPicture2, 'PiP'),
      (EditorTool.chroma, LucideIcons.aperture, 'Chroma key'),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Text(
          'More',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
          children: [
            for (final tool in tools)
              _MoreTile(
                icon: tool.$2,
                label: tool.$3,
                color: cs.primary,
                onTap: () => _openTool(context, tool.$1),
              ),
            _MoreTile(
              icon: LucideIcons.snowflake,
              label: 'Freeze',
              color: cs.secondary,
              onTap: () => _freeze(context, ref),
            ),
          ],
        ),
      ],
    );
  }

  void _openTool(BuildContext sheetContext, EditorTool tool) {
    HapticFeedback.selectionClick();
    final host = hostContext;
    BottomToolbar.invalidateOpenSheet();
    Navigator.of(sheetContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!host.mounted) return;
      BottomToolbar.openToolSheet(host, tool);
    });
  }

  Future<void> _freeze(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();
    final clip = ref.read(selectedClipProvider);
    final pos = ref.read(playbackProvider).position;
    if (clip is! VideoClip) {
      _toast(context, 'Select a video clip first');
      return;
    }
    final inside = pos > clip.startTime + const Duration(milliseconds: 80) &&
        pos < clip.endTime - const Duration(milliseconds: 80);
    if (!inside) {
      _toast(context, 'Move the playhead into the clip, then freeze');
      return;
    }
    await ref.read(projectProvider.notifier).freezeFrame(
          clip.id,
          pos,
          const Duration(seconds: 1),
        );
    if (!context.mounted) return;
    ref.read(timelineProvider.notifier).focusOn(pos);
    _toast(context, 'Froze 1 second at the playhead');
    Navigator.of(context).pop();
  }
}

class _MoreTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MoreTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.22)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1800),
      ),
    );
}

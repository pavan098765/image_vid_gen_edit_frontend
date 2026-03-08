// lib/features/video_editor/widgets/toolbar/panels/export_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../models/project_model.dart';
import '../../../state/editor_providers.dart';

/// Panel for configuring export settings and starting the render.
class ExportPanel extends ConsumerWidget {
  const ExportPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final project = ref.watch(projectProvider);
    final settings = project?.exportSettings ?? const ExportSettings();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(LucideIcons.download, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Export Video',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Quality presets
          Text('Quality',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          Row(
            children: ExportQuality.values.map((q) {
              final selected = q == settings.quality;
              return Expanded(
                child: GestureDetector(
                  onTap: () => ref
                      .read(projectProvider.notifier)
                      .updateExportSettings(settings.copyWith(quality: q)),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary.withOpacity(0.15)
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? cs.primary : cs.onSurface.withOpacity(0.08),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      q.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                        color: selected ? cs.primary : cs.onSurface.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Aspect ratio
          Text('Aspect Ratio',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(height: 8),
          SizedBox(
            height: 58,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AspectRatioPreset.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final ar = AspectRatioPreset.values[i];
                final selected = ar == settings.aspectRatio;
                return GestureDetector(
                  onTap: () => ref
                      .read(projectProvider.notifier)
                      .updateExportSettings(settings.copyWith(aspectRatio: ar)),
                  child: Container(
                    width: 72,
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary.withOpacity(0.15)
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? cs.primary : cs.onSurface.withOpacity(0.08),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ar.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? cs.primary : cs.onSurface.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ar.platformHint,
                          style: TextStyle(
                            fontSize: 9,
                            color: selected
                                ? cs.primary.withOpacity(0.7)
                                : cs.onSurface.withOpacity(0.4),
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

          // Format + FPS
          Row(
            children: [
              // Format
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Format',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.6))),
                    const SizedBox(height: 6),
                    Row(
                      children: ['mp4', 'mov'].map((f) {
                        final selected = f == settings.format;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => ref
                                .read(projectProvider.notifier)
                                .updateExportSettings(settings.copyWith(format: f)),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? cs.primary.withOpacity(0.15)
                                    : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? cs.primary
                                      : cs.onSurface.withOpacity(0.08),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                f.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      selected ? FontWeight.w600 : FontWeight.normal,
                                  color: selected
                                      ? cs.primary
                                      : cs.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // FPS
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('FPS',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withOpacity(0.6))),
                    const SizedBox(height: 6),
                    Row(
                      children: [24, 30, 60].map((fps) {
                        final selected = fps == settings.fps;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => ref
                                .read(projectProvider.notifier)
                                .updateExportSettings(settings.copyWith(fps: fps)),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: selected
                                    ? cs.primary.withOpacity(0.15)
                                    : cs.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selected
                                      ? cs.primary
                                      : cs.onSurface.withOpacity(0.08),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$fps',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      selected ? FontWeight.w600 : FontWeight.normal,
                                  color: selected
                                      ? cs.primary
                                      : cs.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Export button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                // Trigger export via parent page callback
                _triggerExport(context, ref);
              },
              icon: const Icon(LucideIcons.download),
              label: const Text('Export Video'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _triggerExport(BuildContext context, WidgetRef ref) {
    // Close the bottom sheet first
    Navigator.of(context).pop();

    // Increment the export trigger counter to signal VideoEditorPage
    ref.read(exportTriggerProvider.notifier).state++;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting export... This may take a moment.'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

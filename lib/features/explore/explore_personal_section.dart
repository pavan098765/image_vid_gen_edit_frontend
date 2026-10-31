import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/relative_time.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/tool_launch.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/user_template_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ExplorePersonalSection extends StatelessWidget {
  final List<JobModel> jobs;
  final List<UserTemplateRecord> shortcuts;
  final Set<String> dismissedJobIds;
  final VoidCallback onSeeAll;
  final ValueChanged<JobModel> onOpenJob;
  final ValueChanged<UserTemplateRecord> onOpenShortcut;
  final ValueChanged<JobModel> onDismissJob;
  final ValueChanged<UserTemplateRecord> onDismissShortcut;

  const ExplorePersonalSection({
    super.key,
    required this.jobs,
    required this.shortcuts,
    required this.dismissedJobIds,
    required this.onSeeAll,
    required this.onOpenJob,
    required this.onOpenShortcut,
    required this.onDismissJob,
    required this.onDismissShortcut,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final continueJobs = jobs
        .where((job) =>
            !dismissedJobIds.contains(job.jobId) && _hasUsableThumb(job))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (continueJobs.isNotEmpty) {
      final shown = continueJobs.take(3).toList();
      return _section(
        cs,
        title: 'Continue creating',
        trailing: continueJobs.length > 3
            ? TextButton(onPressed: onSeeAll, child: const Text('See all'))
            : null,
        child: Column(
          children: [
            for (final job in shown)
              _GlassRow(
                isDark: isDark,
                onTap: () => onOpenJob(job),
                onDismiss: () => onDismissJob(job),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _thumbFor(job, cs),
                ),
                title: job.templateTitle ?? job.title,
                subtitle: relativeTimeLabel(job.createdAt),
                note: job.expiryCue,
                noteColor: job.expiryCueUrgent ? cs.error : cs.onSurfaceVariant,
              ),
          ],
        ),
      );
    }

    if (shortcuts.isNotEmpty) {
      final shown = shortcuts.take(3).toList();
      return _section(
        cs,
        title: 'My templates',
        child: Column(
          children: [
            for (final template in shown)
              _GlassRow(
                isDark: isDark,
                onTap: () => onOpenShortcut(template),
                onDismiss: () => onDismissShortcut(template),
                leading: const _TemplateMark(),
                title: template.name,
                subtitle: template.prompt,
              ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  bool _hasUsableThumb(JobModel job) {
    if (job.status != 'completed') return false;
    final local = job.localFilePath;
    if (local != null &&
        local.isNotEmpty &&
        File(local).existsSync() &&
        pathLooksLikeImage(local)) {
      return true;
    }
    final url = job.downloadUrl;
    if (!job.isCloudExpired &&
        url != null &&
        url.isNotEmpty &&
        pathLooksLikeImage(url.split('?').first)) {
      return true;
    }
    return false;
  }

  Widget _thumbFor(JobModel job, ColorScheme cs) {
    final local = job.localFilePath;
    if (local != null &&
        local.isNotEmpty &&
        File(local).existsSync() &&
        pathLooksLikeImage(local)) {
      return Image.file(
        File(local),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbFallback(cs),
      );
    }
    final url = job.downloadUrl;
    if (url == null || url.isEmpty) return _thumbFallback(cs);
    return Image.network(
      url,
      width: 64,
      height: 64,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _thumbFallback(cs),
    );
  }

  Widget _thumbFallback(ColorScheme cs) {
    return Container(
      width: 64,
      height: 64,
      color: cs.primaryContainer,
      alignment: Alignment.center,
      child: Icon(LucideIcons.image, color: cs.primary, size: 22),
    );
  }

  Widget _section(
    ColorScheme cs, {
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _GlassRow extends StatelessWidget {
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final Widget leading;
  final String title;
  final String subtitle;
  final String? note;
  final Color? noteColor;

  const _GlassRow({
    required this.isDark,
    required this.onTap,
    required this.onDismiss,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.note,
    this.noteColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: kalaGlassDecoration(isDark: isDark, radius: 16),
            padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (note != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: noteColor ?? cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: onDismiss,
                  icon: Icon(
                    LucideIcons.x,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateMark extends StatelessWidget {
  const _TemplateMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: KalaColors.brandGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(LucideIcons.sparkles, color: Colors.white, size: 22),
    );
  }
}

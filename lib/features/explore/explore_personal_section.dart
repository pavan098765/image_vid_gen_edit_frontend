import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/relative_time.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/tool_launch.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/user_template_store.dart';

class ExplorePersonalSection extends StatelessWidget {
  final List<JobModel> jobs;
  final List<UserTemplateRecord> shortcuts;
  final List<Map<String, dynamic>> starterTemplates;
  final VoidCallback onSeeAll;
  final ValueChanged<JobModel> onOpenJob;
  final ValueChanged<UserTemplateRecord> onOpenShortcut;
  final ValueChanged<Map<String, dynamic>> onOpenStarter;

  const ExplorePersonalSection({
    super.key,
    required this.jobs,
    required this.shortcuts,
    required this.starterTemplates,
    required this.onSeeAll,
    required this.onOpenJob,
    required this.onOpenShortcut,
    required this.onOpenStarter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final continueJobs = jobs.where(_hasUsableThumb).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (continueJobs.isNotEmpty) {
      final shown = continueJobs.take(2).toList();
      return _section(
        cs,
        title: 'Continue creating',
        trailing: continueJobs.length > 2
            ? TextButton(onPressed: onSeeAll, child: const Text('See all'))
            : null,
        child: Column(
          children: shown.map((job) {
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: _thumbFor(job),
              ),
              title: Text(
                job.templateTitle ?? job.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(relativeTimeLabel(job.createdAt)),
                  if (job.expiryCue != null)
                    Text(
                      job.expiryCue!,
                      style: TextStyle(
                        fontSize: 12,
                        color: job.expiryCueUrgent
                            ? cs.error
                            : cs.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              onTap: () => onOpenJob(job),
            );
          }).toList(),
        ),
      );
    }

    if (shortcuts.isNotEmpty) {
      final shown = shortcuts.take(2).toList();
      return _section(
        cs,
        title: 'Your shortcuts',
        child: Column(
          children: shown
              .map(
                (t) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(t.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    t.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => onOpenShortcut(t),
                ),
              )
              .toList(),
        ),
      );
    }

    if (starterTemplates.isEmpty) return const SizedBox.shrink();
    return _section(
      cs,
      title: 'Start your first creation',
      child: Column(
        children: starterTemplates
            .map(
              (t) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text(t['title'] as String? ?? 'Template'),
                subtitle: Text(t['subtitle'] as String? ?? ''),
                onTap: () => onOpenStarter(t),
              ),
            )
            .toList(),
      ),
    );
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

  Widget _thumbFor(JobModel job) {
    final local = job.localFilePath;
    if (local != null &&
        local.isNotEmpty &&
        File(local).existsSync() &&
        pathLooksLikeImage(local)) {
      return Image.file(
        File(local),
        width: 72,
        height: 72,
        fit: BoxFit.cover,
      );
    }
    return Image.network(
      job.downloadUrl!,
      width: 72,
      height: 72,
      fit: BoxFit.cover,
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
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

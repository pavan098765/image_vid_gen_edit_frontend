import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/polling_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/audio_result_player.dart';

/// Saves a Kie result onto the phone once it has been ready for 17 minutes.
class KieResultSaver {
  static Timer? _timer;
  static bool _ticking = false;
  static final Set<String> _inFlight = <String>{};
  static GlobalKey<NavigatorState>? _navigatorKey;

  static void start(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(tick());
    });
    unawaited(tick());
  }

  static Future<void> tick() async {
    if (_ticking) return;
    if (_navigatorKey?.currentContext == null) return;
    _ticking = true;
    try {
      final due = <JobModel>[];
      var remembered = false;
      for (final job in jobListNotifier.value) {
        if (job.hasKeptResult && !job.autoDownloaded) {
          job.autoDownloaded = true;
          remembered = true;
        }
        if (job.shouldAutoSave) due.add(job);
      }
      if (remembered) await saveJobsToPrefs();
      for (final job in due) {
        if (_inFlight.contains(job.jobId)) continue;
        _inFlight.add(job.jobId);
        try {
          await _save(job);
        } catch (e) {
          debugPrint('Auto-save failed for ${job.jobId}: $e');
        } finally {
          _inFlight.remove(job.jobId);
        }
      }
    } finally {
      _ticking = false;
    }
  }

  static bool _stillListed(String jobId) =>
      jobListNotifier.value.any((job) => job.jobId == jobId);

  static Future<void> _save(JobModel job) async {
    if (await wasJobDeleted(job.jobId) || !_stillListed(job.jobId)) return;
    final url = await PollingService.refreshDownloadUrl(job.jobId);
    if (url == null || url.isEmpty) return;
    if (await wasJobDeleted(job.jobId) || !_stillListed(job.jobId)) return;
    job.downloadUrl = url;
    await addOrUpdateJob(job);
    if (await wasJobDeleted(job.jobId) || !_stillListed(job.jobId)) return;
    final context = _navigatorKey?.currentContext;
    if (context == null || !context.mounted) return;
    final savedVersions = await FileService.saveHitMakerVersions(context, job);
    if (savedVersions || !context.mounted) return;
    await FileService.downloadFromUrl(
      context,
      url,
      suggestedFileName:
          job.isAudioOutput ? savedAudioFileBaseName(job) : job.jobId,
      jobId: job.jobId,
      maxRetries: 2,
      outputType: job.outputType,
      showPreview: false,
      documentsFallback: true,
    );
  }
}

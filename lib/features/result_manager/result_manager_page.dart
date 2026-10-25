// lib/features/result_manager/result_manager_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shimmer/shimmer.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/model_display_name.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/motion.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/ad_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/polling_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/thumbnail_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/app_menu_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/audio_result_player.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/exit_app_dialog.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_job_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_storyboard_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/before_after_preview.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/job_next_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool isResultManagerOpen = false;

/// =============================================================================
/// MODEL NAME HELPER
/// =============================================================================
/// Load catalogue names saved with the tool config.
Future<void> _loadModelNameCache() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString('cached_tool_config_v3');
    if (configStr == null || configStr.isEmpty) return;

    final config = jsonDecode(configStr) as Map<String, dynamic>;
    if (config['capabilities'] is! List) return;
    indexModelDisplayNames(config);
  } catch (e) {
    debugPrint('⚠️ Failed to load model name cache: $e');
  }
}

/// The name stored on the job, or the one kept in its launch snapshot.
String? modelNameForJob(JobModel job) {
  return friendlyModelName(job.model) ??
      friendlyModelName(job.settingsSnapshot?['modelId']?.toString());
}

String _jobTitle(JobModel job) {
  final raw = job.title.trim();
  return raw.isEmpty ? 'Untitled' : raw;
}

/// =============================================================================
/// SHARED ANIMATION CONTROLLER FOR PROCESSING JOBS
/// =============================================================================
/// Single controller shared across all processing job previews to minimize
/// performance overhead when many jobs are processing simultaneously
class _ProcessingAnimationController {
  static final _ProcessingAnimationController _instance =
      _ProcessingAnimationController._();
  static _ProcessingAnimationController get instance => _instance;
  _ProcessingAnimationController._();

  AnimationController? _controller;
  int _activeListeners = 0;

  AnimationController? get controller => _controller;

  void initialize(TickerProvider vsync) {
    if (_controller != null) return;
    _controller = AnimationController(
      vsync: vsync,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  void addListener() {
    _activeListeners++;
  }

  void removeListener() {
    _activeListeners--;
    if (_activeListeners <= 0 && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  void dispose() {
    _controller?.dispose();
    _controller = null;
    _activeListeners = 0;
  }
}

/// Tracks downloads for rewarded ad rate limiting.
/// Heavy tier: ad before every download. Light tier: every 5th download.
Future<bool> _shouldShowDownloadAd() async {
  if (kDebugMode) return false;

  if (!shouldShowAds()) return false;

  final tier = adExperienceNotifier.value;
  if (tier == 'heavy') {
    return true;
  }
  if (tier != 'light') {
    return false;
  }

  final prefs = await SharedPreferences.getInstance();
  var downloadCount = prefs.getInt('download_count_for_ad') ?? 0;
  downloadCount++;
  await prefs.setInt('download_count_for_ad', downloadCount);
  return downloadCount % 5 == 0;
}

/// Show rewarded ad for download rate limiting
/// Returns true if ad was shown and completed, false if skipped/failed
Future<bool> _showDownloadRewardedAd(BuildContext context) async {
  final adService = AdService();

  // Load ad if not ready
  if (!adService.isAdReadyNotifier.value) {
    await adService.loadRewardedAd();
    // Wait for ad to load (max 5 seconds)
    for (int i = 0; i < 10; i++) {
      if (adService.isAdReadyNotifier.value) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // If ad still not ready, let the download proceed
  if (!adService.isAdReadyNotifier.value) {
    debugPrint('⚠️ Ad not available for download gate - proceeding');
    return false;
  }

  // Show the ad
  final completed = await adService.showAdForFeatureGate();
  return completed;
}

class ResultManagerPage extends StatefulWidget {
  final String? initialJobId;

  /// True when this page is the bottom-nav tab, so a pushed copy can still open.
  final bool asTab;

  const ResultManagerPage({super.key, this.initialJobId, this.asTab = false});

  @override
  State<ResultManagerPage> createState() => _ResultManagerPageState();
}

class _ResultManagerPageState extends State<ResultManagerPage> {
  // Multi-select state
  bool _isSelectionMode = false;
  final Set<String> _selectedJobIds = <String>{};

  // Search and filter state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'date'; // 'date', 'status', 'title'
  bool _sortAscending = false; // newest first by default

  final GlobalKey _initialJobKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!widget.asTab) isResultManagerOpen = true;
    if (widget.initialJobId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _initialJobKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 300),
            alignment: 0.1,
          );
        }
      });
    }
    _refreshJobs();
    _markAllCompletedAsSeen();
    _prefetchDownloadUrls(); // Pre-fetch URLs in background
    _loadModelNameCache().then((_) {
      if (mounted) setState(() {});
    });

    SharedPreferences.getInstance().then((prefs) async {
      await prefs.reload();
    });

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  /// Pre-fetch download URLs for completed jobs in background
  /// This reduces network calls when users click download buttons
  Future<void> _prefetchDownloadUrls() async {
    try {
      final jobs = jobListNotifier.value;
      final completedJobs = jobs
          .where((j) => j.status == 'completed' && !j.isSavedLocally)
          .take(10) // Limit to first 10 unsaved jobs
          .toList();

      if (completedJobs.isEmpty) return;

      debugPrint(
          '🔄 Pre-fetching URLs for ${completedJobs.length} completed jobs...');

      // Fetch URLs in parallel with a small delay between each
      for (final job in completedJobs) {
        if (await wasJobDeleted(job.jobId)) continue;
        // Don't block - fire and forget
        PollingService.getValidDownloadUrl(job.jobId).then((url) {
          if (url != null && url.isNotEmpty && url != job.downloadUrl) {
            job.downloadUrl = url;
            addOrUpdateJob(job);
          }
        }).catchError((_) {});

        // Small delay to avoid overwhelming the server
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      debugPrint('⚠️ Error pre-fetching URLs: $e');
    }
  }

  Future<void> _markAllCompletedAsSeen() async {
    try {
      final completedJobs = jobListNotifier.value
          .where((j) => j.status == 'completed')
          .map((j) => j.jobId)
          .toList();

      if (completedJobs.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      final seenList = prefs.getStringList('seen_completed_job_ids') ?? [];
      final seenSet = seenList.toSet();
      seenSet.addAll(completedJobs);
      await prefs.setStringList('seen_completed_job_ids', seenSet.toList());
    } catch (e) {
      debugPrint('⚠️ Failed to mark jobs as seen: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (!widget.asTab) isResultManagerOpen = false;
    super.dispose();
  }

  Future<void> _refreshJobs() async {
    try {
      // Get SharedPreferences instance once at the start (used throughout)
      final prefs = await SharedPreferences.getInstance();

      // 📁 FIRST: Apply any pending FCM updates from file
      // This is the most reliable cross-isolate sync mechanism
      // CRITICAL: Background FCM handler writes to this file, and SharedPreferences
      // might not sync across isolates on some platforms!
      final appliedFromFile = await applyPendingFcmUpdatesFromFile();
      final refreshIds = takeFcmJobsToRefresh();
      for (final id in refreshIds) {
        unawaited(PollingService.instance.refreshJob(id));
      }
      if (appliedFromFile) {
        debugPrint("✅ [ResultManager] Applied FCM updates from file");
        final jobs = jobListNotifier.value;
        final completed = jobs.where((j) => j.status == 'completed').length;
        final processing = jobs.where((j) => j.status == 'processing').length;
        debugPrint(
            "📊 Status after FCM file: $completed completed, $processing processing");

        // CRITICAL: After applying file updates, we need to ensure SharedPreferences
        // is reloaded to get the latest data (file updates were saved to SharedPreferences).
        // But we should merge, not overwrite, to preserve any local data like localFilePath.
        await prefs.reload(); // Reload to get the updates we just saved
        await Future.delayed(
            const Duration(milliseconds: 100)); // Give it time to flush
        await prefs.reload();

        // Now merge SharedPreferences data with current notifier to preserve local fields
        final jsonStr = prefs.getString('jobs');
        if (jsonStr != null) {
          try {
            final decoded = jsonDecode(jsonStr);
            if (decoded is List) {
              final prefsJobs = decoded
                  .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
                  .toList();

              // Merge: use SharedPreferences data (which has file updates) but preserve
              // any local fields from current notifier that might not be in SharedPreferences
              final currentJobs = jobListNotifier.value;
              final mergedJobs = <JobModel>[];

              // Safety check: if SharedPreferences has fewer jobs than current notifier,
              // something went wrong - keep current notifier data
              if (prefsJobs.length < currentJobs.length) {
                debugPrint(
                    "⚠️ [ResultManager] SharedPreferences has ${prefsJobs.length} jobs but notifier has ${currentJobs.length} - keeping notifier data");
                for (final currentJob in currentJobs) {
                  final prefsJob = prefsJobs.firstWhere(
                    (j) => j.jobId == currentJob.jobId,
                    orElse: () => currentJob,
                  );

                  // Use prefsJob if it has newer status, otherwise keep currentJob
                  final usePrefs = prefsJob.status != currentJob.status ||
                      (prefsJob.downloadUrl != null &&
                          prefsJob.downloadUrl != currentJob.downloadUrl);
                  final sourceJob = usePrefs ? prefsJob : currentJob;

                  final mergedJob = sourceJob.mergePreservingLaunch(currentJob);
                  mergedJobs.add(mergedJob);
                }
              } else {
                // Normal merge: SharedPreferences has same or more jobs
                for (final prefsJob in prefsJobs) {
                  final currentJob = currentJobs.firstWhere(
                    (j) => j.jobId == prefsJob.jobId,
                    orElse: () => prefsJob,
                  );

                  // Use prefsJob (has latest status/url) but preserve localFilePath if it exists
                  final mergedJob = prefsJob.mergePreservingLaunch(currentJob);
                  mergedJobs.add(mergedJob);
                }
              }

              jobListNotifier.value = await withoutDeletedJobs(mergedJobs);
              debugPrint(
                  "✅ [ResultManager] Merged ${mergedJobs.length} jobs from file + SharedPreferences");

              // Continue to check for stuck jobs below
            }
          } catch (e) {
            debugPrint(
                "⚠️ [ResultManager] Failed to merge SharedPreferences data: $e");
            // Continue with current notifier value (from file updates)
          }
        }
      } else {
        // No file updates - load from SharedPreferences normally
        // 🔄 Multiple reload attempts to ensure cross-isolate sync with FCM background handler
        await prefs.reload();
        await Future.delayed(const Duration(milliseconds: 50));
        await prefs.reload();

        // Check for pending FCM updates flag (backup mechanism)
        final hasUpdate = prefs.getBool('has_fcm_update') ?? false;
        if (hasUpdate) {
          debugPrint(
              "📦 [ResultManager] Found FCM update flag — forcing reload");
          await prefs.remove('has_fcm_update');
          await prefs.reload();
        }

        // ✅ PRIMARY: Load jobs from SharedPreferences (contains FCM updates)
        // FCM notifications already have status and download_url - trust this data!
        final localJson = prefs.getString('jobs');
        if (localJson != null) {
          final decoded = jsonDecode(localJson);
          if (decoded is List) {
            jobListNotifier.value = await withoutDeletedJobs(
              decoded
                  .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
                  .toList(),
            );

            // Log status summary
            final jobs = jobListNotifier.value;
            final completed = jobs.where((j) => j.status == 'completed').length;
            final processing =
                jobs.where((j) => j.status == 'processing').length;
            debugPrint(
                "📊 Loaded ${jobs.length} jobs: $completed completed, $processing processing");
          }
        }
      }

      // 🔄 BACKUP: Only poll server for "stuck" processing jobs (>5 min old)
      // Reduced from 10 min - if FCM didn't deliver in 5 min, it's unlikely to
      // This is a safety net in case FCM failed to deliver
      final stuckJobs = jobListNotifier.value
          .where((j) => j.status == 'processing')
          .where((j) {
        final age = DateTime.now().difference(j.createdAt).inMinutes;
        return age >= 5; // Changed from 10 to 5 minutes
      }).toList();

      if (stuckJobs.isNotEmpty) {
        debugPrint(
            "🔄 Backup: Checking ${stuckJobs.length} stuck processing jobs from server...");
        await PollingService.instance.refreshProcessingJobs(forceRefresh: true);

        // Reload after server update
        await prefs.reload();
        final updatedJson = prefs.getString('jobs');
        if (updatedJson != null) {
          final decoded = jsonDecode(updatedJson);
          if (decoded is List) {
            jobListNotifier.value = await withoutDeletedJobs(
              decoded
                  .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
                  .toList(),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ _refreshJobs failed: $e");
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedJobIds.clear();
      }
    });
  }

  void _toggleJobSelection(String jobId) {
    setState(() {
      if (_selectedJobIds.contains(jobId)) {
        _selectedJobIds.remove(jobId);
      } else {
        _selectedJobIds.add(jobId);
      }
      if (_selectedJobIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAll() {
    setState(() {
      final jobs = _getFilteredAndSortedJobs();
      _selectedJobIds.clear();
      _selectedJobIds.addAll(jobs.map((j) => j.jobId));
      if (_selectedJobIds.isNotEmpty) {
        _isSelectionMode = true;
      }
    });
  }

  List<JobModel> _getFilteredAndSortedJobs() {
    var jobs = List<JobModel>.from(jobListNotifier.value);

    // Filter by search query
    if (_searchQuery.isNotEmpty) {
      jobs = jobs.where((job) {
        final modelName = modelNameForJob(job)?.toLowerCase() ?? '';
        return _jobTitle(job).toLowerCase().contains(_searchQuery) ||
            modelName.contains(_searchQuery) ||
            job.title.toLowerCase().contains(_searchQuery) ||
            job.jobId.toLowerCase().contains(_searchQuery) ||
            job.model.toLowerCase().contains(_searchQuery) ||
            job.status.toLowerCase().contains(_searchQuery);
      }).toList();
    }

    // Sort
    jobs.sort((a, b) {
      int comparison = 0;
      switch (_sortBy) {
        case 'date':
          comparison = a.createdAt.compareTo(b.createdAt);
          break;
        case 'status':
          comparison = a.status.compareTo(b.status);
          break;
        case 'title':
          comparison = a.title.compareTo(b.title);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });

    return jobs;
  }

  Future<void> _batchDelete() async {
    if (_selectedJobIds.isEmpty) return;

    final cs = Theme.of(context).colorScheme;
    bool deleteGalleryFiles = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Text(
              'Delete ${_selectedJobIds.length} job(s)?',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This will remove the selected creations from your list and delete related files.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: deleteGalleryFiles,
                      onChanged: (val) =>
                          setState(() => deleteGalleryFiles = val ?? false),
                      activeColor: cs.error,
                      side: BorderSide(color: cs.onSurfaceVariant),
                    ),
                    Flexible(
                      child: Text(
                        'Also delete saved result files from gallery',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text(
                  'Cancel',
                  style: TextStyle(color: cs.primary),
                ),
                onPressed: () => Navigator.pop(context, false),
              ),
              TextButton(
                child: Text(
                  'Delete',
                  style: TextStyle(color: cs.error),
                ),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      final selectedCount = _selectedJobIds.length;
      final selectedIdsCopy = Set<String>.from(_selectedJobIds);
      final jobs = jobListNotifier.value;
      final jobsToDelete = jobs
          .where((job) => selectedIdsCopy.contains(job.jobId))
          .toList();

      await markJobsAsDeleted(selectedIdsCopy.toList());
      jobListNotifier.value =
          jobs.where((j) => !selectedIdsCopy.contains(j.jobId)).toList();
      await saveJobsToPrefs();

      for (final job in jobsToDelete) {
        await FileService.deleteJobFiles(job,
            deleteGalleryFile: deleteGalleryFiles);
      }

      setState(() {
        _selectedJobIds.clear();
        _isSelectionMode = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $selectedCount job(s)'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildCloudStorageInfoBanner(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: BacklitGlass(
        role: BacklitGlassRole.chip,
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: cs.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                'Inputs and results are deleted from the server after 14 days.',
                maxLines: 1,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Future<bool> _handleSystemBack() async {
    final leave = await showDialog<bool>(
          context: context,
          builder: (_) => const ConfirmExitAppDialog(),
        ) ??
        false;
    if (leave) SystemNavigator.pop();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final page = PopScope(
      canPop: !widget.asTab,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !widget.asTab) return;
        if (selectedIndexNotifier.value != AppTabs.creations) return;
        _handleSystemBack();
      },
      child: Scaffold(
      backgroundColor: backlitScaffoldColor(context, cs),
      appBar: AppBar(
        leading: widget.asTab ? const AppMenuButton() : null,
        automaticallyImplyLeading: !widget.asTab,
        title: _isSelectionMode
            ? Text(
                '${_selectedJobIds.length} selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              )
            : widget.asTab
                ? const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
                  )
                : Text(
                    'Creations',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
        backgroundColor: backlitScaffoldColor(context, cs),
        elevation: 0,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: Icon(Icons.select_all, color: cs.primary),
                  tooltip: 'Select All',
                  onPressed: _selectAll,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  tooltip: 'Delete Selected',
                  onPressed: _selectedJobIds.isEmpty ? null : _batchDelete,
                ),
                IconButton(
                  icon: Icon(Icons.close, color: cs.onSurface),
                  tooltip: 'Cancel',
                  onPressed: _toggleSelectionMode,
                ),
              ]
            : [
                PopupMenuButton<String>(
                  icon: Icon(Icons.sort, color: cs.onSurface),
                  onSelected: (value) {
                    setState(() {
                      if (value == 'toggle_sort') {
                        _sortAscending = !_sortAscending;
                      } else {
                        _sortBy = value;
                      }
                    });
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'date',
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 20,
                            color: _sortBy == 'date' ? cs.primary : null,
                          ),
                          const SizedBox(width: 8),
                          const Text('Sort by Date'),
                          if (_sortBy == 'date')
                            Icon(
                              _sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 16,
                              color: cs.primary,
                            ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'status',
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 20,
                            color: _sortBy == 'status' ? cs.primary : null,
                          ),
                          const SizedBox(width: 8),
                          const Text('Sort by Status'),
                          if (_sortBy == 'status')
                            Icon(
                              _sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 16,
                              color: cs.primary,
                            ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'title',
                      child: Row(
                        children: [
                          Icon(
                            Icons.title,
                            size: 20,
                            color: _sortBy == 'title' ? cs.primary : null,
                          ),
                          const SizedBox(width: 8),
                          const Text('Sort by Title'),
                          if (_sortBy == 'title')
                            Icon(
                              _sortAscending
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: 16,
                              color: cs.primary,
                            ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'toggle_sort',
                      child: Row(
                        children: [
                          const Icon(Icons.swap_vert, size: 20),
                          const SizedBox(width: 8),
                          Text(
                              _sortAscending ? 'Newest First' : 'Oldest First'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          if (widget.asTab && !_isSelectionMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Creations',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: cs.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
          // 🔔 Cloud Storage Info Banner
          _buildCloudStorageInfoBanner(cs),

          // Search bar - uses consistent AppStyles
          Padding(
            padding: const EdgeInsets.all(AppStyles.spacing12),
            child: BacklitGlass(
              role: BacklitGlassRole.chip,
              borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              child: TextField(
                controller: _searchController,
                decoration: AppStyles.inputDecoration(
                  cs,
                  hintText: 'Search creations...',
                  prefixIcon: Icons.search,
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear,
                              color: cs.onSurfaceVariant, size: 20),
                          onPressed: () {
                            _searchController.clear();
                          },
                        )
                      : null,
                ).copyWith(
                  filled: true,
                  fillColor: Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                    borderSide: BorderSide(
                      color: cs.primary.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Job list
          Expanded(
            child: RefreshIndicator(
              color: cs.primary,
              backgroundColor: cs.surfaceContainer,
              onRefresh: _refreshJobs,
              child: ValueListenableBuilder<List<JobModel>>(
                valueListenable: jobListNotifier,
                builder: (_, jobs, __) {
                  final filteredJobs = _getFilteredAndSortedJobs();

                  if (filteredJobs.isEmpty) {
                    final emptyLabel = _searchQuery.isNotEmpty
                        ? 'No creations found matching "$_searchQuery"'
                        : 'No creations yet.';
                    return Center(
                      child: OnceFadeRise(
                        token: _searchQuery.isNotEmpty
                            ? 'creations-empty-search'
                            : 'creations-empty',
                        child: Text(
                          emptyLabel,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: filteredJobs.length,
                    itemBuilder: (_, i) {
                      final job = filteredJobs[i];
                      final batchId = job.batchId;
                      final batchCount = batchId == null
                          ? 0
                          : filteredJobs
                              .where((j) =>
                                  j.batchId == batchId &&
                                  j.status == 'completed')
                              .length;
                      final isBatchStart = batchId != null &&
                          batchCount > 1 &&
                          filteredJobs
                                  .indexWhere((j) => j.batchId == batchId) ==
                              i;
                      final card = JobCard(
                        key: job.jobId == widget.initialJobId
                            ? _initialJobKey
                            : ValueKey(job.jobId),
                        job: job,
                        isSelectionMode: _isSelectionMode,
                        isSelected:
                            _selectedJobIds.contains(filteredJobs[i].jobId),
                        onLongPress: () {
                          if (!_isSelectionMode) {
                            _toggleSelectionMode();
                          }
                          _toggleJobSelection(filteredJobs[i].jobId);
                        },
                        onTap: _isSelectionMode
                            ? () => _toggleJobSelection(filteredJobs[i].jobId)
                            : () {
                                final job = filteredJobs[i];
                                if (job.outputType == 'studio_video' &&
                                    job.status == 'reviewing') {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => StudioStoryboardPage(
                                          jobId: job.jobId),
                                    ),
                                  );
                                } else if (job.outputType == 'studio_video') {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => StudioJobPage(
                                        jobId: job.jobId,
                                        reviewMode: true,
                                      ),
                                    ),
                                  );
                                }
                              },
                      );
                      final tile = isBatchStart
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                                  child: Text(
                                    '$batchCount from one run',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                card,
                              ],
                            )
                          : card;
                      if (i >= 6) return tile;
                      return OnceFadeRise(
                        key: ValueKey(job.jobId),
                        token: job.jobId,
                        order: i,
                        child: tile,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
    );

    if (widget.asTab) return page;
    return Stack(
      children: [
        const Positioned.fill(child: BacklitWash()),
        page,
      ],
    );
  }
}

/// Owns the text field so it is released only after the dialog route unmounts.
class _RenameJobDialog extends StatefulWidget {
  const _RenameJobDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameJobDialog> createState() => _RenameJobDialogState();
}

class _RenameJobDialogState extends State<_RenameJobDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close([String? value]) {
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => _close(_controller.text),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => _close(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class JobCard extends StatefulWidget {
  final JobModel job;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;

  const JobCard({
    super.key,
    required this.job,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onTap,
  });

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  static bool _openingPreview = false;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;
  bool _isPromptExpanded = false; // For expandable enhanced prompt section

  bool get _isDownloaded =>
      widget.job.localFilePath != null &&
      File(widget.job.localFilePath!).existsSync();

  bool _jobHasAudio(JobModel job, String path) {
    if (job.isAudioOutput) return true;
    final ext = path.split('.').last.toLowerCase();
    return ext == 'mp3' ||
        ext == 'wav' ||
        ext == 'm4a' ||
        ext == 'aac' ||
        ext == 'ogg' ||
        ext == 'flac';
  }

  Future<void> _openPreview(BuildContext context) async {
    if (_openingPreview) return;
    _openingPreview = true;

    try {
      String? path = widget.job.localFilePath;
      final liveTracks = audioTracksFromJob(widget.job);
      if (liveTracks.isNotEmpty &&
          (path == null || !File(path).existsSync())) {
        if (context.mounted) {
          await FileService.openAudioTracks(context, tracks: liveTracks);
        }
        return;
      }

      // If file doesn't exist locally, trigger download first (same as download button)
      if (path == null || !File(path).existsSync()) {
        // If already downloading, wait for it to complete
        if (_isDownloading) {
          // Wait for download to complete (check every 200ms, max 2 minutes)
          int waitCount = 0;
          while (_isDownloading && waitCount < 600) {
            await Future.delayed(const Duration(milliseconds: 200));
            waitCount++;
          }
        } else {
          // Start the download
          await _download(context);
        }

        // After download, check if we now have the file
        path = widget.job.localFilePath;
        if (path == null || !File(path).existsSync()) {
          // Download failed or was cancelled - don't show error (download already did)
          return;
        }
      }

      // File exists locally, open preview with swipe navigation
      if (context.mounted) {
        // Get all downloaded file paths for swipe navigation
        final allJobs = jobListNotifier.value;
        final downloadedPaths = <String>[];
        int currentIndex = 0;

        for (final job in allJobs) {
          if (job.localFilePath != null &&
              File(job.localFilePath!).existsSync()) {
            if (job.jobId == widget.job.jobId) {
              currentIndex = downloadedPaths.length;
            }
            downloadedPaths.add(job.localFilePath!);
          }
        }

        final source = widget.job.inputImagePath;
        if (widget.job.isImageOutput &&
            source != null &&
            source != path &&
            File(source).existsSync() &&
            File(path).existsSync()) {
          openBeforeAfterPreview(
            context,
            resultFile: File(path),
            originalFile: File(source),
          );
        } else if (_jobHasAudio(widget.job, path)) {
          final tracks = liveTracks.isNotEmpty
              ? liveTracks
              : <AudioTrackDetails>[AudioTrackDetails.fromJob(widget.job)];
          await FileService.openAudioTracks(context, tracks: tracks);
        } else {
          FileService.openLocalPreview(
            context,
            path,
            allPaths: downloadedPaths.length > 1 ? downloadedPaths : null,
            currentIndex: currentIndex,
          );
        }
      }
    } finally {
      _openingPreview = false;
    }
  }

  Future<void> _download(BuildContext context, {bool fromCloud = false}) async {
    if (_isDownloading) return;

    // A file already on the phone can be copied into the gallery.
    // Download again skips that and fetches a fresh cloud link.
    if (!fromCloud &&
        widget.job.localFilePath != null &&
        File(widget.job.localFilePath!).existsSync()) {
      final success = await FileService.saveExistingToGallery(
        context,
        widget.job.localFilePath!,
      );
      if (success) return;
    }

    // Check queue status before starting
    if (FileService.pendingDownloads >= 8) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Too many downloads queued. Please wait.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Check if rewarded ad should be shown (every 5th download, unless ad-free)
    if (await _shouldShowDownloadAd()) {
      debugPrint('📺 Showing rewarded ad for 5th download');

      // Show loading indicator while ad loads
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Loading ad...'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      // Show the ad - this is just a rate limiter, doesn't block download
      await _showDownloadRewardedAd(context);
      debugPrint('📺 Ad completed or skipped - proceeding with download');
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    String? savedPath;

    // Try downloading with URL refresh on failure (handles 1-hour URL expiry)
    for (int attempt = 1; attempt <= 2; attempt++) {
      String? downloadUrl;

      try {
        // First, check if job already has a valid cached URL in memory (from FCM notification)
        if (attempt == 1 &&
            widget.job.downloadUrl != null &&
            widget.job.downloadUrl!.isNotEmpty) {
          // Quick check if URL looks valid (has exp parameter and not too old)
          if (PollingService.isSignedUrlValid(widget.job.downloadUrl,
              minRemainingSeconds: 60)) {
            downloadUrl = widget.job.downloadUrl;
            debugPrint(
                '✅ Using job\'s cached signed URL directly (from FCM) - NO API call');
          } else {
            debugPrint('⏰ Job URL expired or invalid, will fetch fresh one');
          }
        }

        // If no valid URL from job, try SharedPreferences cache
        if (downloadUrl == null || downloadUrl.isEmpty) {
          if (attempt == 1) {
            debugPrint('🔍 Checking SharedPreferences cache for URL...');
            downloadUrl =
                await PollingService.getValidDownloadUrl(widget.job.jobId);
            if (downloadUrl != null) {
              debugPrint('✅ Found valid URL in SharedPreferences cache');
            }
          } else {
            // Force refresh on second attempt
            debugPrint('🔄 Force refreshing download URL from server...');
            downloadUrl =
                await PollingService.refreshDownloadUrl(widget.job.jobId);
          }
        }

        // Update job with new URL if we got one
        if (downloadUrl != null &&
            downloadUrl.isNotEmpty &&
            downloadUrl != widget.job.downloadUrl) {
          widget.job.downloadUrl = downloadUrl;
          await addOrUpdateJob(widget.job);
        }
      } catch (e) {
        debugPrint('⚠️ Failed to get download URL (attempt $attempt): $e');
      }

      if (downloadUrl == null || downloadUrl.isEmpty) {
        if (attempt == 2) {
          // Both attempts failed to get URL
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _downloadProgress = 0.0;
            });
            // Don't spam snackbars - FileService handles this
          }
          return;
        }
        continue; // Try again with force refresh
      }

      // Reset progress for each attempt
      if (mounted) {
        setState(() => _downloadProgress = 0.0);
      }

      // Attempt download
      savedPath = await FileService.queueDownload(
        context,
        downloadUrl,
        suggestedFileName: widget.job.jobId,
        maxRetries: 2,
        outputType: widget.job.outputType,
        showPreview: !_isMusicDownload,
        onProgress: (progress) {
          if (mounted) {
            setState(() => _downloadProgress = progress);
          }
        },
      );

      // If download succeeded, break out of retry loop
      if (savedPath != null) {
        break;
      }

      // Download failed - if this was first attempt, force refresh URL and retry
      if (attempt == 1) {
        debugPrint('⚠️ Download failed, will retry with fresh URL...');
        // Clear cached URL so next attempt fetches fresh one
        widget.job.downloadUrl = null;
        await addOrUpdateJob(widget.job);
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }

    if (savedPath != null) {
      final file = File(savedPath);
      for (int i = 0; i < 5; i++) {
        if (file.existsSync() && file.lengthSync() > 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      widget.job.localFilePath = savedPath;

      try {
        final lp = savedPath.toLowerCase();
        if (!lp.endsWith('.mp4') &&
            !lp.endsWith('.mov') &&
            !lp.endsWith('.txt') &&
            !lp.endsWith('.json') &&
            !lp.endsWith('.text')) {
          await precacheImage(FileImage(file), context);
        }
      } catch (_) {}

      await addOrUpdateJob(widget.job);
      await saveJobsToPrefs();

      // Force ValueListenableBuilder rebuild to update thumbnail
      jobListNotifier.value = List<JobModel>.from(jobListNotifier.value);
    }
    // Note: Error snackbars are handled by FileService with debouncing

    if (mounted) {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final job = widget.job;

    // Clear stale localFilePath if file was deleted from device
    if (job.localFilePath != null &&
        job.localFilePath!.isNotEmpty &&
        !File(job.localFilePath!).existsSync()) {
      // Fire-and-forget cleanup - clear stale path reference
      Future.microtask(() async {
        if (mounted) {
          job.localFilePath = null;
          await addOrUpdateJob(job);
          await saveJobsToPrefs();
        }
      });
    }

    // Kie results are saved on the phone at 17 minutes, so they stay visible
    // after the cloud link times out.
    final isExpired = job.showsCloudExpiry;
    final isSaved = job.isSavedLocally;
    final playMusic = _canPlayMusic;

    return InkWell(
      onTap: widget.isSelectionMode
          ? widget.onTap
          : () {
              if (job.outputType == 'studio_video') {
                widget.onTap?.call();
                return;
              }
              if (_canPlayMusic) {
                _openPreview(context);
              } else if (job.status == 'completed' && !isExpired && isSaved) {
                _openPreview(context);
              }
            },
      onLongPress: widget.onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        // Dim expired jobs that aren't saved locally
        opacity: isExpired ? 0.6 : 1.0,
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: widget.isSelected
              ? cs.primaryContainer.withValues(alpha: 0.3)
              : isExpired
                  ? cs.surfaceContainerHigh.withValues(alpha: 0.5)
                  : cs.surfaceContainerHigh,
          elevation: widget.isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: widget.isSelected
                ? BorderSide(color: cs.primary, width: 2)
                : isExpired
                    ? BorderSide(color: cs.outline.withValues(alpha: 0.3), width: 1)
                    : BorderSide.none,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                minVerticalPadding: 0,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),

                // ✅ Thumbnail (always visible, including in selection mode)
                leading: _buildThumbnail(cs),

                title: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _renameJob,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _jobTitle(job),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.15,
                            color: isExpired
                                ? cs.onSurface.withValues(alpha: 0.7)
                                : cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),

                // ✅ Status animated
                subtitle: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  layoutBuilder: (currentChild, previousChildren) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: currentChild,
                    );
                  },
                  child: widget.isSelectionMode
                      ? Column(
                          key: ValueKey('select-${job.jobId}'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (modelNameForJob(job) case final modelName?)
                              Text(
                                modelName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            _buildStatus(cs),
                          ],
                        )
                      : _buildStatus(cs),
                ),

                // ✅ Trailing: Checkbox in selection mode, or action buttons in normal mode
                trailing: widget.isSelectionMode
                    ? Checkbox(
                        value: widget.isSelected,
                        onChanged: (_) => widget.onTap?.call(),
                        activeColor: cs.primary,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (job.status == 'completed' &&
                              (job.outputType == 'video' ||
                                  job.outputType == 'studio_video'))
                            IconButton(
                              icon: Icon(Icons.movie_creation_outlined,
                                  color: cs.primary),
                              tooltip: 'Use this clip as scene 1 in Studio',
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StudioPage(
                                      initialExploreJobId: job.jobId,
                                      initialSceneIndex: 1,
                                      initialLocalPath: job.localFilePath,
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (job.status == 'completed')
                            IconButton(
                              icon: _isDownloading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Icon(
                                      isExpired
                                          ? Icons.cloud_off_rounded
                                          : (playMusic || isSaved)
                                              ? (playMusic ||
                                                      job.isAudioOutput ||
                                                      job.isVideoOutput
                                                  ? Icons.play_arrow_rounded
                                                  : Icons.visibility_outlined)
                                              : Icons.download,
                                      color: isExpired ? cs.outline : cs.primary,
                                    ),
                              tooltip: isExpired
                                  ? 'Cloud result expired'
                                  : playMusic
                                      ? 'Play'
                                      : isSaved
                                          ? (job.isAudioOutput || job.isVideoOutput
                                              ? 'Play'
                                              : 'View')
                                          : 'Save to device',
                              onPressed: _isDownloading
                                  ? null
                                  : isExpired
                                      ? () => _showExpiredDialog(context, cs)
                                      : (playMusic || isSaved)
                                          ? () => _openPreview(context)
                                          : () => _download(context),
                            ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                color: cs.onSurfaceVariant),
                            tooltip: 'Delete Job',
                            onPressed: () => _confirmDelete(context, cs),
                          ),
                        ],
                      ),
              ),
              if (_versionCount > 0) _versionRow(cs),
              if (_musicResult?.anyStreaming == true)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Streaming now. The time updates when the full song is ready.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                ),

              // ✅ Small linear progress bar
              if (_isDownloading)
                Padding(
                  padding: const EdgeInsets.only(
                      left: 20, right: 20, bottom: 10, top: 0),
                  child: LinearProgressIndicator(
                    value: _downloadProgress,
                    minHeight: 4,
                    color: cs.primary,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                ),

              // ✅ Variations and Enhanced Prompt badges row
              if (job.hasMultipleVariations || job.promptEnhanced)
                Padding(
                  padding:
                      const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      // Variations badge
                      if (job.hasMultipleVariations)
                        _buildVariationsBadge(cs, job),
                      // Enhanced prompt indicator (tappable)
                      if (job.promptEnhanced && job.enhancedPrompt != null)
                        _buildEnhancedPromptBadge(cs),
                    ],
                  ),
                ),

              // ✅ Expandable Enhanced Prompt section
              if (_isPromptExpanded && job.enhancedPrompt != null)
                _buildEnhancedPromptSection(cs, job),
              if (job.expiryCue != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    job.expiryCue!,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          job.expiryCueUrgent ? cs.error : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              if (!widget.isSelectionMode) JobNextActions(job: job),
            ],
          ),
        ),
      ),
    );
  }

  /// Badge showing variations count
  Widget _buildVariationsBadge(ColorScheme cs, JobModel job) {
    final successCount = job.successfulVariationsCount;
    final failedCount = job.failedVariationsCount;
    final totalCount = job.variations;

    Color badgeColor = cs.primary;
    IconData badgeIcon = Icons.grid_view_rounded;
    String badgeText = '$successCount/$totalCount variations';

    if (failedCount > 0 && successCount > 0) {
      badgeColor = Colors.orange;
      badgeText = '$successCount/$totalCount ($failedCount failed)';
    } else if (failedCount == totalCount) {
      badgeColor = cs.error;
      badgeIcon = Icons.error_outline;
      badgeText = 'All variations failed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, size: 14, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            badgeText,
            style: TextStyle(
              color: badgeColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Badge for enhanced prompt (tappable to expand)
  Widget _buildEnhancedPromptBadge(ColorScheme cs) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isPromptExpanded = !_isPromptExpanded;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 14, color: Colors.purple),
            const SizedBox(width: 6),
            const Text(
              'AI Enhanced',
              style: TextStyle(
                color: Colors.purple,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _isPromptExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  /// Expandable section showing the enhanced prompt
  Widget _buildEnhancedPromptSection(ColorScheme cs, JobModel job) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.purple.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.purple.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, size: 16, color: Colors.purple),
                SizedBox(width: 8),
                Text(
                  'Enhanced Prompt',
                  style: TextStyle(
                    color: Colors.purple,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              job.enhancedPrompt!,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.85),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (job.originalPrompt != null &&
                job.originalPrompt!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Original prompt:',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      job.originalPrompt!,
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  MusicResult? get _musicResult {
    final raw = widget.job.music;
    if (raw == null) return null;
    return MusicResult.fromJson(raw);
  }

  String get _musicModelId {
    final snap = widget.job.settingsSnapshot?['modelId'];
    if (snap is String && snap.isNotEmpty) return snap;
    return widget.job.model;
  }

  String get _musicAction {
    final fromMusic = _musicResult?.action;
    if (fromMusic != null && fromMusic.isNotEmpty) return fromMusic;
    final snap = widget.job.settingsSnapshot?['musicAction'];
    if (snap is String && snap.isNotEmpty) return snap;
    return 'song';
  }

  bool get _isHitMaker => _musicModelId == kSunoV6ModelId;

  bool get _hitMakerSong =>
      _isHitMaker && (_musicAction == 'song' || _musicAction.isEmpty);

  bool get _isMusicDownload =>
      widget.job.isAudioOutput || _isHitMaker || widget.job.music != null;

  /// Play as soon as a real clip exists. A finished song does not need a save first.
  bool get _canPlayMusic {
    if (_musicResult?.hasPlayableTrack == true) return true;
    final musicJob = widget.job.isAudioOutput ||
        _isHitMaker ||
        widget.job.capabilityId == 'create_music';
    if (!musicJob || widget.job.status != 'completed') return false;
    final path = widget.job.localFilePath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) return true;
    final url = widget.job.downloadUrl;
    return url != null && url.isNotEmpty;
  }

  /// Both versions already have a finished file, so the cloud countdown is not
  /// the status of the song.
  bool get _musicFullyPlayable {
    final music = _musicResult;
    if (music == null || widget.job.status != 'completed') return false;
    if (music.anyStreaming || music.tracks.isEmpty) return false;
    return music.tracks.every((track) => track.fileUrl != null);
  }

  /// Stored versions. A finished HitMaker song with only the job file still
  /// shows that one version. The second slot is only a placeholder while it runs.
  List<MusicTrack> get _cardTracks {
    final tracks = _musicResult?.tracks ?? const <MusicTrack>[];
    if (tracks.isNotEmpty) return tracks;
    if (!_hitMakerSong || widget.job.status != 'completed') return tracks;
    final url = widget.job.downloadUrl;
    if (url == null || url.isEmpty) return tracks;
    return [
      MusicTrack(
        id: widget.job.jobId,
        title: widget.job.title.trim().isEmpty ? 'Version A' : widget.job.title,
        audioUrl: url,
        downloadUrl: url,
      ),
    ];
  }

  /// HitMaker songs return two versions. Keep the second slot while the job
  /// is still running, including the stretch where only the first has streamed.
  int get _versionCount {
    final tracks = _musicResult?.tracks.length ?? 0;
    if (_hitMakerSong) {
      final stillMaking =
          widget.job.status != 'completed' && widget.job.status != 'failed';
      // A running song keeps two slots. After it finishes, only real versions stay.
      if (stillMaking) return tracks < 2 ? 2 : tracks;
      if (tracks > 0) return tracks;
      return _cardTracks.length;
    }
    return tracks > 1 ? tracks : 0;
  }

  Future<void> _renameJob() async {
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _RenameJobDialog(initialName: widget.job.title),
    );
    final name = saved?.trim() ?? '';
    if (!mounted || name.isEmpty || name == widget.job.title) return;
    await addOrUpdateJob(widget.job.copyWith(title: name));
  }

  bool get _coverGenerationOn {
    if (!_isHitMaker) return false;
    if (_musicAction == 'sounds' ||
        _musicAction == 'video' ||
        _musicAction == 'stems') {
      return false;
    }
    if (widget.job.settingsSnapshot?['coverEnabled'] == true) return true;
    final music = _musicResult;
    if (music == null) return false;
    if (music.covers.isNotEmpty) return true;
    if (music.tracks.any((track) => (track.coverUrl ?? '').isNotEmpty)) {
      return true;
    }
    return music.easy && _hitMakerSong;
  }

  String? _coverUrlFor(MusicTrack? track, {bool allowShared = true}) {
    if (!_coverGenerationOn) return null;
    final fromTrack = track?.coverUrl;
    if (fromTrack != null && fromTrack.isNotEmpty) return fromTrack;
    if (!allowShared) return null;
    final covers = _musicResult?.covers ?? const <String>[];
    if (covers.isNotEmpty) return covers.first;
    return null;
  }

  String? get _localCoverPath {
    if (widget.job.settingsSnapshot?['coverEnabled'] != true) return null;
    final path = widget.job.settingsSnapshot?['coverPath'];
    if (path is! String || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  Future<void> _openMusicVersion(int index) async {
    final tracks = audioTracksFromJob(widget.job);
    if (tracks.isEmpty || !mounted) return;
    final phase = _musicResult?.phase ?? '';
    final playable = <int>[];
    final musicTracks = _cardTracks;
    for (var i = 0; i < tracks.length; i++) {
      if (i < musicTracks.length && musicTracks[i].urlDuring(phase) != null) {
        playable.add(i);
      }
    }
    if (playable.isEmpty) return;
    final start = playable.contains(index) ? index : playable.first;
    await FileService.openAudioTracks(
      context,
      tracks: tracks,
      initialIndex: start,
    );
  }

  Widget _versionRow(ColorScheme cs) {
    const names = ['A', 'B', 'C', 'D'];
    final tracks = _cardTracks;
    final count = _versionCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _versionChip(
                cs,
                i < tracks.length ? tracks[i] : null,
                i,
                names,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _versionState(MusicTrack? track) {
    final phase = _musicResult?.phase ?? '';
    if (track == null || track.urlDuring(phase) == null) return 'Generating..';
    if (track.streamsDuring(phase)) return 'Streaming';
    final length = track.knownDuration;
    if (length == null) return 'Ready';
    final minutes = length.inMinutes;
    final seconds = (length.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _versionChip(
    ColorScheme cs,
    MusicTrack? track,
    int index,
    List<String> names,
  ) {
    final phase = _musicResult?.phase ?? '';
    final label = index < names.length ? 'Version ${names[index]}' : 'Version ${index + 1}';
    final playable = track != null && track.urlDuring(phase) != null;
    final streaming = track?.streamsDuring(phase) == true;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: playable ? () => _openMusicVersion(index) : null,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: _coverArt(
                    _coverUrlFor(track, allowShared: track != null),
                    (track?.id ?? '${widget.job.jobId}-$index').hashCode,
                    cs,
                    filePath: index == 0 ? _localCoverPath : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _versionState(track),
                      style: TextStyle(
                        color: streaming ? cs.primary : cs.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _audioThumb(ColorScheme cs, MusicResult? music) {
    final tracks = music?.tracks ?? const <MusicTrack>[];
    final cover = _coverUrlFor(tracks.isEmpty ? null : tracks.first);
    final count = _versionCount;
    return Stack(
      fit: StackFit.expand,
      children: [
        _coverArt(
          cover,
          widget.job.jobId.hashCode,
          cs,
          filePath: _localCoverPath,
        ),
        if (count > 1)
          Positioned(
            right: 3,
            bottom: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _coverArt(String? url, int seed, ColorScheme cs, {String? filePath}) {
    final palette = CoverPalette.of(seed);
    final placeholder = Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.glow, palette.warm],
        ),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white.withValues(alpha: 0.92),
        size: 22,
      ),
    );
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: 58,
        height: 58,
        errorBuilder: (_, __, ___) => _coverFile(filePath) ?? placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return _coverFile(filePath) ?? placeholder;
        },
      );
    }
    return _coverFile(filePath) ?? placeholder;
  }

  Widget? _coverFile(String? filePath) {
    if (filePath == null || !File(filePath).existsSync()) return null;
    return Image.file(
      File(filePath),
      fit: BoxFit.cover,
      width: 58,
      height: 58,
      cacheWidth: 174,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  // ✅ Thumbnail widget - uses cached thumbnails for large images
  //
  // Three visual states:
  //  1. Processing       → blurred input + shimmer  (or animated gradient if no input)
  //  2. Completed, not   → blurred input, no shimmer (or static gradient icon)
  //     yet downloaded
  //  3. Downloaded        → actual result thumbnail  (CachedThumbnail / text icon)
  //
  // "Downloaded" = localFilePath != null AND File.existsSync() returns true.
  // If file is deleted from device, reverts to state 2 (blur/placeholder).
  Widget _buildThumbnail(ColorScheme cs) {
    final isDownloaded = widget.job.localFilePath != null &&
        widget.job.localFilePath!.isNotEmpty &&
        File(widget.job.localFilePath!).existsSync();
    final isProcessing = widget.job.status == 'processing';
    final jobCategory = _getJobCategory(widget.job);
    final music = _musicResult;

    // Check if file is a text file (text output type or text file extension)
    final isTextFile = jobCategory == 'text' ||
        (isDownloaded && _isTextFile(widget.job.localFilePath!));

    // Decide which content to render inside the thumbnail box
    Widget thumbnailContent;
    // Check if the saved file is a video by extension
    final isVideoFile = isDownloaded &&
        (widget.job.localFilePath!.toLowerCase().endsWith('.mp4') ||
            widget.job.localFilePath!.toLowerCase().endsWith('.mov') ||
            widget.job.localFilePath!.toLowerCase().endsWith('.avi'));

    if (widget.job.isAudioOutput ||
        (music != null &&
            !widget.job.isVideoOutput &&
            !widget.job.isImageOutput)) {
      thumbnailContent = _audioThumb(cs, music);
    } else if (isDownloaded && !isTextFile) {
      if (!isVideoFile) {
        // Image file on disk → use Flutter's native Image.file for reliable decoding
        thumbnailContent = Stack(
          key: ValueKey('thumb_${widget.job.localFilePath}'),
          fit: StackFit.expand,
          children: [
            Image.file(
              File(widget.job.localFilePath!),
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              cacheWidth:
                  174, // 58 * 3 for high-DPI; only set width to preserve aspect ratio
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('❌ Thumbnail image error: $error');
                return Container(
                  color: cs.surfaceContainerHigh,
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 20,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                );
              },
            ),
            // Subtle gradient overlay for depth
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.05),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      } else {
        // Video file on disk → generate thumbnail from video
        thumbnailContent = Stack(
          key: ValueKey('video_thumb_${widget.job.localFilePath}'),
          fit: StackFit.expand,
          children: [
            CachedThumbnail(
              key: ValueKey(widget.job.localFilePath),
              filePath: widget.job.localFilePath,
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              thumbnailSize: 150,
              errorWidget: Container(
                color: cs.surfaceContainerHighest,
                child: Center(
                  child: Icon(
                    Icons.videocam_rounded,
                    color: cs.primary.withValues(alpha: 0.7),
                    size: 24,
                  ),
                ),
              ),
            ),
            // Small video indicator badge
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 10,
                ),
              ),
            ),
          ],
        );
      }
    } else if (isDownloaded && isTextFile) {
      // Text file – show text icon
      thumbnailContent = Container(
        key: const ValueKey('text_placeholder'),
        color: cs.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.text_snippet_rounded,
            color: cs.primary.withValues(alpha: 0.7),
            size: 24,
          ),
        ),
      );
    } else {
      // Not downloaded yet → blur / processing placeholder
      thumbnailContent = _buildBlurOrPlaceholder(cs);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _AnimatedProcessingBorder(
        key: ValueKey(
            'thumb_${widget.job.localFilePath ?? 'pending_${widget.job.status}'}'),
        isProcessing: isProcessing,
        jobCategory: jobCategory,
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: isProcessing
                ? null
                : Border.all(
                    color: cs.outline.withValues(alpha: 0.15),
                    width: 1,
                  ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: thumbnailContent,
          ),
        ),
      ),
    );
  }

  /// Check if file is a text file by extension
  bool _isTextFile(String filePath) {
    final ext = filePath.toLowerCase().split('.').last;
    return ext == 'txt' || ext == 'json' || ext == 'text';
  }

  /// Get job category for visual styling
  String _getJobCategory(JobModel job) {
    final output = job.outputType.toLowerCase();
    final model = job.model.toLowerCase();

    if (output == 'video' ||
        output == 'studio_video' ||
        model.contains('video') ||
        model.contains('animate') ||
        model.contains('studio')) {
      return 'video';
    } else if (output == 'audio' ||
        model.contains('audio') ||
        model.contains('tts')) {
      return 'audio';
    } else if (output == 'text' || model.contains('ocr')) {
      return 'text';
    } else if (model.contains('upscale') || model.contains('enhance')) {
      return 'enhance';
    } else if (model.contains('remove') ||
        model.contains('erase') ||
        model.contains('inpaint')) {
      return 'edit';
    }
    return 'image';
  }

  Widget _buildBlurOrPlaceholder(ColorScheme cs) {
    final job = widget.job;
    final inputExists =
        job.inputImagePath != null && File(job.inputImagePath!).existsSync();
    final isProcessing = job.status == 'processing';

    // Determine job category for appropriate visual treatment
    final jobCategory = _getJobCategory(job);

    // For jobs WITH input image (image-to-image, image-to-video, etc.)
    // The blur stays until the result is downloaded (localFilePath exists).
    // _buildThumbnail already shows CachedThumbnail when localFilePath exists,
    // so this branch only runs for NOT-YET-DOWNLOADED jobs.
    // • Processing  → blur + shimmer/glow
    // • Completed (not downloaded) → blur only (no shimmer)
    if (inputExists) {
      return Stack(
        key: const ValueKey('blurred'),
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Image.file(
              File(job.inputImagePath!),
              width: 58,
              height: 58,
              fit: BoxFit.cover,
              cacheWidth: 116,
              cacheHeight: 116,
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.1)),
          if (isProcessing)
            Positioned.fill(
              child: Shimmer.fromColors(
                baseColor: cs.primary.withValues(alpha: 0.15),
                highlightColor: cs.primary.withValues(alpha: 0.45),
                child: Container(color: cs.primary.withValues(alpha: 0.10)),
              ),
            ),
        ],
      );
    }

    // For jobs WITHOUT input image (text-to-image, text-to-video, text-to-audio, etc.)
    // Show enhanced animated placeholder with vibrant blurred background
    return Stack(
      key: ValueKey('placeholder_$jobCategory'),
      fit: StackFit.expand,
      children: [
        // Enhanced animated gradient background
        _AnimatedGradientBackground(
          category: jobCategory,
          isProcessing: isProcessing,
        ),
        // Blur filter overlay for frosted glass effect
        if (isProcessing)
          ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                color: Colors.black.withValues(alpha: 0.15),
              ),
            ),
          ),
        // Shimmer overlay for processing state
        if (isProcessing)
          Positioned.fill(
            child: Shimmer.fromColors(
              baseColor: Colors.white.withValues(alpha: 0.08),
              highlightColor: Colors.white.withValues(alpha: 0.25),
              child: Container(color: Colors.transparent),
            ),
          ),
        // Centered icon with subtle shadow
        Center(
          child: Icon(
            _getPlaceholderIcon(job.outputType, job.model),
            color: isProcessing
                ? Colors.white.withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.7),
            size: 24,
            shadows: isProcessing
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
        ),
      ],
    );
  }

  /// Get appropriate icon based on output type and model
  IconData _getPlaceholderIcon(String outputType, String model) {
    final output = outputType.toLowerCase();
    final modelLower = model.toLowerCase();

    // Check output type first
    if (output == 'video' || output == 'studio_video') {
      return Icons.videocam_rounded;
    } else if (output == 'audio') {
      return Icons.audiotrack_rounded;
    } else if (output == 'text') {
      return Icons.text_snippet_rounded;
    }

    // Then check model name for more specific icons
    if (modelLower.contains('video') || modelLower.contains('animate')) {
      return Icons.videocam_rounded;
    } else if (modelLower.contains('audio') || modelLower.contains('tts')) {
      return Icons.audiotrack_rounded;
    } else if (modelLower.contains('ocr') || modelLower.contains('text')) {
      return Icons.text_snippet_rounded;
    } else if (modelLower.contains('upscale') ||
        modelLower.contains('enhance')) {
      return Icons.auto_awesome;
    } else if (modelLower.contains('remove') || modelLower.contains('erase')) {
      return Icons.auto_fix_high;
    } else if (modelLower.contains('inpaint') ||
        modelLower.contains('outpaint')) {
      return Icons.brush_rounded;
    } else if (modelLower.contains('bg') || modelLower.contains('background')) {
      return Icons.content_cut_rounded;
    }

    return Icons.image_rounded;
  }

  // ✅ Status widget (includes DOWNLOADING state)
  Widget _buildStatus(ColorScheme cs) {
    final job = widget.job;

    if (job.status == 'processing' ||
        job.status == 'provisioning' ||
        job.status == 'queued' ||
        job.status == 'running' ||
        job.status == 'stitching' ||
        job.status == 'uploading' ||
        job.status == 'reviewing') {
      String statusText = "${job.status.toUpperCase()}…";
      if (job.status == 'reviewing') statusText = 'REVIEW SCENES';
      final music = _musicResult;
      if (music != null) {
        statusText = music.anyStreaming
            ? 'STREAMING…'
            : music.statusLine.toUpperCase();
      }
      if (job.hasMultipleVariations && job.variationResults != null) {
        final completed = job.variationResults!
            .where((v) => v.status == 'completed' || v.status == 'failed')
            .length;
        statusText = "PROCESSING… ($completed/${job.variations})";
      }
      String? etaText;
      final eta = job.estimatedWaitSeconds;
      if (eta != null && eta > 0) {
        final m = (eta ~/ 60);
        final s = (eta % 60);
        etaText = m > 0 ? '~${m}m ${s}s' : '~${s}s';
      }

      String? queueText;
      final qp = job.queuePosition;
      if (qp != null && qp > 0) {
        queueText = 'Queue #$qp';
      }

      return Column(
        key: const ValueKey('processing'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            statusText,
            style: TextStyle(
              color: cs.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (etaText != null || queueText != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  if (queueText != null) queueText,
                  if (etaText != null) 'ETA $etaText'
                ].join(' • '),
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ),
        ],
      );
    }

    if (_isDownloading) {
      return Row(
        key: const ValueKey('downloading'),
        children: [
          Text(
            "DOWNLOADING…",
            style: TextStyle(
              color: cs.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    final isFailed = job.status == 'failed';
    final isDownloaded = _isDownloaded;
    final isExpired = job.showsCloudExpiry;
    final isSaved = job.isSavedLocally;

    // Show expired status for completed jobs that have expired and aren't saved
    if (job.status == 'completed' && isExpired) {
      return Row(
        key: const ValueKey('expired'),
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 16,
            color: cs.outline,
          ),
          const SizedBox(width: 8),
          Text(
            "EXPIRED",
            style: TextStyle(
              color: cs.outline,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    // Show saved status with a nice green indicator
    if (isSaved) {
      return const Row(
        key: ValueKey('saved'),
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: Colors.green,
          ),
          SizedBox(width: 8),
          Text(
            "SAVED",
            style: TextStyle(
              color: Colors.green,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    // Countdown until the cloud copy times out. Kie jobs are downloaded
    // automatically, so after that timeout they stay a normal result.
    // A finished song whose versions can already play is a completed result.
    if (job.status == 'completed' &&
        !isExpired &&
        !isSaved &&
        !_musicFullyPlayable &&
        !(job.usesKieCloud && job.isCloudExpired)) {
      final timeLeft = job.expiryTimeFormatted;
      return Row(
        key: ValueKey('expiring_$timeLeft'),
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 16,
            color:
                job.timeUntilExpiry.inHours < 2 ? Colors.orange : cs.secondary,
          ),
          const SizedBox(width: 8),
          Text(
            timeLeft,
            style: TextStyle(
              color: job.timeUntilExpiry.inHours < 2
                  ? Colors.orange
                  : cs.secondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            "• Ready",
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    return Row(
      key: const ValueKey('completed_or_failed'),
      children: [
        Icon(
          isFailed ? Icons.error_outline : Icons.check_circle_outline,
          size: 16,
          color: isFailed ? cs.error : cs.secondary,
        ),
        const SizedBox(width: 8),
        Text(
          isFailed
              ? job.status.toUpperCase()
              : (isDownloaded ? "SAVED" : "COMPLETED").toUpperCase(),
          style: TextStyle(
            color: isFailed
                ? cs.error
                : isDownloaded
                    ? Colors.green
                    : cs.secondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ✅ Delete confirmation dialog
  Future<void> _confirmDelete(BuildContext context, ColorScheme cs) async {
    bool deleteGalleryFile = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Text(
              'Delete this job?',
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'This will remove this job from your list and delete related files.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: deleteGalleryFile,
                      onChanged: (val) =>
                          setState(() => deleteGalleryFile = val ?? false),
                      activeColor: cs.error,
                      side: BorderSide(color: cs.onSurfaceVariant),
                    ),
                    Flexible(
                      child: Text(
                        'Also delete saved result file from gallery',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                child: Text(
                  'Cancel',
                  style: TextStyle(color: cs.primary),
                ),
                onPressed: () => Navigator.pop(context, false),
              ),
              TextButton(
                child: Text(
                  'Delete',
                  style: TextStyle(color: cs.error),
                ),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await markJobAsDeleted(widget.job.jobId);
      jobListNotifier.value = jobListNotifier.value
          .where((j) => j.jobId != widget.job.jobId)
          .toList();
      await saveJobsToPrefs();
      await FileService.deleteJobFiles(widget.job,
          deleteGalleryFile: deleteGalleryFile);
    }
  }

  // ✅ Show expired cloud result dialog
  void _showExpiredDialog(BuildContext context, ColorScheme cs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        icon: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.errorContainer.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_off_rounded,
            size: 32,
            color: cs.error,
          ),
        ),
        title: Text(
          'Cloud Result Expired',
          style: TextStyle(
            color: cs.onSurface,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This result is no longer available in the cloud. '
              'Results stay for 14 days on server then deleted. Download them before they expire.',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 20,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tip: Save results to your device to keep them forever!',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Got it',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// =============================================================================
/// ANIMATED PROCESSING BORDER
/// =============================================================================
/// Rotating gradient border that replaces the spinner for processing jobs.
/// Uses a shared animation controller to minimize overhead.
class _AnimatedProcessingBorder extends StatefulWidget {
  final bool isProcessing;
  final String jobCategory;
  final Widget child;

  const _AnimatedProcessingBorder({
    super.key,
    required this.isProcessing,
    required this.jobCategory,
    required this.child,
  });

  @override
  State<_AnimatedProcessingBorder> createState() =>
      _AnimatedProcessingBorderState();
}

class _AnimatedProcessingBorderState extends State<_AnimatedProcessingBorder>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    if (widget.isProcessing) {
      _ProcessingAnimationController.instance.initialize(this);
      _ProcessingAnimationController.instance.addListener();
    }
  }

  @override
  void didUpdateWidget(_AnimatedProcessingBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isProcessing && !oldWidget.isProcessing) {
      _ProcessingAnimationController.instance.initialize(this);
      _ProcessingAnimationController.instance.addListener();
    } else if (!widget.isProcessing && oldWidget.isProcessing) {
      _ProcessingAnimationController.instance.removeListener();
    }
  }

  @override
  void dispose() {
    if (widget.isProcessing) {
      _ProcessingAnimationController.instance.removeListener();
    }
    super.dispose();
  }

  List<Color> _getBorderColors() {
    // Professional, muted colors that work in light/dark modes
    switch (widget.jobCategory) {
      case 'video':
        return [
          const Color(0xFFE07B54), // Muted coral
          const Color(0xFFD4915C), // Muted amber
          const Color(0xFFBF7B6A), // Muted terracotta
          const Color(0xFFE07B54), // Muted coral
        ];
      case 'audio':
        return [
          const Color(0xFF5BA88F), // Muted teal
          const Color(0xFF6BA3A8), // Muted cyan
          const Color(0xFF7B9EB0), // Muted sky
          const Color(0xFF5BA88F), // Muted teal
        ];
      case 'enhance':
        return [
          const Color(0xFF9B7BB8), // Muted lavender
          const Color(0xFFB87BA0), // Muted rose
          const Color(0xFFA8859B), // Muted mauve
          const Color(0xFF9B7BB8), // Muted lavender
        ];
      case 'edit':
        return [
          const Color(0xFF6B8FC7), // Muted blue
          const Color(0xFF8B7BC7), // Muted periwinkle
          const Color(0xFF9B8BB0), // Muted violet
          const Color(0xFF6B8FC7), // Muted blue
        ];
      case 'text':
        return [
          const Color(0xFF5BA88F), // Muted teal-green
          const Color(0xFF6BA3A8), // Muted cyan
          const Color(0xFF7B9EB0), // Muted sky-blue
          const Color(0xFF5BA88F), // Muted teal-green
        ];
      default: // image
        return [
          const Color(0xFF7B8BC7), // Muted indigo
          const Color(0xFF9B7BB8), // Muted purple
          const Color(0xFFB8859B), // Muted pink
          const Color(0xFF7B8BC7), // Muted indigo
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isProcessing) {
      return widget.child;
    }

    final controller = _ProcessingAnimationController.instance.controller;
    if (controller == null) {
      return widget.child;
    }

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _RotatingBorderPainter(
              progress: controller.value,
              colors: _getBorderColors(),
            ),
            child: widget.child,
          );
        },
      ),
    );
  }
}

/// Custom painter for rotating gradient border with pulsing glow
class _RotatingBorderPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;

  _RotatingBorderPainter({
    required this.progress,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    const radius = 12.0;

    // Create rotating gradient with smooth rotation
    final angle = progress * 2 * math.pi;

    // Pulsing effect: oscillates between 0.6 and 1.0
    final pulseValue = 0.8 + 0.2 * math.sin(progress * 4 * math.pi);

    // Subtle brightness modulation for professional look
    final enhancedColors = colors.map((c) {
      final hsl = HSLColor.fromColor(c);
      // Keep saturation moderate and lightness balanced for light/dark modes
      return hsl
          .withLightness(
              (hsl.lightness * (0.9 + 0.1 * pulseValue)).clamp(0.35, 0.65))
          .toColor();
    }).toList();

    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: angle,
      endAngle: angle + 2 * math.pi,
      colors: enhancedColors,
      stops: const [0.0, 0.33, 0.66, 1.0],
    );

    // Draw rounded rectangle path
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(radius)));

    // Layer 1: Outer glow (soft, wide)
    final outerGlowPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0 * pulseValue
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * pulseValue);
    canvas.drawPath(path, outerGlowPaint);

    // Layer 2: Mid glow (medium intensity)
    final midGlowPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0 * pulseValue
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * pulseValue);
    canvas.drawPath(path, midGlowPaint);

    // Layer 3: Core border (sharp, bright)
    final borderPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, borderPaint);

    // Layer 4: Inner highlight (bright center line)
    final highlightPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.5 * pulseValue);
    canvas.drawPath(path, highlightPaint);
  }

  @override
  bool shouldRepaint(_RotatingBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// =============================================================================
/// ANIMATED GRADIENT BACKGROUND
/// =============================================================================
/// Vibrant animated gradient background for text-to-image/video/audio jobs
class _AnimatedGradientBackground extends StatefulWidget {
  final String category;
  final bool isProcessing;

  const _AnimatedGradientBackground({
    required this.category,
    required this.isProcessing,
  });

  @override
  State<_AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState
    extends State<_AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (widget.isProcessing) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_AnimatedGradientBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isProcessing && !oldWidget.isProcessing) {
      _controller.repeat();
    } else if (!widget.isProcessing && oldWidget.isProcessing) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Color> _getColors() {
    // Professional, muted colors that work in light/dark modes
    switch (widget.category) {
      case 'video':
        return [
          const Color(0xFFD4825C), // Muted coral
          const Color(0xFFCB9465), // Muted sand
          const Color(0xFFBF8A70), // Muted peach
          const Color(0xFFD4825C), // Muted coral
        ];
      case 'audio':
        return [
          const Color(0xFF5AA08A), // Muted seafoam
          const Color(0xFF6899A0), // Muted teal
          const Color(0xFF7094A8), // Muted steel blue
          const Color(0xFF5AA08A), // Muted seafoam
        ];
      case 'enhance':
        return [
          const Color(0xFF9575A8), // Muted orchid
          const Color(0xFFA87595), // Muted dusty rose
          const Color(0xFF957590), // Muted plum
          const Color(0xFF9575A8), // Muted orchid
        ];
      case 'edit':
        return [
          const Color(0xFF6588B8), // Muted azure
          const Color(0xFF7580B0), // Muted slate blue
          const Color(0xFF8580A8), // Muted lavender blue
          const Color(0xFF6588B8), // Muted azure
        ];
      case 'text':
        return [
          const Color(0xFF5AA08A), // Muted seafoam-green
          const Color(0xFF6899A0), // Muted teal
          const Color(0xFF7094A8), // Muted steel blue
          const Color(0xFF5AA08A), // Muted seafoam-green
        ];
      default: // image
        return [
          const Color(0xFF7580B8), // Muted periwinkle
          const Color(0xFF8878A8), // Muted iris
          const Color(0xFFA07898), // Muted mauve
          const Color(0xFF7580B8), // Muted periwinkle
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _getColors();

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // Smooth rotating gradient with easing
          final progress = _controller.value;
          final angle = progress * 2 * math.pi;

          // Subtle pulsing brightness for professional look
          final pulse = 0.92 + 0.08 * math.sin(progress * 3 * math.pi);

          // Balanced colors that work in light/dark modes
          final pulsedColors = colors.map((c) {
            final hsl = HSLColor.fromColor(c);
            return hsl
                .withLightness((hsl.lightness * pulse).clamp(0.4, 0.6))
                .toColor();
          }).toList();

          return CustomPaint(
            painter: _GradientBackgroundPainter(
              angle: angle,
              colors: pulsedColors,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

/// Custom painter for animated gradient background
class _GradientBackgroundPainter extends CustomPainter {
  final double angle;
  final List<Color> colors;

  _GradientBackgroundPainter({
    required this.angle,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Create sweep gradient for smooth rotation
    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: angle,
      endAngle: angle + 2 * math.pi,
      colors: colors,
      stops: const [0.0, 0.33, 0.66, 1.0],
    );

    final paint = Paint()..shader = gradient.createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_GradientBackgroundPainter oldDelegate) {
    return oldDelegate.angle != angle;
  }
}

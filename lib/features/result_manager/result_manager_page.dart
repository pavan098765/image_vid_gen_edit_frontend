// lib/features/result_manager/result_manager_page.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/polling_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/thumbnail_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool isResultManagerOpen = false;

class ResultManagerPage extends StatefulWidget {
  const ResultManagerPage({super.key});

  @override
  State<ResultManagerPage> createState() => _ResultManagerPageState();
}

class _ResultManagerPageState extends State<ResultManagerPage>
    with WidgetsBindingObserver {
  // Multi-select state
  bool _isSelectionMode = false;
  final Set<String> _selectedJobIds = <String>{};
  
  // Search and filter state
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _sortBy = 'date'; // 'date', 'status', 'title'
  bool _sortAscending = false; // newest first by default
  
  // Cloud storage banner state
  bool _isBannerExpanded = true;

  @override
  void initState() {
    super.initState();
    isResultManagerOpen = true;
    WidgetsBinding.instance.addObserver(this);
    _refreshJobs();
    _markAllCompletedAsSeen();
    _loadBannerPreference();
    _prefetchDownloadUrls(); // Pre-fetch URLs in background

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
      
      debugPrint('🔄 Pre-fetching URLs for ${completedJobs.length} completed jobs...');
      
      // Fetch URLs in parallel with a small delay between each
      for (final job in completedJobs) {
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
  
  Future<void> _loadBannerPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _isBannerExpanded = prefs.getBool('cloud_storage_banner_expanded') ?? true;
      });
    }
  }
  
  Future<void> _toggleBanner() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isBannerExpanded = !_isBannerExpanded;
    });
    await prefs.setBool('cloud_storage_banner_expanded', _isBannerExpanded);
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
    WidgetsBinding.instance.removeObserver(this);
    isResultManagerOpen = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshJobs();
    }
  }

  Future<void> _refreshJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();

      // Load existing jobs
      final localJson = prefs.getString('jobs');
      if (localJson != null) {
        final decoded = jsonDecode(localJson);
        if (decoded is List) {
          jobListNotifier.value = decoded
              .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      // Query server with force refresh (bypasses age limit and throttling)
      await PollingService.instance.refreshProcessingJobs(forceRefresh: true);

      // Reload after server update
      await prefs.reload();
      final updatedJson = prefs.getString('jobs');
      if (updatedJson != null) {
        final decoded = jsonDecode(updatedJson);
        if (decoded is List) {
          jobListNotifier.value = decoded
              .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      }
    } catch (_) {}
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
        return job.title.toLowerCase().contains(_searchQuery) ||
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
                  'This will remove selected jobs from your list and delete related files.',
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
      
      for (final jobId in selectedIdsCopy) {
        final job = jobs.firstWhere((j) => j.jobId == jobId,
            orElse: () => jobs.first);
        await FileService.deleteJobFiles(job,
            deleteGalleryFile: deleteGalleryFiles);
      }

      jobListNotifier.value = jobs
          .where((j) => !selectedIdsCopy.contains(j.jobId))
          .toList();
      await saveJobsToPrefs();

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

  // Info banner explaining 24-hour cloud storage (collapsible)
  Widget _buildCloudStorageInfoBanner(ColorScheme cs) {
    return GestureDetector(
      onTap: _toggleBanner,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        padding: EdgeInsets.symmetric(
          horizontal: _isBannerExpanded ? 14 : 12,
          vertical: _isBannerExpanded ? 10 : 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.primaryContainer.withOpacity(_isBannerExpanded ? 0.4 : 0.25),
              cs.secondaryContainer.withOpacity(_isBannerExpanded ? 0.3 : 0.15),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.primary.withOpacity(_isBannerExpanded ? 0.2 : 0.1),
          ),
        ),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          crossFadeState: _isBannerExpanded 
              ? CrossFadeState.showFirst 
              : CrossFadeState.showSecond,
          firstChild: _buildExpandedBanner(cs),
          secondChild: _buildCollapsedBanner(cs),
        ),
      ),
    );
  }
  
  Widget _buildExpandedBanner(ColorScheme cs) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cloud_queue_rounded,
            size: 18,
            color: cs.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Free Cloud Storage',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Results available for 24 hours • Save to keep forever',
                style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.8),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.keyboard_arrow_up_rounded,
          size: 20,
          color: cs.onSurfaceVariant.withOpacity(0.5),
        ),
      ],
    );
  }
  
  Widget _buildCollapsedBanner(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.cloud_queue_rounded,
          size: 14,
          color: cs.primary.withOpacity(0.7),
        ),
        const SizedBox(width: 8),
        Text(
          '24h cloud storage',
          style: TextStyle(
            color: cs.onSurfaceVariant.withOpacity(0.7),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 16,
          color: cs.onSurfaceVariant.withOpacity(0.5),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: _isSelectionMode
            ? Text(
                '${_selectedJobIds.length} selected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              )
            : Text(
                'My AI Jobs',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
        backgroundColor: cs.surface,
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
                          Text('Sort by Date'),
                          if (_sortBy == 'date')
                            Icon(
                              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
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
                          Text('Sort by Status'),
                          if (_sortBy == 'status')
                            Icon(
                              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
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
                          Text('Sort by Title'),
                          if (_sortBy == 'title')
                            Icon(
                              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                              size: 16,
                              color: cs.primary,
                            ),
                        ],
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'toggle_sort',
                      child: Row(
                        children: [
                          Icon(Icons.swap_vert, size: 20),
                          const SizedBox(width: 8),
                          Text(_sortAscending ? 'Newest First' : 'Oldest First'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          // 🔔 Cloud Storage Info Banner
          _buildCloudStorageInfoBanner(cs),
          
          // Search bar - uses consistent AppStyles
          Padding(
            padding: const EdgeInsets.all(AppStyles.spacing12),
            child: TextField(
              controller: _searchController,
              decoration: AppStyles.inputDecoration(
                cs,
                hintText: 'Search jobs...',
                prefixIcon: Icons.search,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: cs.onSurfaceVariant, size: 20),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
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
                    return Center(
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No jobs found matching "$_searchQuery"'
                            : 'No jobs yet.',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filteredJobs.length,
                    itemBuilder: (_, i) => JobCard(
                      job: filteredJobs[i],
                      isSelectionMode: _isSelectionMode,
                      isSelected: _selectedJobIds.contains(filteredJobs[i].jobId),
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          _toggleSelectionMode();
                        }
                        _toggleJobSelection(filteredJobs[i].jobId);
                      },
                      onTap: _isSelectionMode
                          ? () => _toggleJobSelection(filteredJobs[i].jobId)
                          : null,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
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

  bool get _isDownloaded =>
      widget.job.localFilePath != null &&
      File(widget.job.localFilePath!).existsSync();

  Future<void> _openPreview(BuildContext context) async {
    if (_openingPreview) return;
    _openingPreview = true;

    try {
      String? path = widget.job.localFilePath;

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

      // File exists locally, open preview
      if (context.mounted) {
        FileService.openLocalPreview(context, path);
      }
    } finally {
      _openingPreview = false;
    }
  }

  Future<void> _download(BuildContext context) async {
    if (_isDownloading) return;

    // If file already exists locally, just save to gallery
    if (widget.job.localFilePath != null &&
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
        if (attempt == 1 && widget.job.downloadUrl != null && widget.job.downloadUrl!.isNotEmpty) {
          // Quick check if URL looks valid (has exp parameter and not too old)
          if (PollingService.isSignedUrlValid(widget.job.downloadUrl, minRemainingSeconds: 60)) {
            downloadUrl = widget.job.downloadUrl;
            debugPrint('✅ Using job\'s cached signed URL directly (from FCM) - NO API call');
          } else {
            debugPrint('⏰ Job URL expired or invalid, will fetch fresh one');
          }
        }
        
        // If no valid URL from job, try SharedPreferences cache
        if (downloadUrl == null || downloadUrl.isEmpty) {
          if (attempt == 1) {
            debugPrint('🔍 Checking SharedPreferences cache for URL...');
            downloadUrl = await PollingService.getValidDownloadUrl(widget.job.jobId);
            if (downloadUrl != null) {
              debugPrint('✅ Found valid URL in SharedPreferences cache');
            }
          } else {
            // Force refresh on second attempt
            debugPrint('🔄 Force refreshing download URL from server...');
            downloadUrl = await PollingService.refreshDownloadUrl(widget.job.jobId);
          }
        }
        
        // Update job with new URL if we got one
        if (downloadUrl != null && downloadUrl.isNotEmpty && downloadUrl != widget.job.downloadUrl) {
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

      try {
        await precacheImage(FileImage(file), context);
      } catch (_) {}

      widget.job.localFilePath = savedPath;
      await addOrUpdateJob(widget.job);
      await saveJobsToPrefs();

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
    
    // Check if expired (>24h old and not saved locally)
    final isExpired = job.isCloudExpired && !job.isSavedLocally;
    final isSaved = job.isSavedLocally;

    final downloadColor = isSaved 
        ? Colors.green 
        : isExpired 
            ? cs.outline 
            : cs.primary;
    final downloadIcon = isSaved 
        ? Icons.check_circle 
        : isExpired 
            ? Icons.cloud_off_rounded 
            : Icons.download;

    return InkWell(
      onTap: widget.isSelectionMode
          ? widget.onTap
          : (job.status == 'completed' && !isExpired ? () => _openPreview(context) : null),
      onLongPress: widget.onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Opacity(
        // Dim expired jobs that aren't saved locally
        opacity: isExpired ? 0.6 : 1.0,
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: widget.isSelected
              ? cs.primaryContainer.withOpacity(0.3)
              : isExpired
                  ? cs.surfaceContainerHigh.withOpacity(0.5)
                  : cs.surfaceContainerHigh,
          elevation: widget.isSelected ? 2 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: widget.isSelected
                ? BorderSide(color: cs.primary, width: 2)
                : isExpired
                    ? BorderSide(color: cs.outline.withOpacity(0.3), width: 1)
                    : BorderSide.none,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

                // ✅ Selection checkbox or thumbnail
                leading: widget.isSelectionMode
                    ? Checkbox(
                        value: widget.isSelected,
                        onChanged: (_) => widget.onTap?.call(),
                        activeColor: cs.primary,
                      )
                    : _buildThumbnail(cs),

                // ✅ Title
                title: Text(
                  job.title,
                  style: textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isExpired ? cs.onSurface.withOpacity(0.7) : cs.onSurface,
                ),
              ),

              // ✅ Status animated
              subtitle: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildStatus(cs),
              ),

              // ✅ Trailing buttons (hidden in selection mode)
              trailing: widget.isSelectionMode
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (job.status == 'completed')
                          IconButton(
                            icon: _isDownloading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : Icon(downloadIcon, color: downloadColor),
                            tooltip: isExpired 
                                ? 'Cloud result expired' 
                                : isSaved 
                                    ? 'Already saved' 
                                    : 'Save to device',
                            onPressed: _isDownloading || isExpired || isSaved 
                                ? (isExpired ? () => _showExpiredDialog(context, cs) : null) 
                                : () => _download(context),
                          ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant),
                          tooltip: 'Delete Job',
                          onPressed: () => _confirmDelete(context, cs),
                        ),
                      ],
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
          ],
        ),
        ),
      ),
    );
  }

  // ✅ Thumbnail widget - uses cached thumbnails for large images
  Widget _buildThumbnail(ColorScheme cs) {
    final fileExists = widget.job.localFilePath != null &&
        File(widget.job.localFilePath!).existsSync();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outline.withOpacity(0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: fileExists
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedThumbnail(
                      key: ValueKey(widget.job.localFilePath),
                      filePath: widget.job.localFilePath,
                      width: 58,
                      height: 58,
                      fit: BoxFit.cover,
                      thumbnailSize: 150, // Generate 150px thumbnails for crisp display
                      placeholder: _buildLoadingPlaceholder(cs),
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
                              Colors.black.withOpacity(0.05),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : _buildBlurOrPlaceholder(cs),
        ),
      ),
    );
  }
  
  Widget _buildLoadingPlaceholder(ColorScheme cs) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHigh,
            cs.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: cs.primary.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildBlurOrPlaceholder(ColorScheme cs) {
    final job = widget.job;
    final inputExists =
        job.inputImagePath != null && File(job.inputImagePath!).existsSync();

    if ((job.status == 'processing' || job.status == 'completed') &&
        inputExists) {
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
              // Use cacheWidth/cacheHeight to prevent loading full res for blur
              cacheWidth: 116, // 2x display size for retina
              cacheHeight: 116,
            ),
          ),
          // Subtle dark overlay for better visual
          Container(
            color: Colors.black.withOpacity(0.1),
          ),
          if (job.status == 'processing')
            Positioned.fill(
              child: Shimmer.fromColors(
                baseColor: cs.primary.withOpacity(0.15),
                highlightColor: cs.primary.withOpacity(0.45),
                child: Container(color: cs.primary.withOpacity(0.10)),
              ),
            ),
          // Processing indicator in center
          if (job.status == 'processing')
            Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(0.85),
                  shape: BoxShape.circle,
                ),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // Default placeholder with icon
    return Container(
      key: const ValueKey('placeholder'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surfaceContainerHigh,
            cs.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          _getPlaceholderIcon(job.model),
          color: cs.onSurfaceVariant.withOpacity(0.4),
          size: 24,
        ),
      ),
    );
  }
  
  // Get appropriate icon based on job type
  IconData _getPlaceholderIcon(String model) {
    final modelLower = model.toLowerCase();
    if (modelLower.contains('video') || modelLower.contains('animate')) {
      return Icons.videocam_rounded;
    } else if (modelLower.contains('upscale') || modelLower.contains('enhance')) {
      return Icons.auto_awesome;
    } else if (modelLower.contains('remove') || modelLower.contains('erase')) {
      return Icons.auto_fix_high;
    }
    return Icons.image_rounded;
  }

  // ✅ Status widget (includes DOWNLOADING state)
  Widget _buildStatus(ColorScheme cs) {
    final job = widget.job;

    if (job.status == 'processing') {
      return Row(
        key: const ValueKey('processing'),
        children: [
          SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "PROCESSING…",
            style: TextStyle(
              color: cs.primary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    if (_isDownloading) {
      return Row(
        key: const ValueKey('downloading'),
        children: [
          SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 10),
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
    final isExpired = job.isCloudExpired && !job.isSavedLocally;
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
      return Row(
        key: const ValueKey('saved'),
        children: [
          Icon(
            Icons.check_circle,
            size: 16,
            color: Colors.green,
          ),
          const SizedBox(width: 8),
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

    // Show expiry countdown for completed but not yet saved/expired
    if (job.status == 'completed' && !isExpired && !isSaved) {
      final timeLeft = job.expiryTimeFormatted;
      return Row(
        key: ValueKey('expiring_$timeLeft'),
        children: [
          Icon(
            Icons.schedule_rounded,
            size: 16,
            color: job.timeUntilExpiry.inHours < 2 
                ? Colors.orange 
                : cs.secondary,
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
              color: cs.onSurfaceVariant.withOpacity(0.6),
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
      await FileService.deleteJobFiles(widget.job,
          deleteGalleryFile: deleteGalleryFile);

      jobListNotifier.value = jobListNotifier.value
          .where((j) => j.jobId != widget.job.jobId)
          .toList();
      await saveJobsToPrefs();
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
            color: cs.errorContainer.withOpacity(0.3),
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
              'Free cloud storage keeps results for 24 hours.',
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
                color: cs.primaryContainer.withOpacity(0.3),
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

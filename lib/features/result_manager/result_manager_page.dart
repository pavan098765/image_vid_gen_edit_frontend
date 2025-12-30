// lib/features/result_manager/result_manager_page.dart

import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:image_vid_gen_edit_frontend/core/app_state.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:image_vid_gen_edit_frontend/core/services/polling_service.dart';
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

  @override
  void initState() {
    super.initState();
    isResultManagerOpen = true;
    WidgetsBinding.instance.addObserver(this);
    _refreshJobs();
    _markAllCompletedAsSeen();

    SharedPreferences.getInstance().then((prefs) async {
      await prefs.reload();
    });
    
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
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

      // Query server
      await PollingService.instance.refreshProcessingJobs();

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
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search jobs...',
                prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: cs.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
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

      if (path == null || !File(path).existsSync()) {
        // 🔐 Refresh signed URL before preview (URLs expire after 1 hour)
        String? downloadUrl = widget.job.downloadUrl;
        if (downloadUrl == null || downloadUrl.isEmpty) {
          downloadUrl = await PollingService.getSignedDownloadUrl(widget.job.jobId);
          if (downloadUrl != null) {
            widget.job.downloadUrl = downloadUrl;
            await addOrUpdateJob(widget.job);
          }
        }

        if (downloadUrl == null || downloadUrl.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to get download URL')),
            );
          }
          return;
        }

        path = await FileService.previewFileAndReturnPath(
          context,
          downloadUrl,
          uniqueKey: widget.job.jobId,
        );

        if (path != null) {
          widget.job.localFilePath = path;
          await addOrUpdateJob(widget.job);
        }
        return;
      }

      FileService.openLocalPreview(context, path);
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

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    // 🔐 Refresh signed URL before download (URLs expire after 1 hour)
    String? downloadUrl = widget.job.downloadUrl;
    if (downloadUrl == null || downloadUrl.isEmpty) {
      downloadUrl = await PollingService.getSignedDownloadUrl(widget.job.jobId);
      if (downloadUrl != null) {
        widget.job.downloadUrl = downloadUrl;
        await addOrUpdateJob(widget.job);
      }
    }

    if (downloadUrl == null || downloadUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to get download URL')),
        );
      }
      return;
    }

    final savedPath = await FileService.downloadFromUrl(
      context,
      downloadUrl,
      suggestedFileName: widget.job.jobId,
      onProgress: (progress) {
        if (mounted) {
          setState(() => _downloadProgress = progress);
        }
      },
    );

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

    final downloadColor = _isDownloaded ? Colors.green : cs.primary;
    final downloadIcon =
        _isDownloaded ? Icons.check_circle : Icons.download;

    return InkWell(
      onTap: widget.isSelectionMode
          ? widget.onTap
          : (job.status == 'completed' ? () => _openPreview(context) : null),
      onLongPress: widget.onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: widget.isSelected
            ? cs.primaryContainer.withOpacity(0.3)
            : cs.surfaceContainerHigh,
        elevation: widget.isSelected ? 2 : 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: widget.isSelected
              ? BorderSide(color: cs.primary, width: 2)
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
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: _buildThumbnail(cs),
                    ),

              // ✅ Title
              title: Text(
                job.title,
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
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
                            tooltip: 'Save to device',
                            onPressed:
                                _isDownloading ? null : () => _download(context),
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
    );
  }

  // ✅ Thumbnail widget
  Widget _buildThumbnail(ColorScheme cs) {
    final fileExists = widget.job.localFilePath != null &&
        File(widget.job.localFilePath!).existsSync();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: fileExists
          ? Image.file(
              File(widget.job.localFilePath!),
              key: ValueKey(widget.job.localFilePath),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            )
          : _buildBlurOrPlaceholder(cs),
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
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: Image.file(
              File(job.inputImagePath!),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
            ),
          ),
          if (job.status == 'processing')
            Positioned.fill(
              child: Shimmer.fromColors(
                baseColor: cs.primary.withOpacity(0.15),
                highlightColor: cs.primary.withOpacity(0.45),
                child: Container(color: cs.primary.withOpacity(0.10)),
              ),
            ),
        ],
      );
    }

    return Container(
      key: const ValueKey('placeholder'),
      width: 52,
      height: 52,
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.image, color: cs.onSurfaceVariant),
    );
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
          : (isDownloaded ? "DOWNLOADED" : "COMPLETED").toUpperCase(),
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
}

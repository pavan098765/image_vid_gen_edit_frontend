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
  @override
  void initState() {
    super.initState();
    isResultManagerOpen = true;
    WidgetsBinding.instance.addObserver(this);
    _refreshJobs();

    SharedPreferences.getInstance().then((prefs) async {
      await prefs.reload();
    });
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'My AI Jobs',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: cs.onSurface,
          ),
        ),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: cs.primary,
        backgroundColor: cs.surfaceContainer,
        onRefresh: _refreshJobs,
        child: ValueListenableBuilder<List<JobModel>>(
          valueListenable: jobListNotifier,
          builder: (_, jobs, __) {
            if (jobs.isEmpty) {
              return Center(
                child: Text(
                  'No jobs yet.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 15,
                  ),
                ),
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: jobs.length,
              itemBuilder: (_, i) => JobCard(job: jobs[i]),
            );
          },
        ),
      ),
    );
  }
}

class JobCard extends StatefulWidget {
  final JobModel job;
  const JobCard({super.key, required this.job});

  @override
  State<JobCard> createState() => _JobCardState();
}

class _JobCardState extends State<JobCard> {
  static bool _openingPreview = false;
  double _downloadProgress = 0.0;
  bool _isDownloading = false;

  Future<void> _openPreview(BuildContext context) async {
    if (_openingPreview) return;
    _openingPreview = true;

    try {
      String? path = widget.job.localFilePath;

      if (path == null || !File(path).existsSync()) {
        path = await FileService.previewFileAndReturnPath(
          context,
          widget.job.downloadUrl!,
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

    final savedPath = await FileService.downloadFromUrl(
      context,
      widget.job.downloadUrl!,
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

    return InkWell(
      onTap: job.status == 'completed' ? () => _openPreview(context) : null,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: cs.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

              // ✅ Thumbnail area
              leading: ClipRRect(
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

              // ✅ Trailing buttons
              trailing: Row(
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
                          : Icon(Icons.download, color: cs.primary),
                      tooltip: 'Save to device',
                      onPressed:
                          _isDownloading ? null : () => _download(context),
                    ),
                  IconButton(
                    icon:
                        Icon(Icons.delete_outline, color: cs.onSurfaceVariant),
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
          (isFailed ? job.status : "COMPLETED").toUpperCase(),
          style: TextStyle(
            color: isFailed ? cs.error : cs.secondary,
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

// class JobCard extends StatelessWidget {
//   final JobModel job;
//   const JobCard({super.key, required this.job});

//   static bool _openingPreview = false;

//   Future<void> _openPreview(BuildContext context) async {
//     if (_openingPreview) return;
//     _openingPreview = true;

//     try {
//       String? path = job.localFilePath;

//       if (path == null || !File(path).existsSync()) {
//         path = await FileService.previewFileAndReturnPath(
//           context,
//           job.downloadUrl!,
//           uniqueKey: job.jobId,
//         );

//         if (path != null) {
//           job.localFilePath = path;
//           await addOrUpdateJob(job);
//         }
//         return; // preview already shown
//       }

//       FileService.openLocalPreview(context, path);
//     } finally {
//       _openingPreview = false;
//     }
//   }

//   Future<void> _download(BuildContext context) async {
//     if (job.localFilePath != null &&
//         File(job.localFilePath!).existsSync()) {
//       final success = await FileService.saveExistingToGallery(
//         context,
//         job.localFilePath!,
//       );
//       if (success) return;
//     }

//     final savedPath = await FileService.downloadFromUrl(
//       context,
//       job.downloadUrl!,
//       suggestedFileName: job.jobId,
//     );

//     if (savedPath != null) {
//       final file = File(savedPath);
//       for (int i = 0; i < 5; i++) {
//         if (file.existsSync() && file.lengthSync() > 0) break;
//         await Future.delayed(const Duration(milliseconds: 100));
//       }

//       try {
//         await precacheImage(FileImage(file), context);
//       } catch (_) {}

//       job.localFilePath = savedPath;
//       await addOrUpdateJob(job);
//       await saveJobsToPrefs();

//       jobListNotifier.value = List<JobModel>.from(jobListNotifier.value);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     final textTheme = Theme.of(context).textTheme;

//     return InkWell(
//       onTap: job.status == 'completed' ? () => _openPreview(context) : null,
//       borderRadius: BorderRadius.circular(16),
//       child: Card(
//         margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//         color: cs.surfaceContainerHigh,
//         elevation: 0,
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//         child: ListTile(
//           contentPadding:
//               const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

//           // ✅ Thumbnail area
//           leading: ClipRRect(
//             borderRadius: BorderRadius.circular(10),
//             child: _buildThumbnail(cs),
//           ),

//           // ✅ Title
//           title: Text(
//             job.title,
//             style: textTheme.bodyLarge?.copyWith(
//               fontWeight: FontWeight.w600,
//               color: cs.onSurface,
//             ),
//           ),

//           // ✅ Status animated
//           subtitle: AnimatedSwitcher(
//             duration: const Duration(milliseconds: 300),
//             child: _buildStatus(cs),
//           ),

//           // ✅ Trailing buttons
//           trailing: Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               if (job.status == 'completed')
//                 IconButton(
//                   icon: Icon(Icons.download, color: cs.primary),
//                   tooltip: 'Save to device',
//                   onPressed: () => _download(context),
//                 ),

//               IconButton(
//                 icon: Icon(Icons.delete_outline, color: cs.onSurfaceVariant),
//                 tooltip: 'Delete Job',
//                 onPressed: () => _confirmDelete(context, cs),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // ✅ Thumbnail widget
//   Widget _buildThumbnail(ColorScheme cs) {
//     final fileExists =
//         job.localFilePath != null && File(job.localFilePath!).existsSync();

//     return AnimatedSwitcher(
//       duration: const Duration(milliseconds: 350),
//       child: fileExists
//           ? Image.file(
//               File(job.localFilePath!),
//               key: ValueKey(job.localFilePath),
//               width: 52,
//               height: 52,
//               fit: BoxFit.cover,
//             )
//           : _buildBlurOrPlaceholder(cs),
//     );
//   }

//   Widget _buildBlurOrPlaceholder(ColorScheme cs) {
//     final inputExists =
//         job.inputImagePath != null && File(job.inputImagePath!).existsSync();

//     if ((job.status == 'processing' || job.status == 'completed') &&
//         inputExists) {
//       return Stack(
//         key: const ValueKey('blurred'),
//         children: [
//           ImageFiltered(
//             imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
//             child: Image.file(
//               File(job.inputImagePath!),
//               width: 52,
//               height: 52,
//               fit: BoxFit.cover,
//             ),
//           ),

//           if (job.status == 'processing')
//             Positioned.fill(
//               child: Shimmer.fromColors(
//                 baseColor: cs.primary.withOpacity(0.15),
//                 highlightColor: cs.primary.withOpacity(0.45),
//                 child: Container(color: cs.primary.withOpacity(0.10)),
//               ),
//             ),
//         ],
//       );
//     }

//     return Container(
//       key: const ValueKey('placeholder'),
//       width: 52,
//       height: 52,
//       color: cs.surfaceContainerHighest,
//       child: Icon(Icons.image, color: cs.onSurfaceVariant),
//     );
//   }

//   // ✅ Status widget
//   Widget _buildStatus(ColorScheme cs) {
//     if (job.status == 'processing') {
//       return Row(
//         key: const ValueKey('processing'),
//         children: [
//           SizedBox(
//             height: 16,
//             width: 16,
//             child: CircularProgressIndicator(
//               strokeWidth: 2,
//               color: cs.primary,
//             ),
//           ),
//           const SizedBox(width: 10),
//           Text(
//             "PROCESSING…",
//             style: TextStyle(
//               color: cs.primary,
//               fontSize: 13,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//         ],
//       );
//     }

//     final isFailed = job.status == 'failed';

//     return Row(
//       key: const ValueKey('completed_or_failed'),
//       children: [
//         Icon(
//           isFailed ? Icons.error_outline : Icons.check_circle_outline,
//           size: 16,
//           color: isFailed ? cs.error : cs.secondary,
//         ),
//         const SizedBox(width: 8),
//         Text(
//           job.status.toUpperCase(),
//           style: TextStyle(
//             color: isFailed ? cs.error : cs.secondary,
//             fontSize: 13,
//             fontWeight: FontWeight.w600,
//           ),
//         ),
//       ],
//     );
//   }

//   // ✅ Delete confirmation dialog
//   Future<void> _confirmDelete(BuildContext context, ColorScheme cs) async {
//     bool deleteGalleryFile = false;

//     final confirmed = await showDialog<bool>(
//       context: context,
//       builder: (context) {
//         return StatefulBuilder(
//           builder: (context, setState) => AlertDialog(
//             backgroundColor: cs.surface,
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(18),
//             ),
//             title: Text(
//               'Delete this job?',
//               style: TextStyle(
//                 color: cs.onSurface,
//                 fontWeight: FontWeight.bold,
//               ),
//             ),
//             content: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Text(
//                   'This will remove this job from your list and delete related files.',
//                   style: TextStyle(
//                     color: cs.onSurfaceVariant,
//                     height: 1.4,
//                   ),
//                 ),
//                 const SizedBox(height: 12),
//                 Row(
//                   children: [
//                     Checkbox(
//                       value: deleteGalleryFile,
//                       onChanged: (val) =>
//                           setState(() => deleteGalleryFile = val ?? false),
//                       activeColor: cs.error,
//                       side: BorderSide(color: cs.onSurfaceVariant),
//                     ),
//                     Flexible(
//                       child: Text(
//                         'Also delete saved result file from gallery',
//                         style: TextStyle(color: cs.onSurfaceVariant),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//             actions: [
//               TextButton(
//                 child: Text(
//                   'Cancel',
//                   style: TextStyle(color: cs.primary),
//                 ),
//                 onPressed: () => Navigator.pop(context, false),
//               ),
//               TextButton(
//                 child: Text(
//                   'Delete',
//                   style: TextStyle(color: cs.error),
//                 ),
//                 onPressed: () => Navigator.pop(context, true),
//               ),
//             ],
//           ),
//         );
//       },
//     );

//     if (confirmed == true) {
//       await FileService.deleteJobFiles(job,
//           deleteGalleryFile: deleteGalleryFile);

//       jobListNotifier.value = jobListNotifier.value
//           .where((j) => j.jobId != job.jobId)
//           .toList();
//       await saveJobsToPrefs();
//     }
//   }
// }

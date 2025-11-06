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
    isResultManagerOpen = true; // ✅ mark open
    WidgetsBinding.instance.addObserver(this);
    debugPrint("🟢 ResultManagerPage opened");
    _refreshJobs(); // initial refresh on open
    // 🧩 Also ensure latest FCM background writes are caught
    SharedPreferences.getInstance().then((prefs) async {
      await prefs.reload();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    isResultManagerOpen = false; // ✅ mark closed
    debugPrint("🔴 ResultManagerPage closed");
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint("🔁 ResultManagerPage resumed — refreshing jobs");
      _refreshJobs();
    }
  }

  Future<void> _refreshJobs() async {
    debugPrint("🔄 Pull-to-refresh triggered");

    try {
      final prefs = await SharedPreferences.getInstance();

      debugPrint("📂 Reloaded ${jobListNotifier.value.length} jobs from prefs");
      for (final j in jobListNotifier.value) {
        debugPrint(
            "  • job=${j.jobId} inputImagePath=${j.inputImagePath} localFilePath=${j.localFilePath}");
      }
      // ✅ Step 1: Reload what we already have on disk
      await prefs.reload();
      final localJson = prefs.getString('jobs');

      if (localJson != null) {
        final decoded = jsonDecode(localJson);
        if (decoded is List) {
          final list = decoded
              .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          jobListNotifier.value = List<JobModel>.from(list);
          debugPrint("📂 Loaded ${list.length} jobs from disk");
        }
      }

      // ✅ Step 2: Query server for any jobs still processing
      await PollingService.instance.refreshProcessingJobs();

      // ✅ Step 3: Reload updated statuses from SharedPrefs
      await prefs.reload();
      final updatedJson = prefs.getString('jobs');

      if (updatedJson != null) {
        final decoded = jsonDecode(updatedJson);
        if (decoded is List) {
          final list = decoded
              .map((e) => JobModel.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          jobListNotifier.value = List<JobModel>.from(list);
          debugPrint("✅ Updated ${list.length} jobs after server sync");
        }
      }
    } catch (e, st) {
      debugPrint("⚠️ Refresh failed: $e\n$st");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My AI Jobs')),
      body: RefreshIndicator(
        onRefresh: _refreshJobs, // 👈 pull-to-refresh logic
        child: ValueListenableBuilder<List<JobModel>>(
          valueListenable: jobListNotifier,
          builder: (_, jobs, __) {
            if (jobs.isEmpty) {
              return const Center(
                child: Text(
                  'No jobs yet.',
                  style: TextStyle(color: Colors.white70),
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

class JobCard extends StatelessWidget {
  final JobModel job;
  const JobCard({super.key, required this.job});
  static bool _openingPreview = false;

  Future<void> _openPreview(BuildContext context) async {
    if (_openingPreview) return;
    _openingPreview = true;

    try {
      String? path = job.localFilePath;

      // If no local path, fetch+preview once
      if (path == null || !File(path).existsSync()) {
        path = await FileService.previewFileAndReturnPath(
          context,
          job.downloadUrl!,
          uniqueKey: job.jobId,
        );

        // If downloaded successfully, update job
        if (path != null) {
          job.localFilePath = path;
          await addOrUpdateJob(job);
        }

        // ⛔ DO NOT open preview again here — already shown inside previewFileAndReturnPath
        return;
      }

      // If we already have local file – open it normally
      FileService.openLocalPreview(context, path);
    } finally {
      _openingPreview = false;
    }
  }

  Future<void> _download(BuildContext context) async {
    // Already downloaded → re-save
    if (job.localFilePath != null && File(job.localFilePath!).existsSync()) {
      final success = await FileService.saveExistingToGallery(
        context,
        job.localFilePath!,
      );
      if (success) return;
    }

    // Download, save, and link
    final savedPath = await FileService.downloadFromUrl(
      context,
      job.downloadUrl!,
      suggestedFileName: job.jobId, // use jobId-based filename
    );

    if (savedPath != null) {
      // Wait a little to ensure file system ready
      final file = File(savedPath);
      for (int i = 0; i < 5; i++) {
        if (file.existsSync() && file.lengthSync() > 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // Precache image to force reload
      try {
        await precacheImage(FileImage(file), context);
      } catch (e) {
        debugPrint("⚠️ precacheImage failed: $e");
      }

      // Update job and save persistently
      job.localFilePath = savedPath;
      await addOrUpdateJob(job);
      await saveJobsToPrefs();

      // Force rebuild list
      jobListNotifier.value = List<JobModel>.from(jobListNotifier.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: job.status == 'completed' ? () => _openPreview(context) : null,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.white10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          // 🟣 THUMBNAIL AREA (fade between blurred + final)
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Builder(
              builder: (_) {
                final fileExists = job.localFilePath != null &&
                    File(job.localFilePath!).existsSync();

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: fileExists
                      ? Image.file(
                          File(job.localFilePath!),
                          key: ValueKey(job.localFilePath),
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        )
                      : ((job.status == 'processing' ||
                                  job.status == 'completed') &&
                              (job.localFilePath == null ||
                                  !File(job.localFilePath!).existsSync()) &&
                              job.inputImagePath != null &&
                              File(job.inputImagePath!).existsSync())
                          ? Stack(
                              key: const ValueKey('blurred'),
                              children: [
                                ImageFiltered(
                                  imageFilter:
                                      ImageFilter.blur(sigmaX: 6, sigmaY: 6),
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
                                      baseColor: Colors.white24,
                                      highlightColor: Colors.white70,
                                      child: Container(color: Colors.white24),
                                    ),
                                  ),
                              ],
                            )
                          : Container(
                              key: const ValueKey('placeholder'),
                              width: 52,
                              height: 52,
                              color: Colors.black26,
                              child: const Icon(Icons.image,
                                  color: Colors.white54),
                            ),
                );
              },
            ),
          ),

          // 🟣 TITLE
          title: Text(
            job.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),

          // 🟣 SUBTITLE AREA (fade between processing ↔ completed)
          subtitle: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: job.status == 'processing'
                ? const Row(
                    key: ValueKey('processing'),
                    children: [
                      SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blueAccent,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        "PROCESSING...",
                        style: TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : Row(
                    key: ValueKey('completed_or_failed'),
                    children: [
                      Icon(
                        job.status == 'failed'
                            ? Icons.error_outline
                            : Icons.check_circle,
                        size: 16,
                        color: job.status == 'failed'
                            ? Colors.redAccent
                            : Colors.greenAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        job.status.toUpperCase(),
                        style: TextStyle(
                          color: job.status == 'failed'
                              ? Colors.redAccent
                              : Colors.greenAccent,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
          ),

          // 🟣 TRAILING BUTTONS
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (job.status == 'completed')
                IconButton(
                  icon: const Icon(Icons.download, color: Colors.white),
                  tooltip: 'Save to device',
                  onPressed: () => _download(context),
                ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.white70),
                tooltip: 'Delete Job',
                onPressed: () async {
                  bool deleteGalleryFile = false;

                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) {
                      return StatefulBuilder(
                        builder: (context, setState) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          title: const Text(
                            'Delete this job?',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'This will remove this job from your list and delete cached files.',
                                style: TextStyle(
                                    color: Colors.white70, height: 1.4),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Checkbox(
                                    value: deleteGalleryFile,
                                    onChanged: (val) => setState(
                                        () => deleteGalleryFile = val ?? false),
                                    activeColor: Colors.redAccent,
                                    side:
                                        const BorderSide(color: Colors.white54),
                                  ),
                                  const Flexible(
                                    child: Text(
                                      'Also delete saved result file from gallery',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel',
                                  style: TextStyle(color: Colors.blue)),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Delete',
                                  style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      );
                    },
                  );

                  if (confirmed == true) {
                    await FileService.deleteJobFiles(job,
                        deleteGalleryFile: deleteGalleryFile);

                    jobListNotifier.value = jobListNotifier.value
                        .where((j) => j.jobId != job.jobId)
                        .toList();
                    await saveJobsToPrefs();
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

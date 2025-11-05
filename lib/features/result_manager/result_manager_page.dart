import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
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
    final hasPreview =
        job.localFilePath != null && File(job.localFilePath!).existsSync();

    return InkWell(
      onTap: job.status == 'completed' ? () => _openPreview(context) : null,
      borderRadius: BorderRadius.circular(16),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: Colors.white10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: (job.localFilePath != null &&
                    File(job.localFilePath!).existsSync())
                ? Image.file(
                    File(job.localFilePath!),
                    key: ValueKey(job.localFilePath), // ✅ force reload
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 52,
                    height: 52,
                    color: Colors.black26,
                    child: const Icon(Icons.image, color: Colors.white54),
                  ),
          ),
          title: Text(
            job.title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          subtitle: job.status == 'processing'
              ? const Row(
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
                    )
                  ],
                )
              : Text(
                  job.status.toUpperCase(),
                  style: TextStyle(
                    color: job.status == 'failed'
                        ? Colors.redAccent
                        : Colors.greenAccent,
                    fontSize: 13,
                  ),
                ),
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
                  await FileService.deleteJobFiles(job);
                  jobListNotifier.value = jobListNotifier.value
                      .where((j) => j.jobId != job.jobId)
                      .toList();
                  await saveJobsToPrefs();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

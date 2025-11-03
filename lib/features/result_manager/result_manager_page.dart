import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:image_vid_gen_edit_frontend/core/app_state.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';

bool isResultManagerOpen = false;

class ResultManagerPage extends StatefulWidget {
  const ResultManagerPage({super.key});

  @override
  State<ResultManagerPage> createState() => _ResultManagerPageState();
}

class _ResultManagerPageState extends State<ResultManagerPage> {
  @override
  void initState() {
    super.initState();
    isResultManagerOpen = true; // ✅ mark open
    debugPrint("🟢 ResultManagerPage opened");
  }

  @override
  void dispose() {
    isResultManagerOpen = false; // ✅ mark closed
    debugPrint("🔴 ResultManagerPage closed");
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My AI Jobs')),
      body: ValueListenableBuilder<List<JobModel>>(
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
            itemCount: jobs.length,
            itemBuilder: (_, i) => JobCard(job: jobs[i]),
          );
        },
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  final JobModel job;
  const JobCard({super.key, required this.job});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white10,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        title: Text(
          job.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),

        // ✅ Improved subtitle — spinner on LEFT, stable width
        subtitle: job.status == 'processing'
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blueAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 180, // stable width for animated text
                    child: AnimatedTextKit(
                      animatedTexts: [
                        TyperAnimatedText(
                          'Status: processing...',
                          textStyle: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                          speed: const Duration(milliseconds: 80),
                        ),
                      ],
                      repeatForever: true,
                      isRepeatingAnimation: true,
                      pause: const Duration(milliseconds: 500),
                    ),
                  ),
                ],
              )
            : Text(
                "Status: ${job.status}",
                style: TextStyle(
                  color: job.status == 'failed'
                      ? Colors.redAccent
                      : job.status == 'completed'
                          ? Colors.greenAccent
                          : Colors.white70,
                  fontSize: 13,
                ),
              ),

        // ✅ Trailing action buttons
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 👁️ View result
            if (job.status == 'completed' && job.downloadUrl != null)
              IconButton(
                icon: const Icon(Icons.visibility, color: Colors.white70),
                tooltip: 'View Result',
                onPressed: () async {
                  // ✅ Unique preview filename using jobId
                  await FileService.previewFile(
                    context,
                    job.downloadUrl!,
                    uniqueKey: job.jobId,
                  );
                },
              ),

            // ⬇️ Download result
            if (job.status == 'completed' && job.downloadUrl != null)
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white),
                tooltip: 'Download Result',
                onPressed: () async {
                  await FileService.downloadFromUrl(
                    context,
                    job.downloadUrl!,
                    fileName: job.model,
                  );
                },
              ),

            // 🗑️ Delete job
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white70),
              tooltip: 'Delete Job',
              onPressed: () {
                jobListNotifier.value = jobListNotifier.value
                    .where((j) => j.jobId != job.jobId)
                    .toList();
              },
            ),
          ],
        ),
      ),
    );
  }
}

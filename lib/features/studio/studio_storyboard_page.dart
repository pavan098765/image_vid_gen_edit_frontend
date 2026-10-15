import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/studio/studio_api.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/studio/studio_models.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_job_page.dart';
import 'dart:io';

class StudioStoryboardPage extends StatefulWidget {
  final String jobId;
  const StudioStoryboardPage({super.key, required this.jobId});

  @override
  State<StudioStoryboardPage> createState() => _StudioStoryboardPageState();
}

class _StudioStoryboardPageState extends State<StudioStoryboardPage> {
  StudioStoryboard? _board;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final board = await StudioApi.instance.getStoryboard(widget.jobId);
      if (!mounted) return;
      setState(() => _board = board);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _act(
    StudioScene scene,
    String action, {
    String? copy,
    String? replaceR2Key,
    String? exploreJobId,
  }) async {
    setState(() => _busy = true);
    try {
      await StudioApi.instance.sceneAction(
        jobId: widget.jobId,
        sceneId: scene.id,
        action: action,
        copy: copy,
        replaceR2Key: replaceR2Key,
        exploreJobId: exploreJobId,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replaceFromRoll(StudioScene scene) async {
    final file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    final key = await StudioApi.instance.uploadFile(
      jobId: widget.jobId,
      file: File(file.path),
    );
    await _act(scene, 'replace', replaceR2Key: key);
  }

  Future<void> _replaceFromExplore(StudioScene scene) async {
    final jobs = jobListNotifier.value
        .where((j) =>
            j.outputType == 'video' &&
            j.status == 'completed' &&
            (j.downloadUrl != null || j.localFilePath != null))
        .toList();
    if (!mounted) return;
    final picked = await showModalBottomSheet<JobModel>(
      context: context,
      builder: (ctx) {
        if (jobs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No Explore video results yet.'),
          );
        }
        return ListView(
          children: [
            for (final job in jobs)
              ListTile(
                title: Text(job.title),
                subtitle: Text(job.jobId),
                onTap: () => Navigator.pop(ctx, job),
              ),
          ],
        );
      },
    );
    if (picked == null) return;
    await _act(scene, 'replace', exploreJobId: picked.jobId);
  }

  Future<void> _editCopy(StudioScene scene) async {
    final controller = TextEditingController(text: scene.scriptLine ?? '');
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit copy'),
        content: TextField(controller: controller, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next == null) return;
    await _act(scene, 'patch_copy', copy: next);
  }

  Future<void> _continue() async {
    setState(() => _busy = true);
    try {
      await StudioApi.instance.continueJob(widget.jobId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StudioJobPage(jobId: widget.jobId, reviewMode: false),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    return Scaffold(
      appBar: AppBar(title: const Text('Scene review')),
      body: board == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: board.scenes.length,
                    itemBuilder: (context, i) {
                      final scene = board.scenes[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (scene.posterUrl != null)
                                Image.network(scene.posterUrl!, height: 120, fit: BoxFit.cover),
                              Text('Scene ${scene.id}',
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              if (scene.scriptLine != null) Text(scene.scriptLine!),
                              Wrap(
                                spacing: 8,
                                children: [
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _act(scene, 'approve'),
                                    child: Text(scene.approved ? 'Approved' : 'Approve'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _act(scene, 'regenerate'),
                                    child: const Text('Regenerate'),
                                  ),
                                  TextButton(
                                    onPressed: _busy ? null : () => _replaceFromRoll(scene),
                                    child: const Text('Replace (camera roll)'),
                                  ),
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _replaceFromExplore(scene),
                                    child: const Text('Replace (Explore)'),
                                  ),
                                  TextButton(
                                    onPressed: _busy ? null : () => _editCopy(scene),
                                    child: const Text('Edit copy'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton(
                    onPressed: (_busy || !(board.allApproved)) ? null : _continue,
                    child: const Text('Continue → stitch'),
                  ),
                ),
              ],
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/studio/studio_api.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/studio/studio_models.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_open_editor.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_storyboard_page.dart';
import 'package:video_player/video_player.dart';

class StudioJobPage extends StatefulWidget {
  final String jobId;
  final bool reviewMode;

  const StudioJobPage({
    super.key,
    required this.jobId,
    this.reviewMode = true,
  });

  @override
  State<StudioJobPage> createState() => _StudioJobPageState();
}

class _StudioJobPageState extends State<StudioJobPage> {
  String _status = 'queued';
  String? _error;
  String? _resultUrl;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  Future<void> _tick() async {
    try {
      final data = await StudioApi.instance.getJob(widget.jobId);
      final status = mapStudioStatus((data['status'] ?? '').toString());
      String? url;
      if (status == 'completed') {
        final result = await StudioApi.instance.getResult(widget.jobId);
        url = result['url'] as String?;
        await updateJobFields(
          jobId: widget.jobId,
          status: 'completed',
          downloadUrl: url,
          outputType: 'studio_video',
        );
      } else {
        await updateJobFields(
          jobId: widget.jobId,
          status: status,
          outputType: 'studio_video',
        );
      }
      if (!mounted) return;
      setState(() {
        _status = status;
        _resultUrl = url;
        _loading = false;
        _error = data['error'] as String?;
      });
      if (status == 'reviewing' && widget.reviewMode) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => StudioStoryboardPage(jobId: widget.jobId),
          ),
        );
        return;
      }
      const active = {
        'queued',
        'provisioning',
        'running',
        'stitching',
        'uploading',
        'processing',
      };
      if (active.contains(status)) {
        Future<void>.delayed(const Duration(seconds: 4), () {
          if (mounted) _tick();
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Studio job')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: $_status',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  if (_status == 'provisioning')
                    const Text(
                      'Booting the Studio snapshot (usually 2–5 minutes). Keep this screen open or wait for a notification.',
                    ),
                  if (_status == 'reviewing')
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                StudioStoryboardPage(jobId: widget.jobId),
                          ),
                        );
                      },
                      child: const Text('Open storyboard'),
                    ),
                  if (_resultUrl != null) ...[
                    const SizedBox(height: 12),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _StudioPlayer(url: _resultUrl!),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => openStudioInEditor(context, widget.jobId),
                      child: const Text('Open in Editor'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _StudioPlayer extends StatefulWidget {
  final String url;
  const _StudioPlayer({required this.url});
  @override
  State<_StudioPlayer> createState() => _StudioPlayerState();
}

class _StudioPlayerState extends State<_StudioPlayer> {
  VideoPlayerController? _c;

  @override
  void initState() {
    super.initState();
    _c = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || !c.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return GestureDetector(
      onTap: () => c.value.isPlaying ? c.pause() : c.play(),
      child: VideoPlayer(c),
    );
  }
}

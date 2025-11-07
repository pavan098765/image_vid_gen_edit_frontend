// lib/features/video_editor/video_editor_page.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:video_player/video_player.dart';

class VideoEditorPage extends StatefulWidget {
  const VideoEditorPage({super.key});

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  // ---------------- State ----------------
  EditorVideo? _video; // set after picking

  // Controllers
  ProVideoController? _proVideoController;
  late final _editorKey = GlobalKey<ProImageEditorState>();

  // Original video playback
  VideoPlayerController? _videoController;
  late VideoMetadata _videoMetadata;

  // Exported result playback (inline preview)
  String? _outputPath;
  // ignore: unused_field
  Duration _generationTime = Duration.zero;
  VideoPlayerController? _resultController;

  // Thumbnails
  List<ImageProvider>? _thumbnails;
  final int _thumbnailCount = 7;

  // Editor/trim state
  bool _isSeeking = false;
  TrimDurationSpan? _durationSpan;
  TrimDurationSpan? _pendingSeek;

  // UI state
  bool _isInitializing = false;
  bool _exportJustCompleted = false;
  bool _editorOpen = false; // <-- whether the editor overlay is visible now

  // Render config
  final _taskId = DateTime.now().microsecondsSinceEpoch.toString();
  final _outputFormat = VideoOutputFormat.mp4;
  late final VideoEditorConfigs _videoConfigs = const VideoEditorConfigs(
    initialMuted: true,
    initialPlay: false,
    isAudioSupported: true,
    minTrimDuration: Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    // Safe even if already called in main
    MediaKit.ensureInitialized();
  }

  // ---------------- Picking & Initialize ----------------
  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    await _disposeControllers();

    setState(() {
      _video = EditorVideo.file(File(picked.path));
      _outputPath = null;
      _thumbnails = null;
      _isInitializing = true;
      _durationSpan = null;
      _pendingSeek = null;
      _editorOpen = true; // A: open editor automatically
      _exportJustCompleted = false;
    });

    await _initializeEditor();
  }

  Future<void> _initializeEditor() async {
    if (_video == null) return;

    await _setMetadata();
    await _generateThumbnails();

    // Always get a real local file path for the video_player
    final realPath = await _video!.safeFilePath();
    _videoController = VideoPlayerController.file(File(realPath));

    await Future.wait([
      _videoController!.initialize(),
      _videoController!.setLooping(false),
      _videoController!.setVolume(_videoConfigs.initialMuted ? 0 : 1),
      _videoConfigs.initialPlay
          ? _videoController!.play()
          : _videoController!.pause(),
    ]);

    _proVideoController = ProVideoController(
      videoPlayer: _buildVideoPlayer(),
      initialResolution: _videoMetadata.resolution,
      videoDuration: _videoMetadata.duration,
      fileSize: _videoMetadata.fileSize,
      thumbnails: _thumbnails,
    );

    _videoController!.addListener(_onPlaybackTick);

    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _setMetadata() async {
    _videoMetadata = await ProVideoEditor.instance.getMetadata(_video!);
  }

  Future<void> _generateThumbnails() async {
    final screenW = MediaQuery.maybeOf(context)?.size.width ?? 360.0;
    final dpr = WidgetsBinding.instance.window.devicePixelRatio;
    final imageWidth = (screenW / _thumbnailCount) * dpr;

    List<Uint8List> list;

    if (!kIsWeb && Platform.isAndroid) {
      list = await ProVideoEditor.instance.getKeyFrames(
        KeyFramesConfigs(
          video: _video!,
          outputSize: Size.square(imageWidth),
          boxFit: ThumbnailBoxFit.cover,
          maxOutputFrames: _thumbnailCount,
          outputFormat: ThumbnailFormat.jpeg,
        ),
      );
    } else {
      final total = _videoMetadata.duration.inMilliseconds.toDouble();
      final seg = total / _thumbnailCount;
      final timestamps = List.generate(_thumbnailCount, (i) {
        final mid = (i + 0.5) * seg;
        return Duration(milliseconds: mid.round());
      });

      list = await ProVideoEditor.instance.getThumbnails(
        ThumbnailConfigs(
          video: _video!,
          outputSize: Size.square(imageWidth),
          boxFit: ThumbnailBoxFit.cover,
          timestamps: timestamps,
          outputFormat: ThumbnailFormat.jpeg,
        ),
      );
    }

    final imgs = list.map(MemoryImage.new).toList();
    await Future.wait(imgs.map((img) => precacheImage(img, context)));

    _thumbnails = imgs;
    _proVideoController?.thumbnails = _thumbnails;
  }

  // ---------------- Playback sync while editing ----------------
  void _onPlaybackTick() {
    if (_videoController == null || _proVideoController == null) return;
    final total = _videoMetadata.duration;
    final pos = _videoController!.value.position;

    _proVideoController!.setPlayTime(pos);

    if (_durationSpan != null && pos >= _durationSpan!.end) {
      _seekTo(_durationSpan!);
    } else if (pos >= total) {
      _seekTo(TrimDurationSpan(start: Duration.zero, end: total));
    }
  }

  Future<void> _seekTo(TrimDurationSpan span) async {
    _durationSpan = span;
    if (_isSeeking) {
      _pendingSeek = span;
      return;
    }
    _isSeeking = true;

    _proVideoController?.pause();
    _proVideoController?.setPlayTime(span.start);

    await _videoController?.pause();
    await _videoController?.seekTo(span.start);

    _isSeeking = false;

    if (_pendingSeek != null) {
      final next = _pendingSeek!;
      _pendingSeek = null;
      await _seekTo(next);
    }
  }

  // ---------------- Export ----------------
  Future<void> _generateVideo(CompleteParameters p) async {
    if (_video == null) return;

    final sw = Stopwatch()..start();
    unawaited(_videoController?.pause());

    final model = RenderVideoModel(
      id: _taskId,
      video: _video!,
      outputFormat: _outputFormat,
      enableAudio: _proVideoController?.isAudioEnabled ?? true,
      imageBytes: p.layers.isNotEmpty ? p.image : null,
      blur: p.blur,
      colorMatrixList: p.colorFilters,
      startTime: p.startTime,
      endTime: p.endTime,
      transform: p.isTransformed
          ? ExportTransform(
              width: p.cropWidth,
              height: p.cropHeight,
              rotateTurns: p.rotateTurns,
              x: p.cropX,
              y: p.cropY,
              flipX: p.flipX,
              flipY: p.flipY,
            )
          : null,
    );

    final dir = await getTemporaryDirectory();
    final out =
        '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.mp4';
    _outputPath = await ProVideoEditor.instance.renderVideoToFile(out, model);
    _generationTime = sw.elapsed;
    _exportJustCompleted = true;

    // 🎬 Prepare inline result
    await _disposeResultController();
    final file = File(_outputPath!);
    if (await file.exists()) {
      _resultController = VideoPlayerController.file(file);
      await _resultController!.initialize();
      await _resultController!.setLooping(true);
      await _resultController!.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onCloseEditor(EditorMode mode) async {
    debugPrint(
        '🎬 onCloseEditor called — mode: $mode, outputPath: $_outputPath, exportJustCompleted: $_exportJustCompleted');

    // ✅ Only auto-show result if an export just completed
    if (_exportJustCompleted && _outputPath != null) {
      try {
        final file = File(_outputPath!);
        if (await file.exists()) {
          await _disposeResultController();
          _resultController = VideoPlayerController.file(file);
          await _resultController!.initialize();
          await _resultController!.setLooping(true);
          await _resultController!.play();
        }
      } catch (e) {
        debugPrint('⚠️ Error preparing result controller: $e');
      }

      if (mounted) {
        setState(() {
          _editorOpen = false; // Hide editor, show result preview
          _exportJustCompleted = false; // consume the flag
        });
      }
      return;
    }

    // Otherwise (no recent export) — show confirmation dialog on close/back
    final confirm = await _confirmExitEditing();
    if (!confirm) return;

    await _clearLoadedVideo();
  }

  // ---------------- Save exported video ----------------
  Future<void> _saveExported() async {
    if (_outputPath == null) return;
    try {
      final file = File(_outputPath!);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();

      // 🎞 Generate a single thumbnail for bottom sheet preview
      Uint8List? thumbBytes;
      try {
        final thumbList = await ProVideoEditor.instance.getKeyFrames(
          KeyFramesConfigs(
            video: EditorVideo.file(file),
            outputSize: const Size.square(180),
            boxFit: ThumbnailBoxFit.cover,
            maxOutputFrames: 1,
            outputFormat: ThumbnailFormat.jpeg,
          ),
        );
        if (thumbList.isNotEmpty) {
          thumbBytes = thumbList.first;
        }
      } catch (e) {
        debugPrint("⚠️ Failed to create video thumbnail: $e");
      }

      // ✅ Save the video file
      await FileService.saveFile(
        context,
        bytes,
        extension: "mp4",
        customFileName: FileService.generateTimestampFilename("video", "mp4"),
        // NEW: pass thumbnail image bytes for bottom sheet preview
        previewBytes: thumbBytes,
      );

      // ✅ Update in-memory thumbnail in editor view (if desired)
      if (mounted && thumbBytes != null) {
        final newThumb = MemoryImage(thumbBytes);
        await precacheImage(newThumb, context);
        setState(() {
          _thumbnails = [newThumb];
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    }
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Video Editor'),
          actions: [
            if (_video == null)
              IconButton(
                icon: const Icon(Icons.video_library_outlined),
                tooltip: 'Pick Video',
                onPressed: _pickVideo,
              ),
            if (_video != null && !_editorOpen)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
                onPressed: () => setState(() {
                  _editorOpen = true;
                  _exportJustCompleted = false;
                }),
                // onPressed: () => setState(() => _editorOpen = true),
              ),
            if (_outputPath != null && !_editorOpen)
              IconButton(
                icon: const Icon(Icons.save_alt),
                tooltip: 'Save to Gallery',
                onPressed: _saveExported,
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  Future<bool> _handleSystemBack() async {
    // 🎥 1. If editor is open → ask confirmation
    if (_editorOpen) {
      final ok = await _confirmExitEditing();
      if (ok) {
        await _clearLoadedVideo(); // go to pick video
      }
      return false;
    }

    // 🎬 2. If result screen showing → return to editor (to re-edit)
    if (_outputPath != null && !_editorOpen) {
      setState(() => _editorOpen = true);
      return false;
    }

    // 📁 3. If no video selected → allow normal back
    return true;
  }

  // ---------------- MAIN BODY ----------------
  Widget _buildBody() {
    // 🟢 No video picked yet
    if (_video == null) {
      return _pickPlaceholder();
    }

    // 🟡 Still initializing video/editor
    if (_isInitializing ||
        _proVideoController == null ||
        _videoController == null) {
      return const _VideoInitializingWidget();
    }

    // 🟣 Editor overlay active
    if (_editorOpen) {
      return ProImageEditor.video(
        _proVideoController!,
        key: _editorKey,
        callbacks: ProImageEditorCallbacks(
          onCompleteWithParameters: _generateVideo, // apply edits
          onCloseEditor: _onCloseEditor,
          videoEditorCallbacks: VideoEditorCallbacks(
            onPause: _videoController!.pause,
            onPlay: _videoController!.play,
            onMuteToggle: (muted) => _videoController!.setVolume(muted ? 0 : 1),
            onTrimSpanUpdate: (span) {
              if (_videoController!.value.isPlaying) {
                _proVideoController!.pause();
              }
            },
            onTrimSpanEnd: _seekTo,
          ),
        ),
        configs: ProImageEditorConfigs(
          dialogConfigs: DialogConfigs(
            widgets: DialogWidgets(
              loadingDialog: (_, __) => _VideoProgressAlert(taskId: _taskId),
            ),
          ),
          mainEditor: MainEditorConfigs(
            widgets: MainEditorWidgets(
              removeLayerArea: (
                removeAreaKey,
                editor,
                rebuildStream,
                isLayerBeingTransformed,
              ) =>
                  VideoEditorRemoveArea(
                removeAreaKey: removeAreaKey,
                editor: editor,
                rebuildStream: rebuildStream,
                isLayerBeingTransformed: isLayerBeingTransformed,
              ),
            ),
          ),
          paintEditor: const PaintEditorConfigs(
            enableModePixelate: false,
            enableModeBlur: false,
          ),
          videoEditor: _videoConfigs.copyWith(
            playTimeSmoothingDuration: const Duration(milliseconds: 600),
          ),
        ),
      );
    }

    // 🔵 Result view (after export)
    if (_outputPath != null && !_editorOpen) {
      return _buildResultScreen();
    }

    // 🔘 Default fallback → Original video view
    return _buildOriginalPlayer();
  }

// ---------------- ORIGINAL VIDEO PLAYER ----------------
  Widget _buildOriginalPlayer() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: _videoController!.value.size.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: VideoPlayer(_videoController!),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => setState(() {
                  _editorOpen = true;
                  _exportJustCompleted = false;
                }),
                // onPressed: () => setState(() => _editorOpen = true),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Video'),
              ),
              if (_outputPath != null)
                FilledButton.icon(
                  onPressed: _saveExported,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save Result'),
                ),
              if (_outputPath != null)
                OutlinedButton.icon(
                  onPressed: () async {
                    await _disposeResultController();
                    setState(() {
                      _outputPath = null;
                      _generationTime = Duration.zero;
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Discard Result'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultScreen() {
    final controller = _resultController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final screenHeight = MediaQuery.of(context).size.height;
    final videoHeight = min(screenHeight * 0.5, 360.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Edited Video',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Container(
            constraints: BoxConstraints(maxHeight: videoHeight),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: VideoPlayer(controller),
                  ),
                ),
                // Overlay play/pause button
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        controller.value.isPlaying
                            ? controller.pause()
                            : controller.play();
                      });
                    },
                    child: AnimatedOpacity(
                      opacity: controller.value.isPlaying ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        color: Colors.black26,
                        child: const Icon(Icons.play_circle_fill_rounded,
                            size: 80, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                // Progress bar and timestamp overlay
                Positioned(
                  bottom: 6,
                  left: 10,
                  right: 10,
                  child: Column(
                    children: [
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.orange,
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.black26,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(controller.value.position),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70),
                          ),
                          Text(
                            _formatDuration(controller.value.duration),
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: () => setState(() {
                  _editorOpen = true;
                  _exportJustCompleted = false;
                }),
                //onPressed: () => setState(() => _editorOpen = true),
                icon: const Icon(Icons.edit),
                label: const Text('Edit Again'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _saveExported,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Video'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '${d.inHours > 0 ? '${two(d.inHours)}:' : ''}$m:$s';
  }

  Widget _pickPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.movie_outlined, size: 80, color: Colors.white38),
          const SizedBox(height: 16),
          const Text(
            'No video selected.\nTap the button below to choose one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 16),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.video_call_outlined),
            label: const Text('Pick Video'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmExitEditing() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit editing?'),
        content: const Text('Your unsaved changes will be lost. Exit editor?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Exit')),
        ],
      ),
    );
    return res ?? false;
  }

  // ---------------- Cleanup ----------------
  Future<void> _disposeResultController() async {
    try {
      await _resultController?.dispose();
    } catch (_) {}
    _resultController = null;
  }

  Future<void> _clearLoadedVideo() async {
    await _disposeResultController();
    try {
      _videoController?.removeListener(_onPlaybackTick);
      await _videoController?.dispose();
    } catch (_) {}
    setState(() {
      _videoController = null;
      _proVideoController = null;
      _video = null;
      _outputPath = null;
      _generationTime = Duration.zero;
      _editorOpen = false;
      _thumbnails = null;
    });
  }

  Future<void> _disposeControllers() async {
    await _disposeResultController();
    try {
      _videoController?.removeListener(_onPlaybackTick);
      await _videoController?.dispose();
    } catch (_) {}
    _videoController = null;
    _proVideoController = null;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }
}

// ---------------- Inline helper widgets ----------------

class _VideoInitializingWidget extends StatelessWidget {
  const _VideoInitializingWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade900, Colors.black87],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_camera_back_rounded,
                size: 80, color: Colors.white70),
            SizedBox(height: 30),
            Text(
              'Initializing Video-Editor...',
              style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 24),
            SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}

class _VideoProgressAlert extends StatelessWidget {
  const _VideoProgressAlert({this.taskId = ''});
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(color: Colors.black54, dismissible: false),
        Center(
          child: AlertDialog(
            contentPadding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: StreamBuilder<ProgressModel>(
                stream: ProVideoEditor.instance.progressStreamById(taskId),
                builder: (context, snapshot) {
                  final progress = snapshot.data?.progress ?? 0.0;
                  return TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 300),
                    builder: (context, value, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(value: value),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${(value * 100).toStringAsFixed(1)} %',
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

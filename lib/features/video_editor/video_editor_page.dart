// lib/features/video_editor/video_editor_page.dart

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/ad_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/themed_native_ad.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
  final AdService _adService = AdService();

  // Controllers
  ProVideoController? _proVideoController;
  late final _editorKey = GlobalKey<ProImageEditorState>();

  // Original video playback
  VideoPlayerController? _videoController;
  late VideoMetadata _videoMetadata;

  // Exported result playback
  String? _outputPath;
  // ignore: unused_field
  Duration _generationTime = Duration.zero;
  VideoPlayerController? _resultController;

  // Thumbnails
  List<ImageProvider>? _thumbnails;
  final int _thumbnailCount = 7;

  // Trim state
  bool _isSeeking = false;
  TrimDurationSpan? _durationSpan;
  TrimDurationSpan? _pendingSeek;

  // UI state
  bool _isInitializing = false;
  bool _exportJustCompleted = false;
  bool _editorOpen = false;
  bool _isSaving = false;

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
    MediaKit.ensureInitialized();
    // Listen for ad-free status changes to hide/show native ads
    isAdFreeNotifier.addListener(_onAdFreeStatusChanged);
  }
  
  void _onAdFreeStatusChanged() {
    // Rebuild to hide/show native ads when ad-free status changes
    if (mounted) setState(() {});
  }

  // ---------------- Video Picking ----------------
  Future<void> _pickVideo() async {
    try {
      final source = await _showSourcePickerSheet();
      if (source == null) return;

      final picked = await ImagePicker().pickVideo(source: source);
      if (picked == null) return;

      await _disposeControllers();

      setState(() {
        _video = EditorVideo.file(File(picked.path));
        _outputPath = null;
        _thumbnails = null;
        _isInitializing = true;
        _durationSpan = null;
        _pendingSeek = null;
        _editorOpen = true;
        _exportJustCompleted = false;
      });

      await _initializeEditor();
    } catch (e) {
      debugPrint('❌ Error picking video: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking video: $e')),
        );
      }
    }
  }

  // ---------------- Themed Source Picker Bottom Sheet ----------------
  Future<ImageSource?> _showSourcePickerSheet() async {
    final cs = Theme.of(context).colorScheme;

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          LucideIcons.clapperboard,
                          color: cs.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Choose Video Source',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Options
                  Row(
                    children: [
                      // Gallery option
                      Expanded(
                        child: _buildPickerOption(
                          icon: LucideIcons.film,
                          label: 'Gallery',
                          sublabel: 'Choose from videos',
                          color: cs.primary,
                          onTap: () => Navigator.pop(context, ImageSource.gallery),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Camera option
                      Expanded(
                        child: _buildPickerOption(
                          icon: LucideIcons.video,
                          label: 'Camera',
                          sublabel: 'Record a new video',
                          color: cs.secondary,
                          onTap: () => Navigator.pop(context, ImageSource.camera),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Picker option card for bottom sheet
  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sublabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- Initialize Editor ----------------
  Future<void> _initializeEditor() async {
    if (_video == null) return;

    await _setMetadata();
    await _generateThumbnails();

    final realPath = await _video!.safeFilePath();

    _videoController = VideoPlayerController.file(File(realPath));

    await Future.wait([
      _videoController!.initialize(),
      _videoController!.setLooping(false),
      _videoController!.setVolume(_videoConfigs.initialMuted ? 0 : 1),
      _videoConfigs.initialPlay
          ? _videoController!.play()
          : _videoController!.pause()
    ]);

    _proVideoController = ProVideoController(
      videoPlayer: _buildVideoPlayer(),
      initialResolution: _videoMetadata.resolution,
      videoDuration: _videoMetadata.duration,
      fileSize: _videoMetadata.fileSize,
      thumbnails: _thumbnails,
    );

    _videoController!.addListener(_onPlaybackTick);

    if (mounted) setState(() => _isInitializing = false);
  }

  Future<void> _setMetadata() async {
    _videoMetadata = await ProVideoEditor.instance.getMetadata(_video!);
  }

  Future<void> _generateThumbnails() async {
    final screenW = MediaQuery.of(context).size.width;
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
    await Future.wait(imgs.map((e) => precacheImage(e, context)));

    _thumbnails = imgs;
    _proVideoController?.thumbnails = _thumbnails;
  }

  // ---------------- Playback Sync ----------------
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

    await _disposeResultController();

    final file = File(_outputPath!);
    if (await file.exists()) {
      _resultController = VideoPlayerController.file(file);
      await _resultController!.initialize();
      await _resultController!.setLooping(true);
      await _resultController!.play();
    }

    if (mounted) setState(() {});
  }

  // ---------------- Close Editor ----------------
  Future<void> _onCloseEditor(EditorMode mode) async {
    if (_exportJustCompleted && _outputPath != null) {
      await _prepareInlineResult();
      if (mounted) {
        setState(() {
          _editorOpen = false;
          _exportJustCompleted = false;
        });
      }
      return;
    }

    final ok = await _confirmExitEditing();
    if (!ok) return;

    await _clearLoadedVideo();
  }

  Future<void> _prepareInlineResult() async {
    await _disposeResultController();
    final file = File(_outputPath!);
    if (await file.exists()) {
      _resultController = VideoPlayerController.file(file);
      await _resultController!.initialize();
      await _resultController!.setLooping(true);
      await _resultController!.play();
    }
  }

  // ---------------- Save Exported Video ----------------
  Future<void> _saveExported() async {
    if (_outputPath == null) return;
    if (_isSaving) return;
    
    setState(() => _isSaving = true);
    
    try {
      // Show rewarded ad before allowing export
      final adCompleted = await _showExportAd();
      
      if (!adCompleted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(LucideIcons.alertCircle, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(child: Text('Please watch the ad to save your video')),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }
      
      // Ad completed - proceed with save
      final file = File(_outputPath!);
      if (!await file.exists()) return;

      final bytes = await file.readAsBytes();

      Uint8List? thumbBytes;
      try {
        final list = await ProVideoEditor.instance.getKeyFrames(
          KeyFramesConfigs(
            video: EditorVideo.file(file),
            outputSize: const Size.square(180),
            boxFit: ThumbnailBoxFit.cover,
            maxOutputFrames: 1,
            outputFormat: ThumbnailFormat.jpeg,
          ),
        );
        if (list.isNotEmpty) thumbBytes = list.first;
      } catch (_) {}

      await FileService.saveFile(
        context,
        bytes,
        extension: "mp4",
        customFileName: FileService.generateTimestampFilename("video", "mp4"),
        previewBytes: thumbBytes,
      );

      if (mounted && thumbBytes != null) {
        final img = MemoryImage(thumbBytes);
        await precacheImage(img, context);
        setState(() => _thumbnails = [img]);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  
  /// Shows a rewarded ad for export gate
  /// Returns true if ad was completed, false otherwise
  Future<bool> _showExportAd() async {
    // Pre-load ad if not ready
    if (!_adService.isAdReadyNotifier.value) {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Loading ad...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      await _adService.loadRewardedAd();
      
      // Wait for ad to load (with timeout)
      for (int i = 0; i < 10; i++) {
        if (_adService.isAdReadyNotifier.value) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Clear the loading snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }
      
      if (!_adService.isAdReadyNotifier.value) {
        // Ad failed to load - allow export anyway (better UX)
        debugPrint('⚠️ Ad failed to load, allowing export anyway');
        return true;
      }
    }
    
    // Show the ad
    return await _adService.showAdForFeatureGate();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        appBar: AppBar(
          title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
          actions: [
            if (_video != null && !_editorOpen)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
                onPressed: () => setState(() {
                  _editorOpen = true;
                  _exportJustCompleted = false;
                }),
              ),
            if (_outputPath != null && !_editorOpen)
              _isSaving
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.save_alt),
                      tooltip: 'Save to Gallery',
                      onPressed: _saveExported,
                    ),
          ],
        ),
        body: _buildBody(),
        floatingActionButton: _video == null
            ? GradientButton(
                label: 'Pick Video',
                icon: Icons.video_library_outlined,
                onPressed: _pickVideo,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildBody() {
    if (_video == null) return _buildEmptyStateWithAd();
    if (_isInitializing) return const _VideoInitializingWidget();
    if (_editorOpen) return _buildEditor();
    if (_outputPath != null && !_editorOpen) {
      return _buildResultScreen();
    }
    return _buildOriginalPlayer();
  }
  
  Widget _buildEmptyStateWithAd() {
    final showAds = shouldShowAds();
    
    return Column(
      children: [
        // Native ad at top (only if not ad-free)
        if (showAds)
          const ThemedNativeAd(
            height: 260,
            useSmallTemplate: false,
          ),
        // Placeholder in remaining space - with bottom padding for FAB
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 80), // Space for FAB
            child: _buildNoVideoPlaceholder(),
          ),
        ),
      ],
    );
  }

  // ---------------- EDITOR ----------------
  Widget _buildEditor() {
    return ProImageEditor.video(
      _proVideoController!,
      key: _editorKey,
      callbacks: ProImageEditorCallbacks(
        onCompleteWithParameters: _generateVideo,
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

  // ---------------- ORIGINAL PLAYER ----------------
  Widget _buildOriginalPlayer() {
    final controller = _videoController!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: VideoPlayer(controller),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            alignment: WrapAlignment.center,
            children: [
              GradientButton(
                label: "Edit Video",
                icon: Icons.edit,
                onPressed: () => setState(() => _editorOpen = true),
                variant: ButtonVariant.primary,
                size: ButtonSize.medium,
              ),
              if (_outputPath != null)
                GradientButton(
                  label: _isSaving ? "Saving..." : "Save Result",
                  icon: _isSaving ? null : Icons.save_alt,
                  onPressed: _isSaving ? null : _saveExported,
                  variant: ButtonVariant.success,
                  size: ButtonSize.medium,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // // ---------------- RESULT SCREEN ----------------
  Widget _buildResultScreen() {
    final controller = _resultController;
    final cs = Theme.of(context).colorScheme;

    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final videoHeight = min(screenHeight * 0.55, 360.0);
    final videoWidth = screenWidth; // full width

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 0),
      child: Center(
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
            const SizedBox(height: 12),

            // Video card
            Container(
              width: videoWidth,
              constraints: BoxConstraints(maxHeight: videoHeight),
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    cs.surface.withOpacity(0.9),
                    cs.surface.withOpacity(0.65),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(0.25),
                    blurRadius: 22,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias, // keeps overlay clipping clean
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Video fills entire available area, no rounding on video itself
                  AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),

                  // Play / Pause overlay
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
                          color: cs.surface.withOpacity(0.25),
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            size: 90,
                            color: cs.onSurface.withOpacity(0.85),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Progress bar and duration text
                  Positioned(
                    bottom: 8,
                    left: 12,
                    right: 12,
                    child: Column(
                      children: [
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: cs.primary,
                            bufferedColor: cs.onSurface.withOpacity(0.30),
                            backgroundColor: cs.onSurface.withOpacity(0.15),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(controller.value.position),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.70),
                              ),
                            ),
                            Text(
                              _formatDuration(controller.value.duration),
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withOpacity(0.70),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                GradientButton(
                  label: "Edit Again",
                  icon: Icons.edit,
                  onPressed: _isSaving ? null : () => setState(() => _editorOpen = true),
                  variant: ButtonVariant.secondary,
                  size: ButtonSize.medium,
                ),
                GradientButton(
                  label: _isSaving ? "Saving..." : "Save Video",
                  icon: _isSaving ? null : Icons.save_alt,
                  onPressed: _isSaving ? null : _saveExported,
                  variant: ButtonVariant.success,
                  size: ButtonSize.medium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- PLACEHOLDER ----------------
  Widget _buildNoVideoPlaceholder() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isDark
                ? [cs.surface.withOpacity(0.65), cs.surface.withOpacity(0.50)]
                : [cs.surface.withOpacity(0.85), cs.surface.withOpacity(0.70)],
          ),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.25),
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined,
                size: 56, color: cs.onSurface.withOpacity(0.38)),
            const SizedBox(height: 12),
            Text(
              'No video selected.\nTap the button below to choose one to start editing.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withOpacity(0.70),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- CONFIRM EXIT ----------------
  Future<bool> _confirmExitEditing() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmExitDialog(),
        )) ??
        false;
  }

  // ---------------- Back Handler ----------------
  Future<bool> _handleSystemBack() async {
    if (_editorOpen) {
      final ok = await _confirmExitEditing();
      if (ok) await _clearLoadedVideo();
      return false;
    }

    if (_outputPath != null && !_editorOpen) {
      setState(() => _editorOpen = true);
      return false;
    }

    return true;
  }

  // ---------------- Cleanup ----------------
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

  Future<void> _disposeResultController() async {
    try {
      await _resultController?.dispose();
    } catch (_) {}
    _resultController = null;
  }

  @override
  void dispose() {
    isAdFreeNotifier.removeListener(_onAdFreeStatusChanged);
    _disposeControllers();
    super.dispose();
  }

  // ---------------- Helpers ----------------
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

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '${d.inHours > 0 ? '${two(d.inHours)}:' : ''}$m:$s';
  }
}

// ---------------- Helper Widgets ----------------

// Confirm exit dialog
class _ConfirmExitDialog extends StatelessWidget {
  const _ConfirmExitDialog();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Exit editing?',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      content: Text('Your unsaved changes will be lost. Exit editor?',
          style: t.bodyMedium),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        GradientButton(
          label: "Exit",
          onPressed: () => Navigator.pop(context, true),
          variant: ButtonVariant.danger,
          size: ButtonSize.small,
        ),
      ],
    );
  }
}

// Initial loading screen (theme-adaptive)
class _VideoInitializingWidget extends StatelessWidget {
  const _VideoInitializingWidget();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [
                  cs.surface.withOpacity(0.95),
                  cs.surface.withOpacity(0.80),
                ]
              : [
                  cs.surface.withOpacity(0.98),
                  cs.surface.withOpacity(0.92),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_camera_back_rounded,
                size: 80, color: cs.onSurface.withOpacity(0.70)),
            const SizedBox(height: 30),
            Text(
              'Initializing Video-Editor...',
              style: TextStyle(
                fontSize: 18,
                color: cs.onSurface.withOpacity(0.70),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 60,
              height: 60,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

// Video Progress Alert
// 📹 Clean Video Progress Overlay (no stretched dialog)
class _VideoProgressAlert extends StatelessWidget {
  const _VideoProgressAlert({this.taskId = ''});
  final String taskId;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        // Dim background overlay
        ModalBarrier(
          color: cs.surface.withOpacity(0.35),
          dismissible: false,
        ),

        // Center floating progress HUD
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: cs.surface.withOpacity(0.95),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: StreamBuilder<ProgressModel>(
              stream: ProVideoEditor.instance.progressStreamById(taskId),
              builder: (context, snap) {
                final progress = snap.data?.progress ?? 0.0;
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: progress),
                  duration: const Duration(milliseconds: 250),
                  builder: (_, value, __) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: value,
                                strokeWidth: 5,
                                color: cs.primary,
                                backgroundColor: cs.onSurface.withOpacity(0.15),
                              ),
                              Text(
                                '',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '',
                          style: TextStyle(
                            fontSize: 15,
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// class _VideoProgressAlert extends StatelessWidget {
//   const _VideoProgressAlert({this.taskId = ''});
//   final String taskId;

//   @override
//   Widget build(BuildContext context) {
//     final cs = Theme.of(context).colorScheme;
//     return Stack(
//       children: [
//         ModalBarrier(
//           color: cs.surface.withOpacity(0.4),
//           dismissible: false,
//         ),
//         Center(
//           child: AlertDialog(
//             contentPadding:
//                 const EdgeInsets.symmetric(vertical: 20, horizontal: 22),
//             shape: RoundedRectangleBorder(
//               borderRadius: BorderRadius.circular(20),
//             ),
//             content: ConstrainedBox(
//               constraints: const BoxConstraints(maxWidth: 500),
//               child: StreamBuilder<ProgressModel>(
//                 stream: ProVideoEditor.instance.progressStreamById(taskId),
//                 builder: (context, snap) {
//                   final progress = snap.data?.progress ?? 0.0;
//                   return TweenAnimationBuilder<double>(
//                     tween: Tween(begin: 0, end: progress),
//                     duration: const Duration(milliseconds: 250),
//                     builder: (_, value, __) {
//                       return Row(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           SizedBox(
//                             width: 26,
//                             height: 26,
//                             child: CircularProgressIndicator(
//                               value: value,
//                               color: cs.primary,
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Text(
//                             '${(value * 100).toStringAsFixed(1)} %',
//                             style: TextStyle(
//                                 fontSize: 18,
//                                 color: cs.onSurface,
//                                 fontWeight: FontWeight.w600),
//                           ),
//                         ],
//                       );
//                     },
//                   );
//                 },
//               ),
//             ),
//           ),
//         ),
//       ],
//     );
//   }
// }

// lib/features/video_editor/video_editor_page.dart
//
// CapCut-style professional video editor page.
// Replaces the old ProImageEditor.video() wrapper with a custom 3-zone layout:
//   1. Preview Player  (top ~42%)
//   2. Multi-Track Timeline  (middle ~38%)
//   3. Bottom Toolbar + Sliding Tool Panels  (bottom)
//
// Preserves: video picking, ad-gate export, save-to-gallery, MediaEditorPage API.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/ad_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/themed_native_ad.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:video_player/video_player.dart';

import 'models/clip_model.dart' hide Clip;
import 'models/project_model.dart';
import 'services/export_service.dart';
import 'state/editor_providers.dart';
import 'state/playback_notifier.dart';
import 'state/tool_notifier.dart';
import 'widgets/preview/preview_player.dart';
import 'widgets/timeline/timeline_panel.dart';
import 'widgets/toolbar/bottom_toolbar.dart';

class VideoEditorPage extends ConsumerStatefulWidget {
  /// Whether to show the AppBar. Set to false when nested in MediaEditorPage.
  final bool showAppBar;

  const VideoEditorPage({super.key, this.showAppBar = true});

  @override
  ConsumerState<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends ConsumerState<VideoEditorPage> {
  // ─── Services ──────────────────────────────────────────────────────────────
  final AdService _adService = AdService();

  // ─── Video state ───────────────────────────────────────────────────────────
  File? _videoFile;
  VideoPlayerController? _videoController;
  bool _isInitializing = false;
  bool _editorOpen = false;

  // ─── Export state ──────────────────────────────────────────────────────────
  String? _outputPath;
  bool _isSaving = false;
  bool _isExporting = false;
  double _exportProgress = 0;
  VideoPlayerController? _resultController;

  // ─── Audio players ─────────────────────────────────────────────────────────
  final Map<String, Player> _audioPlayers = {};

  // ─── Listeners ─────────────────────────────────────────────────────────────
  Timer? _positionTimer;
  bool _isSyncingFromController = false;
  final List<ProviderSubscription> _providerSubscriptions = [];

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    isAdFreeNotifier.addListener(_onAdFreeStatusChanged);
  }

  void _onAdFreeStatusChanged() {
    if (mounted) setState(() {});
  }

  // =========================================================================
  //  VIDEO PICKING  (preserved from original)
  // =========================================================================

  Future<void> _pickVideo() async {
    try {
      final source = await _showSourcePickerSheet();
      if (source == null) return;

      final picked = await ImagePicker().pickVideo(source: source);
      if (picked == null) return;

      await _disposeControllers();

      setState(() {
        _videoFile = File(picked.path);
        _outputPath = null;
        _isInitializing = true;
        _editorOpen = true;
      });

      await _initializeEditor();
    } catch (e) {
      debugPrint('Error picking video: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking video: $e')),
        );
      }
    }
  }

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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
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
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(LucideIcons.clapperboard,
                            color: cs.primary, size: 22),
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
                  Row(
                    children: [
                      Expanded(
                        child: _buildPickerOption(
                          icon: LucideIcons.film,
                          label: 'Gallery',
                          sublabel: 'Choose from videos',
                          color: cs.primary,
                          onTap: () =>
                              Navigator.pop(context, ImageSource.gallery),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildPickerOption(
                          icon: LucideIcons.video,
                          label: 'Camera',
                          sublabel: 'Record a new video',
                          color: cs.secondary,
                          onTap: () =>
                              Navigator.pop(context, ImageSource.camera),
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
            border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
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
              Text(label,
                  style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(sublabel,
                  style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 12),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================================
  //  EDITOR INITIALIZATION
  // =========================================================================

  Future<void> _initializeEditor() async {
    if (_videoFile == null) return;

    try {
      // Get video metadata via pro_video_editor
      final video = EditorVideo.file(_videoFile!);
      final metadata = await ProVideoEditor.instance.getMetadata(video);

      // Initialize video player controller
      _videoController = VideoPlayerController.file(_videoFile!);
      await _videoController!.initialize();
      await _videoController!.setLooping(false);
      await _videoController!.setVolume(1.0); // start with full volume

      // Create the project in state
      final projectId = 'proj_${DateTime.now().microsecondsSinceEpoch}';
      ref.read(projectProvider.notifier).createProject(
            projectId: projectId,
            videoPath: _videoFile!.path,
            videoDuration: metadata.duration,
            width: metadata.resolution.width,
            height: metadata.resolution.height,
          );

      // Set playback duration
      ref
          .read(playbackProvider.notifier)
          .setTotalDuration(metadata.duration);

      // Auto-add an audio track representing the video's embedded audio
      final audioTrackId = '${projectId}_audio_embedded';
      ref.read(projectProvider.notifier).addTrack(
            Track(
              id: audioTrackId,
              type: TrackType.audio,
              name: 'Original Audio',
            ),
          );
      // Add a clip representing the embedded audio
      ref.read(projectProvider.notifier).addClipToTrack(
            audioTrackId,
            AudioClip(
              id: '${projectId}_audio_embedded_clip',
              startTime: Duration.zero,
              duration: metadata.duration,
              sourcePath: _videoFile!.path,
              trimStart: Duration.zero,
              trimEnd: metadata.duration,
              originalDuration: metadata.duration,
              volume: 1.0,
              name: 'Video Audio',
            ),
          );

      // Auto-select the first video clip so tools work immediately
      final firstClipId = '${projectId}_clip_0';
      final firstTrackId = '${projectId}_video_0';
      ref.read(timelineProvider.notifier).selectClip(firstClipId, trackId: firstTrackId);
      ref.read(projectProvider.notifier).selectClip(firstClipId);

      // Generate thumbnails asynchronously (don't block initialization)
      _generateThumbnails(_videoFile!, metadata.duration);

      // Start position sync timer
      _startPositionSync();

      // Listen for export trigger from ExportPanel (listenManual: safe outside build)
      _providerSubscriptions.add(
        ref.listenManual<int>(exportTriggerProvider, (prev, next) {
          if (prev != null && next > prev) {
            _startExport();
          }
        }),
      );

      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      debugPrint('Editor init error: $e');
      if (mounted) {
        setState(() => _isInitializing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to initialize editor: $e')),
        );
      }
    }
  }

  /// Periodically sync the video_player position to our playback state.
  void _startPositionSync() {
    _positionTimer?.cancel();
    // Clean up any previous subscriptions to avoid duplicates on re-init
    for (final sub in _providerSubscriptions) {
      sub.close();
    }
    _providerSubscriptions.clear();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_videoController == null || !_videoController!.value.isInitialized) {
        return;
      }
      // Don't overwrite position while user is dragging the playhead
      final tlState = ref.read(timelineProvider);
      if (tlState.isDraggingPlayhead) return;

      final pos = _videoController!.value.position;
      final playback = ref.read(playbackProvider);
      if ((pos - playback.position).abs() > const Duration(milliseconds: 80)) {
        _isSyncingFromController = true;
        ref.read(playbackProvider.notifier).setPosition(pos);
        _isSyncingFromController = false;
      }
      // Sync audio players with current position
      _syncAudioPlayback();
    });

    // Listen for seek requests (e.g. from timeline playhead drag)
    // and forward them to the video controller.
    // Using listenManual because we're outside build().
    _providerSubscriptions.add(
      ref.listenManual<PlaybackState>(playbackProvider, (prev, next) {
        if (_isSyncingFromController) return;
        if (_videoController == null || !_videoController!.value.isInitialized) return;
        final diff = (next.position - _videoController!.value.position).abs();
        if (diff > const Duration(milliseconds: 80)) {
          _videoController!.seekTo(next.position);
        }
      }),
    );

    // Listen for speed changes on the selected video clip.
    // Note: audio volume is NOT synced here — it comes from the
    // embedded AudioClip, handled in _syncEmbeddedAudioVolume().
    _providerSubscriptions.add(
      ref.listenManual(selectedClipProvider, (prev, next) {
        if (next is VideoClip && _videoController != null && _videoController!.value.isInitialized) {
          // Sync speed
          final speed = next.speedEffect.speed.clamp(0.25, 5.0);
          if ((_videoController!.value.playbackSpeed - speed).abs() > 0.01) {
            _videoController!.setPlaybackSpeed(speed);
          }
        }
      }),
    );

    // Listen for project changes to manage audio players.
    // fireImmediately so existing clips get Players on setup.
    _providerSubscriptions.add(
      ref.listenManual<VideoProject?>(projectProvider, (prev, next) {
        if (next != null) {
          _syncAudioPlayers(next);
        }
      }, fireImmediately: true),
    );
  }

  /// Sync audio players with the current project state.
  ///
  /// Only creates media_kit Players for **imported** audio clips.
  /// The embedded video audio (same sourcePath as the main video) is
  /// handled by [_videoController] directly, so we skip it here to
  /// avoid double-playing the video's own audio.
  ///
  /// Also syncs the embedded audio clip's volume to [_videoController].
  void _syncAudioPlayers(VideoProject project) {
    final audioClipIds = <String>{};
    final videoPath = _videoFile?.path;

    // Track whether we found the embedded audio clip & its effective volume.
    bool embeddedAudioFound = false;
    double embeddedAudioVolume = 0.0;

    for (final track in project.audioTracks) {
      for (final clip in track.clips) {
        if (clip is AudioClip) {
          // Embedded video audio – handled by the video controller
          if (videoPath != null && clip.sourcePath == videoPath) {
            if (!track.isMuted) {
              embeddedAudioFound = true;
              embeddedAudioVolume = clip.volume;
            }
            // else: track muted → embedded volume stays 0
            continue;
          }

          // Skip muted tracks for imported audio
          if (track.isMuted) continue;

          audioClipIds.add(clip.id);
          // Create player if it doesn't exist
          if (!_audioPlayers.containsKey(clip.id)) {
            final player = Player();
            _audioPlayers[clip.id] = player;
            // Open the media, then set volume once the stream is ready
            player.open(Media(clip.sourcePath), play: false).then((_) {
              player.setVolume(clip.volume * 100);
            });
          } else {
            // Update volume
            _audioPlayers[clip.id]!.setVolume(clip.volume * 100);
          }
        }
      }
    }

    // Sync the embedded audio volume to the video controller.
    // If the embedded clip was removed or its track is muted, mute the video controller.
    if (_videoController != null && _videoController!.value.isInitialized) {
      final targetVol = embeddedAudioFound ? embeddedAudioVolume : 0.0;
      if ((_videoController!.value.volume - targetVol).abs() > 0.01) {
        _videoController!.setVolume(targetVol);
      }
    }

    // Remove players for clips that no longer exist
    final toRemove = _audioPlayers.keys.where((id) => !audioClipIds.contains(id)).toList();
    for (final id in toRemove) {
      _audioPlayers[id]?.dispose();
      _audioPlayers.remove(id);
    }
  }

  // Track last synced position per audio player to avoid seeking storm
  final Map<String, Duration> _lastAudioSyncPos = {};
  final Map<String, bool> _audioPlayingState = {};

  /// Sync audio players' playback state with the video.
  void _syncAudioPlayback() {
    final project = ref.read(projectProvider);
    final playback = ref.read(playbackProvider);
    if (project == null) return;

    for (final track in project.audioTracks) {
      if (track.isMuted) continue;
      for (final clip in track.clips) {
        if (clip is AudioClip) {
          final player = _audioPlayers[clip.id];
          if (player == null) continue;

          final pos = playback.position;
          if (pos >= clip.startTime && pos < clip.endTime) {
            // Clip should be playing
            final clipPosition = pos - clip.startTime + clip.trimStart;
            if (playback.isPlaying) {
              // Only seek if we're far from the expected position (>500ms)
              final lastSync = _lastAudioSyncPos[clip.id] ?? Duration.zero;
              final drift = (clipPosition - lastSync).abs();
              if (drift > const Duration(milliseconds: 500)) {
                player.seek(clipPosition);
                _lastAudioSyncPos[clip.id] = clipPosition;
              } else {
                // Let it play naturally, just update tracking
                _lastAudioSyncPos[clip.id] = clipPosition;
              }
              // Start playing if not already
              if (_audioPlayingState[clip.id] != true) {
                player.play();
                _audioPlayingState[clip.id] = true;
              }
            } else {
              if (_audioPlayingState[clip.id] != false) {
                player.pause();
                _audioPlayingState[clip.id] = false;
              }
            }
          } else {
            // Clip should not be playing
            if (_audioPlayingState[clip.id] != false) {
              player.pause();
              _audioPlayingState[clip.id] = false;
            }
            _lastAudioSyncPos.remove(clip.id);
          }
        }
      }
    }
  }

  // =========================================================================
  //  THUMBNAIL GENERATION
  // =========================================================================

  Future<void> _generateThumbnails(File file, Duration duration) async {
    try {
      final video = EditorVideo.file(file);
      final thumbs = await ProVideoEditor.instance.getKeyFrames(
        KeyFramesConfigs(
          video: video,
          outputSize: const Size.square(48),
          boxFit: ThumbnailBoxFit.cover,
          maxOutputFrames: 10,
          outputFormat: ThumbnailFormat.jpeg,
        ),
      );

      if (thumbs.isNotEmpty && mounted) {
        // Update the first video clip with thumbnails
        final project = ref.read(projectProvider);
        if (project != null) {
          for (final track in project.videoTracks) {
            for (final clip in track.clips) {
              if (clip is VideoClip) {
                ref.read(projectProvider.notifier).updateClip(
                      clip.id,
                      (c) => (c as VideoClip).copyWith(thumbnails: thumbs),
                    );
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Thumbnail generation failed: $e');
    }
  }

  // =========================================================================
  //  EXPORT  (preserved ad-gate + FileService save logic)
  // =========================================================================

  Future<void> _startExport() async {
    final project = ref.read(projectProvider);
    if (project == null) return;

    setState(() {
      _isExporting = true;
      _exportProgress = 0;
    });

    // Pause playback
    _videoController?.pause();
    ref.read(playbackProvider.notifier).pause();

    try {
      final result = await ExportService.exportProject(
        project: project,
        onProgress: (p) {
          if (mounted) setState(() => _exportProgress = p);
        },
      );

      _outputPath = result ?? _videoFile?.path;

      // Prepare result preview
      if (_outputPath != null) {
        await _disposeResultController();
        final file = File(_outputPath!);
        if (await file.exists()) {
          try {
            _resultController = VideoPlayerController.file(file);
            await _resultController!.initialize();
            await _resultController!.setLooping(true);
            await _resultController!.play();
          } catch (playerErr) {
            debugPrint('Result player init failed: $playerErr');
            // Still show the result screen; save button will work even if preview doesn't
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Export complete! Tap Save Video to save.'),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isExporting = false;
        _editorOpen = false;
      });
    }
  }

  /// Save exported video to gallery (with ad gate).
  Future<void> _saveExported() async {
    if (_outputPath == null || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      // Ad gate – but don't block save if ad fails to load
      final adCompleted = await _showExportAd();
      if (!adCompleted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(LucideIcons.alertCircle, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                      child:
                          Text('Saving video...')),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        // Continue saving anyway – ad is a soft gate
      }

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

      if (!mounted) return;

      await FileService.saveFile(
        context,
        bytes,
        extension: "mp4",
        customFileName:
            FileService.generateTimestampFilename("video", "mp4"),
        previewBytes: thumbBytes,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Save failed: $e")),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Shows a rewarded ad for export gate (preserved from original).
  Future<bool> _showExportAd() async {
    if (!shouldRequireHeavyTierRewardedAd()) return true;

    if (!_adService.isAdReadyNotifier.value) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
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

      for (int i = 0; i < 10; i++) {
        if (_adService.isAdReadyNotifier.value) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (!_adService.isAdReadyNotifier.value) return true;
    }

    return await _adService.showAdForFeatureGate();
  }

  // =========================================================================
  //  BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmExitApp();
        if (ok && mounted) SystemNavigator.pop();
      },
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title:
                    const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
                actions: [
                  if (_videoFile != null && !_editorOpen)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      tooltip: 'Edit',
                      onPressed: () => setState(() {
                        _editorOpen = true;
                      }),
                    ),
                  if (_outputPath != null && !_editorOpen)
                    _isSaving
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.save_alt),
                            tooltip: 'Save to Gallery',
                            onPressed: _saveExported,
                          ),
                ],
              )
            : null,
        body: Stack(
          children: [
            _buildBody(),

            // Floating action buttons when AppBar hidden (nested in MediaEditorPage)
            if (!widget.showAppBar &&
                _videoFile != null &&
                !_editorOpen)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildActionButton(
                      icon: Icons.edit,
                      tooltip: 'Edit',
                      onPressed: () => setState(() => _editorOpen = true),
                    ),
                    if (_outputPath != null) ...[
                      const SizedBox(width: 8),
                      _isSaving
                          ? _buildLoadingButton()
                          : _buildActionButton(
                              icon: Icons.save_alt,
                              tooltip: 'Save to Gallery',
                              onPressed: _saveExported,
                              isPrimary: true,
                            ),
                    ],
                  ],
                ),
              ),

            // Export progress overlay
            if (_isExporting) _buildExportOverlay(),
          ],
        ),
        floatingActionButton: _videoFile == null
            ? GradientButton(
                label: 'Pick Video',
                icon: Icons.video_library_outlined,
                onPressed: _pickVideo,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
              )
            : null,
        floatingActionButtonLocation:
            FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildBody() {
    if (_videoFile == null) return _buildEmptyStateWithAd();
    if (_isInitializing) return const _VideoInitializingWidget();
    if (_editorOpen) return _buildEditor();
    if (_outputPath != null) return _buildResultScreen();
    return _buildOriginalPlayer();
  }

  // =========================================================================
  //  THE NEW EDITOR (3-zone CapCut layout)
  // =========================================================================

  Widget _buildEditor() {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ─── Top bar ──────────────────────────────────────────────
        _buildEditorTopBar(cs),

        // ─── Preview Player ───────────────────────────────────────
        Expanded(
          flex: 42,
          child: PreviewPlayer(controller: _videoController),
        ),

        // ─── Timeline ─────────────────────────────────────────────
        const Expanded(
          flex: 38,
          child: TimelinePanel(),
        ),

        // ─── Bottom Toolbar ───────────────────────────────────────
        const BottomToolbar(),
      ],
    );
  }

  Widget _buildEditorTopBar(ColorScheme cs) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.onSurface.withOpacity(0.08)),
        ),
      ),
      child: Row(
        children: [
          // Close
          IconButton(
            icon: Icon(LucideIcons.x, size: 20, color: cs.onSurface),
            tooltip: 'Close Editor',
            onPressed: _onCloseEditor,
          ),

          const Spacer(),

          // Project name
          Text(
            'Video Editor',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),

          const Spacer(),

          // Export button – opens the ExportPanel settings first
          FilledButton.icon(
            onPressed: _isExporting
                ? null
                : () => BottomToolbar.openToolSheet(context, ref, EditorTool.export),
            icon: const Icon(LucideIcons.download, size: 16),
            label: const Text('Export', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              minimumSize: Size.zero,
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onCloseEditor() async {
    final ok = await _confirmExitEditing();
    if (!ok) return;

    // Close any open tool panel
    ref.read(toolProvider.notifier).closePanel();

    // Cancel timers & subscriptions
    _positionTimer?.cancel();
    for (final sub in _providerSubscriptions) {
      sub.close();
    }
    _providerSubscriptions.clear();

    // Dispose all controllers (video, result, audio)
    await _disposeControllers();

    // Clear all project state so we go back to the "Pick Video" screen
    ref.read(projectProvider.notifier).clearProject();
    ref.read(playbackProvider.notifier).setPosition(Duration.zero);
    ref.read(playbackProvider.notifier).setTotalDuration(Duration.zero);
    ref.read(timelineProvider.notifier).clearSelection();

    setState(() {
      _videoFile = null;
      _outputPath = null;
      _editorOpen = false;
      _isExporting = false;
      _exportProgress = 0;
    });
  }

  // =========================================================================
  //  EMPTY STATE / PLACEHOLDER / RESULT (preserved from original)
  // =========================================================================

  Widget _buildEmptyStateWithAd() {
    final showAds = shouldShowNativeBannerAds();
    return Column(
      children: [
        if (showAds)
          const ThemedNativeAd(height: 260, useSmallTemplate: false),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 80),
            child: _buildNoVideoPlaceholder(),
          ),
        ),
      ],
    );
  }

  Widget _buildNoVideoPlaceholder() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding:
            const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isDark
                ? [
                    cs.surface.withOpacity(0.65),
                    cs.surface.withOpacity(0.50)
                  ]
                : [
                    cs.surface.withOpacity(0.85),
                    cs.surface.withOpacity(0.70)
                  ],
          ),
          border:
              Border.all(color: cs.outlineVariant.withOpacity(0.25)),
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

  Widget _buildResultScreen() {
    final controller = _resultController;
    final cs = Theme.of(context).colorScheme;
    final hasVideo = controller != null && controller.value.isInitialized;

    final screenHeight = MediaQuery.of(context).size.height;
    final videoHeight = min(screenHeight * 0.55, 360.0);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Column(
          children: [
            Text(
              'Edited Video',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (hasVideo)
              Container(
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
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
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
                    Positioned(
                      bottom: 8,
                      left: 12,
                      right: 12,
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: cs.primary,
                          bufferedColor:
                              cs.onSurface.withOpacity(0.30),
                          backgroundColor:
                              cs.onSurface.withOpacity(0.15),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                height: videoHeight,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.video_file, size: 48, color: cs.onSurface.withOpacity(0.4)),
                      const SizedBox(height: 8),
                      Text(
                        'Video exported successfully.\nPreview not available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurface.withOpacity(0.5), fontSize: 13),
                      ),
                    ],
                  ),
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
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _editorOpen = true),
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

  // =========================================================================
  //  OVERLAYS & HELPERS
  // =========================================================================

  Widget _buildExportOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(0.3),
                blurRadius: 20,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: CircularProgressIndicator(
                  value: _exportProgress > 0 ? _exportProgress : null,
                  strokeWidth: 5,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Exporting...',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_exportProgress > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '${(_exportProgress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isPrimary ? cs.primary : cs.surface.withOpacity(0.9),
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(icon,
              size: 22,
              color: isPrimary ? cs.onPrimary : cs.onSurface),
        ),
      ),
    );
  }

  Widget _buildLoadingButton() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  // ─── Dialogs ───────────────────────────────────────────────────────────────

  Future<bool> _confirmExitEditing() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmExitDialog(),
        )) ??
        false;
  }

  Future<bool> _confirmExitApp() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmExitAppDialog(),
        )) ??
        false;
  }

  // ─── Cleanup ───────────────────────────────────────────────────────────────

  Future<void> _disposeControllers() async {
    _positionTimer?.cancel();
    await _disposeResultController();
    try {
      await _videoController?.dispose();
    } catch (_) {}
    _videoController = null;
    // Dispose audio players
    for (final player in _audioPlayers.values) {
      try {
        await player.dispose();
      } catch (_) {}
    }
    _audioPlayers.clear();
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
    _positionTimer?.cancel();
    // Close all Riverpod subscriptions created via listenManual
    for (final sub in _providerSubscriptions) {
      sub.close();
    }
    _providerSubscriptions.clear();
    _disposeControllers();
    super.dispose();
  }
}

// =============================================================================
//  HELPER WIDGETS (preserved from original)
// =============================================================================

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

class _ConfirmExitAppDialog extends StatelessWidget {
  const _ConfirmExitAppDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.logOut, size: 40, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'Exit App?',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Are you sure you want to exit?',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Exit',
                icon: LucideIcons.logOut,
                onPressed: () => Navigator.pop(context, true),
                variant: ButtonVariant.danger,
                size: ButtonSize.medium,
                expanded: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

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
                  cs.surface.withOpacity(0.80)
                ]
              : [
                  cs.surface.withOpacity(0.98),
                  cs.surface.withOpacity(0.92)
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
              'Initializing Video Editor...',
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

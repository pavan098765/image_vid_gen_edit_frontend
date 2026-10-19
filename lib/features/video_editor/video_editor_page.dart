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
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/media_source_picker_sheet.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/themed_native_ad.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:pro_video_editor/pro_video_editor.dart';
import 'package:video_player/video_player.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/media_editor/editor_tab_launch.dart';

import 'models/clip_model.dart' hide Clip;
import 'models/project_model.dart';
import 'services/export_service.dart';
import 'services/thumbnail_cache_service.dart';
import 'services/video_project_store.dart';
import 'utils/playback_mapping.dart';
import 'utils/speed_timeline_mapping.dart';
import 'state/editor_providers.dart';
import 'state/playback_notifier.dart';
import 'state/tool_notifier.dart';
import 'widgets/preview/preview_player.dart';
import 'widgets/timeline/timeline_panel.dart';
import 'widgets/toolbar/bottom_toolbar.dart';

enum VideoEditorInitialTool { none, text, export }

class VideoEditorPage extends ConsumerStatefulWidget {
  /// Whether to show the AppBar. Set to false when nested in MediaEditorPage.
  final bool showAppBar;
  final String? initialVideoPath;
  final String? initialStickerPath;
  final VideoEditorInitialTool initialTool;
  final ExportSettings? initialExport;
  final bool useExistingProject;
  final String? jobId;

  /// When false, this page is the hidden side of the photo/video toggle and
  /// must not answer the system back button.
  final bool handlesSystemBack;

  const VideoEditorPage({
    super.key,
    this.showAppBar = true,
    this.initialVideoPath,
    this.initialStickerPath,
    this.initialTool = VideoEditorInitialTool.none,
    this.initialExport,
    this.useExistingProject = false,
    this.jobId,
    this.handlesSystemBack = true,
  });

  @override
  ConsumerState<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends ConsumerState<VideoEditorPage>
    with WidgetsBindingObserver {
  // ─── Services ──────────────────────────────────────────────────────────────
  final AdService _adService = AdService();

  // ─── Video state ───────────────────────────────────────────────────────────
  File? _videoFile;
  VideoPlayerController? _videoController;
  bool _isInitializing = false;
  bool _editorOpen = false;
  bool _allowRoutePop = false;
  bool _openedInitialTool = false;
  bool _returnToResultManager = false;
  String? _sessionJobId;
  int _restoreTabIndex = 0;
  int _seenLaunchId = 0;

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
  DateTime? _playClock;
  final List<ProviderSubscription> _providerSubscriptions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MediaKit.ensureInitialized();
    isAdFreeNotifier.addListener(_onAdFreeStatusChanged);
    editorTabLaunchNotifier.addListener(_onEditorTabLaunch);
    final path = widget.initialVideoPath;
    if (path != null && path.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInitialVideo(path);
      });
    }
  }

  Future<void> _openInitialVideo(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open that video.")),
        );
      }
      return;
    }
    setState(() {
      _videoFile = file;
      _outputPath = null;
      _isInitializing = true;
      _editorOpen = true;
    });
    await _initializeEditor(skipCreateProject: widget.useExistingProject);
    _applyInitialExportAndTool();
  }

  void _applyInitialExportAndTool() {
    if (!mounted) return;
    if (widget.initialExport != null) {
      ref
          .read(projectProvider.notifier)
          .updateExportSettings(widget.initialExport!);
    }
    if (_openedInitialTool) return;
    _openedInitialTool = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (widget.initialTool) {
        case VideoEditorInitialTool.text:
          BottomToolbar.openToolSheet(context, EditorTool.text);
          break;
        case VideoEditorInitialTool.export:
          BottomToolbar.openToolSheet(context, EditorTool.export);
          break;
        case VideoEditorInitialTool.none:
          break;
      }
      _placeInitialSticker();
    });
  }

  void _placeInitialSticker() {
    final path = widget.initialStickerPath;
    if (path == null || path.isEmpty) return;
    if (!File(path).existsSync()) return;
    final project = ref.read(projectProvider);
    if (project == null) return;
    final already = project.stickerTracks.any(
      (t) => t.clips.any((c) => c is StickerClip && c.stickerData == path),
    );
    if (already) return;
    ref.read(projectProvider.notifier).addImageSticker(
          path,
          duration: project.totalDuration > Duration.zero
              ? project.totalDuration
              : const Duration(seconds: 3),
        );
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

      _sessionJobId = null;
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

  Future<ImageSource?> _showSourcePickerSheet() {
    return showMediaSourcePickerBottomSheet(
      context,
      title: 'Add a video',
      galleryLabel: 'Videos',
      gallerySublabel: 'Choose from gallery',
      cameraSublabel: 'Record a new video',
      galleryIcon: LucideIcons.film,
      cameraIcon: LucideIcons.video,
    );
  }

  // =========================================================================
  //  EDITOR INITIALIZATION
  // =========================================================================

  Future<void> _initializeEditor({bool skipCreateProject = false}) async {
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

      if (!skipCreateProject) {
        final jobId = _activeJobId;
        VideoProject? restored;
        if (jobId != null && jobId.isNotEmpty) {
          restored = await VideoProjectStore.loadForJob(jobId);
        }
        if (restored != null) {
          ref.read(projectProvider.notifier).replaceProject(restored);
          ref
              .read(playbackProvider.notifier)
              .setTotalDuration(restored.totalDuration);
        } else {
        // Create the project in state
        final projectId = jobId ?? 'proj_${DateTime.now().microsecondsSinceEpoch}';
        ref.read(projectProvider.notifier).createProject(
              projectId: projectId,
              videoPath: _videoFile!.path,
              videoDuration: metadata.duration,
              width: metadata.resolution.width,
              height: metadata.resolution.height,
            );

        ref.read(playbackProvider.notifier).setTotalDuration(metadata.duration);

        final audioTrackId = '${projectId}_audio_embedded';
        ref.read(projectProvider.notifier).addTrack(
              Track(
                id: audioTrackId,
                type: TrackType.audio,
                name: 'Original Audio',
              ),
            );
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

        final firstClipId = '${projectId}_clip_0';
        final firstTrackId = '${projectId}_video_0';
        ref
            .read(timelineProvider.notifier)
            .selectClip(firstClipId, trackId: firstTrackId);
        ref.read(projectProvider.notifier).selectClip(firstClipId);
        }
      } else {
        final project = ref.read(projectProvider);
        ref
            .read(playbackProvider.notifier)
            .setTotalDuration(project?.totalDuration ?? metadata.duration);
      }

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

      _placeInitialSticker();

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

  /// Drive the playhead from the file while a clip is showing, and by the
  /// wall clock through gaps so a split does not restart playback.
  void _onPlaybackTick() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (ref.read(timelineProvider).isDraggingPlayhead) {
      _playClock = null;
      return;
    }

    final project = ref.read(projectProvider);
    if (project == null) return;
    final playback = ref.read(playbackProvider);
    if (!playback.isPlaying) {
      _playClock = null;
      _syncAudioPlayers(project);
      _syncAudioPlayback();
      return;
    }

    final total = project.computeTotalDuration();
    if (controller.value.isCompleted) {
      _finishPlayback(controller, total);
      return;
    }

    final pos = playback.position;
    final active = activeVideoClipAt(project, pos);
    if (active == null) {
      _advanceThroughGap(controller, project, pos, total);
      return;
    }

    var filePos = controller.value.position;
    if (filePos < active.trimStart) {
      controller.seekTo(active.trimStart);
      filePos = active.trimStart;
    } else if (filePos >= active.trimEnd) {
      if (_handoffAtClipEnd(controller, project, active)) return;
    }

    final timeline = timelinePositionForSource(project, filePos, pos);
    if ((timeline - pos).abs() > const Duration(milliseconds: 40)) {
      _setPlayhead(timeline);
    }

    final atClip = activeVideoClipAt(
      project,
      ref.read(playbackProvider).position,
    );
    if (atClip != null) {
      final speed = instantaneousPlaybackSpeed(
        atClip,
        ref.read(playbackProvider).position,
      ).clamp(0.25, 5.0);
      if ((controller.value.playbackSpeed - speed).abs() > 0.01) {
        controller.setPlaybackSpeed(speed);
      }
      if (!controller.value.isPlaying) controller.play();
    }

    _syncAudioPlayers(project);
    _syncAudioPlayback();
  }

  /// Returns true when this tick already placed the playhead (gap, seek, or end).
  bool _handoffAtClipEnd(
    VideoPlayerController controller,
    VideoProject project,
    VideoClip active,
  ) {
    final nextClip = nextVideoClipAfter(project, active);
    if (nextClip == null) {
      _finishPlayback(controller, project.computeTotalDuration());
      return true;
    }

    final gap = nextClip.startTime - active.endTime;
    final snapped = gap <= const Duration(milliseconds: 80) &&
        gap >= const Duration(milliseconds: -40);
    final filePos = controller.value.position;
    final sameFileContinues = snapped &&
        nextClip.sourcePath == active.sourcePath &&
        filePos >= nextClip.trimStart &&
        filePos < nextClip.trimEnd;
    if (sameFileContinues) return false;

    if (snapped && nextClip.sourcePath == active.sourcePath) {
      final enter = active.endTime;
      _setPlayhead(enter);
      controller.seekTo(sourcePositionForTimeline(nextClip, enter));
      if (!controller.value.isPlaying) controller.play();
      _syncAudioPlayers(project);
      _syncAudioPlayback();
      return true;
    }

    // A real gap, or a following clip this player cannot show: hold and stay quiet.
    controller.pause();
    _setPlayhead(active.endTime);
    _playClock = DateTime.now();
    _syncAudioPlayers(project);
    _syncAudioPlayback();
    return true;
  }

  void _advanceThroughGap(
    VideoPlayerController controller,
    VideoProject project,
    Duration pos,
    Duration total,
  ) {
    final now = DateTime.now();
    final elapsed =
        _playClock == null ? Duration.zero : now.difference(_playClock!);
    _playClock = now;
    if (controller.value.isPlaying) controller.pause();

    var nextPos = pos + elapsed;
    if (total > Duration.zero && nextPos >= total) {
      _finishPlayback(controller, total);
      return;
    }

    VideoClip? upcoming;
    for (final clip in sortedVideoClips(project)) {
      if (clip.startTime >= pos) {
        upcoming = clip;
        break;
      }
    }

    if (upcoming != null && nextPos >= upcoming.startTime) {
      nextPos = upcoming.startTime;
      if (upcoming.sourcePath == _videoFile?.path) {
        controller.seekTo(sourcePositionForTimeline(upcoming, nextPos));
        if (!controller.value.isPlaying) controller.play();
      }
      _playClock = null;
    }
    _setPlayhead(nextPos);
    _syncAudioPlayers(project);
    _syncAudioPlayback();
  }

  void _finishPlayback(VideoPlayerController controller, Duration total) {
    controller.pause();
    ref.read(playbackProvider.notifier).pause();
    final end = total > Duration.zero
        ? total - const Duration(microseconds: 1)
        : Duration.zero;
    _setPlayhead(end);
    _playClock = null;
    _syncAudioPlayback();
  }

  void _setPlayhead(Duration position) {
    _isSyncingFromController = true;
    ref.read(playbackProvider.notifier).setPosition(position);
    _isSyncingFromController = false;
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
      _onPlaybackTick();
    });

    // Listen for seek requests (e.g. from timeline playhead drag)
    // and forward them to the video controller.
    // Using listenManual because we're outside build().
    _providerSubscriptions.add(
      ref.listenManual<PlaybackState>(playbackProvider, (prev, next) {
        if (_isSyncingFromController) return;
        if (_videoController == null ||
            !_videoController!.value.isInitialized) {
          return;
        }
        final project = ref.read(projectProvider);
        if (project == null) return;

        final clip = activeVideoClipAt(project, next.position);
        if (clip == null) return;

        final fpTarget = sourcePositionForTimeline(clip, next.position);
        final diff = (fpTarget - _videoController!.value.position).abs();
        if (diff > const Duration(milliseconds: 80)) {
          _videoController!.seekTo(fpTarget);
        }
      }),
    );

    // Listen for speed changes on the selected video clip.
    // Note: audio volume is NOT synced here — it comes from the
    // embedded AudioClip, handled in _syncEmbeddedAudioVolume().
    _providerSubscriptions.add(
      ref.listenManual(selectedClipProvider, (prev, next) {
        if (next is VideoClip &&
            _videoController != null &&
            _videoController!.value.isInitialized) {
          final pos = ref.read(playbackProvider).position;
          final speed = instantaneousPlaybackSpeed(next, pos).clamp(0.25, 5.0);
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
          ref
              .read(playbackProvider.notifier)
              .setTotalDuration(next.computeTotalDuration());
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
    final pos = ref.read(playbackProvider).position;

    // Embedded video audio: any AudioClip whose source matches a video clip path.
    // Sorted by startTime; overlapping intervals: last clip in sort order wins.
    final videoSources = <String>{};
    for (final t in project.videoTracks) {
      for (final c in t.clips) {
        if (c is VideoClip) videoSources.add(c.sourcePath);
      }
    }
    final embeddedFamily = <AudioClip>[];
    for (final track in project.audioTracks) {
      if (track.isMuted) continue;
      for (final clip in track.clips) {
        if (clip is AudioClip && videoSources.contains(clip.sourcePath)) {
          embeddedFamily.add(clip);
        }
      }
    }
    embeddedFamily.sort((a, b) {
      final c = a.startTime.compareTo(b.startTime);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });

    double targetVol;
    if (embeddedFamily.isEmpty) {
      var embeddedOnMutedTrackOnly = false;
      for (final track in project.audioTracks) {
        if (!track.isMuted) continue;
        for (final clip in track.clips) {
          if (clip is AudioClip && videoSources.contains(clip.sourcePath)) {
            embeddedOnMutedTrackOnly = true;
            break;
          }
        }
      }
      targetVol = embeddedOnMutedTrackOnly ? 0.0 : 1.0;
    } else {
      var inClip = false;
      var v = 1.0;
      for (final clip in embeddedFamily) {
        if (pos >= clip.startTime && pos < clip.endTime) {
          inClip = true;
          v = clip.volume;
        }
      }
      // A gap between clips stays silent instead of leaking the file's audio.
      targetVol = inClip ? v : 0.0;
    }

    for (final track in project.audioTracks) {
      for (final clip in track.clips) {
        if (clip is AudioClip) {
          // Embedded video audio – handled by the video controller
          if (videoSources.contains(clip.sourcePath)) {
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
    if (_videoController != null && _videoController!.value.isInitialized) {
      if ((_videoController!.value.volume - targetVol).abs() > 0.01) {
        _videoController!.setVolume(targetVol);
      }
    }

    // Remove players for clips that no longer exist
    final toRemove =
        _audioPlayers.keys.where((id) => !audioClipIds.contains(id)).toList();
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
      final thumbs = await ThumbnailCacheService.generateKeyFramesForFile(file);

      if (thumbs.isNotEmpty && mounted) {
        final project = ref.read(projectProvider);
        if (project != null) {
          for (final track in project.videoTracks) {
            for (final clip in track.clips) {
              if (clip is VideoClip && clip.sourcePath == file.path) {
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                  Expanded(child: Text('Saving video...')),
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
        customFileName: FileService.generateTimestampFilename("video", "mp4"),
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
      canPop: _allowRoutePop || !widget.handlesSystemBack,
      onPopInvokedWithResult: (didPop, _) async {
        if (!widget.handlesSystemBack || didPop || _allowRoutePop) return;
        if (selectedIndexNotifier.value == AppTabs.editor &&
            _returnToResultManager &&
            _videoFile != null) {
          await _onCloseEditor();
          return;
        }
        if (Navigator.of(context).canPop()) {
          if (_editorOpen) {
            final ok = await _confirmExitEditing();
            if (!ok || !mounted) return;
            await _closeProject(leaveRoute: false);
          }
          if (!mounted) return;
          setState(() => _allowRoutePop = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
          return;
        }
        final ok = await _confirmExitApp();
        if (ok && mounted) SystemNavigator.pop();
      },
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
                actions: [
                  if (_editorOpen)
                    IconButton(
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Open',
                      onPressed: _openProject,
                    ),
                  if (_editorOpen)
                    IconButton(
                      icon: const Icon(Icons.save),
                      tooltip: 'Save',
                      onPressed: () => _autosave(notify: true),
                    ),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
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
            if (!widget.showAppBar && _videoFile != null && !_editorOpen)
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
                label: 'Add a video',
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
        if (ref.watch(projectProvider)?.videoTracks.every((t) => t.clips.isEmpty) ??
            true)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text(
              'Add a video to start.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
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
          bottom: BorderSide(color: cs.onSurface.withValues(alpha: 0.08)),
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
                : () => BottomToolbar.openToolSheet(
                    context, EditorTool.export),
            icon: const Icon(LucideIcons.download, size: 16),
            label: const Text('Export', style: TextStyle(fontSize: 13)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
    if (!ok || !mounted) return;
    if (_returnToResultManager) {
      final tab = _restoreTabIndex;
      _returnToResultManager = false;
      _sessionJobId = null;
      returnEditorSessionToResultManager(
        restoreTabIndex: tab,
        onCovered: () {
          if (mounted) _closeProject(leaveRoute: false);
        },
      );
      return;
    }
    await _closeProject(leaveRoute: false);
    if (!mounted || !Navigator.of(context).canPop()) return;
    setState(() => _allowRoutePop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  /// Clears the open project and returns to the empty editor.
  /// When this page was pushed on its own, also leaves the screen.
  Future<void> _closeProject({required bool leaveRoute}) async {
    ref.read(toolProvider.notifier).closePanel();

    _positionTimer?.cancel();
    for (final sub in _providerSubscriptions) {
      sub.close();
    }
    _providerSubscriptions.clear();

    await _disposeControllers();
    if (!mounted) return;

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

    if (leaveRoute && widget.showAppBar && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  // =========================================================================
  //  EMPTY STATE / PLACEHOLDER / RESULT (preserved from original)
  // =========================================================================

  Widget _buildEmptyStateWithAd() {
    final showAds = shouldShowNativeBannerAds();
    return Column(
      children: [
        if (showAds) const ThemedNativeAd(height: 260, useSmallTemplate: false),
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
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: isDark
                ? [cs.surface.withValues(alpha: 0.65), cs.surface.withValues(alpha: 0.50)]
                : [cs.surface.withValues(alpha: 0.85), cs.surface.withValues(alpha: 0.70)],
          ),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined,
                size: 56, color: cs.onSurface.withValues(alpha: 0.38)),
            const SizedBox(height: 12),
            Text(
              widget.initialStickerPath != null
                  ? 'Add a video. This sticker goes on it.'
                  : 'Add a video to start.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.70),
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
                      cs.surface.withValues(alpha: 0.9),
                      cs.surface.withValues(alpha: 0.65),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withValues(alpha: 0.25),
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
                            color: cs.surface.withValues(alpha: 0.25),
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 90,
                              color: cs.onSurface.withValues(alpha: 0.85),
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
                          bufferedColor: cs.onSurface.withValues(alpha: 0.30),
                          backgroundColor: cs.onSurface.withValues(alpha: 0.15),
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
                      Icon(Icons.video_file,
                          size: 48, color: cs.onSurface.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Text(
                        'Video exported successfully.\nPreview not available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  GradientButton(
                    label: _isSaving ? 'Saving...' : 'Save Video',
                    icon: _isSaving ? null : Icons.save_alt,
                    onPressed: _isSaving ? null : _saveExported,
                    variant: ButtonVariant.success,
                    size: ButtonSize.medium,
                    expanded: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          label: 'Edit Again',
                          icon: Icons.edit,
                          onPressed: _isSaving
                              ? null
                              : () => setState(() => _editorOpen = true),
                          variant: ButtonVariant.secondary,
                          size: ButtonSize.medium,
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GradientButton(
                          label: 'Close',
                          icon: Icons.close,
                          onPressed: _isSaving
                              ? null
                              : () => _closeProject(leaveRoute: true),
                          variant: ButtonVariant.outline,
                          size: ButtonSize.medium,
                          expanded: true,
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
                color: cs.shadow.withValues(alpha: 0.3),
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
                    color: cs.onSurface.withValues(alpha: 0.6),
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
      color: isPrimary ? cs.primary : cs.surface.withValues(alpha: 0.9),
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
              size: 22, color: isPrimary ? cs.onPrimary : cs.onSurface),
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
        color: cs.surface.withValues(alpha: 0.9),
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _autosave();
    }
  }

  Future<void> _autosave({bool notify = false}) async {
    final project = ref.read(projectProvider);
    if (project == null) return;
    final id = _activeJobId ?? project.id;
    try {
      await VideoProjectStore.save(project.copyWith(id: id));
      if (notify && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Project saved')),
        );
      }
    } catch (e) {
      debugPrint('Video project save failed: $e');
    }
  }

  Future<void> _openProject() async {
    final ids = await VideoProjectStore.listIds();
    if (!mounted) return;
    if (ids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No saved projects yet.')),
      );
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Open project'),
        children: [
          for (final id in ids)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, id),
              child: Text(id),
            ),
        ],
      ),
    );
    if (picked == null) return;
    final loaded = await VideoProjectStore.load(picked);
    if (loaded == null || !mounted) return;
    ref.read(projectProvider.notifier).replaceProject(loaded);
    ref.read(playbackProvider.notifier).setTotalDuration(loaded.totalDuration);
  }

  String? get _activeJobId {
    final session = _sessionJobId;
    if (session != null && session.isNotEmpty) return session;
    return widget.jobId;
  }

  void _onEditorTabLaunch() {
    final launch = editorTabLaunchNotifier.value;
    if (launch == null || launch.id == _seenLaunchId) return;
    _seenLaunchId = launch.id;
    final path = launch.videoPath;
    if (path == null || path.isEmpty) {
      _returnToResultManager = false;
      return;
    }
    _returnToResultManager = launch.returnToResultManager;
    _sessionJobId = launch.jobId;
    _restoreTabIndex = launch.restoreTabIndex;
    _openedInitialTool = false;
    _openLaunchedVideo(path);
  }

  Future<void> _openLaunchedVideo(String path) async {
    await _disposeControllers();
    if (!mounted) return;
    await _openInitialVideo(path);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autosave();
    editorTabLaunchNotifier.removeListener(_onEditorTabLaunch);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
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
              ? [cs.surface.withValues(alpha: 0.95), cs.surface.withValues(alpha: 0.80)]
              : [cs.surface.withValues(alpha: 0.98), cs.surface.withValues(alpha: 0.92)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_camera_back_rounded,
                size: 80, color: cs.onSurface.withValues(alpha: 0.70)),
            const SizedBox(height: 30),
            Text(
              'Initializing Video Editor...',
              style: TextStyle(
                fontSize: 18,
                color: cs.onSurface.withValues(alpha: 0.70),
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

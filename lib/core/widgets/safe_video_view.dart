import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// How a ready frame is sized inside its parent.
enum SafeVideoLayout {
  /// Scales the real frame. The parent must give a bounded box.
  fitted,

  /// Uses the frame's aspect ratio. Safe in a vertical scroll view.
  aspect,
}

/// True when [controller] has a real frame.
/// A paused activity can leave `isInitialized` set and the size at 0x0.
bool videoFrameIsReady(VideoPlayerController? controller) {
  if (controller == null) return false;
  try {
    final value = controller.value;
    final size = value.size;
    return value.isInitialized &&
        !value.hasError &&
        size.width > 0 &&
        size.height > 0 &&
        size.width.isFinite &&
        size.height.isFinite;
  } catch (_) {
    return false;
  }
}

/// True when an initialized player has lost its frame and must be opened again.
/// A player that is still opening is left alone.
bool videoNeedsRestart(VideoPlayerController? controller) {
  if (controller == null) return false;
  try {
    final value = controller.value;
    if (value.hasError) return true;
    if (!value.isInitialized) return false;
    return !videoFrameIsReady(controller);
  } catch (_) {
    return true;
  }
}

/// Pauses [controller]. A missing or already-closed player is ignored.
Future<void> pauseVideoController(VideoPlayerController? controller) async {
  if (controller == null) return;
  try {
    await controller.pause();
  } catch (_) {}
}

/// Opens a new player for the same source when the frame is gone.
///
/// Returns the controller the caller should keep. When a new player is
/// returned, the caller disposes [controller] after it has swapped the
/// reference. [initialize] cannot be called twice on one controller.
Future<VideoPlayerController?> replaceDeadVideo(
  VideoPlayerController? controller, {
  bool play = false,
}) async {
  if (controller == null) return null;
  if (!videoNeedsRestart(controller)) {
    if (play) {
      try {
        await controller.play();
      } catch (_) {}
    }
    return controller;
  }
  final next = await _openCopy(controller, play: play);
  if (next == null) return controller;
  return next;
}

/// Shows [fallback] until the player has a positive frame, then the video.
///
/// Rebuilds only when that readiness changes, so a 0x0 size never reaches
/// [FittedBox] or [AspectRatio].
class SafeVideoView extends StatefulWidget {
  final VideoPlayerController? controller;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;
  final SafeVideoLayout layout;

  /// Crop factors applied to the frame size. Values that are not positive
  /// keep [fallback] on screen.
  final double widthFactor;
  final double heightFactor;

  /// Replaces the plain [VideoPlayer] once the frame is ready.
  final Widget Function(VideoPlayerController controller)? frameBuilder;

  const SafeVideoView({
    super.key,
    required this.controller,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.layout = SafeVideoLayout.fitted,
    this.widthFactor = 1,
    this.heightFactor = 1,
    this.frameBuilder,
  });

  @override
  State<SafeVideoView> createState() => _SafeVideoViewState();
}

class _SafeVideoViewState extends State<SafeVideoView> {
  var _ready = false;

  @override
  void initState() {
    super.initState();
    _follow(widget.controller);
  }

  @override
  void didUpdateWidget(SafeVideoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    _unfollow(oldWidget.controller);
    _follow(widget.controller);
  }

  @override
  void dispose() {
    _unfollow(widget.controller);
    super.dispose();
  }

  void _follow(VideoPlayerController? controller) {
    _ready = videoFrameIsReady(controller);
    if (controller == null) return;
    try {
      controller.addListener(_onFrame);
    } catch (_) {
      _ready = false;
    }
  }

  void _unfollow(VideoPlayerController? controller) {
    if (controller == null) return;
    try {
      controller.removeListener(_onFrame);
    } catch (_) {}
  }

  void _onFrame() {
    final ready = videoFrameIsReady(widget.controller);
    if (ready == _ready || !mounted) return;
    setState(() => _ready = ready);
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.controller;
    if (!_ready || current == null || !videoFrameIsReady(current)) {
      return widget.fallback;
    }
    final size = current.value.size;
    final width = size.width * widget.widthFactor;
    final height = size.height * widget.heightFactor;
    if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) {
      return widget.fallback;
    }
    final Widget child;
    try {
      child = widget.frameBuilder?.call(current) ?? VideoPlayer(current);
    } catch (_) {
      return widget.fallback;
    }
    if (widget.layout == SafeVideoLayout.aspect) {
      return AspectRatio(aspectRatio: width / height, child: child);
    }
    return FittedBox(
      fit: widget.fit,
      alignment: widget.alignment,
      child: SizedBox(width: width, height: height, child: child),
    );
  }
}

Future<VideoPlayerController?> _openCopy(
  VideoPlayerController controller, {
  required bool play,
}) async {
  final looping = _flag(controller, (value) => value.isLooping);
  final volume = _flag(controller, (value) => value.volume);
  final speed = _flag(controller, (value) => value.playbackSpeed);
  final position = _flag(controller, (value) => value.position);
  final next = _copyController(controller);
  try {
    await next.initialize();
    if (!videoFrameIsReady(next)) {
      await next.dispose();
      return null;
    }
    await _restorePlayback(
      next,
      looping: looping,
      volume: volume,
      speed: speed,
      position: position,
      play: play,
    );
    return next;
  } catch (_) {
    try {
      await next.dispose();
    } catch (_) {}
    return null;
  }
}

T? _flag<T>(VideoPlayerController controller, T Function(VideoPlayerValue) read) {
  try {
    return read(controller.value);
  } catch (_) {
    return null;
  }
}

Future<void> _restorePlayback(
  VideoPlayerController controller, {
  required bool? looping,
  required double? volume,
  required double? speed,
  required Duration? position,
  required bool play,
}) async {
  try {
    if (looping != null) await controller.setLooping(looping);
    if (volume != null) await controller.setVolume(volume);
    if (speed != null && speed > 0 && (speed - 1).abs() > 0.01) {
      await controller.setPlaybackSpeed(speed);
    }
    final duration = controller.value.duration;
    if (position != null &&
        position > Duration.zero &&
        position < duration) {
      await controller.seekTo(position);
    }
    if (play) await controller.play();
  } catch (_) {}
}

VideoPlayerController _copyController(VideoPlayerController controller) {
  switch (controller.dataSourceType) {
    case DataSourceType.file:
      return VideoPlayerController.file(
        File(Uri.parse(controller.dataSource).toFilePath()),
        videoPlayerOptions: controller.videoPlayerOptions,
        httpHeaders: controller.httpHeaders,
        viewType: controller.viewType,
      );
    case DataSourceType.contentUri:
      return VideoPlayerController.contentUri(
        Uri.parse(controller.dataSource),
        videoPlayerOptions: controller.videoPlayerOptions,
        viewType: controller.viewType,
      );
    case DataSourceType.asset:
      return VideoPlayerController.asset(
        controller.dataSource,
        package: controller.package,
        videoPlayerOptions: controller.videoPlayerOptions,
        viewType: controller.viewType,
      );
    case DataSourceType.network:
      return VideoPlayerController.networkUrl(
        Uri.parse(controller.dataSource),
        formatHint: controller.formatHint,
        videoPlayerOptions: controller.videoPlayerOptions,
        httpHeaders: controller.httpHeaders,
        viewType: controller.viewType,
      );
  }
}

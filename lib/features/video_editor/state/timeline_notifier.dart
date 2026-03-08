// lib/features/video_editor/state/timeline_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/editor_constants.dart';

/// Timeline viewport state.
class TimelineState {
  /// Current zoom level (1.0 = default).
  final double zoom;

  /// Horizontal scroll offset in pixels.
  final double scrollOffset;

  /// ID of the currently selected clip (or null).
  final String? selectedClipId;

  /// ID of the currently selected track (or null).
  final String? selectedTrackId;

  /// Whether the user is currently dragging the playhead.
  final bool isDraggingPlayhead;

  /// Whether the user is currently resizing a clip.
  final bool isResizingClip;

  /// Whether the user is currently dragging a clip.
  final bool isDraggingClip;

  const TimelineState({
    this.zoom = EditorConstants.defaultZoom,
    this.scrollOffset = 0,
    this.selectedClipId,
    this.selectedTrackId,
    this.isDraggingPlayhead = false,
    this.isResizingClip = false,
    this.isDraggingClip = false,
  });

  TimelineState copyWith({
    double? zoom,
    double? scrollOffset,
    String? selectedClipId,
    String? selectedTrackId,
    bool? isDraggingPlayhead,
    bool? isResizingClip,
    bool? isDraggingClip,
    bool clearSelection = false,
  }) {
    return TimelineState(
      zoom: zoom ?? this.zoom,
      scrollOffset: scrollOffset ?? this.scrollOffset,
      selectedClipId: clearSelection ? null : (selectedClipId ?? this.selectedClipId),
      selectedTrackId: clearSelection ? null : (selectedTrackId ?? this.selectedTrackId),
      isDraggingPlayhead: isDraggingPlayhead ?? this.isDraggingPlayhead,
      isResizingClip: isResizingClip ?? this.isResizingClip,
      isDraggingClip: isDraggingClip ?? this.isDraggingClip,
    );
  }

  /// Pixels per second at the current zoom level.
  double get pixelsPerSecond => EditorConstants.pixelsPerSecondBase * zoom;
}

/// Manages timeline viewport state.
class TimelineNotifier extends StateNotifier<TimelineState> {
  TimelineNotifier() : super(const TimelineState());

  void setZoom(double z) {
    final clamped = z.clamp(EditorConstants.minZoom, EditorConstants.maxZoom);
    state = state.copyWith(zoom: clamped);
  }

  void zoomIn() => setZoom(state.zoom * 1.25);
  void zoomOut() => setZoom(state.zoom / 1.25);

  void setScrollOffset(double offset) {
    state = state.copyWith(scrollOffset: offset.clamp(0, double.infinity));
  }

  void selectClip(String clipId, {String? trackId}) {
    state = state.copyWith(selectedClipId: clipId, selectedTrackId: trackId);
  }

  void clearSelection() {
    state = state.copyWith(clearSelection: true);
  }

  void setDraggingPlayhead(bool v) {
    state = state.copyWith(isDraggingPlayhead: v);
  }

  void setResizingClip(bool v) {
    state = state.copyWith(isResizingClip: v);
  }

  void setDraggingClip(bool v) {
    state = state.copyWith(isDraggingClip: v);
  }

  void reset() => state = const TimelineState();
}

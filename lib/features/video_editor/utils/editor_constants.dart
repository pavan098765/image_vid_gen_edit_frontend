// lib/features/video_editor/utils/editor_constants.dart

import 'package:flutter/material.dart';

/// Constants for the professional video editor layout & behaviour.
class EditorConstants {
  EditorConstants._();

  // ---------------------------------------------------------------------------
  //  LAYOUT
  // ---------------------------------------------------------------------------

  /// Fraction of screen height for the preview player area.
  static const double previewHeightFraction = 0.42;

  /// Minimum height for the timeline panel.
  static const double timelineMinHeight = 180;

  /// Maximum height for the timeline panel.
  static const double timelineMaxHeight = 320;

  /// Height of the bottom toolbar icon row.
  static const double toolbarHeight = 56;

  /// Max height of a tool panel that slides up above the toolbar.
  static const double toolPanelMaxHeight = 300;

  /// Duration of slide-up / slide-down animations.
  static const Duration panelAnimDuration = Duration(milliseconds: 280);

  /// Curve used for panel open/close.
  static const Curve panelAnimCurve = Curves.easeOutCubic;

  // ---------------------------------------------------------------------------
  //  TIMELINE
  // ---------------------------------------------------------------------------

  /// Height of a single track row in the timeline.
  static const double trackHeight = 52;

  /// Height of the time ruler bar at the top of the timeline.
  static const double rulerHeight = 28;

  /// Width in logical pixels that represents 1 second at zoom = 1.0.
  static const double pixelsPerSecondBase = 60.0;

  /// Minimum zoom level for the timeline.
  static const double minZoom = 0.25;

  /// Maximum zoom level for the timeline.
  static const double maxZoom = 8.0;

  /// Default zoom level.
  static const double defaultZoom = 1.0;

  /// Width of the track label gutter on the left.
  static const double trackLabelWidth = 44;

  /// Snap threshold (in pixels) when dragging clips or playhead.
  static const double snapThresholdPx = 6;

  /// Minimum clip width in pixels (prevents clips from becoming invisible).
  static const double minClipWidthPx = 16;

  /// Width of resize handles on clips.
  static const double clipResizeHandleWidth = 10;

  // ---------------------------------------------------------------------------
  //  PLAYHEAD
  // ---------------------------------------------------------------------------

  /// Width of the playhead line.
  static const double playheadWidth = 2;

  /// Radius of the playhead knob at the top.
  static const double playheadKnobRadius = 7;

  // ---------------------------------------------------------------------------
  //  CLIPS
  // ---------------------------------------------------------------------------

  /// Corner radius for clip widgets.
  static const double clipBorderRadius = 6;

  /// Height of the thumbnail strip inside a video clip.
  static const double clipThumbnailHeight = 40;

  /// Padding inside a clip widget.
  static const EdgeInsets clipPadding = EdgeInsets.symmetric(horizontal: 2, vertical: 2);

  // ---------------------------------------------------------------------------
  //  COLORS  (editor-specific; brand colours live in app_theme)
  // ---------------------------------------------------------------------------

  static const Color videoTrackColor = Color(0xFF5C6BC0);     // Indigo
  static const Color audioTrackColor = Color(0xFF66BB6A);     // Green
  static const Color textTrackColor = Color(0xFFFFCA28);      // Amber
  static const Color stickerTrackColor = Color(0xFFEF5350);   // Red
  static const Color pipTrackColor = Color(0xFF26C6DA);       // Cyan

  static const Color playheadColor = Color(0xFFFF5252);       // Red accent
  static const Color selectionColor = Color(0x447B5EFF);      // Semi-transparent purple
  static const Color snapLineColor = Color(0xFFFFD740);       // Yellow snap guide

  // ---------------------------------------------------------------------------
  //  EXPORT DEFAULTS
  // ---------------------------------------------------------------------------

  static const int defaultBitrate = 8000000;  // 8 Mbps
  static const int defaultFps = 30;
  static const String defaultFormat = 'mp4';

  // ---------------------------------------------------------------------------
  //  TRANSITIONS
  // ---------------------------------------------------------------------------

  /// Default transition duration.
  static const Duration defaultTransitionDuration = Duration(milliseconds: 500);

  /// Maximum transition duration.
  static const Duration maxTransitionDuration = Duration(seconds: 3);

  // ---------------------------------------------------------------------------
  //  SPEED
  // ---------------------------------------------------------------------------

  static const double minSpeed = 0.1;
  static const double maxSpeed = 10.0;
  static const double defaultSpeed = 1.0;

  // ---------------------------------------------------------------------------
  //  THUMBNAILS
  // ---------------------------------------------------------------------------

  /// Number of thumbnails to generate per clip for the timeline strip.
  static const int timelineThumbnailCount = 10;

  /// Size (square) of each timeline thumbnail in logical pixels.
  static const double timelineThumbnailSize = 48;
}

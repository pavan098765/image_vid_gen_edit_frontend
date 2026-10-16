// lib/features/video_editor/state/tool_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Available tools in the bottom toolbar.
enum EditorTool {
  none,
  trim,
  text,
  audio,
  filter,
  transition,
  speed,
  sticker,
  pip,
  export,
  keyframe,
  more,
  chroma,
}

extension EditorToolX on EditorTool {
  String get label {
    switch (this) {
      case EditorTool.none:
        return '';
      case EditorTool.trim:
        return 'Trim';
      case EditorTool.text:
        return 'Text';
      case EditorTool.audio:
        return 'Audio';
      case EditorTool.filter:
        return 'Filters';
      case EditorTool.transition:
        return 'Effects';
      case EditorTool.speed:
        return 'Speed';
      case EditorTool.sticker:
        return 'Sticker';
      case EditorTool.pip:
        return 'PiP';
      case EditorTool.export:
        return 'Export';
      case EditorTool.keyframe:
        return 'Animate';
      case EditorTool.more:
        return 'More';
      case EditorTool.chroma:
        return 'Key';
    }
  }

  String get iconName {
    switch (this) {
      case EditorTool.none:
        return 'circle';
      case EditorTool.trim:
        return 'scissors';
      case EditorTool.text:
        return 'type';
      case EditorTool.audio:
        return 'music';
      case EditorTool.filter:
        return 'palette';
      case EditorTool.transition:
        return 'layers';
      case EditorTool.speed:
        return 'gauge';
      case EditorTool.sticker:
        return 'smile';
      case EditorTool.pip:
        return 'picture_in_picture';
      case EditorTool.export:
        return 'download';
      case EditorTool.keyframe:
        return 'key';
      case EditorTool.more:
        return 'more';
      case EditorTool.chroma:
        return 'aperture';
    }
  }
}

/// Tool panel state.
class ToolState {
  /// The currently active tool (determines which panel is open).
  final EditorTool activeTool;

  /// Whether the panel is expanded / visible.
  final bool isPanelOpen;

  const ToolState({
    this.activeTool = EditorTool.none,
    this.isPanelOpen = false,
  });

  ToolState copyWith({
    EditorTool? activeTool,
    bool? isPanelOpen,
  }) {
    return ToolState(
      activeTool: activeTool ?? this.activeTool,
      isPanelOpen: isPanelOpen ?? this.isPanelOpen,
    );
  }
}

/// Manages which tool panel is open.
class ToolNotifier extends StateNotifier<ToolState> {
  ToolNotifier() : super(const ToolState());

  void openTool(EditorTool tool) {
    if (state.activeTool == tool && state.isPanelOpen) {
      // Toggle off if same tool tapped again
      state = state.copyWith(activeTool: EditorTool.none, isPanelOpen: false);
    } else {
      state = state.copyWith(activeTool: tool, isPanelOpen: true);
    }
  }

  /// Opens [tool] without toggling. Used by the modal sheet, which closes itself.
  void activate(EditorTool tool) {
    state = state.copyWith(activeTool: tool, isPanelOpen: true);
  }

  void closePanel() {
    state = state.copyWith(activeTool: EditorTool.none, isPanelOpen: false);
  }

  void reset() => state = const ToolState();
}

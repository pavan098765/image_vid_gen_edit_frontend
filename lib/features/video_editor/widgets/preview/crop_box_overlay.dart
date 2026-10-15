import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/clip_model.dart';
import '../../state/editor_providers.dart';
import '../../state/tool_notifier.dart';

/// Drag-corner crop box shown while Trim is open on a video clip.
class CropBoxOverlay extends ConsumerWidget {
  const CropBoxOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tool = ref.watch(toolProvider);
    if (tool.activeTool != EditorTool.trim) return const SizedBox.shrink();
    final clip = ref.watch(selectedClipProvider);
    if (clip is! VideoClip) return const SizedBox.shrink();
    final crop = clip.cropNorm ?? const Rect.fromLTWH(0, 0, 1, 1);

    return LayoutBuilder(builder: (context, constraints) {
      final box = Rect.fromLTWH(
        crop.left * constraints.maxWidth,
        crop.top * constraints.maxHeight,
        crop.width * constraints.maxWidth,
        crop.height * constraints.maxHeight,
      );
      return Stack(
        children: [
          Positioned.fromRect(
            rect: box,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
          ),
          _handle(ref, clip, constraints, box.topLeft, Alignment.topLeft),
          _handle(ref, clip, constraints, box.topRight, Alignment.topRight),
          _handle(ref, clip, constraints, box.bottomLeft, Alignment.bottomLeft),
          _handle(
              ref, clip, constraints, box.bottomRight, Alignment.bottomRight),
        ],
      );
    });
  }

  Widget _handle(
    WidgetRef ref,
    VideoClip clip,
    BoxConstraints constraints,
    Offset pos,
    Alignment corner,
  ) {
    return Positioned(
      left: pos.dx - 10,
      top: pos.dy - 10,
      child: GestureDetector(
        onPanUpdate: (d) {
          final nx = d.delta.dx / constraints.maxWidth;
          final ny = d.delta.dy / constraints.maxHeight;
          var r = clip.cropNorm ?? const Rect.fromLTWH(0, 0, 1, 1);
          if (corner == Alignment.topLeft) {
            r = Rect.fromLTRB(
              (r.left + nx).clamp(0.0, r.right - 0.05),
              (r.top + ny).clamp(0.0, r.bottom - 0.05),
              r.right,
              r.bottom,
            );
          } else if (corner == Alignment.topRight) {
            r = Rect.fromLTRB(
              r.left,
              (r.top + ny).clamp(0.0, r.bottom - 0.05),
              (r.right + nx).clamp(r.left + 0.05, 1.0),
              r.bottom,
            );
          } else if (corner == Alignment.bottomLeft) {
            r = Rect.fromLTRB(
              (r.left + nx).clamp(0.0, r.right - 0.05),
              r.top,
              r.right,
              (r.bottom + ny).clamp(r.top + 0.05, 1.0),
            );
          } else {
            r = Rect.fromLTRB(
              r.left,
              r.top,
              (r.right + nx).clamp(r.left + 0.05, 1.0),
              (r.bottom + ny).clamp(r.top + 0.05, 1.0),
            );
          }
          ref.read(projectProvider.notifier).updateClip(
                clip.id,
                (c) => (c as VideoClip).copyWith(cropNorm: r),
              );
        },
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black54),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

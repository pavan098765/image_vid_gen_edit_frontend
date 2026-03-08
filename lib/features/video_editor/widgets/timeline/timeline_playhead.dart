// lib/features/video_editor/widgets/timeline/timeline_playhead.dart

import 'package:flutter/material.dart';

import '../../utils/editor_constants.dart';

/// The vertical playhead line + knob painted over the timeline.
class TimelinePlayhead extends StatelessWidget {
  final double positionPx;
  final double height;

  const TimelinePlayhead({
    super.key,
    required this.positionPx,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: positionPx - EditorConstants.playheadKnobRadius + EditorConstants.trackLabelWidth,
      top: 0,
      child: SizedBox(
        width: EditorConstants.playheadKnobRadius * 2,
        height: height,
        child: CustomPaint(
          painter: _PlayheadPainter(
            color: EditorConstants.playheadColor,
          ),
        ),
      ),
    );
  }
}

class _PlayheadPainter extends CustomPainter {
  final Color color;

  _PlayheadPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;

    // Vertical line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = EditorConstants.playheadWidth;
    canvas.drawLine(
      Offset(centerX, EditorConstants.playheadKnobRadius),
      Offset(centerX, size.height),
      linePaint,
    );

    // Top knob (inverted triangle)
    final knobPaint = Paint()..color = color;
    const r = EditorConstants.playheadKnobRadius;
    final path = Path()
      ..moveTo(centerX - r, 0)
      ..lineTo(centerX + r, 0)
      ..lineTo(centerX, r * 1.4)
      ..close();
    canvas.drawPath(path, knobPaint);
  }

  @override
  bool shouldRepaint(_PlayheadPainter old) => old.color != color;
}

// lib/features/video_editor/widgets/timeline/timeline_ruler.dart

import 'package:flutter/material.dart';

import '../../utils/editor_constants.dart';
import '../../utils/time_utils.dart';

/// The time ruler drawn at the top of the timeline.
class TimelineRuler extends StatelessWidget {
  final double pixelsPerSecond;
  final Duration totalDuration;
  final double scrollOffset;

  const TimelineRuler({
    super.key,
    required this.pixelsPerSecond,
    required this.totalDuration,
    required this.scrollOffset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: EditorConstants.rulerHeight,
      child: CustomPaint(
        painter: _RulerPainter(
          pixelsPerSecond: pixelsPerSecond,
          totalDuration: totalDuration,
          scrollOffset: scrollOffset,
          textColor: cs.onSurface.withOpacity(0.5),
          lineColor: cs.onSurface.withOpacity(0.15),
          majorLineColor: cs.onSurface.withOpacity(0.3),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final double pixelsPerSecond;
  final Duration totalDuration;
  final double scrollOffset;
  final Color textColor;
  final Color lineColor;
  final Color majorLineColor;

  _RulerPainter({
    required this.pixelsPerSecond,
    required this.totalDuration,
    required this.scrollOffset,
    required this.textColor,
    required this.lineColor,
    required this.majorLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (pixelsPerSecond <= 0) return;

    // Determine tick interval based on zoom
    double intervalSec;
    if (pixelsPerSecond > 200) {
      intervalSec = 0.5;
    } else if (pixelsPerSecond > 100) {
      intervalSec = 1;
    } else if (pixelsPerSecond > 40) {
      intervalSec = 2;
    } else if (pixelsPerSecond > 20) {
      intervalSec = 5;
    } else {
      intervalSec = 10;
    }

    final majorEvery = intervalSec >= 5 ? 2 : 5;
    final totalSec = totalDuration.inMilliseconds / 1000.0;
    final startSec = (scrollOffset / pixelsPerSecond).floorToDouble();
    final endSec = ((scrollOffset + size.width) / pixelsPerSecond).ceilToDouble() + intervalSec;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;
    final majorLinePaint = Paint()
      ..color = majorLineColor
      ..strokeWidth = 1;

    final tp = TextPainter(textDirection: TextDirection.ltr);

    int tickIndex = 0;
    for (double sec = (startSec / intervalSec).floorToDouble() * intervalSec;
        sec <= endSec && sec <= totalSec + intervalSec;
        sec += intervalSec) {
      final x = sec * pixelsPerSecond - scrollOffset + EditorConstants.trackLabelWidth;
      if (x < EditorConstants.trackLabelWidth - 20 || x > size.width + 20) {
        tickIndex++;
        continue;
      }

      final isMajor = tickIndex % majorEvery == 0;

      canvas.drawLine(
        Offset(x, isMajor ? 0 : size.height * 0.4),
        Offset(x, size.height),
        isMajor ? majorLinePaint : linePaint,
      );

      if (isMajor && sec >= 0) {
        final label = TimeUtils.formatRulerLabel(
          Duration(milliseconds: (sec * 1000).round()),
        );
        tp.text = TextSpan(
          text: label,
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(x + 3, 1));
      }
      tickIndex++;
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.pixelsPerSecond != pixelsPerSecond ||
      old.totalDuration != totalDuration ||
      old.scrollOffset != scrollOffset;
}

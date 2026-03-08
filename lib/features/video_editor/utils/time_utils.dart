// lib/features/video_editor/utils/time_utils.dart

/// Helpers for working with [Duration] and time in the video editor.
class TimeUtils {
  TimeUtils._();

  /// Format duration as HH:MM:SS (e.g. "01:23:45") or MM:SS if under 1 hour.
  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  /// Format duration with milliseconds: MM:SS.mmm
  static String formatDurationMs(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$m:$s.$ms';
  }

  /// Format a duration compactly for timeline ruler labels.
  /// Under 1 minute:  "0s", "5s", "10s", ...
  /// Under 1 hour:    "1:00", "1:30", ...
  /// Over 1 hour:     "1:00:00", ...
  static String formatRulerLabel(Duration d) {
    final totalSec = d.inSeconds;
    if (totalSec < 60) return '${totalSec}s';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  /// Convert a pixel offset on the timeline to a [Duration].
  static Duration pxToDuration(double px, double pixelsPerSecond) {
    if (pixelsPerSecond <= 0) return Duration.zero;
    final ms = (px / pixelsPerSecond * 1000).round();
    return Duration(milliseconds: ms.clamp(0, 999999999));
  }

  /// Convert a [Duration] to a pixel offset on the timeline.
  static double durationToPx(Duration d, double pixelsPerSecond) {
    return d.inMilliseconds / 1000.0 * pixelsPerSecond;
  }

  /// Clamp a duration between [min] and [max].
  static Duration clampDuration(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  /// Snap a duration to the nearest frame boundary.
  static Duration snapToFrame(Duration d, {int fps = 30}) {
    final frameDurationMs = 1000.0 / fps;
    final frames = (d.inMilliseconds / frameDurationMs).round();
    return Duration(milliseconds: (frames * frameDurationMs).round());
  }

  /// Returns the FFmpeg-compatible time string (HH:MM:SS.mmm).
  static String toFfmpegTime(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final ms = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

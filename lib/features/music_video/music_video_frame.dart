import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/audio_features.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_template.dart';

class MusicVideoFramePainter extends CustomPainter {
  final MusicVideoTemplate template;
  final ui.Image? cover;
  final ui.Image? base;
  final FrameFeatures? features;
  final String? lyricLine;
  final String title;
  final String artist;
  final bool foregroundOnly;

  const MusicVideoFramePainter({
    required this.template,
    this.cover,
    this.base,
    this.features,
    this.lyricLine,
    this.title = '',
    this.artist = '',
    this.foregroundOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (base != null && !foregroundOnly) {
      canvas.drawImageRect(
        base!,
        Rect.fromLTWH(0, 0, base!.width.toDouble(), base!.height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
    } else if (!foregroundOnly) {
      _paintBackdrop(canvas, size);
      _paintArt(canvas, size);
    } else {
      _paintArt(canvas, size);
    }
    final meter = features;
    if (meter != null && template.meter != MusicVideoMeter.none) {
      _paintMeter(canvas, size, meter);
    }
    if (!foregroundOnly && lyricLine != null && lyricLine!.trim().isNotEmpty) {
      _paintLyric(canvas, size, lyricLine!.trim());
    }
  }

  void _paintBackdrop(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = template.backgroundColor);
    final image = cover;
    if (image == null) return;
    if (template.splitBlur) {
      _paintSplit(canvas, size, image);
      return;
    }
    if (template.background == MusicVideoBackground.color) return;
    final blur = template.background == MusicVideoBackground.blurredCover;
    if (blur) {
      canvas.saveLayer(
        rect,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
      );
    }
    _drawCover(canvas, rect, image, cover: true);
    if (blur) canvas.restore();
    if (blur) {
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0x66000000),
      );
    }
  }

  void _paintSplit(Canvas canvas, Size size, ui.Image image) {
    final width = size.width;
    final side = width / 3;
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
    );
    _drawCover(canvas, Offset.zero & size, image, cover: true);
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(side, 0, side, size.height));
    _drawCover(
      canvas,
      Rect.fromLTWH(side, size.height * 0.22, side, side),
      image,
      cover: false,
    );
    canvas.restore();
  }

  void _paintArt(Canvas canvas, Size size) {
    if (template.artFrame == MusicVideoArtFrame.none) return;
    final image = cover;
    final rect = musicVideoArtRect(size, template);
    if (template.artFrame == MusicVideoArtFrame.vinyl) {
      _paintVinyl(canvas, rect, image);
      if (template.showTitle) _paintTitle(canvas, size, rect);
      return;
    }
    final round = template.artFrame == MusicVideoArtFrame.circle;
    canvas.save();
    if (round) {
      canvas.clipPath(Path()..addOval(rect));
    } else {
      canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    }
    if (image == null) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF2A2A3A));
    } else {
      _drawCover(canvas, rect, image, cover: false);
    }
    canvas.restore();
    if (template.showTitle) _paintTitle(canvas, size, rect);
  }

  void _paintVinyl(Canvas canvas, Rect rect, ui.Image? image) {
    final center = rect.center;
    final radius = rect.shortestSide / 2;
    canvas.drawCircle(center, radius * 1.08, Paint()..color = const Color(0xFF111111));
    canvas.save();
    canvas.clipPath(Path()..addOval(rect));
    if (image == null) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF2A2A3A));
    } else {
      _drawCover(canvas, rect, image, cover: false);
    }
    canvas.restore();
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x55FFFFFF);
    canvas.drawCircle(center, radius * 0.78, groove);
    canvas.drawCircle(center, radius * 0.62, groove);
    canvas.drawCircle(center, radius * 0.22, Paint()..color = template.backgroundColor);
    canvas.drawCircle(
      center,
      radius * 0.04,
      Paint()..color = const Color(0xFF111111),
    );
  }

  void _paintTitle(Canvas canvas, Size size, Rect art) {
    final onLight = template.backgroundColor.computeLuminance() > 0.55;
    final titleStyle = TextStyle(
      color: onLight ? const Color(0xFF1A1A2E) : Colors.white,
      fontSize: size.shortestSide * 0.045,
      fontWeight: FontWeight.w700,
    );
    final artistStyle = TextStyle(
      color: onLight ? const Color(0xCC1A1A2E) : const Color(0xCCFFFFFF),
      fontSize: size.shortestSide * 0.032,
    );
    final titlePainter = TextPainter(
      text: TextSpan(text: title, style: titleStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width * 0.8);
    final artistPainter = TextPainter(
      text: TextSpan(text: artist, style: artistStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width * 0.8);
    final top = math.min(art.bottom + size.height * 0.04, size.height - titlePainter.height - 24);
    titlePainter.paint(canvas, Offset((size.width - titlePainter.width) / 2, top));
    artistPainter.paint(
      canvas,
      Offset((size.width - artistPainter.width) / 2, top + titlePainter.height + 4),
    );
  }

  void _paintMeter(Canvas canvas, Size size, FrameFeatures features) {
    final art = musicVideoArtRect(size, template);
    switch (template.meter) {
      case MusicVideoMeter.wave:
        _paintWave(canvas, size, art, features);
      case MusicVideoMeter.line:
        _paintLine(canvas, size, features);
      case MusicVideoMeter.bars:
        _paintBars(canvas, size, art, features);
      case MusicVideoMeter.circular:
        _paintRing(canvas, art, features, arc: false);
      case MusicVideoMeter.arc:
        _paintRing(canvas, art, features, arc: true);
      case MusicVideoMeter.none:
        break;
    }
  }

  void _paintWave(Canvas canvas, Size size, Rect art, FrameFeatures features) {
    final paint = Paint()
      ..color = template.meterColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, size.shortestSide * 0.004)
      ..strokeCap = StrokeCap.round;
    final fade = Paint()
      ..color = template.meterColor.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = paint.strokeWidth
      ..strokeCap = StrokeCap.round;
    _strokeWave(
      canvas,
      Rect.fromLTRB(size.width * 0.04, art.top, art.left - 12, art.bottom),
      features.waveform,
      paint,
      fade,
    );
    _strokeWave(
      canvas,
      Rect.fromLTRB(art.right + 12, art.top, size.width * 0.96, art.bottom),
      features.waveform,
      paint,
      fade,
    );
  }

  void _strokeWave(Canvas canvas, Rect area, Float64List wave, Paint paint, Paint fade) {
    if (area.width < 8 || area.height < 8) return;
    final path = Path();
    final mirror = Path();
    final mid = area.center.dy;
    final amp = area.height * 0.28;
    for (var i = 0; i < wave.length; i++) {
      final x = area.left + area.width * (i / (wave.length - 1));
      final y = mid + wave[i] * amp;
      if (i == 0) {
        path.moveTo(x, y);
        mirror.moveTo(x, mid - (y - mid));
      } else {
        path.lineTo(x, y);
        mirror.lineTo(x, mid - (y - mid));
      }
    }
    canvas.drawPath(path, paint);
    canvas.drawPath(mirror, fade);
  }

  void _paintLine(Canvas canvas, Size size, FrameFeatures features) {
    final paint = Paint()
      ..color = template.meterColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.shortestSide * 0.005)
      ..strokeCap = StrokeCap.round;
    final bins = features.bins;
    final left = size.width * 0.08;
    final right = size.width * 0.92;
    final base = size.height * 0.86;
    final height = size.height * 0.12;
    final path = Path();
    for (var i = 0; i < bins.length; i++) {
      final x = left + (right - left) * (i / (bins.length - 1));
      final y = base - bins[i] * height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  void _paintBars(Canvas canvas, Size size, Rect art, FrameFeatures features) {
    final bins = features.bins;
    final left = size.width * 0.08;
    final width = size.width * 0.84;
    final gap = width * 0.008;
    final barWidth = (width - gap * (bins.length - 1)) / bins.length;
    final centerY = math.min(art.bottom + size.height * 0.1, size.height * 0.78);
    final maxHeight = size.height * 0.08;
    final paint = Paint()..color = template.meterColor;
    for (var i = 0; i < bins.length; i++) {
      final x = left + i * (barWidth + gap);
      final bar = bins[i] * maxHeight;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, centerY - bar, barWidth, bar * 2),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  void _paintRing(Canvas canvas, Rect art, FrameFeatures features, {required bool arc}) {
    final bins = features.bins;
    final paint = Paint()
      ..color = template.meterColor
      ..strokeWidth = math.max(2.5, art.shortestSide * 0.012)
      ..strokeCap = StrokeCap.round;
    final inner = art.shortestSide / 2 + art.shortestSide * 0.08;
    final start = arc ? 0.2 : -math.pi / 2;
    final sweep = arc ? math.pi * 0.9 : math.pi * 2;
    for (var i = 0; i < bins.length; i++) {
      final angle = start + sweep * (i / bins.length);
      final length = art.shortestSide * (0.03 + bins[i] * 0.16);
      final dir = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        art.center + dir * inner,
        art.center + dir * (inner + length),
        paint,
      );
    }
  }

  void _paintLyric(Canvas canvas, Size size, String line) {
    final painter = TextPainter(
      text: TextSpan(
        text: line,
        style: TextStyle(
          color: Colors.white,
          fontSize: size.shortestSide * 0.04,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: size.width * 0.86);
    final offset = Offset(
      (size.width - painter.width) / 2,
      size.height * 0.9 - painter.height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(offset.dx - 12, offset.dy - 6, painter.width + 24, painter.height + 12),
        const Radius.circular(8),
      ),
      Paint()..color = const Color(0x99000000),
    );
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(MusicVideoFramePainter oldDelegate) {
    return oldDelegate.template != template ||
        oldDelegate.cover != cover ||
        oldDelegate.base != base ||
        oldDelegate.features != features ||
        oldDelegate.lyricLine != lyricLine ||
        oldDelegate.foregroundOnly != foregroundOnly;
  }
}

Rect musicVideoArtRect(Size size, MusicVideoTemplate template) {
  final side = size.shortestSide * template.artScale;
  if (side <= 0) return Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
  final lift = template.meter == MusicVideoMeter.bars || template.meter == MusicVideoMeter.line
      ? size.height * 0.06
      : 0.0;
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2 - lift),
    width: side,
    height: side,
  );
}

void _drawCover(Canvas canvas, Rect rect, ui.Image image, {required bool cover}) {
  final src = _sourceRect(image, rect, cover: cover);
  canvas.drawImageRect(image, src, rect, Paint()..filterQuality = FilterQuality.medium);
}

Rect _sourceRect(ui.Image image, Rect dest, {required bool cover}) {
  final imageWidth = image.width.toDouble();
  final imageHeight = image.height.toDouble();
  if (!cover) {
    final scale = math.max(dest.width / imageWidth, dest.height / imageHeight);
    final width = dest.width / scale;
    final height = dest.height / scale;
    return Rect.fromCenter(
      center: Offset(imageWidth / 2, imageHeight / 2),
      width: width,
      height: height,
    );
  }
  final scale = math.max(dest.width / imageWidth, dest.height / imageHeight);
  final width = dest.width / scale;
  final height = dest.height / scale;
  return Rect.fromCenter(
    center: Offset(imageWidth / 2, imageHeight / 2),
    width: width,
    height: height,
  );
}

Future<ui.Image> rasterizeMusicVideoFrame({
  required Size size,
  required MusicVideoTemplate template,
  ui.Image? cover,
  ui.Image? base,
  FrameFeatures? features,
  String? lyricLine,
  String title = '',
  String artist = '',
  bool foregroundOnly = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  MusicVideoFramePainter(
    template: template,
    cover: cover,
    base: base,
    features: features,
    lyricLine: lyricLine,
    title: title,
    artist: artist,
    foregroundOnly: foregroundOnly,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  return image;
}

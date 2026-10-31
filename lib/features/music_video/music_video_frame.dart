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
  final bool includeArt;

  const MusicVideoFramePainter({
    required this.template,
    this.cover,
    this.base,
    this.features,
    this.lyricLine,
    this.title = '',
    this.artist = '',
    this.foregroundOnly = false,
    this.includeArt = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final visual = !foregroundOnly &&
        features != null &&
        template.meter != MusicVideoMeter.none;
    if (base != null && !foregroundOnly) {
      canvas.drawImageRect(
        base!,
        Rect.fromLTWH(0, 0, base!.width.toDouble(), base!.height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
    } else if (!foregroundOnly) {
      _paintBackdrop(canvas, size);
      if (!visual && includeArt) _paintArt(canvas, size);
    } else {
      _paintArt(canvas, size);
    }
    final meter = features;
    if (visual && meter != null) {
      _paintStage(canvas, size, meter);
      _paintMeter(canvas, size, meter);
      _paintArt(canvas, size);
    }
    if (!foregroundOnly && lyricLine != null && lyricLine!.trim().isNotEmpty) {
      _paintLyric(canvas, size, lyricLine!.trim());
    }
  }

  void _paintStage(Canvas canvas, Size size, FrameFeatures features) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 1.05,
          colors: [
            _ink.withValues(alpha: 0.16 + features.bass * 0.28),
            _ink.withValues(alpha: 0.05 + features.mid * 0.08),
            const Color(0x00000000),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width * 0.08, size.height * 0.18),
      size.shortestSide * (0.28 + features.bass * 0.12),
      Paint()..color = _ink.withValues(alpha: 0.10 + features.bass * 0.16),
    );
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.78),
      size.shortestSide * (0.22 + features.high * 0.14),
      Paint()..color = _hot.withValues(alpha: 0.08 + features.high * 0.14),
    );
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
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, rect.shortestSide * 0.018)
      ..color = const Color(0x99FFFFFF);
    if (round) {
      canvas.drawOval(rect, framePaint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        framePaint,
      );
    }
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
        _paintRing(canvas, size, art, features, arc: false);
      case MusicVideoMeter.arc:
        _paintRing(canvas, size, art, features, arc: true);
      case MusicVideoMeter.glowBars:
        _paintGlowBars(canvas, size, features);
      case MusicVideoMeter.ribbon:
        _paintRibbon(canvas, size, features);
      case MusicVideoMeter.halo:
        _paintHalo(canvas, size, art, features);
      case MusicVideoMeter.pillars:
        _paintPillars(canvas, size, features);
      case MusicVideoMeter.neon:
        _paintNeon(canvas, size, features);
      case MusicVideoMeter.orbit:
        _paintOrbit(canvas, size, art, features);
      case MusicVideoMeter.columns:
        _paintColumns(canvas, size, features);
      case MusicVideoMeter.pulse:
        _paintPulse(canvas, size, art, features);
      case MusicVideoMeter.horizon:
        _paintHorizon(canvas, size, features);
      case MusicVideoMeter.none:
        break;
    }
  }

  Color get _ink => template.meterColor;

  Color get _hot => Color.lerp(_ink, Colors.white, 0.42) ?? _ink;

  void _paintWave(Canvas canvas, Size size, Rect art, FrameFeatures features) {
    _strokeWave(
      canvas,
      Rect.fromLTRB(size.width * 0.03, size.height * 0.08, math.max(size.width * 0.28, art.left - 10), size.height * 0.9),
      features.waveform,
      math.max(2.2, size.shortestSide * 0.006),
    );
    _strokeWave(
      canvas,
      Rect.fromLTRB(math.min(size.width * 0.72, art.right + 10), size.height * 0.08, size.width * 0.97, size.height * 0.9),
      features.waveform,
      math.max(2.2, size.shortestSide * 0.006),
    );
  }

  void _strokeWave(Canvas canvas, Rect area, Float64List wave, double core) {
    if (area.width < 8 || area.height < 8 || wave.length < 2) return;
    final path = Path();
    final mirror = Path();
    final mid = area.center.dy;
    final amp = area.height * 0.42;
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
    final fill = Path.from(path)
      ..lineTo(area.right, mid)
      ..lineTo(area.left, mid)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_ink.withValues(alpha: 0.42), _ink.withValues(alpha: 0.02)],
        ).createShader(area),
    );
    _glowStroke(canvas, path, core);
    _glowStroke(canvas, mirror, core * 0.7, alpha: 0.45);
  }

  void _glowStroke(Canvas canvas, Path path, double width, {double alpha = 1}) {
    canvas.drawPath(
      path,
      Paint()
        ..color = _ink.withValues(alpha: 0.28 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 3.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _hot.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintLine(Canvas canvas, Size size, FrameFeatures features) {
    final curve = _spectrumPath(size, features.bins, base: 0.7, reach: 0.4);
    final fill = Path.from(curve.path)
      ..lineTo(curve.right, size.height * 0.7)
      ..lineTo(curve.left, size.height * 0.7)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_ink.withValues(alpha: 0.55), _ink.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(curve.left, size.height * 0.62, curve.right - curve.left, size.height * 0.24)),
    );
    _glowStroke(canvas, curve.path, math.max(2, size.shortestSide * 0.005));
  }

  void _paintBars(Canvas canvas, Size size, Rect art, FrameFeatures features) {
    final samples = _sample(features.bins, 36);
    _mirroredBars(
      canvas,
      size,
      samples,
      centerY: size.height * 0.72,
      maxHeight: size.height * 0.24,
      inset: 0.08,
    );
  }

  void _paintGlowBars(Canvas canvas, Size size, FrameFeatures features) {
    final samples = _sample(features.bins, 28);
    _mirroredBars(
      canvas,
      size,
      samples,
      centerY: size.height * 0.8,
      maxHeight: size.height * 0.46,
      inset: 0.07,
      glow: true,
    );
  }

  void _mirroredBars(
    Canvas canvas,
    Size size,
    List<double> samples, {
    required double centerY,
    required double maxHeight,
    required double inset,
    bool glow = false,
  }) {
    if (samples.isEmpty) return;
    final left = size.width * inset;
    final width = size.width * (1 - inset * 2);
    final gap = math.max(2.0, width * 0.012);
    final barWidth = (width - gap * (samples.length - 1)) / samples.length;
    for (var i = 0; i < samples.length; i++) {
      final x = left + i * (barWidth + gap);
      final bar = math.max(2.0, samples[i] * maxHeight);
      final rect = Rect.fromLTWH(x, centerY - bar, barWidth, bar * 2);
      final color = Color.lerp(_ink, _hot, i / samples.length) ?? _ink;
      if (glow) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(barWidth * 0.35), Radius.circular(barWidth)),
          Paint()..color = color.withValues(alpha: 0.22),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withValues(alpha: 0.35), color, _hot],
          ).createShader(rect),
      );
    }
  }

  void _paintRibbon(Canvas canvas, Size size, FrameFeatures features) {
    final curve = _spectrumPath(size, _sample(features.bins, 48), base: 0.58, reach: 0.46);
    final fill = Path.from(curve.path)
      ..lineTo(curve.right, size.height)
      ..lineTo(curve.left, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_hot.withValues(alpha: 0.9), _ink.withValues(alpha: 0.35), _ink.withValues(alpha: 0.02)],
        ).createShader(Rect.fromLTWH(0, size.height * 0.66, size.width, size.height * 0.34)),
    );
    _glowStroke(canvas, curve.path, math.max(2.2, size.shortestSide * 0.006));
  }

  void _paintHalo(Canvas canvas, Size size, Rect art, FrameFeatures features) {
    final field = size.shortestSide;
    final radius = field * (0.34 + features.bass * 0.06);
    final ring = Path()..addOval(Rect.fromCircle(center: art.center, radius: radius));
    canvas.drawPath(
      ring,
      Paint()
        ..color = _ink.withValues(alpha: 0.16 + features.rms * 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = field * (0.012 + features.bass * 0.02),
    );
    _glowStroke(canvas, ring, math.max(2.4, field * 0.008));
    _paintTicks(canvas, art.center, radius + field * 0.02, features.bins, field, arc: false);
  }

  void _paintPillars(Canvas canvas, Size size, FrameFeatures features) {
    final samples = _sample(features.bins, 18);
    final left = size.width * 0.06;
    final width = size.width * 0.88;
    final gap = width * 0.018;
    final barWidth = (width - gap * (samples.length - 1)) / samples.length;
    final floor = size.height * 0.86;
    final maxHeight = size.height * 0.5;
    for (var i = 0; i < samples.length; i++) {
      final x = left + i * (barWidth + gap);
      final bar = math.max(4.0, samples[i] * maxHeight);
      final rect = Rect.fromLTWH(x, floor - bar, barWidth, bar);
      final color = Color.lerp(_ink, _hot, samples[i]) ?? _ink;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth * 0.35)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withValues(alpha: 0.45), color],
          ).createShader(rect),
      );
      final reflection = Rect.fromLTWH(x, floor + 3, barWidth, bar * 0.38);
      canvas.drawRRect(
        RRect.fromRectAndRadius(reflection, Radius.circular(barWidth * 0.35)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
          ).createShader(reflection),
      );
    }
  }

  void _paintNeon(Canvas canvas, Size size, FrameFeatures features) {
    final curve = _spectrumPath(size, features.bins, base: 0.62, reach: 0.36);
    canvas.drawPath(
      curve.path,
      Paint()
        ..color = _ink.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(10, size.shortestSide * 0.028)
        ..strokeCap = StrokeCap.round,
    );
    _glowStroke(canvas, curve.path, math.max(2.4, size.shortestSide * 0.006));
  }

  void _paintOrbit(Canvas canvas, Size size, Rect art, FrameFeatures features) {
    final samples = _sample(features.bins, 42);
    final field = size.shortestSide;
    final inner = art.shortestSide / 2 + field * 0.06;
    canvas.drawCircle(
      art.center,
      inner,
      Paint()
        ..color = _ink.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    for (var i = 0; i < samples.length; i++) {
      final angle = -math.pi / 2 + math.pi * 2 * (i / samples.length);
      final reach = field * (0.04 + samples[i] * 0.22);
      final center = art.center + Offset(math.cos(angle), math.sin(angle)) * (inner + reach);
      final radius = math.max(1.6, field * (0.006 + samples[i] * 0.012));
      final color = Color.lerp(_ink, _hot, samples[i]) ?? _ink;
      canvas.drawCircle(center, radius * 2.2, Paint()..color = color.withValues(alpha: 0.2));
      canvas.drawCircle(center, radius, Paint()..color = color);
    }
  }

  void _paintRing(Canvas canvas, Size size, Rect art, FrameFeatures features, {required bool arc}) {
    final field = size.shortestSide;
    final inner = art.shortestSide / 2 + field * 0.045;
    final start = arc ? 0.15 : -math.pi / 2;
    final sweep = arc ? math.pi * 1.15 : math.pi * 2;
    canvas.drawArc(
      Rect.fromCircle(center: art.center, radius: inner),
      start,
      sweep,
      false,
      Paint()
        ..color = _ink.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.4, field * 0.006),
    );
    _paintTicks(
      canvas,
      art.center,
      inner,
      features.bins,
      field,
      arc: arc,
      start: start,
      sweep: sweep,
    );
  }

  void _paintTicks(
    Canvas canvas,
    Offset center,
    double inner,
    Float64List bins,
    double artSide, {
    required bool arc,
    double start = 0.35,
    double sweep = math.pi * 0.85,
  }) {
    final origin = arc ? start : -math.pi / 2;
    final turn = arc ? sweep : math.pi * 2;
    final width = math.max(2.2, artSide * 0.011);
    for (var i = 0; i < bins.length; i++) {
      final angle = origin + turn * (i / bins.length);
      final length = artSide * (0.04 + bins[i] * 0.34);
      final dir = Offset(math.cos(angle), math.sin(angle));
      final color = Color.lerp(_ink, _hot, bins[i]) ?? _ink;
      canvas.drawLine(
        center + dir * inner,
        center + dir * (inner + length),
        Paint()
          ..color = color.withValues(alpha: 0.28)
          ..strokeWidth = width * 2.4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        center + dir * inner,
        center + dir * (inner + length),
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  List<double> _sample(Float64List bins, int count) {
    if (bins.isEmpty || count < 1) return const [];
    final out = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final start = i * bins.length ~/ count;
      final end = math.max(start + 1, (i + 1) * bins.length ~/ count);
      var sum = 0.0;
      for (var j = start; j < end && j < bins.length; j++) {
        sum += bins[j];
      }
      out[i] = sum / (end - start);
    }
    return out;
  }

  ({Path path, double left, double right}) _spectrumPath(
    Size size,
    List<double> samples, {
    required double base,
    required double reach,
  }) {
    final left = size.width * 0.06;
    final right = size.width * 0.94;
    final floor = size.height * base;
    final height = size.height * reach;
    final path = Path();
    if (samples.length < 2) return (path: path, left: left, right: right);
    final xs = List<double>.generate(
      samples.length,
      (i) => left + (right - left) * (i / (samples.length - 1)),
    );
    final ys = List<double>.generate(
      samples.length,
      (i) => floor - samples[i] * height,
    );
    path.moveTo(xs.first, ys.first);
    for (var i = 1; i < xs.length - 1; i++) {
      final midX = (xs[i] + xs[i + 1]) / 2;
      final midY = (ys[i] + ys[i + 1]) / 2;
      path.quadraticBezierTo(xs[i], ys[i], midX, midY);
    }
    path.lineTo(xs.last, ys.last);
    return (path: path, left: left, right: right);
  }

  void _paintColumns(Canvas canvas, Size size, FrameFeatures features) {
    final samples = _sample(features.bins, 14);
    final left = size.width * 0.05;
    final width = size.width * 0.9;
    final gap = width * 0.03;
    final barWidth = (width - gap * (samples.length - 1)) / samples.length;
    final floor = size.height * 0.94;
    for (var i = 0; i < samples.length; i++) {
      final bar = size.height * (0.12 + samples[i] * 0.62);
      final rect = Rect.fromLTWH(left + i * (barWidth + gap), floor - bar, barWidth, bar);
      final color = Color.lerp(_ink, _hot, i / samples.length) ?? _ink;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barWidth * 0.28)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withValues(alpha: 0.25), color, _hot],
          ).createShader(rect),
      );
    }
  }

  void _paintPulse(Canvas canvas, Size size, Rect art, FrameFeatures features) {
    final center = art.center;
    final field = size.shortestSide;
    final energies = [features.bass, features.mid, features.high, features.rms];
    for (var i = 0; i < energies.length; i++) {
      final radius = field * (0.22 + i * 0.1 + energies[i] * 0.06);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = field * (0.012 + energies[i] * 0.02)
          ..color = (Color.lerp(_ink, _hot, i / energies.length) ?? _ink).withValues(alpha: 0.35 + energies[i] * 0.45),
      );
    }
  }

  void _paintHorizon(Canvas canvas, Size size, FrameFeatures features) {
    final samples = _sample(features.bins, 48);
    final mid = size.height * 0.62;
    final reach = size.height * 0.28;
    final left = size.width * 0.04;
    final right = size.width * 0.96;
    final upper = Path()..moveTo(left, mid);
    final lower = Path()..moveTo(left, mid);
    for (var i = 0; i < samples.length; i++) {
      final x = left + (right - left) * (i / (samples.length - 1));
      final lift = samples[i] * reach;
      upper.lineTo(x, mid - lift);
      lower.lineTo(x, mid + lift * 0.55);
    }
    upper.lineTo(right, mid);
    lower.lineTo(right, mid);
    upper.close();
    lower.close();
    canvas.drawPath(upper, Paint()..color = _ink.withValues(alpha: 0.85));
    canvas.drawPath(lower, Paint()..color = _ink.withValues(alpha: 0.35));
    _glowStroke(canvas, upper, math.max(2, size.shortestSide * 0.005));
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
        oldDelegate.foregroundOnly != foregroundOnly ||
        oldDelegate.includeArt != includeArt;
  }
}

Rect musicVideoArtRect(Size size, MusicVideoTemplate template) {
  final side = size.shortestSide * template.artScale;
  if (side <= 0) return Rect.fromCenter(center: size.center(Offset.zero), width: 0, height: 0);
  final lift = template.meter.sitsAlongTheBottom ? size.height * 0.06 : 0.0;
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
  bool includeArt = true,
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
    includeArt: includeArt,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  return image;
}

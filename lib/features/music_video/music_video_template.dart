import 'package:flutter/material.dart';

const String kLocalMusicVideoModelId = 'kala_music_video';

enum MusicVideoFamily { still, visualizer, canvas }

enum MusicVideoBackground { color, blurredCover, coverFill }

enum MusicVideoArtFrame { square, circle, vinyl, small, none }

enum MusicVideoMeter { none, wave, line, bars, circular, arc, glowBars, ribbon, halo, pillars, neon, orbit, columns, pulse, horizon }

extension MusicVideoMeterLayout on MusicVideoMeter {
  bool get sitsAlongTheBottom => switch (this) {
        MusicVideoMeter.bars ||
        MusicVideoMeter.line ||
        MusicVideoMeter.glowBars ||
        MusicVideoMeter.ribbon ||
        MusicVideoMeter.pillars ||
        MusicVideoMeter.neon ||
        MusicVideoMeter.columns ||
        MusicVideoMeter.horizon =>
          true,
        _ => false,
      };
}

enum MusicVideoAspect {
  landscape(16, 9, 1280, 720, '16:9'),
  square(1, 1, 1080, 1080, '1:1'),
  fourFive(4, 5, 864, 1080, '4:5'),
  portrait(9, 16, 720, 1280, '9:16');

  final int widthRatio;
  final int heightRatio;
  final int exportWidth;
  final int exportHeight;
  final String label;

  const MusicVideoAspect(
    this.widthRatio,
    this.heightRatio,
    this.exportWidth,
    this.exportHeight,
    this.label,
  );

  double get ratio => widthRatio / heightRatio;
}

class MusicVideoTemplate {
  final String id;
  final String title;
  final MusicVideoFamily family;
  final MusicVideoBackground background;
  final Color backgroundColor;
  final MusicVideoArtFrame artFrame;
  final double artScale;
  final bool splitBlur;
  final MusicVideoMeter meter;
  final Color meterColor;
  final bool showTitle;

  const MusicVideoTemplate({
    required this.id,
    required this.title,
    required this.family,
    required this.background,
    required this.backgroundColor,
    required this.artFrame,
    required this.artScale,
    this.splitBlur = false,
    this.meter = MusicVideoMeter.none,
    this.meterColor = Colors.white,
    this.showTitle = false,
  });

  MusicVideoTemplate copyWith({Color? meterColor}) {
    return MusicVideoTemplate(
      id: id,
      title: title,
      family: family,
      background: background,
      backgroundColor: backgroundColor,
      artFrame: artFrame,
      artScale: artScale,
      splitBlur: splitBlur,
      meter: meter,
      meterColor: meterColor ?? this.meterColor,
      showTitle: showTitle,
    );
  }

  bool get needsLoopVideo => family == MusicVideoFamily.canvas;

  bool get needsAudioAnalysis => meter != MusicVideoMeter.none;
}

const List<MusicVideoTemplate> kMusicVideoTemplates = [
  MusicVideoTemplate(
    id: 'vinyl_cover',
    title: 'Vinyl cover',
    family: MusicVideoFamily.still,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFFF2C200),
    artFrame: MusicVideoArtFrame.vinyl,
    artScale: 0.46,
    showTitle: true,
  ),
  MusicVideoTemplate(
    id: 'album_medium',
    title: 'Album art',
    family: MusicVideoFamily.still,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF12121C),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.42,
  ),
  MusicVideoTemplate(
    id: 'disk_black',
    title: 'Disk cutout',
    family: MusicVideoFamily.still,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFF050505),
    artFrame: MusicVideoArtFrame.circle,
    artScale: 0.5,
  ),
  MusicVideoTemplate(
    id: 'album_large',
    title: 'Album art large',
    family: MusicVideoFamily.still,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF12121C),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.68,
  ),
  MusicVideoTemplate(
    id: 'split_blur',
    title: 'Split blur',
    family: MusicVideoFamily.still,
    background: MusicVideoBackground.coverFill,
    backgroundColor: Color(0xFF12121C),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.34,
    splitBlur: true,
  ),
  MusicVideoTemplate(
    id: 'album_small',
    title: 'Album art small',
    family: MusicVideoFamily.still,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF8E1B4A),
    artFrame: MusicVideoArtFrame.small,
    artScale: 0.28,
  ),
  MusicVideoTemplate(
    id: 'full_background',
    title: 'Full screen',
    family: MusicVideoFamily.still,
    background: MusicVideoBackground.coverFill,
    backgroundColor: Color(0xFF12121C),
    artFrame: MusicVideoArtFrame.none,
    artScale: 0,
  ),
  MusicVideoTemplate(
    id: 'canvas_cover',
    title: 'Canvas cover',
    family: MusicVideoFamily.canvas,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFF12121C),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.34,
    showTitle: true,
  ),
  MusicVideoTemplate(
    id: 'canvas_vinyl',
    title: 'Canvas vinyl',
    family: MusicVideoFamily.canvas,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFF12121C),
    artFrame: MusicVideoArtFrame.vinyl,
    artScale: 0.4,
  ),
  MusicVideoTemplate(
    id: 'canvas_circle',
    title: 'Canvas circle',
    family: MusicVideoFamily.canvas,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFF12121C),
    artFrame: MusicVideoArtFrame.circle,
    artScale: 0.36,
  ),
  MusicVideoTemplate(
    id: 'side_wave',
    title: 'Side waveform',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF0E0E16),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.34,
    meter: MusicVideoMeter.wave,
  ),
  MusicVideoTemplate(
    id: 'bottom_line',
    title: 'Bottom line spectrum',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF0E0E16),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.46,
    meter: MusicVideoMeter.line,
  ),
  MusicVideoTemplate(
    id: 'mirrored_bars',
    title: 'Mirrored bars',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF0E0E16),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.36,
    meter: MusicVideoMeter.bars,
    meterColor: Color(0xFF7B5EFF),
  ),
  MusicVideoTemplate(
    id: 'circular_bars',
    title: 'Circular bars',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF0E0E16),
    artFrame: MusicVideoArtFrame.circle,
    artScale: 0.34,
    meter: MusicVideoMeter.circular,
    meterColor: Color(0xFF00D4FF),
  ),
  MusicVideoTemplate(
    id: 'record_arc',
    title: 'Record arc bars',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFF120818),
    artFrame: MusicVideoArtFrame.vinyl,
    artScale: 0.42,
    meter: MusicVideoMeter.arc,
    meterColor: Color(0xFFFF66B2),
  ),
  MusicVideoTemplate(
    id: 'glow_bars',
    title: 'Glow bars',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF0B1020),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.38,
    meter: MusicVideoMeter.glowBars,
    meterColor: Color(0xFF8B6CFF),
  ),
  MusicVideoTemplate(
    id: 'bottom_ribbon',
    title: 'Ribbon',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF101018),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.42,
    meter: MusicVideoMeter.ribbon,
    meterColor: Color(0xFF3AD1FF),
  ),
  MusicVideoTemplate(
    id: 'bass_halo',
    title: 'Bass halo',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF120818),
    artFrame: MusicVideoArtFrame.circle,
    artScale: 0.36,
    meter: MusicVideoMeter.halo,
    meterColor: Color(0xFFFF4F9A),
  ),
  MusicVideoTemplate(
    id: 'reflected_pillars',
    title: 'Pillars',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFF0A0A12),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.34,
    meter: MusicVideoMeter.pillars,
    meterColor: Color(0xFFFFB020),
    showTitle: true,
  ),
  MusicVideoTemplate(
    id: 'neon_line',
    title: 'Neon line',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF070712),
    artFrame: MusicVideoArtFrame.circle,
    artScale: 0.32,
    meter: MusicVideoMeter.neon,
    meterColor: Color(0xFF3DDC97),
  ),
  MusicVideoTemplate(
    id: 'orbit_dots',
    title: 'Orbit',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF0E0E16),
    artFrame: MusicVideoArtFrame.circle,
    artScale: 0.34,
    meter: MusicVideoMeter.orbit,
    meterColor: Color(0xFFFF5C33),
  ),
  MusicVideoTemplate(
    id: 'wide_columns',
    title: 'Columns',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFF07070E),
    artFrame: MusicVideoArtFrame.small,
    artScale: 0.22,
    meter: MusicVideoMeter.columns,
    meterColor: Color(0xFF8B6CFF),
    showTitle: true,
  ),
  MusicVideoTemplate(
    id: 'pulse_rings',
    title: 'Pulse',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.color,
    backgroundColor: Color(0xFF0A0614),
    artFrame: MusicVideoArtFrame.circle,
    artScale: 0.28,
    meter: MusicVideoMeter.pulse,
    meterColor: Color(0xFF3AD1FF),
  ),
  MusicVideoTemplate(
    id: 'horizon_band',
    title: 'Horizon',
    family: MusicVideoFamily.visualizer,
    background: MusicVideoBackground.blurredCover,
    backgroundColor: Color(0xFF101018),
    artFrame: MusicVideoArtFrame.square,
    artScale: 0.3,
    meter: MusicVideoMeter.horizon,
    meterColor: Color(0xFFFF4F9A),
  ),
];

MusicVideoTemplate musicVideoTemplateById(String id) {
  for (final template in kMusicVideoTemplates) {
    if (template.id == id) return template;
  }
  return kMusicVideoTemplates.first;
}

// lib/features/video_editor/utils/color_matrix_presets.dart

/// Predefined color filter matrices for the video editor.
/// Each matrix is a 4x5 list (20 values) for use with ColorFilter.matrix().
class ColorMatrixPresets {
  ColorMatrixPresets._();

  /// Identity (no change).
  static const String normalId = 'normal';

  static const List<FilterPreset> presets = [
    FilterPreset(id: 'normal', name: 'Normal', matrix: _identity),
    FilterPreset(id: 'grayscale', name: 'B&W', matrix: _grayscale),
    FilterPreset(id: 'sepia', name: 'Sepia', matrix: _sepia),
    FilterPreset(id: 'vintage', name: 'Vintage', matrix: _vintage),
    FilterPreset(id: 'cool', name: 'Cool', matrix: _cool),
    FilterPreset(id: 'warm', name: 'Warm', matrix: _warm),
    FilterPreset(id: 'bright', name: 'Bright', matrix: _bright),
    FilterPreset(id: 'contrast', name: 'Contrast', matrix: _contrast),
    FilterPreset(id: 'fade', name: 'Fade', matrix: _fade),
    FilterPreset(id: 'dramatic', name: 'Dramatic', matrix: _dramatic),
    FilterPreset(id: 'invert', name: 'Invert', matrix: _invert),
    FilterPreset(id: 'purple_tint', name: 'Purple', matrix: _purpleTint),
    FilterPreset(id: 'cyan_tint', name: 'Cyan', matrix: _cyanTint),
  ];

  // Identity
  static const List<double> _identity = [
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];

  // Grayscale
  static const List<double> _grayscale = [
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0.2126, 0.7152, 0.0722, 0, 0,
    0, 0, 0, 1, 0,
  ];

  // Sepia
  static const List<double> _sepia = [
    0.393, 0.769, 0.189, 0, 0,
    0.349, 0.686, 0.168, 0, 0,
    0.272, 0.534, 0.131, 0, 0,
    0, 0, 0, 1, 0,
  ];

  // Vintage
  static const List<double> _vintage = [
    0.9, 0.5, 0.1, 0, 20,
    0.3, 0.8, 0.1, 0, 10,
    0.2, 0.3, 0.5, 0, 30,
    0, 0, 0, 1, 0,
  ];

  // Cool blue tones
  static const List<double> _cool = [
    0.9, 0, 0, 0, 0,
    0, 0.95, 0, 0, 0,
    0, 0, 1.1, 0, 20,
    0, 0, 0, 1, 0,
  ];

  // Warm tones
  static const List<double> _warm = [
    1.1, 0, 0, 0, 15,
    0, 1.0, 0, 0, 5,
    0, 0, 0.9, 0, -10,
    0, 0, 0, 1, 0,
  ];

  // Bright
  static const List<double> _bright = [
    1.2, 0, 0, 0, 20,
    0, 1.2, 0, 0, 20,
    0, 0, 1.2, 0, 20,
    0, 0, 0, 1, 0,
  ];

  // High contrast
  static const List<double> _contrast = [
    1.5, 0, 0, 0, -40,
    0, 1.5, 0, 0, -40,
    0, 0, 1.5, 0, -40,
    0, 0, 0, 1, 0,
  ];

  // Fade / washed out
  static const List<double> _fade = [
    1, 0, 0, 0, 40,
    0, 1, 0, 0, 40,
    0, 0, 1, 0, 40,
    0, 0, 0, 0.9, 0,
  ];

  // Dramatic / desaturated contrast
  static const List<double> _dramatic = [
    1.3, -0.1, -0.1, 0, -20,
    -0.1, 1.3, -0.1, 0, -20,
    -0.1, -0.1, 1.3, 0, -20,
    0, 0, 0, 1, 0,
  ];

  // Invert
  static const List<double> _invert = [
    -1, 0, 0, 0, 255,
    0, -1, 0, 0, 255,
    0, 0, -1, 0, 255,
    0, 0, 0, 1, 0,
  ];

  // Purple tint (brand colour)
  static const List<double> _purpleTint = [
    1.1, 0, 0, 0, 15,
    0, 0.9, 0, 0, -5,
    0, 0, 1.15, 0, 20,
    0, 0, 0, 1, 0,
  ];

  // Cyan tint (brand colour)
  static const List<double> _cyanTint = [
    0.9, 0, 0, 0, -10,
    0, 1.05, 0, 0, 10,
    0, 0, 1.15, 0, 20,
    0, 0, 0, 1, 0,
  ];

  /// Generate a brightness adjustment matrix.  [-100 .. 100]
  static List<double> brightness(double value) {
    return [
      1, 0, 0, 0, value,
      0, 1, 0, 0, value,
      0, 0, 1, 0, value,
      0, 0, 0, 1, 0,
    ];
  }

  /// Generate a contrast adjustment matrix.  [0.5 .. 2.0]
  static List<double> contrast(double factor) {
    final t = (1.0 - factor) * 128;
    return [
      factor, 0, 0, 0, t,
      0, factor, 0, 0, t,
      0, 0, factor, 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  /// Generate a saturation adjustment matrix.  [0.0 .. 2.0]
  static List<double> saturation(double s) {
    final sr = (1 - s) * 0.2126;
    final sg = (1 - s) * 0.7152;
    final sb = (1 - s) * 0.0722;
    return [
      sr + s, sg, sb, 0, 0,
      sr, sg + s, sb, 0, 0,
      sr, sg, sb + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

/// A named filter preset.
class FilterPreset {
  final String id;
  final String name;
  final List<double> matrix;

  const FilterPreset({
    required this.id,
    required this.name,
    required this.matrix,
  });
}

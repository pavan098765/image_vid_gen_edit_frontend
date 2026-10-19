import '../../media_editor/color_looks.dart';

/// Video-editor view of [ColorLooks].
///
/// Each preset is one combined 4×5 matrix for preview and export.
class ColorMatrixPresets {
  ColorMatrixPresets._();

  static const String normalId = 'normal';

  static final List<FilterPreset> presets = [
    for (final look in ColorLooks.looks)
      FilterPreset(id: look.id, name: look.name, matrix: look.matrix),
  ];

  static const List<double> identity = colorLookIdentity;

  /// The look at [strength], or null when there is nothing to apply.
  static List<double>? resolvedMatrix(String? id, double strength) {
    if (id == null || id == normalId || strength <= 0) return null;
    final look = ColorLooks.byId(id);
    if (look == null || look.filters.isEmpty) return null;
    return applyColorLookStrength(look.matrix, strength);
  }

  /// Brightness adjustment. [value] is in the same units as [ColorAdjustment].
  static List<double> brightness(double value) {
    return [
      1, 0, 0, 0, value,
      0, 1, 0, 0, value,
      0, 0, 1, 0, value,
      0, 0, 0, 1, 0,
    ];
  }

  /// Contrast adjustment. [factor] of 1 leaves the picture unchanged.
  static List<double> contrast(double factor) {
    final t = (1.0 - factor) * 128;
    return [
      factor, 0, 0, 0, t,
      0, factor, 0, 0, t,
      0, 0, factor, 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  /// Saturation adjustment. [s] of 1 leaves the picture unchanged.
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

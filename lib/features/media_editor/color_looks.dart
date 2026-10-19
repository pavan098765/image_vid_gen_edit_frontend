import 'package:pro_image_editor/pro_image_editor.dart';

/// One color look shared by the photo Filters tool and the video filter strip.
///
/// Built from the editor's color-matrix recipes. No LUT files to author.
class ColorLook {
  ColorLook({
    required this.id,
    required this.name,
    required this.filters,
  });

  final String id;
  final String name;

  /// Stacked 4×5 matrices. Empty means no change.
  final List<List<double>> filters;

  FilterModel toFilterModel() => FilterModel(name: name, filters: filters);

  List<double> get matrix => mergeColorLookMatrices(filters);
}

/// Catalog of looks. Photo and video both read this list.
class ColorLooks {
  ColorLooks._();

  static final List<ColorLook> looks = [
    ColorLook(id: 'normal', name: 'Clean', filters: const []),
    _preset('clarendon', 'Clarendon', PresetFilters.clarendon),
    _preset('lark', 'Lark', PresetFilters.lark),
    _preset('juno', 'Juno', PresetFilters.juno),
    _preset('aden', 'Aden', PresetFilters.aden),
    _preset('crema', 'Crema', PresetFilters.crema),
    _preset('perpetua', 'Perpetua', PresetFilters.perpetua),
    _preset('helena', 'Helena', PresetFilters.helena),
    _preset('maven', 'Maven', PresetFilters.maven),
    _preset('amaro', 'Amaro', PresetFilters.amaro),
    _preset('rise', 'Rise', PresetFilters.rise),
    _preset('hudson', 'Hudson', PresetFilters.hudson),
    _preset('valencia', 'Valencia', PresetFilters.valencia),
    _preset('xpro', 'X-Pro', PresetFilters.xProII),
    _preset('sierra', 'Sierra', PresetFilters.sierra),
    _preset('earlybird', 'Earlybird', PresetFilters.earlybird),
    _preset('brannan', 'Brannan', PresetFilters.brannan),
    _preset('sutro', 'Sutro', PresetFilters.sutro),
    _preset('toaster', 'Toaster', PresetFilters.toaster),
    _preset('walden', 'Walden', PresetFilters.walden),
    _preset('f1977', '1977', PresetFilters.f1977),
    _preset('kelvin', 'Kelvin', PresetFilters.kelvin),
    _preset('hefe', 'Hefe', PresetFilters.hefe),
    _preset('lofi', 'Lo-Fi', PresetFilters.loFi),
    _preset('nashville', 'Nashville', PresetFilters.nashville),
    _preset('mayfair', 'Mayfair', PresetFilters.mayfair),
    _preset('gingham', 'Gingham', PresetFilters.gingham),
    _preset('slumber', 'Slumber', PresetFilters.slumber),
    _preset('reyes', 'Reyes', PresetFilters.reyes),
    _preset('willow', 'Willow', PresetFilters.willow),
    _preset('ashby', 'Ashby', PresetFilters.ashby),
    _preset('stinson', 'Stinson', PresetFilters.stinson),
    _preset('ginza', 'Ginza', PresetFilters.ginza),
    _preset('moon', 'Moon', PresetFilters.moon),
    _preset('brooklyn', 'Brooklyn', PresetFilters.brooklyn),
    _preset('skyline', 'Skyline', PresetFilters.skyline),
    _preset('dogpatch', 'Dogpatch', PresetFilters.dogpatch),
    _preset('vesper', 'Vesper', PresetFilters.vesper),
    _preset('ludwig', 'Ludwig', PresetFilters.ludwig),
    _preset('charmes', 'Charmes', PresetFilters.charmes),
    _preset('inkwell', 'Ink', PresetFilters.inkwell),
    _preset('red', 'Red', PresetFilters.addictiveRed),
    _preset('blue', 'Blue', PresetFilters.addictiveBlue),
    ColorLook(
      id: 'warm',
      name: 'Warm',
      filters: [
        ColorFilterAddons.temperature(0.28),
        ColorFilterAddons.saturation(0.08),
      ],
    ),
    ColorLook(
      id: 'cool',
      name: 'Cool',
      filters: [
        ColorFilterAddons.temperature(-0.22),
        ColorFilterAddons.saturation(0.06),
      ],
    ),
    ColorLook(
      id: 'golden',
      name: 'Golden',
      filters: [
        ColorFilterAddons.temperature(0.34),
        ColorFilterAddons.sepia(0.18),
        ColorFilterAddons.brightness(0.04),
      ],
    ),
    ColorLook(
      id: 'food',
      name: 'Food',
      filters: [
        ColorFilterAddons.temperature(0.2),
        ColorFilterAddons.saturation(0.28),
        ColorFilterAddons.contrast(0.08),
      ],
    ),
    ColorLook(
      id: 'teal',
      name: 'Teal',
      filters: [
        ColorFilterAddons.rgbScale(0.9, 1.05, 1.18),
        ColorFilterAddons.saturation(0.12),
        ColorFilterAddons.contrast(0.06),
      ],
    ),
    ColorLook(
      id: 'rose',
      name: 'Rose',
      filters: [
        ColorFilterAddons.addictiveColor(28, 6, 12),
        ColorFilterAddons.saturation(0.1),
      ],
    ),
    ColorLook(
      id: 'vivid',
      name: 'Vivid',
      filters: [
        ColorFilterAddons.saturation(0.45),
        ColorFilterAddons.contrast(0.12),
      ],
    ),
    ColorLook(
      id: 'fade',
      name: 'Fade',
      filters: [
        ColorFilterAddons.fade(0.32),
        ColorFilterAddons.saturation(-0.1),
      ],
    ),
    ColorLook(
      id: 'mist',
      name: 'Mist',
      filters: [
        ColorFilterAddons.brightness(0.08),
        ColorFilterAddons.fade(0.2),
        ColorFilterAddons.saturation(-0.16),
      ],
    ),
    ColorLook(
      id: 'drama',
      name: 'Drama',
      filters: [
        ColorFilterAddons.contrast(0.34),
        ColorFilterAddons.saturation(-0.14),
        ColorFilterAddons.brightness(-0.04),
      ],
    ),
    ColorLook(
      id: 'vintage',
      name: 'Vintage',
      filters: [
        ColorFilterAddons.sepia(0.4),
        ColorFilterAddons.contrast(-0.06),
        ColorFilterAddons.brightness(0.05),
      ],
    ),
    ColorLook(
      id: 'sepia',
      name: 'Sepia',
      filters: [ColorFilterAddons.sepia(0.85)],
    ),
    ColorLook(
      id: 'grayscale',
      name: 'B&W',
      filters: [ColorFilterAddons.grayscale()],
    ),
    ColorLook(
      id: 'noir',
      name: 'Noir',
      filters: [
        ColorFilterAddons.grayscale(),
        ColorFilterAddons.contrast(0.3),
        ColorFilterAddons.brightness(-0.06),
      ],
    ),
    ColorLook(
      id: 'bright',
      name: 'Bright',
      filters: [ColorFilterAddons.brightness(0.12), ColorFilterAddons.contrast(0.04)],
    ),
    ColorLook(
      id: 'contrast',
      name: 'Contrast',
      filters: [ColorFilterAddons.contrast(0.28)],
    ),
    ColorLook(
      id: 'dramatic',
      name: 'Dramatic',
      filters: [
        ColorFilterAddons.contrast(0.22),
        ColorFilterAddons.saturation(-0.2),
      ],
    ),
    ColorLook(id: 'invert', name: 'Invert', filters: [ColorFilterAddons.invert()]),
    ColorLook(
      id: 'purple_tint',
      name: 'Purple',
      filters: [ColorFilterAddons.addictiveColor(18, -6, 28)],
    ),
    ColorLook(
      id: 'cyan_tint',
      name: 'Cyan',
      filters: [ColorFilterAddons.addictiveColor(-12, 10, 24)],
    ),
  ];

  static List<FilterModel> get imageFilters =>
      looks.map((look) => look.toFilterModel()).toList();

  static ColorLook? byId(String? id) {
    if (id == null) return null;
    for (final look in looks) {
      if (look.id == id) return look;
    }
    return null;
  }

  static ColorLook _preset(String id, String name, FilterModel preset) {
    return ColorLook(id: id, name: name, filters: preset.filters);
  }
}

const List<double> colorLookIdentity = [
  1, 0, 0, 0, 0,
  0, 1, 0, 0, 0,
  0, 0, 1, 0, 0,
  0, 0, 0, 1, 0,
];

/// Mix [matrix] toward identity. [strength] 1 keeps the look, 0 removes it.
List<double> applyColorLookStrength(List<double> matrix, double strength) {
  final t = strength.clamp(0.0, 1.0);
  if (t >= 0.999) return List<double>.from(matrix);
  return List<double>.generate(
    20,
    (i) => colorLookIdentity[i] * (1 - t) + matrix[i] * t,
  );
}

List<double> mergeColorLookMatrices(List<List<double>> filters) {
  var combined = List<double>.from(colorLookIdentity);
  for (final filter in filters) {
    combined = _multiplyColorMatrices(filter, combined);
  }
  return combined;
}

List<double> _multiplyColorMatrices(List<double> a, List<double> b) {
  final out = List<double>.filled(20, 0);
  for (var row = 0; row < 4; row++) {
    for (var col = 0; col < 5; col++) {
      var sum = col == 4 ? a[row * 5 + 4] : 0.0;
      for (var k = 0; k < 4; k++) {
        sum += a[row * 5 + k] * b[k * 5 + col];
      }
      out[row * 5 + col] = sum;
    }
  }
  return out;
}

import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Qwen 2.1 image-to-image at 1K draws one of these canvases. A reference that
/// is a different size is letterboxed onto that canvas, and the empty strip
/// comes back purple. The upload is resized to the exact frame so nothing is
/// left for the model to pad. The whole photo stays in frame.
const List<(int, int)> qwenEditRatios = [
  (1, 1),
  (4, 3),
  (3, 4),
  (3, 2),
  (2, 3),
  (16, 9),
  (9, 16),
  (21, 9),
  (9, 21),
];

/// Pixel size of each 1K label. These are the frames Kie renders, and they
/// are not half of the 2K frames: 4:3 is 1184x896, not 1200x896.
const Map<String, (int, int)> qwen1kFrames = {
  '1:1': (1024, 1024),
  '4:3': (1184, 896),
  '3:4': (896, 1184),
  '3:2': (1248, 832),
  '2:3': (832, 1248),
  '16:9': (1376, 768),
  '9:16': (768, 1376),
  '21:9': (1568, 672),
  '9:21': (672, 1568),
};

/// Pixel size of each 2K label. These are not double the 1K frames.
const Map<String, (int, int)> qwen2kFrames = {
  '1:1': (2048, 2048),
  '4:3': (2400, 1792),
  '3:4': (1792, 2400),
  '3:2': (2528, 1696),
  '2:3': (1696, 2528),
  '16:9': (2752, 1536),
  '9:16': (1536, 2752),
  '21:9': (3136, 1344),
  '9:21': (1344, 3136),
};

const Map<String, double> qwenOutputAspect = {
  '1:1': 1024 / 1024,
  '4:3': 1184 / 896,
  '3:4': 896 / 1184,
  '3:2': 1248 / 832,
  '2:3': 832 / 1248,
  '16:9': 1376 / 768,
  '9:16': 768 / 1376,
  '21:9': 1568 / 672,
  '9:21': 672 / 1568,
};

Map<String, (int, int)> qwenFramesFor(String resolution) {
  return resolution.toUpperCase() == '2K' ? qwen2kFrames : qwen1kFrames;
}

class FrameFit {
  final Uint8List image;
  final String aspectRatio;
  final int sourceWidth;
  final int sourceHeight;
  final int x;
  final int y;
  final int width;
  final int height;
  final bool cropped;

  const FrameFit({
    required this.image,
    required this.aspectRatio,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.cropped,
  });
}

FrameFit? fitImageToQwenRatio(Uint8List source, {String resolution = '1K'}) {
  final decoded = img.decodeImage(source);
  if (decoded == null || decoded.width < 2 || decoded.height < 2) return null;
  final ratio = nearestQwenRatio(
    decoded.width / decoded.height,
    resolution: resolution,
  );
  return _fitDecoded(decoded, source, ratio, resolution: resolution);
}

Uint8List? fitBytesToAspect(
  Uint8List source,
  String aspectRatio, {
  String resolution = '1K',
}) {
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;
  final fitted = _fitDecoded(
    decoded,
    source,
    aspectRatio,
    resolution: resolution,
  );
  return fitted?.image;
}

/// Brush export is white paint on a transparent sheet. Kie local-edit treats
/// white as the area to change and black as the area to keep. The file it
/// receives is opaque white on the painted pixels and opaque black everywhere
/// else, the same size as the fitted photo.
Uint8List? qwenLocalEditMask(
  Uint8List painted, {
  int? width,
  int? height,
}) {
  final decoded = img.decodeImage(painted);
  if (decoded == null || decoded.width < 1 || decoded.height < 1) return null;
  final solid = img.Image(width: decoded.width, height: decoded.height);
  for (var y = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final pixel = decoded.getPixel(x, y);
      final isPaint = pixel.a.toInt() > 16;
      final value = isPaint ? 255 : 0;
      solid.setPixelRgba(x, y, value, value, value, 255);
    }
  }
  final fitted = width != null &&
          height != null &&
          width >= 2 &&
          height >= 2 &&
          (width != solid.width || height != solid.height)
      ? img.copyResize(
          solid,
          width: width,
          height: height,
          interpolation: img.Interpolation.nearest,
        )
      : solid;
  return Uint8List.fromList(img.encodePng(fitted));
}

Uint8List? cropBytesLikeFrame(Uint8List bytes, FrameFit fit) {
  if (!fit.cropped) return bytes;
  final decoded = img.decodeImage(bytes);
  if (decoded == null || fit.sourceWidth == 0 || fit.sourceHeight == 0) {
    return null;
  }
  final sx = decoded.width / fit.sourceWidth;
  final sy = decoded.height / fit.sourceHeight;
  var x = (fit.x * sx).round();
  var y = (fit.y * sy).round();
  var w = (fit.width * sx).round();
  var h = (fit.height * sy).round();
  x = x.clamp(0, decoded.width - 1);
  y = y.clamp(0, decoded.height - 1);
  w = w.clamp(1, decoded.width - x);
  h = h.clamp(1, decoded.height - y);
  final cropped = img.copyCrop(decoded, x: x, y: y, width: w, height: h);
  return Uint8List.fromList(img.encodePng(cropped));
}

String nearestQwenRatio(double aspect, {String resolution = '1K'}) {
  final frames = qwenFramesFor(resolution);
  var best = qwenEditRatios.first;
  var bestGap = double.infinity;
  for (final ratio in qwenEditRatios) {
    final label = '${ratio.$1}:${ratio.$2}';
    final size = frames[label];
    final target = size == null ? (ratio.$1 / ratio.$2) : size.$1 / size.$2;
    final gap = (aspect - target).abs() / aspect;
    if (gap < bestGap) {
      bestGap = gap;
      best = ratio;
    }
  }
  return '${best.$1}:${best.$2}';
}

FrameFit? _fitDecoded(
  img.Image decoded,
  Uint8List original,
  String aspectRatio, {
  String resolution = '1K',
}) {
  final parts = aspectRatio.split(':');
  if (parts.length != 2) return null;
  final rw = int.tryParse(parts[0]);
  final rh = int.tryParse(parts[1]);
  if (rw == null || rh == null || rw == 0 || rh == 0) return null;
  final frame = qwenFramesFor(resolution)[aspectRatio];
  if (frame == null) return null;
  final outW = frame.$1;
  final outH = frame.$2;
  if (decoded.width == outW && decoded.height == outH) {
    return FrameFit(
      image: original,
      aspectRatio: aspectRatio,
      sourceWidth: decoded.width,
      sourceHeight: decoded.height,
      x: 0,
      y: 0,
      width: outW,
      height: outH,
      cropped: false,
    );
  }
  // Fill the selected 1K or 2K canvas. A smaller photo would be padded, and
  // that pad is the purple band. Both original edges stay in the picture.
  final resized = img.copyResize(
    decoded,
    width: outW,
    height: outH,
    interpolation: img.Interpolation.cubic,
  );
  return FrameFit(
    image: Uint8List.fromList(img.encodePng(resized)),
    aspectRatio: aspectRatio,
    sourceWidth: decoded.width,
    sourceHeight: decoded.height,
    x: 0,
    y: 0,
    width: outW,
    height: outH,
    cropped: false,
  );
}

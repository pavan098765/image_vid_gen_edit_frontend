import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Qwen 2.1 image-to-image only emits these ratios. The pixel frames are the
/// ones the model actually draws: 16:9 is 2752x1536, not 16/9. The whole photo
/// is resized onto that frame so a full-body shot stays full. A crop would
/// cut the head or the feet, and a leftover sliver comes back as a purple edge.
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

const Map<String, double> qwenOutputAspect = {
  '1:1': 2048 / 2048,
  '4:3': 2400 / 1792,
  '3:4': 1792 / 2400,
  '3:2': 2528 / 1696,
  '2:3': 1696 / 2528,
  '16:9': 2752 / 1536,
  '9:16': 1536 / 2752,
  '21:9': 21 / 9,
  '9:21': 9 / 21,
};

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

FrameFit? fitImageToQwenRatio(Uint8List source) {
  final decoded = img.decodeImage(source);
  if (decoded == null || decoded.width < 2 || decoded.height < 2) return null;
  final ratio = nearestQwenRatio(decoded.width / decoded.height);
  return _fitDecoded(decoded, source, ratio);
}

Uint8List? fitBytesToAspect(Uint8List source, String aspectRatio) {
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;
  final fitted = _fitDecoded(decoded, source, aspectRatio);
  return fitted?.image;
}

/// Brush export is white paint on a transparent sheet. Kie local-edit kept
/// that painted region and edited the clear area, so a shirt recolor changed
/// every other person. The file Kie receives is opaque black on the painted
/// pixels and opaque white everywhere else, the same size as the fitted photo.
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
      final value = isPaint ? 0 : 255;
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

String nearestQwenRatio(double aspect) {
  var best = qwenEditRatios.first;
  var bestGap = double.infinity;
  for (final ratio in qwenEditRatios) {
    final label = '${ratio.$1}:${ratio.$2}';
    final target = qwenOutputAspect[label] ?? (ratio.$1 / ratio.$2);
    final gap = (aspect - target).abs() / aspect;
    if (gap < bestGap) {
      bestGap = gap;
      best = ratio;
    }
  }
  return '${best.$1}:${best.$2}';
}

FrameFit? _fitDecoded(img.Image decoded, Uint8List original, String aspectRatio) {
  final parts = aspectRatio.split(':');
  if (parts.length != 2) return null;
  final rw = int.tryParse(parts[0]);
  final rh = int.tryParse(parts[1]);
  if (rw == null || rh == null || rw == 0 || rh == 0) return null;
  final target = qwenOutputAspect[aspectRatio] ?? (rw / rh);
  final current = decoded.width / decoded.height;
  if ((current - target).abs() / current < 0.002) {
    return FrameFit(
      image: original,
      aspectRatio: aspectRatio,
      sourceWidth: decoded.width,
      sourceHeight: decoded.height,
      x: 0,
      y: 0,
      width: decoded.width,
      height: decoded.height,
      cropped: false,
    );
  }
  // Stretch one axis onto the model's frame. Both original edges stay in
  // the picture, so a full-body photo is not trimmed.
  final int outW;
  final int outH;
  if (current > target) {
    outH = decoded.height;
    outW = (decoded.height * target).round().clamp(2, 8192);
  } else {
    outW = decoded.width;
    outH = (decoded.width / target).round().clamp(2, 8192);
  }
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

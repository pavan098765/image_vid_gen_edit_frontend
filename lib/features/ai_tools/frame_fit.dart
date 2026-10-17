import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Qwen 2.1 image-to-image only emits these ratios. A photo that sits between
/// them comes back with a thin bar. Cropping the input onto the nearest ratio
/// lets the result fill that frame.
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
    final target = ratio.$1 / ratio.$2;
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
  final target = rw / rh;
  final current = decoded.width / decoded.height;
  var cropW = decoded.width;
  var cropH = decoded.height;
  if ((current - target).abs() / current >= 0.002) {
    if (current > target) {
      cropW = (decoded.height * target).round().clamp(1, decoded.width);
    } else {
      cropH = (decoded.width / target).round().clamp(1, decoded.height);
    }
  }
  final x = ((decoded.width - cropW) / 2).round();
  final y = ((decoded.height - cropH) / 2).round();
  final cropped = cropW != decoded.width || cropH != decoded.height;
  final bytes = cropped
      ? Uint8List.fromList(img.encodePng(
          img.copyCrop(decoded, x: x, y: y, width: cropW, height: cropH),
        ))
      : original;
  return FrameFit(
    image: bytes,
    aspectRatio: aspectRatio,
    sourceWidth: decoded.width,
    sourceHeight: decoded.height,
    x: x,
    y: y,
    width: cropW,
    height: cropH,
    cropped: cropped,
  );
}

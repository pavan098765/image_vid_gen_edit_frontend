import 'dart:ui';

/// Pixel crop rectangle from a normalized source crop and the source size.
Rect? cropPixels(Rect? cropNorm, Size source) {
  if (cropNorm == null) return null;
  final left = (cropNorm.left * source.width).clamp(0.0, source.width);
  final top = (cropNorm.top * source.height).clamp(0.0, source.height);
  final width = (cropNorm.width * source.width).clamp(1.0, source.width - left);
  final height =
      (cropNorm.height * source.height).clamp(1.0, source.height - top);
  return Rect.fromLTWH(left, top, width, height);
}

/// Output canvas size for an aspect preset and a quality height.
Size canvasSizeFor({
  required double? aspectRatio,
  required Size source,
  required int qualityHeight,
}) {
  if (aspectRatio == null || aspectRatio <= 0) return source;
  final h = qualityHeight.toDouble();
  return Size(h * aspectRatio, h);
}

/// Per-clip crop mapped to native segment transform space (crop pixels, not canvas).
class MappedSegmentCrop {
  final Offset offset;
  final Size size;

  const MappedSegmentCrop({required this.offset, required this.size});
}

MappedSegmentCrop mappedSegmentCrop({
  required Rect? cropNorm,
  required Size source,
  required Size canvas,
}) {
  final crop = cropPixels(cropNorm, source);
  if (crop == null) {
    return MappedSegmentCrop(offset: Offset.zero, size: canvas);
  }
  return MappedSegmentCrop(
    offset: Offset(crop.left, crop.top),
    size: Size(crop.width, crop.height),
  );
}

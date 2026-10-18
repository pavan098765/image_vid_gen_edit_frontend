import 'dart:math' as math;
import 'dart:ui';

/// Largest centered rectangle of [targetRatio] (width / height) that fits in
/// a bitmap of [width] x [height].
Rect centerCropRect({
  required int width,
  required int height,
  required double targetRatio,
}) {
  if (width <= 0 || height <= 0 || targetRatio <= 0) {
    return Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  }
  final sourceRatio = width / height;
  double cropW;
  double cropH;
  if (sourceRatio > targetRatio) {
    cropH = height.toDouble();
    cropW = cropH * targetRatio;
  } else {
    cropW = width.toDouble();
    cropH = cropW / targetRatio;
  }
  cropW = math.min(cropW, width.toDouble());
  cropH = math.min(cropH, height.toDouble());
  final left = (width - cropW) / 2;
  final top = (height - cropH) / 2;
  return Rect.fromLTWH(left, top, cropW, cropH);
}

/// Canvas size that matches [targetRatio] while keeping every source pixel.
/// The longer side stays, and the other side grows so the photo is padded
/// rather than cropped.
(int, int) containCanvasSize({
  required int width,
  required int height,
  required double targetRatio,
}) {
  if (width <= 0 || height <= 0 || targetRatio <= 0) return (width, height);
  final sourceRatio = width / height;
  if ((sourceRatio - targetRatio).abs() / targetRatio <= 0.02) {
    return (width, height);
  }
  if (sourceRatio > targetRatio) {
    final canvasHeight = (width / targetRatio).round().clamp(1, 100000);
    return (width, canvasHeight);
  }
  final canvasWidth = (height * targetRatio).round().clamp(1, 100000);
  return (canvasWidth, height);
}

/// True when the source aspect is already within 2% of [targetRatio].
bool isAlreadyTargetRatio({
  required int width,
  required int height,
  required double targetRatio,
}) {
  if (width <= 0 || height <= 0 || targetRatio <= 0) return false;
  final sourceRatio = width / height;
  return (sourceRatio - targetRatio).abs() / targetRatio <= 0.02;
}

int bulkPhotoTotal({required int unitCost, required int count}) {
  if (count < 0) return 0;
  return unitCost * count;
}

const int kBulkPhotosNonVip = 5;
const int kBulkPhotosVip = 15;

bool bulkCountAllowed({required int count, required bool isVip}) {
  if (count < 1) return false;
  final cap = isVip ? kBulkPhotosVip : kBulkPhotosNonVip;
  return count <= cap;
}

List<String> favoriteIdsInCatalog({
  required List<String> storedIds,
  required Set<String> knownIds,
}) {
  return storedIds.where(knownIds.contains).toList();
}

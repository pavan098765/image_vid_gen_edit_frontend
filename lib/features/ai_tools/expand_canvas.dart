import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ExpandPair {
  final Uint8List canvas;
  final Uint8List mask;

  const ExpandPair({required this.canvas, required this.mask});
}

class ExpandRequest {
  final Uint8List? image;
  final int top;
  final int bottom;
  final int left;
  final int right;
  final int width;
  final int height;
  final String? error;

  const ExpandRequest({
    this.image,
    this.top = 0,
    this.bottom = 0,
    this.left = 0,
    this.right = 0,
    this.width = 0,
    this.height = 0,
    this.error,
  });

  const ExpandRequest.error(String message)
      : image = null,
        top = 0,
        bottom = 0,
        left = 0,
        right = 0,
        width = 0,
        height = 0,
        error = message;
}

int _down64(int value) => (value ~/ 64) * 64;

int _up64(int value) => ((value + 63) ~/ 64) * 64;

/// Outpaint margins for Kala Vista and Kala Touch.
/// The photo is cropped onto the 64-pixel grid, then the canvas grows in
/// steps of 64 so width equals the photo plus the side margins.
ExpandRequest buildRunwareOutpaint(
  Uint8List source,
  Map<String, dynamic> inputs,
) {
  final decoded = img.decodeImage(source);
  if (decoded == null) {
    return const ExpandRequest.error('Could not read that image.');
  }
  final cropW = _down64(decoded.width);
  final cropH = _down64(decoded.height);
  if (cropW < 64 || cropH < 64) {
    return const ExpandRequest.error('This image is too small to expand.');
  }
  final cropped = img.copyCrop(
    decoded,
    x: 0,
    y: 0,
    width: cropW,
    height: cropH,
  );
  final aspect = _ratio(inputs['aspect_ratio']?.toString() ?? '16:9');
  final srcAspect = cropW / cropH;
  var canvasW = cropW;
  var canvasH = cropH;
  if ((aspect - srcAspect).abs() < 0.02) {
    if (cropW <= cropH) {
      canvasW = cropW + 256;
    } else {
      canvasH = cropH + 256;
    }
  } else if (aspect >= srcAspect) {
    canvasH = cropH;
    canvasW = _up64((cropH * aspect).round());
  } else {
    canvasW = cropW;
    canvasH = _up64((cropW / aspect).round());
  }
  canvasW = _up64(canvasW);
  canvasH = _up64(canvasH);
  if (canvasW > 2048 ||
      canvasH > 2048 ||
      canvasW < cropW ||
      canvasH < cropH ||
      (canvasW == cropW && canvasH == cropH)) {
    return const ExpandRequest.error(
      'This image is too large for that shape.',
    );
  }
  final extraW = canvasW - cropW;
  final extraH = canvasH - cropH;
  final left = (extraW ~/ 2) ~/ 64 * 64;
  final top = (extraH ~/ 2) ~/ 64 * 64;
  return ExpandRequest(
    image: Uint8List.fromList(img.encodePng(cropped)),
    top: top,
    bottom: extraH - top,
    left: left,
    right: extraW - left,
    width: canvasW,
    height: canvasH,
  );
}

/// Place the photo on a larger canvas and paint a mask for the new border.
/// White in the mask is the area the model may fill. Black stays the photo.
ExpandPair? buildExpandPair(Uint8List source, Map<String, dynamic> inputs) {
  final decoded = img.decodeImage(source);
  if (decoded == null) return null;

  final custom = inputs['is_custom']?.toString() == 'true';
  final scale = double.tryParse(inputs['custom_scale']?.toString() ?? '') ?? 0.72;
  final placed = _customPlacement(decoded, inputs);
  late int canvasW;
  late int canvasH;
  if (placed != null) {
    canvasW = placed.width;
    canvasH = placed.height;
  } else if (custom && scale > 0 && scale < 1) {
    canvasW = (decoded.width / scale).round();
    canvasH = (decoded.height / scale).round();
  } else {
    final aspect = _ratio(inputs['aspect_ratio']?.toString() ?? '16:9');
    final srcAspect = decoded.width / decoded.height;
    if (aspect >= srcAspect) {
      canvasH = decoded.height;
      canvasW = (decoded.height * aspect).round();
    } else {
      canvasW = decoded.width;
      canvasH = (decoded.width / aspect).round();
    }
  }
  if (canvasW <= decoded.width && canvasH <= decoded.height) {
    canvasW = (decoded.width * 1.2).round();
    canvasH = (decoded.height * 1.2).round();
  }
  canvasW = canvasW.clamp(decoded.width, 2048);
  canvasH = canvasH.clamp(decoded.height, 2048);

  final align = (inputs['alignment'] ?? 'Middle').toString();
  var left = placed?.left ?? ((canvasW - decoded.width) / 2).round();
  var top = placed?.top ?? ((canvasH - decoded.height) / 2).round();
  if (placed == null) {
    switch (align) {
    case 'Left':
      left = 0;
      break;
    case 'Right':
      left = canvasW - decoded.width;
      break;
    case 'Top':
      top = 0;
      break;
    case 'Bottom':
      top = canvasH - decoded.height;
      break;
    }
  }
  left = left.clamp(0, canvasW - decoded.width);
  top = top.clamp(0, canvasH - decoded.height);

  final canvas = img.Image(width: canvasW, height: canvasH);
  // Flat gray, not a stretched edge pixel. A one-pixel smear is what comes
  // back as the vertical color bands.
  img.fill(canvas, color: img.ColorRgb8(128, 128, 128));
  img.compositeImage(canvas, decoded, dstX: left, dstY: top);

  final mask = img.Image(width: canvasW, height: canvasH);
  img.fill(mask, color: img.ColorRgb8(255, 255, 255));
  _keepPhoto(mask, left, top, decoded.width, decoded.height);

  return ExpandPair(
    canvas: Uint8List.fromList(img.encodePng(canvas)),
    mask: Uint8List.fromList(img.encodePng(mask)),
  );
}

class _Placement {
  final int width;
  final int height;
  final int left;
  final int top;

  const _Placement(this.width, this.height, this.left, this.top);
}

_Placement? _customPlacement(img.Image source, Map<String, dynamic> inputs) {
  if (inputs['is_custom']?.toString() != 'true') return null;
  final uiW = double.tryParse(inputs['canvas_width']?.toString() ?? '');
  final uiH = double.tryParse(inputs['canvas_height']?.toString() ?? '');
  final photoW = double.tryParse(inputs['image_width']?.toString() ?? '');
  final photoH = double.tryParse(inputs['image_height']?.toString() ?? '');
  final photoLeft = double.tryParse(inputs['image_left']?.toString() ?? '');
  final photoTop = double.tryParse(inputs['image_top']?.toString() ?? '');
  if (uiW == null ||
      uiH == null ||
      photoW == null ||
      photoH == null ||
      photoLeft == null ||
      photoTop == null ||
      photoW < 8 ||
      photoH < 8) {
    return null;
  }
  final pixelsPerUi = source.width / photoW;
  var canvasW = (uiW * pixelsPerUi).round();
  var canvasH = (uiH * pixelsPerUi).round();
  canvasW = canvasW.clamp(source.width + 8, 2048);
  canvasH = canvasH.clamp(source.height + 8, 2048);
  final fit = (canvasW / (uiW * pixelsPerUi)).clamp(0.01, 1.0);
  final left = (photoLeft * pixelsPerUi * fit).round();
  final top = (photoTop * pixelsPerUi * fit).round();
  return _Placement(canvasW, canvasH, left, top);
}

const _feather = 32;

/// White is the area the model may paint. The photo stays black, with a short
/// fade at each new edge so the join is not a hard rectangle.
void _keepPhoto(img.Image mask, int left, int top, int srcW, int srcH) {
  final rightPad = left + srcW < mask.width;
  final bottomPad = top + srcH < mask.height;
  for (var y = top; y < top + srcH; y++) {
    for (var x = left; x < left + srcW; x++) {
      var edge = _feather;
      if (top > 0) edge = _min(edge, y - top);
      if (bottomPad) edge = _min(edge, top + srcH - 1 - y);
      if (left > 0) edge = _min(edge, x - left);
      if (rightPad) edge = _min(edge, left + srcW - 1 - x);
      final kept = edge >= _feather;
      final value = kept ? 0 : (255 * (1 - edge / _feather)).round();
      mask.setPixelRgba(x, y, value, value, value, 255);
    }
  }
}

int _min(int a, int b) => a < b ? a : b;

double _ratio(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return 16 / 9;
  final w = double.tryParse(parts[0]) ?? 16;
  final h = double.tryParse(parts[1]) ?? 9;
  if (h == 0) return 16 / 9;
  return w / h;
}

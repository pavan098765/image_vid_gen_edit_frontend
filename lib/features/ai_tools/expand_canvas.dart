import 'dart:typed_data';

import 'package:image/image.dart' as img;

class ExpandPair {
  final Uint8List canvas;
  final Uint8List mask;

  const ExpandPair({required this.canvas, required this.mask});
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
  _extendEdges(canvas, decoded, left, top);
  img.compositeImage(canvas, decoded, dstX: left, dstY: top);

  final mask = img.Image(width: canvasW, height: canvasH);
  img.fill(mask, color: img.ColorRgb8(255, 255, 255));
  img.fillRect(
    mask,
    x1: left,
    y1: top,
    x2: left + decoded.width - 1,
    y2: top + decoded.height - 1,
    color: img.ColorRgb8(0, 0, 0),
  );

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

void _extendEdges(img.Image canvas, img.Image source, int left, int top) {
  if (top > 0) {
    final row = img.copyCrop(source, x: 0, y: 0, width: source.width, height: 1);
    final band = img.copyResize(row, width: canvas.width, height: top);
    img.compositeImage(canvas, band);
  }
  final bottom = canvas.height - top - source.height;
  if (bottom > 0) {
    final row = img.copyCrop(
      source,
      x: 0,
      y: source.height - 1,
      width: source.width,
      height: 1,
    );
    final band = img.copyResize(row, width: canvas.width, height: bottom);
    img.compositeImage(canvas, band, dstY: top + source.height);
  }
  if (left > 0) {
    final col = img.copyCrop(source, x: 0, y: 0, width: 1, height: source.height);
    final band = img.copyResize(col, width: left, height: source.height);
    img.compositeImage(canvas, band, dstY: top);
  }
  final right = canvas.width - left - source.width;
  if (right > 0) {
    final col = img.copyCrop(
      source,
      x: source.width - 1,
      y: 0,
      width: 1,
      height: source.height,
    );
    final band = img.copyResize(col, width: right, height: source.height);
    img.compositeImage(canvas, band, dstX: left + source.width, dstY: top);
  }
}

double _ratio(String value) {
  final parts = value.split(':');
  if (parts.length != 2) return 16 / 9;
  final w = double.tryParse(parts[0]) ?? 16;
  final h = double.tryParse(parts[1]) ?? 9;
  if (h == 0) return 16 / 9;
  return w / h;
}

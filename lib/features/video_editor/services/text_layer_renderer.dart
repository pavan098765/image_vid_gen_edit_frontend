import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/clip_model.dart';

/// Renders a [TextClip] (or a substring) to a transparent PNG for the
/// native video compositor's image layers.
class TextLayerRenderer {
  TextLayerRenderer._();

  static Future<Uint8List> render(
    TextClip clip, {
    String? textOverride,
    double maxWidth = 1080,
    double pixelRatio = 2,
  }) async {
    final text = textOverride ?? clip.text;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: clip.fontFamily,
          fontSize: clip.fontSize * pixelRatio,
          color: clip.color,
          fontWeight: clip.isBold ? FontWeight.w700 : FontWeight.w500,
          fontStyle: clip.isItalic ? FontStyle.italic : FontStyle.normal,
          backgroundColor: clip.backgroundColor.alpha == 0
              ? null
              : clip.backgroundColor,
        ),
      ),
      textAlign: clip.textAlign,
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: maxWidth * pixelRatio);
    final width = painter.width.ceil().clamp(1, 4096);
    final height = painter.height.ceil().clamp(1, 4096);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (bytes == null) return Uint8List(0);
    return bytes.buffer.asUint8List();
  }
}

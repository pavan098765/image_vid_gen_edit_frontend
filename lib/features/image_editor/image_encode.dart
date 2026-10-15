import 'dart:typed_data';

import 'package:image/image.dart' as imglib;

enum ImageSaveFormat { jpeg, png, webp }

Uint8List encodeEditedImage(
  Uint8List bytes, {
  required ImageSaveFormat format,
  int maxEdge = 0,
  int jpegQuality = 92,
}) {
  final decoded = imglib.decodeImage(bytes);
  if (decoded == null) return bytes;
  var img = decoded;
  if (maxEdge > 0) {
    final longest = img.width > img.height ? img.width : img.height;
    if (longest > maxEdge) {
      img = imglib.copyResize(
        img,
        width: img.width >= img.height ? maxEdge : null,
        height: img.height > img.width ? maxEdge : null,
      );
    }
  }
  switch (format) {
    case ImageSaveFormat.jpeg:
      return Uint8List.fromList(imglib.encodeJpg(img, quality: jpegQuality));
    case ImageSaveFormat.png:
      return Uint8List.fromList(imglib.encodePng(img));
    case ImageSaveFormat.webp:
      return Uint8List.fromList(imglib.encodeWebP(img, lossless: true));
  }
}

String extensionFor(ImageSaveFormat format) {
  switch (format) {
    case ImageSaveFormat.jpeg:
      return 'jpg';
    case ImageSaveFormat.png:
      return 'png';
    case ImageSaveFormat.webp:
      return 'webp';
  }
}

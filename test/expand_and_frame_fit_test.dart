import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/expand_canvas.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/frame_fit.dart';

void main() {
  test('expand pads with gray instead of stretching an edge pixel', () {
    final source = img.Image(width: 80, height: 40);
    img.fill(source, color: img.ColorRgb8(20, 40, 200));
    for (var x = 0; x < source.width; x++) {
      source.setPixelRgba(x, 0, 200, 10, 10, 255);
    }
    final bytes = Uint8List.fromList(img.encodePng(source));
    final built = buildExpandPair(bytes, const {'aspect_ratio': '9:16'});
    expect(built, isNotNull);
    final canvas = img.decodePng(built!.canvas)!;
    expect(canvas.height, greaterThan(source.height));
    final top = canvas.getPixel(canvas.width ~/ 2, 0);
    expect(top.r.toInt(), 128);
    expect(top.g.toInt(), 128);
    expect(top.b.toInt(), 128);
  });

  test('a photo is resized onto the Qwen frame without cutting either edge', () {
    final wide = img.Image(width: 1920, height: 1080);
    img.fill(wide, color: img.ColorRgb8(10, 10, 10));
    final fit = fitImageToQwenRatio(Uint8List.fromList(img.encodePng(wide)));
    expect(fit, isNotNull);
    expect(fit!.aspectRatio, '16:9');
    expect(fit.cropped, isFalse);
    final resized = img.decodePng(fit.image)!;
    expect(resized.width, 1376);
    expect(resized.height, 768);

    final sharp = fitImageToQwenRatio(
      Uint8List.fromList(img.encodePng(wide)),
      resolution: '2K',
    );
    expect(sharp!.aspectRatio, '16:9');
    final sharpImage = img.decodePng(sharp.image)!;
    expect(sharpImage.width, 2752);
    expect(sharpImage.height, 1536);

    final body = img.Image(width: 100, height: 220);
    img.fill(body, color: img.ColorRgb8(10, 10, 10));
    final tall = fitImageToQwenRatio(Uint8List.fromList(img.encodePng(body)));
    expect(tall, isNotNull);
    expect(tall!.aspectRatio, '9:21');
    final tallImage = img.decodePng(tall.image)!;
    expect(tallImage.width, 672);
    expect(tallImage.height, 1568);
  });

  test('a painted edit mask is white on the paint and black everywhere else', () {
    final mask = img.Image(width: 8, height: 8, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 0));
    mask.setPixelRgba(3, 3, 255, 255, 255, 255);
    final bytes = qwenLocalEditMask(
      Uint8List.fromList(img.encodePng(mask)),
      width: 8,
      height: 8,
    );
    expect(bytes, isNotNull);
    final solid = img.decodePng(bytes!)!;
    final painted = solid.getPixel(3, 3);
    final rest = solid.getPixel(0, 0);
    expect(painted.r.toInt(), 255);
    expect(painted.a.toInt(), 255);
    expect(rest.r.toInt(), 0);
    expect(rest.a.toInt(), 255);
  });
}

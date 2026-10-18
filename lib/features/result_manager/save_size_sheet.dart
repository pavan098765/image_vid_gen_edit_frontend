import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;
import 'package:kala_ai_create_images_videos_with_ai/core/center_crop.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';

class _SizePreset {
  final String label;
  final double ratio;
  const _SizePreset(this.label, this.ratio);
}

const _presets = [
  _SizePreset('Square post', 1),
  _SizePreset('Portrait post', 4 / 5),
  _SizePreset('Story', 9 / 16),
  _SizePreset('Thumbnail', 16 / 9),
];

Future<void> showSaveSizeSheet(BuildContext context, File source) async {
  final bytes = await source.readAsBytes();
  final decoded = imglib.decodeImage(bytes);
  if (!context.mounted) return;
  if (decoded == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not read that photo.')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Save a copy',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The whole photo stays. Empty space is filled to match the shape. 0 credits.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ..._presets.map((p) {
                final already = isAlreadyTargetRatio(
                  width: decoded.width,
                  height: decoded.height,
                  targetRatio: p.ratio,
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  minVerticalPadding: 12,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56,
                      child: AspectRatio(
                        aspectRatio: p.ratio,
                        child: ColoredBox(
                          color: _padUiColor(decoded),
                          child: Image.memory(bytes, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                  title: Text(p.label),
                  subtitle: already ? const Text('Already this shape') : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _saveFittedCopy(context, source, decoded, bytes, p);
                  },
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}

Color _padUiColor(imglib.Image image) {
  final pixel = _padColor(image);
  return Color.fromARGB(255, pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
}

imglib.Color _padColor(imglib.Image image) {
  final corners = [
    image.getPixel(0, 0),
    image.getPixel(image.width - 1, 0),
    image.getPixel(0, image.height - 1),
    image.getPixel(image.width - 1, image.height - 1),
  ];
  var r = 0;
  var g = 0;
  var b = 0;
  for (final pixel in corners) {
    r += pixel.r.toInt();
    g += pixel.g.toInt();
    b += pixel.b.toInt();
  }
  final n = corners.length;
  return imglib.ColorRgb8(r ~/ n, g ~/ n, b ~/ n);
}

imglib.Image fitImageOnCanvas(imglib.Image source, double targetRatio) {
  final size = containCanvasSize(
    width: source.width,
    height: source.height,
    targetRatio: targetRatio,
  );
  if (size.$1 == source.width && size.$2 == source.height) return source;
  final canvas = imglib.Image(width: size.$1, height: size.$2);
  imglib.fill(canvas, color: _padColor(source));
  final scaleW = size.$1 / source.width;
  final scaleH = size.$2 / source.height;
  final scale = scaleW < scaleH ? scaleW : scaleH;
  final fittedW = (source.width * scale).round().clamp(1, size.$1);
  final fittedH = (source.height * scale).round().clamp(1, size.$2);
  final fitted = (fittedW == source.width && fittedH == source.height)
      ? source
      : imglib.copyResize(
          source,
          width: fittedW,
          height: fittedH,
          interpolation: imglib.Interpolation.cubic,
        );
  imglib.compositeImage(
    canvas,
    fitted,
    dstX: ((size.$1 - fitted.width) / 2).round(),
    dstY: ((size.$2 - fitted.height) / 2).round(),
  );
  return canvas;
}

Future<void> _saveFittedCopy(
  BuildContext context,
  File source,
  imglib.Image decoded,
  Uint8List originalBytes,
  _SizePreset preset,
) async {
  final already = isAlreadyTargetRatio(
    width: decoded.width,
    height: decoded.height,
    targetRatio: preset.ratio,
  );
  Uint8List outBytes;
  if (already) {
    outBytes = originalBytes;
  } else {
    final fitted = fitImageOnCanvas(decoded, preset.ratio);
    final lower = source.path.toLowerCase();
    outBytes = lower.endsWith('.png')
        ? Uint8List.fromList(imglib.encodePng(fitted))
        : Uint8List.fromList(imglib.encodeJpg(fitted, quality: 92));
  }

  if (!context.mounted) return;
  await FileService.saveFile(
    context,
    outBytes,
    showPreview: false,
    extension: source.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg',
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Saved a copy')),
  );
}

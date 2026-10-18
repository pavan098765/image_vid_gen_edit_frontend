import 'dart:io';
import 'dart:isolate';
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

/// Longest edge kept when padding a copy. Phone photos stay sharp enough
/// for a post, and the canvas no longer grows into a multi-second encode.
const int _kSaveSizeLongEdge = 2048;

Future<void> showSaveSizeSheet(BuildContext context, File source) async {
  final bytes = await source.readAsBytes();
  final preview = await Isolate.run(() => buildSaveSizePreview(bytes));
  if (!context.mounted) return;
  if (preview == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not read that photo.')),
    );
    return;
  }
  final width = preview['width']! as int;
  final height = preview['height']! as int;
  final thumb = preview['thumb']! as Uint8List;
  final pad = Color.fromARGB(
    255,
    preview['r']! as int,
    preview['g']! as int,
    preview['b']! as int,
  );

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
                  width: width,
                  height: height,
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
                          color: pad,
                          child: Image.memory(thumb, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                  ),
                  title: Text(p.label),
                  subtitle: already ? const Text('Already this shape') : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _saveFittedCopy(
                      context,
                      source,
                      bytes,
                      p,
                      already: already,
                    );
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

Map<String, Object>? buildSaveSizePreview(Uint8List bytes) {
  final decoded = imglib.decodeImage(bytes);
  if (decoded == null) return null;
  final thumb = _limitLongEdge(decoded, 480);
  final pixel = _padColor(decoded);
  return {
    'width': decoded.width,
    'height': decoded.height,
    'r': pixel.r.toInt(),
    'g': pixel.g.toInt(),
    'b': pixel.b.toInt(),
    'thumb': Uint8List.fromList(imglib.encodeJpg(thumb, quality: 70)),
  };
}

Uint8List encodeSaveSizeCopy(Map<String, Object> args) {
  final bytes = args['bytes']! as Uint8List;
  final ratio = (args['ratio']! as num).toDouble();
  final png = args['png']! as bool;
  final decoded = imglib.decodeImage(bytes);
  if (decoded == null) return bytes;
  if (isAlreadyTargetRatio(
    width: decoded.width,
    height: decoded.height,
    targetRatio: ratio,
  )) {
    return bytes;
  }
  final fitted = fitImageOnCanvas(_limitLongEdge(decoded, _kSaveSizeLongEdge), ratio);
  return png
      ? Uint8List.fromList(imglib.encodePng(fitted))
      : Uint8List.fromList(imglib.encodeJpg(fitted, quality: 90));
}

imglib.Image _limitLongEdge(imglib.Image source, int longEdge) {
  final long = source.width > source.height ? source.width : source.height;
  if (long <= longEdge) return source;
  final scale = longEdge / long;
  return imglib.copyResize(
    source,
    width: (source.width * scale).round().clamp(1, longEdge),
    height: (source.height * scale).round().clamp(1, longEdge),
    interpolation: imglib.Interpolation.linear,
  );
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
          interpolation: imglib.Interpolation.linear,
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
  Uint8List originalBytes,
  _SizePreset preset, {
  required bool already,
}) async {
  final png = source.path.toLowerCase().endsWith('.png');
  final Uint8List outBytes;
  if (already) {
    outBytes = originalBytes;
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preparing your copy...')),
      );
    }
    final payload = <String, Object>{
      'bytes': originalBytes,
      'ratio': preset.ratio,
      'png': png,
    };
    outBytes = await Isolate.run(() => encodeSaveSizeCopy(payload));
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
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

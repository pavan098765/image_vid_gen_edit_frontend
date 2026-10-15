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
                'This crops the photo. It does not add detail. 0 credits.',
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
                        child: Image.memory(bytes, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  title: Text(p.label),
                  subtitle: already ? const Text('Already this shape') : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _saveCroppedCopy(context, source, decoded, bytes, p);
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

Future<void> _saveCroppedCopy(
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
    final rect = centerCropRect(
      width: decoded.width,
      height: decoded.height,
      targetRatio: preset.ratio,
    );
    final cropped = imglib.copyCrop(
      decoded,
      x: rect.left.round().clamp(0, decoded.width - 1),
      y: rect.top.round().clamp(0, decoded.height - 1),
      width: rect.width.round().clamp(1, decoded.width),
      height: rect.height.round().clamp(1, decoded.height),
    );
    final lower = source.path.toLowerCase();
    outBytes = lower.endsWith('.png')
        ? Uint8List.fromList(imglib.encodePng(cropped))
        : Uint8List.fromList(imglib.encodeJpg(cropped, quality: 92));
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

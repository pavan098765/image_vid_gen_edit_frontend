import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/frame_fit.dart';

/// Photo with the edit mask laid on top, using the same frame the upload uses.
class MaskLayoutPreviewPage extends StatefulWidget {
  final Uint8List photo;
  final Uint8List brushMask;
  final bool fitToQwenFrame;
  final String resolution;

  const MaskLayoutPreviewPage({
    super.key,
    required this.photo,
    required this.brushMask,
    required this.fitToQwenFrame,
    required this.resolution,
  });

  @override
  State<MaskLayoutPreviewPage> createState() => _MaskLayoutPreviewPageState();
}

class _MaskLayoutPreviewPageState extends State<MaskLayoutPreviewPage> {
  Uint8List? _photo;
  Uint8List? _mask;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final prepared = await Isolate.run(
        () => prepareMaskLayoutPreview({
          'photo': widget.photo,
          'brush': widget.brushMask,
          'fit': widget.fitToQwenFrame,
          'resolution': widget.resolution,
        }),
      );
      if (!mounted) return;
      setState(() {
        _photo = prepared['photo'];
        _mask = prepared['mask'];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
  final photo = _photo;
  final mask = _mask;
  return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Mask on photo'),
      ),
      body: _failed
          ? const Center(
              child: Text(
                'Could not build the mask preview.',
                style: TextStyle(color: Colors.white),
              ),
            )
          : photo == null || mask == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        minScale: 1,
                        maxScale: 5,
                        child: Stack(
                          fit: StackFit.expand,
                          alignment: Alignment.center,
                          children: [
                            Image.memory(photo, fit: BoxFit.contain),
                            ColorFiltered(
                              colorFilter: ColorFilter.mode(
                                Colors.red.withValues(alpha: 0.72),
                                BlendMode.srcATop,
                              ),
                              child: Image.memory(mask, fit: BoxFit.contain),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SafeArea(
                      top: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: Text(
                          'Red is the mask sent with this photo. It should cover the area you painted.',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

Map<String, Uint8List> prepareMaskLayoutPreview(Map<String, Object> args) {
  final photo = args['photo']! as Uint8List;
  final brush = args['brush']! as Uint8List;
  final fit = args['fit'] == true;
  final resolution = args['resolution'] as String? ?? '1K';
  if (!fit) {
    final painted = qwenLocalEditMask(brush) ?? brush;
    return {'photo': photo, 'mask': _paintOnly(painted)};
  }
  final fitted = fitImageToQwenRatio(photo, resolution: resolution);
  final photoOut = fitted?.image ?? photo;
  final mask = qwenLocalEditMask(
        brush,
        width: fitted?.width,
        height: fitted?.height,
      ) ??
      brush;
  return {'photo': photoOut, 'mask': _paintOnly(mask)};
}

Uint8List _paintOnly(Uint8List solidMask) {
  final decoded = img.decodeImage(solidMask);
  if (decoded == null) return solidMask;
  for (var y = 0; y < decoded.height; y++) {
    for (var x = 0; x < decoded.width; x++) {
      final paint = decoded.getPixel(x, y).r.toInt() > 127;
      decoded.setPixelRgba(x, y, 255, 255, 255, paint ? 255 : 0);
    }
  }
  return Uint8List.fromList(img.encodePng(decoded));
}

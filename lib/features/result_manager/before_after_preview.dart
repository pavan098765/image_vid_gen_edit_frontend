import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class BeforeAfterPreviewPage extends StatefulWidget {
  final File resultFile;
  final File originalFile;

  const BeforeAfterPreviewPage({
    super.key,
    required this.resultFile,
    required this.originalFile,
  });

  @override
  State<BeforeAfterPreviewPage> createState() => _BeforeAfterPreviewPageState();
}

class _BeforeAfterPreviewPageState extends State<BeforeAfterPreviewPage> {
  double _split = 0.5;
  Size? _resultSize;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    final result = await _readSize(widget.resultFile);
    final original = result ?? await _readSize(widget.originalFile);
    if (!mounted) return;
    setState(() {
      _resultSize = original;
      _measured = true;
    });
  }

  Future<Size?> _readSize(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final size = Size(image.width.toDouble(), image.height.toDouble());
        image.dispose();
        if (size.width <= 0 || size.height <= 0) return null;
        return size;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Compare'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (!_measured) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (constraints.maxWidth < 8 || constraints.maxHeight < 8) {
                    return const SizedBox.shrink();
                  }
                  final frame = _frameSize(constraints);
                  return Center(
                    child: SizedBox(
                      width: frame.width,
                      height: frame.height,
                      child: GestureDetector(
                        onHorizontalDragUpdate: (d) {
                          setState(() {
                            _split = (_split + d.delta.dx / frame.width)
                                .clamp(0.04, 0.96);
                          });
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _cover(widget.resultFile),
                              ClipRect(
                                clipper: _LeftRevealClipper(_split),
                                child: _cover(widget.originalFile),
                              ),
                              Positioned(
                                left: frame.width * _split - 1,
                                top: 0,
                                bottom: 0,
                                child: const ColoredBox(
                                  color: Colors.white,
                                  child: SizedBox(width: 2),
                                ),
                              ),
                              Positioned(
                                left: frame.width * _split - 18,
                                top: frame.height / 2 - 18,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: cs.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.drag_handle,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(
                children: [
                  const Text(
                    'Original',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    'Drag to compare',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Result',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One shared rectangle, using the result's shape, so neither photo can
  /// stick out behind the other.
  Size _frameSize(BoxConstraints constraints) {
    final known = _resultSize;
    final aspect = (known == null || known.height <= 0)
        ? 1.0
        : known.width / known.height;
    var width = constraints.maxWidth - 24;
    var height = width / aspect;
    final maxHeight = constraints.maxHeight - 8;
    if (height > maxHeight) {
      height = maxHeight;
      width = height * aspect;
    }
    return Size(width.clamp(1, constraints.maxWidth), height.clamp(1, constraints.maxHeight));
  }

  Widget _cover(File file) {
    return Image.file(
      file,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
    );
  }
}

class _LeftRevealClipper extends CustomClipper<Rect> {
  final double split;

  _LeftRevealClipper(this.split);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(0, 0, size.width * split, size.height);
  }

  @override
  bool shouldReclip(_LeftRevealClipper oldClipper) => oldClipper.split != split;
}

void openBeforeAfterPreview(
  BuildContext context, {
  required File resultFile,
  required File originalFile,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BeforeAfterPreviewPage(
        resultFile: resultFile,
        originalFile: originalFile,
      ),
    ),
  );
}

import 'dart:io';

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
                  return GestureDetector(
                    onHorizontalDragUpdate: (d) {
                      setState(() {
                        _split = (_split + d.delta.dx / constraints.maxWidth)
                            .clamp(0.04, 0.96);
                      });
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: Colors.black),
                        _framedImage(widget.resultFile),
                        ClipRect(
                          clipper: _LeftRevealClipper(_split),
                          child: _framedImage(widget.originalFile),
                        ),
                        Positioned(
                          left: constraints.maxWidth * _split - 1,
                          top: 0,
                          bottom: 0,
                          child: Container(width: 2, color: Colors.white),
                        ),
                        Positioned(
                          left: constraints.maxWidth * _split - 18,
                          top: constraints.maxHeight / 2 - 18,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.drag_handle,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ],
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

  Widget _framedImage(File file) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Image.file(
        file,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      ),
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

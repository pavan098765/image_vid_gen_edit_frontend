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
  double _t = 1;

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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onHorizontalDragUpdate: (d) {
              setState(() {
                _t = (_t + d.delta.dx / constraints.maxWidth).clamp(0.0, 1.0);
              });
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  widget.originalFile,
                  fit: BoxFit.cover,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                ),
                ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: _t,
                    child: Image.file(
                      widget.resultFile,
                      fit: BoxFit.cover,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                    ),
                  ),
                ),
                Positioned(
                  left: (constraints.maxWidth * _t) - 1,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2, color: cs.primary),
                ),
                Positioned(
                  left: (constraints.maxWidth * _t) - 18,
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
                const Positioned(
                  left: 16,
                  bottom: 24,
                  child: Text(
                    'Original',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const Positioned(
                  right: 16,
                  bottom: 24,
                  child: Text(
                    'Result',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
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

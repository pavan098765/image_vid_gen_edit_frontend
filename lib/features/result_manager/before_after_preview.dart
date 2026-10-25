import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  bool _showOriginal = false;
  int? _heldPointer;
  final TransformationController _zoom = TransformationController();
  Offset? _doubleTapPoint;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _zoom.value = Matrix4.identity();
  }

  void _press(PointerDownEvent event) {
    _heldPointer = event.pointer;
    if (_showOriginal) return;
    _resetZoom();
    setState(() => _showOriginal = true);
  }

  void _release(PointerEvent event) {
    if (event.pointer != _heldPointer) return;
    _heldPointer = null;
    if (!_showOriginal) return;
    _resetZoom();
    setState(() => _showOriginal = false);
  }

  void _toggleZoom() {
    final point = _doubleTapPoint;
    if (_zoom.value.getMaxScaleOnAxis() > 1.05 || point == null) {
      _resetZoom();
      return;
    }
    const zoom = 2.5;
    _zoom.value = Matrix4.identity()
      ..translate(-point.dx * (zoom - 1), -point.dy * (zoom - 1))
      ..scale(zoom);
  }

  @override
  Widget build(BuildContext context) {
    final file = _showOriginal ? widget.originalFile : widget.resultFile;
    final label = _showOriginal ? 'Original photo' : 'Edited result';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_showOriginal ? 'Original' : 'Result'),
        actions: [
          Tooltip(
            message: 'Hold to see original',
            child: Semantics(
              button: true,
              label: 'Hold to see the original photo',
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _press,
                onPointerUp: _release,
                onPointerCancel: _release,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(LucideIcons.eye, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = _finiteExtent(constraints.maxWidth);
              final height = _finiteExtent(constraints.maxHeight);
              if (width == null || height == null) {
                return const SizedBox.shrink();
              }
              return Semantics(
                image: true,
                label: label,
                child: GestureDetector(
                  onDoubleTapDown: (details) =>
                      _doubleTapPoint = details.localPosition,
                  onDoubleTap: _toggleZoom,
                  child: InteractiveViewer(
                    transformationController: _zoom,
                    minScale: 1,
                    maxScale: 5,
                    child: Image.file(
                      file,
                      key: ValueKey<String>(file.path + label),
                      fit: BoxFit.contain,
                      width: width,
                      height: height,
                      cacheWidth: _previewCacheEdge(
                        width,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      errorBuilder: (context, error, stackTrace) {
                        return SizedBox(
                          width: width,
                          height: height,
                          child: const Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              color: Colors.white38,
                              size: 48,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

double? _finiteExtent(double value) {
  if (value <= 0 || !value.isFinite) return null;
  return value;
}

/// One decode edge. Null until the viewport has a real width.
int? _previewCacheEdge(double logicalWidth, double devicePixelRatio) {
  if (logicalWidth <= 0 || !logicalWidth.isFinite) return null;
  if (devicePixelRatio <= 0 || !devicePixelRatio.isFinite) return null;
  final edge = (logicalWidth * devicePixelRatio).round();
  if (edge <= 0) return null;
  return edge > 4096 ? 4096 : edge;
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

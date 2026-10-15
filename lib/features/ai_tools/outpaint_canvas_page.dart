import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// OutpaintCanvasPage allows users to position their image within a canvas
/// for outpainting/expanding. Supports both fixed aspect ratios and custom mode.
class OutpaintCanvasPage extends StatefulWidget {
  final Uint8List imageBytes;
  const OutpaintCanvasPage({super.key, required this.imageBytes});

  @override
  State<OutpaintCanvasPage> createState() => _OutpaintCanvasPageState();
}

class _OutpaintCanvasPageState extends State<OutpaintCanvasPage> {
  String _aspect = "9:16";
  final _ratios = ['1:1', '3:4', '4:3', '9:16', '16:9', '2:3', '3:2', 'Custom'];

  // Transform state
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  
  // Gesture tracking
  Offset _baseOffset = Offset.zero;
  double _baseScale = 1.0;
  Offset _startFocalLocal = Offset.zero;

  // Decoded image natural size
  Size? _naturalSize;
  
  // Canvas layout info (updated by LayoutBuilder)
  Size _canvasSize = Size.zero;
  Size _fittedImageSize = Size.zero;
  double _emptyX = 0;
  double _emptyY = 0;

  bool get _isCustom => _aspect == 'Custom';

  @override
  void initState() {
    super.initState();
    _decodeImage();
  }

  Future<void> _decodeImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      setState(() {
        _naturalSize = Size(img.width.toDouble(), img.height.toDouble());
      });
      img.dispose();
    } catch (e) {
      debugPrint("Image decode failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : cs.surface,
      appBar: AppBar(
        title: const Text("Adjust Expansion"),
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.x, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Reset button (only show if position changed)
          if (_offset != Offset.zero || _scale != 1.0)
            TextButton(
              onPressed: _resetTransform,
              child: Text(
                "Reset",
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ),
          TextButton.icon(
            onPressed: _onDone,
            icon: Icon(LucideIcons.check, size: 18, color: cs.primary),
            label: Text(
              "Done",
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Instructions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isCustom
                            ? "Pinch to resize • Drag to position"
                            : "Drag image to set expansion direction",
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Canvas area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _isCustom ? 1.0 : _parseRatio(_aspect),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: cs.outline.withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRect(
                        child: LayoutBuilder(builder: (context, constraints) {
                          return _buildInteractiveCanvas(constraints.biggest);
                        }),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Aspect ratio selector
            _buildAspectRatioSelector(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractiveCanvas(Size boxSize) {
    _canvasSize = boxSize;
    
    // Calculate image aspect ratio from decoded image
    final double imageAspect = _naturalSize != null
        ? (_naturalSize!.width / _naturalSize!.height)
        : 3.0 / 4.0;

    // Calculate fitted image size (BoxFit.contain) - use exact pixel values
    _fittedImageSize = _fitContainExact(boxSize, imageAspect);

    // Calculate empty space on each axis - ensure non-negative
    _emptyX = math.max(0.0, (boxSize.width - _fittedImageSize.width) / 2.0);
    _emptyY = math.max(0.0, (boxSize.height - _fittedImageSize.height) / 2.0);


    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (details) {
        _baseOffset = _offset;
        _baseScale = _scale;
        final renderBox = context.findRenderObject() as RenderBox?;
        _startFocalLocal = renderBox?.globalToLocal(details.focalPoint) ?? Offset.zero;
      },
      onScaleUpdate: (details) {
        final renderBox = context.findRenderObject() as RenderBox?;
        final localFocal = renderBox?.globalToLocal(details.focalPoint) ?? Offset.zero;
        final Offset focalDelta = localFocal - _startFocalLocal;

        double newScale = _scale;
        Offset tentative = _baseOffset + focalDelta;

        if (_isCustom) {
          // Custom mode: allow scaling
          newScale = (_baseScale * details.scale).clamp(0.3, 3.0);
          
          // Recalculate bounds for new scale
          final newDisplayedW = _fittedImageSize.width * newScale;
          final newDisplayedH = _fittedImageSize.height * newScale;
          
          if (newScale >= 1.0) {
            // Zoomed in: can pan but must keep image covering canvas edges
            final newMaxX = math.max(0.0, (newDisplayedW - boxSize.width) / 2.0);
            final newMaxY = math.max(0.0, (newDisplayedH - boxSize.height) / 2.0);
            tentative = Offset(
              tentative.dx.clamp(-newMaxX, newMaxX),
              tentative.dy.clamp(-newMaxY, newMaxY),
            );
          } else {
            // Zoomed out: image smaller than canvas, can position within
            final halfExcessX = (boxSize.width - newDisplayedW) / 2.0;
            final halfExcessY = (boxSize.height - newDisplayedH) / 2.0;
            tentative = Offset(
              tentative.dx.clamp(-halfExcessX, halfExcessX),
              tentative.dy.clamp(-halfExcessY, halfExcessY),
            );
          }
        } else {
          // Fixed aspect mode: only pan along axis with empty space
          newScale = 1.0;
          
          if (_emptyX > 0 && _emptyY == 0) {
            // Can only move horizontally
            tentative = Offset(
              tentative.dx.clamp(-_emptyX, _emptyX),
              0,
            );
          } else if (_emptyY > 0 && _emptyX == 0) {
            // Can only move vertically
            tentative = Offset(
              0,
              tentative.dy.clamp(-_emptyY, _emptyY),
            );
          } else if (_emptyX > 0 && _emptyY > 0) {
            // Both axes have space - allow movement in both
            tentative = Offset(
              tentative.dx.clamp(-_emptyX, _emptyX),
              tentative.dy.clamp(-_emptyY, _emptyY),
            );
          } else {
            // Image perfectly fills canvas
            tentative = Offset.zero;
          }
        }

        setState(() {
          _scale = newScale;
          _offset = tentative;
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Checkered background
          const CustomPaint(painter: _CheckerPainter()),
          
          // Image with transform
          Center(
            child: Transform.translate(
              offset: _offset,
              child: Transform.scale(
                scale: _scale,
                alignment: Alignment.center,
                child: SizedBox(
                  width: _fittedImageSize.width,
                  height: _fittedImageSize.height,
                  child: ClipRect(
                    child: Image.memory(
                      widget.imageBytes,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          // Edge indicators for fixed aspect modes
          if (!_isCustom) _buildEdgeIndicators(),
        ],
      ),
    );
  }

  Widget _buildEdgeIndicators() {
    final bool canMoveHorizontal = _emptyX > 0;
    final bool canMoveVertical = _emptyY > 0;
    
    if (!canMoveHorizontal && !canMoveVertical) return const SizedBox();
    
    // Calculate which edges are "touching" based on offset
    final double dxRatio = _emptyX > 0 ? (_offset.dx / _emptyX) : 0;
    final double dyRatio = _emptyY > 0 ? (_offset.dy / _emptyY) : 0;
    
    const double edgeThreshold = 0.7;
    
    return Stack(
      fit: StackFit.expand,
      children: [
        // Left edge indicator
        if (canMoveHorizontal && dxRatio <= -edgeThreshold)
          Positioned(
            left: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        // Right edge indicator
        if (canMoveHorizontal && dxRatio >= edgeThreshold)
          Positioned(
            right: 4,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        // Top edge indicator
        if (canMoveVertical && dyRatio <= -edgeThreshold)
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        // Bottom edge indicator
        if (canMoveVertical && dyRatio >= edgeThreshold)
          Positioned(
            bottom: 4,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAspectRatioSelector(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(LucideIcons.maximize2, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  "Output Aspect Ratio",
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: _ratios.map((r) {
                final selected = _aspect == r;
                final isCustom = r == 'Custom';
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _aspect = r;
                        _offset = Offset.zero;
                        _scale = isCustom ? 0.7 : 1.0; // Start custom with smaller image
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(
                        horizontal: isCustom ? 16 : 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? cs.primary
                              : cs.outline.withOpacity(0.2),
                          width: 1.5,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: cs.primary.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isCustom) ...[
                            Icon(
                              LucideIcons.move,
                              size: 14,
                              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            r,
                            style: TextStyle(
                              color: selected ? cs.onPrimary : cs.onSurface,
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _resetTransform() {
    setState(() {
      _offset = Offset.zero;
      _scale = _isCustom ? 0.7 : 1.0;
    });
  }

  // Precise fitting that ensures image fills one dimension exactly
  Size _fitContainExact(Size box, double imageAspect) {
    final boxAspect = box.width / box.height;
    if (imageAspect > boxAspect) {
      // Image is wider than box - fit to width
      return Size(box.width, box.width / imageAspect);
    } else {
      // Image is taller than box - fit to height
      return Size(box.height * imageAspect, box.height);
    }
  }

  void _onDone() {
    if (_isCustom) {
      _onDoneCustom();
    } else {
      _onDoneFixedAspect();
    }
  }

  void _onDoneFixedAspect() {
    const double edgeThreshold = 0.70;
    const double slightThreshold = 0.20;

    final double dx = _offset.dx;
    final double dy = _offset.dy;

    final double dxRatio = _emptyX == 0 ? 0 : (dx.abs() / _emptyX);
    final double dyRatio = _emptyY == 0 ? 0 : (dy.abs() / _emptyY);

    String align = "Middle";

    // Priority 1: Hard edge push
    if (_emptyX > 0 && dxRatio >= edgeThreshold) {
      align = dx < 0 ? "Left" : "Right";
    } else if (_emptyY > 0 && dyRatio >= edgeThreshold) {
      align = dy < 0 ? "Top" : "Bottom";
    }
    // Priority 2: Slight movement - expand all sides
    else if (dxRatio >= slightThreshold || dyRatio >= slightThreshold) {
      align = "All Sides";
    }
    // Priority 3: No movement
    else {
      align = "Middle";
    }

    // Calculate normalized position for preview
    // Range: -1.0 to 1.0 (where -1 = fully left/top, 1 = fully right/bottom)
    final double normX = _emptyX > 0 ? (dx / _emptyX).clamp(-1.0, 1.0) : 0.0;
    final double normY = _emptyY > 0 ? (dy / _emptyY).clamp(-1.0, 1.0) : 0.0;

    Navigator.pop(context, {
      "alignment": align,
      "aspect_ratio": _aspect,
      "is_custom": "false",
      // Normalized position for accurate preview
      "norm_offset_x": normX.toStringAsFixed(3),
      "norm_offset_y": normY.toStringAsFixed(3),
      // Original offset in pixels (relative to fitted size)
      "offset_x": dx.toStringAsFixed(1),
      "offset_y": dy.toStringAsFixed(1),
      // Canvas info
      "canvas_width": _canvasSize.width.toStringAsFixed(1),
      "canvas_height": _canvasSize.height.toStringAsFixed(1),
      "fitted_width": _fittedImageSize.width.toStringAsFixed(1),
      "fitted_height": _fittedImageSize.height.toStringAsFixed(1),
    });
  }

  void _onDoneCustom() {
    // For custom mode, we need to calculate the exact positioning
    // to send to the backend
    
    // The scale and offset determine where the image sits in the canvas
    final double imageW = _fittedImageSize.width * _scale;
    final double imageH = _fittedImageSize.height * _scale;
    
    // Position of image center relative to canvas center
    final double centerX = _canvasSize.width / 2 + _offset.dx;
    final double centerY = _canvasSize.height / 2 + _offset.dy;
    
    // Top-left position of image
    final double imageLeft = centerX - imageW / 2;
    final double imageTop = centerY - imageH / 2;
    
    // Calculate normalized values (0-1 range for backend)
    final double normScale = _scale;
    final double normOffsetX = _offset.dx / (_canvasSize.width / 2);
    final double normOffsetY = _offset.dy / (_canvasSize.height / 2);
    
    // Determine alignment hint based on position
    String alignHint = "Middle";
    if (_offset.dx < -_canvasSize.width * 0.1) {
      alignHint = "Left";
    } else if (_offset.dx > _canvasSize.width * 0.1) {
      alignHint = "Right";
    } else if (_offset.dy < -_canvasSize.height * 0.1) {
      alignHint = "Top";
    } else if (_offset.dy > _canvasSize.height * 0.1) {
      alignHint = "Bottom";
    }

    Navigator.pop(context, {
      "alignment": alignHint,
      "aspect_ratio": "1:1", // Custom always uses 1:1 canvas
      "is_custom": "true",
      "custom_scale": normScale.toStringAsFixed(3),
      "norm_offset_x": normOffsetX.toStringAsFixed(3),
      "norm_offset_y": normOffsetY.toStringAsFixed(3),
      "offset_x": _offset.dx.toStringAsFixed(1),
      "offset_y": _offset.dy.toStringAsFixed(1),
      "canvas_width": _canvasSize.width.toStringAsFixed(1),
      "canvas_height": _canvasSize.height.toStringAsFixed(1),
      "image_width": imageW.toStringAsFixed(1),
      "image_height": imageH.toStringAsFixed(1),
      "image_left": imageLeft.toStringAsFixed(1),
      "image_top": imageTop.toStringAsFixed(1),
    });
  }

  double _parseRatio(String s) {
    if (s == "Custom") return 1.0;
    final parts = s.split(':');
    if (parts.length != 2) return 1.0;
    final w = double.tryParse(parts[0]) ?? 1;
    final h = double.tryParse(parts[1]) ?? 1;
    return w / h;
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 24;
    final paint1 = Paint()..color = const Color(0xFF2A2A2A);
    final paint2 = Paint()..color = const Color(0xFF1E1E1E);
    
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final usePaint = ((x / cell).floor() + (y / cell).floor()) % 2 == 0
            ? paint1
            : paint2;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), usePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

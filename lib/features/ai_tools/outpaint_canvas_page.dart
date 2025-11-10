import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';

class OutpaintCanvasPage extends StatefulWidget {
  final Uint8List imageBytes;
  const OutpaintCanvasPage({super.key, required this.imageBytes});

  @override
  State<OutpaintCanvasPage> createState() => _OutpaintCanvasPageState();
}

class _OutpaintCanvasPageState extends State<OutpaintCanvasPage> {
  String _aspect = "1:1";
  final _ratios = ['1:1', '3:4', '4:3', '9:16', '16:9', '2:3', "3:2"];

  // transform state
  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _maxHorizontal = 0;
  double _maxVertical = 0;

  // gesture base states
  Offset _baseOffset = Offset.zero;
  double _baseScale = 1.0;
  Offset _startFocalLocal = Offset.zero;

  // decoded image natural size
  Size? _naturalSize;

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
      // leave _naturalSize null; fallback to square aspect later
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Adjust Expansion"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _onDone,
            child:
                const Text("Done", style: TextStyle(color: Colors.lightBlue)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _parseRatio(_aspect),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final Size box = constraints.biggest;

                      // 1) determine image aspect from decoded image, fallback to 3/4
                      final double imageAspect = _naturalSize != null
                          ? (_naturalSize!.width / _naturalSize!.height)
                          : 3.0 / 4.0;

                      // 2) calculate the fitted size (BoxFit.contain)
                      final Size fitted = _fitContain(box, imageAspect);

                      // 3) compute empty space (half on each side)
                      final double emptyX = ((box.width - fitted.width) / 2.0)
                          .clamp(0.0, double.infinity);
                      final double emptyY = ((box.height - fitted.height) / 2.0)
                          .clamp(0.0, double.infinity);

                      _maxHorizontal = emptyX;
                      _maxVertical = emptyY;

                      // 4) when zoomed (Custom), the displayed image size becomes fitted * scale
                      final double displayedW = fitted.width * _scale;
                      final double displayedH = fitted.height * _scale;
                      final double maxTranslateX =
                          math.max(0.0, (displayedW - box.width) / 2.0);
                      final double maxTranslateY =
                          math.max(0.0, (displayedH - box.height) / 2.0);

                      // Gesture handling uses onScale callbacks to support both pan & pinch
                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onScaleStart: (details) {
                          _baseOffset = _offset;
                          _baseScale = _scale;
                          // convert start focal to local coordinates (so deltas are local)
                          final renderBox =
                              context.findRenderObject() as RenderBox?;
                          _startFocalLocal =
                              renderBox?.globalToLocal(details.focalPoint) ??
                                  Offset.zero;
                        },
                        onScaleUpdate: (details) {
                          final renderBox =
                              context.findRenderObject() as RenderBox?;
                          final localFocal =
                              renderBox?.globalToLocal(details.focalPoint) ??
                                  Offset.zero;
                          final Offset focalDelta =
                              localFocal - _startFocalLocal;

                          // calculate new scale (only when in Custom mode)
                          double newScale =
                              _isCustom ? (_baseScale * details.scale) : 1.0;
                          // clamp scale for Custom
                          if (_isCustom) newScale = newScale.clamp(0.5, 4.0);

                          // calculate tentative newOffset = baseOffset + focalDelta
                          Offset tentative = _baseOffset + focalDelta;

                          if (!_isCustom) {
                            // fixed aspect: allow only along axis that has empty canvas
                            if (emptyX > 0 && emptyY == 0) {
                              // horizontal move only — center vertically
                              tentative = Offset(tentative.dx, 0);
                              // clamp to visible edge: allowed range is [-emptyX, emptyX]
                              tentative = Offset(
                                tentative.dx.clamp(-emptyX, emptyX).toDouble(),
                                0,
                              );
                            } else if (emptyY > 0 && emptyX == 0) {
                              // vertical move only
                              tentative = Offset(0, tentative.dy);
                              tentative = Offset(
                                0,
                                tentative.dy.clamp(-emptyY, emptyY).toDouble(),
                              );
                            } else {
                              // if both empty (rare) or none -> no movement or center
                              tentative = Offset.zero;
                            }
                          } else {
                            // Custom: free pan but clamp by maxTranslate computed from displayed size
                            tentative = Offset(
                              tentative.dx
                                  .clamp(-maxTranslateX, maxTranslateX)
                                  .toDouble(),
                              tentative.dy
                                  .clamp(-maxTranslateY, maxTranslateY)
                                  .toDouble(),
                            );
                          }

                          setState(() {
                            _scale = newScale;
                            _offset = tentative;
                          });
                        },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            const CustomPaint(painter: _CheckerPainter()),
                            // center the fitted image; use sized box equal to fitted size then scale/translate
                            Center(
                              child: Transform.translate(
                                offset: _offset,
                                child: Transform.scale(
                                  scale: _scale,
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    width: fitted.width,
                                    height: fitted.height,
                                    child: Image.memory(
                                      widget.imageBytes,
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.black,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _ratios.map((r) {
                    final selected = _aspect == r;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(
                          r,
                          style: TextStyle(
                              color: selected ? Colors.black : Colors.white70),
                        ),
                        selected: selected,
                        onSelected: (_) {
                          setState(() {
                            _aspect = r;
                            // reset transforms when switching
                            _offset = Offset.zero;
                            _scale = 1.0;
                          });
                        },
                        selectedColor: Colors.white,
                        backgroundColor: Colors.grey[800],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Fit contain calculation (returns size the image will occupy inside box)
  Size _fitContain(Size box, double imageAspect) {
    final boxAspect = box.width / box.height;
    if (imageAspect > boxAspect) {
      final width = box.width;
      final height = width / imageAspect;
      return Size(width, height);
    } else {
      final height = box.height;
      final width = height * imageAspect;
      return Size(width, height);
    }
  }

  void _onDone() {
    // absolute offset in px for gesture detection
    const int pixelEdgeThreshold = 30;

    // relative offset (percentage of max) for precision detection
    const double edgeThreshold = 0.70; // 70% of max movement = “touching edge”
    const double slightThreshold = 0.20; // 20% of max movement = “slight move”

    final double dx = _offset.dx;
    final double dy = _offset.dy;

    // Compute normalized movement (0.0 → 1.0)
    final double dxRatio =
        _maxHorizontal == 0 ? 0 : (dx.abs() / _maxHorizontal);
    final double dyRatio = _maxVertical == 0 ? 0 : (dy.abs() / _maxVertical);

    String align = "Middle"; // default

    // ---------------------------------------------------------
    // PRIORITY 1 — HARD EDGE PUSH (ratio ≥ edgeThreshold)
    // ---------------------------------------------------------
    if (_maxHorizontal > 0 && dxRatio >= edgeThreshold) {
      align = dx < 0 ? "Left" : "Right";
    } else if (_maxVertical > 0 && dyRatio >= edgeThreshold) {
      align = dy < 0 ? "Top" : "Bottom";
    }

    // ---------------------------------------------------------
    // PRIORITY 2 — SLIGHT MOVEMENT (ratio ≥ slightThreshold)
    // Produce BOTH SIDE expansion.
    // ---------------------------------------------------------
    else if (dxRatio >= slightThreshold || dyRatio >= slightThreshold) {
      align = "All Sides";
    }

    // ---------------------------------------------------------
    // PRIORITY 3 — NO MOVEMENT
    // ---------------------------------------------------------
    else {
      align = "Middle";
    }

    Navigator.pop(context, {
      "alignment": align,
      "aspect_ratio": _aspect,
    });
  }

  // void _onDone() {
  //   // threshold for "touching" edge movement
  //   const double edgeThreshold = 30;
  //   const slightThreshold = 0.20;

  //   // detect horizontal movement
  //   double dxAbs =
  //       _maxHorizontal == 0 ? 0 : (_offset.dx.abs() / _maxHorizontal);
  //   double dyAbs = _maxVertical == 0 ? 0 : (_offset.dy.abs() / _maxVertical);

  //   String align;

  //   final double dx = _offset.dx;
  //   final double dy = _offset.dy;

  //   final bool pushLeft = dx < -edgeThreshold;
  //   final bool pushRight = dx > edgeThreshold;
  //   final bool pushUp = dy < -edgeThreshold;
  //   final bool pushDown = dy > edgeThreshold;

  //   // CASE 1: user pushed to EXACTLY one edge → one-sided expansion
  //   if (pushLeft && !pushRight && !pushUp && !pushDown) {
  //     align = "Left"; // expand right
  //   } else if (pushRight && !pushLeft && !pushUp && !pushDown) {
  //     align = "Right"; // expand left
  //   } else if (pushUp && !pushDown && !pushLeft && !pushRight) {
  //     align = "Top"; // expand down
  //   } else if (pushDown && !pushUp && !pushLeft && !pushRight) {
  //     align = "Bottom"; // expand up
  //   }

  //   // CASE 2: user moved BUT is NOT touching edge → expand on BOTH sides
  //   else if ((dx.abs() > 0 && dx.abs() < edgeThreshold) ||
  //       (dy.abs() > 0 && dy.abs() < edgeThreshold)) {
  //     align = "All Sides";
  //   }

  //   // CASE 3: no movement → middle
  //   else {
  //     align = "Middle";
  //   }

  //   Navigator.pop(context, {
  //     "alignment": align,
  //     "aspect_ratio": _aspect,
  //   });
  // }

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
    const double cell = 32;
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

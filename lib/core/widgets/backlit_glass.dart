import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Atmospheric light behind the app.
/// Both blooms are stops on the logo gradient: gold into magenta, cyan into violet.
/// Dark mode keeps those neons on a near-black field. Light mode uses the same hues, lifted and softer, so type stays readable.
class BacklitWash extends StatelessWidget {
  final Alignment glowAlignment;
  final Color? glow;
  final Color? warm;

  /// Keeps the dark wash when the surrounding theme is light.
  /// The audio player uses this so its white type stays readable.
  final bool forceDark;

  const BacklitWash({
    super.key,
    this.glowAlignment = const Alignment(-0.55, -0.72),
    this.glow,
    this.warm,
    this.forceDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark =
        forceDark || Theme.of(context).brightness == Brightness.dark;
    // Logo crystal: gold → magenta on one side, cyan → violet on the other.
    const gold = Color(0xFFFFB020);
    const magenta = Color(0xFFFF4D9A);
    const violet = Color(0xFF7B5EFF);
    const cyan = Color(0xFF00C8FF);
    const blue = Color(0xFF3D7CFF);

    // Upper light follows the gold crystal. The other follows the cyan crystal.
    // A passed color still owns its light, then fades toward the shared violet.
    final upperBloom = glow == null
        ? (isDark
            ? const [gold, magenta, violet]
            : const [Color(0xFFFFC27A), Color(0xFFFF8EC8), Color(0xFFC9B0FF)])
        : [glow!, Color.lerp(glow!, magenta, 0.35)!];
    final sideBloom = warm == null
        ? (isDark
            ? const [cyan, blue, violet]
            : const [Color(0xFF7AD4FF), Color(0xFF8AA6FF), Color(0xFFD4C6FF)])
        : [warm!, Color.lerp(warm!, violet, 0.4)!];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [
                  Color(0xFF140818),
                  Color(0xFF0A0814),
                  Color(0xFF07101C),
                ]
              : const [
                  Color(0xFFFFF7F2),
                  Color(0xFFF8F4FF),
                  Color(0xFFF3F7FF),
                ],
          stops: const [0.0, 0.48, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DriftingLights(
            isDark: isDark,
            upper: upperBloom,
            side: sideBloom,
            glowAlignment: glowAlignment,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.15,
                colors: [
                  Colors.transparent,
                  (isDark ? Colors.black : const Color(0xFF3A2A66))
                      .withValues(alpha: isDark ? 0.5 : 0.07),
                ],
                stops: const [0.42, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slow drift of the logo lights.
/// The wash repaints on its own so the rest of the screen stays still.
class _DriftingLights extends StatefulWidget {
  final bool isDark;
  final List<Color> upper;
  final List<Color> side;
  final Alignment glowAlignment;

  const _DriftingLights({
    required this.isDark,
    required this.upper,
    required this.side,
    required this.glowAlignment,
  });

  @override
  State<_DriftingLights> createState() => _DriftingLightsState();
}

class _DriftingLightsState extends State<_DriftingLights>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final t = _clock.value;
          final breathe = 0.94 + 0.06 * math.sin(t * math.pi * 2);
          double wobbleX(double phase) =>
              0.028 * math.sin((t + phase) * math.pi * 2);
          double wobbleY(double phase) =>
              0.02 * math.cos((t + phase) * math.pi * 2);

          return LayoutBuilder(
            builder: (context, constraints) {
              final width =
                  constraints.maxWidth <= 0 ? 390.0 : constraints.maxWidth;
              final height = constraints.maxHeight.isFinite &&
                      constraints.maxHeight > 0
                  ? constraints.maxHeight
                  : width * 2;

              Widget light(
                double cx,
                double cy,
                double scale,
                List<Color> colors,
                double strength,
              ) {
                final diameter = width * scale;
                return Positioned(
                  left: width * cx - diameter / 2,
                  top: height * cy - diameter / 2,
                  width: diameter,
                  height: diameter,
                  child: _Glow(
                    colors: colors,
                    strength: strength * breathe,
                  ),
                );
              }

              final bridge = [
                Color.lerp(widget.upper.first, widget.side.first, 0.5)!,
                const Color(0xFF7B5EFF),
              ];
              // Gold sits in the upper middle. Cyan overlaps it from the right.
              // The violet pool stays low, behind the glass bar.
              final upperCx = 0.36 + widget.glowAlignment.x * 0.04;
              final upperCy = 0.30 + widget.glowAlignment.y * 0.03;
              if (widget.isDark) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    light(
                      upperCx + wobbleX(0),
                      upperCy + wobbleY(0.1),
                      1.9,
                      widget.upper,
                      0.28,
                    ),
                    light(
                      0.86 + wobbleX(0.33),
                      0.18 + wobbleY(0.4),
                      1.65,
                      widget.side,
                      0.22,
                    ),
                    light(
                      0.5 + wobbleX(0.66),
                      0.94 + wobbleY(0.2),
                      2.05,
                      bridge,
                      0.26,
                    ),
                  ],
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  light(
                    upperCx + wobbleX(0),
                    upperCy + wobbleY(0.1),
                    1.75,
                    widget.upper,
                    0.16,
                  ),
                  light(
                    0.84 + wobbleX(0.33),
                    0.16 + wobbleY(0.4),
                    1.5,
                    widget.side,
                    0.12,
                  ),
                  light(
                    0.5 + wobbleX(0.66),
                    0.94 + wobbleY(0.2),
                    1.85,
                    bridge,
                    0.12,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final List<Color> colors;
  final double strength;

  const _Glow({
    required this.colors,
    required this.strength,
  });

  @override
  Widget build(BuildContext context) {
    final core = colors.first;
    final mid = colors.length > 1 ? colors[1] : core;
    final edge = colors.length > 2 ? colors[2] : mid;
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              core.withValues(alpha: strength),
              mid.withValues(alpha: strength * 0.55),
              edge.withValues(alpha: strength * 0.22),
              edge.withValues(alpha: strength * 0.06),
              edge.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.28, 0.55, 0.78, 1.0],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Shared card fill for tiles that should sit in the wash without a blur cost.
BoxDecoration kalaGlassDecoration({
  required bool isDark,
  double radius = 16,
}) {
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [
              const Color(0xFF3A2A48).withValues(alpha: 0.78),
              const Color(0xFF161018).withValues(alpha: 0.62),
            ]
          : [
              Colors.white.withValues(alpha: 0.9),
              const Color(0xFFF6F0FF).withValues(alpha: 0.74),
            ],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.22)
          : Colors.white,
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF6A4AD4))
            .withValues(alpha: isDark ? 0.28 : 0.08),
        blurRadius: 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
}

/// One frosted sheet. The modal background stays clear so this panel is the surface.
Widget glassSheet(Widget child, {double radius = 22}) {
  return BacklitGlass(
    role: BacklitGlassRole.pane,
    blur: true,
    borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
    child: child,
  );
}

/// How dense the glass is.
/// [bar] is the shell navigation. [chip] is a field or banner.
/// [pane] keeps the denser fill the audio player relies on.
enum BacklitGlassRole { bar, chip, pane }

/// Frosted panel. Blur stays off for chips and lists; one bar-level blur is enough.
class BacklitGlass extends StatelessWidget {
  final Widget child;
  final BacklitGlassRole role;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final bool blur;
  final Color? tint;

  /// Keeps the dark glass when the app theme is light.
  final bool forceDark;

  const BacklitGlass({
    super.key,
    required this.child,
    this.role = BacklitGlassRole.chip,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.padding = EdgeInsets.zero,
    this.blur = false,
    this.tint,
    this.forceDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark =
        forceDark || Theme.of(context).brightness == Brightness.dark;
    final hairline = role == BacklitGlassRole.bar;
    final bordered = !hairline;
    final sigma = role == BacklitGlassRole.bar ? 24.0 : 18.0;

    final layers = DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        gradient: tint == null ? _fill(isDark) : null,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: _wash(isDark)),
        child: CustomPaint(
          painter: _GlassChromePainter(isDark: isDark, role: role),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );

    final clipped = ClipRRect(
      borderRadius: bordered ? _deflate(borderRadius, 1) : borderRadius,
      child: blur
          ? BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: layers,
            )
          : layers,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: bordered ? _border(isDark) : null,
        boxShadow: _shadows(isDark),
      ),
      child: Padding(
        padding: bordered ? const EdgeInsets.all(1) : EdgeInsets.zero,
        child: clipped,
      ),
    );
  }

  LinearGradient _fill(bool isDark) {
    final (Color top, Color bottom) = switch (role) {
      BacklitGlassRole.bar => isDark
          ? (
              const Color(0xFF32243C).withValues(alpha: 0.44),
              const Color(0xFF120C18).withValues(alpha: 0.68),
            )
          : (
              Colors.white.withValues(alpha: 0.68),
              const Color(0xFFF4ECFF).withValues(alpha: 0.84),
            ),
      BacklitGlassRole.chip => isDark
          ? (
              const Color(0xFF2A1C36).withValues(alpha: 0.62),
              const Color(0xFF161018).withValues(alpha: 0.72),
            )
          : (
              Colors.white.withValues(alpha: 0.78),
              const Color(0xFFF6F0FF).withValues(alpha: 0.7),
            ),
      BacklitGlassRole.pane => isDark
          ? (
              const Color(0xFF2A1C36).withValues(alpha: 0.78),
              const Color(0xFF120C16).withValues(alpha: 0.62),
            )
          : (
              Colors.white.withValues(alpha: 0.82),
              const Color(0xFFF4ECFF).withValues(alpha: 0.66),
            ),
    };
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, bottom],
    );
  }

  LinearGradient _wash(bool isDark) {
    final alpha = switch (role) {
      BacklitGlassRole.bar => isDark ? 0.14 : 0.1,
      BacklitGlassRole.chip => isDark ? 0.08 : 0.06,
      BacklitGlassRole.pane => isDark ? 0.07 : 0.05,
    };
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        const Color(0xFFFF4D9A).withValues(alpha: alpha),
        Colors.transparent,
        const Color(0xFF00C8FF).withValues(alpha: alpha),
      ],
    );
  }

  LinearGradient _border(bool isDark) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withValues(alpha: 0.38),
              const Color(0xFF00C8FF).withValues(alpha: 0.2),
              const Color(0xFFFF4D9A).withValues(alpha: 0.08),
            ]
          : [
              Colors.white,
              const Color(0xFFE7DEFF).withValues(alpha: 0.95),
              Colors.white.withValues(alpha: 0.45),
            ],
    );
  }

  List<BoxShadow> _shadows(bool isDark) {
    return switch (role) {
      BacklitGlassRole.bar => [
          BoxShadow(
            color: const Color(0xFF7B5EFF).withValues(alpha: isDark ? 0.32 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
          BoxShadow(
            color: const Color(0xFFFF4D9A).withValues(alpha: isDark ? 0.14 : 0.08),
            blurRadius: 22,
            offset: const Offset(-10, -2),
          ),
        ],
      BacklitGlassRole.chip => [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF6A4AD4))
                .withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      BacklitGlassRole.pane => [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: const Color(0xFFFF4D9A).withValues(alpha: isDark ? 0.14 : 0.1),
            blurRadius: 28,
            offset: const Offset(-6, 8),
          ),
          BoxShadow(
            color: const Color(0xFF00C8FF).withValues(alpha: isDark ? 0.12 : 0.1),
            blurRadius: 28,
            offset: const Offset(8, 10),
          ),
        ],
    };
  }

  static BorderRadius _deflate(BorderRadius radius, double inset) {
    Radius shrink(Radius r) => Radius.elliptical(
          math.max(0, r.x - inset),
          math.max(0, r.y - inset),
        );
    return BorderRadius.only(
      topLeft: shrink(radius.topLeft),
      topRight: shrink(radius.topRight),
      bottomLeft: shrink(radius.bottomLeft),
      bottomRight: shrink(radius.bottomRight),
    );
  }
}

class _GlassChromePainter extends CustomPainter {
  final bool isDark;
  final BacklitGlassRole role;

  const _GlassChromePainter({required this.isDark, required this.role});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final sheenHeight = switch (role) {
      BacklitGlassRole.bar => 36.0,
      BacklitGlassRole.chip => 22.0,
      BacklitGlassRole.pane => 42.0,
    };
    final sheenAlpha = isDark
        ? (role == BacklitGlassRole.bar ? 0.14 : 0.1)
        : switch (role) {
            BacklitGlassRole.bar => 0.5,
            BacklitGlassRole.chip => 0.6,
            BacklitGlassRole.pane => 0.7,
          };
    final sheen = Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(0, sheenHeight),
        [
          Colors.white.withValues(alpha: sheenAlpha),
          Colors.white.withValues(alpha: 0),
        ],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, sheenHeight), sheen);

    final noiseAlpha = switch (role) {
      BacklitGlassRole.bar => isDark ? 0.55 : 0.4,
      BacklitGlassRole.chip => isDark ? 0.42 : 0.3,
      BacklitGlassRole.pane => isDark ? 0.26 : 0.2,
    };
    _paintNoise(canvas, size, noiseAlpha);

    if (role == BacklitGlassRole.bar && size.width > 48) {
      const inset = 20.0;
      final line = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(inset, 0),
          Offset(size.width - inset, 0),
          [
            Colors.transparent,
            const Color(0xFFFF4D9A).withValues(alpha: isDark ? 0.32 : 0.2),
            Colors.white.withValues(alpha: isDark ? 0.42 : 0.85),
            const Color(0xFF00C8FF).withValues(alpha: isDark ? 0.26 : 0.22),
            Colors.transparent,
          ],
          const [0.0, 0.18, 0.48, 0.72, 1.0],
        );
      canvas.drawRect(
        Rect.fromLTWH(inset, 0, size.width - inset * 2, 1.15),
        line,
      );
    }
  }

  void _paintNoise(Canvas canvas, Size size, double strength) {
    final image = _GlassNoise.tile();
    if (image == null || strength <= 0) return;
    final shader = ui.ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.softLight
        ..color = Colors.white.withValues(alpha: strength),
    );
    shader.dispose();
  }

  @override
  bool shouldRepaint(covariant _GlassChromePainter oldDelegate) {
    return oldDelegate.isDark != isDark || oldDelegate.role != role;
  }
}

class _GlassNoise {
  static ui.Image? _tile;
  static bool _failed = false;

  static ui.Image? tile() {
    if (_failed) return null;
    final cached = _tile;
    if (cached != null) return cached;
    try {
      const size = 96;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint();
      final random = math.Random(41);
      for (var i = 0; i < 1600; i++) {
        final bright = random.nextBool();
        final alpha = 0.15 + random.nextDouble() * 0.55;
        paint.color = bright
            ? Colors.white.withValues(alpha: alpha)
            : Colors.black.withValues(alpha: alpha * 0.45);
        canvas.drawRect(
          Rect.fromLTWH(
            random.nextDouble() * size,
            random.nextDouble() * size,
            1,
            1,
          ),
          paint,
        );
      }
      final picture = recorder.endRecording();
      final image = picture.toImageSync(size, size);
      picture.dispose();
      _tile = image;
      return image;
    } catch (_) {
      _failed = true;
      return null;
    }
  }
}

/// Translucent panel. Blur is optional because a scrolling list of blurs is expensive.
class FrostedPane extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool blur;
  final Color? tint;

  /// Keeps the dark glass when the app theme is light.
  /// The audio player uses this so white type stays on a dark pane.
  final bool forceDark;

  const FrostedPane({
    super.key,
    required this.child,
    this.radius = 22,
    this.padding = const EdgeInsets.all(16),
    this.blur = false,
    this.tint,
    this.forceDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return BacklitGlass(
      role: BacklitGlassRole.pane,
      borderRadius: BorderRadius.circular(radius),
      padding: padding,
      blur: blur,
      tint: tint,
      forceDark: forceDark,
      child: child,
    );
  }
}

/// Lets [BacklitWash] show through a scaffold in either theme.
Color backlitScaffoldColor(BuildContext context, ColorScheme cs) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? const Color(0xFF100C16) : cs.surface).withValues(alpha: 0);
}

import 'dart:async';
import 'dart:ui';

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
                      .withValues(alpha: isDark ? 0.45 : 0.06),
                ],
                stops: const [0.58, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slow drift of the logo lights. A few updates a second is enough,
/// and the wash repaints on its own so the rest of the screen stays still.
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

class _DriftingLightsState extends State<_DriftingLights> {
  Timer? _timer;
  double _shift = 0;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 280), (_) {
      if (!mounted) return;
      setState(() {
        _shift += _forward ? 0.045 : -0.045;
        if (_shift >= 1) {
          _shift = 1;
          _forward = false;
        } else if (_shift <= 0) {
          _shift = 0;
          _forward = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<Color> _drift(List<Color> colors) {
    if (colors.length < 2) return colors;
    final core = Color.lerp(colors[0], colors[1], _shift * 0.55)!;
    final mid = colors.length > 2
        ? Color.lerp(colors[1], colors[2], _shift * 0.45)!
        : colors[1];
    final edge = colors.length > 2 ? colors[2] : mid;
    return [core, mid, edge];
  }

  Alignment _nudge(Alignment base, double dx, double dy) {
    final wave = (_shift - 0.5) * 2;
    return Alignment(
      (base.x + dx * wave).clamp(-1.0, 1.0),
      (base.y + dy * wave).clamp(-1.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final upper = _drift(widget.upper);
    final side = _drift(widget.side);
    final breathe = 0.92 + (_shift * 0.08);
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth <= 0 ? 390.0 : constraints.maxWidth;
          Widget light(
            Alignment alignment,
            double scale,
            List<Color> colors,
            double strength,
          ) {
            return Align(
              alignment: alignment,
              child: _Glow(
                colors: colors,
                diameter: width * scale,
                strength: strength * breathe,
              ),
            );
          }

          final bridge = [
            Color.lerp(upper.first, side.first, 0.5)!,
            const Color(0xFF7B5EFF),
          ];
          if (widget.isDark) {
            return Stack(
              fit: StackFit.expand,
              children: [
                light(_nudge(widget.glowAlignment, 0.05, 0.04), 1.62, upper, 0.46),
                light(_nudge(const Alignment(0.82, -0.18), -0.04, 0.03), 1.28, side, 0.36),
                light(const Alignment(0.05, 0.62), 1.45, bridge, 0.16),
              ],
            );
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              light(_nudge(widget.glowAlignment, 0.04, 0.03), 1.5, upper, 0.2),
              light(_nudge(const Alignment(0.8, -0.12), -0.03, 0.02), 1.2, side, 0.16),
              light(const Alignment(0.05, 0.7), 1.35, bridge, 0.1),
            ],
          );
        },
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final List<Color> colors;
  final double diameter;
  final double strength;

  const _Glow({
    required this.colors,
    required this.diameter,
    required this.strength,
  });

  @override
  Widget build(BuildContext context) {
    final core = colors.first;
    final mid = colors.length > 1 ? colors[1] : core;
    final edge = colors.length > 2 ? colors[2] : mid;
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              core.withValues(alpha: strength),
              mid.withValues(alpha: strength * 0.55),
              edge.withValues(alpha: strength * 0.16),
              edge.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.28, 0.58, 1.0],
          ),
        ),
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
              const Color(0xFF2A1C38).withValues(alpha: 0.9),
              const Color(0xFF161018).withValues(alpha: 0.78),
            ]
          : [
              Colors.white.withValues(alpha: 0.88),
              const Color(0xFFF6F0FF).withValues(alpha: 0.74),
            ],
    ),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.white,
      width: 1,
    ),
    boxShadow: [
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF6A4AD4))
            .withValues(alpha: isDark ? 0.32 : 0.1),
        blurRadius: isDark ? 18 : 16,
        offset: const Offset(0, 8),
      ),
    ],
  );
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
    final isDark =
        forceDark || Theme.of(context).brightness == Brightness.dark;
    final fill = tint;

    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        gradient: fill == null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [
                        const Color(0xFF2A1C36).withValues(alpha: 0.78),
                        const Color(0xFF120C16).withValues(alpha: 0.62),
                      ]
                    : [
                        Colors.white.withValues(alpha: 0.82),
                        const Color(0xFFF4ECFF).withValues(alpha: 0.66),
                      ],
              )
            : null,
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 42,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: isDark ? 0.1 : 0.7),
                      Colors.white.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );

    final glass = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? [
                  Colors.white.withValues(alpha: 0.28),
                  Colors.white.withValues(alpha: 0.05),
                ]
              : [
                  Colors.white,
                  Colors.white.withValues(alpha: 0.35),
                ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: const Color(0xFFFF4D9A)
                .withValues(alpha: isDark ? 0.14 : 0.1),
            blurRadius: 28,
            offset: const Offset(-6, 8),
          ),
          BoxShadow(
            color: const Color(0xFF00C8FF)
                .withValues(alpha: isDark ? 0.12 : 0.1),
            blurRadius: 28,
            offset: const Offset(8, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(1),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: blur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: body,
              )
            : body,
      ),
    );

    return glass;
  }
}

/// Lets [BacklitWash] show through a scaffold in either theme.
Color backlitScaffoldColor(BuildContext context, ColorScheme cs) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? const Color(0xFF100C16) : cs.surface).withValues(alpha: 0);
}

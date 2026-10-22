import 'dart:ui';

import 'package:flutter/material.dart';

/// Atmospheric light behind the app.
/// Dark mode is smoked glass over a deep violet and amber bloom.
/// Light mode is frosted crystal over a lit lilac and peach page.
/// Each theme has its own palette. They are not the same wash at a different brightness.
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
    final cool = glow ??
        (isDark ? const Color(0xFF8B6CFF) : const Color(0xFF7B5EFF));
    final amber = warm ??
        (isDark ? const Color(0xFFE08A45) : const Color(0xFFFF9A62));

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? const [
                  Color(0xFF1A1024),
                  Color(0xFF100C16),
                  Color(0xFF16100E),
                ]
              : const [
                  Color(0xFFF3E9FF),
                  Color(0xFFFBF7FF),
                  Color(0xFFFFF0E4),
                ],
          stops: const [0.0, 0.48, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _field(isDark, cool, amber),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                radius: 1.15,
                colors: [
                  Colors.transparent,
                  (isDark ? Colors.black : const Color(0xFF5C4788))
                      .withValues(alpha: isDark ? 0.42 : 0.07),
                ],
                stops: const [0.58, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(bool isDark, Color cool, Color amber) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth <= 0 ? 390.0 : constraints.maxWidth;
        Widget light(Alignment alignment, double scale, Color color, double strength) {
          return Align(
            alignment: alignment,
            child: _Glow(
              color: color,
              diameter: width * scale,
              strength: strength,
            ),
          );
        }

        if (isDark) {
          return Stack(
            fit: StackFit.expand,
            children: [
              light(glowAlignment, 1.55, cool, 0.42),
              light(const Alignment(0.9, -0.35), 1.05, const Color(0xFF5B3CC4), 0.28),
              light(const Alignment(0.15, 0.72), 1.35, amber, 0.26),
              light(const Alignment(-0.8, 0.25), 0.7, const Color(0xFF3D8BFF), 0.12),
            ],
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            light(glowAlignment, 1.45, cool, 0.22),
            light(const Alignment(0.85, -0.2), 1.05, const Color(0xFFC4B0FF), 0.2),
            light(const Alignment(0.25, 0.85), 1.3, amber, 0.18),
            light(const Alignment(-0.7, 0.35), 0.75, const Color(0xFF8FD8FF), 0.14),
          ],
        );
      },
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double diameter;
  final double strength;

  const _Glow({
    required this.color,
    required this.diameter,
    required this.strength,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: strength),
              color.withValues(alpha: strength * 0.42),
              color.withValues(alpha: strength * 0.12),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.32, 0.62, 1.0],
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
            color: (isDark ? const Color(0xFF7B5EFF) : const Color(0xFF8A6BFF))
                .withValues(alpha: isDark ? 0.16 : 0.12),
            blurRadius: 28,
            offset: const Offset(0, 8),
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

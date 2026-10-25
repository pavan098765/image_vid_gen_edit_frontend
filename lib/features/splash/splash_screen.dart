import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:kala_ai_create_images_videos_with_ai/main.dart'
    show initializeApp;

const Duration _kEntranceDuration = Duration(milliseconds: 1600);
const Duration _kSplashHold = Duration(milliseconds: 2400);

/// Startup screen. Stays up until both the entrance and [initializeApp] finish,
/// then calls [onComplete] once.
class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _logoScale;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _lightReveal;

  bool _animationsComplete = false;
  bool _initializationComplete = false;
  bool _reportedComplete = false;
  bool _reducedMotionApplied = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _entranceController.forward();
    _finishAfterHold();
    _runInitialization();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reducedMotionApplied) return;
    if (!MediaQuery.disableAnimationsOf(context)) return;
    _reducedMotionApplied = true;
    _entranceController.value = 1;
  }

  Future<void> _runInitialization() async {
    try {
      await initializeApp();
      _initializationComplete = true;
      _checkComplete();
    } catch (e) {
      debugPrint("⚠️ Initialization error: $e");
      // Still finish the splash if init fails. The app handles the error later.
      _initializationComplete = true;
      _checkComplete();
    }
  }

  void _checkComplete() {
    if (_reportedComplete || !mounted) return;
    if (!_animationsComplete || !_initializationComplete) return;
    _reportedComplete = true;
    widget.onComplete();
  }

  void _initAnimations() {
    _entranceController = AnimationController(
      duration: _kEntranceDuration,
      vsync: this,
    );

    _logoScale = Tween<double>(begin: 0.97, end: 1).animate(
      CurvedAnimation(
        parent: _entranceController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
      ),
    );

    _titleOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.28, 0.68, curve: Curves.easeOut),
    );

    _taglineOpacity = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.46, 0.9, curve: Curves.easeOut),
    );

    _lightReveal = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    );
  }

  Future<void> _finishAfterHold() async {
    await Future<void>.delayed(_kSplashHold);
    if (!mounted) return;
    _animationsComplete = true;
    _checkComplete();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0814),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const BacklitWash(forceDark: true),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = _cardWidth(constraints.maxWidth);
                final compact = constraints.maxHeight < 560;
                final tight = constraints.maxHeight < 420;
                final horizontalPadding = _horizontalPadding(cardWidth);
                // Pane glass draws a 1px border on every side.
                final rawInner = cardWidth - horizontalPadding * 2 - 2;
                final innerWidth = rawInner > 0 ? rawInner : 0.0;
                final markSize = _markSize(
                  innerWidth,
                  compact: compact || tight,
                  tight: tight,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: _SplashBacklight(
                        width: cardWidth + 150,
                        reveal: _lightReveal,
                        animate: !reduceMotion,
                      ),
                    ),
                    Center(
                      child: _buildCard(
                        width: cardWidth,
                        markSize: markSize,
                        titleSize: tight ? 30 : (compact ? 34 : 38),
                        compact: compact || tight,
                        horizontalPadding: horizontalPadding,
                        loaderWidth: innerWidth < 132 ? innerWidth : 132,
                        animateLoader: !reduceMotion,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required double width,
    required double markSize,
    required double titleSize,
    required bool compact,
    required double horizontalPadding,
    required double loaderWidth,
    required bool animateLoader,
  }) {
    final afterMark = compact ? 16.0 : 26.0;
    final afterTitle = compact ? 10.0 : 14.0;
    final beforeLoader = compact ? 18.0 : 28.0;

    // No Opacity, scroll view, or scale around this panel. Those layers
    // isolate BackdropFilter, so the frost would miss the backlight.
    return SizedBox(
      width: width,
      child: BacklitGlass(
        role: BacklitGlassRole.pane,
        blur: true,
        forceDark: true,
        borderRadius: const BorderRadius.all(Radius.circular(32)),
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          compact ? 28 : 40,
          horizontalPadding,
          compact ? 22 : 28,
        ),
        tint: const Color(0xFF160E1C).withValues(alpha: 0.5),
        child: AnimatedBuilder(
          animation: _entranceController,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: _logoScale.value,
                  child: _SplashMark(size: markSize),
                ),
                SizedBox(height: afterMark),
                Opacity(
                  opacity: _titleOpacity.value,
                  alwaysIncludeSemantics: true,
                  child: Transform.translate(
                    offset: Offset(0, (1 - _titleOpacity.value) * 8),
                    child: _SplashTitle(fontSize: titleSize),
                  ),
                ),
                SizedBox(height: afterTitle),
                Opacity(
                  opacity: _taglineOpacity.value,
                  alwaysIncludeSemantics: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _SplashRule(),
                      SizedBox(height: afterTitle),
                      const _SplashTagline(),
                      SizedBox(height: beforeLoader),
                      _SplashLoader(width: loaderWidth, animate: animateLoader),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

double _cardWidth(double maxWidth) {
  final available = maxWidth - 32;
  if (available < 220) {
    return maxWidth > 0 ? maxWidth : 220;
  }
  return available > 340 ? 340 : available;
}

double _horizontalPadding(double cardWidth) {
  final preferred = cardWidth >= 320 ? 28.0 : 20.0;
  final maxPadding = (cardWidth - 2 - 72) / 2;
  if (maxPadding <= 0) return 0;
  return preferred < maxPadding ? preferred : maxPadding;
}

double _markSize(
  double innerWidth, {
  required bool compact,
  required bool tight,
}) {
  if (innerWidth <= 0) return 0;
  final preferred = tight ? 76.0 : (compact ? 92.0 : 112.0);
  if (preferred <= innerWidth) return preferred;
  return innerWidth;
}

class _SplashBacklight extends StatefulWidget {
  final double width;
  final Animation<double> reveal;
  final bool animate;

  const _SplashBacklight({
    required this.width,
    required this.reveal,
    required this.animate,
  });

  @override
  State<_SplashBacklight> createState() => _SplashBacklightState();
}

class _SplashBacklightState extends State<_SplashBacklight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );
    if (widget.animate) {
      _breathe.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _SplashBacklight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _breathe.repeat(reverse: true);
    } else {
      _breathe.stop();
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.reveal, _breathe]),
        builder: (context, child) {
          final breathe = widget.animate ? _breathe.value : 0.5;
          return Opacity(
            opacity: widget.reveal.value * (0.86 + 0.14 * breathe),
            child: child,
          );
        },
        child: _BacklightField(width: widget.width),
      ),
    );
  }
}

class _BacklightField extends StatelessWidget {
  final double width;

  const _BacklightField({required this.width});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: SizedBox(
          width: width,
          height: width * 1.15,
          child: const Stack(
            clipBehavior: Clip.none,
            children: [
              _PositionedGlow(
                alignment: Alignment(-0.42, -0.48),
                diameterFactor: 0.58,
                color: KalaColors.magenta,
                alpha: 0.58,
              ),
              _PositionedGlow(
                alignment: Alignment(0.02, -0.28),
                diameterFactor: 0.7,
                color: KalaColors.purple,
                alpha: 0.5,
              ),
              _PositionedGlow(
                alignment: Alignment(0.46, -0.12),
                diameterFactor: 0.52,
                color: KalaColors.cyan,
                alpha: 0.46,
              ),
              _PositionedGlow(
                alignment: Alignment(-0.2, -0.36),
                diameterFactor: 0.4,
                color: KalaColors.gold,
                alpha: 0.3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PositionedGlow extends StatelessWidget {
  final Alignment alignment;
  final double diameterFactor;
  final Color color;
  final double alpha;

  const _PositionedGlow({
    required this.alignment,
    required this.diameterFactor,
    required this.color,
    required this.alpha,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: diameterFactor,
        child: AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: alpha),
                  color.withValues(alpha: alpha * 0.4),
                  color.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.42, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashMark extends StatelessWidget {
  final double size;

  const _SplashMark({required this.size});

  @override
  Widget build(BuildContext context) {
    if (size <= 0) return const SizedBox.shrink();
    final radius = BorderRadius.circular(size * 0.22);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: const Color(0xFF24143F),
              boxShadow: [
                BoxShadow(
                  color: KalaColors.purple.withValues(alpha: 0.48),
                  blurRadius: size * 0.18,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: KalaColors.cyan.withValues(alpha: 0.2),
                  blurRadius: size * 0.14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SizedBox(width: size, height: size),
          ),
          ClipRRect(
            borderRadius: radius,
            child: Image.asset(
              'assets/kala_ai_logo.png',
              width: size,
              height: size,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashTitle extends StatelessWidget {
  final double fontSize;

  const _SplashTitle({required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: KalaColors.fullGradient,
            ).createShader(bounds);
          },
          child: Text(
            'Kala AI',
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              height: 1.05,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashRule extends StatelessWidget {
  const _SplashRule();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          gradient: LinearGradient(colors: KalaColors.fullGradient),
        ),
      ),
    );
  }
}

class _SplashTagline extends StatelessWidget {
  const _SplashTagline();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Create with Intelligence',
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.4,
        height: 1.3,
        color: Colors.white.withValues(alpha: 0.74),
      ),
    );
  }
}

class _SplashLoader extends StatefulWidget {
  final double width;
  final bool animate;

  const _SplashLoader({required this.width, required this.animate});

  @override
  State<_SplashLoader> createState() => _SplashLoaderState();
}

class _SplashLoaderState extends State<_SplashLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _travel;

  @override
  void initState() {
    super.initState();
    _travel = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    if (widget.animate) {
      _travel.repeat();
    } else {
      _travel.value = 0.62;
    }
  }

  @override
  void didUpdateWidget(covariant _SplashLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate == oldWidget.animate) return;
    if (widget.animate) {
      _travel.repeat();
    } else {
      _travel
        ..stop()
        ..value = 0.62;
    }
  }

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.width <= 0) return const SizedBox.shrink();
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        width: widget.width,
        height: 3,
        child: AnimatedBuilder(
          animation: _travel,
          builder: (context, _) {
            return CustomPaint(
              painter: _SplashLoaderPainter(progress: _travel.value),
            );
          },
        ),
      ),
    );
  }
}

class _SplashLoaderPainter extends CustomPainter {
  final double progress;

  const _SplashLoaderPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final track = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height),
    );
    canvas.drawRRect(
      track,
      Paint()..color = Colors.white.withValues(alpha: 0.14),
    );

    final capsuleWidth = size.width * 0.46;
    final left = (size.width + capsuleWidth) * progress - capsuleWidth;
    final rect = Rect.fromLTWH(left, 0, capsuleWidth, size.height);
    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x00FF66B2),
            KalaColors.magenta,
            KalaColors.purple,
            KalaColors.cyan,
            Color(0x0000D4FF),
          ],
          stops: [0.0, 0.18, 0.5, 0.82, 1.0],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SplashLoaderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

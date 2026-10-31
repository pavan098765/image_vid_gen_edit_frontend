import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Horizontal shared-axis push for a tool or a Studio step.
/// The fill matches the theme surface so the move does not flash the canvas.
Route<T> sharedAxisRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.disableAnimationsOf(context)) return child;
      return SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transitionType: SharedAxisTransitionType.horizontal,
        fillColor: Theme.of(context).colorScheme.surface,
        child: child,
      );
    },
  );
}

/// Fades the shell's incoming tab in over the wash. Tab state stays mounted.
class ShellFadeThrough extends StatefulWidget {
  final int index;
  final Widget child;

  const ShellFadeThrough({super.key, required this.index, required this.child});

  @override
  State<ShellFadeThrough> createState() => _ShellFadeThroughState();
}

class _ShellFadeThroughState extends State<ShellFadeThrough>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant ShellFadeThrough oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
      return;
    }
    _enter.forward(from: 0);
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeThroughTransition(
      animation: _enter,
      secondaryAnimation: const AlwaysStoppedAnimation<double>(0),
      fillColor: Colors.transparent,
      child: widget.child,
    );
  }
}

/// Fade and a short rise. Plays once per [token], including after scroll-away.
class OnceFadeRise extends StatefulWidget {
  final String token;
  final int order;
  final Widget child;

  const OnceFadeRise({
    super.key,
    required this.token,
    required this.child,
    this.order = 0,
  });

  @override
  State<OnceFadeRise> createState() => _OnceFadeRiseState();
}

class _OnceFadeRiseState extends State<OnceFadeRise> {
  static final Set<String> _played = <String>{};
  late final bool _skip;

  @override
  void initState() {
    super.initState();
    _skip = _played.contains(widget.token);
    _played.add(widget.token);
  }

  @override
  Widget build(BuildContext context) {
    if (_skip || MediaQuery.disableAnimationsOf(context)) return widget.child;
    final delay = Duration(milliseconds: widget.order.clamp(0, 5) * 40);
    return widget.child
        .animate(delay: delay)
        .fadeIn(duration: 280.ms, curve: Curves.easeOutCubic)
        .slideY(
          begin: 0.08,
          end: 0,
          duration: 280.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

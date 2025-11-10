import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GradientButton extends StatelessWidget {
  final String? label;
  final Widget? child;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool disabled;
  final EdgeInsets padding;

  const GradientButton({
    super.key,
    this.label,
    this.child,
    required this.onPressed,
    this.icon,
    this.disabled = false,
    this.padding = const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final gradient = LinearGradient(
      colors: cs.brightness == Brightness.dark
          ? [cs.primary, cs.secondary, Colors.purpleAccent]
          : [cs.primary, cs.secondary, Colors.pinkAccent],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.6),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: disabled ? null : onPressed,
              splashColor: cs.primary.withOpacity(0.15),
              child: Padding(
                padding: padding,
                child: child ??
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label ?? "",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

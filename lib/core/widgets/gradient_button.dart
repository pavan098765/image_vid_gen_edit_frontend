import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';

/// Button style variants for consistent UI across the app
enum ButtonVariant {
  /// Gradient button - for primary/main actions (Generate, Submit, etc.)
  primary,
  
  /// Solid primary color - for important secondary actions
  secondary,
  
  /// Outlined button - for tertiary actions
  outline,
  
  /// Ghost/transparent button - for subtle actions
  ghost,
  
  /// Success style - for positive confirmations
  success,
  
  /// Danger style - for destructive actions
  danger,
}

/// Button size presets
enum ButtonSize {
  small,
  medium,
  large,
}

class GradientButton extends StatelessWidget {
  final String? label;
  final Widget? child;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool disabled;
  final EdgeInsets? padding;
  final ButtonVariant variant;
  final ButtonSize size;
  final double? width;
  final bool expanded;

  const GradientButton({
    super.key,
    this.label,
    this.child,
    required this.onPressed,
    this.icon,
    this.disabled = false,
    this.padding,
    this.variant = ButtonVariant.primary,
    this.size = ButtonSize.medium,
    this.width,
    this.expanded = false,
  });

  EdgeInsets _getPadding() {
    if (padding != null) return padding!;
    switch (size) {
      case ButtonSize.small:
        return const EdgeInsets.symmetric(vertical: 10, horizontal: 16);
      case ButtonSize.medium:
        return const EdgeInsets.symmetric(vertical: 14, horizontal: 20);
      case ButtonSize.large:
        return const EdgeInsets.symmetric(vertical: 18, horizontal: 28);
    }
  }

  double _getFontSize() {
    switch (size) {
      case ButtonSize.small:
        return 13;
      case ButtonSize.medium:
        return 15;
      case ButtonSize.large:
        return 17;
    }
  }

  double _getIconSize() {
    switch (size) {
      case ButtonSize.small:
        return 16;
      case ButtonSize.medium:
        return 20;
      case ButtonSize.large:
        return 22;
    }
  }

  double _getBorderRadius() {
    switch (size) {
      case ButtonSize.small:
        return 12;
      case ButtonSize.medium:
        return 14;
      case ButtonSize.large:
        return 18;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDisabled = disabled || onPressed == null;

    switch (variant) {
      case ButtonVariant.primary:
        return _buildPrimaryButton(context, cs, isDisabled);
      case ButtonVariant.secondary:
        return _buildSecondaryButton(context, cs, isDisabled);
      case ButtonVariant.outline:
        return _buildOutlineButton(context, cs, isDisabled);
      case ButtonVariant.ghost:
        return _buildGhostButton(context, cs, isDisabled);
      case ButtonVariant.success:
        return _buildSuccessButton(context, cs, isDisabled);
      case ButtonVariant.danger:
        return _buildDangerButton(context, cs, isDisabled);
    }
  }

  /// Primary gradient button - main action style (Kala AI brand gradient)
  Widget _buildPrimaryButton(BuildContext context, ColorScheme cs, bool isDisabled) {
    final gradient = LinearGradient(
      colors: isDisabled
          ? [Colors.grey.shade600, Colors.grey.shade500]
          : KalaColors.brandGradient,
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Container(
      width: expanded ? double.infinity : width,
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(_getBorderRadius()),
        boxShadow: isDisabled
            ? null
            : [
                BoxShadow(
                  color: KalaColors.purple.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: KalaColors.cyan.withOpacity(0.2),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
      ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_getBorderRadius()),
          onTap: isDisabled ? null : onPressed,
          splashFactory: NoSplash.splashFactory, // Clean tap without splash
          highlightColor: Colors.transparent,
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          child: Padding(
            padding: _getPadding(),
            child: _buildContent(Colors.white, isDisabled),
          ),
        ),
      ),
    );
  }

  /// Secondary solid button
  Widget _buildSecondaryButton(BuildContext context, ColorScheme cs, bool isDisabled) {
    final bgColor = isDisabled
        ? cs.surfaceContainerHighest
        : cs.primaryContainer;
    final fgColor = isDisabled
        ? cs.onSurfaceVariant.withOpacity(0.5)
        : cs.primary;

    return Container(
      width: expanded ? double.infinity : width,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(_getBorderRadius()),
        border: Border.all(
          color: isDisabled ? Colors.transparent : cs.primary.withOpacity(0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_getBorderRadius()),
          onTap: isDisabled ? null : onPressed,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          child: Padding(
            padding: _getPadding(),
            child: _buildContent(fgColor, isDisabled),
          ),
        ),
      ),
    );
  }

  /// Outline button
  Widget _buildOutlineButton(BuildContext context, ColorScheme cs, bool isDisabled) {
    final borderColor = isDisabled
        ? cs.outlineVariant.withOpacity(0.3)
        : cs.primary.withOpacity(0.5);
    final fgColor = isDisabled
        ? cs.onSurfaceVariant.withOpacity(0.5)
        : cs.primary;

    return Container(
      width: expanded ? double.infinity : width,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_getBorderRadius()),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_getBorderRadius()),
          onTap: isDisabled ? null : onPressed,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          child: Padding(
            padding: _getPadding(),
            child: _buildContent(fgColor, isDisabled),
          ),
        ),
      ),
    );
  }

  /// Ghost/transparent button
  Widget _buildGhostButton(BuildContext context, ColorScheme cs, bool isDisabled) {
    final fgColor = isDisabled
        ? cs.onSurfaceVariant.withOpacity(0.4)
        : cs.onSurfaceVariant;

    return Container(
      width: expanded ? double.infinity : width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_getBorderRadius()),
          onTap: isDisabled ? null : onPressed,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          child: Padding(
            padding: _getPadding(),
            child: _buildContent(fgColor, isDisabled),
          ),
        ),
      ),
    );
  }

  /// Success button
  Widget _buildSuccessButton(BuildContext context, ColorScheme cs, bool isDisabled) {
    const successColor = Color(0xFF10B981); // Emerald green

    return Container(
      width: expanded ? double.infinity : width,
          decoration: BoxDecoration(
        color: isDisabled ? Colors.grey.shade700 : successColor,
        borderRadius: BorderRadius.circular(_getBorderRadius()),
        boxShadow: isDisabled
            ? null
            : [
                BoxShadow(
                  color: successColor.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_getBorderRadius()),
          onTap: isDisabled ? null : onPressed,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          child: Padding(
            padding: _getPadding(),
            child: _buildContent(Colors.white, isDisabled),
          ),
        ),
      ),
    );
  }

  /// Danger button
  Widget _buildDangerButton(BuildContext context, ColorScheme cs, bool isDisabled) {
    final dangerColor = cs.error;

    return Container(
      width: expanded ? double.infinity : width,
      decoration: BoxDecoration(
        color: isDisabled ? Colors.grey.shade700 : dangerColor,
        borderRadius: BorderRadius.circular(_getBorderRadius()),
        boxShadow: isDisabled
            ? null
            : [
                BoxShadow(
                  color: dangerColor.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(_getBorderRadius()),
          onTap: isDisabled ? null : onPressed,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          child: Padding(
            padding: _getPadding(),
            child: _buildContent(Colors.white, isDisabled),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(Color color, bool isDisabled) {
    if (child != null) return child!;

    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (icon != null) ...[
          Icon(
            icon,
            color: color.withOpacity(isDisabled ? 0.5 : 1.0),
            size: _getIconSize(),
          ),
          if (label != null) SizedBox(width: size == ButtonSize.small ? 6 : 8),
                        ],
        if (label != null)
                        Text(
            label!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
              color: color.withOpacity(isDisabled ? 0.5 : 1.0),
              fontSize: _getFontSize(),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
    );
  }
}

// ============================================================================
// App-wide shared styles for consistent UI
// ============================================================================

class AppStyles {
  AppStyles._();

  // ---------------------------------------------------------------------------
  // Border Radius
  // ---------------------------------------------------------------------------
  static const double radiusXs = 8;
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;
  static const double radiusFull = 100;

  // ---------------------------------------------------------------------------
  // Spacing
  // ---------------------------------------------------------------------------
  static const double spacing2 = 2;
  static const double spacing4 = 4;
  static const double spacing6 = 6;
  static const double spacing8 = 8;
  static const double spacing10 = 10;
  static const double spacing12 = 12;
  static const double spacing14 = 14;
  static const double spacing16 = 16;
  static const double spacing20 = 20;
  static const double spacing24 = 24;
  static const double spacing32 = 32;

  // ---------------------------------------------------------------------------
  // Card Decoration
  // ---------------------------------------------------------------------------
  static BoxDecoration cardDecoration(ColorScheme cs, {bool elevated = false}) {
    return BoxDecoration(
      gradient: LinearGradient(
        colors: [
          cs.surfaceContainerHighest.withOpacity(0.12),
          cs.surfaceContainerHigh.withOpacity(0.06),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(radiusLg),
      border: Border.all(
        color: cs.outlineVariant.withOpacity(0.25),
        width: 1,
      ),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: cs.shadow.withOpacity(0.12),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: cs.primary.withOpacity(0.04),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ]
          : [
              BoxShadow(
                color: cs.shadow.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
    );
  }

  // ---------------------------------------------------------------------------
  // Input Field Decoration
  // ---------------------------------------------------------------------------
  static InputDecoration inputDecoration(
    ColorScheme cs, {
    String? hintText,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(
        color: cs.onSurfaceVariant.withOpacity(0.6),
        fontSize: 15,
      ),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: cs.onSurfaceVariant, size: 20)
          : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: cs.surfaceContainerHigh.withOpacity(0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(
          color: cs.outlineVariant.withOpacity(0.2),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(
          color: cs.primary.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(
          color: cs.error.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section Header
  // ---------------------------------------------------------------------------
  static Widget sectionHeader(
    BuildContext context,
    String title, {
    IconData? icon,
    Color? iconColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (iconColor ?? cs.primary).withOpacity(0.12),
                borderRadius: BorderRadius.circular(radiusSm),
              ),
              child: Icon(icon, size: 18, color: iconColor ?? cs.primary),
            ),
            const SizedBox(width: 12),
          ],
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Icon Badge (for notification counts, etc.)
  // ---------------------------------------------------------------------------
  static Widget iconBadge(
    BuildContext context, {
    required IconData icon,
    int? count,
    Color? backgroundColor,
    Color? iconColor,
    double size = 48,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: backgroundColor ?? cs.primaryContainer.withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(
              color: cs.primary.withOpacity(0.2),
            ),
          ),
          child: Icon(
            icon,
            size: size * 0.5,
            color: iconColor ?? cs.primary,
          ),
        ),
        if (count != null && count > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.error,
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 2),
              ),
              constraints: const BoxConstraints(
                minWidth: 20,
                minHeight: 20,
              ),
              child: Text(
                count > 99 ? "99+" : count.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onError,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Chip/Tag Style
  // ---------------------------------------------------------------------------
  static Widget chip(
    BuildContext context,
    String text, {
    IconData? icon,
    Color? color,
    bool selected = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final chipColor = color ?? cs.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? chipColor : chipColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(
          color: selected ? chipColor : chipColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : chipColor,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: selected ? Colors.white : chipColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Status Indicator
  // ---------------------------------------------------------------------------
  static Widget statusIndicator(
    BuildContext context,
    String text, {
    required StatusType type,
  }) {
    final cs = Theme.of(context).colorScheme;
    
    Color bgColor;
    Color fgColor;
    IconData icon;
    
    switch (type) {
      case StatusType.success:
        bgColor = Colors.green.withOpacity(0.15);
        fgColor = Colors.green.shade400;
        icon = Icons.check_circle_rounded;
        break;
      case StatusType.warning:
        bgColor = Colors.orange.withOpacity(0.15);
        fgColor = Colors.orange.shade400;
        icon = Icons.warning_rounded;
        break;
      case StatusType.error:
        bgColor = cs.error.withOpacity(0.15);
        fgColor = cs.error;
        icon = Icons.error_rounded;
        break;
      case StatusType.info:
        bgColor = cs.primary.withOpacity(0.15);
        fgColor = cs.primary;
        icon = Icons.info_rounded;
        break;
      case StatusType.processing:
        bgColor = cs.primary.withOpacity(0.15);
        fgColor = cs.primary;
        icon = Icons.hourglass_top_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(radiusSm),
        border: Border.all(color: fgColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fgColor),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: fgColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

enum StatusType {
  success,
  warning,
  error,
  info,
  processing,
}

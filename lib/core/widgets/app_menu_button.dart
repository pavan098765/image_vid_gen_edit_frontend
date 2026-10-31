import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';

/// Opens the side menu (account, theme, storage, and legal).
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Menu',
      icon: Icon(LucideIcons.menu, color: cs.onSurface),
      onPressed: openAppMenu,
    );
  }
}

/// Shared top bar: menu, then the Kala logo, then optional actions.
/// Title stays left beside the menu and shrinks instead of overflowing.
class KalaTabAppBar extends StatelessWidget implements PreferredSizeWidget {
  final List<Widget>? actions;

  const KalaTabAppBar({super.key, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppBar(
      leading: const AppMenuButton(),
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            color: isDark
                ? Colors.black.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ),
      title: const FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
      ),
      actions: actions,
    );
  }
}

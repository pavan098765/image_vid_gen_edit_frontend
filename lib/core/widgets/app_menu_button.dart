import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';

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

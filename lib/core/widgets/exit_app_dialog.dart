import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';

/// Exit confirmation used by the main tabs.
class ConfirmExitAppDialog extends StatelessWidget {
  const ConfirmExitAppDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.logOut,
              size: 40,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Exit App?',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Are you sure you want to exit?',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Exit',
                icon: LucideIcons.logOut,
                onPressed: () => Navigator.pop(context, true),
                variant: ButtonVariant.danger,
                size: ButtonSize.medium,
                expanded: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

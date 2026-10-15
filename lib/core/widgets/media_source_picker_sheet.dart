import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Standard card for Gallery / Camera selection (shared layout across tools).
class MediaSourcePickerTile extends StatelessWidget {
  const MediaSourcePickerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: accentColor),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: 38,
                width: double.infinity,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    sublabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _mediaSourceSheetGrabber(ColorScheme cs) {
  return Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: cs.outlineVariant.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// Bottom sheet: handle + title row + [Gallery | Camera] using [MediaSourcePickerTile].
Future<ImageSource?> showMediaSourcePickerBottomSheet(
  BuildContext context, {
  required String title,
  IconData titleIcon = LucideIcons.imagePlus,
  Color? titleIconAccent,
  String galleryLabel = 'Gallery',
  String cameraLabel = 'Camera',
  String gallerySublabel = 'Choose from gallery',
  String cameraSublabel = 'Take a new photo',
  IconData galleryIcon = LucideIcons.image,
  IconData cameraIcon = LucideIcons.camera,
  Color? galleryAccent,
  Color? cameraAccent,
}) {
  final cs = Theme.of(context).colorScheme;
  final gAcc = galleryAccent ?? cs.primary;
  final cAcc = cameraAccent ?? cs.secondary;
  final headTint = titleIconAccent ?? cs.primary;

  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _mediaSourceSheetGrabber(cs),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: headTint.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(titleIcon, color: headTint, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: MediaSourcePickerTile(
                        icon: galleryIcon,
                        label: galleryLabel,
                        sublabel: gallerySublabel,
                        accentColor: gAcc,
                        onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MediaSourcePickerTile(
                        icon: cameraIcon,
                        label: cameraLabel,
                        sublabel: cameraSublabel,
                        accentColor: cAcc,
                        onTap: () => Navigator.pop(ctx, ImageSource.camera),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
    },
  );
}

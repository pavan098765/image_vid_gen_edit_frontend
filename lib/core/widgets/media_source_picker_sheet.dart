import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Standard card for Camera / Photos selection (shared layout across tools).
class MediaSourcePickerTile extends StatelessWidget {
  const MediaSourcePickerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.accentColor,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final Color accentColor;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(compact ? 8 : 16),
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
                padding: EdgeInsets.all(compact ? 8 : 14),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: compact ? 20 : 28, color: accentColor),
              ),
              SizedBox(height: compact ? 8 : 12),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: compact ? 12 : 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                height: compact ? 28 : 38,
                width: double.infinity,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    sublabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.72),
                      fontSize: compact ? 10 : 12,
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

/// Bottom sheet matching the attach picker: Camera, then Photos.
Future<ImageSource?> showMediaSourcePickerBottomSheet(
  BuildContext context, {
  required String title,
  String galleryLabel = 'Photos',
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

  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _mediaSourceSheetGrabber(cs),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: MediaSourcePickerTile(
                        icon: cameraIcon,
                        label: cameraLabel,
                        sublabel: cameraSublabel,
                        accentColor: cAcc,
                        onTap: () => Navigator.pop(ctx, ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: MediaSourcePickerTile(
                        icon: galleryIcon,
                        label: galleryLabel,
                        sublabel: gallerySublabel,
                        accentColor: gAcc,
                        onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

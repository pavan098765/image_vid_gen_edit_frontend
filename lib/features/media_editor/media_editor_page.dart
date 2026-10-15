// lib/features/media_editor/media_editor_page.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import '../image_editor/image_editor_page.dart';
import '../video_editor/video_editor_page.dart';

/// Unified Media Editor page that intelligently handles both photos and videos.
/// Users can toggle between photo and video editing modes.
class MediaEditorPage extends StatefulWidget {
  const MediaEditorPage({super.key});

  @override
  State<MediaEditorPage> createState() => _MediaEditorPageState();
}

class _MediaEditorPageState extends State<MediaEditorPage>
    with SingleTickerProviderStateMixin {
  /// 0 = Photo, 1 = Video
  int _selectedMode = 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
        backgroundColor: cs.surface,
        elevation: 0,
        actions: [
          // Photo/Video toggle in actions
          _buildSegmentedToggle(cs, isDark),
          const SizedBox(width: 12),
        ],
      ),
      body: IndexedStack(
        index: _selectedMode,
        children: const [
          // Pass showAppBar: false to avoid double AppBars
          EditorPage(showAppBar: false),
          VideoEditorPage(showAppBar: false),
        ],
      ),
    );
  }

  Widget _buildSegmentedToggle(ColorScheme cs, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            icon: LucideIcons.image,
            label: 'Photo',
            isSelected: _selectedMode == 0,
            onTap: () => setState(() => _selectedMode = 0),
            cs: cs,
            isDark: isDark,
          ),
          const SizedBox(width: 2),
          _buildToggleButton(
            icon: LucideIcons.video,
            label: 'Video',
            isSelected: _selectedMode == 1,
            onTap: () => setState(() => _selectedMode = 1),
            cs: cs,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme cs,
    required bool isDark,
  }) {
    final selectedColor = isDark ? KalaColors.cyan : KalaColors.purple;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: selectedColor.withValues(alpha: 0.5), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? selectedColor
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? selectedColor
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

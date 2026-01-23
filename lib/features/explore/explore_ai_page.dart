// lib/features/explore/explore_ai_page.dart

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';

/// Explore AI page - Placeholder for future AI exploration features.
/// This page will be built out with curated AI content, trending creations,
/// community showcases, and AI inspiration galleries.
class ExploreAIPage extends StatelessWidget {
  const ExploreAIPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
        backgroundColor: cs.surface,
        elevation: 0,
      ),
      body: _buildPlaceholderContent(cs, isDark),
    );
  }

  Widget _buildPlaceholderContent(ColorScheme cs, bool isDark) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon container
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    (isDark ? KalaColors.cyan : KalaColors.purple)
                        .withValues(alpha: 0.2),
                    (isDark ? KalaColors.purple : KalaColors.cyan)
                        .withValues(alpha: 0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color: (isDark ? KalaColors.cyan : KalaColors.purple)
                      .withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: Icon(
                LucideIcons.sparkles,
                size: 48,
                color: isDark ? KalaColors.cyan : KalaColors.purple,
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Coming Soon',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              'We\'re building something amazing!\nExplore trending AI art, community creations,\nand get inspired by what others are making.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 40),

            // Feature preview cards
            _buildFeaturePreviewCards(cs, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturePreviewCards(ColorScheme cs, bool isDark) {
    final features = [
      {'icon': LucideIcons.trendingUp, 'label': 'Trending'},
      {'icon': LucideIcons.users, 'label': 'Community'},
      {'icon': LucideIcons.lightbulb, 'label': 'Inspiration'},
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: features.map((feature) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  feature['icon'] as IconData,
                  size: 24,
                  color: cs.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  feature['label'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

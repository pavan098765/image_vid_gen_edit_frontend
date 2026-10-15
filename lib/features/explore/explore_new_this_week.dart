import 'package:flutter/material.dart';

class ExploreNewThisWeek extends StatelessWidget {
  final List<Map<String, dynamic>> templates;
  final ValueChanged<Map<String, dynamic>> onTap;
  final Set<String> favoriteIds;
  final ValueChanged<String> onToggleFavorite;

  const ExploreNewThisWeek({
    super.key,
    required this.templates,
    required this.onTap,
    required this.favoriteIds,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'New this week',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: templates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final t = templates[i];
                final id = t['id'] as String? ?? '';
                final fav = favoriteIds.contains(id);
                return SizedBox(
                  width: 200,
                  child: Material(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => onTap(t),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                t['title'] as String? ?? 'Template',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                fav ? Icons.favorite : Icons.favorite_border,
                                color: fav
                                    ? cs.primary
                                    : cs.onSurface.withValues(alpha: 0.7),
                              ),
                              onPressed: () => onToggleFavorite(id),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

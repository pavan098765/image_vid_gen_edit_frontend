import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
            height: 168,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: templates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final t = templates[i];
                final id = t['id'] as String? ?? '';
                return _NewWeekCard(
                  template: t,
                  isFavorite: favoriteIds.contains(id),
                  onTap: () => onTap(t),
                  onToggleFavorite: () => onToggleFavorite(id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NewWeekCard extends StatefulWidget {
  final Map<String, dynamic> template;
  final bool isFavorite;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const _NewWeekCard({
    required this.template,
    required this.isFavorite,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  State<_NewWeekCard> createState() => _NewWeekCardState();
}

class _NewWeekCardState extends State<_NewWeekCard> {
  VideoPlayerController? _video;
  var _closed = false;

  bool get _isVideo => widget.template['preview_type'] == 'video';

  String? get _previewUrl {
    final url = widget.template['preview_url'] as String?;
    if (url == null || url.isEmpty) return null;
    return url;
  }

  @override
  void initState() {
    super.initState();
    final url = _previewUrl;
    if (!_isVideo || url == null) return;
    _startVideo(url);
  }

  Future<void> _startVideo(String url) async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted || _closed) return;
      await controller.setLooping(true);
      await controller.setVolume(0);
      await controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _closed = true;
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.template['title'] as String? ?? 'Template';
    final url = _previewUrl;
    final videoReady = _video?.value.isInitialized ?? false;

    return SizedBox(
      width: 132,
      child: Material(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null && _isVideo && videoReady)
                FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _video!.value.size.width,
                    height: _video!.value.size.height,
                    child: VideoPlayer(_video!),
                  ),
                )
              else if (url != null && !_isVideo)
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                    stops: [0.45, 1],
                  ),
                ),
              ),
              if (_isVideo)
                const Positioned(
                  left: 8,
                  top: 8,
                  child: Icon(Icons.play_circle_fill, color: Colors.white, size: 22),
                ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  tooltip: widget.isFavorite ? 'Unfavorite' : 'Favorite',
                  icon: Icon(
                    widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: widget.isFavorite ? cs.primary : Colors.white,
                    size: 20,
                  ),
                  onPressed: widget.onToggleFavorite,
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
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

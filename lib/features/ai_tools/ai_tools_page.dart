import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/result_manager_page.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/generic_tool_page.dart';

// -------------------- MODEL CLASSES --------------------
class ToolConfig {
  final List<ToolCategory> categories;
  ToolConfig({required this.categories});

  factory ToolConfig.fromJson(Map<String, dynamic> json) => ToolConfig(
        categories: (json['categories'] as List)
            .map((c) => ToolCategory.fromJson(c))
            .toList(),
      );
}

class ToolCategory {
  final String title;
  final Color accent;
  final List<ToolItem> tools;

  ToolCategory({
    required this.title,
    required this.accent,
    required this.tools,
  });

  factory ToolCategory.fromJson(Map<String, dynamic> json) => ToolCategory(
        title: json['title'],
        accent: Color(
          int.parse(json['accent'].substring(1, 7), radix: 16) + 0xFF000000,
        ),
        tools:
            (json['tools'] as List).map((t) => ToolItem.fromJson(t)).toList(),
      );
}

class ToolItem {
  final String name;
  final String icon;
  final List<String> caps;
  final String type;
  final String model;
  final int maxImages;
  final List<dynamic>? inputs;
  final Map<String, dynamic>? params;
  final String? outputType;
  final Map<String, dynamic>? modes;
  final List<dynamic>? elements;
  final int cost;
  final int costUpscale;
  final int offer;

  ToolItem({
    required this.name,
    required this.icon,
    required this.caps,
    required this.type,
    required this.model,
    this.maxImages = 1,
    this.inputs,
    this.params,
    this.outputType,
    this.modes,
    this.elements,
    this.cost = 0,
    this.costUpscale = 0,
    this.offer = 0,
  });

  factory ToolItem.fromJson(Map<String, dynamic> json) => ToolItem(
        name: json['name'],
        icon: json['icon'],
        caps: List<String>.from(json['caps']),
        type: json['type'],
        model: json['model'],
        maxImages: json['maxImages'] ?? 1,
        inputs: json['inputs'],
        params: json['params'],
        outputType: json['outputType'],
        modes: json['modes'],
        elements: json['elements'],
        cost: json['cost'] ?? 0,
        costUpscale: json['cost_upscale'] ?? 0,
        offer: json['offer'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        "name": name,
        "icon": icon,
        "caps": caps,
        "type": type,
        "model": model,
        "maxImages": maxImages,
        "inputs": inputs,
        "params": params,
        "outputType": outputType,
        "modes": modes,
        "elements": elements,
        "cost": cost,
        "costUpscale": costUpscale,
        "offer": offer,
      };
}

// -------------------- MAIN PAGE --------------------
class AiToolsPage extends StatefulWidget {
  const AiToolsPage({super.key});

  @override
  State<AiToolsPage> createState() => _AiToolsPageState();
}

class _AiToolsPageState extends State<AiToolsPage>
    with SingleTickerProviderStateMixin {
  late Future<ToolConfig> _futureConfig;
  static const String cacheKey = "cached_tool_config_v1";
  static const String cacheDateKey = "cached_tool_config_date_v1";
  static const String configUrl =
      "https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/tool_config.json";

  late AnimationController _glowController;
  Set<String> _seenJobIds = {};
  static const String _seenJobsKey = 'seen_completed_job_ids';
  
  // Track expanded state of each category (by index)
  // All expanded by default
  final Map<int, bool> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _futureConfig = _loadToolConfig();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _loadSeenJobs();
    jobListNotifier.addListener(_checkCompletedJobs);
  }

  Future<void> _loadSeenJobs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final seenList = prefs.getStringList(_seenJobsKey) ?? [];
      _seenJobIds = seenList.toSet();
      setState(() {});
    } catch (e) {
      debugPrint('⚠️ Failed to load seen jobs: $e');
    }
  }

  Future<void> _markAllCompletedAsSeen() async {
    try {
      final completedJobs = jobListNotifier.value
          .where((j) => j.status == 'completed')
          .map((j) => j.jobId)
          .toList();
      _seenJobIds.addAll(completedJobs);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_seenJobsKey, _seenJobIds.toList());
      setState(() {});
    } catch (e) {
      debugPrint('⚠️ Failed to save seen jobs: $e');
    }
  }

  void _checkCompletedJobs() {
    setState(() {
      // Trigger rebuild to update count
    });
  }

  int _getUnseenCompletedCount() {
    return jobListNotifier.value
        .where((j) => j.status == 'completed' && !_seenJobIds.contains(j.jobId))
        .length;
  }

  bool _hasUnseenCompleted() {
    return _getUnseenCompletedCount() > 0;
  }

  @override
  void dispose() {
    _glowController.dispose();
    jobListNotifier.removeListener(_checkCompletedJobs);
    super.dispose();
  }

  Future<ToolConfig> _loadToolConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final lastFetchedDate = prefs.getString(cacheDateKey)?.substring(0, 10);
    final cachedData = prefs.getString(cacheKey);

    if (lastFetchedDate == today && cachedData != null) {
      debugPrint("📦 Using cached tool config");
      return ToolConfig.fromJson(jsonDecode(cachedData));
    }

    try {
      final response = await http.get(Uri.parse(configUrl));
      if (response.statusCode == 200) {
        await prefs.setString(cacheKey, response.body);
        await prefs.setString(cacheDateKey, today);
        return ToolConfig.fromJson(jsonDecode(response.body));
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      if (cachedData != null) {
        return ToolConfig.fromJson(jsonDecode(cachedData));
      }
      throw Exception("No internet and no cached data");
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
        actions: [
          // ✅ Credits Chip (Option A - Primary Themed)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ValueListenableBuilder<int>(
              valueListenable: userCreditsNotifier,
              builder: (_, credits, __) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.primary,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.gem,
                      color: cs.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "$credits",
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ✅ Results button (glowing)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ValueListenableBuilder<List<JobModel>>(
              valueListenable: jobListNotifier,
              builder: (_, jobs, __) {
                final unseenCount = _getUnseenCompletedCount();
                final hasUnseen = _hasUnseenCompleted();

                return AnimatedBuilder(
                  animation: _glowController,
                  builder: (context, child) {
                    final glowIntensity = hasUnseen
                        ? 0.3 + (_glowController.value * 0.2)
                        : 0.0;

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Glow effect container
                        if (hasUnseen)
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: cs.primary.withOpacity(glowIntensity),
                                  blurRadius: 12 + (_glowController.value * 8),
                                  spreadRadius: 2 + (_glowController.value * 2),
                                ),
                                BoxShadow(
                                  color: cs.secondary.withOpacity(glowIntensity * 0.7),
                                  blurRadius: 8 + (_glowController.value * 4),
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        // Main button
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasUnseen
                                ? cs.primaryContainer.withOpacity(0.3)
                                : Colors.transparent,
                            border: hasUnseen
                                ? Border.all(
                                    color: cs.primary.withOpacity(0.4),
                                    width: 1.5,
                                  )
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: () {
                                _markAllCompletedAsSeen();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const ResultManagerPage()),
                                );
                              },
                              child: Icon(
                                LucideIcons.folderCheck,
                                size: 28,
                                color: hasUnseen
                                    ? cs.primary
                                    : cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                        // Badge with count
                        if (unseenCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: AnimatedScale(
                              scale: hasUnseen ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.elasticOut,
                              child: Container(
                                padding: unseenCount > 9
                                    ? const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2)
                                    : const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: cs.error,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: cs.surface,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.error.withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                child: Center(
                                  child: Text(
                                    unseenCount > 99 ? '99+' : unseenCount.toString(),
                                    style: TextStyle(
                                      color: cs.onError,
                                      fontSize: unseenCount > 9 ? 10 : 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      body: FutureBuilder<ToolConfig>(
        future: _futureConfig,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }
          return _buildToolList(snapshot.data!, cs, tt);
        },
      ),
    );
  }

  Widget _buildErrorState(String msg) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off,
                size: 64, color: cs.onSurface.withOpacity(0.50)),
            const SizedBox(height: 12),
            Text(
              "Unable to load tools",
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () =>
                  setState(() => _futureConfig = _loadToolConfig()),
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolList(ToolConfig config, ColorScheme cs, TextTheme tt) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: config.categories.length,
      itemBuilder: (_, i) {
        final cat = config.categories[i];
        final isExpanded = _expandedCategories[i] ?? true; // Default expanded
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            // Collapsible header
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _expandedCategories[i] = !isExpanded;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: cat.accent.withOpacity(isExpanded ? 0.08 : 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cat.accent.withOpacity(isExpanded ? 0.2 : 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 5,
                        height: 22,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: cat.accent,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          cat.title,
                          style: tt.titleMedium?.copyWith(
                            color: cat.accent,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      // Tool count badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cat.accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${cat.tools.length}',
                          style: tt.labelSmall?.copyWith(
                            color: cat.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Chevron indicator
                      AnimatedRotation(
                        turns: isExpanded ? 0 : -0.25,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          LucideIcons.chevronDown,
                          color: cat.accent,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Animated tools grid
            AnimatedCrossFade(
              firstChild: Column(
                children: [
                  const SizedBox(height: 12),
                  GridView.builder(
                    itemCount: cat.tools.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 0.75,
                    ),
                    itemBuilder: (_, j) =>
                        _ToolCard(item: cat.tools[j], accent: cat.accent),
                  ),
                ],
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: isExpanded 
                  ? CrossFadeState.showFirst 
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 250),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        );
      },
    );
  }
}

// -------------------- TOOL CARD --------------------
class _ToolCard extends StatefulWidget {
  final ToolItem item;
  final Color accent;
  const _ToolCard({required this.item, required this.accent});

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _hover = false;

  IconData _resolveIcon(String name) {
    switch (name.toLowerCase()) {
      // Image Generation & Editing
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'wand':
      case 'wand2':
        return LucideIcons.wand2;
      case 'palette':
        return LucideIcons.palette;
      case 'paintbrush':
        return LucideIcons.paintbrush;
      case 'edit3':
        return LucideIcons.edit3;
      case 'image':
        return LucideIcons.image;
      case 'images':
      case 'galleryvertical':
        return LucideIcons.galleryVertical;
      case 'layers':
        return LucideIcons.layers;
      case 'flaskconical':
        return LucideIcons.flaskConical;
      case 'microscope':
        return LucideIcons.microscope;
      case 'eye':
        return LucideIcons.eye;
      case 'crop':
        return LucideIcons.crop;
      case 'eraser':
        return LucideIcons.eraser;
      case 'scissors':
        return LucideIcons.scissors;
      
      // Upscalers
      case 'maximize':
      case 'maximize2':
        return LucideIcons.maximize2;
      case 'scan':
        return LucideIcons.scan;
      case 'focus':
        return LucideIcons.focus;
      case 'zoomin':
        return LucideIcons.zoomIn;
      case 'sunmedium':
        return LucideIcons.sunMedium;
      case 'contrast':
        return LucideIcons.contrast;
      case 'sparkle':
        return LucideIcons.sparkle;
      
      // Video & Animation
      case 'video':
        return LucideIcons.video;
      case 'film':
        return LucideIcons.film;
      case 'clapperboard':
        return LucideIcons.clapperboard;
      
      // Misc
      case 'zap':
        return LucideIcons.zap;
      case 'triangle':
        return LucideIcons.triangle;
      case 'aperture':
        return LucideIcons.aperture;
      
      default:
        return LucideIcons.cpu;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final accent = widget.accent;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 🌟 Main Card Container
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hover
                  ? accent.withOpacity(0.55)
                  : cs.outline.withOpacity(0.25),
              width: 1.1,
            ),
            gradient: LinearGradient(
              colors: _hover
                  ? [
                      accent.withOpacity(0.10),
                      cs.surfaceContainerHighest.withOpacity(0.08)
                    ]
                  : [
                      cs.surfaceContainerHighest.withOpacity(0.04),
                      cs.surface.withOpacity(0.03)
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.18),
                      offset: const Offset(0, 4),
                      blurRadius: 12,
                    )
                  ]
                : [],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onHover: (v) => setState(() => _hover = v),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GenericToolPage(
                    config: GenericToolConfig(
                      title: item.name,
                      model: item.model,
                      inputs: item.inputs ?? [],
                      params: item.params,
                      modes: item.modes,
                      elements: item.elements,
                      outputType: item.outputType ?? "image",
                      cost: item.cost,
                      costUpscale: item.costUpscale,
                      offer: item.offer,
                    ),
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 24), // spacing from top for badges
                  Icon(_resolveIcon(item.icon), color: accent, size: 40),
                  const SizedBox(height: 10),

                  // 🧾 Name (consistent height container)
                  SizedBox(
                    height: 36, // fixes uneven multi-line height
                    child: Center(
                      child: Text(
                        item.name,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          height: 1.18,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 🪄 Capabilities
                  Flexible(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: item.caps
                          .map(
                            (cap) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                cap,
                                maxLines: 1,
                                style: tt.labelSmall?.copyWith(
                                  color: accent.withOpacity(0.95),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),

        // 💎 Credits Badge (top-left, gradient glass look)
        if (item.cost > 0)
          Positioned(
            top: 8,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.surface.withOpacity(0.9),
                    cs.surfaceContainerHighest.withOpacity(0.85)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(0.45), width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.15),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.gem, color: accent, size: 13),
                  const SizedBox(width: 3),
                  Text(
                    "${item.cost}",
                    style: tt.labelSmall?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 🏷️ Offer Badge (top-right, pill style)
        if (item.offer > 0)
          Positioned(
            top: 8,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withOpacity(0.18),
                    accent.withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withOpacity(0.4), width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: accent.withOpacity(0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                "-${item.offer}%",
                style: tt.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

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

/// Represents a model option within a capability
class ModelOption {
  final String id;
  final String name;
  final String? description;
  final int cost;
  final int costUpscale;
  final Map<String, dynamic>? params;
  final Map<String, dynamic>? rootParams;
  final Map<String, dynamic>? inputOverrides;

  ModelOption({
    required this.id,
    required this.name,
    this.description,
    this.cost = 10,
    this.costUpscale = 5,
    this.params,
    this.rootParams,
    this.inputOverrides,
  });

  factory ModelOption.fromJson(Map<String, dynamic> json) => ModelOption(
        id: json['id'],
        name: json['name'],
        description: json['description'],
        cost: json['cost'] ?? 10,
        costUpscale: json['costUpscale'] ?? 5,
        params: json['params'],
        rootParams: json['rootParams'],
        inputOverrides: json['inputOverrides'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'cost': cost,
        'costUpscale': costUpscale,
        'params': params,
        'rootParams': rootParams,
        'inputOverrides': inputOverrides,
      };
}

/// Represents a capability (e.g., Create Image, Edit Image)
class Capability {
  final String id;
  final String name;
  final String description;
  final String icon;
  final Color accent;
  final String outputType;
  final String defaultModel;
  final List<ModelOption> models;
  final List<dynamic> inputs;
  final List<dynamic> elements;

  Capability({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.accent,
    required this.outputType,
    required this.defaultModel,
    required this.models,
    required this.inputs,
    required this.elements,
  });

  factory Capability.fromJson(Map<String, dynamic> json) => Capability(
        id: json['id'],
        name: json['name'],
        description: json['description'] ?? '',
        icon: json['icon'] ?? 'cpu',
        accent: Color(
          int.parse(json['accent'].substring(1, 7), radix: 16) + 0xFF000000,
        ),
        outputType: json['outputType'] ?? 'image',
        defaultModel: json['defaultModel'] ?? '',
        models: (json['models'] as List?)
                ?.map((m) => ModelOption.fromJson(m))
                .toList() ??
            [],
        inputs: json['inputs'] ?? [],
        elements: json['elements'] ?? [],
      );

  /// Get the default model option
  ModelOption? get defaultModelOption {
    try {
      return models.firstWhere((m) => m.id == defaultModel);
    } catch (e) {
      return models.isNotEmpty ? models.first : null;
    }
  }

  /// Get cost range string (e.g., "10" or "10-15")
  String get costRange {
    if (models.isEmpty) return '10';
    final costs = models.map((m) => m.cost).toSet().toList()..sort();
    if (costs.length == 1) return '${costs.first}';
    return '${costs.first}-${costs.last}';
  }
}

/// Root config containing all capabilities
class CapabilityConfig {
  final List<Capability> capabilities;

  CapabilityConfig({required this.capabilities});

  factory CapabilityConfig.fromJson(Map<String, dynamic> json) =>
      CapabilityConfig(
        capabilities: (json['capabilities'] as List?)
                ?.map((c) => Capability.fromJson(c))
                .toList() ??
            [],
      );
}

// -------------------- MAIN PAGE --------------------
class AiToolsPage extends StatefulWidget {
  const AiToolsPage({super.key});

  @override
  State<AiToolsPage> createState() => _AiToolsPageState();
}

class _AiToolsPageState extends State<AiToolsPage>
    with SingleTickerProviderStateMixin {
  late Future<CapabilityConfig> _futureConfig;
  static const String cacheKey = "cached_tool_config_v2";
  static const String cacheDateKey = "cached_tool_config_date_v2";
  static const String configUrl =
      "https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/tool_config.json";

  late AnimationController _glowController;
  Set<String> _seenJobIds = {};
  static const String _seenJobsKey = 'seen_completed_job_ids';

  @override
  void initState() {
    super.initState();
    _futureConfig = _loadCapabilityConfig();

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

  Future<CapabilityConfig> _loadCapabilityConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final lastFetchedDate = prefs.getString(cacheDateKey)?.substring(0, 10);
    final cachedData = prefs.getString(cacheKey);

    if (lastFetchedDate == today && cachedData != null) {
      debugPrint("📦 Using cached capability config");
      return CapabilityConfig.fromJson(jsonDecode(cachedData));
    }

    try {
      final response = await http.get(Uri.parse(configUrl));
      if (response.statusCode == 200) {
        await prefs.setString(cacheKey, response.body);
        await prefs.setString(cacheDateKey, today);
        return CapabilityConfig.fromJson(jsonDecode(response.body));
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      if (cachedData != null) {
        return CapabilityConfig.fromJson(jsonDecode(cachedData));
      }
      throw Exception("No internet and no cached data");
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 16,
        title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
        actions: [
          // Credits Chip
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

          // Results button (glowing)
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
                                  spreadRadius:
                                      2 + (_glowController.value * 2),
                                ),
                                BoxShadow(
                                  color: cs.secondary
                                      .withOpacity(glowIntensity * 0.7),
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
                                      builder: (_) =>
                                          const ResultManagerPage()),
                                );
                              },
                              child: Icon(
                                LucideIcons.folderCheck,
                                size: 28,
                                color:
                                    hasUnseen ? cs.primary : cs.onSurface,
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
                                    unseenCount > 99
                                        ? '99+'
                                        : unseenCount.toString(),
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
      body: FutureBuilder<CapabilityConfig>(
        future: _futureConfig,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }
          return _buildCapabilityGrid(snapshot.data!, cs);
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
                  setState(() => _futureConfig = _loadCapabilityConfig()),
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilityGrid(CapabilityConfig config, ColorScheme cs) {
    final tt = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header section
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              "Create Studio",
              style: tt.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: cs.onSurface,
              ),
            ),
          ),
          Text(
            "Choose what you want to create",
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // Capability grid
          GridView.builder(
            itemCount: config.capabilities.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (_, i) =>
                _CapabilityCard(capability: config.capabilities[i]),
          ),
        ],
      ),
    );
  }
}

// -------------------- CAPABILITY CARD --------------------
class _CapabilityCard extends StatefulWidget {
  final Capability capability;
  const _CapabilityCard({required this.capability});

  @override
  State<_CapabilityCard> createState() => _CapabilityCardState();
}

class _CapabilityCardState extends State<_CapabilityCard> {
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

      default:
        return LucideIcons.cpu;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cap = widget.capability;
    final accent = cap.accent;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Main Card Container
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _hover
                  ? accent.withOpacity(0.6)
                  : cs.outline.withOpacity(0.2),
              width: _hover ? 1.5 : 1,
            ),
            gradient: LinearGradient(
              colors: _hover
                  ? [
                      accent.withOpacity(0.12),
                      cs.surfaceContainerHighest.withOpacity(0.06)
                    ]
                  : [
                      cs.surfaceContainerHighest.withOpacity(0.04),
                      cs.surface.withOpacity(0.02)
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: _hover
                ? [
                    BoxShadow(
                      color: accent.withOpacity(0.2),
                      offset: const Offset(0, 6),
                      blurRadius: 16,
                    )
                  ]
                : [],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onHover: (v) => setState(() => _hover = v),
            onTap: () {
              // Get the default model
              final defaultModel = cap.defaultModelOption;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GenericToolPage(
                    config: GenericToolConfig(
                      title: cap.name,
                      model: defaultModel?.id ?? cap.defaultModel,
                      inputs: cap.inputs,
                      params: defaultModel?.params,
                      rootParams: defaultModel?.rootParams,
                      elements: cap.elements,
                      outputType: cap.outputType,
                      cost: defaultModel?.cost ?? 10,
                      costUpscale: defaultModel?.costUpscale ?? 5,
                      // Pass models for model selector
                      models: cap.models
                          .map((m) => {
                                'id': m.id,
                                'name': m.name,
                                'description': m.description,
                                'cost': m.cost,
                                'costUpscale': m.costUpscale,
                                'params': m.params,
                                'rootParams': m.rootParams,
                                'inputOverrides': m.inputOverrides,
                              })
                          .toList(),
                      defaultModel: cap.defaultModel,
                    ),
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon with accent background
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _resolveIcon(cap.icon),
                      color: accent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Name
                  Text(
                    cap.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Description
                  Text(
                    cap.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant.withOpacity(0.8),
                      height: 1.3,
                    ),
                  ),

                  const Spacer(),

                  // Bottom row: Model count + Output type
                  Row(
                    children: [
                      // Model count badge
                      if (cap.models.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.layers,
                                  size: 12, color: accent),
                              const SizedBox(width: 4),
                              Text(
                                '${cap.models.length} models',
                                style: tt.labelSmall?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Spacer(),
                      // Output type indicator
                      Icon(
                        cap.outputType == 'video'
                            ? LucideIcons.film
                            : LucideIcons.image,
                        size: 16,
                        color: cs.onSurfaceVariant.withOpacity(0.5),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Credits Badge (top-right)
        Positioned(
          top: 10,
          right: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.surface.withOpacity(0.95),
                  cs.surfaceContainerHighest.withOpacity(0.9)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: accent.withOpacity(0.4), width: 0.8),
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
                const SizedBox(width: 4),
                Text(
                  cap.costRange,
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
      ],
    );
  }
}

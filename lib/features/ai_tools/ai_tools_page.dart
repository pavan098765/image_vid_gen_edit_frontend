import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_vid_gen_edit_frontend/core/app_state.dart';
import 'package:image_vid_gen_edit_frontend/features/result_manager/result_manager_page.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_vid_gen_edit_frontend/features/ai_tools/generic_tool_page.dart';


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
  bool _hasUnseenCompleted = false;

  @override
  void initState() {
    super.initState();
    _futureConfig = _loadToolConfig();

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    jobListNotifier.addListener(_checkCompletedJobs);
  }

  void _checkCompletedJobs() {
    final completedCount =
        jobListNotifier.value.where((j) => j.status == 'completed').length;
    setState(() {
      _hasUnseenCompleted = completedCount > 0;
    });
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
        title: Text(
          "AI Tools",
          style: tt.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
          ),
        ),
        actions: [
          // ✅ Credits Chip (Option A - Primary Themed)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ValueListenableBuilder<int>(
              valueListenable: userCreditsNotifier,
              builder: (_, credits, __) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                final count = jobs.where((j) => j.status == 'completed').length;

                final glow = LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.25),
                    cs.secondary.withOpacity(0.30),
                    cs.primary.withOpacity(0.25),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  stops: [
                    _glowController.value * 0.5,
                    0.5 + _glowController.value * 0.3,
                    1.0
                  ],
                );

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ShaderMask(
                      shaderCallback: (rect) => glow.createShader(rect),
                      blendMode:
                          _hasUnseenCompleted ? BlendMode.srcATop : BlendMode.dst,
                      child: IconButton(
                        icon: Icon(
                          LucideIcons.activitySquare,
                          size: 26,
                          color: cs.onSurface,
                        ),
                        tooltip: "My Results",
                        onPressed: () {
                          setState(() => _hasUnseenCompleted = false);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ResultManagerPage()),
                          );
                        },
                      ),
                    ),

                    if (count > 0)
                      Positioned(
                        right: 4,
                        top: 6,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 400),
                          opacity: _hasUnseenCompleted ? 1.0 : 0.0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cs.error,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: cs.onError.withOpacity(0.5), width: 1),
                            ),
                            child: Text(
                              count.toString(),
                              style: TextStyle(
                                color: cs.onError,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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
            Icon(Icons.cloud_off, size: 64, color: cs.onSurface.withOpacity(0.50)),
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
              onPressed: () => setState(() => _futureConfig = _loadToolConfig()),
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 24,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: cat.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Text(
                  cat.title,
                  style: tt.titleMedium?.copyWith(
                    color: cat.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              itemCount: cat.tools.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (_, j) =>
                  _ToolCard(item: cat.tools[j], accent: cat.accent),
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
      case 'sparkles':
        return LucideIcons.sparkles;
      case 'edit3':
        return LucideIcons.edit3;
      case 'image':
      case 'images':
        return LucideIcons.image;
      case 'flaskconical':
        return LucideIcons.flaskConical;
      case 'microscope':
        return LucideIcons.microscope;
      case 'eye':
        return LucideIcons.eye;
      case 'crop':
        return LucideIcons.crop;
      case 'video':
        return LucideIcons.video;
      case 'film':
        return LucideIcons.film;
      case 'zap':
        return LucideIcons.zap;
      case 'triangle':
        return LucideIcons.triangle;
      case 'aperture':
        return LucideIcons.aperture;
      case 'eraser':
        return LucideIcons.eraser;
      case 'scissors':
        return LucideIcons.scissors;
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

    return AnimatedContainer(
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
                  color: accent.withOpacity(0.22),
                  offset: const Offset(0, 6),
                  blurRadius: 16,
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
                ),
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(_resolveIcon(item.icon), color: accent, size: 40),
              const SizedBox(height: 10),
              Text(
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
              const SizedBox(height: 10),
              Wrap(
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
            ],
          ),
        ),
      ),
    );
  }
}

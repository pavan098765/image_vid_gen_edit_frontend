// lib/features/explore/explore_ai_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    hide userCreditsNotifier, currentUserNotifier, isLoadingUserNotifier, UserData;
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/result_manager_page.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;

/// =============================================================================
/// EXPLORE AI PAGE - Premium Template-Based AI Tool Launcher
/// =============================================================================
/// A high-conversion, visually stunning entry point for AI features.
/// Features: Animations, swipe navigation, intermediate config screen,
/// model selection, cost preview, and professional UI.

class ExploreAIPage extends StatefulWidget {
  const ExploreAIPage({super.key});

  @override
  State<ExploreAIPage> createState() => _ExploreAIPageState();
}

class _ExploreAIPageState extends State<ExploreAIPage>
    with TickerProviderStateMixin {
  // Config from R2 storage
  Map<String, dynamic>? _exploreConfig;
  List<dynamic> _categories = [];
  Map<String, dynamic> _templates = {};
  Map<String, dynamic> _capabilities = {};

  // UI state
  bool _isLoading = true;
  String? _loadError;
  int _selectedCategoryIndex = 0;

  // Controllers
  late TabController _tabController;
  late PageController _pageController;
  late AnimationController _headerAnimController;
  late AnimationController _cardRevealController;
  late Animation<double> _headerSlide;
  late Animation<double> _headerFade;

  // Job submission state
  bool _isSubmittingJob = false;
  static const String controllerUrl = "https://genedit.mooo.com";

  // Config loading from R2
  static const String _cacheKey = "cached_tool_config_v3";
  static const String _cacheDateKey = "cached_tool_config_date_v3";
  static const String _cacheHashKey = "cached_tool_config_hash_v3";
  static const String _configUrl =
      "https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/tool_config.json";
  static const String _configHashUrl =
      "https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/tool_config.json.sha256";

  @override
  void initState() {
    super.initState();

    // Header animation
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerSlide = Tween<double>(begin: -30, end: 0).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOutCubic),
    );
    _headerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut),
    );

    // Card reveal animation
    _cardRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Page controller for swipe navigation
    _pageController = PageController();

    _loadConfig();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pageController.dispose();
    _headerAnimController.dispose();
    _cardRevealController.dispose();
    super.dispose();
  }

  void _initTabController() {
    _tabController = TabController(
      length: _categories.length,
      vsync: this,
      initialIndex: _selectedCategoryIndex,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedCategoryIndex = _tabController.index);
        _pageController.animateToPage(
          _tabController.index,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final lastFetchedDate = prefs.getString(_cacheDateKey)?.substring(0, 10);
      final cachedData = prefs.getString(_cacheKey);
      final cachedHash = prefs.getString(_cacheHashKey);

      if (lastFetchedDate == today && cachedData != null && cachedHash != null) {
        final computedHash = _computeConfigHash(cachedData);
        if (computedHash == cachedHash) {
          debugPrint("📦 Explore: Using verified cached config");
          _parseConfig(cachedData);
          return;
        }
      }

      try {
        final responses = await Future.wait([
          http.get(Uri.parse(_configUrl)),
          http.get(Uri.parse(_configHashUrl)).catchError((_) => http.Response('', 404)),
        ]);

        final configResponse = responses[0];
        final hashResponse = responses[1];

        if (configResponse.statusCode == 200) {
          final configBody = configResponse.body;
          final computedHash = _computeConfigHash(configBody);

          if (hashResponse.statusCode == 200) {
            final serverHash = hashResponse.body.trim().toLowerCase();
            if (serverHash.isNotEmpty && computedHash != serverHash && !kDebugMode) {
              throw Exception("Config integrity verification failed");
            }
          }

          await prefs.setString(_cacheKey, configBody);
          await prefs.setString(_cacheDateKey, today);
          await prefs.setString(_cacheHashKey, computedHash);

          _parseConfig(configBody);
          return;
        } else {
          throw Exception("Server error: ${configResponse.statusCode}");
        }
      } catch (e) {
        if (cachedData != null) {
          debugPrint("⚠️ Explore: Using cached config (offline fallback)");
          _parseConfig(cachedData);
          return;
        }
        rethrow;
      }
    } catch (e) {
      debugPrint('❌ Failed to load explore config: $e');
      setState(() {
        _loadError = 'Failed to load templates';
        _isLoading = false;
      });
    }
  }

  void _parseConfig(String jsonStr) {
    final config = jsonDecode(jsonStr) as Map<String, dynamic>;

    _exploreConfig = config['explore'] as Map<String, dynamic>?;
    _categories = _exploreConfig?['categories'] ?? [];
    _templates = _exploreConfig?['templates'] ?? {};
    _capabilities = _buildCapabilitiesMap(config['capabilities'] ?? []);

    if (_categories.isNotEmpty) {
      _initTabController();
    }

    setState(() => _isLoading = false);

    // Start animations
    _headerAnimController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _cardRevealController.forward();
    });
  }

  Map<String, dynamic> _buildCapabilitiesMap(List<dynamic> capabilities) {
    final map = <String, dynamic>{};
    for (final cap in capabilities) {
      if (cap is Map<String, dynamic> && cap['id'] != null) {
        map[cap['id']] = cap;
      }
    }
    return map;
  }

  String _computeConfigHash(String data) {
    final bytes = utf8.encode(data);
    final digest = sha256.convert(bytes);
    return digest.toString().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: _isLoading
            ? _buildLoadingState(cs, isDark)
            : _loadError != null
                ? _buildErrorState(cs)
                : _buildContent(cs, isDark),
      ),
    );
  }

  // ============================================================================
  // LOADING STATE - Animated Shimmer
  // ============================================================================

  Widget _buildLoadingState(ColorScheme cs, bool isDark) {
    return Column(
      children: [
        // Header shimmer
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShimmerBox(width: 120, height: 28, isDark: isDark),
              const SizedBox(height: 20),
              _ShimmerBox(width: 280, height: 32, isDark: isDark),
              const SizedBox(height: 8),
              _ShimmerBox(width: 200, height: 16, isDark: isDark),
            ],
          ),
        ),
        // Category tabs shimmer
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 5,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 10),
              child: _ShimmerBox(width: 80, height: 40, isDark: isDark, radius: 12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Grid shimmer
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.75,
            ),
            itemCount: 6,
            itemBuilder: (_, i) => _ShimmerBox(
              width: double.infinity,
              height: double.infinity,
              isDark: isDark,
              radius: 20,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.errorContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.alertCircle, size: 48, color: cs.error),
          ),
          const SizedBox(height: 20),
          Text(
            _loadError ?? 'Something went wrong',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          GradientButton(
            icon: LucideIcons.refreshCw,
            label: 'Try Again',
            onPressed: () {
              setState(() {
                _isLoading = true;
                _loadError = null;
              });
              _loadConfig();
            },
            variant: ButtonVariant.secondary,
            size: ButtonSize.medium,
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // MAIN CONTENT
  // ============================================================================

  Widget _buildContent(ColorScheme cs, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Animated Header
        AnimatedBuilder(
          animation: _headerAnimController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _headerSlide.value),
              child: Opacity(
                opacity: _headerFade.value,
                child: child,
              ),
            );
          },
          child: _buildHeader(cs, isDark),
        ),

        // Swipeable Category Tabs
        _buildCategoryTabs(cs, isDark),

        // Template Grid with PageView for swipe
        Expanded(
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              _tabController.animateTo(index);
              setState(() => _selectedCategoryIndex = index);
            },
            itemCount: _categories.length,
            itemBuilder: (context, categoryIndex) {
              return _buildTemplateGrid(cs, isDark, categoryIndex);
            },
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // HEADER - Premium Design
  // ============================================================================

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: Logo + Credits
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const KalaLogoWithIcon(logoHeight: 28, fontSize: 20),
              _buildCreditsChip(cs, isDark),
            ],
          ),

          const SizedBox(height: 24),

          // Greeting with gradient
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: isDark
                  ? [KalaColors.cyan, KalaColors.purple]
                  : [KalaColors.purple, KalaColors.magenta],
            ).createShader(bounds),
            child: const Text(
              'What will you create?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
                height: 1.1,
              ),
            ),
          ),

          const SizedBox(height: 6),

          Row(
            children: [
              Icon(
                LucideIcons.sparkles,
                size: 14,
                color: cs.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                'Tap any template to get started',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreditsChip(ColorScheme cs, bool isDark) {
    return ValueListenableBuilder<int>(
      valueListenable: userCreditsNotifier,
      builder: (context, credits, _) {
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            selectedIndexNotifier.value = 3;
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  KalaColors.purple.withValues(alpha: 0.2),
                  KalaColors.cyan.withValues(alpha: 0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.primary.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: KalaColors.purple.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: KalaColors.brandGradient,
                  ).createShader(bounds),
                  child: const Icon(LucideIcons.gem, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text(
                  '$credits',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.plus,
                  size: 14,
                  color: cs.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================================
  // CATEGORY TABS - Swipeable with TabBar
  // ============================================================================

  Widget _buildCategoryTabs(ColorScheme cs, bool isDark) {
    if (_categories.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 8),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          gradient: const LinearGradient(colors: KalaColors.brandGradient),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: KalaColors.purple.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        labelColor: Colors.white,
        unselectedLabelColor: cs.onSurfaceVariant,
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        tabs: _categories.map((category) {
          final cat = category as Map<String, dynamic>;
          final isSelected = _categories.indexOf(category) == _selectedCategoryIndex;

          return Tab(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: isSelected
                  ? null
                  : BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
              child: Text(cat['title'] ?? ''),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================================
  // TEMPLATE GRID - Animated Cards
  // ============================================================================

  Widget _buildTemplateGrid(ColorScheme cs, bool isDark, int categoryIndex) {
    final category = _categories[categoryIndex] as Map<String, dynamic>;
    final templateIds = (category['templates'] as List<dynamic>?) ?? [];

    if (templateIds.isEmpty) {
      return _buildEmptyCategory(cs);
    }

    return AnimatedBuilder(
      animation: _cardRevealController,
      builder: (context, child) {
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          itemCount: templateIds.length,
          itemBuilder: (context, index) {
            final templateId = templateIds[index] as String;
            final template = _templates[templateId] as Map<String, dynamic>?;

            if (template == null) return const SizedBox.shrink();

            // Staggered animation
            final delay = index * 0.1;
            final animation = Tween<double>(begin: 0, end: 1).animate(
              CurvedAnimation(
                parent: _cardRevealController,
                curve: Interval(
                  delay.clamp(0.0, 0.6),
                  (delay + 0.4).clamp(0.0, 1.0),
                  curve: Curves.easeOutBack,
                ),
              ),
            );

            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Transform.scale(
                  scale: 0.8 + (animation.value * 0.2),
                  child: Opacity(
                    opacity: animation.value,
                    child: child,
                  ),
                );
              },
              child: _TemplateCard(
                template: template,
                capabilities: _capabilities,
                isDark: isDark,
                onTap: () => _showTemplateConfigSheet(template),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyCategory(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.inbox,
              size: 48,
              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Coming soon!',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'More templates in this category',
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // TEMPLATE CONFIG SHEET - Intermediate Screen
  // ============================================================================

  Future<void> _showTemplateConfigSheet(Map<String, dynamic> template) async {
    HapticFeedback.mediumImpact();

    final result = await showModalBottomSheet<_TemplateConfigResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TemplateConfigSheet(
        template: template,
        capabilities: _capabilities,
      ),
    );

    if (result != null) {
      await _processTemplateResult(template, result);
    }
  }

  Future<void> _processTemplateResult(
    Map<String, dynamic> template,
    _TemplateConfigResult result,
  ) async {
    final mediaType = template['media_type'] as String? ?? 'image';

    if (result.customPrompt != null) {
      // Text-to-video or prompt-based
      await _submitJob(
        template,
        customPrompt: result.customPrompt,
        selectedModelId: result.selectedModelId,
        scaleFactor: result.scaleFactor,
      );
    } else if (mediaType == 'image') {
      await _pickImageAndSubmit(
        template,
        selectedModelId: result.selectedModelId,
        scaleFactor: result.scaleFactor,
      );
    } else if (mediaType == 'video') {
      await _pickVideoAndSubmit(
        template,
        selectedModelId: result.selectedModelId,
        scaleFactor: result.scaleFactor,
      );
    } else if (mediaType == 'none') {
      // Text-only, prompt should have been provided
      await _submitJob(
        template,
        selectedModelId: result.selectedModelId,
        scaleFactor: result.scaleFactor,
      );
    }
  }

  // ============================================================================
  // MEDIA PICKERS
  // ============================================================================

  Future<void> _pickImageAndSubmit(
    Map<String, dynamic> template, {
    String? selectedModelId,
    int scaleFactor = 2,
  }) async {
    final source = await _showMediaSourcePicker(isImage: true);
    if (source == null) return;

    final picker = ImagePicker();
    XFile? file;

    if (source == ImageSource.gallery) {
      file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    } else {
      file = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    }

    if (file == null) return;

    final bytes = await file.readAsBytes();
    final resizedBytes = await _resizeImageIfNeeded(bytes);

    await _submitJob(
      template,
      imageBytes: resizedBytes,
      imagePath: file.path,
      selectedModelId: selectedModelId,
      scaleFactor: scaleFactor,
    );
  }

  Future<void> _pickVideoAndSubmit(
    Map<String, dynamic> template, {
    String? selectedModelId,
    int scaleFactor = 1,
  }) async {
    final source = await _showMediaSourcePicker(isImage: false);
    if (source == null) return;

    final picker = ImagePicker();
    final file = await picker.pickVideo(source: source);

    if (file == null) return;

    final bytes = await file.readAsBytes();
    await _submitJob(
      template,
      videoBytes: bytes,
      videoPath: file.path,
      selectedModelId: selectedModelId,
      scaleFactor: scaleFactor,
    );
  }

  Future<ImageSource?> _showMediaSourcePicker({required bool isImage}) async {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    isImage ? 'Select Image' : 'Select Video',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: _buildSourceOption(
                          icon: isImage ? LucideIcons.image : LucideIcons.film,
                          label: 'Gallery',
                          sublabel: isImage ? 'Choose from photos' : 'Choose from videos',
                          color: isDark ? KalaColors.cyan : KalaColors.purple,
                          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildSourceOption(
                          icon: isImage ? LucideIcons.camera : LucideIcons.video,
                          label: 'Camera',
                          sublabel: isImage ? 'Take a new photo' : 'Record a video',
                          color: KalaColors.magenta,
                          onTap: () => Navigator.pop(ctx, ImageSource.camera),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSourceOption({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.15),
              color.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: color),
            ),
            const SizedBox(height: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              sublabel,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<Uint8List> _resizeImageIfNeeded(Uint8List bytes) async {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;

      const maxDim = 2048;
      if (decoded.width <= maxDim && decoded.height <= maxDim) {
        return bytes;
      }

      final scale = maxDim /
          (decoded.width > decoded.height ? decoded.width : decoded.height);
      final newWidth = (decoded.width * scale).round();
      final newHeight = (decoded.height * scale).round();

      final resized = img.copyResize(decoded, width: newWidth, height: newHeight);
      return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
    } catch (e) {
      debugPrint('⚠️ Image resize failed: $e');
      return bytes;
    }
  }

  // ============================================================================
  // JOB SUBMISSION
  // ============================================================================

  Future<void> _submitJob(
    Map<String, dynamic> template, {
    Uint8List? imageBytes,
    Uint8List? videoBytes,
    String? imagePath,
    String? videoPath,
    String? customPrompt,
    String? selectedModelId,
    int scaleFactor = 2,
  }) async {
    if (_isSubmittingJob) return;
    setState(() => _isSubmittingJob = true);

    final dialogMessage = ValueNotifier<String>('Preparing...');
    bool dialogDismissed = false;
    final upscaleEnabled = scaleFactor > 1;

    void dismissDialog() {
      if (!dialogDismissed && mounted) {
        dialogDismissed = true;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(messageNotifier: dialogMessage),
    );

    try {
      if (!AuthService().isSignedIn) {
        dismissDialog();
        final signedIn = await requireSignIn(context, feature: 'Explore');
        if (!signedIn) {
          setState(() => _isSubmittingJob = false);
          return;
        }
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => _ProgressDialog(messageNotifier: dialogMessage),
        );
        dialogDismissed = false;
      }

      final capabilityId = template['capability'] as String?;
      if (capabilityId == null) throw Exception('Template missing capability');

      final capability = _capabilities[capabilityId] as Map<String, dynamic>?;
      if (capability == null) throw Exception('Capability not found: $capabilityId');

      // Get model config
      final modelId = selectedModelId ??
          template['model'] as String? ??
          capability['defaultModel'];
      final models = capability['models'] as List<dynamic>? ?? [];
      final modelConfig = models.firstWhere(
        (m) => m['id'] == modelId,
        orElse: () => models.isNotEmpty ? models.first : <String, dynamic>{},
      ) as Map<String, dynamic>;

      // Calculate cost (VIP gets free upscale)
      final baseCost = modelConfig['cost'] as int? ?? 10;
      final offer = modelConfig['offer'] as int? ?? 0;
      final effectiveBaseCost = offer > 0 ? (baseCost * (1 - offer / 100)).round() : baseCost;
      final upscaleCost = isUpscaleFree() ? 0 : (modelConfig['costUpscale'] as int? ?? 5);
      final totalCost = effectiveBaseCost + (upscaleEnabled ? upscaleCost : 0);
      final currentCredits = userCreditsNotifier.value;

      if (!UserService().hasEnoughCredits(totalCost)) {
        dismissDialog();
        await _showInsufficientCreditsSheet(totalCost, currentCredits);
        setState(() => _isSubmittingJob = false);
        return;
      }

      dialogMessage.value = 'Submitting job...';

      // Build params
      final jobConfig = template['job_config'] as Map<String, dynamic>? ?? {};
      final modelParams = Map<String, dynamic>.from(
          modelConfig['params'] as Map<String, dynamic>? ?? {});
      final rootParams = Map<String, dynamic>.from(
          modelConfig['rootParams'] as Map<String, dynamic>? ?? {});

      // Apply job config
      for (final entry in jobConfig.entries) {
        if (entry.key == 'prompt') continue;
        if (entry.key == 'scale_factor') {
          // Use user-selected scale factor
          modelParams['scale_factor'] = scaleFactor;
          modelParams['scale_image'] = upscaleEnabled;
        } else {
          modelParams[entry.key] = entry.value;
        }
      }

      // Set scale_image flag and factor
      modelParams['scale_image'] = upscaleEnabled;
      modelParams['scale_factor'] = scaleFactor;

      // Set prompt
      String prompt = customPrompt ?? jobConfig['prompt'] as String? ?? '';
      rootParams['prompt'] = prompt;

      // Add media
      if (imageBytes != null) {
        modelParams['init_image'] = base64Encode(imageBytes);
      }
      if (videoBytes != null) {
        modelParams['init_video'] = base64Encode(videoBytes);
      }

      final outputType = template['output_type'] as String? ??
          capability['outputType'] as String? ??
          'image';

      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      final payload = <String, dynamic>{
        'model': modelId,
        'params': modelParams,
        'fcm_token': fcmToken,
        'enhance_prompt': false,
        'variations': 1,
        ...rootParams,
      };

      debugPrint('🚀 Explore submit: model=$modelId, capability=$capabilityId');

      final prefs = await SharedPreferences.getInstance();
      final firebaseToken = await AuthService().getIdToken();
      if (firebaseToken == null) {
        throw Exception('Not authenticated. Please sign in first.');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $firebaseToken',
      };

      final resp = await http
          .post(
            Uri.parse('$controllerUrl/submit'),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 60));

      if (resp.statusCode != 200) {
        throw Exception('Submit failed: ${resp.statusCode} ${resp.body}');
      }

      final data = jsonDecode(resp.body);
      final jobId = data['job_id']?.toString();
      final downloadUrl = data['download_url']?.toString();

      if (jobId == null) throw Exception('No job_id returned');

      debugPrint('✅ Job submitted: $jobId');

      final title = await generateFriendlyJobName();
      final newJob = JobModel(
        jobId: jobId,
        title: title,
        model: modelId ?? 'unknown',
        outputType: outputType,
        downloadUrl: downloadUrl,
        status: 'processing',
        inputImagePath: imagePath ?? videoPath,
        variations: 1,
        allCompleted: false,
        originalPrompt: prompt.isNotEmpty ? prompt : null,
      );

      await addOrUpdateJob(newJob);

      final jobContext = {
        'title': template['title'],
        'model': modelId,
        'outputType': outputType,
      };
      await prefs.setString('notify_job_$jobId', jsonEncode(jobContext));

      await UserService().refreshCredits();

      dismissDialog();
      setState(() => _isSubmittingJob = false);

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ResultManagerPage()),
        );
      }
    } catch (e) {
      debugPrint('❌ Job submission failed: $e');
      dismissDialog();
      setState(() => _isSubmittingJob = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _showInsufficientCreditsSheet(int required, int current) async {
    final cs = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 28),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cs.errorContainer.withValues(alpha: 0.4),
                          cs.errorContainer.withValues(alpha: 0.2),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.coins, size: 36, color: cs.error),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'Not Enough Credits',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),

                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                      children: [
                        const TextSpan(text: 'You need '),
                        TextSpan(
                          text: '$required',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.error,
                          ),
                        ),
                        const TextSpan(text: ' credits but only have '),
                        TextSpan(
                          text: '$current',
                          style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    child: GradientButton(
                      icon: LucideIcons.gem,
                      label: 'Get Credits',
                      onPressed: () {
                        Navigator.pop(ctx);
                        selectedIndexNotifier.value = 3;
                      },
                      variant: ButtonVariant.primary,
                      size: ButtonSize.large,
                      expanded: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// TEMPLATE CONFIG RESULT
// =============================================================================

class _TemplateConfigResult {
  final String? selectedModelId;
  final int scaleFactor; // 1 = no upscale, 2 = 2x, 4 = 4x
  final String? customPrompt;

  _TemplateConfigResult({
    this.selectedModelId,
    this.scaleFactor = 2,
    this.customPrompt,
  });

  bool get upscaleEnabled => scaleFactor > 1;
}

// =============================================================================
// TEMPLATE CONFIG SHEET - Intermediate Configuration Screen
// =============================================================================

class _TemplateConfigSheet extends StatefulWidget {
  final Map<String, dynamic> template;
  final Map<String, dynamic> capabilities;

  const _TemplateConfigSheet({
    required this.template,
    required this.capabilities,
  });

  @override
  State<_TemplateConfigSheet> createState() => _TemplateConfigSheetState();
}

class _TemplateConfigSheetState extends State<_TemplateConfigSheet> {
  late String? _selectedModelId;
  late int _scaleFactor; // 1 = off, 2 = 2x, 4 = 4x
  final TextEditingController _promptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedModelId = widget.template['model'] as String?;
    // Default scale factor from template or 2x
    final jobConfig = widget.template['job_config'] as Map<String, dynamic>? ?? {};
    _scaleFactor = jobConfig['scale_factor'] as int? ?? 2;
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _capability {
    final capId = widget.template['capability'] as String?;
    return widget.capabilities[capId] as Map<String, dynamic>?;
  }

  List<Map<String, dynamic>> get _models {
    final models = _capability?['models'] as List<dynamic>? ?? [];
    return models.cast<Map<String, dynamic>>();
  }

  String? get _preferredModelId => widget.template['preferred_model'] as String?;

  Map<String, dynamic>? get _selectedModel {
    return _models.firstWhere(
      (m) => m['id'] == _selectedModelId,
      orElse: () => _models.isNotEmpty ? _models.first : <String, dynamic>{},
    );
  }

  bool get _isVip => isVipUser();
  bool get _freeUpscale => isUpscaleFree();

  int get _baseCost {
    final cost = _selectedModel?['cost'] as int? ?? 10;
    final offer = _selectedModel?['offer'] as int? ?? 0;
    if (offer > 0) {
      return (cost * (1 - offer / 100)).round();
    }
    return cost;
  }

  int get _upscaleCost {
    if (_freeUpscale) return 0; // VIP gets free upscale
    return _selectedModel?['costUpscale'] as int? ?? 5;
  }

  int get _totalCost {
    final upscaleEnabled = _scaleFactor > 1;
    return _baseCost + (upscaleEnabled ? _upscaleCost : 0);
  }

  bool get _showPromptInput =>
      widget.template['show_prompt'] == true ||
      widget.template['media_type'] == 'none';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mediaType = widget.template['media_type'] as String? ?? 'image';
    final outputType = widget.template['output_type'] as String? ?? 'image';
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 16,
                bottom: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Template Header
                  _buildTemplateHeader(cs, isDark, mediaType, outputType),

                  const SizedBox(height: 24),

                  // Model Selection (if multiple)
                  if (_models.length > 1) ...[
                    _buildModelSelector(cs, isDark),
                    const SizedBox(height: 20),
                  ],

                  // Prompt Input (for text-based templates)
                  if (_showPromptInput) ...[
                    _buildPromptInput(cs),
                    const SizedBox(height: 20),
                  ],

                  // Upscale Selector (2x/4x)
                  _buildUpscaleSelector(cs, isDark),

                  const SizedBox(height: 20),

                  // Cost Summary
                  _buildCostSummary(cs, isDark),
                ],
              ),
            ),
          ),

          // Fixed bottom button with safe area
          Container(
            padding: EdgeInsets.fromLTRB(24, 16, 24, bottomPadding + 16),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                top: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: _buildGenerateButton(cs, mediaType),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateHeader(
    ColorScheme cs,
    bool isDark,
    String mediaType,
    String outputType,
  ) {
    final title = widget.template['title'] as String? ?? 'Template';
    final subtitle = widget.template['subtitle'] as String? ?? '';

    return Row(
      children: [
        // Template Icon
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                (isDark ? KalaColors.cyan : KalaColors.purple).withValues(alpha: 0.2),
                (isDark ? KalaColors.purple : KalaColors.cyan).withValues(alpha: 0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(
            _getOutputIcon(outputType),
            size: 28,
            color: cs.primary,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // Media type badges
              Wrap(
                spacing: 8,
                children: [
                  _MediaTypeBadge(
                    icon: _getInputIcon(mediaType),
                    label: _getInputLabel(mediaType),
                    color: _getInputColor(mediaType, isDark),
                  ),
                  _MediaTypeBadge(
                    icon: _getOutputIcon(outputType),
                    label: '→ ${_getOutputLabel(outputType)}',
                    color: _getOutputColor(outputType, isDark),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModelSelector(ColorScheme cs, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.cpu, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Model',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            if (_isVip)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: KalaColors.brandGradient),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.crown, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'VIP',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Horizontal scrollable model cards
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _models.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final model = _models[index];
              final isSelected = model['id'] == _selectedModelId;
              final isPreferred = model['id'] == _preferredModelId;
              final name = model['name'] as String? ?? model['id'];
              final desc = model['description'] as String? ?? '';
              final cost = model['cost'] as int? ?? 10;
              final offer = model['offer'] as int? ?? 0;

              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedModelId = model['id'] as String?);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 140,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(colors: KalaColors.brandGradient)
                        : null,
                    color: isSelected ? null : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : isPreferred
                              ? KalaColors.gold.withValues(alpha: 0.5)
                              : cs.outlineVariant.withValues(alpha: 0.3),
                      width: isPreferred && !isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: KalaColors.purple.withValues(alpha: 0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + Preferred badge
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : cs.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPreferred) ...[
                            const SizedBox(width: 4),
                            Icon(
                              LucideIcons.star,
                              size: 14,
                              color: isSelected ? Colors.white : KalaColors.gold,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Description
                      if (desc.isNotEmpty)
                        Expanded(
                          child: Text(
                            desc,
                            style: TextStyle(
                              fontSize: 11,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : cs.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const Spacer(),
                      // Cost
                      Row(
                        children: [
                          Icon(
                            LucideIcons.gem,
                            size: 12,
                            color: isSelected ? Colors.white70 : KalaColors.cyan,
                          ),
                          const SizedBox(width: 4),
                          if (offer > 0) ...[
                            Text(
                              '$cost',
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.white54
                                    : cs.onSurfaceVariant,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${(cost * (1 - offer / 100)).round()}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : KalaColors.cyan,
                              ),
                            ),
                          ] else
                            Text(
                              '$cost',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : cs.onSurface,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPromptInput(ColorScheme cs) {
    final placeholder = widget.template['prompt_placeholder'] as String? ??
        'Describe what you want to create...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.penTool, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Your Prompt',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptController,
          maxLines: 4,
          style: TextStyle(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildUpscaleSelector(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: KalaColors.cyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.maximize2,
                  size: 18,
                  color: KalaColors.cyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HD Upscale',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _freeUpscale
                              ? 'Free with VIP'
                              : '+$_upscaleCost credits',
                          style: TextStyle(
                            fontSize: 12,
                            color: _freeUpscale
                                ? KalaColors.gold
                                : cs.onSurfaceVariant,
                            fontWeight:
                                _freeUpscale ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        if (_freeUpscale) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            LucideIcons.crown,
                            size: 12,
                            color: KalaColors.gold,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Scale factor selector (Off / 2x / 4x)
          Row(
            children: [
              _buildScaleOption(cs, 1, 'Off'),
              const SizedBox(width: 10),
              _buildScaleOption(cs, 2, '2x'),
              const SizedBox(width: 10),
              _buildScaleOption(cs, 4, '4x'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScaleOption(ColorScheme cs, int scale, String label) {
    final isSelected = _scaleFactor == scale;
    final isUpscale = scale > 1;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _scaleFactor = scale);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: isSelected && isUpscale
                ? const LinearGradient(colors: KalaColors.brandGradient)
                : null,
            color: isSelected
                ? (isUpscale ? null : cs.surfaceContainerHigh)
                : cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? (isUpscale ? Colors.transparent : cs.primary)
                  : cs.outlineVariant.withValues(alpha: 0.3),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected && isUpscale
                ? [
                    BoxShadow(
                      color: KalaColors.purple.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? (isUpscale ? Colors.white : cs.primary)
                      : cs.onSurfaceVariant,
                ),
              ),
              if (isUpscale) ...[
                const SizedBox(height: 2),
                Text(
                  'HD',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.8)
                        : cs.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCostSummary(ColorScheme cs, bool isDark) {
    final currentCredits = userCreditsNotifier.value;
    final hasEnough = currentCredits >= _totalCost;
    final upscaleEnabled = _scaleFactor > 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            (hasEnough ? KalaColors.purple : cs.error).withValues(alpha: 0.1),
            (hasEnough ? KalaColors.cyan : cs.error).withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (hasEnough ? cs.primary : cs.error).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          // Cost breakdown
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Cost',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: KalaColors.brandGradient,
                      ).createShader(bounds),
                      child: const Icon(LucideIcons.gem, size: 20, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$_totalCost',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (upscaleEnabled && !_freeUpscale)
                      Text(
                        '($_baseCost + $_upscaleCost)',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      )
                    else if (upscaleEnabled && _freeUpscale)
                      Row(
                        children: [
                          Text(
                            '($_baseCost + ',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const Text(
                            'FREE',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: KalaColors.gold,
                            ),
                          ),
                          Text(
                            ')',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Balance
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Your Balance',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$currentCredits',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: hasEnough ? cs.primary : cs.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton(ColorScheme cs, String mediaType) {
    final hasEnough = userCreditsNotifier.value >= _totalCost;

    String buttonLabel;
    IconData buttonIcon;

    if (_showPromptInput) {
      buttonLabel = 'Generate';
      buttonIcon = LucideIcons.sparkles;
    } else if (mediaType == 'image') {
      buttonLabel = 'Select Image & Generate';
      buttonIcon = LucideIcons.image;
    } else if (mediaType == 'video') {
      buttonLabel = 'Select Video & Generate';
      buttonIcon = LucideIcons.video;
    } else {
      buttonLabel = 'Generate';
      buttonIcon = LucideIcons.sparkles;
    }

    return SizedBox(
      width: double.infinity,
      child: GradientButton(
        icon: buttonIcon,
        label: buttonLabel,
        onPressed: hasEnough
            ? () {
                String? prompt;
                if (_showPromptInput) {
                  prompt = _promptController.text.trim();
                  if (prompt.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Please enter a prompt'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                    return;
                  }
                }
                Navigator.pop(
                  context,
                  _TemplateConfigResult(
                    selectedModelId: _selectedModelId,
                    scaleFactor: _scaleFactor,
                    customPrompt: prompt,
                  ),
                );
              }
            : () {
                Navigator.pop(context);
                selectedIndexNotifier.value = 3;
              },
        variant: hasEnough ? ButtonVariant.primary : ButtonVariant.secondary,
        size: ButtonSize.large,
        expanded: true,
      ),
    );
  }

  // Helper methods for icons and labels
  IconData _getInputIcon(String mediaType) {
    switch (mediaType) {
      case 'image':
        return LucideIcons.image;
      case 'video':
        return LucideIcons.video;
      case 'audio':
        return LucideIcons.music;
      case 'none':
        return LucideIcons.penTool;
      default:
        return LucideIcons.file;
    }
  }

  String _getInputLabel(String mediaType) {
    switch (mediaType) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'audio':
        return 'Audio';
      case 'none':
        return 'Text';
      default:
        return 'Input';
    }
  }

  Color _getInputColor(String mediaType, bool isDark) {
    switch (mediaType) {
      case 'image':
        return KalaColors.purple;
      case 'video':
        return KalaColors.gold;
      case 'audio':
        return KalaColors.magenta;
      case 'none':
        return KalaColors.cyan;
      default:
        return KalaColors.purple;
    }
  }

  IconData _getOutputIcon(String outputType) {
    switch (outputType) {
      case 'image':
        return LucideIcons.image;
      case 'video':
        return LucideIcons.film;
      case 'audio':
        return LucideIcons.music;
      default:
        return LucideIcons.file;
    }
  }

  String _getOutputLabel(String outputType) {
    switch (outputType) {
      case 'image':
        return 'Image';
      case 'video':
        return 'Video';
      case 'audio':
        return 'Audio';
      default:
        return 'Output';
    }
  }

  Color _getOutputColor(String outputType, bool isDark) {
    switch (outputType) {
      case 'image':
        return isDark ? KalaColors.cyan : KalaColors.purple;
      case 'video':
        return KalaColors.gold;
      case 'audio':
        return KalaColors.magenta;
      default:
        return KalaColors.purple;
    }
  }
}

// =============================================================================
// MEDIA TYPE BADGE
// =============================================================================

class _MediaTypeBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MediaTypeBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TEMPLATE CARD - Premium Design with Animations
// =============================================================================

class _TemplateCard extends StatefulWidget {
  final Map<String, dynamic> template;
  final Map<String, dynamic> capabilities;
  final bool isDark;
  final VoidCallback onTap;

  const _TemplateCard({
    required this.template,
    required this.capabilities,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  int get _cost {
    final capId = widget.template['capability'] as String?;
    final capability = widget.capabilities[capId] as Map<String, dynamic>?;
    final models = capability?['models'] as List<dynamic>? ?? [];
    if (models.isEmpty) return 10;
    final modelId = widget.template['model'] as String?;
    final model = models.firstWhere(
      (m) => m['id'] == modelId,
      orElse: () => models.first,
    ) as Map<String, dynamic>;
    return model['cost'] as int? ?? 10;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = widget.template['title'] as String? ?? 'Template';
    final subtitle = widget.template['subtitle'] as String? ?? '';
    final badges = (widget.template['badges'] as List<dynamic>?) ?? [];
    final outputType = widget.template['output_type'] as String? ?? 'image';
    final mediaType = widget.template['media_type'] as String? ?? 'image';

    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        _pressController.forward();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        _pressController.reverse();
        widget.onTap();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        _pressController.reverse();
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: _isPressed ? 0.15 : 0.1),
                blurRadius: _isPressed ? 20 : 16,
                offset: Offset(0, _isPressed ? 8 : 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Gradient Background
                _buildGradientBackground(),

                // Pattern overlay
                _buildPatternOverlay(),

                // Dark gradient overlay
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.2),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.2, 0.5, 1.0],
                    ),
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top: Badges + Cost
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Badges
                          if (badges.isNotEmpty)
                            Flexible(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  badges.first.toString(),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          // Cost badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  LucideIcons.gem,
                                  size: 12,
                                  color: KalaColors.cyan,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$_cost',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const Spacer(),

                      // Bottom: Title, Subtitle, Media Types
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Media type indicators
                          Row(
                            children: [
                              _buildMediaIndicator(
                                _getInputIcon(mediaType),
                                _getInputColor(mediaType),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(
                                  LucideIcons.arrowRight,
                                  size: 10,
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                              _buildMediaIndicator(
                                _getOutputIcon(outputType),
                                _getOutputColor(outputType),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Title
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),

                          // Subtitle
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.75),
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaIndicator(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Icon(icon, size: 14, color: Colors.white),
    );
  }

  Widget _buildGradientBackground() {
    final templateId = widget.template['id'] as String? ?? '';
    final hash = templateId.hashCode;
    final baseHue = (hash % 360).abs().toDouble();

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HSLColor.fromAHSL(1.0, baseHue, 0.7, 0.45).toColor(),
            HSLColor.fromAHSL(1.0, (baseHue + 60) % 360, 0.6, 0.35).toColor(),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildPatternOverlay() {
    return CustomPaint(
      painter: _PatternPainter(
        color: Colors.white.withValues(alpha: 0.05),
      ),
    );
  }

  IconData _getInputIcon(String mediaType) {
    switch (mediaType) {
      case 'image':
        return LucideIcons.image;
      case 'video':
        return LucideIcons.video;
      case 'audio':
        return LucideIcons.music;
      case 'none':
        return LucideIcons.penTool;
      default:
        return LucideIcons.file;
    }
  }

  Color _getInputColor(String mediaType) {
    switch (mediaType) {
      case 'image':
        return KalaColors.purple;
      case 'video':
        return KalaColors.gold;
      case 'audio':
        return KalaColors.magenta;
      case 'none':
        return KalaColors.cyan;
      default:
        return KalaColors.purple;
    }
  }

  IconData _getOutputIcon(String outputType) {
    switch (outputType) {
      case 'image':
        return LucideIcons.image;
      case 'video':
        return LucideIcons.film;
      case 'audio':
        return LucideIcons.music;
      default:
        return LucideIcons.file;
    }
  }

  Color _getOutputColor(String outputType) {
    switch (outputType) {
      case 'image':
        return widget.isDark ? KalaColors.cyan : KalaColors.purple;
      case 'video':
        return KalaColors.gold;
      case 'audio':
        return KalaColors.magenta;
      default:
        return KalaColors.purple;
    }
  }
}

// =============================================================================
// PATTERN PAINTER - Subtle geometric pattern
// =============================================================================

class _PatternPainter extends CustomPainter {
  final Color color;

  _PatternPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const spacing = 30.0;
    for (double i = 0; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(0, i),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// =============================================================================
// SHIMMER BOX - Loading placeholder
// =============================================================================

class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final bool isDark;
  final double radius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.isDark,
    this.radius = 8,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              colors: widget.isDark
                  ? [
                      Colors.white.withValues(alpha: 0.05),
                      Colors.white.withValues(alpha: 0.1),
                      Colors.white.withValues(alpha: 0.05),
                    ]
                  : [
                      Colors.black.withValues(alpha: 0.05),
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.05),
                    ],
              stops: [
                0.0,
                _controller.value,
                1.0,
              ],
              begin: const Alignment(-1, 0),
              end: const Alignment(2, 0),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// PROGRESS DIALOG
// =============================================================================

class _ProgressDialog extends StatelessWidget {
  final ValueNotifier<String> messageNotifier;

  const _ProgressDialog({required this.messageNotifier});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(cs.primary),
              ),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<String>(
              valueListenable: messageNotifier,
              builder: (_, message, __) {
                return Text(
                  message,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

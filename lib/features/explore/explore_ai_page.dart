// lib/features/explore/explore_ai_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback, SystemNavigator;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/api/submit_payload_helpers.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/center_crop.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/explore_favorites.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/tool_launch.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/user_template_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/explore/explore_new_this_week.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/explore/explore_outcome_chips.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/explore/explore_personal_section.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    hide
        userCreditsNotifier,
        currentUserNotifier,
        isLoadingUserNotifier,
        UserData;
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sale_banner.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/media_source_picker_sheet.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/sale_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/utils/rife_interpolation.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/result_manager_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/ai_tools_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/generic_tool_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

// -----------------------------------------------------------------------------
// Explore submit: build params + fetch FCM/auth tokens in parallel with the
// heavy-tier rewarded ad (same idea as generic_tool_page _runJob).
// -----------------------------------------------------------------------------

Future<({Map<String, dynamic> snapshot, String? primaryPath})>
    saveExploreContinueMedia({
  required String prompt,
  required String? modelId,
  required bool upscaleEnabled,
  int scaleFactor = 2,
  bool interpolateEnabled = false,
  int interpolateFps = 2,
  bool enableUpscale = false,
  int upscaleFactor = 2,
  String? loraAdapter,
  String? aspectRatio,
  List<Uint8List>? images,
  List<String>? imagePaths,
  String? videoPath,
}) async {
  final media = <String, List<String>>{};
  if (images != null && images.isNotEmpty) {
    media['init_image'] = await FileService.writeLaunchCopies(
      images,
      prefix: 'explore_launch',
    );
  } else if (imagePaths != null) {
    final live = imagePaths.where((path) => File(path).existsSync()).toList();
    if (live.isNotEmpty) media['init_image'] = live;
  }
  if (videoPath != null &&
      videoPath.isNotEmpty &&
      File(videoPath).existsSync()) {
    media['input_video'] = [videoPath];
  }
  final inputPaths = media['init_image'] ?? const <String>[];
  return (
    primaryPath: inputPaths.isNotEmpty
        ? inputPaths.first
        : (videoPath != null && File(videoPath).existsSync() ? videoPath : null),
    snapshot: sanitizeSettingsSnapshot({
      'prompt': prompt,
      'modelId': modelId,
      'scaleFactor': scaleFactor,
      'variations': 1,
      'upscaleEnabled': upscaleEnabled,
      'interpolateEnabled': interpolateEnabled,
      'interpolateFps': interpolateFps,
      'enableUpscale': enableUpscale,
      'upscaleFactor': upscaleFactor,
      if (loraAdapter != null && loraAdapter.isNotEmpty)
        'loraAdapter': loraAdapter,
      if (aspectRatio != null && aspectRatio.isNotEmpty)
        'aspectRatio': aspectRatio,
      if (inputPaths.isNotEmpty) 'inputPaths': inputPaths,
      if (media.isNotEmpty) 'mediaPaths': media,
    }),
  );
}

class _ExploreSubmitPrepBundle {
  final Map<String, dynamic> modelParams;
  final Map<String, dynamic> payload;
  final String firebaseToken;
  final String prompt;

  const _ExploreSubmitPrepBundle({
    required this.modelParams,
    required this.payload,
    required this.firebaseToken,
    required this.prompt,
  });
}

Future<_ExploreSubmitPrepBundle?> _runExploreHeavyTierGateWithParallelPrep(
  BuildContext context,
  Future<_ExploreSubmitPrepBundle> Function() prep,
) async {
  if (!shouldRequireHeavyTierRewardedAd()) {
    return prep();
  }
  final results = await Future.wait<Object>([
    completeHeavyTierRewardedAdIfNeeded(context),
    prep(),
  ]);
  if (!(results[0] as bool)) return null;
  return results[1] as _ExploreSubmitPrepBundle;
}

Future<_ExploreSubmitPrepBundle> _buildExploreSubmitPrepBeforeUpload({
  required Map<String, dynamic> jobConfig,
  required Map<String, dynamic> modelConfig,
  required String modelId,
  required String outputType,
  required bool upscaleEnabled,
  required int scaleFactor,
  required bool enableInterpolate,
  required int interpolateFps,
  required bool enableVideoEnhanceUpscale,
  required int videoEnhanceUpscaleFactor,
  required String prompt,
  String? loraAdapter,
}) async {
  final modelParams = Map<String, dynamic>.from(
      modelConfig['params'] as Map<String, dynamic>? ?? {});
  final rootParams = Map<String, dynamic>.from(
      modelConfig['rootParams'] as Map<String, dynamic>? ?? {});

  for (final entry in jobConfig.entries) {
    if (entry.key == 'prompt') continue;
    if (entry.key == 'scale_factor') {
      if (outputType == 'video') {
        modelParams['scale_factor'] = entry.value;
        modelParams['scale_image'] = false;
      } else {
        modelParams['scale_factor'] = scaleFactor;
        modelParams['scale_image'] = upscaleEnabled;
      }
    } else {
      modelParams[entry.key] = entry.value;
    }
  }

  final dynamic useExternalApiRaw =
      modelConfig['useExternalApi'] ?? modelConfig['use_external_api'];
  if (useExternalApiRaw is bool) {
    modelParams['use_external_api'] = useExternalApiRaw;
  }

  if (outputType == 'video') {
    modelParams['scale_image'] = false;
    modelParams.putIfAbsent('scale_factor', () => 1);
    if (enableInterpolate) {
      final mult = migrateLegacyInterpolateStorageValue(interpolateFps);
      final baseFps = estimatedBaseFpsForRife(
        modelId: modelId,
        modelParams: modelParams,
        isVideoUpscalerTool: false,
      );
      modelParams['enable_rife'] = true;
      modelParams['rife_target_fps'] = rifeTargetFpsForSubmit(
        multiplier: mult,
        baseFps: baseFps,
        forUpscalerTargetFps: false,
      );
    } else {
      modelParams['enable_rife'] = false;
    }
    if (enableVideoEnhanceUpscale) {
      modelParams['enable_upscaling'] = true;
      modelParams['upscale_factor'] = videoEnhanceUpscaleFactor;
    } else {
      modelParams['enable_upscaling'] = false;
    }
  } else {
    modelParams['scale_image'] = upscaleEnabled;
    modelParams['scale_factor'] = scaleFactor;
  }

  rootParams['prompt'] = prompt;

  if (loraAdapter != null && modelId == 'qwen_image_edit_2511_rapid_aio') {
    modelParams['lora_adapter'] = loraAdapter;
  }

  String? fcmToken;
  try {
    fcmToken = await FirebaseMessaging.instance.getToken();
  } catch (_) {}

  final payload = buildSubmitPayload(
    modelId: modelId,
    modelParams: modelParams,
    fcmToken: fcmToken,
    rootParams: rootParams,
    enhancePrompt: false,
    variations: 1,
  );

  final firebaseToken = await AuthService().getIdToken();
  if (firebaseToken == null) {
    throw Exception('Not authenticated. Please sign in first.');
  }

  return _ExploreSubmitPrepBundle(
    modelParams: modelParams,
    payload: payload,
    firebaseToken: firebaseToken,
    prompt: prompt,
  );
}

/// =============================================================================
/// EXPLORE AI PAGE - Premium Template-Based AI Tool Launcher
/// =============================================================================
/// A high-conversion, visually stunning entry point for AI features.
/// Features: Animations, swipe navigation, intermediate config screen,
/// model selection, cost preview, and professional UI.

// =============================================================================
// VIDEO PREVIEW MANAGER - Controls concurrent video playback with disk caching
// Auto-generates thumbnails from videos for smooth loading experience
// =============================================================================

class _VideoPreviewManager {
  static final _VideoPreviewManager _instance = _VideoPreviewManager._();
  static _VideoPreviewManager get instance => _instance;
  _VideoPreviewManager._();

  static const int maxConcurrentVideos =
      3; // Increased for better UX with all-video previews
  final Map<String, VideoPlayerController> _activeControllers = {};
  final List<String> _playOrder = []; // Track order for LRU eviction
  Directory? _cacheDir;

  // Thumbnail cache (in-memory for quick access)
  final Map<String, Uint8List> _thumbnailCache = {};
  // Track ongoing thumbnail generation to prevent duplicates
  final Map<String, Future<Uint8List?>> _pendingThumbnails = {};

  /// Get or create cache directory for video previews
  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appDir.path}/video_previews');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// Get hash for URL (used for file names)
  String _getUrlHash(String url) {
    return md5.convert(utf8.encode(url)).toString();
  }

  /// Get thumbnail for a video URL (returns cached or generates new)
  Future<Uint8List?> getThumbnail(String videoUrl) async {
    final hash = _getUrlHash(videoUrl);

    // Check in-memory cache first
    if (_thumbnailCache.containsKey(hash)) {
      return _thumbnailCache[hash];
    }

    // Check if there's a pending thumbnail generation
    if (_pendingThumbnails.containsKey(hash)) {
      return _pendingThumbnails[hash];
    }

    // Check disk cache
    try {
      final cacheDir = await _getCacheDir();
      final thumbFile = File('${cacheDir.path}/${hash}_thumb.jpg');

      if (await thumbFile.exists()) {
        final bytes = await thumbFile.readAsBytes();
        _thumbnailCache[hash] = bytes;
        debugPrint('📦 Using cached thumbnail: ${hash}_thumb.jpg');
        return bytes;
      }
    } catch (e) {
      debugPrint('⚠️ Error reading cached thumbnail: $e');
    }

    // Generate thumbnail (this will also cache it)
    final future = _generateThumbnail(videoUrl);
    _pendingThumbnails[hash] = future;

    final result = await future;
    _pendingThumbnails.remove(hash);
    return result;
  }

  /// Generate thumbnail from video URL
  Future<Uint8List?> _generateThumbnail(String videoUrl) async {
    final hash = _getUrlHash(videoUrl);

    try {
      // First, ensure video is cached
      final videoFile = await _getCachedVideo(videoUrl);
      final videoPath = videoFile?.path ?? videoUrl;

      debugPrint('🖼️ Generating thumbnail for: $hash');

      // Extract first frame using video_thumbnail
      final thumbnailBytes = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 400, // Good balance of quality vs size
        quality: 75,
        timeMs: 0, // First frame
      );

      if (thumbnailBytes != null) {
        // Cache to memory
        _thumbnailCache[hash] = thumbnailBytes;

        // Cache to disk
        try {
          final cacheDir = await _getCacheDir();
          final thumbFile = File('${cacheDir.path}/${hash}_thumb.jpg');
          await thumbFile.writeAsBytes(thumbnailBytes);
          debugPrint('✅ Thumbnail cached: ${hash}_thumb.jpg');
        } catch (e) {
          debugPrint('⚠️ Failed to cache thumbnail to disk: $e');
        }

        return thumbnailBytes;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to generate thumbnail: $e');
    }
    return null;
  }

  /// Download video to cache if not already cached
  Future<File?> _getCachedVideo(String videoUrl) async {
    try {
      final cacheDir = await _getCacheDir();
      final hash = _getUrlHash(videoUrl);
      final cachedFile = File('${cacheDir.path}/$hash.mp4');

      // Check if already cached
      if (await cachedFile.exists()) {
        debugPrint('📦 Using cached video: $hash.mp4');
        return cachedFile;
      }

      // Download and cache
      debugPrint('⬇️ Downloading video for cache: $videoUrl');
      final response = await http.get(Uri.parse(videoUrl));
      if (response.statusCode == 200) {
        await cachedFile.writeAsBytes(response.bodyBytes);
        debugPrint('✅ Video cached: $hash.mp4');
        return cachedFile;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to cache video: $e');
    }
    return null;
  }

  Future<VideoPlayerController?> getOrCreateController(
    String templateId,
    String videoUrl,
  ) async {
    // If already exists, move to end of play order and return
    if (_activeControllers.containsKey(templateId)) {
      _playOrder.remove(templateId);
      _playOrder.add(templateId);
      return _activeControllers[templateId];
    }

    // If at max capacity, pause and remove oldest
    while (_activeControllers.length >= maxConcurrentVideos &&
        _playOrder.isNotEmpty) {
      final oldestId = _playOrder.removeAt(0);
      final oldController = _activeControllers.remove(oldestId);
      await oldController?.pause();
      await oldController?.dispose();
    }

    // Create new controller (try cached file first, fallback to network)
    try {
      VideoPlayerController controller;

      // Try to use cached video
      final cachedFile = await _getCachedVideo(videoUrl);
      if (cachedFile != null) {
        controller = VideoPlayerController.file(cachedFile);
      } else {
        // Fallback to network streaming
        controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      }

      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(0); // Muted

      _activeControllers[templateId] = controller;
      _playOrder.add(templateId);

      return controller;
    } catch (e) {
      debugPrint('⚠️ Failed to create video controller for $templateId: $e');
      return null;
    }
  }

  void pauseController(String templateId) {
    _activeControllers[templateId]?.pause();
  }

  void playController(String templateId) {
    _activeControllers[templateId]?.play();
  }

  Future<void> disposeController(String templateId) async {
    final controller = _activeControllers.remove(templateId);
    _playOrder.remove(templateId);
    await controller?.dispose();
  }

  Future<void> disposeAll() async {
    for (final controller in _activeControllers.values) {
      await controller.dispose();
    }
    _activeControllers.clear();
    _playOrder.clear();
  }

  /// Clear video and thumbnail cache
  Future<void> clearCache() async {
    try {
      final cacheDir = await _getCacheDir();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        _cacheDir = null;
        _thumbnailCache.clear();
        debugPrint('🗑️ Video and thumbnail cache cleared');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to clear cache: $e');
    }
  }
}

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
  List<dynamic> _capabilitiesList = []; // For AI tools preview

  // UI state
  bool _isLoading = true;
  String? _loadError;
  int _selectedCategoryIndex = 0; // 0 = "All", 1+ = specific categories
  bool _proToolsExpanded = false; // Pro Tools section collapse state
  int _visibleTemplateCount = 16; // For lazy loading templates
  ExploreOutcomeChip _outcomeChip = ExploreOutcomeChip.all;
  List<String> _favoriteIds = [];
  List<UserTemplateRecord> _userShortcuts = [];
  static const int _templateBatchSize = 12; // Load more increment

  // Controllers
  late ScrollController _scrollController;
  late ScrollController _tabScrollController; // For horizontal tab scrolling
  late AnimationController _headerAnimController;
  late AnimationController _cardRevealController;
  late AnimationController _glowController;
  late AnimationController _heroSlideshowController;
  late Animation<double> _headerSlide;
  late Animation<double> _headerFade;

  // Hero slideshow state
  int _heroSlideIndex = 0;
  List<String> _heroSlideUrls = [];
  List<String> _heroSlideTemplateIds =
      []; // Track which template each slide belongs to

  // Job submission state
  bool _isSubmittingJob = false;
  static const String controllerUrl = "https://genedit.mooo.com";

  // Result manager tracking uses shared state from app_state.dart

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

    // Scroll controllers
    _scrollController = ScrollController();
    _tabScrollController = ScrollController();

    // Header animation
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _headerSlide = Tween<double>(begin: -30, end: 0).animate(
      CurvedAnimation(
          parent: _headerAnimController, curve: Curves.easeOutCubic),
    );
    _headerFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeOut),
    );

    // Card reveal animation
    _cardRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Glow animation for result manager button
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    // Hero slideshow animation
    _heroSlideshowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _startHeroSlideshow();

    // Listen to shared seen jobs changes
    seenJobIdsNotifier.addListener(_onStateChanged);
    jobListNotifier.addListener(_onStateChanged);
    SaleService().state.addListener(_onStateChanged);
    _loadConfig();
    _loadExploreFavoritesAndShortcuts();
  }

  Future<void> _loadExploreFavoritesAndShortcuts() async {
    final favs = await loadExploreFavoriteTemplateIds();
    final shortcuts = await loadUserTemplateRecords();
    if (!mounted) return;
    setState(() {
      _favoriteIds = favoriteIdsInCatalog(
        storedIds: favs,
        knownIds: _templates.keys.map((e) => e.toString()).toSet(),
      );
      _userShortcuts = shortcuts;
    });
  }

  Future<void> _toggleFavorite(String id) async {
    HapticFeedback.lightImpact();
    setState(() {
      if (_favoriteIds.contains(id)) {
        _favoriteIds.remove(id);
      } else {
        _favoriteIds.add(id);
      }
    });
    await saveExploreFavoriteTemplateIds(_favoriteIds);
  }

  Timer? _heroSlideshowTimer;

  void _startHeroSlideshow() {
    _heroSlideshowTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_heroSlideUrls.isNotEmpty && mounted) {
        setState(() {
          _heroSlideIndex = (_heroSlideIndex + 1) % _heroSlideUrls.length;
        });
        _heroSlideshowController.forward(from: 0);
      }
    });
  }

  void _initHeroSlideUrls() {
    // Pick random preview images from templates for slideshow
    final urls = <String>[];
    final templateIds = <String>[];
    final allTemplateIds = _getAllTemplateIds();
    allTemplateIds.shuffle();

    for (final id in allTemplateIds.take(5)) {
      final template = _templates[id] as Map<String, dynamic>?;
      if (template != null) {
        final previewUrl = template['preview_url'] as String?;
        final previewType = template['preview_type'] as String?;
        // Only use images for slideshow, not videos
        if (previewUrl != null && previewType != 'video') {
          urls.add(previewUrl);
          templateIds.add(id);
        }
      }
    }

    // Fallback if no preview URLs found
    if (urls.isEmpty) {
      urls.addAll([
        'https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/explore/glow_up.jpg',
        'https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/explore/headshot.jpg',
        'https://pub-67f874d172874988b5754734cc4fcb7e.r2.dev/explore/anime.jpg',
      ]);
      // Use first available templates as fallback
      final fallbackIds = _getAllTemplateIds().take(3).toList();
      templateIds.addAll(fallbackIds.isNotEmpty
          ? fallbackIds
          : ['glow_up_photo', 'ai_headshot', 'anime_portrait']);
    }

    _heroSlideUrls = urls;
    _heroSlideTemplateIds = templateIds;
  }

  void _onHeroTryNowTap() {
    if (_heroSlideTemplateIds.isEmpty) return;

    // Get the current template based on slide index
    final currentIndex = _heroSlideIndex % _heroSlideTemplateIds.length;
    final templateId = _heroSlideTemplateIds[currentIndex];
    final template = _templates[templateId] as Map<String, dynamic>?;

    if (template != null) {
      HapticFeedback.mediumImpact();
      _showTemplateConfigSheet(template);
    }
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _tabScrollController.dispose();
    _headerAnimController.dispose();
    _cardRevealController.dispose();
    _glowController.dispose();
    _heroSlideshowController.dispose();
    _heroSlideshowTimer?.cancel();
    seenJobIdsNotifier.removeListener(_onStateChanged);
    jobListNotifier.removeListener(_onStateChanged);
    SaleService().state.removeListener(_onStateChanged);
    // Dispose all video preview controllers
    _VideoPreviewManager.instance.disposeAll();
    super.dispose();
  }

  void _selectCategory(int index) {
    if (index < 0 || index > _categories.length)
      return; // 0 = All, 1+ = categories

    HapticFeedback.lightImpact();
    setState(() {
      _selectedCategoryIndex = index;
      _visibleTemplateCount = 16; // Reset pagination on category change
      _outcomeChip = ExploreOutcomeChip.all;
    });
  }

  void _selectOutcome(ExploreOutcomeChip chip) {
    HapticFeedback.lightImpact();
    setState(() {
      _outcomeChip = chip;
      _selectedCategoryIndex = 0;
      _visibleTemplateCount = 16;
    });
  }

  /// Check if a template's model is enabled
  bool _isTemplateModelEnabled(Map<String, dynamic> template) {
    final capabilityId = template['capability'] as String?;
    if (capabilityId == null)
      return true; // Default to enabled if no capability

    final capability = _capabilities[capabilityId] as Map<String, dynamic>?;
    if (capability == null)
      return true; // Default to enabled if capability not found

    final templateModelId = template['model'] as String? ??
        template['preferred_model'] as String? ??
        capability['defaultModel'] as String?;
    if (templateModelId == null)
      return true; // Default to enabled if no model specified

    final allModels = capability['models'] as List<dynamic>? ?? [];
    final model = allModels.firstWhere(
      (m) => m['id'] == templateModelId,
      orElse: () => null,
    );

    if (model == null) return true; // Default to enabled if model not found

    final enabled = model['enabled'];
    return enabled == null ||
        enabled == true; // Default to enabled if not specified
  }

  /// All template id strings from a category's root `templates` and each `subcategories[].templates`.
  List<String> _rawTemplateIdsFromCategoryMap(Map<String, dynamic> cat) {
    final out = <String>[];
    for (final id in (cat['templates'] as List<dynamic>?) ?? []) {
      if (id is String) out.add(id);
    }
    for (final sub in (cat['subcategories'] as List<dynamic>?) ?? []) {
      if (sub is! Map) continue;
      for (final id in (sub['templates'] as List<dynamic>?) ?? []) {
        if (id is String) out.add(id);
      }
    }
    return out;
  }

  /// Get all templates for "All" tab (filtered by enabled models)
  List<String> _getAllTemplateIds() {
    final allIds = <String>{};
    for (final cat in _categories) {
      final c = cat as Map<String, dynamic>;
      for (final templateId in _rawTemplateIdsFromCategoryMap(c)) {
        final template = _templates[templateId] as Map<String, dynamic>?;
        if (template != null && _isTemplateModelEnabled(template)) {
          allIds.add(templateId);
        }
      }
    }
    return allIds.toList();
  }

  /// Get templates for selected category (filtered by enabled models)
  List<String> _getSelectedTemplateIds() {
    List<String> ids;
    if (_selectedCategoryIndex == 0) {
      ids = _getAllTemplateIds();
    } else {
      final categoryIndex = _selectedCategoryIndex - 1;
      if (categoryIndex >= 0 && categoryIndex < _categories.length) {
        final cat = _categories[categoryIndex] as Map<String, dynamic>;
        ids = _rawTemplateIdsFromCategoryMap(cat).where((templateId) {
          final template = _templates[templateId] as Map<String, dynamic>?;
          return template != null && _isTemplateModelEnabled(template);
        }).toList();
      } else {
        ids = [];
      }
    }
    return _applyOutcomeFilter(ids);
  }

  List<String> _applyOutcomeFilter(List<String> ids) {
    const restoreIds = {
      'photo_restore',
      'face_restore',
      'portrait_enhance',
      'hd_upscale',
    };
    return ids.where((id) {
      final template = _templates[id] as Map<String, dynamic>?;
      if (template == null || !_isTemplateModelEnabled(template)) return false;
      final cap = template['capability'] as String?;
      switch (_outcomeChip) {
        case ExploreOutcomeChip.all:
          return true;
        case ExploreOutcomeChip.edit:
          return cap == 'edit_image';
        case ExploreOutcomeChip.createImage:
          return cap == 'create_image';
        case ExploreOutcomeChip.createVideo:
          return cap == 'animate_image' || cap == 'create_video';
        case ExploreOutcomeChip.social:
          final hasCreator = _categories.any(
            (c) => c is Map && c['id'] == 'creator',
          );
          if (hasCreator) {
            final creator = _categories.firstWhere(
              (c) => c is Map && c['id'] == 'creator',
            ) as Map<String, dynamic>;
            return _rawTemplateIdsFromCategoryMap(creator).contains(id);
          }
          return id == 'ai_headshot' || id == 'animate_portrait';
        case ExploreOutcomeChip.restore:
          return restoreIds.contains(id);
        case ExploreOutcomeChip.favorites:
          return _favoriteIds.contains(id);
      }
    }).toList();
  }

  List<Map<String, dynamic>> _newThisWeekTemplates() {
    final raw = _exploreConfig?['new_this_week'];
    if (raw is! List) return [];
    final out = <Map<String, dynamic>>[];
    for (final id in raw) {
      final t = _templates[id.toString()];
      if (t is Map && _isTemplateModelEnabled(Map<String, dynamic>.from(t))) {
        out.add(Map<String, dynamic>.from(t));
      }
    }
    return out;
  }

  Future<void> _openShortcut(UserTemplateRecord record) async {
    final resolved = await resolveRecipeLaunch(
      capabilityId: record.capabilityId,
      modelId: record.modelId,
    );
    if (!mounted) return;
    if (resolved == null) {
      await showModelUnavailableDialog(context);
      return;
    }
    await openGenericTool(
      context,
      config: resolved.config,
      initialPrompt: record.prompt,
      initialSettings: {
        'modelId': record.modelId,
        'prompt': record.prompt,
        'aspectRatio': record.settings['aspectRatio'],
        'quality': record.settings['quality'],
        'videoDuration': record.settings['videoDuration'],
        'variations': record.settings['variations'],
        'enhancePrompt': record.settings['enhancePrompt'] == true,
        'cfgScale': record.settings['cfgScale'],
        'loraAdapter': record.settings['loraAdapter'],
        'cineRealMotionMode': record.settings['cineRealMotionMode'],
        'upscaleEnabled': record.settings['enableUpscale'] == true ||
            record.settings['upscaleOutput'] == true,
        'enableUpscale': record.settings['enableUpscale'] == true,
        'upscaleFactor': record.settings['upscaleFactor'],
        'interpolateEnabled': record.settings['enableInterpolate'] == true,
        'interpolateFps': record.settings['interpolateFps'],
        'bulkEditEnabled': record.settings['bulkEditEnabled'] == true,
      },
    );
  }

  Future<void> _openCreateImageTool() async {
    final cap = _capabilities['create_image'];
    if (cap is! Map) return;
    await openGenericTool(
      context,
      config: genericConfigFromCapability(Map<String, dynamic>.from(cap)),
    );
  }

  Widget _exploreTemplateCard(Map<String, dynamic> template, bool isDark) {
    final id = template['id'] as String? ?? '';
    return _TemplateCard(
      template: template,
      capabilities: _capabilities,
      isDark: isDark,
      onTap: () => _showTemplateConfigSheet(template),
      isFavorite: _favoriteIds.contains(id),
      onFavoriteToggle: () => _toggleFavorite(id),
    );
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final lastFetchedDate = prefs.getString(_cacheDateKey)?.substring(0, 10);
      final cachedData = prefs.getString(_cacheKey);
      final cachedHash = prefs.getString(_cacheHashKey);

      // Load cached config immediately for instant UI (non-blocking)
      if (cachedData != null && cachedHash != null) {
        final computedHash = _computeConfigHash(cachedData);
        if (computedHash == cachedHash) {
          debugPrint("📦 Explore: Using verified cached config");
          _parseConfig(cachedData);

          // Check for updates in background only if cache is older than today
          // (avoid unnecessary checks if we just fetched today)
          if (lastFetchedDate != today) {
            _checkForConfigUpdates(prefs, today, cachedHash);
          }
          return;
        }
      }

      // No valid cache - fetch from network with timeout
      try {
        final responses = await Future.wait([
          http.get(Uri.parse(_configUrl)).timeout(const Duration(seconds: 10)),
          http
              .get(Uri.parse(_configHashUrl))
              .timeout(const Duration(seconds: 5))
              .catchError((_) => http.Response('', 404)),
        ]);

        final configResponse = responses[0];
        final hashResponse = responses[1];

        if (configResponse.statusCode == 200) {
          final configBody = configResponse.body;
          final computedHash = _computeConfigHash(configBody);

          if (hashResponse.statusCode == 200) {
            final serverHash = hashResponse.body.trim().toLowerCase();
            if (serverHash.isNotEmpty &&
                computedHash != serverHash &&
                !kDebugMode) {
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

  /// Check for config updates in background (non-blocking)
  Future<void> _checkForConfigUpdates(
      SharedPreferences prefs, String today, String currentHash) async {
    try {
      final hashResponse = await http
          .get(Uri.parse(_configHashUrl))
          .timeout(const Duration(seconds: 5))
          .catchError((_) => http.Response('', 404));

      if (hashResponse.statusCode == 200) {
        final serverHash = hashResponse.body.trim().toLowerCase();
        if (serverHash.isNotEmpty && serverHash != currentHash) {
          // Config updated - fetch new version
          debugPrint("🔄 Explore: Config updated, fetching new version...");
          final configResponse = await http
              .get(Uri.parse(_configUrl))
              .timeout(const Duration(seconds: 10));

          if (configResponse.statusCode == 200) {
            final configBody = configResponse.body;
            final computedHash = _computeConfigHash(configBody);

            await prefs.setString(_cacheKey, configBody);
            await prefs.setString(_cacheDateKey, today);
            await prefs.setString(_cacheHashKey, computedHash);

            if (mounted) {
              _parseConfig(configBody);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Background config update check failed: $e');
      // Silently fail - user already has cached config
    }
  }

  void _parseConfig(String jsonStr) {
    // Parse JSON in isolate for better performance (non-blocking UI)
    compute(_parseConfigInIsolate, jsonStr).then((parsed) {
      if (!mounted) return;

      _exploreConfig = parsed['explore'] as Map<String, dynamic>?;
      _categories = _exploreConfig?['categories'] ?? [];
      _templates = _exploreConfig?['templates'] ?? {};
      _capabilitiesList =
          parsed['capabilities'] ?? []; // Store raw list for AI tools preview
      _capabilities = _buildCapabilitiesMap(_capabilitiesList);

      // Initialize hero slideshow with random templates
      _initHeroSlideUrls();

      setState(() => _isLoading = false);
      _loadExploreFavoritesAndShortcuts();

      // Start animations
      _headerAnimController.forward();
      Future.delayed(const Duration(milliseconds: 200), () {
        _cardRevealController.forward();
      });
    }).catchError((e) {
      debugPrint('❌ Failed to parse config: $e');
      // Fallback: parse synchronously if compute fails
      try {
        final config = jsonDecode(jsonStr) as Map<String, dynamic>;
        _exploreConfig = config['explore'] as Map<String, dynamic>?;
        _categories = _exploreConfig?['categories'] ?? [];
        _templates = _exploreConfig?['templates'] ?? {};
        _capabilitiesList = config['capabilities'] ?? [];
        _capabilities = _buildCapabilitiesMap(_capabilitiesList);
        _initHeroSlideUrls();
        setState(() => _isLoading = false);
        _headerAnimController.forward();
        Future.delayed(const Duration(milliseconds: 200), () {
          _cardRevealController.forward();
        });
      } catch (e2) {
        if (mounted) {
          setState(() {
            _loadError = 'Failed to parse templates';
            _isLoading = false;
          });
        }
      }
    });
  }

  /// Parse config in isolate (static function for compute)
  static Map<String, dynamic> _parseConfigInIsolate(String jsonStr) {
    return jsonDecode(jsonStr) as Map<String, dynamic>;
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

  Future<bool> _handleSystemBack() async {
    final ok = await _confirmExitApp();
    if (ok) {
      // User confirmed exit - actually exit the app
      SystemNavigator.pop();
    }
    return false; // Always prevent default back navigation
  }

  Future<bool> _confirmExitApp() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmExitAppDialog(),
        )) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: _isLoading
              ? _buildLoadingState(cs, isDark)
              : _loadError != null
                  ? _buildErrorState(cs)
                  : _buildContent(cs, isDark),
        ),
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
              child: _ShimmerBox(
                  width: 80, height: 40, isDark: isDark, radius: 12),
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
  // MAIN CONTENT - Tab-based navigation with templates
  // ============================================================================

  Widget _buildContent(ColorScheme cs, bool isDark) {
    return NestedScrollView(
      controller: _scrollController,
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        // Animated Header
        SliverToBoxAdapter(
          child: AnimatedBuilder(
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
        ),

        // AI Tools Preview Section (collapsible)
        if (_capabilitiesList.isNotEmpty)
          SliverToBoxAdapter(
            child: _buildAIToolsPreview(cs, isDark),
          ),

        // Hero slideshow — below Pro Tools (see _buildHeader: sale stays up top)
        SliverToBoxAdapter(
          child: _buildHeroBanner(cs, isDark),
        ),

        SliverToBoxAdapter(
          child: ValueListenableBuilder<List<JobModel>>(
            valueListenable: jobListNotifier,
            builder: (context, jobs, _) {
              return ExplorePersonalSection(
                jobs: jobs,
                shortcuts: _userShortcuts,
                onSeeAll: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ResultManagerPage()),
                  );
                },
                onOpenJob: (job) {
                  openJobForContinue(context, job);
                },
                onOpenShortcut: _openShortcut,
              );
            },
          ),
        ),

        if (_newThisWeekTemplates().isNotEmpty)
          SliverToBoxAdapter(
            child: ExploreNewThisWeek(
              templates: _newThisWeekTemplates(),
              onTap: _showTemplateConfigSheet,
              favoriteIds: _favoriteIds.toSet(),
              onToggleFavorite: _toggleFavorite,
            ),
          ),

        // Sticky Category Tabs
        SliverPersistentHeader(
          pinned: true,
          delegate: _StickyTabBarDelegate(
            child: _buildCategoryTabs(cs, isDark),
            color: cs.surface,
          ),
        ),
      ],
      // Scrollable content based on selected tab
      body: _buildTabContent(cs, isDark),
    );
  }

  Widget _buildTabContent(ColorScheme cs, bool isDark) {
    if (_selectedCategoryIndex > 0) {
      final categoryIndex = _selectedCategoryIndex - 1;
      if (categoryIndex < _categories.length) {
        final category = _categories[categoryIndex] as Map<String, dynamic>;
        final subcategories =
            (category['subcategories'] as List<dynamic>?) ?? [];
        if (subcategories.isNotEmpty) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: _buildInlineSubcategorySections(cs, isDark, category),
          );
        }
      }
    }

    final templateIds = _getSelectedTemplateIds();

    if (templateIds.isEmpty) {
      final isCreateImage = _outcomeChip == ExploreOutcomeChip.createImage;
      final isFavorites = _outcomeChip == ExploreOutcomeChip.favorites;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.inbox,
                size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              isFavorites
                  ? 'Heart a template to keep it here.'
                  : isCreateImage
                      ? 'No templates for this yet'
                      : 'No templates available',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (isCreateImage)
              TextButton(
                onPressed: _openCreateImageTool,
                child: const Text('Open Create Image'),
              ),
            TextButton(
              onPressed: () =>
                  setState(() => _outcomeChip = ExploreOutcomeChip.all),
              child: const Text('Show all'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      child: _buildStaggeredTemplateGrid(cs, isDark, templateIds),
    );
  }

  /// When a category defines [subcategories], show each as a title + horizontal template strip in-place.
  Widget _buildInlineSubcategorySections(
    ColorScheme cs,
    bool isDark,
    Map<String, dynamic> category,
  ) {
    final colorHex = category['color'] as String? ?? '#8B5CF6';
    final accent =
        Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000);
    final subcategories = (category['subcategories'] as List<dynamic>?) ?? [];
    if (subcategories.isEmpty) {
      return const SizedBox.shrink();
    }

    final children = <Widget>[];
    for (final sub in subcategories) {
      if (sub is! Map<String, dynamic>) continue;
      final section = _buildExploreSubcategoryRow(cs, isDark, sub, accent);
      if (section != null) {
        children.add(section);
      }
    }

    if (children.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: Text(
            'No templates available',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  /// One subcategory: label + horizontal [ListView] of large template cards. Returns null if no templates.
  Widget? _buildExploreSubcategoryRow(
    ColorScheme cs,
    bool isDark,
    Map<String, dynamic> subcategory,
    Color accentColor,
  ) {
    final title = subcategory['title'] as String? ?? 'Subcategory';
    final rawIds = (subcategory['templates'] as List<dynamic>?) ?? [];
    final templateIds = rawIds.whereType<String>().where((id) {
      final t = _templates[id] as Map<String, dynamic>?;
      return t != null && _isTemplateModelEnabled(t);
    }).toList();
    if (templateIds.isEmpty) return null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cardW = (w * 0.46).clamp(200.0, 260.0);
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                ),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  itemCount: templateIds.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final template =
                        _templates[templateIds[index]] as Map<String, dynamic>?;
                    if (template == null) return const SizedBox.shrink();
                    return SizedBox(
                      width: cardW,
                      child: _exploreTemplateCard(template, isDark),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Determine template priority (for content-aware sizing)
  /// Returns: 3 = featured, 2 = trending/new, 1 = normal
  int _getTemplatePriority(Map<String, dynamic> template) {
    final badges = (template['badges'] as List<dynamic>?) ?? [];
    final badgeStr = badges.map((b) => b.toString().toLowerCase()).join(' ');

    // Featured templates get highest priority
    if (badgeStr.contains('featured') || badgeStr.contains('⭐')) return 3;
    // Trending/New/Hot get medium priority
    if (badgeStr.contains('trending') ||
        badgeStr.contains('🔥') ||
        badgeStr.contains('new') ||
        badgeStr.contains('hot')) {
      return 2;
    }
    return 1;
  }

  /// Build smart template grid with content-aware sizing and pagination
  Widget _buildStaggeredTemplateGrid(
      ColorScheme cs, bool isDark, List<String> templateIds) {
    final widgets = <Widget>[];

    // Sort templates: Featured first, then Trending/New, then rest
    final sortedIds = List<String>.from(templateIds);
    sortedIds.sort((a, b) {
      final templateA = _templates[a] as Map<String, dynamic>?;
      final templateB = _templates[b] as Map<String, dynamic>?;
      if (templateA == null || templateB == null) return 0;
      return _getTemplatePriority(templateB)
          .compareTo(_getTemplatePriority(templateA));
    });

    // Limit to visible count for lazy loading
    final visibleIds = sortedIds.take(_visibleTemplateCount).toList();
    final hasMore = sortedIds.length > _visibleTemplateCount;
    final totalCount = sortedIds.length;

    // Section 1: Featured templates (full-width, if any)
    final featuredIds = <String>[];
    final regularIds = <String>[];

    for (final id in visibleIds) {
      final template = _templates[id] as Map<String, dynamic>?;
      if (template != null && _getTemplatePriority(template) >= 3) {
        featuredIds.add(id);
      } else {
        regularIds.add(id);
      }
    }

    // Limit featured to max 2 full-width cards
    final displayFeatured = featuredIds.take(2).toList();
    regularIds.insertAll(
        0, featuredIds.skip(2)); // Move excess featured to regular

    // Build featured cards (full-width)
    for (final id in displayFeatured) {
      final template = _templates[id] as Map<String, dynamic>?;
      if (template == null) continue;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: 240,
            child: _exploreTemplateCard(template, isDark),
          ),
        ),
      );
    }

    // Section 2: Regular templates in uniform 2-column grid
    // Group into pairs, with trending/new getting slightly taller cards
    for (int i = 0; i < regularIds.length; i += 2) {
      final id1 = regularIds[i];
      final template1 = _templates[id1] as Map<String, dynamic>?;

      // Check if we have a second template
      final hasSecond = i + 1 < regularIds.length;
      final id2 = hasSecond ? regularIds[i + 1] : null;
      final template2 =
          id2 != null ? _templates[id2] as Map<String, dynamic>? : null;

      // Determine row height based on content priority
      final priority1 = template1 != null ? _getTemplatePriority(template1) : 1;
      final priority2 = template2 != null ? _getTemplatePriority(template2) : 1;
      final maxPriority = priority1 > priority2 ? priority1 : priority2;
      final rowHeight = maxPriority >= 2 ? 230.0 : 210.0;

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            height: rowHeight,
            child: Row(
              children: [
                // First card
                Expanded(
                  child: template1 != null
                      ? _exploreTemplateCard(template1, isDark)
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 12),
                // Second card (or empty space if odd number)
                Expanded(
                  child: template2 != null
                      ? _exploreTemplateCard(template2, isDark)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // "Load More" button if there are more templates
    if (hasMore) {
      final remaining = totalCount - _visibleTemplateCount;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: _buildLoadMoreButton(cs, isDark, remaining),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildLoadMoreButton(ColorScheme cs, bool isDark, int remaining) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() {
          _visibleTemplateCount += _templateBatchSize;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.chevronDown, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Load More ($remaining more)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _capabilityHasEnabledModel(Map<String, dynamic> capability) {
    final models = capability['models'];
    if (models is! List || models.isEmpty) return false;
    for (final model in models) {
      if (model is! Map) continue;
      final enabled = model['enabled'];
      if (enabled == null || enabled == true) return true;
    }
    return false;
  }

  // ============================================================================
  // AI TOOLS PREVIEW SECTION - Collapsible section with all tools
  // ============================================================================

  Widget _buildAIToolsPreview(ColorScheme cs, bool isDark) {
    // Priority tool IDs (most commonly used) - shown first
    const priorityToolIds = [
      'create_image',
      'edit_image',
      'create_video',
      'animate_image',
      'upscale',
      'remove_background',
      'inpaint',
      'expand_scene',
    ];

    // Build ordered tool list with priority tools first
    final allTools = <Map<String, dynamic>>[];
    for (final toolId in priorityToolIds) {
      final tool = _capabilitiesList.firstWhere(
        (cap) => (cap as Map<String, dynamic>)['id'] == toolId,
        orElse: () => null,
      );
      if (tool != null) allTools.add(tool as Map<String, dynamic>);
    }
    // Add remaining tools not in priority list
    for (final cap in _capabilitiesList) {
      final capMap = cap as Map<String, dynamic>;
      if (!allTools.any((t) => t['id'] == capMap['id'])) {
        allTools.add(capMap);
      }
    }

    // Hidden tools (no enabled model) must not keep an empty grid cell.
    allTools.removeWhere((tool) => !_capabilityHasEnabledModel(tool));

    // Show 6 tools when collapsed (2 rows x 3 cols), all when expanded
    const collapsedCount = 6;
    final visibleTools =
        _proToolsExpanded ? allTools : allTools.take(collapsedCount).toList();
    final hasMoreTools = allTools.length > collapsedCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with expand/collapse toggle
          GestureDetector(
            onTap: hasMoreTools
                ? () {
                    HapticFeedback.lightImpact();
                    setState(() => _proToolsExpanded = !_proToolsExpanded);
                  }
                : null,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: KalaColors.cyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    LucideIcons.wand2,
                    size: 12,
                    color: KalaColors.cyan,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Pro Tools',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                if (hasMoreTools)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _proToolsExpanded = !_proToolsExpanded);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _proToolsExpanded ? 'Collapse' : 'More',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 2),
                          AnimatedRotation(
                            turns: _proToolsExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              LucideIcons.chevronDown,
                              size: 14,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // 3-column grid layout
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                // Build rows of 3 items each
                for (int i = 0; i < visibleTools.length; i += 3)
                  Padding(
                    padding: EdgeInsets.only(
                        bottom: i + 3 < visibleTools.length ? 8 : 0),
                    child: Row(
                      children: [
                        for (int j = 0; j < 3; j++)
                          if (i + j < visibleTools.length)
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: j < 2 ? 8 : 0,
                                ),
                                child: _buildGridToolCard(
                                    cs, isDark, visibleTools[i + j]),
                              ),
                            )
                          else
                            Expanded(child: Container()), // Empty placeholder
                      ],
                    ),
                  ),
                // See All button when expanded
                if (_proToolsExpanded) ...[
                  const SizedBox(height: 8),
                  _buildSeeAllToolButton(cs, isDark),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridToolCard(
      ColorScheme cs, bool isDark, Map<String, dynamic> capability) {
    final name = capability['name'] as String? ?? 'Tool';
    final iconName = capability['icon'] as String? ?? 'cpu';
    final accentHex = capability['accent'] as String? ?? '#9333EA';
    final accent =
        Color(int.parse(accentHex.substring(1, 7), radix: 16) + 0xFF000000);

    final allModelsJson = capability['models'] as List<dynamic>? ?? [];
    // Filter to only enabled models
    final enabledModelsJson = allModelsJson.where((m) {
      final enabled = m['enabled'];
      return enabled == null ||
          enabled == true; // Default to enabled if not specified
    }).toList();

    if (enabledModelsJson.isEmpty)
      return const SizedBox.shrink(); // Hide if no enabled models

    final models = enabledModelsJson
        .map((m) => ModelOption.fromJson(m as Map<String, dynamic>))
        .toList();

    final defaultModelId = capability['defaultModel'] as String?;
    final defaultModel = models.isNotEmpty
        ? models.firstWhere((m) => m.id == defaultModelId,
            orElse: () => models.first)
        : null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GenericToolPage(
              config: GenericToolConfig(
                title: name,
                model: defaultModel?.id ?? defaultModelId ?? '',
                inputs: capability['inputs'] ?? [],
                params: defaultModel?.params,
                rootParams: defaultModel?.rootParams,
                elements: capability['elements'] ?? [],
                outputType: capability['outputType'] as String? ?? 'image',
                cost: defaultModel?.cost ?? 10,
                costUpscale: defaultModel?.costUpscale ?? 0,
                offer: (defaultModel?.rawJson['offer'] as num?)?.toInt() ?? 0,
                capabilityId: capability['id'] as String?,
                // Use toJson() to pass ALL model fields (baseCost, offer,
                // maxDuration, enabled, loraAdapters, etc.) through to GenericToolPage.
                models: models.map((m) => m.toJson()).toList(),
                defaultModel: defaultModelId ?? '',
              ),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_resolveIcon(iconName), size: 20, color: accent),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeeAllToolButton(ColorScheme cs, bool isDark) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AiToolsPage()));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.layoutGrid, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'See All Tools',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: cs.primary),
            ),
            const SizedBox(width: 4),
            Icon(LucideIcons.arrowRight, size: 14, color: cs.primary),
          ],
        ),
      ),
    );
  }

  IconData _resolveIcon(String name) {
    switch (name.toLowerCase()) {
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
      case 'video':
        return LucideIcons.video;
      case 'film':
        return LucideIcons.film;
      case 'clapperboard':
        return LucideIcons.clapperboard;
      case 'zap':
        return LucideIcons.zap;
      default:
        return LucideIcons.cpu;
    }
  }

  // ============================================================================
  // HEADER - Premium Design
  // ============================================================================

  Widget _buildHeader(ColorScheme cs, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row: Logo + Credits + Results
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
              Row(
                children: [
                  _buildCreditsChip(cs, isDark),
                  const SizedBox(width: 8),
                  _buildResultsButton(cs, isDark),
                ],
              ),
            ],
          ),
        ),

        // Sale / next-sale — primary focal point above hero carousel
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 2),
          child: SaleBanner(display: SaleBannerDisplay.highlight),
        ),
      ],
    );
  }

  Widget _buildHeroBanner(ColorScheme cs, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: KalaColors.purple.withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Slideshow background
            if (_heroSlideUrls.isNotEmpty)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                child: Image.network(
                  _heroSlideUrls[_heroSlideIndex % _heroSlideUrls.length],
                  key: ValueKey(_heroSlideIndex),
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            KalaColors.purple.withValues(alpha: 0.5),
                            KalaColors.magenta.withValues(alpha: 0.5),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          KalaColors.purple.withValues(alpha: 0.5),
                          KalaColors.magenta.withValues(alpha: 0.5),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      KalaColors.purple.withValues(alpha: 0.6),
                      KalaColors.magenta.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),

            // Dark overlay for text readability
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.0, 1.0],
                ),
              ),
            ),

            // Content overlay
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Main headline
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Colors.white, KalaColors.cyan],
                    ).createShader(bounds),
                    child: const Text(
                      'What will you create?',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Row with subtitle and Try Now button
                  Row(
                    children: [
                      // Subtitle pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.sparkles,
                              size: 12,
                              color: KalaColors.cyan,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'Featured template',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Try Now button
                      GestureDetector(
                        onTap: _onHeroTryNowTap,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [KalaColors.purple, KalaColors.magenta],
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: KalaColors.purple.withValues(alpha: 0.5),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Try Now',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(
                                LucideIcons.arrowRight,
                                size: 16,
                                color: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Slide indicators
            if (_heroSlideUrls.length > 1)
              Positioned(
                bottom: 12,
                right: 16,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_heroSlideUrls.length, (index) {
                    final isActive =
                        index == (_heroSlideIndex % _heroSlideUrls.length);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(left: 4),
                      width: isActive ? 16 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsButton(ColorScheme cs, bool isDark) {
    return ValueListenableBuilder<List<JobModel>>(
      valueListenable: jobListNotifier,
      builder: (_, jobs, __) {
        final unseenCount = getUnseenCompletedJobCount();
        final hasUnseen = hasUnseenCompletedJobs();

        return AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            final glowIntensity =
                hasUnseen ? 0.3 + (_glowController.value * 0.2) : 0.0;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Glow effect container
                if (hasUnseen)
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: glowIntensity),
                          blurRadius: 12 + (_glowController.value * 8),
                          spreadRadius: 2 + (_glowController.value * 2),
                        ),
                        BoxShadow(
                          color: cs.secondary
                              .withValues(alpha: glowIntensity * 0.7),
                          blurRadius: 8 + (_glowController.value * 4),
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                // Main button
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    markAllCompletedJobsAsSeen();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ResultManagerPage()),
                    );
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasUnseen
                          ? cs.primaryContainer.withValues(alpha: 0.3)
                          : Colors.transparent,
                      border: hasUnseen
                          ? Border.all(
                              color: cs.primary.withValues(alpha: 0.4),
                              width: 1.5,
                            )
                          : null,
                    ),
                    child: Icon(
                      LucideIcons.folderCheck,
                      size: 24,
                      color: hasUnseen ? cs.primary : cs.onSurface,
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
                                horizontal: 5, vertical: 2)
                            : const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: cs.error,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: cs.surface,
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: cs.error.withValues(alpha: 0.5),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Center(
                          child: Text(
                            unseenCount > 99 ? '99+' : unseenCount.toString(),
                            style: TextStyle(
                              color: cs.onError,
                              fontSize: unseenCount > 9 ? 9 : 10,
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
    );
  }

  Widget _buildCreditsChip(ColorScheme cs, bool isDark) {
    return ValueListenableBuilder<int>(
      valueListenable: userCreditsNotifier,
      builder: (context, credits, _) {
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            selectedIndexNotifier.value = AppTabs.credits; // Credits/Store page
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.85),
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
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '$credits',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  LucideIcons.plus,
                  color: cs.primary,
                  size: 14,
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
    // One row: All, the action filters, then each topic category.
    final tabItems = <_TabItem>[
      const _TabItem(
        id: 'all',
        title: 'All',
        color: KalaColors.purple,
        categoryIndex: 0,
      ),
      const _TabItem(
        id: 'edit',
        title: 'Edit a photo',
        color: Color(0xFF8B5CF6),
        outcome: ExploreOutcomeChip.edit,
      ),
      const _TabItem(
        id: 'create_image',
        title: 'Create an image',
        color: Color(0xFF6366F1),
        outcome: ExploreOutcomeChip.createImage,
      ),
      const _TabItem(
        id: 'create_video',
        title: 'Create a video',
        color: Color(0xFFF59E0B),
        outcome: ExploreOutcomeChip.createVideo,
      ),
      const _TabItem(
        id: 'restore',
        title: 'Restore',
        color: Color(0xFF10B981),
        outcome: ExploreOutcomeChip.restore,
      ),
      const _TabItem(
        id: 'favorites',
        title: 'Favorites',
        color: Color(0xFFEC4899),
        outcome: ExploreOutcomeChip.favorites,
      ),
      ..._categories.asMap().entries.map((entry) {
        final c = entry.value as Map<String, dynamic>;
        final colorHex = c['color'] as String? ?? '#8B5CF6';
        return _TabItem(
          id: c['id'] as String? ?? '',
          title: c['title'] as String? ?? '',
          color:
              Color(int.parse(colorHex.substring(1), radix: 16) + 0xFF000000),
          categoryIndex: entry.key + 1,
        );
      }),
    ];

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: ListView.separated(
        controller: _tabScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: tabItems.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = tabItems[index];
          final isSelected = tab.outcome != null
              ? _outcomeChip == tab.outcome && _selectedCategoryIndex == 0
              : _selectedCategoryIndex == tab.categoryIndex &&
                  _outcomeChip == ExploreOutcomeChip.all;

          return GestureDetector(
            onTap: () {
              final outcome = tab.outcome;
              if (outcome != null) {
                _selectOutcome(outcome);
                return;
              }
              _selectCategory(tab.categoryIndex);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [
                          tab.color,
                          tab.color.withValues(alpha: 0.8),
                        ],
                      )
                    : null,
                color: isSelected
                    ? null
                    : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: isSelected
                    ? null
                    : Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.3),
                      ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: tab.color.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                tab.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================================================
  // TEMPLATE CONFIG SHEET - Intermediate Screen
  // ============================================================================

  Future<void> _showTemplateConfigSheet(Map<String, dynamic> template) async {
    HapticFeedback.mediumImpact();

    if (template['require_end_frame'] == true) {
      final capId = template['capability'] as String?;
      final cap = capId == null
          ? null
          : _capabilities[capId] as Map<String, dynamic>?;
      if (cap != null) {
        await openTemplateInTool(context, template: template, capability: cap);
        return;
      }
    }

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
    // Media is now selected in the config sheet, submit directly
    if (result.selectedImages != null && result.selectedImages!.isNotEmpty) {
      final images = result.selectedImages!;
      final paths = result.selectedImagePaths ?? const <String>[];
      if (images.length > 1) {
        final batchId = 'batch_${DateTime.now().microsecondsSinceEpoch}';
        var started = 0;
        for (var i = 0; i < images.length; i++) {
          final ok = await _submitJob(
            template,
            imageBytes: images[i],
            imagePath: i < paths.length ? paths[i] : null,
            customPrompt: result.customPrompt,
            selectedModelId: result.selectedModelId,
            scaleFactor: result.scaleFactor,
            enableInterpolate: result.enableInterpolate,
            interpolateFps: result.interpolateFps,
            enableVideoEnhanceUpscale: result.enableUpscale,
            videoEnhanceUpscaleFactor: result.upscaleFactor,
            batchId: batchId,
            openResults: false,
          );
          if (ok) started++;
        }
        if (!mounted) return;
        if (started < images.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$started of ${images.length} started. The rest were not charged.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (started > 0) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ResultManagerPage()),
          );
        }
        return;
      }
      await _submitJob(
        template,
        imageBytes: images.first,
        imagePath: paths.isNotEmpty ? paths.first : null,
        customPrompt: result.customPrompt,
        selectedModelId: result.selectedModelId,
        scaleFactor: result.scaleFactor,
        enableInterpolate: result.enableInterpolate,
        interpolateFps: result.interpolateFps,
        enableVideoEnhanceUpscale: result.enableUpscale,
        videoEnhanceUpscaleFactor: result.upscaleFactor,
      );
    } else if (result.selectedVideo != null) {
      await _submitJob(
        template,
        videoBytes: result.selectedVideo,
        videoPath: result.selectedVideoPath,
        customPrompt: result.customPrompt,
        selectedModelId: result.selectedModelId,
        scaleFactor: result.scaleFactor,
        enableInterpolate: result.enableInterpolate,
        interpolateFps: result.interpolateFps,
        enableVideoEnhanceUpscale: result.enableUpscale,
        videoEnhanceUpscaleFactor: result.upscaleFactor,
      );
    } else {
      // Text-only or prompt-based
      await _submitJob(
        template,
        customPrompt: result.customPrompt,
        selectedModelId: result.selectedModelId,
        scaleFactor: result.scaleFactor,
        enableInterpolate: result.enableInterpolate,
        interpolateFps: result.interpolateFps,
        enableVideoEnhanceUpscale: result.enableUpscale,
        videoEnhanceUpscaleFactor: result.upscaleFactor,
      );
    }
  }

  // ============================================================================
  // JOB SUBMISSION
  // ============================================================================

  Future<bool> _submitJob(
    Map<String, dynamic> template, {
    Uint8List? imageBytes,
    Uint8List? videoBytes,
    String? imagePath,
    String? videoPath,
    String? customPrompt,
    String? selectedModelId,
    int scaleFactor = 2,
    List<Uint8List>? allImageBytes, // For multi-image models
    bool enableInterpolate = false,
    int interpolateFps = 2,
    bool enableVideoEnhanceUpscale = false,
    int videoEnhanceUpscaleFactor = 2,
    String? parentJobId,
    String? batchId,
    bool openResults = true,
  }) async {
    if (_isSubmittingJob) return false;
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
          return false;
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
      if (capability == null)
        throw Exception('Capability not found: $capabilityId');

      // Get model config
      final modelId = selectedModelId ??
          template['model'] as String? ??
          capability['defaultModel'];
      final allModels = capability['models'] as List<dynamic>? ?? [];
      // Filter to only enabled models
      final enabledModels = allModels.where((m) {
        final enabled = m['enabled'];
        return enabled == null ||
            enabled == true; // Default to enabled if not specified
      }).toList();

      // Check if the template's model is enabled
      final templateModelId =
          template['model'] as String? ?? capability['defaultModel'];
      final isTemplateModelEnabled =
          enabledModels.any((m) => m['id'] == templateModelId);
      if (!isTemplateModelEnabled && templateModelId != null) {
        throw Exception('Template model is disabled');
      }

      if (enabledModels.isEmpty) throw Exception('No enabled models available');

      final modelConfig = enabledModels.firstWhere(
        (m) => m['id'] == modelId,
        orElse: () => enabledModels.isNotEmpty
            ? enabledModels.first
            : <String, dynamic>{},
      ) as Map<String, dynamic>;

      final outputType = template['output_type'] as String? ??
          capability['outputType'] as String? ??
          'image';
      final imageHdUpscaleCharges = upscaleEnabled && outputType != 'video';

      // Calculate cost (VIP gets free upscale; HD upscale surcharge applies to image jobs only)
      final baseCost = modelConfig['cost'] as int? ?? 10;
      final modelOffer = modelConfig['offer'] as int? ?? 0;
      final sale = SaleService().state.value;
      final offer = (sale.isActive && sale.discountPercent > 0)
          ? sale.discountPercent
          : modelOffer;
      final effectiveBaseCost =
          offer > 0 ? (baseCost * (1 - offer / 100)).round() : baseCost;
      final upscaleCost =
          isUpscaleFree() ? 0 : (modelConfig['costUpscale'] as int? ?? 5);
      final videoEnhancementCharges = outputType == 'video' &&
              (enableInterpolate || enableVideoEnhanceUpscale)
          ? upscaleCost
          : 0;
      final totalCost = effectiveBaseCost +
          (imageHdUpscaleCharges ? upscaleCost : 0) +
          videoEnhancementCharges;
      final currentCredits = userCreditsNotifier.value;

      if (!UserService().hasEnoughCredits(totalCost)) {
        dismissDialog();
        await _showInsufficientCreditsSheet(totalCost, currentCredits);
        setState(() => _isSubmittingJob = false);
        return false;
      }

      final jobConfig = template['job_config'] as Map<String, dynamic>? ?? {};
      final prompt = customPrompt ?? jobConfig['prompt'] as String? ?? '';

      final prepBundle = await _runExploreHeavyTierGateWithParallelPrep(
        context,
        () => _buildExploreSubmitPrepBeforeUpload(
          jobConfig: jobConfig,
          modelConfig: modelConfig,
          modelId: modelId.toString(),
          outputType: outputType,
          upscaleEnabled: upscaleEnabled,
          scaleFactor: scaleFactor,
          enableInterpolate: enableInterpolate,
          interpolateFps: interpolateFps,
          enableVideoEnhanceUpscale: enableVideoEnhanceUpscale,
          videoEnhanceUpscaleFactor: videoEnhanceUpscaleFactor,
          prompt: prompt,
          loraAdapter: null,
        ),
      );
      if (prepBundle == null) {
        dismissDialog();
        setState(() => _isSubmittingJob = false);
        return false;
      }

      final modelParams = prepBundle.modelParams;
      final payload = prepBundle.payload;
      final firebaseToken = prepBundle.firebaseToken;

      dialogMessage.value = 'Submitting job...';
      debugPrint('🚀 Explore submit: model=$modelId, capability=$capabilityId');

      dialogMessage.value =
          'Uploading media…\nPlease be patient if your internet connection is slow.';

      final List<Uint8List>? rawImages =
          allImageBytes != null && allImageBytes.length > 1
              ? allImageBytes
              : (imageBytes != null ? [imageBytes] : null);

      await applyExploreMediaR2Upload(
        images: rawImages,
        videoBytes: videoBytes,
        modelParams: modelParams,
        payload: payload,
        authToken: firebaseToken,
      );
      stripForbiddenMediaFromParams(modelParams);

      dialogMessage.value = 'Submitting job...';

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
      final aspect = modelParams['aspect_ratio'] ?? modelParams['aspectRatio'];
      final saved = await saveExploreContinueMedia(
        prompt: prompt,
        modelId: modelId,
        upscaleEnabled: upscaleEnabled,
        scaleFactor: scaleFactor,
        interpolateEnabled: enableInterpolate,
        interpolateFps: interpolateFps,
        enableUpscale: enableVideoEnhanceUpscale,
        upscaleFactor: videoEnhanceUpscaleFactor,
        aspectRatio: aspect is String ? aspect : null,
        images: rawImages,
        imagePaths: imagePath == null ? const [] : [imagePath],
        videoPath: videoPath,
      );
      final newJob = JobModel(
        jobId: jobId,
        title: title,
        model: modelId ?? 'unknown',
        outputType: outputType,
        downloadUrl: downloadUrl,
        status: 'processing',
        inputImagePath: saved.primaryPath ?? imagePath ?? videoPath,
        variations: 1,
        allCompleted: false,
        originalPrompt: prompt.isNotEmpty ? prompt : null,
        templateId: template['id'] as String?,
        templateTitle: template['title'] as String?,
        capabilityId: capabilityId,
        settingsSnapshot: saved.snapshot,
        creditsCharged: totalCost,
        parentJobId: parentJobId,
        batchId: batchId,
      );

      await addOrUpdateJob(newJob);

      final prefs = await SharedPreferences.getInstance();
      final jobContext = {
        'title': template['title'],
        'model': modelId,
        'outputType': outputType,
      };
      await prefs.setString('notify_job_$jobId', jsonEncode(jobContext));

      await UserService().refreshCredits();

      dismissDialog();
      setState(() => _isSubmittingJob = false);

      if (mounted && openResults) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ResultManagerPage()),
        );
      }
      return true;
    } catch (e) {
      debugPrint('❌ Job submission failed: $e');
      dismissDialog();
      setState(() => _isSubmittingJob = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return false;
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
                      style:
                          TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
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
                          style: TextStyle(
                              fontWeight: FontWeight.w700, color: cs.primary),
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
                        selectedIndexNotifier.value = AppTabs.credits;
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
  final List<Uint8List>? selectedImages; // Support multiple images
  final List<String>? selectedImagePaths;
  final Uint8List? selectedVideo;
  final String? selectedVideoPath;
  final bool readyToSubmit; // If true, submit job; if false, pick media
  // Video upscale settings
  final bool enableInterpolate;
  final int interpolateFps;
  final bool enableUpscale;
  final int upscaleFactor;
  // LoRA adapter (for qwen_image_edit_2511_rapid_aio)
  final String loraAdapter;

  _TemplateConfigResult({
    this.selectedModelId,
    this.scaleFactor = 2,
    this.customPrompt,
    this.selectedImages,
    this.selectedImagePaths,
    this.selectedVideo,
    this.selectedVideoPath,
    this.readyToSubmit = false,
    this.enableInterpolate = false,
    this.interpolateFps = 2,
    this.enableUpscale = false,
    this.upscaleFactor = 2,
    this.loraAdapter = 'None',
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
  // ── Friendly display names for LoRA adapters ──
  static const Map<String, String> _loraFriendlyNames = {
    'None': 'None',
    'Consistance': 'Consistency',
    'Semirealistic-photo-detailer': 'Photo Detailer',
    'AnyPose': 'Pose Transfer',
    'Any2Real_2601': 'Any to Realistic',
    'Hyperrealistic-Portrait': 'Hyper Portrait',
    'Ultrarealistic-Portrait': 'Ultra Portrait',
    'BFS-Best-FaceSwap': 'Face Swap',
    'BFS-Best-FaceSwap-merge': 'Face Swap Blend',
    'F2P': 'Face to Photo',
    'Multiple-Angles': 'Multi-Angle View',
    'Light-Restoration': 'Light Restore',
    'Relight': 'Relight',
    'Multi-Angle-Lighting': 'Multi-Angle Light',
    'Edit-Skin': 'Skin Editor',
    'Next-Scene': 'Next Scene',
    'Flat-Log': 'Flat / Log',
    'Upscale-Image': 'Upscale Image',
    'Upscale2K': 'Upscale 2K',
  };

  static const Map<String, String> _loraDescriptions = {
    'None': 'Standard edit — no special mode',
    'Consistance': 'Keep character identity consistent',
    'Semirealistic-photo-detailer': 'Enhance photo with fine details',
    'AnyPose': 'Change pose while keeping identity',
    'Any2Real_2601': 'Convert any style to realistic photo',
    'Hyperrealistic-Portrait': 'Hyper-detailed portrait output',
    'Ultrarealistic-Portrait': 'Ultra-realistic portrait style',
    'BFS-Best-FaceSwap': 'Swap faces between images',
    'BFS-Best-FaceSwap-merge': 'Blend swapped face seamlessly',
    'F2P': 'Generate full photo from a face',
    'Multiple-Angles': 'Generate multiple angle views',
    'Light-Restoration': 'Restore and fix lighting',
    'Relight': 'Re-light the scene creatively',
    'Multi-Angle-Lighting': 'Adjust lighting from multiple angles',
    'Edit-Skin': 'Enhance and retouch skin texture',
    'Next-Scene': 'Generate a continuation scene',
    'Flat-Log': 'Apply flat / log color grading',
    'Upscale-Image': 'Increase image resolution',
    'Upscale2K': 'Upscale to 2K resolution',
  };

  late String? _selectedModelId;
  late int _scaleFactor;
  late bool _upscaleEnabled;
  final TextEditingController _promptController = TextEditingController();
  // Video enhancement (combined UI → fixed 2× FPS + 2× upscale in submit params)
  bool _videoEnhancementOn = false;
  // LoRA adapter (for qwen_image_edit_2511_rapid_aio)
  String _loraAdapter = 'None';

  // Selected media state
  List<Uint8List> _selectedImages = [];
  List<String> _selectedImagePaths = [];
  Uint8List? _selectedVideo;
  String? _selectedVideoPath;
  bool _severalPhotos = false;

  // Preview video player
  VideoPlayerController? _previewVideoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    _selectedModelId = widget.template['model'] as String?;
    final jobConfig =
        widget.template['job_config'] as Map<String, dynamic>? ?? {};
    final outputType = widget.template['output_type'] as String? ?? 'image';
    if (outputType == 'video') {
      _scaleFactor = jobConfig['scale_factor'] as int? ?? 1;
      _upscaleEnabled = false;
    } else {
      _scaleFactor = jobConfig['scale_factor'] as int? ?? 2;
      _upscaleEnabled = _scaleFactor > 1;
    }

    // Initialize video player if preview is a video
    _initPreviewVideo();
  }

  Future<void> _initPreviewVideo() async {
    final previewType = widget.template['preview_type'] as String?;
    final previewUrl = widget.template['preview_url'] as String?;

    if (previewType == 'video' && previewUrl != null && previewUrl.isNotEmpty) {
      try {
        _previewVideoController =
            VideoPlayerController.networkUrl(Uri.parse(previewUrl));
        await _previewVideoController!.initialize();
        _previewVideoController!.setLooping(true);
        _previewVideoController!.setVolume(0); // Muted
        _previewVideoController!.play();
        if (mounted) {
          setState(() => _isVideoInitialized = true);
        }
      } catch (e) {
        debugPrint('⚠️ Failed to initialize preview video: $e');
      }
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _previewVideoController?.dispose();
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

  Map<String, dynamic>? get _selectedModel {
    return _models.firstWhere(
      (m) => m['id'] == _selectedModelId,
      orElse: () => _models.isNotEmpty ? _models.first : <String, dynamic>{},
    );
  }

  bool get _freeUpscale => isUpscaleFree();

  int get _baseCost {
    final cost = _selectedModel?['cost'] as int? ?? 10;
    final modelOffer = _selectedModel?['offer'] as int? ?? 0;
    final sale = SaleService().state.value;
    final offer = (sale.isActive && sale.discountPercent > 0)
        ? sale.discountPercent
        : modelOffer;
    if (offer > 0) {
      return (cost * (1 - offer / 100)).round();
    }
    return cost;
  }

  int get _upscaleCost {
    if (_freeUpscale) return 0;
    return _selectedModel?['costUpscale'] as int? ?? 5;
  }

  /// Listed model surcharge from config (before VIP waiver), for labels only.
  int get _modelListedCostUpscale =>
      _selectedModel?['costUpscale'] as int? ?? 5;

  bool get _exploreTemplateIsLtx23SpatialVideo {
    final id = (_selectedModelId ?? '').toLowerCase();
    return id.startsWith('ltx2_3') ||
        id.startsWith('ltx25_int8') ||
        id == 'minimax_h3';
  }

  /// Same rule as [GenericToolPage._enhancementUpscaleCreditsPerVariation]: one
  /// [costUpscale] add-on when interpolation or video upscale is on; VIP pays 0.
  int get _videoEnhancementAddOn {
    if (!_isVideoOutput) return 0;
    if (!_videoEnhancementOn) return 0;
    return _upscaleCost;
  }

  int get _unitCost {
    if (_isVideoOutput) return _baseCost + _videoEnhancementAddOn;
    return _baseCost + (_upscaleEnabled ? _upscaleCost : 0);
  }

  int get _photoCount {
    if (_severalPhotos && _selectedImages.isNotEmpty) {
      return _selectedImages.length;
    }
    return 1;
  }

  int get _totalCost => _unitCost * _photoCount;

  bool get _supportsSeveralPhotos {
    if (_mediaType != 'image' || _isVideoOutput) return false;
    const caps = {'edit_image', 'upscale', 'remove_background'};
    return caps.contains(widget.template['capability']);
  }

  String get _mediaType => widget.template['media_type'] as String? ?? 'image';

  bool get _isVideoOutput =>
      (widget.template['output_type'] as String? ?? 'image') == 'video';

  bool get _isTextOnly => _mediaType == 'none';

  bool get _showPromptInput =>
      widget.template['show_prompt'] == true || _isTextOnly;

  // Get max images allowed for current model
  int get _maxImages {
    if (_severalPhotos && _supportsSeveralPhotos) {
      return isVipUser() ? kBulkPhotosVip : kBulkPhotosNonVip;
    }
    final inputOverrides =
        _selectedModel?['inputOverrides'] as Map<String, dynamic>?;
    if (inputOverrides != null) {
      final imageOverride =
          inputOverrides['init_image'] as Map<String, dynamic>?;
      if (imageOverride != null) {
        return imageOverride['max'] as int? ?? 1;
      }
    }
    return 1;
  }

  bool get _hasMedia {
    if (_mediaType == 'image') return _selectedImages.isNotEmpty;
    if (_mediaType == 'video') return _selectedVideo != null;
    return true; // Text-only doesn't need media
  }

  bool get _canGenerate {
    if (!_hasMedia && !_isTextOnly) return false;
    if (_showPromptInput &&
        _promptController.text.trim().isEmpty &&
        _isTextOnly) return false;
    return userCreditsNotifier.value >= _totalCost;
  }

  Future<void> _pickImages() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();

    if (_maxImages == 1) {
      final source = await _showMediaSourcePicker(isImage: true);
      if (source == null) return;

      final file = await picker.pickImage(source: source, imageQuality: 85);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      setState(() {
        _selectedImages = [bytes];
        _selectedImagePaths = [file.path];
      });
    } else {
      // Multi-image selection
      final files =
          await picker.pickMultiImage(imageQuality: 85, limit: _maxImages);
      if (files.isEmpty) return;

      final images = <Uint8List>[];
      final paths = <String>[];
      for (final file in files.take(_maxImages)) {
        images.add(await file.readAsBytes());
        paths.add(file.path);
      }
      setState(() {
        _selectedImages = images;
        _selectedImagePaths = paths;
      });
    }
  }

  Future<void> _pickVideo() async {
    HapticFeedback.lightImpact();
    final source = await _showMediaSourcePicker(isImage: false);
    if (source == null) return;

    final picker = ImagePicker();
    final file = await picker.pickVideo(source: source);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    setState(() {
      _selectedVideo = bytes;
      _selectedVideoPath = file.path;
    });
  }

  Future<ImageSource?> _showMediaSourcePicker({required bool isImage}) {
    return showMediaSourcePickerBottomSheet(
      context,
      title: isImage ? 'Choose Image Source' : 'Choose Video Source',
      titleIcon: isImage ? LucideIcons.imagePlus : LucideIcons.video,
      gallerySublabel: isImage ? 'Choose from photos' : 'Choose from videos',
      cameraSublabel: isImage ? 'Take a new photo' : 'Record a new video',
      galleryIcon: isImage ? LucideIcons.image : LucideIcons.film,
      cameraIcon: LucideIcons.camera,
    );
  }

  void _removeImage(int index) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedImages.removeAt(index);
      _selectedImagePaths.removeAt(index);
    });
  }

  void _removeVideo() {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedVideo = null;
      _selectedVideoPath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outputType = widget.template['output_type'] as String? ?? 'image';
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Large Preview Card with actual image
                  _buildLargePreviewCard(cs, isDark, outputType),

                  const SizedBox(height: 16),

                  // Media Selection Section (for non-text templates)
                  if (!_isTextOnly) ...[
                    _buildMediaSelectionSection(cs, isDark),
                    const SizedBox(height: 16),
                  ],

                  // HD Upscale (image templates only — not video output)
                  if (!_isVideoOutput) ...[
                    _buildSettingsRow(cs, isDark),
                  ],

                  // Video enhancement (frame interpolation / video upscale — no extra credit line)
                  _buildVideoUpscaleSettings(cs),

                  // LoRA Adapter Selector (only for qwen_image_edit_2511_rapid_aio)
                  if (_selectedModelId == 'qwen_image_edit_2511_rapid_aio') ...[
                    const SizedBox(height: 16),
                    _buildLoraAdapterSelector(cs),
                  ],

                  // Prompt Input (for text-based templates)
                  if (_showPromptInput) ...[
                    const SizedBox(height: 16),
                    _buildPromptInput(cs),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Fixed bottom bar
          _buildBottomBar(cs, isDark, bottomPadding),
        ],
      ),
    );
  }

  Widget _buildLargePreviewCard(
      ColorScheme cs, bool isDark, String outputType) {
    final title = widget.template['title'] as String? ?? 'Template';
    final subtitle = widget.template['subtitle'] as String? ?? '';
    final previewUrl = widget.template['preview_url'] as String?;
    final previewType = widget.template['preview_type'] as String?;
    final templateId = widget.template['id'] as String? ?? '';
    final hash = templateId.hashCode;
    final baseHue = (hash % 360).abs().toDouble();
    final isVideoPreview = previewType == 'video';

    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: HSLColor.fromAHSL(0.3, baseHue, 0.5, 0.4).toColor(),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background video, image, or gradient
            if (isVideoPreview &&
                _isVideoInitialized &&
                _previewVideoController != null)
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _previewVideoController!.value.size.width,
                  height: _previewVideoController!.value.size.height,
                  child: VideoPlayer(_previewVideoController!),
                ),
              )
            else if (previewUrl != null &&
                previewUrl.isNotEmpty &&
                !isVideoPreview)
              Image.network(
                previewUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          HSLColor.fromAHSL(1.0, baseHue, 0.6, 0.4).toColor(),
                          HSLColor.fromAHSL(1.0, (baseHue + 50) % 360, 0.5, 0.3)
                              .toColor(),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => _buildGradientFallback(baseHue),
              )
            else if (isVideoPreview && !_isVideoInitialized)
              // Show loading state for video
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      HSLColor.fromAHSL(1.0, baseHue, 0.6, 0.4).toColor(),
                      HSLColor.fromAHSL(1.0, (baseHue + 50) % 360, 0.5, 0.3)
                          .toColor(),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54),
                      const SizedBox(height: 8),
                      Text(
                        'Loading preview...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              _buildGradientFallback(baseHue),

            // Dark overlay gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                    Colors.black.withValues(alpha: 0.8),
                  ],
                  stops: const [0.3, 0.6, 1.0],
                ),
              ),
            ),

            // Content overlay
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Media flow badges + Video indicator
                  Row(
                    children: [
                      _buildFlowBadge(
                        icon: _getInputIcon(_mediaType),
                        label: _getInputLabel(_mediaType),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          LucideIcons.arrowRight,
                          size: 16,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      _buildFlowBadge(
                        icon: _getOutputIcon(outputType),
                        label: _getOutputLabel(outputType),
                      ),
                      const Spacer(),
                      // Video preview indicator
                      if (isVideoPreview && _isVideoInitialized)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.play,
                                  size: 12, color: Colors.white),
                              SizedBox(width: 4),
                              Text(
                                'Preview',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  // Title & subtitle
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientFallback(double baseHue) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            HSLColor.fromAHSL(1.0, baseHue, 0.6, 0.4).toColor(),
            HSLColor.fromAHSL(1.0, (baseHue + 50) % 360, 0.5, 0.3).toColor(),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  Widget _buildMediaSelectionSection(ColorScheme cs, bool isDark) {
    final isImage = _mediaType == 'image';
    final hasSelection =
        isImage ? _selectedImages.isNotEmpty : _selectedVideo != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasSelection
              ? cs.primary.withValues(alpha: 0.3)
              : cs.outlineVariant.withValues(alpha: 0.2),
          width: hasSelection ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isImage ? LucideIcons.image : LucideIcons.video,
                size: 16,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isImage
                    ? 'Select ${_maxImages > 1 ? "up to $_maxImages images" : "Image"}'
                    : 'Select Video',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              if (!hasSelection)
                GestureDetector(
                  onTap: isImage ? _pickImages : _pickVideo,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.plus, size: 14, color: cs.onPrimary),
                        const SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (hasSelection) ...[
            const SizedBox(height: 12),
            // Show selected media previews
            if (isImage) _buildImagePreviews(cs) else _buildVideoPreview(cs),
          ],
          if (_supportsSeveralPhotos) ...[
            const SizedBox(height: 4),
            SizedBox(
              height: 44,
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _severalPhotos = !_severalPhotos;
                    if (!_severalPhotos && _selectedImages.length > 1) {
                      _selectedImages = [_selectedImages.first];
                      if (_selectedImagePaths.isNotEmpty) {
                        _selectedImagePaths = [_selectedImagePaths.first];
                      }
                    }
                  });
                },
                child: Text(
                  _severalPhotos ? 'Use one photo' : 'Use on several photos',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagePreviews(ColorScheme cs) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length +
            (_selectedImages.length < _maxImages ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          // Add button
          if (index == _selectedImages.length) {
            return GestureDetector(
              onTap: _pickImages,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.plus, size: 24, color: cs.primary),
                    const SizedBox(height: 4),
                    Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          // Image preview
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _selectedImages[index],
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  iconSize: 14,
                  constraints:
                      const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: EdgeInsets.zero,
                  onPressed: () => _removeImage(index),
                  icon: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(LucideIcons.x,
                        size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoPreview(ColorScheme cs) {
    return Stack(
      children: [
        Container(
          height: 80,
          width: 120,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LucideIcons.film, size: 28, color: cs.primary),
                const SizedBox(height: 4),
                Text(
                  'Video Selected',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: _removeVideo,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.x, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlowBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsRow(ColorScheme cs, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Upscale Toggle
          Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _upscaleEnabled = !_upscaleEnabled;
                  _scaleFactor = _upscaleEnabled ? 2 : 1;
                });
              },
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _upscaleEnabled
                          ? KalaColors.cyan.withValues(alpha: 0.2)
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      LucideIcons.maximize2,
                      size: 18,
                      color: _upscaleEnabled
                          ? KalaColors.cyan
                          : cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HD Upscale',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        Text(
                          _freeUpscale
                              ? 'Free (VIP)'
                              : '+$_upscaleCost credits',
                          style: TextStyle(
                            fontSize: 11,
                            color: _freeUpscale
                                ? KalaColors.gold
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _upscaleEnabled,
                    onChanged: (v) {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _upscaleEnabled = v;
                        _scaleFactor = v ? 2 : 1;
                      });
                    },
                    activeThumbColor: KalaColors.cyan,
                  ),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }

  /// Build LoRA Adapter selector (only for qwen_image_edit_2511_rapid_aio)
  Widget _buildLoraAdapterSelector(ColorScheme cs) {
    // Get LoRA adapter options from model config
    final modelData = _selectedModel ?? <String, dynamic>{};
    final loraAdapters = (modelData['loraAdapters'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        ['None'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.sparkles, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Mode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _loraFriendlyNames[_loraAdapter] ?? _loraAdapter,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: loraAdapters.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final option = loraAdapters[index];
                final isSelected = _loraAdapter == option;
                final friendlyName = _loraFriendlyNames[option] ?? option;
                final description = _loraDescriptions[option];

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _loraAdapter = option);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.primary.withValues(alpha: 0.12)
                          : cs.surfaceContainerHigh.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? cs.primary.withValues(alpha: 0.5)
                            : cs.outlineVariant.withValues(alpha: 0.15),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? cs.primary : Colors.transparent,
                            border: Border.all(
                              color: isSelected
                                  ? cs.primary
                                  : cs.outlineVariant.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check,
                                  size: 12, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                friendlyName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected ? cs.primary : cs.onSurface,
                                ),
                              ),
                              if (description != null) ...[
                                const SizedBox(height: 2),
                                Text(
                                  description,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant
                                        .withValues(alpha: 0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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

  Widget _buildVideoUpscaleSettings(ColorScheme cs) {
    final outputType = widget.template['output_type'] as String? ?? 'image';
    if (outputType != 'video') return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Video Enhancement',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
          if (_freeUpscale) ...[
            const SizedBox(height: 4),
            Text(
              'VIP: video enhancement add-on is free.',
              style: TextStyle(
                fontSize: 11,
                color: KalaColors.gold.withValues(alpha: 0.9),
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            Text(
              'Non-VIP: +$_modelListedCostUpscale credits once when enhancement is on.',
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _videoEnhancementOn = !_videoEnhancementOn);
                  },
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _videoEnhancementOn
                              ? KalaColors.cyan.withValues(alpha: 0.2)
                              : cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          LucideIcons.sparkles,
                          size: 18,
                          color: _videoEnhancementOn
                              ? KalaColors.cyan
                              : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enhance output',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                            Text(
                              _exploreTemplateIsLtx23SpatialVideo
                                  ? '2× spatial upscale'
                                  : '2× FPS and 2× resolution',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            Text(
                              _freeUpscale
                                  ? 'Free (VIP)'
                                  : '+$_modelListedCostUpscale credits',
                              style: TextStyle(
                                fontSize: 11,
                                color: _freeUpscale
                                    ? KalaColors.gold
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _videoEnhancementOn,
                        onChanged: (v) {
                          HapticFeedback.lightImpact();
                          setState(() => _videoEnhancementOn = v);
                        },
                        activeThumbColor: KalaColors.cyan,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs, bool isDark, double bottomPadding) {
    final hasEnough = userCreditsNotifier.value >= _totalCost;
    final currentCredits = userCreditsNotifier.value;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding + 12),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_severalPhotos && _photoCount > 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$_photoCount photos × $_unitCost credits = $_totalCost',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          // Cost row
          Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: KalaColors.brandGradient,
                ).createShader(bounds),
                child:
                    const Icon(LucideIcons.gem, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(
                '$_totalCost',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              if (!_isVideoOutput && _upscaleEnabled) ...[
                const SizedBox(width: 8),
                Text(
                  _freeUpscale ? '(+FREE HD)' : '(+$_upscaleCost HD)',
                  style: TextStyle(
                    fontSize: 12,
                    color: _freeUpscale ? KalaColors.gold : cs.onSurfaceVariant,
                    fontWeight:
                        _freeUpscale ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
              if (_isVideoOutput && _videoEnhancementOn) ...[
                const SizedBox(width: 8),
                Text(
                  _freeUpscale
                      ? '(+FREE enhancement)'
                      : '(+$_upscaleCost enhancement)',
                  style: TextStyle(
                    fontSize: 12,
                    color: _freeUpscale ? KalaColors.gold : cs.onSurfaceVariant,
                    fontWeight:
                        _freeUpscale ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                'Balance: $currentCredits',
                style: TextStyle(
                  fontSize: 13,
                  color: hasEnough ? cs.onSurfaceVariant : cs.error,
                  fontWeight: hasEnough ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Generate button (always visible)
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              icon: LucideIcons.sparkles,
              label: (_severalPhotos && _photoCount > 1)
                  ? 'Generate $_photoCount'
                  : 'Generate',
              onPressed: _canGenerate
                  ? () {
                      HapticFeedback.lightImpact();
                      String? prompt;
                      if (_showPromptInput) {
                        prompt = _promptController.text.trim();
                        if (prompt.isEmpty && _isTextOnly) {
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
                          loraAdapter: _loraAdapter,
                          selectedModelId: _selectedModelId,
                          scaleFactor: _scaleFactor,
                          customPrompt: prompt,
                          selectedImages: _selectedImages.isNotEmpty
                              ? _selectedImages
                              : null,
                          selectedImagePaths: _selectedImagePaths.isNotEmpty
                              ? _selectedImagePaths
                              : null,
                          selectedVideo: _selectedVideo,
                          selectedVideoPath: _selectedVideoPath,
                          readyToSubmit: true,
                          enableInterpolate: _videoEnhancementOn &&
                              !_exploreTemplateIsLtx23SpatialVideo,
                          interpolateFps: 2,
                          enableUpscale: _videoEnhancementOn,
                          upscaleFactor: 2,
                        ),
                      );
                    }
                  : hasEnough
                      ? null // Disabled because media not selected
                      : () {
                          Navigator.pop(context);
                          selectedIndexNotifier.value = AppTabs.credits;
                        },
              variant: _canGenerate
                  ? ButtonVariant.primary
                  : ButtonVariant.secondary,
              size: ButtonSize.large,
              expanded: true,
            ),
          ),
        ],
      ),
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
            Icon(LucideIcons.penTool, size: 14, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              'Your Prompt',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _promptController,
          maxLines: 3,
          style: TextStyle(fontSize: 14, color: cs.onSurface),
          onChanged: (_) => setState(() {}), // Rebuild to update _canGenerate
          decoration: InputDecoration(
            hintText: placeholder,
            hintStyle:
                TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.all(14),
          ),
        ),
      ],
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

  String _getInputLabel(String mediaType) {
    switch (mediaType) {
      case 'image':
        return 'Image';
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
}

// =============================================================================
// TEMPLATE CARD - Premium Design with Image/Video Previews
// =============================================================================

class _TemplateCard extends StatefulWidget {
  final Map<String, dynamic> template;
  final Map<String, dynamic> capabilities;
  final bool isDark;
  final VoidCallback onTap;
  final bool isFavorite;
  final VoidCallback? onFavoriteToggle;

  const _TemplateCard({
    required this.template,
    required this.capabilities,
    required this.isDark,
    required this.onTap,
    this.isFavorite = false,
    this.onFavoriteToggle,
  });

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  // Preview state
  bool _isVisible = false;
  bool _isVideoInitialized = false;
  VideoPlayerController? _videoController;
  bool _imageLoaded = false;
  bool _imageError = false;

  String get _templateId => widget.template['id'] as String? ?? '';
  String? get _previewUrl => widget.template['preview_url'] as String?;
  bool get _isVideoPreview => widget.template['preview_type'] == 'video';

  // Auto-generated thumbnail state
  Uint8List? _thumbnailBytes;
  bool _thumbnailLoading = false;

  @override
  bool get wantKeepAlive => true; // Keep card alive while scrolling

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

    // Start observing visibility after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  @override
  void dispose() {
    _pressController.dispose();
    if (_isVideoPreview) {
      _VideoPreviewManager.instance.disposeController(_templateId);
    }
    super.dispose();
  }

  void _checkVisibility() {
    if (!mounted) return;

    // Get render box and check if visible in viewport
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      // Try again next frame
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
      return;
    }

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;

    // Consider visible if any part is on screen with some buffer
    final isOnScreen =
        offset.dy < screenHeight + 100 && offset.dy + size.height > -100;

    if (isOnScreen != _isVisible) {
      _isVisible = isOnScreen;
      if (_isVisible) {
        _onBecameVisible();
      } else {
        _onBecameInvisible();
      }
    }

    // Continue checking visibility (reduced frequency for better performance)
    if (mounted) {
      Future.delayed(const Duration(milliseconds: 500), _checkVisibility);
    }
  }

  void _onBecameVisible() {
    if (_isVideoPreview && _previewUrl != null) {
      // Load thumbnail first (fast), then video
      _loadThumbnail();
      _initVideoPreview();

      // Resume playing if video is already initialized
      if (_isVideoInitialized && _videoController != null) {
        _VideoPreviewManager.instance.playController(_templateId);
      }
    }
  }

  void _onBecameInvisible() {
    if (_isVideoPreview) {
      _VideoPreviewManager.instance.pauseController(_templateId);
    }
  }

  Future<void> _loadThumbnail() async {
    if (_thumbnailBytes != null || _thumbnailLoading || _previewUrl == null)
      return;

    setState(() => _thumbnailLoading = true);

    final bytes =
        await _VideoPreviewManager.instance.getThumbnail(_previewUrl!);

    if (mounted && bytes != null) {
      setState(() {
        _thumbnailBytes = bytes;
        _thumbnailLoading = false;
      });
    } else if (mounted) {
      setState(() => _thumbnailLoading = false);
    }
  }

  Future<void> _initVideoPreview() async {
    if (_isVideoInitialized || _previewUrl == null) return;

    final controller =
        await _VideoPreviewManager.instance.getOrCreateController(
      _templateId,
      _previewUrl!,
    );

    if (controller != null && mounted) {
      setState(() {
        _videoController = controller;
        _isVideoInitialized = true;
      });

      if (_isVisible) {
        controller.play();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final cs = Theme.of(context).colorScheme;
    final title = widget.template['title'] as String? ?? 'Template';
    final subtitle = widget.template['subtitle'] as String? ?? '';
    final badges = (widget.template['badges'] as List<dynamic>?) ?? [];
    final outputType = widget.template['output_type'] as String? ?? 'image';
    final mediaType = widget.template['media_type'] as String? ?? 'image';
    final templateId = widget.template['id'] as String? ?? '';
    final hash = templateId.hashCode;
    final baseHue = (hash % 360).abs().toDouble();

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
                // Background: Video, Image, or Gradient fallback
                _buildPreviewBackground(baseHue),

                // Dark gradient overlay for text readability
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

                // Content overlay
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: Badge + Video indicator
                      Row(
                        children: [
                          if (badges.isNotEmpty)
                            Container(
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
                          const Spacer(),
                          if (widget.onFavoriteToggle != null)
                            IconButton(
                              icon: Icon(
                                widget.isFavorite
                                    ? Icons.favorite
                                    : Icons.favorite_border,
                                color: widget.isFavorite
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white.withValues(alpha: 0.7),
                                size: 22,
                              ),
                              onPressed: widget.onFavoriteToggle,
                            ),
                          // Video playing indicator
                          if (_isVideoPreview &&
                              _isVideoInitialized &&
                              _isVisible)
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                LucideIcons.play,
                                size: 10,
                                color: Colors.white,
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
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
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

  Widget _buildPreviewBackground(double baseHue) {
    // Video preview - show video when loaded
    if (_isVideoPreview && _isVideoInitialized && _videoController != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _videoController!.value.size.width,
          height: _videoController!.value.size.height,
          child: VideoPlayer(_videoController!),
        ),
      );
    }

    // Video loading state - show auto-generated thumbnail with loading indicator
    if (_isVideoPreview && !_isVideoInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          // Show auto-generated thumbnail if available, else gradient
          if (_thumbnailBytes != null)
            Image.memory(
              _thumbnailBytes!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildGradientFallback(baseHue),
            )
          else
            _buildGradientFallback(baseHue),
          // Loading indicator overlay (only when visible and loading)
          if (_isVisible)
            Center(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // Image preview
    if (_previewUrl != null && !_isVideoPreview && !_imageError) {
      return Image.network(
        _previewUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            // Image loaded
            if (!_imageLoaded) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _imageLoaded = true);
              });
            }
            return child;
          }
          // Loading state - show gradient
          return _buildGradientFallback(baseHue);
        },
        errorBuilder: (_, __, ___) {
          // Mark as error to avoid retry
          if (!_imageError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _imageError = true);
            });
          }
          return _buildGradientFallback(baseHue);
        },
      );
    }

    // Fallback gradient
    return _buildGradientFallback(baseHue);
  }

  Widget _buildGradientFallback(double baseHue) {
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
      // Add pattern overlay
      child: CustomPaint(
        painter: _PatternPainter(
          color: Colors.white.withValues(alpha: 0.05),
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

// =============================================================================
// STICKY TAB BAR DELEGATE - For pinned category tabs
// =============================================================================

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final Color color;

  _StickyTabBarDelegate({required this.child, required this.color});

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: color,
      child: child,
    );
  }

  @override
  double get maxExtent => 52;

  @override
  double get minExtent => 52;

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) {
    return child != oldDelegate.child || color != oldDelegate.color;
  }
}

// =============================================================================
// CATEGORY TEMPLATES PAGE - Shows all templates for a category
// =============================================================================

class _CategoryTemplatesPage extends StatefulWidget {
  final Map<String, dynamic> category;
  final Map<String, dynamic> templates;
  final Map<String, dynamic> capabilities;

  const _CategoryTemplatesPage({
    required this.category,
    required this.templates,
    required this.capabilities,
  });

  @override
  State<_CategoryTemplatesPage> createState() => _CategoryTemplatesPageState();
}

class _CategoryTemplatesPageState extends State<_CategoryTemplatesPage> {
  bool _isSubmitting = false;
  static const String controllerUrl = "https://genedit.mooo.com";

  Future<void> _showTemplateConfigSheet(Map<String, dynamic> template) async {
    HapticFeedback.mediumImpact();

    if (template['require_end_frame'] == true) {
      final capId = template['capability'] as String?;
      final cap = capId == null
          ? null
          : widget.capabilities[capId] as Map<String, dynamic>?;
      if (cap != null) {
        await openTemplateInTool(context, template: template, capability: cap);
        return;
      }
    }

    final result = await showModalBottomSheet<_TemplateConfigResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TemplateConfigSheet(
        template: template,
        capabilities: widget.capabilities,
      ),
    );

    if (result != null && result.readyToSubmit) {
      final images = result.selectedImages;
      final paths = result.selectedImagePaths;
      if (images != null && images.length > 1) {
        final batchId = 'batch_${DateTime.now().microsecondsSinceEpoch}';
        var started = 0;
        for (var i = 0; i < images.length; i++) {
          final one = _TemplateConfigResult(
            selectedModelId: result.selectedModelId,
            scaleFactor: result.scaleFactor,
            customPrompt: result.customPrompt,
            selectedImages: [images[i]],
            selectedImagePaths:
                paths != null && i < paths.length ? [paths[i]] : null,
            readyToSubmit: true,
            enableInterpolate: result.enableInterpolate,
            interpolateFps: result.interpolateFps,
            enableUpscale: result.enableUpscale,
            upscaleFactor: result.upscaleFactor,
            loraAdapter: result.loraAdapter,
          );
          final ok = await _processAndSubmit(
            template,
            one,
            batchId: batchId,
            openResults: false,
          );
          if (ok) started++;
        }
        if (!mounted) return;
        if (started < images.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$started of ${images.length} started. The rest were not charged.',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        if (started > 0) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ResultManagerPage()),
          );
        }
      } else {
        await _processAndSubmit(template, result);
      }
    }
  }

  Future<bool> _processAndSubmit(
    Map<String, dynamic> template,
    _TemplateConfigResult result, {
    String? batchId,
    bool openResults = true,
  }) async {
    if (_isSubmitting) return false;
    setState(() => _isSubmitting = true);

    final dialogMessage = ValueNotifier<String>('Preparing...');
    bool dialogDismissed = false;
    final upscaleEnabled = result.scaleFactor > 1;

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
          setState(() => _isSubmitting = false);
          return false;
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

      final capability =
          widget.capabilities[capabilityId] as Map<String, dynamic>?;
      if (capability == null)
        throw Exception('Capability not found: $capabilityId');

      final modelId = result.selectedModelId ??
          template['model'] as String? ??
          capability['defaultModel'];
      final allModels = capability['models'] as List<dynamic>? ?? [];
      // Filter to only enabled models
      final enabledModels = allModels.where((m) {
        final enabled = m['enabled'];
        return enabled == null ||
            enabled == true; // Default to enabled if not specified
      }).toList();

      if (enabledModels.isEmpty) throw Exception('No enabled models available');

      final modelConfig = enabledModels.firstWhere(
        (m) => m['id'] == modelId,
        orElse: () => enabledModels.isNotEmpty
            ? enabledModels.first
            : <String, dynamic>{},
      ) as Map<String, dynamic>;

      final outputType = template['output_type'] as String? ??
          capability['outputType'] as String? ??
          'image';
      final imageHdUpscaleCharges = upscaleEnabled && outputType != 'video';

      final baseCost = modelConfig['cost'] as int? ?? 10;
      final modelOffer = modelConfig['offer'] as int? ?? 0;
      final sale = SaleService().state.value;
      final offer = (sale.isActive && sale.discountPercent > 0)
          ? sale.discountPercent
          : modelOffer;
      final effectiveBaseCost =
          offer > 0 ? (baseCost * (1 - offer / 100)).round() : baseCost;
      final upscaleCost =
          isUpscaleFree() ? 0 : (modelConfig['costUpscale'] as int? ?? 5);
      final videoEnhancementCharges = outputType == 'video' &&
              (result.enableInterpolate || result.enableUpscale)
          ? upscaleCost
          : 0;
      final totalCost = effectiveBaseCost +
          (imageHdUpscaleCharges ? upscaleCost : 0) +
          videoEnhancementCharges;

      if (!UserService().hasEnoughCredits(totalCost)) {
        dismissDialog();
        _showInsufficientCreditsSheet(totalCost, userCreditsNotifier.value);
        setState(() => _isSubmitting = false);
        return false;
      }

      final jobConfig = template['job_config'] as Map<String, dynamic>? ?? {};
      final prompt =
          result.customPrompt ?? jobConfig['prompt'] as String? ?? '';

      final prepBundle = await _runExploreHeavyTierGateWithParallelPrep(
        context,
        () => _buildExploreSubmitPrepBeforeUpload(
          jobConfig: jobConfig,
          modelConfig: modelConfig,
          modelId: modelId.toString(),
          outputType: outputType,
          upscaleEnabled: upscaleEnabled,
          scaleFactor: result.scaleFactor,
          enableInterpolate: result.enableInterpolate,
          interpolateFps: result.interpolateFps,
          enableVideoEnhanceUpscale: result.enableUpscale,
          videoEnhanceUpscaleFactor: result.upscaleFactor,
          prompt: prompt,
          loraAdapter: modelId == 'qwen_image_edit_2511_rapid_aio'
              ? result.loraAdapter
              : null,
        ),
      );
      if (prepBundle == null) {
        dismissDialog();
        setState(() => _isSubmitting = false);
        return false;
      }

      final modelParams = prepBundle.modelParams;
      final payload = prepBundle.payload;
      final firebaseToken = prepBundle.firebaseToken;

      dialogMessage.value = 'Submitting job...';

      dialogMessage.value =
          'Uploading media…\nPlease be patient if your internet connection is slow.';

      await applyExploreMediaR2Upload(
        images: result.selectedImages,
        videoBytes: result.selectedVideo,
        modelParams: modelParams,
        payload: payload,
        authToken: firebaseToken,
      );
      stripForbiddenMediaFromParams(modelParams);

      dialogMessage.value = 'Submitting job...';

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

      final title = await generateFriendlyJobName();
      final aspect = modelParams['aspect_ratio'] ?? modelParams['aspectRatio'];
      final saved = await saveExploreContinueMedia(
        prompt: prompt,
        modelId: modelId,
        upscaleEnabled: upscaleEnabled,
        scaleFactor: result.scaleFactor,
        interpolateEnabled: result.enableInterpolate,
        interpolateFps: result.interpolateFps,
        enableUpscale: result.enableUpscale,
        upscaleFactor: result.upscaleFactor,
        loraAdapter: result.loraAdapter,
        aspectRatio: aspect is String ? aspect : null,
        images: result.selectedImages,
        imagePaths: result.selectedImagePaths,
        videoPath: result.selectedVideoPath,
      );
      final newJob = JobModel(
        jobId: jobId,
        title: title,
        model: modelId ?? 'unknown',
        outputType: outputType,
        downloadUrl: downloadUrl,
        status: 'processing',
        inputImagePath: saved.primaryPath ??
            result.selectedImagePaths?.first ??
            result.selectedVideoPath,
        variations: 1,
        allCompleted: false,
        originalPrompt: prompt.isNotEmpty ? prompt : null,
        templateId: template['id'] as String?,
        templateTitle: template['title'] as String?,
        capabilityId: capabilityId,
        settingsSnapshot: saved.snapshot,
        creditsCharged: totalCost,
        batchId: batchId,
      );

      await addOrUpdateJob(newJob);

      final prefs = await SharedPreferences.getInstance();
      final jobContext = {
        'title': template['title'],
        'model': modelId,
        'outputType': outputType,
      };
      await prefs.setString('notify_job_$jobId', jsonEncode(jobContext));

      await UserService().refreshCredits();

      dismissDialog();
      setState(() => _isSubmitting = false);

      if (mounted && openResults) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ResultManagerPage()),
        );
      }
      return true;
    } catch (e) {
      debugPrint('❌ Job submission failed: $e');
      dismissDialog();
      setState(() => _isSubmitting = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _showInsufficientCreditsSheet(int required, int current) async {
    final cs = Theme.of(context).colorScheme;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
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
                    color: cs.errorContainer.withValues(alpha: 0.3),
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
                Text(
                  'You need $required credits but only have $current.',
                  style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: GradientButton(
                    icon: LucideIcons.gem,
                    label: 'Get Credits',
                    onPressed: () {
                      Navigator.pop(ctx);
                      selectedIndexNotifier.value = AppTabs.credits;
                    },
                    variant: ButtonVariant.primary,
                    size: ButtonSize.large,
                    expanded: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.category['title'] as String? ?? 'Templates';
    final templateIds = (widget.category['templates'] as List<dynamic>?) ?? [];

    // Get color and icon from config (OTA-updateable)
    final colorHex = widget.category['color'] as String? ?? '#8B5CF6';
    final color = _parseHexColor(colorHex);
    final iconName = widget.category['icon'] as String? ?? 'grid';

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _resolveIconName(iconName),
                size: 16,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: SaleBanner(display: SaleBannerDisplay.highlight),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemCount: templateIds.length,
                itemBuilder: (context, index) {
                  final templateId = templateIds[index] as String;
                  final template =
                      widget.templates[templateId] as Map<String, dynamic>?;

                  if (template == null) return const SizedBox.shrink();

                  return _TemplateCard(
                    template: template,
                    capabilities: widget.capabilities,
                    isDark: isDark,
                    onTap: () => _showTemplateConfigSheet(template),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// HELPER CLASSES
// =============================================================================

class _TabItem {
  final String id;
  final String title;
  final Color color;
  final ExploreOutcomeChip? outcome;
  final int categoryIndex;

  const _TabItem({
    required this.id,
    required this.title,
    required this.color,
    this.outcome,
    this.categoryIndex = 0,
  });
}

// =============================================================================
// HELPER FUNCTIONS - Used across multiple classes (OTA-updateable from config)
// =============================================================================

/// Parse hex color string from config (e.g., "#FF6B35" -> Color)
Color _parseHexColor(String hexColor) {
  try {
    final hex = hexColor.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse(hex, radix: 16) + 0xFF000000);
    } else if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
  } catch (_) {}
  return KalaColors.purple; // Default fallback
}

/// Resolve icon name string from config to IconData
/// Supports common Lucide icon names used in categories
IconData _resolveIconName(String iconName) {
  switch (iconName.toLowerCase()) {
    // Category icons
    case 'flame':
    case 'fire':
      return LucideIcons.flame;
    case 'film':
    case 'video':
      return LucideIcons.film;
    case 'image':
    case 'photo':
      return LucideIcons.image;
    case 'sparkles':
    case 'enhance':
    case 'magic':
      return LucideIcons.sparkles;
    case 'palette':
    case 'styles':
    case 'art':
      return LucideIcons.palette;
    case 'smile':
    case 'fun':
    case 'emoji':
      return LucideIcons.smile;
    case 'wand':
    case 'wand2':
      return LucideIcons.wand2;
    case 'star':
      return LucideIcons.star;
    case 'heart':
      return LucideIcons.heart;
    case 'zap':
    case 'lightning':
      return LucideIcons.zap;
    case 'camera':
      return LucideIcons.camera;
    case 'music':
    case 'audio':
      return LucideIcons.music;
    case 'paintbrush':
    case 'brush':
      return LucideIcons.paintbrush;
    case 'crop':
      return LucideIcons.crop;
    case 'layers':
      return LucideIcons.layers;
    case 'eye':
      return LucideIcons.eye;
    case 'sun':
    case 'sunmedium':
      return LucideIcons.sunMedium;
    case 'moon':
      return LucideIcons.moon;
    case 'cloud':
      return LucideIcons.cloud;
    case 'clock':
    case 'time':
      return LucideIcons.clock;
    case 'user':
    case 'person':
      return LucideIcons.user;
    case 'users':
    case 'people':
      return LucideIcons.users;
    case 'crown':
    case 'premium':
      return LucideIcons.crown;
    case 'gift':
      return LucideIcons.gift;
    case 'trophy':
      return LucideIcons.trophy;
    case 'target':
      return LucideIcons.target;
    case 'refresh':
    case 'refreshcw':
      return LucideIcons.refreshCw;
    case 'download':
      return LucideIcons.download;
    case 'upload':
      return LucideIcons.upload;
    case 'share':
      return LucideIcons.share;
    case 'grid':
    default:
      return LucideIcons.grid;
  }
}

// Confirm Exit App Dialog (for base pages)
class _ConfirmExitAppDialog extends StatelessWidget {
  const _ConfirmExitAppDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.logOut,
              size: 40,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Exit App?',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Are you sure you want to exit?',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Exit',
                icon: LucideIcons.logOut,
                onPressed: () => Navigator.pop(context, true),
                variant: ButtonVariant.danger,
                size: ButtonSize.medium,
                expanded: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

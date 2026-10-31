// lib/features/ai_tools/generic_tool_page.dart
// FULL THEME-AWARE REWRITE — logic unchanged, UI fully Material 3 + ColorScheme

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as imglib;
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/api/submit_payload_helpers.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/explore_favorites.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/cached_tool_config.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/tool_launch.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/media_upload_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    hide
        userCreditsNotifier,
        currentUserNotifier,
        isLoadingUserNotifier,
        UserData;
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/safe_video_view.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/media_source_picker_sheet.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/themed_native_ad.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/frame_fit.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/gemini_client.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/mask_layout_preview.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/expand_canvas.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/outpaint_canvas_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/services/on_device_inpaint_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/services/selfie_segmentation_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/result_manager_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/sale_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/utils/rife_interpolation.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/rife_multiplier_control.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/streaming_composer_hint.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// --------------------------------------
///  GENERIC TOOL PAGE (Dynamic Version)
///  - Fully driven by tool_config.json
///  - Dynamically renders all UI elements & modes
///  - Keeps all animations, HMAC submit, job polling, etc.
/// --------------------------------------

class GenericToolConfig {
  final String title;
  final String model;
  final List<dynamic> inputs;
  final Map<String, dynamic>? params;
  final Map<String, dynamic>? rootParams;
  final Map<String, dynamic>? modes;
  final List<dynamic>? elements;
  final String outputType;
  final int cost;
  final int costUpscale;
  final int offer;

  /// Capability id from tool_config (e.g. create_image, create_video).
  final String? capabilityId;
  // New fields for model selection
  final List<Map<String, dynamic>>? models;
  final String? defaultModel;

  const GenericToolConfig({
    required this.title,
    required this.model,
    required this.inputs,
    this.params,
    this.rootParams,
    this.modes,
    this.elements,
    required this.outputType,
    this.cost = 0,
    this.costUpscale = 0,
    this.offer = 0,
    this.capabilityId,
    this.models,
    this.defaultModel,
  });

  /// Check if multiple models are available
  bool get hasMultipleModels => models != null && models!.length > 1;

  // Optional: helpful for serialization (tool_config parsing)
  factory GenericToolConfig.fromJson(Map<String, dynamic> json) {
    return GenericToolConfig(
      title: json["title"] ?? "",
      model: json["model"] ?? "",
      inputs: json["inputs"] ?? [],
      params: (json["params"] ?? {}) as Map<String, dynamic>,
      rootParams: (json["root_params"] ?? {}) as Map<String, dynamic>,
      modes: (json["modes"] ?? {}) as Map<String, dynamic>,
      elements: json["elements"] ?? [],
      outputType: json["outputType"] ?? "image",
      capabilityId: json["capabilityId"] as String?,
      models: json["models"] != null
          ? List<Map<String, dynamic>>.from(json["models"])
          : null,
      defaultModel: json["defaultModel"],
    );
  }
}

/// --------------------------------------
///  PROMPT HELPER CHIPS (Quick-add tags)
///  Now loaded from tool_config.json for OTA updates
/// --------------------------------------

class PromptChip {
  final String id;
  final String label;
  final String snippet;
  final String icon;
  final String? previewUrl;

  const PromptChip({
    this.id = '',
    required this.label,
    required this.snippet,
    required this.icon,
    this.previewUrl,
  });

  factory PromptChip.fromJson(Map<String, dynamic> json) {
    return PromptChip(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      snippet: json['snippet'] ?? '',
      icon: json['icon'] ?? '🏷️',
      previewUrl: json['preview_url'],
    );
  }
}

/// Fallback chips used if config loading fails
const List<PromptChip> promptHelperChips = [
  PromptChip(
      id: 'cinematic',
      label: 'Cinematic',
      snippet: 'cinematic lighting, film grain',
      icon: '🎬'),
  PromptChip(
      id: 'anime',
      label: 'Anime',
      snippet: 'anime style, vibrant colors',
      icon: '🎌'),
  PromptChip(
      id: 'portrait',
      label: 'Portrait',
      snippet: 'portrait photography, sharp focus',
      icon: '👤'),
  PromptChip(
      id: 'soft_light',
      label: 'Soft Light',
      snippet: 'soft diffused lighting, gentle shadows',
      icon: '💡'),
  PromptChip(
      id: 'high_detail',
      label: 'High Detail',
      snippet: '8K, ultra detailed, intricate details',
      icon: '🔍'),
  PromptChip(
      id: 'studio',
      label: 'Studio',
      snippet: 'professional studio lighting, clean background',
      icon: '📸'),
  PromptChip(
      id: 'dramatic',
      label: 'Dramatic',
      snippet: 'dramatic lighting, high contrast',
      icon: '🌟'),
  PromptChip(
      id: 'dreamy',
      label: 'Dreamy',
      snippet: 'dreamy atmosphere, ethereal glow',
      icon: '✨'),
  PromptChip(
      id: 'vintage',
      label: 'Vintage',
      snippet: 'vintage aesthetic, retro film look',
      icon: '📼'),
  PromptChip(
      id: 'neon',
      label: 'Neon',
      snippet: 'neon lights, cyberpunk vibes',
      icon: '🌃'),
  PromptChip(
      id: 'nature',
      label: 'Nature',
      snippet: 'natural lighting, outdoor setting',
      icon: '🌿'),
  PromptChip(
      id: 'minimal',
      label: 'Minimal',
      snippet: 'minimalist, clean composition',
      icon: '⬜'),
];

/// --------------------------------------
///  STYLE PRESETS (Visual Styles)
///  Now loaded from tool_config.json for OTA updates
///  Supports image/video previews with caching
/// --------------------------------------

class StylePreset {
  final String id;
  final String name;
  final String category;
  final String promptSnippet;
  final String icon; // emoji fallback
  final String? previewUrl; // preview image/video URL
  final String? previewType; // 'image' or 'video' (auto-detected from URL)
  final bool isFeatured;

  /// Tool capability ids that may show this preset. Image styles stay on
  /// create/edit image. Video styles stay on create video and animate image.
  final List<String> capabilities;

  static const List<String> imageCapabilities = [
    'create_image',
    'edit_image',
  ];

  const StylePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.promptSnippet,
    required this.icon,
    this.previewUrl,
    this.previewType,
    this.isFeatured = false,
    this.capabilities = imageCapabilities,
  });

  factory StylePreset.fromJson(Map<String, dynamic> json) {
    final url = json['preview_url'] as String?;
    String? pType;
    if (url != null) {
      pType = url.endsWith('.mp4') || url.endsWith('.webm') ? 'video' : 'image';
    }
    final rawCapabilities = json['capabilities'];
    final capabilities = rawCapabilities is List
        ? rawCapabilities
            .map((entry) => entry.toString())
            .where((entry) => entry.isNotEmpty)
            .toList()
        : imageCapabilities;
    return StylePreset(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      category: json['category'] ?? 'Artistic',
      promptSnippet: json['promptSnippet'] ?? '',
      icon: json['icon'] ?? '🎨',
      previewUrl: url,
      previewType: pType,
      isFeatured: json['featured'] ?? false,
      capabilities: capabilities.isEmpty ? imageCapabilities : capabilities,
    );
  }
}

/// Fallback categories used if config loading fails
const List<String> styleCategories = [
  'All',
  'Favorites',
  'Fun',
  'Realistic',
  'Artistic',
  'Anime',
  'Cinematic'
];

/// --------------------------------------
///  USER TEMPLATE (Saved Settings)
///  Stores user's custom templates with prompt and settings
/// --------------------------------------
class UserTemplate {
  final String id;
  final String name;
  final String prompt;
  final String? modelId;
  final String? capabilityId;
  final String? toolTitle;
  final AdvancedSettings settings;
  final DateTime createdAt;
  final DateTime? lastUsed;

  UserTemplate({
    required this.id,
    required this.name,
    required this.prompt,
    this.modelId,
    this.capabilityId,
    this.toolTitle,
    required this.settings,
    required this.createdAt,
    this.lastUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'prompt': prompt,
      'modelId': modelId,
      'capabilityId': capabilityId,
      'toolTitle': toolTitle,
      'settings': {
        'enhancePrompt': settings.enhancePrompt,
        'upscaleOutput': settings.upscaleOutput,
        'quality': settings.quality,
        'aspectRatio': settings.aspectRatio,
        'variations': settings.variations,
        'videoDuration': settings.videoDuration,
        'cfgScale': settings.cfgScale,
        'bulkEditEnabled': settings.bulkEditEnabled,
        'enableInterpolate': settings.enableInterpolate,
        'interpolateFps': settings.interpolateFps,
        'enableUpscale': settings.enableUpscale,
        'upscaleFactor': settings.upscaleFactor,
        'loraAdapter': settings.loraAdapter,
        'cineRealMotionMode': settings.cineRealMotionMode,
      },
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed?.toIso8601String(),
    };
  }

  factory UserTemplate.fromJson(Map<String, dynamic> json) {
    final settingsJson = json['settings'] as Map<String, dynamic>;
    return UserTemplate(
      id: json['id'] as String,
      name: json['name'] as String,
      prompt: json['prompt'] as String,
      modelId: json['modelId'] as String?,
      capabilityId: json['capabilityId'] as String?,
      toolTitle: json['toolTitle'] as String?,
      settings: AdvancedSettings(
        enhancePrompt: settingsJson['enhancePrompt'] as bool? ?? false,
        upscaleOutput: settingsJson['upscaleOutput'] as bool? ?? false,
        quality: settingsJson['quality'] as String? ?? 'High',
        aspectRatio: AdvancedSettings.normalizeAspectRatio(
          settingsJson['aspectRatio'] as String?,
        ),
        variations: settingsJson['variations'] as int? ?? 1,
        videoDuration: settingsJson['videoDuration'] as int? ?? 5,
        cfgScale: settingsJson['cfgScale'] as double? ?? 1.0,
        bulkEditEnabled: settingsJson['bulkEditEnabled'] as bool? ?? false,
        enableInterpolate: settingsJson['enableInterpolate'] as bool? ?? false,
        interpolateFps: migrateLegacyInterpolateStorageValue(
          settingsJson['interpolateFps'] as int?,
        ),
        enableUpscale: settingsJson['enableUpscale'] as bool? ?? false,
        upscaleFactor: settingsJson['upscaleFactor'] as int? ?? 2,
        loraAdapter: settingsJson['loraAdapter'] as String? ?? 'None',
        cineRealMotionMode:
            settingsJson['cineRealMotionMode'] as String? ?? 'i2v',
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsed: json['lastUsed'] != null
          ? DateTime.parse(json['lastUsed'] as String)
          : null,
    );
  }

  UserTemplate copyWith({
    String? name,
    String? prompt,
    String? modelId,
    String? capabilityId,
    String? toolTitle,
    AdvancedSettings? settings,
    DateTime? lastUsed,
  }) {
    return UserTemplate(
      id: id,
      name: name ?? this.name,
      prompt: prompt ?? this.prompt,
      modelId: modelId ?? this.modelId,
      capabilityId: capabilityId ?? this.capabilityId,
      toolTitle: toolTitle ?? this.toolTitle,
      settings: settings ?? this.settings,
      createdAt: createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}

const List<StylePreset> allStylePresets = [
  // Fun
  StylePreset(
    id: 'cartoon_3d',
    name: '3D Cartoon',
    category: 'Fun',
    promptSnippet:
        'Pixar 3D animation style, colorful, rounded shapes, playful lighting',
    icon: '🎪',
    isFeatured: true,
  ),
  StylePreset(
    id: 'comic_book',
    name: 'Comic Book',
    category: 'Fun',
    promptSnippet:
        'comic book style, bold outlines, halftone dots, speech bubbles aesthetic',
    icon: '💥',
  ),
  StylePreset(
    id: 'clay_render',
    name: 'Clay Render',
    category: 'Fun',
    promptSnippet:
        'claymation style, soft clay texture, stop motion aesthetic, handcrafted look',
    icon: '🎨',
  ),
  StylePreset(
    id: 'sticker',
    name: 'Sticker Style',
    category: 'Fun',
    promptSnippet:
        'cute sticker design, white outline, kawaii aesthetic, glossy finish',
    icon: '🏷️',
  ),

  // Realistic
  StylePreset(
    id: 'photo_real',
    name: 'Photorealistic',
    category: 'Realistic',
    promptSnippet:
        'photorealistic, DSLR quality, natural lighting, 8K resolution, sharp details',
    icon: '📷',
    isFeatured: true,
  ),
  StylePreset(
    id: 'product_shot',
    name: 'Product Shot',
    category: 'Realistic',
    promptSnippet:
        'professional product photography, studio lighting, clean white background',
    icon: '🛍️',
  ),
  StylePreset(
    id: 'fashion',
    name: 'Fashion Editorial',
    category: 'Realistic',
    promptSnippet:
        'high fashion editorial, Vogue magazine quality, dramatic pose, designer aesthetic',
    icon: '👗',
  ),
  StylePreset(
    id: 'documentary',
    name: 'Documentary',
    category: 'Realistic',
    promptSnippet:
        'documentary photography style, candid moment, natural light, authentic',
    icon: '🎞️',
  ),

  // Painting
  StylePreset(
    id: 'oil_classic',
    name: 'Oil Painting',
    category: 'Painting',
    promptSnippet:
        'classical oil painting, rich brush strokes, Renaissance masters style, museum quality',
    icon: '🖼️',
    isFeatured: true,
  ),
  StylePreset(
    id: 'watercolor',
    name: 'Watercolor',
    category: 'Painting',
    promptSnippet:
        'watercolor painting, soft color blends, paper texture, artistic drips',
    icon: '🎨',
  ),
  StylePreset(
    id: 'impressionist',
    name: 'Impressionist',
    category: 'Painting',
    promptSnippet:
        'impressionist painting, visible brush strokes, light and color emphasis, Monet style',
    icon: '🌸',
  ),
  StylePreset(
    id: 'digital_art',
    name: 'Digital Art',
    category: 'Painting',
    promptSnippet:
        'professional digital art, trending on ArtStation, concept art quality',
    icon: '💻',
  ),

  // Anime
  StylePreset(
    id: 'anime_modern',
    name: 'Modern Anime',
    category: 'Anime',
    promptSnippet:
        'modern anime style, detailed shading, vibrant colors, high quality animation',
    icon: '🎌',
    isFeatured: true,
  ),
  StylePreset(
    id: 'ghibli',
    name: 'Studio Ghibli',
    category: 'Anime',
    promptSnippet:
        'Studio Ghibli style, Hayao Miyazaki aesthetic, magical realism, detailed backgrounds',
    icon: '🏯',
  ),
  StylePreset(
    id: 'manga',
    name: 'Manga Panel',
    category: 'Anime',
    promptSnippet:
        'manga illustration style, black and white, screentones, dynamic composition',
    icon: '📖',
  ),
  StylePreset(
    id: 'chibi',
    name: 'Chibi',
    category: 'Anime',
    promptSnippet:
        'chibi style, cute proportions, big head small body, kawaii expressions',
    icon: '🥰',
  ),

  // Cinematic
  StylePreset(
    id: 'film_noir',
    name: 'Film Noir',
    category: 'Cinematic',
    promptSnippet:
        'film noir style, black and white, dramatic shadows, 1940s detective aesthetic',
    icon: '🎬',
    isFeatured: true,
  ),
  StylePreset(
    id: 'blockbuster',
    name: 'Blockbuster',
    category: 'Cinematic',
    promptSnippet:
        'Hollywood blockbuster look, epic scale, cinematic color grading, anamorphic lens',
    icon: '🎥',
  ),
  StylePreset(
    id: 'scifi',
    name: 'Sci-Fi Epic',
    category: 'Cinematic',
    promptSnippet:
        'science fiction aesthetic, futuristic technology, epic space opera, blade runner vibes',
    icon: '🚀',
  ),
  StylePreset(
    id: 'horror',
    name: 'Horror',
    category: 'Cinematic',
    promptSnippet:
        'horror movie aesthetic, unsettling atmosphere, dark shadows, eerie lighting',
    icon: '👻',
  ),
];

/// =============================================================================
/// STYLE PREVIEW MANAGER - Caches style/tag preview assets to disk
/// Similar to VideoPreviewManager in explore_ai_page.dart
/// =============================================================================

class StylePreviewManager {
  static final StylePreviewManager _instance = StylePreviewManager._();
  static StylePreviewManager get instance => _instance;
  StylePreviewManager._();

  Directory? _cacheDir;

  // In-memory cache for quick access
  final Map<String, Uint8List> _imageCache = {};
  final Map<String, VideoPlayerController> _videoControllers = {};
  final Map<String, Future<VideoPlayerController?>> _recovering = {};
  final Map<String, Future<Uint8List?>> _pendingDownloads = {};

  static const int maxVideoControllers = 2;
  final List<String> _videoPlayOrder = [];

  /// Get or create cache directory
  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final appDir = await getApplicationCacheDirectory();
    _cacheDir = Directory('${appDir.path}/style_previews');
    if (!await _cacheDir!.exists()) {
      await _cacheDir!.create(recursive: true);
    }
    return _cacheDir!;
  }

  /// Get hash for URL (used for file names)
  String _getUrlHash(String url) {
    return md5.convert(utf8.encode(url)).toString();
  }

  /// Get cached image bytes for a URL (downloads if not cached)
  Future<Uint8List?> getImagePreview(String imageUrl) async {
    final hash = _getUrlHash(imageUrl);

    // Check in-memory cache
    if (_imageCache.containsKey(hash)) {
      return _imageCache[hash];
    }

    // Check for pending download
    if (_pendingDownloads.containsKey(hash)) {
      return _pendingDownloads[hash];
    }

    // Check disk cache
    try {
      final cacheDir = await _getCacheDir();
      final ext = imageUrl.endsWith('.png') ? 'png' : 'jpg';
      final cachedFile = File('${cacheDir.path}/$hash.$ext');

      if (await cachedFile.exists()) {
        final bytes = await cachedFile.readAsBytes();
        _imageCache[hash] = bytes;
        debugPrint('📦 Using cached style preview: $hash.$ext');
        return bytes;
      }
    } catch (e) {
      debugPrint('⚠️ Error reading cached preview: $e');
    }

    // Download and cache
    final future = _downloadImage(imageUrl);
    _pendingDownloads[hash] = future;

    final result = await future;
    _pendingDownloads.remove(hash);
    return result;
  }

  /// Download image and cache to disk
  Future<Uint8List?> _downloadImage(String imageUrl) async {
    final hash = _getUrlHash(imageUrl);

    try {
      debugPrint('⬇️ Downloading style preview: $imageUrl');
      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;

        // Cache to memory
        _imageCache[hash] = bytes;

        // Cache to disk
        try {
          final cacheDir = await _getCacheDir();
          final ext = imageUrl.endsWith('.png') ? 'png' : 'jpg';
          final cachedFile = File('${cacheDir.path}/$hash.$ext');
          await cachedFile.writeAsBytes(bytes);
          debugPrint('✅ Style preview cached: $hash.$ext');
        } catch (e) {
          debugPrint('⚠️ Failed to cache preview to disk: $e');
        }

        return bytes;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to download style preview: $e');
    }
    return null;
  }

  /// Get or create video controller for a style preview
  Future<VideoPlayerController?> getVideoController(
      String styleId, String videoUrl) async {
    // Return existing controller
    if (_videoControllers.containsKey(styleId)) {
      _videoPlayOrder.remove(styleId);
      _videoPlayOrder.add(styleId);
      return recover(styleId);
    }

    // Evict oldest if at max
    while (_videoControllers.length >= maxVideoControllers &&
        _videoPlayOrder.isNotEmpty) {
      final oldestId = _videoPlayOrder.removeAt(0);
      final oldController = _videoControllers.remove(oldestId);
      await oldController?.pause();
      await oldController?.dispose();
    }

    try {
      // Try to use cached video first
      final hash = _getUrlHash(videoUrl);
      final cacheDir = await _getCacheDir();
      final cachedFile = File('${cacheDir.path}/$hash.mp4');

      VideoPlayerController controller;

      if (await cachedFile.exists()) {
        controller = VideoPlayerController.file(cachedFile);
        debugPrint('📦 Using cached style video: $hash.mp4');
      } else {
        // Download and cache video
        try {
          debugPrint('⬇️ Downloading style video: $videoUrl');
          final response = await http.get(Uri.parse(videoUrl));
          if (response.statusCode == 200) {
            await cachedFile.writeAsBytes(response.bodyBytes);
            controller = VideoPlayerController.file(cachedFile);
            debugPrint('✅ Style video cached: $hash.mp4');
          } else {
            controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
          }
        } catch (e) {
          controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        }
      }

      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(0);

      _videoControllers[styleId] = controller;
      _videoPlayOrder.add(styleId);

      return controller;
    } catch (e) {
      debugPrint('⚠️ Failed to create video controller for $styleId: $e');
      return null;
    }
  }

  void pauseVideo(String styleId) {
    pauseVideoController(_videoControllers[styleId]);
  }

  Future<void> pauseAll() async {
    for (final controller in _videoControllers.values) {
      await pauseVideoController(controller);
    }
  }

  /// Reopens a style preview whose frame was dropped while the app was stopped.
  Future<VideoPlayerController?> recover(String styleId, {bool play = false}) {
    final pending = _recovering[styleId];
    if (pending != null) return pending;
    final future = _recover(styleId, play: play);
    _recovering[styleId] = future;
    return future.whenComplete(() => _recovering.remove(styleId));
  }

  Future<VideoPlayerController?> _recover(
    String styleId, {
    required bool play,
  }) async {
    final current = _videoControllers[styleId];
    if (current == null) return null;
    final next = await replaceDeadVideo(current, play: play);
    if (next == null || identical(next, current)) return current;
    if (!identical(_videoControllers[styleId], current)) {
      await next.dispose();
      return _videoControllers[styleId];
    }
    _videoControllers[styleId] = next;
    try {
      await current.dispose();
    } catch (_) {}
    return next;
  }

  void playVideo(String styleId) {
    _videoControllers[styleId]?.play();
  }

  Future<void> disposeVideo(String styleId) async {
    final controller = _videoControllers.remove(styleId);
    _videoPlayOrder.remove(styleId);
    await controller?.dispose();
  }

  Future<void> disposeAll() async {
    for (final controller in _videoControllers.values) {
      await controller.dispose();
    }
    _videoControllers.clear();
    _videoPlayOrder.clear();
    _imageCache.clear();
  }
}

/// --------------------------------------
///  ADVANCED SETTINGS MODEL
/// --------------------------------------

class AdvancedSettings {
  bool enhancePrompt;
  bool upscaleOutput;
  String quality; // 'Low', 'Medium', 'High'
  String
      aspectRatio; // '1:1', '9:16', '16:9', '4:3', '3:4' (legacy `Default` → 1:1)
  int variations; // 1-4 (VIP: max 4, non-VIP: max 2)
  int videoDuration; // Create/animate video: min 5s when model allows; max from model
  double cfgScale; // 0.1 - 15.0
  bool bulkEditEnabled; // Process multiple images with same settings
  // Video upscale settings
  bool enableInterpolate; // Enable frame interpolation (RIFE)
  /// RIFE speed step: 2, 4, or 8 (× source FPS). Same JSON key as before for compatibility.
  int interpolateFps;
  bool enableUpscale; // Enable video upscaling
  int upscaleFactor; // Upscale factor (1-4)
  // LoRA adapter (for qwen_image_edit_2511_rapid_aio)
  String loraAdapter; // LoRA adapter name (e.g., "None", "Consistance", etc.)
  /// CineReal animate (`ltx2_3_cinereal`): `i2v` or `flf2v` (two keyframes).
  String cineRealMotionMode;

  AdvancedSettings({
    this.enhancePrompt = false,
    this.upscaleOutput = false,
    this.quality = 'High',
    this.aspectRatio = '1:1',
    this.variations = 1,
    this.videoDuration = 5,
    this.cfgScale = 1.0,
    this.bulkEditEnabled = false,
    this.enableInterpolate = false,
    this.interpolateFps = 2,
    this.enableUpscale = false,
    this.upscaleFactor = 2,
    this.loraAdapter = 'None',
    this.cineRealMotionMode = 'i2v',
  });

  AdvancedSettings copyWith({
    bool? enhancePrompt,
    bool? upscaleOutput,
    String? quality,
    String? aspectRatio,
    int? variations,
    int? videoDuration,
    double? cfgScale,
    bool? bulkEditEnabled,
    bool? enableInterpolate,
    int? interpolateFps,
    bool? enableUpscale,
    int? upscaleFactor,
    String? loraAdapter,
    String? cineRealMotionMode,
  }) {
    return AdvancedSettings(
      enhancePrompt: enhancePrompt ?? this.enhancePrompt,
      upscaleOutput: upscaleOutput ?? this.upscaleOutput,
      quality: quality ?? this.quality,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      variations: variations ?? this.variations,
      cfgScale: cfgScale ?? this.cfgScale,
      videoDuration: videoDuration ?? this.videoDuration,
      bulkEditEnabled: bulkEditEnabled ?? this.bulkEditEnabled,
      enableInterpolate: enableInterpolate ?? this.enableInterpolate,
      interpolateFps: interpolateFps ?? this.interpolateFps,
      enableUpscale: enableUpscale ?? this.enableUpscale,
      upscaleFactor: upscaleFactor ?? this.upscaleFactor,
      loraAdapter: loraAdapter ?? this.loraAdapter,
      cineRealMotionMode: cineRealMotionMode ?? this.cineRealMotionMode,
    );
  }

  /// Ratios shown in Additional Settings (modal). Order matches segmented control.
  static const List<String> kAdvancedAspectRatioOptions = [
    '1:1',
    '9:16',
    '16:9',
    '4:3',
    '3:4',
  ];

  /// Kala Flash and Kala Canvas. Other image models keep the shorter set.
  static const List<String> kFlashCanvasAspectRatioOptions = [
    '1:1',
    '16:9',
    '9:16',
    '4:3',
    '3:4',
    '3:2',
    '2:3',
    '21:9',
  ];

  /// Maps stored values (including legacy `Default`) to a supported ratio.
  static String normalizeAspectRatio(String? raw) {
    if (raw == null) return '1:1';
    final t = raw.trim();
    if (t.isEmpty || t == 'Default') return '1:1';
    if (kAdvancedAspectRatioOptions.contains(t) ||
        kFlashCanvasAspectRatioOptions.contains(t)) {
      return t;
    }
    return '1:1';
  }
}

class GenericToolPage extends StatefulWidget {
  final GenericToolConfig config;
  final String? restoreJobId;
  final List<String> initialLocalPaths;
  final String? initialPrompt;
  final Map<String, dynamic>? initialSettings;
  final String? sourceJobId;
  final String? launchTemplateId;
  final String? launchTemplateTitle;
  final bool focusPrompt;
  final Future<String?>? pendingPrompt;
  const GenericToolPage({
    super.key,
    required this.config,
    this.restoreJobId,
    this.initialLocalPaths = const [],
    this.initialPrompt,
    this.initialSettings,
    this.sourceJobId,
    this.launchTemplateId,
    this.launchTemplateTitle,
    this.focusPrompt = false,
    this.pendingPrompt,
  });

  static Widget restoreFromJob({
    required GenericToolConfig config,
    required String jobId,
  }) {
    return GenericToolPage(config: config, restoreJobId: jobId);
  }

  @override
  State<GenericToolPage> createState() => _GenericToolPageState();
}

class _GenericToolPageState extends State<GenericToolPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Friendly display names for LoRA adapters ──
  // Key = raw adapter value sent to backend, Value = user-friendly label
  static const Map<String, String> _loraFriendlyNames = {
    'None': 'None',
    'Consistance': 'Consistency',
    'Semirealistic-photo-detailer': 'Photo Detailer',
    'AnyPose': 'Pose Transfer',
    'Any2Real_2601': 'Any to Realistic',
    'Hyperrealistic-Portrait': 'Hyper Portrait',
    'Ultrarealistic-Portrait': 'Ultra Portrait',
    'BFS-Best-FaceSwap-merge': 'Face Swap Blend',
    'F2P': 'Face to Photo',
    'Multiple-Angles': 'Multi-Angle View',
    'Light-Restoration': 'Light Restore',
    'Relight': 'Relight',
    'Edit-Skin': 'Skin Editor',
    'Next-Scene': 'Next Scene',
    'Flat-Log': 'Flat / Log',
  };

  // Short descriptions for each LoRA adapter mode
  static const Map<String, String> _loraDescriptions = {
    'None': 'Standard edit — no special mode',
    'Consistance': 'Keep character identity consistent',
    'Semirealistic-photo-detailer': 'Enhance photo with fine details',
    'AnyPose': 'Change pose while keeping identity',
    'Any2Real_2601': 'Convert any style to realistic photo',
    'Hyperrealistic-Portrait': 'Hyper-detailed portrait output',
    'Ultrarealistic-Portrait': 'Ultra-realistic portrait style',
    'BFS-Best-FaceSwap-merge': 'Blend swapped face seamlessly',
    'F2P': 'Generate full photo from a face',
    'Multiple-Angles': 'Generate multiple angle views',
    'Light-Restoration': 'Restore and fix lighting',
    'Relight': 'Re-light the scene creatively',
    'Edit-Skin': 'Enhance and retouch skin texture',
    'Next-Scene': 'Generate a continuation scene',
    'Flat-Log': 'Apply flat / log color grading',
  };

  final picker = ImagePicker();
  final Map<String, dynamic> _inputs = {};
  // Store video duration for video upscaler cost calculation
  Duration? _inputVideoDuration;
  // Fallback LoRA adapter metadata loaded from local tool_config.json
  final Map<String, List<String>> _loraAdaptersByModel = {};
  bool _loading = false;

  /// True while a sparkles request is writing one prompt field.
  bool _composerAutoPromptLoading = false;
  String? _autoPromptField;
  final Map<String, int> _promptFillTicks = {};
  bool _autoOpenMaskAfterPick = false;
  String? _selectedModeKey;
  String? _activeJobId;
  final bool _fetchingResult = false;

  // Track image processing state to prevent race conditions
  bool _isProcessingImage = false;
  int _imageProcessingVersion = 0; // Increment to invalidate stale operations

  // for multi-image preview
  late PageController _previewPageController;

  // Controllers
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _sunoStyleController = TextEditingController();
  String? _stashedMusicLyrics;
  String? _stashedVocalLanguage;
  final FocusNode _promptFocusNode = FocusNode();

  /// Rebuild composer when focus/text changes (streaming hint vs field).
  void _onComposerPromptVisualsChanged() {
    final typed = _promptController.text;
    if (_hasPrompt && typed.trim().isNotEmpty) {
      _inputs['prompt'] = typed;
    }
    if (mounted) setState(() {});
  }

  String _composerHintExamplesKey = '';
  List<String> _composerHintExamplesCache = const [];

  // -------- Style Library (can load from config for OTA updates) --------
  String _selectedStyleCategory = 'All';
  StylePreset? _selectedStyle;
  final Set<String> _favoriteStyles = {};

  // Config-loaded styles and tags (null = use hardcoded fallbacks)
  List<StylePreset>? _configStyles;
  List<String>? _configStyleCategories;
  List<PromptChip>? _configQuickTags;

  // -------- User Templates (local storage) --------
  List<UserTemplate> _userTemplates = [];

  // -------- Prompt Enhancer Section --------
  /// Outer visibility for the Style & Tags block (composer palette button).
  bool _promptStylesVisible = true;
  int _enhancerTabIndex = 0; // 0 = Styles, 1 = My Templates

  // -------- Section Shortcut Bar (smooth-scroll targets) --------
  // GlobalKeys attached to the first widget of each section/group so the
  // pill of circular icons below the composer can scroll to them.
  final GlobalKey _modeSectionKey = GlobalKey();
  final GlobalKey _imageUploadKey = GlobalKey();
  final GlobalKey _videoUploadKey = GlobalKey();
  final GlobalKey _audioUploadKey = GlobalKey();
  final GlobalKey _fileUploadKey = GlobalKey();
  final GlobalKey _textInputKey = GlobalKey();
  final GlobalKey _numericKey = GlobalKey();
  final GlobalKey _slidersKey = GlobalKey();
  final GlobalKey _dropdownsKey = GlobalKey();
  final GlobalKey _togglesKey = GlobalKey();
  final GlobalKey _colorPickerKey = GlobalKey();
  final GlobalKey _aspectRatioKey = GlobalKey();
  final GlobalKey _multiSelectKey = GlobalKey();
  final GlobalKey _rangeSliderKey = GlobalKey();
  final GlobalKey _stylesSectionKey = GlobalKey();
  // Ephemeral pulse animation driver for the most recently targeted section.
  String? _pulseSectionId;

  // -------- Advanced Settings --------
  late AdvancedSettings _advancedSettings;

  // -------- Model Selection --------
  String? _selectedModelId;
  Map<String, dynamic>? _selectedModelData;

  /// Active tool after an in-page image-studio switch. Null keeps the route's tool.
  GenericToolConfig? _imageStudioConfig;
  String? _imageStudioFamilyName;
  String? _videoStudioFamilyName;
  bool _imageStudioSwitching = false;

  GenericToolConfig get _tool => _imageStudioConfig ?? widget.config;

  static const _imageStudioIds = <String>{
    'create_image',
    'edit_image',
    'upscale',
    'remove_background',
    'expand_scene',
    'glm_ocr',
  };
  static const _videoStudioIds = <String>{
    'create_video',
    'animate_image',
  };

  // -------- Generate Button Animation --------
  late AnimationController _glowAnimationController;

  // API config
  static const String controllerUrl = "https://genedit.mooo.com";
  final AuthService _authService = AuthService();

  // -------- Upscale (2x/4x switch) --------
  int _scaleFactor = 2;
  bool _upscaleEnabled = false;
  int? _priorVariationCount;

  // -------- Bulk Edit --------
  // Each inner list is one bulk task: one image (default) or several for multi-init models
  // (e.g. Vectra / Revia up to 3 reference images per task).
  final List<List<Uint8List>> _bulkImageJobs = [];
  // Stores masks for each bulk task (for inpaint/erase tools; one mask per task)
  final List<Uint8List?> _bulkMasks = [];

  // Video controllers for user-uploaded videos (e.g., ref_video for dreamid)
  final Map<String, VideoPlayerController> _userVideoControllers = {};
  // Stores outpaint configurations for each bulk image (for expand scene)
  final List<Map<String, String>?> _bulkOutpaintConfigs = [];

  /// Video upscaler bulk: local file paths (aligned with [_bulkVideoDurations]).
  final List<String> _bulkVideoPaths = [];
  final List<Duration?> _bulkVideoDurations = [];

  /// CineReal bulk: optional reference video per task (same index as [_bulkImageJobs]).
  /// Mutually exclusive with a second (end) frame on that task.
  final List<Uint8List?> _bulkCineRealRefVideoBytes = [];
  final List<String?> _bulkCineRealRefVideoPaths = [];
  final List<Duration?> _bulkCineRealRefVideoDurations = [];

  /// True while dispatching sequential [_runJob] calls for bulk video upscale.
  bool _videoBulkSequentialActive = false;

  /// Set when [completeHeavyTierRewardedAdIfNeeded] runs in parallel with media base64 encoding.
  Map<String, dynamic>? _prefetchedEncodedInputsForSubmit;
  static const int _maxBulkImagesVip = 15;
  static const int _maxBulkImagesNonVip = 5;
  int get _maxBulkImages =>
      isVipUser() ? _maxBulkImagesVip : _maxBulkImagesNonVip;
  // Max total jobs per submission (images × variations) to prevent server overload
  static const int _maxTotalJobs = 15;

  /// Max init/reference images allowed for the *current* model on a single bulk task.
  int get _bulkMaxInitPerJob {
    if (_requiresMask || _isOutpaint) return 1;
    // CineReal bulk: allow start + end per clip (FLF2V when both frames are set).
    if (_isAnimateImageTool &&
        _isCineRealAnimateModel &&
        _advancedSettings.bulkEditEnabled &&
        _supportsBulkImageEdit) {
      return 2;
    }
    final raw = _effectiveInputConfig('init_image')['max'];
    if (raw is int && raw > 1) return raw.clamp(1, 8);
    return 1;
  }

  bool get _bulkSupportsMultiInitPerJob =>
      _bulkMaxInitPerJob > 1 && !_requiresMask && !_isOutpaint;

  int get _bulkTaskCount =>
      _bulkImageJobs.where((job) => job.isNotEmpty).length;

  bool get _hasBulkInput {
    if (_advancedSettings.bulkEditEnabled && _supportsBulkVideoEdit) {
      return _bulkVideoPaths.isNotEmpty;
    }
    return _bulkTaskCount > 0;
  }

  /// Jobs in the current bulk selection (images or videos), for limits and pricing.
  int get _bulkActiveMediaCount {
    if (!_advancedSettings.bulkEditEnabled || !_hasBulkInput) return 1;
    if (_supportsBulkVideoEdit) return _bulkVideoPaths.length;
    return _bulkImageJobs.length;
  }

  /// Check if tool requires mask for each image (inpaint/erase tools)
  bool get _requiresMask {
    final model = _tool.model.toLowerCase();
    final mode = _selectedModeKey?.toLowerCase() ?? "";
    final paramMode =
        (_tool.params?["mode"]?.toString().toLowerCase() ?? "");
    return model.contains("inpaint") ||
        model.contains("lama") ||
        mode.contains("inpaint") ||
        paramMode.contains("inpaint") ||
        paramMode.contains("lama");
  }

  /// Check if tool is outpaint (expand scene)
  bool get _isOutpaint => _tool.model == "diffusers_outpaint";

  /// Check if this is an upscaler tool (e.g., "Upscale Image")
  /// Upscalers have upscale always enabled by default
  bool get _isUpscalerTool {
    final title = _tool.title.toLowerCase();
    final model = _tool.model.toLowerCase();
    // Check by title or model name
    // Upscale models: realesrgan, realesrgan_anime, realesrgan_denoise, face_enhancer
    return title.contains('upscale') ||
        model == 'aurasrv2' ||
        model == 'swin2sr' ||
        model.startsWith('realesrgan');
  }

  /// Face Enhancer sub-model under Upscale Image (fixed backend params; not shown in settings UI).
  static const String _kFaceEnhancerFixedMode = 'v1.4';
  static const String _kFaceEnhancerBgModel4x = 'realesr-general-x4v3';
  static const String _kFaceEnhancerBgModel2x = 'RealESRGAN_x2plus';

  bool get _isFaceEnhancerModel =>
      (_selectedModelId ?? _tool.model) == 'face_enhancer';

  /// Server always receives GFPGAN v1.4 + restore faces for [face_enhancer]; background upscaler follows 2×/4×.
  void _syncFaceEnhancerFixedParams() {
    if (!_isUpscalerTool || !_isFaceEnhancerModel) return;
    _inputs['mode'] = _kFaceEnhancerFixedMode;
    final raw = _inputs['scale_factor'];
    final num scale = raw != null
        ? (raw is num ? raw : (num.tryParse('$raw') ?? _scaleFactor))
        : _scaleFactor;
    _inputs['bg_model'] =
        scale >= 3 ? _kFaceEnhancerBgModel4x : _kFaceEnhancerBgModel2x;
    _inputs['enhance_faces'] = true;
  }

  /// Check if this is an edit_image category tool
  /// Edit image tools: have init_image input and outputType is 'image'
  bool get _isEditImageTool {
    final hasInitImage =
        _tool.inputs.any((i) => i['id'] == 'init_image');
    return hasInitImage && _tool.outputType == 'image';
  }

  /// Unified CineReal model on Animate Image (worker id chosen by motion mode).
  static const String _kCineRealAnimateModelId = 'ltx25_int8';

  /// Cinemotion Pro (MiniMax H3) — one id for text-to-video and image-to-video.
  static const String _kCinemotionProModelId = 'minimax_h3';

  /// Legacy ids remapped onto the live workers.
  static const String _kLegacyWanI2vModelId = 'wan_22_fp8_lightx2v_i2v';
  static const String _kLegacyCineRealAnimateModelId = 'ltx2_3_cinereal';

  /// Keys the mobile app must not forward to LTX 2.5 Comfy (or leftover LTX 2.3).
  static const Set<String> _kLtx25WorkerOmitParams = {
    'duration',
    'enable_rife',
    'rife_target_fps',
    'enable_upscaling',
    'upscale_factor',
    'postprocess_interpolate_first',
    'randomize_seed',
    'resize_image',
    'fps',
    'frame_rate',
    'num_frames',
    'output_dir',
    'use_latent_upsampler',
    'use_spatial_upsampler',
    'scale_image',
    'scale_factor',
    'cfg_scale',
  };

  static const Set<String> _kH3WorkerOmitParams = {
    'duration',
    'duration_seconds',
    'width',
    'height',
    'enable_rife',
    'rife_target_fps',
    'enable_upscaling',
    'upscale_factor',
    'postprocess_interpolate_first',
    'scale_image',
    'scale_factor',
    'cfg_scale',
    'output_dir',
    'num_frames',
    'frame_rate',
    'fps',
  };

  /// MiniMax H3 ResolutionSelector combo labels (ComfyUI AspectRatio).
  static const Map<String, String> _kH3AspectSelectorLabels = {
    '1:1': '1:1 (Square)',
    '2:3': '2:3 (Portrait Photo)',
    '3:2': '3:2 (Photo)',
    '3:4': '3:4 (Portrait Standard)',
    '4:3': '4:3 (Standard)',
    '9:16': '9:16 (Portrait Widescreen)',
    '16:9': '16:9 (Widescreen)',
    '21:9': '21:9 (Ultrawide)',
  };

  static const List<String> _kVideoShapeOptions = ['9:16', '1:1', '16:9'];

  /// Aligns frame count to worker rule: ≥9 and 8k+1 (9, 17, 25, …).
  static int _alignLtx23NumFrames(int raw) {
    if (raw < 9) return 9;
    final k = ((raw - 1) / 8).round();
    return (8 * k + 1).clamp(9, 262144);
  }

  /// LTX 2.5 canvas: 720p-class, multiples of 64 (LTX25AllModesControlsV2).
  static const int _kLtx25MaxLongEdge = 1280;
  static const int _kLtx25MaxShortEdge = 704;

  /// LTX 2.3 T2V: max “720p-class” frame — 1280×720 landscape box, 720×1280 portrait.
  static const int _kLtx23T2vMaxLongEdge = 1280;
  static const int _kLtx23T2vMaxShortEdge = 720;

  /// Largest integer size for [selectedRatio] that fits inside the 720p bounds (before ÷32 floor).
  static (int width, int height) _ltx23T2vPixelsForAspectRatio(
      String selectedRatio) {
    final ratioParts = selectedRatio.split(':');
    if (ratioParts.length != 2) return (768, 512);
    final ratioW = double.tryParse(ratioParts[0]) ?? 1.0;
    final ratioH = double.tryParse(ratioParts[1]) ?? 1.0;
    if (ratioW <= 0 || ratioH <= 0) return (768, 512);
    final r = ratioW / ratioH;
    int w;
    int h;
    if (r >= 1.0) {
      w = _kLtx23T2vMaxLongEdge;
      h = (w / r).round();
      if (h > _kLtx23T2vMaxShortEdge) {
        h = _kLtx23T2vMaxShortEdge;
        w = (h * r).round();
      }
    } else {
      h = _kLtx23T2vMaxLongEdge;
      w = (h * r).round();
      if (w > _kLtx23T2vMaxShortEdge) {
        w = _kLtx23T2vMaxShortEdge;
        h = (w / r).round();
      }
    }
    w = w.clamp(32, _kLtx23T2vMaxLongEdge);
    h = h.clamp(32, _kLtx23T2vMaxLongEdge);
    return (w, h);
  }

  static void _applyLtx23T2vFloor32ToParams(
    Map<String, dynamic> resolvedParams,
    int w,
    int h,
  ) {
    int floorTo32(int x) => ((x / 32).floor() * 32).clamp(32, 2048);
    resolvedParams['width'] = floorTo32(w);
    resolvedParams['height'] = floorTo32(h);
  }

  /// LTX 2.5 stage-1 latent is half the canvas, so both edges must be multiples of 64.
  static void _applyLtx25CanvasToParams(
    Map<String, dynamic> resolvedParams,
    int w,
    int h,
  ) {
    int floorTo64(int x) => ((x / 64).floor() * 64).clamp(256, 2048);
    resolvedParams['width'] = floorTo64(w);
    resolvedParams['height'] = floorTo64(h);
  }

  static (int width, int height) _ltx25PixelsForAspectRatio(
      String selectedRatio) {
    switch (AdvancedSettings.normalizeAspectRatio(selectedRatio)) {
      case '9:16':
        return (_kLtx25MaxShortEdge, _kLtx25MaxLongEdge);
      case '1:1':
        return (768, 768);
      default:
        return (_kLtx25MaxLongEdge, _kLtx25MaxShortEdge);
    }
  }

  String get _selectedShapeRatio {
    final fromInput = _inputs['aspect_ratio']?.toString();
    if (fromInput != null && fromInput.trim().isNotEmpty) {
      final n = AdvancedSettings.normalizeAspectRatio(fromInput);
      if (_kVideoShapeOptions.contains(n) ||
          AdvancedSettings.kAdvancedAspectRatioOptions.contains(n) ||
          AdvancedSettings.kFlashCanvasAspectRatioOptions.contains(n)) {
        return n;
      }
    }
    return AdvancedSettings.normalizeAspectRatio(
        _advancedSettings.aspectRatio);
  }

  bool get _isLtx25Model {
    final id = _selectedVideoGenModelId.toLowerCase();
    return id.startsWith('ltx25_int8');
  }

  bool get _isMinimaxH3Model =>
      _selectedVideoGenModelId == _kCinemotionProModelId;

  bool get _isComfyVideoWorker => _isLtx25Model || _isMinimaxH3Model;

  /// 2× motion and 2× resolution post-process for older video engines.
  /// CineReal and Cinemotion Pro render the frame themselves, so this
  /// control stays hidden for those models and for tools that only offer them.
  bool get _showsVideoEnhancement {
    if (_tool.outputType != 'video') return false;
    if (_isVideoUpscalerTool) return true;
    if (_isComfyVideoWorker) return false;
    final models = _tool.models;
    if (models == null || models.isEmpty) return false;
    for (final model in models) {
      if (model['enabled'] == false) continue;
      final id = (model['id']?.toString() ?? '').toLowerCase();
      if (id.startsWith('ltx25_int8') || id == _kCinemotionProModelId) {
        continue;
      }
      return true;
    }
    return false;
  }

  /// Backend model id when config uses per-mode UI ids (`submitModelId`).
  String get _submitModelIdForRequest {
    final raw = _selectedModelData?['submitModelId'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    return _selectedModelId ?? _tool.model;
  }

  /// Worker-facing `model` for POST /submit (CineReal maps to i2v or flf2v worker).
  String get _workerModelIdForSubmit {
    if (_isCineRealAnimateModel) {
      final i2v = _selectedModelData?['cinerealI2vWorkerModel'] as String? ??
          'ltx25_int8_i2v';
      final flf2v =
          _selectedModelData?['cinerealFlf2vWorkerModel'] as String? ??
              'ltx25_int8_flf2v';
      return _isCineRealFlf2vMode ? flf2v : i2v;
    }
    return _submitModelIdForRequest;
  }

  bool get _isCineRealAnimateModel {
    final id = _selectedModelId ?? _tool.model;
    return id == _kCineRealAnimateModelId ||
        id == _kLegacyCineRealAnimateModelId;
  }

  bool get _requiresEndFrame => widget.launchTemplateId == 'photo_to_photo';

  /// True when CineReal should use the FLF2V pipeline (two keyframes).
  ///
  /// Single mode: [last_frame_image] is set. Bulk image mode: every non-empty
  /// task has exactly two frames. Does not use the removed settings toggle.
  bool get _isCineRealFlf2vMode {
    if (!_isCineRealAnimateModel) return false;
    // Reference video and two-keyframe FLF2V are mutually exclusive.
    if (_cineRealHasRefVideoBytesSingleOrBulk()) return false;
    final bulkOn = _advancedSettings.bulkEditEnabled && _supportsBulkImageEdit;
    if (bulkOn) {
      final tasks =
          _bulkImageJobs.where((job) => job.isNotEmpty).toList(growable: false);
      if (tasks.isEmpty) return false;
      return tasks.every(
        (job) => job.length == 2 && job[0].isNotEmpty && job[1].isNotEmpty,
      );
    }
    final lastBytes = _bytesForInputKey('last_frame_image');
    return lastBytes != null && lastBytes.isNotEmpty;
  }

  bool _cineRealSingleHasEndFrameBytes() {
    if (!_isAnimateImageTool || !_isCineRealAnimateModel) return false;
    return _bytesForInputKey('last_frame_image') != null;
  }

  bool _cineRealSingleHasRefVideoBytes() {
    if (!_isAnimateImageTool || !_isCineRealAnimateModel) return false;
    final v = _inputs['ref_video_bytes'];
    return v is Uint8List && v.isNotEmpty;
  }

  bool _cineRealHasRefVideoBytesSingleOrBulk() {
    if (_cineRealSingleHasRefVideoBytes()) return true;
    if (!_advancedSettings.bulkEditEnabled || !_supportsBulkImageEdit) {
      return false;
    }
    for (final b in _bulkCineRealRefVideoBytes) {
      if (b != null && b.isNotEmpty) return true;
    }
    return false;
  }

  bool _bulkCineRealTaskHasEndFrame(int taskIndex) {
    if (taskIndex < 0 || taskIndex >= _bulkImageJobs.length) return false;
    final job = _bulkImageJobs[taskIndex];
    return job.length >= 2 && job[0].isNotEmpty && job[1].isNotEmpty;
  }

  bool _bulkCineRealTaskHasRefVideo(int taskIndex) {
    if (taskIndex < 0 || taskIndex >= _bulkCineRealRefVideoBytes.length) {
      return false;
    }
    final b = _bulkCineRealRefVideoBytes[taskIndex];
    return b != null && b.isNotEmpty;
  }

  bool _bulkCineRealAnyRefVideoBytes() {
    for (final b in _bulkCineRealRefVideoBytes) {
      if (b != null && b.isNotEmpty) return true;
    }
    return false;
  }

  void _syncBulkCineRealRefVideoListsToJobs() {
    while (_bulkCineRealRefVideoBytes.length < _bulkImageJobs.length) {
      _bulkCineRealRefVideoBytes.add(null);
      _bulkCineRealRefVideoPaths.add(null);
      _bulkCineRealRefVideoDurations.add(null);
    }
    while (_bulkCineRealRefVideoBytes.length > _bulkImageJobs.length) {
      final last = _bulkCineRealRefVideoBytes.length - 1;
      _disposeBulkCineRealRefVideoAt(last);
      _bulkCineRealRefVideoBytes.removeLast();
      _bulkCineRealRefVideoPaths.removeLast();
      _bulkCineRealRefVideoDurations.removeLast();
    }
  }

  void _disposeBulkCineRealRefVideoAt(int index) {
    if (index < 0 || index >= _bulkCineRealRefVideoPaths.length) return;
    final p = _bulkCineRealRefVideoPaths[index];
    if (p != null) {
      final c = _userVideoControllers.remove(p);
      c?.dispose();
    }
  }

  void _clearBulkCineRealRefVideoAt(int index) {
    _disposeBulkCineRealRefVideoAt(index);
    if (index >= 0 && index < _bulkCineRealRefVideoBytes.length) {
      _bulkCineRealRefVideoBytes[index] = null;
      _bulkCineRealRefVideoPaths[index] = null;
      _bulkCineRealRefVideoDurations[index] = null;
    }
  }

  void _clearCineRealSingleRefVideo() {
    final p = _inputs['ref_video_path'] as String?;
    if (p != null) {
      final c = _userVideoControllers.remove(p);
      c?.dispose();
    }
    _inputs.remove('ref_video');
    _inputs.remove('ref_video_path');
    _inputs.remove('ref_video_bytes');
    _inputs.remove('ref_video_duration');
    _inputVideoDuration = null;
  }

  Future<void> _pickRefVideoForBulkTask(int taskIndex) async {
    if (!_isAnimateImageTool ||
        !_isCineRealAnimateModel ||
        !_advancedSettings.bulkEditEnabled ||
        !_supportsBulkImageEdit) {
      return;
    }
    if (taskIndex < 0 || taskIndex >= _bulkImageJobs.length) return;
    if (_bulkCineRealTaskHasEndFrame(taskIndex)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Remove the end frame from this clip before adding a reference video.',
            ),
          ),
        );
      }
      return;
    }
    final vi = _tool.inputs.firstWhere(
      (i) => i['id'] == 'ref_video',
      orElse: () => <String, dynamic>{},
    );
    if (vi.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This tool has no reference-video slot in its configuration.',
            ),
          ),
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        _syncBulkCineRealRefVideoListsToJobs();
        _isProcessingImage = true;
      });
    }
    VideoPlayerController? notYetOwned;
    try {
      final source = await _promptVideoPickSource();
      if (source == null) {
        if (mounted) setState(() => _isProcessingImage = false);
        return;
      }
      final file = await picker.pickVideo(source: source);
      if (file == null) {
        if (mounted) setState(() => _isProcessingImage = false);
        return;
      }
      final videoPath = file.path;
      notYetOwned = VideoPlayerController.file(File(videoPath));
      await notYetOwned.initialize();
      final originalDuration = notYetOwned.value.duration;
      final videoBytes = await file.readAsBytes();
      notYetOwned.setLooping(true);
      notYetOwned.setVolume(0);
      if (!mounted) {
        await notYetOwned.dispose();
        return;
      }
      final c = notYetOwned;
      notYetOwned = null;
      setState(() {
        _syncBulkCineRealRefVideoListsToJobs();
        _clearBulkCineRealRefVideoAt(taskIndex);
        _bulkCineRealRefVideoBytes[taskIndex] = videoBytes;
        _bulkCineRealRefVideoPaths[taskIndex] = videoPath;
        _bulkCineRealRefVideoDurations[taskIndex] = originalDuration;
        _userVideoControllers[videoPath] = c;
        _isProcessingImage = false;
      });
      c.play();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reference video added for clip ${taskIndex + 1}.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('❌ _pickRefVideoForBulkTask: $e\n$st');
      if (notYetOwned != null) {
        await notYetOwned.dispose();
      }
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not add reference video. '
              'If this persists, try a full restart after `flutter clean`. '
              '($e)',
            ),
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _submitCineRealBulkSequentialWithRefVideos({
    required String controllerUrl,
    required Map<String, String> headers,
    required String firebaseToken,
    required Map<String, dynamic> filteredRootParams,
    required Map<String, dynamic> paramsTemplate,
    required List<dynamic> groupedKeys,
    required int requestedVariations,
    required int maxRetries,
  }) async {
    final n = _bulkImageJobs.length;
    final refVideoR2Keys = <String?>[];
    for (var i = 0; i < n; i++) {
      final b = i < _bulkCineRealRefVideoBytes.length
          ? _bulkCineRealRefVideoBytes[i]
          : null;
      if (b != null && b.isNotEmpty) {
        final vk = await MediaUploadService.uploadMediaBatch(
          files: [b],
          mediaType: "video",
          authToken: firebaseToken,
        );
        if (vk == null || vk.isEmpty) {
          throw Exception(
            "Could not upload reference video for clip ${i + 1}. Check your connection and try again.",
          );
        }
        refVideoR2Keys.add(vk.first);
      } else {
        refVideoR2Keys.add(null);
      }
    }

    final allJobIds = <String>[];
    bool promptEnhanced = false;
    String? enhancedPrompt;

    for (var ti = 0; ti < n; ti++) {
      final pRow = Map<String, dynamic>.from(paramsTemplate);
      stripForbiddenMediaFromParams(pRow);
      for (final k in kForbiddenMediaParamKeys) {
        pRow.remove(k);
      }

      final gk = groupedKeys[ti];
      final job = _bulkImageJobs[ti];
      final rowFlf2v =
          job.length >= 2 && job[0].isNotEmpty && job[1].isNotEmpty;
      final worker = rowFlf2v
          ? (_selectedModelData?['cinerealFlf2vWorkerModel'] as String? ??
              'ltx25_int8_flf2v')
          : (_selectedModelData?['cinerealI2vWorkerModel'] as String? ??
              'ltx25_int8_i2v');

      if (rowFlf2v) {
        final lst = (gk is List)
            ? gk.map((e) => e.toString()).toList()
            : <String>[gk.toString()];
        if (lst.length >= 2) {
          pRow['first_frame_image_r2_key'] = lst[0];
          pRow['last_frame_image_r2_key'] = lst[1];
        }
      } else {
        final k0 = gk is List ? gk.first.toString() : gk.toString();
        pRow['init_image_r2_key'] = k0;
      }

      for (final k in ["init_video", "input_video", "ref_video"]) {
        pRow.remove(k);
      }

      final baseRow = <String, dynamic>{
        ...filteredRootParams,
        "model": worker,
        "fcm_token": firebaseToken,
        "variations": requestedVariations,
        "is_bulk": false,
        "enhance_prompt": _advancedSettings.enhancePrompt,
      };
      if (ti < refVideoR2Keys.length && refVideoR2Keys[ti] != null) {
        baseRow["input_video_r2_key"] = refVideoR2Keys[ti]!;
      }

      dynamic rowData;
      for (var attempt = 1; attempt <= maxRetries; attempt++) {
        final resp = await http
            .post(
              Uri.parse('$controllerUrl/submit'),
              headers: headers,
              body: jsonEncode(<String, dynamic>{
                ...baseRow,
                "params": pRow,
              }),
            )
            .timeout(const Duration(seconds: 60));
        if (resp.statusCode == 200) {
          rowData = jsonDecode(resp.body);
          break;
        }
        debugPrint(
            "❌ CineReal bulk row $ti submit failed: ${resp.statusCode} ${resp.body}");
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
        }
      }
      if (rowData == null) {
        throw Exception(
            "Failed to submit clip ${ti + 1} after $maxRetries retries");
      }
      promptEnhanced = promptEnhanced || (rowData["prompt_enhanced"] == true);
      enhancedPrompt ??= rowData["enhanced_prompt"] as String?;
      if (rowData["job_ids"] != null && rowData["job_ids"] is List) {
        allJobIds.addAll((rowData["job_ids"] as List).map((e) => e.toString()));
      } else if (rowData["job_id"] != null) {
        allJobIds.add(rowData["job_id"].toString());
      }
    }

    return <String, dynamic>{
      "job_ids": allJobIds,
      "prompt_enhanced": promptEnhanced,
      "enhanced_prompt": enhancedPrompt,
    };
  }

  /// Check if this is an animate_image category tool
  /// Animate image tools: have init_image input and outputType is 'video'
  bool get _isAnimateImageTool {
    final hasInitImage =
        _tool.inputs.any((i) => i['id'] == 'init_image');
    return hasInitImage && _tool.outputType == 'video';
  }

  /// Check if this is a video upscaler tool
  bool get _isVideoUpscalerTool {
    final model = _tool.model.toLowerCase();
    final title = _tool.title.toLowerCase();
    // Check if model is video_upscaler or title contains both "upscale" and "video"
    return model == 'video_upscaler' ||
        (title.contains('upscale') && title.contains('video'));
  }

  /// Check if this is a video category tool (text to video, image to video, video to video)
  bool get _isVideoTool => _tool.outputType == 'video';
  bool get _isTextTool => _tool.outputType == 'text';
  bool get _isAudioTool => _tool.outputType == 'audio';
  bool get _isSpeechTool => _tool.capabilityId == 'create_speech';
  bool get _isMusicTool => _tool.capabilityId == 'create_music';

  bool get _isMuseModel {
    final id = _selectedModelId ?? _tool.model;
    return id == 'muse_image' || id == 'muse_image_edit';
  }

  bool get _isFlashOrCanvasModel {
    final id = _selectedModelId ?? _tool.model;
    return id == 'flux2_klein_9b' ||
        id == 'flux2_klein_9b_edit' ||
        id == 'muse_image' ||
        id == 'muse_image_edit';
  }

  bool get _allowsOutputUpscale =>
      _tool.capabilityId == 'create_image' ||
      _tool.capabilityId == 'edit_image';
  bool get _musicEasy => _isMusicTool && _inputs['music_mode'] != 'advanced';
  bool get _isKalaSong =>
      _isMusicTool &&
      (_selectedModelId ?? _tool.model) == 'ace_step_music';
  bool get _isKalaSongPro =>
      _isMusicTool &&
      (_selectedModelId ?? _tool.model) == 'minimax_music_26';
  bool get _isSunoV6 =>
      _isMusicTool &&
      (_selectedModelId ?? _tool.model) == kSunoV6ModelId;
  bool get _sunoSounds => _isSunoV6 && _inputs['suno_kind'] == 'sound';
  bool get _sunoExtend => _isSunoV6 && _inputs['suno_kind'] == 'extend';
  bool get _sunoMashup => _isSunoV6 && _inputs['suno_kind'] == 'mashup';
  bool get _sunoSongKind =>
      _isSunoV6 && !_sunoSounds && !_sunoExtend && !_sunoMashup;

  bool _relatesMusicFields(String fieldRef) {
    if (!_isMusicTool || _musicEasy || _sunoSounds) return false;
    switch (fieldRef) {
      case 'prompt':
      case 'style':
      case 'lyrics':
      case 'negative':
      case 'negative_prompt':
        return true;
      default:
        return false;
    }
  }

  List<String> _advancedMusicBoxRefs() {
    return [
      'lyrics',
      _isSunoV6 ? 'style' : 'prompt',
      'negative_prompt',
    ];
  }

  String _musicBoxText(String ref) {
    if (ref == 'style') return _sunoStyleController.text;
    if (ref == 'prompt') return _promptController.text;
    final value = _inputs[ref];
    return value is String ? value : '';
  }

  void _writeMusicBoxIfEmpty(String ref, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _musicBoxText(ref).trim().isNotEmpty) return;
    if (ref == 'style') {
      _sunoStyleController.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
      _inputs['style'] = trimmed;
      return;
    }
    if (ref == 'prompt') {
      _promptController.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
      _inputs['prompt'] = trimmed;
      return;
    }
    _inputs[ref] = trimmed;
    _promptFillTicks[ref] = (_promptFillTicks[ref] ?? 0) + 1;
  }

  bool _filledMedia(String id) {
    final value = _inputs[id];
    if (value is Uint8List && value.isNotEmpty) return true;
    if (value is List && value.isNotEmpty) return true;
    final path = _inputs['${id}_path'];
    if (path is String && path.isNotEmpty) return true;
    final bytes = _inputs['${id}_bytes'];
    return bytes is Uint8List && bytes.isNotEmpty;
  }

  /// A photo, clip, or track attached on the HitMaker easy composer.
  bool get _sunoHasReference =>
      _isSunoV6 &&
      _musicEasy &&
      !_sunoSounds &&
      (_filledMedia('clip') ||
          _filledMedia('reference_audio') ||
          _filledMedia('cover_image'));

  void _keepLyricsAcrossVocals(bool vocalsOn) {
    if (!vocalsOn) {
      final typed = (_inputs['lyrics'] as String?) ?? '';
      if (typed.trim().isNotEmpty) _stashedMusicLyrics = typed;
      final language = _inputs['vocal_language']?.toString();
      if (language != null && language.isNotEmpty && language != 'unknown') {
        _stashedVocalLanguage = language;
      }
      return;
    }
    final current = (_inputs['lyrics'] as String?)?.trim() ?? '';
    final stashed = _stashedMusicLyrics?.trim() ?? '';
    if (current.isEmpty && stashed.isNotEmpty) {
      _inputs['lyrics'] = _stashedMusicLyrics;
    }
    final language = _inputs['vocal_language']?.toString();
    if ((language == null || language.isEmpty || language == 'unknown') &&
        _stashedVocalLanguage != null) {
      _inputs['vocal_language'] = _stashedVocalLanguage;
    }
  }

  String get _musicTrackMode => _inputs['track_mode']?.toString() ?? 'create';
  bool get _musicUsesAudio =>
      _isKalaSong &&
      (_musicTrackMode == 'remix' || _musicTrackMode == 'repaint');
  bool get _musicRepaint => _isKalaSong && _musicTrackMode == 'repaint';
  bool _musicExpanding = false;
  String? _easyMusicPrompt;
  bool _promptFilling = false;

  /// Check if this is an expand scene (outpaint) category tool
  bool get _isExpandSceneTool => _isOutpaint;

  /// Expand Scene keeps the prompt, and hides Style & Tags.
  bool get _hidesStyleAndTags =>
      _tool.capabilityId == 'expand_scene' ||
      _tool.title.toLowerCase() == 'expand scene';

  /// Check if this is an inpaint & erase category tool
  /// Includes inpaint, lama, and erase tools
  bool get _isInpaintEraseTool {
    final model = _tool.model.toLowerCase();
    final title = _tool.title.toLowerCase();
    final mode = _selectedModeKey?.toLowerCase() ?? "";
    final paramMode =
        (_tool.params?["mode"]?.toString().toLowerCase() ?? "");
    return model.contains("inpaint") ||
        model.contains("lama") ||
        model.contains("erase") ||
        title.contains("erase") ||
        mode.contains("inpaint") ||
        paramMode.contains("inpaint") ||
        paramMode.contains("lama") ||
        paramMode.contains("erase");
  }

  /// On-device-only path for Inpaint & Erase.
  /// We currently scope this to the inpaint capability + basic_utils model.
  bool get _isOnDeviceInpaintTool {
    if (!_isInpaintEraseTool) return false;
    final selectedModel =
        (_selectedModelId ?? _tool.model).toLowerCase();
    final toolId = (_tool.title).toLowerCase();
    final explicit = _selectedModelData?['onDeviceOnly'] == true;
    return explicit ||
        (selectedModel == 'basic_utils' && toolId.contains('erase'));
  }

  bool get _showAdvancedControls =>
      !_isOnDeviceInpaintTool && !_isInpaintEraseTool;

  /// Check if this is a remove background category tool
  bool get _isRemoveBackgroundTool {
    final model = _tool.model.toLowerCase();
    final title = _tool.title.toLowerCase();
    return model.contains("remove") && model.contains("background") ||
        title.contains("remove") && title.contains("background") ||
        model.contains("rembg") ||
        title.contains("rembg");
  }

  /// Primary image input id for Single/Bulk tabs (prefer common ids, else first `type: image`).
  String? get _bulkPrimaryImageInputRef {
    const preferredOrder = ['init_image', 'image', 'input_image'];
    final imageInputs = _tool.inputs
        .whereType<Map<String, dynamic>>()
        .where((i) => i['type'] == 'image')
        .toList();
    if (imageInputs.isEmpty) return null;
    for (final id in preferredOrder) {
      if (imageInputs.any((m) => m['id'] == id)) return id;
    }
    return imageInputs.first['id'] as String?;
  }

  bool get _supportsBulkImageEdit =>
      !_isMusicTool && _bulkPrimaryImageInputRef != null;

  /// Video upscaler: bulk queue of input files.
  String? get _bulkPrimaryVideoInputRef {
    if (!_isVideoUpscalerTool) return null;
    final v = _tool.inputs
        .whereType<Map<String, dynamic>>()
        .where((i) => i['type'] == 'video')
        .toList();
    if (v.isEmpty) return null;
    return v.first['id'] as String?;
  }

  bool get _supportsBulkVideoEdit => _bulkPrimaryVideoInputRef != null;

  /// Minimum clip length for create / animate video (not video upscaler).
  static const int _kMinVideoGenDurationSeconds = 5;

  /// Composer prompt field: extra vertical space when thumbnails / style row sit above.
  static const int _kComposerPromptMinLines = 6;
  static const int _kComposerPromptMaxLines = 12;

  int _maxVideoGenDurationSeconds() {
    return (_selectedModelData?['maxDuration'] as num?)?.toInt() ?? 8;
  }

  /// Create Video and Animate Image share 5s steps. Cinemotion Pro stops at
  /// 15s (5, 10, 15). CineReal stops at 20s (5, 10, 15, 20).
  List<int> _allowedVideoGenDurationSeconds() {
    final maxD = _maxVideoGenDurationSeconds();
    if (maxD < 1) return const [1];
    if (maxD < _kMinVideoGenDurationSeconds) {
      return List<int>.generate(maxD, (i) => i + 1);
    }
    final out = <int>[];
    for (var v = _kMinVideoGenDurationSeconds; v <= maxD; v += 5) {
      out.add(v);
    }
    if (out.isEmpty) {
      out.add(maxD.clamp(1, maxD));
    }
    return out;
  }

  int _clampVideoGenDurationSeconds(int seconds) {
    final allowed = _allowedVideoGenDurationSeconds();
    if (allowed.isEmpty) return seconds.clamp(1, 1);
    if (seconds <= allowed.first) return allowed.first;
    if (seconds >= allowed.last) return allowed.last;
    var best = allowed.first;
    var bestDiff = (seconds - best).abs();
    for (final v in allowed) {
      final d = (seconds - v).abs();
      if (d < bestDiff || (d == bestDiff && v > best)) {
        best = v;
        bestDiff = d;
      }
    }
    return best;
  }

  String get _selectedVideoGenModelId =>
      (_selectedModelId ?? _tool.model);

  /// LTX 2.3 family uses spatial upsampling only (no RIFE) in submit path.
  bool get _isLtx23SpatialOnlyVideoEnhancement {
    if (_isVideoUpscalerTool) return false;
    if (_isComfyVideoWorker) return false;
    return _selectedVideoGenModelId.toLowerCase().startsWith('ltx2_3');
  }

  bool get _combinedVideoEnhancementSwitchIsOn {
    if (_isLtx23SpatialOnlyVideoEnhancement) {
      return _advancedSettings.enableUpscale &&
          _advancedSettings.upscaleFactor == 2;
    }
    final mult =
        migrateLegacyInterpolateStorageValue(_advancedSettings.interpolateFps);
    return _advancedSettings.enableInterpolate &&
        mult == 2 &&
        _advancedSettings.enableUpscale &&
        _advancedSettings.upscaleFactor == 2;
  }

  void _setCombinedVideoEnhancement(bool on, StateSetter setSheetState) {
    setSheetState(() {
      setState(() {
        if (on) {
          if (_isLtx23SpatialOnlyVideoEnhancement) {
            _advancedSettings = _advancedSettings.copyWith(
              enableInterpolate: false,
              interpolateFps: 2,
              enableUpscale: true,
              upscaleFactor: 2,
            );
          } else {
            _advancedSettings = _advancedSettings.copyWith(
              enableInterpolate: true,
              interpolateFps: 2,
              enableUpscale: true,
              upscaleFactor: 2,
            );
          }
        } else {
          _advancedSettings = _advancedSettings.copyWith(
            enableInterpolate: false,
            enableUpscale: false,
          );
        }
      });
    });
  }

  /// Tool supports Single/Bulk tabs (image batch and/or video upscaler batch).
  bool get _supportsBulkEdit =>
      _supportsBulkImageEdit || _supportsBulkVideoEdit;

  /// Duration cost for animate / create video.
  /// Scales the model's `baseCost5Sec` (then `cost`) from tool_config.json.
  /// 5 seconds bills that base; 10 seconds bills twice that.
  int _getDurationBasedCost() {
    final maxDuration =
        (_selectedModelData?['maxDuration'] as num?)?.toInt() ?? 10;
    final d = _clampVideoGenDurationSeconds(_advancedSettings.videoDuration)
        .clamp(1, maxDuration);
    final base5 = _videoBaseCost5Sec(_selectedModelData);
    return max(0, ((base5 * d) / 5).round());
  }

  /// 5-second price from the model map in tool_config.json.
  int _videoBaseCost5Sec(Map<String, dynamic>? model) {
    final raw = model?['baseCost5Sec'] ?? model?['cost'] ?? model?['baseCost'];
    if (raw is num && raw > 0) return raw.round();
    if (_currentModelCost > 0) return _currentModelCost;
    return 15;
  }

  /// Per-variation add-on for resolution/video enhancement (VIP pays 0).
  int _enhancementUpscaleCreditsPerVariation() {
    if (isUpscaleFree()) return 0;
    final v = _currentModelUpscaleCost;
    if (_isVideoUpscalerTool) {
      // Dedicated video upscaler always performs upscaling.
      return v;
    }
    final isVideoGenTool =
        _tool.outputType == 'video' && !_isVideoUpscalerTool;
    if (isVideoGenTool) {
      return (_advancedSettings.enableInterpolate ||
              _advancedSettings.enableUpscale)
          ? v
          : 0;
    }
    // Main-card scale slider (e.g. Remove Background) bills via [_inputScaleUpscaleCreditsPerVariation].
    if (_hasScaleFactor) {
      return 0;
    }
    // Image tools bill the upscaler the user picked, not a flat add-on.
    if (_isUpscalerTool) return 0;
    return (_advancedSettings.upscaleOutput && _scaleFactor > 1)
        ? _selectedOutputUpscaleCost
        : 0;
  }

  /// Extra credits when the tool has a main [scale_factor] input and factor > 1 (VIP = 0).
  int _inputScaleUpscaleCreditsPerVariation() {
    if (isUpscaleFree()) return 0;
    if (!_hasScaleFactor) return 0;
    // Video tools use duration + enhancement billing; do not stack main slider upscale here.
    if (_tool.outputType != 'image') return 0;
    final raw = _inputs['scale_factor'];
    final d = raw is num ? raw.toDouble() : 1.0;
    if (d <= 1) return 0;
    return _currentModelUpscaleCost;
  }

  bool get _videoGenEnhancementEnabled =>
      _tool.outputType == 'video' &&
      !_isVideoUpscalerTool &&
      !_isComfyVideoWorker &&
      (_advancedSettings.enableInterpolate || _advancedSettings.enableUpscale);

  int _offerPercentForModelMap(Map<String, dynamic> model) {
    final sale = SaleService().state.value;
    if (sale.isActive && sale.discountPercent > 0) return sale.discountPercent;
    return model['offer'] as int? ?? 0;
  }

  int _baseGemCostForModelMap(Map<String, dynamic> model) {
    return model['baseCost'] as int? ?? model['cost'] as int? ?? 10;
  }

  /// Price shown on a model card. Video models use the 5-second config price.
  int _listedGemCostForModel(Map<String, dynamic> model) {
    if (_tool.outputType == 'video' && !_isVideoUpscalerTool) {
      return _videoBaseCost5Sec(model);
    }
    return _baseGemCostForModelMap(model);
  }

  /// Apply percent-off to credit totals. Plain [round] can leave small bases unchanged (e.g. 5 @ 10%).
  int _applyOfferDiscount(int baseCredits, int offerPercent) {
    if (offerPercent <= 0 || baseCredits <= 0) return baseCredits;
    final raw = baseCredits * (100 - offerPercent) / 100;
    var out = raw.round();
    if (out >= baseCredits && offerPercent < 100) {
      out = raw.floor();
    }
    return max(0, out);
  }

  /// Video upscaler: sum of per-5s units × base rate (bulk queue or single input).
  int _videoUpscalerUndiscountedCreditsTotal() {
    final baseCostPer5Sec = _currentModelCost;
    // During sequential bulk submit, pricing reflects the currently hydrated video only.
    if (_videoBulkSequentialActive) {
      if (_inputVideoDuration == null || _inputVideoDuration!.inSeconds <= 0) {
        return 0;
      }
      final units = (_inputVideoDuration!.inSeconds / 5).ceil().clamp(1, 10000);
      return baseCostPer5Sec * units;
    }
    if (_advancedSettings.bulkEditEnabled &&
        _supportsBulkVideoEdit &&
        _bulkVideoPaths.isNotEmpty) {
      int sumBase = 0;
      for (final d in _bulkVideoDurations) {
        if (d == null || d.inSeconds <= 0) return 0;
        final units = (d.inSeconds / 5).ceil().clamp(1, 10000);
        sumBase += baseCostPer5Sec * units;
      }
      return sumBase;
    }
    if (_inputVideoDuration == null || _inputVideoDuration!.inSeconds <= 0) {
      return 0;
    }
    final units = (_inputVideoDuration!.inSeconds / 5).ceil().clamp(1, 10000);
    return baseCostPer5Sec * units;
  }

  /// Calculate the total credit cost for this job
  /// VIP users get FREE upscale
  int _calculateTotalCost() {
    // Video upscaler billing: base cost per 5 seconds, always charged (VIP included).
    if (_isVideoUpscalerTool) {
      final offer = _currentModelOffer;
      final undiscounted = _videoUpscalerUndiscountedCreditsTotal();
      if (undiscounted <= 0) return 0;
      if (offer > 0) {
        return _applyOfferDiscount(undiscounted, offer);
      }
      return undiscounted;
    }

    // Animate image / create video: duration × the model's baseCost5Sec.
    final bool isVideoGenTool =
        _tool.outputType == 'video' && !_isVideoUpscalerTool;
    final baseCost =
        isVideoGenTool ? _getDurationBasedCost() : _listedGenerationCost();
    final offer = _currentModelOffer;
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());

    // Base cost per variation (includes enhancement/upscale add-on unless VIP)
    final int basePerVariation = baseCost +
        _enhancementUpscaleCreditsPerVariation() +
        _inputScaleUpscaleCreditsPerVariation();

    // Apply offer discount
    int costPerVariation = basePerVariation;
    if (offer > 0) {
      costPerVariation = _applyOfferDiscount(basePerVariation, offer);
    }

    // Calculate total bulk tasks (1 for normal, N for bulk edit)
    final int imageCount = _advancedSettings.bulkEditEnabled && _hasBulkInput
        ? _bulkActiveMediaCount
        : 1;

    // Total = cost per variation × variations × number of images
    // For bulk edit: each image gets processed with N variations
    return costPerVariation * variations * imageCount;
  }

  /// Format duration as MM:SS
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // Dynamic element cache
  List<Map<String, dynamic>> get _currentElements {
    List<Map<String, dynamic>> allElements;
    if (_tool.modes != null &&
        _selectedModeKey != null &&
        _tool.modes!.containsKey(_selectedModeKey)) {
      allElements = List<Map<String, dynamic>>.from(
          _tool.modes![_selectedModeKey]!["elements"] ?? []);
    } else {
      allElements =
          List<Map<String, dynamic>>.from(_tool.elements ?? []);
    }

    // Filter elements based on selected model for animate_image
    // ref_image / ref_video are DreamID reference media; audio is model-gated via input showForModels.
    if (_isAnimateImageTool) {
      final currentModelId = _selectedModelId ?? _tool.model;
      return allElements.where((e) {
        final inputRef = e['input_ref'] as String?;
        // Always show prompt and non-reference elements.
        if (inputRef == null || inputRef == 'prompt') {
          return true;
        }
        if (inputRef == 'init_image') {
          return true;
        }
        if (inputRef == 'ref_image') {
          return currentModelId == 'dreamid';
        }
        if (inputRef == 'ref_video') {
          if (currentModelId == 'dreamid') return true;
          if (currentModelId == _kCineRealAnimateModelId) {
            if (_advancedSettings.bulkEditEnabled && _supportsBulkImageEdit) {
              return false;
            }
            return !_cineRealSingleHasEndFrameBytes();
          }
          return false;
        }
        // Show all other elements (sliders, toggles, etc.)
        return true;
      }).toList();
    }

    // For video upscaler, keep enhancement controls only in Additional Settings.
    if (_isVideoUpscalerTool) {
      const hiddenMainRefs = <String>{
        'enable_interpolation',
        'target_fps',
        'enable_upscaling',
        'upscale_factor',
        'postprocess_interpolate_first',
      };
      return allElements.where((e) {
        final inputRef = e['input_ref'] as String?;
        return inputRef == null || !hiddenMainRefs.contains(inputRef);
      }).toList();
    }

    if (_isMusicTool) {
      const settingsOnly = {
        'vocals',
        'duration',
        'bpm',
        'key_scale',
        'time_signature',
        'vocal_language',
        'lyrics_optimizer',
        'strength',
        'repaint_start',
        'repaint_end',
      };
      return allElements.where((e) {
        final inputRef = e['input_ref'] as String?;
        return inputRef == null || !settingsOnly.contains(inputRef);
      }).toList();
    }

    // Image upscaler: scale + per-model toggles live in Additional Settings only.
    if (_isUpscalerTool) {
      const hiddenMainRefs = <String>{
        'scale_factor',
        'upscale_factor',
        'enhance_details',
        'realism',
        'face_enhance',
        'mode',
        'bg_model',
        'enhance_faces',
      };
      return allElements.where((e) {
        final inputRef = e['input_ref'] as String?;
        return inputRef == null || !hiddenMainRefs.contains(inputRef);
      }).toList();
    }

    return allElements;
  }

  bool get _hasPrompt => _tool.inputs.any((i) => i['id'] == 'prompt');
  bool get _hasScaleFactor =>
      _tool.inputs.any((i) => i['id'] == 'scale_factor');

  /// Returns the effective input config for a given base input id.
  ///
  /// Some models override UI behavior (label/max) via `inputOverrides` in tool_config.json
  /// (e.g. `qwen_image_edit_2509` supports up to 3 images). We apply those overrides
  /// to the base input while keeping the *storage id* unchanged (so elements using
  /// `input_ref: "init_image"` keep working).
  Map<String, dynamic> _effectiveInputConfig(String baseId) {
    final base = Map<String, dynamic>.from(
      _tool.inputs
          .firstWhere((i) => i["id"] == baseId, orElse: () => {}),
    );

    try {
      final Map<String, dynamic>? overridesRoot = (_isCineRealAnimateModel &&
              _isCineRealFlf2vMode)
          ? (_selectedModelData?['inputOverridesFlf2v']
                  as Map<String, dynamic>? ??
              _selectedModelData?['inputOverrides'] as Map<String, dynamic>?)
          : _selectedModelData?['inputOverrides'] as Map<String, dynamic>?;
      final o = overridesRoot != null ? overridesRoot[baseId] : null;
      if (o is Map) {
        // Apply only UI/selection behavior overrides; keep the actual id stable.
        if (o['label'] != null) base['label'] = o['label'];
        if (o['max'] != null) base['max'] = o['max'];
        if (o['min'] != null) base['min'] = o['min'];
        if (o['hintExamples'] != null) base['hintExamples'] = o['hintExamples'];
        // Do NOT apply o['id'] here (it is an alias used by templates/server).
      }
    } catch (_) {}

    return base;
  }

  /// Resolves model [inputOverrides] (e.g. max images) for attach / composer picks.
  ///
  /// Create Image and Create Video inject a photo input that the tool itself
  /// does not declare. Looking that id up returns an empty map, and saving
  /// under a null key throws. Keep the injected id in that case.
  Map<String, dynamic> _attachableImageInputResolved(Map<String, dynamic> raw) {
    final id = raw['id']?.toString();
    if (id == null || id.isEmpty) return Map<String, dynamic>.from(raw);
    final resolved = _effectiveInputConfig(id);
    if (resolved['id'] != null) return resolved;
    return {
      ...Map<String, dynamic>.from(raw),
      ...resolved,
      'id': id,
    };
  }

  /// Prefer [init_image] (or [_bulkPrimaryImageInputRef]) row from attach sheet list.
  Map<String, dynamic> _rawPrimaryImageAttachRow(
      List<Map<String, dynamic>> imageInputs) {
    final pref = _bulkPrimaryImageInputRef;
    if (pref != null) {
      for (final m in imageInputs) {
        if (m['id'] == pref) return Map<String, dynamic>.from(m);
      }
    }
    return Map<String, dynamic>.from(imageInputs.first);
  }

  int _initImageCountForRef(String ref) {
    final v = _inputs[ref];
    if (v is List) {
      return v.whereType<Uint8List>().where((b) => b.isNotEmpty).length;
    }
    if (v is Uint8List && v.isNotEmpty) return 1;
    return 0;
  }

  /// Append more init images in single mode (up to model [max], e.g. 3 for Vectra).
  Future<void> _pickMorePrimaryInitImages(Map<String, dynamic> input) async {
    final id = input['id'] as String?;
    if (id == null) return;
    final maxCount = (input['max'] ?? 1) as int;
    if (maxCount <= 1) return;
    final have = _initImageCountForRef(id);
    final room = maxCount - have;
    if (room <= 0) return;

    try {
      final List<XFile> files;
      if (room == 1) {
        final f = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
        files = f == null ? <XFile>[] : <XFile>[f];
      } else {
        files = await picker.pickMultiImage(imageQuality: 85, limit: room);
      }
      if (files.isEmpty) return;

      setState(() => _isProcessingImage = true);
      final extra = <Uint8List>[];
      for (final f in files) {
        if (extra.length >= room) break;
        extra.add(await _resizeImageSafe(await f.readAsBytes()));
      }
      if (!mounted) return;

      setState(() {
        List<Uint8List> list;
        final cur = _inputs[id];
        if (cur is List) {
          list = cur.whereType<Uint8List>().toList();
        } else if (cur is Uint8List && cur.isNotEmpty) {
          list = [cur];
        } else {
          list = [];
        }
        list.addAll(extra);
        if (list.length > maxCount) {
          list = list.sublist(0, maxCount);
        }
        _inputs[id] = list;
        _inputs['${id}_path'] = files.first.path;
        _inputs['mask_image'] = null;
        _isProcessingImage = false;
      });
    } catch (e) {
      debugPrint('❌ _pickMorePrimaryInitImages: $e');
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding images: $e')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _previewPageController = PageController();

    // Initialize advanced settings with defaults
    _advancedSettings = AdvancedSettings();

    // Auto-enable upscale for upscaler tools (always on, can't be toggled off)
    if (_isUpscalerTool) {
      _advancedSettings = _advancedSettings.copyWith(upscaleOutput: true);
      _upscaleEnabled = true;
    }

    // Initialize glow animation for generate button
    _glowAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Default mode
    if (_tool.modes != null && _tool.modes!.isNotEmpty) {
      _selectedModeKey = _tool.modes!.keys.first;
    }

    // Initialize selected model
    _initializeSelectedModel();
    _seedInputDefaults();
    if (_tool.capabilityId == 'create_music') {
      _inputs['music_mode'] = 'easy';
      _inputs['track_mode'] = 'create';
      _inputs['suno_kind'] = 'song';
      _inputs['vocals'] ??= true;
      _inputs['duration'] ??= 60;
      _inputs['suno_length'] ??= 120;
      _inputs['vocal_gender'] ??= 'auto';
      _inputs['variety'] ??= '1';
      _inputs['strength'] ??= 0.55;
      _inputs['repaint_start'] ??= 8;
      _inputs['repaint_end'] ??= 18;
      _inputs['lyrics_optimizer'] ??= true;
    }
    _syncFaceEnhancerFixedParams();
    if (_isVideoTool && !_isVideoUpscalerTool) {
      _advancedSettings = _advancedSettings.copyWith(aspectRatio: '9:16');
      _inputs['aspect_ratio'] = '9:16';
    }
    if (_isUpscalerTool) {
      _inputs['scale_factor'] ??= _scaleFactor;
    }

    // Video upscaler: upscale on; start in batch mode so multi-video + multi-select UX is default.
    if (_isVideoUpscalerTool) {
      _advancedSettings = _advancedSettings.copyWith(
        enableUpscale: true,
        bulkEditEnabled: true,
      );
    }

    if (widget.restoreJobId != null) {
      _activeJobId = widget.restoreJobId;
      _loading = true;
    }

    _promptFocusNode.addListener(_onComposerPromptVisualsChanged);
    _promptController.addListener(_onComposerPromptVisualsChanged);

    // Listen for ad-free status changes to hide/show native ads
    isAdFreeNotifier.addListener(_onAdFreeStatusChanged);

    // Listen for job list changes to update rate limit status in real-time
    jobListNotifier.addListener(_onJobListChanged);

    SaleService().state.addListener(_onSaleStateChanged);

    // Load styles and quick tags from config for OTA updates
    _loadStylesFromConfig();
    // Load LoRA adapters from local config as fallback for selector metadata
    _loadLoraAdaptersFromConfig();

    // Load user templates from local storage
    _loadUserTemplates();
    _loadFavoriteStyles();
    if (widget.pendingPrompt != null) _promptFilling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _applyLaunchPrefill();
      await _finishPendingPrompt();
      if (widget.focusPrompt && mounted && !_promptFilling) {
        _promptFocusNode.requestFocus();
      }
    });

    debugPrint("🔧 Config for ${_tool.model}");
    debugPrint("  title=${_tool.title}");
    debugPrint("  elements=${_tool.elements?.length}");
    debugPrint("  modes=${_tool.modes?.keys}");
    debugPrint("  models=${_tool.models?.length ?? 0}");

    // NOTE: do not warm up on-device inpaint model on page open; it can stall UI.
    // Session initializes lazily when user taps Generate.
  }

  void _onAdFreeStatusChanged() {
    // Rebuild to hide/show native ads when ad-free status changes
    if (mounted) setState(() {});
  }

  void _onJobListChanged() {
    // Rebuild to update rate limit status when jobs complete
    // This makes the "X slots free" hint update in real-time
    if (mounted) setState(() {});
  }

  void _onSaleStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadLoraAdaptersFromConfig() async {
    try {
      // Read from SharedPreferences cache (tool_config is fetched from CDN, not bundled as an asset)
      final prefs = await SharedPreferences.getInstance();
      final configStr = prefs.getString('cached_tool_config_v3');
      if (configStr == null || configStr.isEmpty) {
        debugPrint('⚠️ No cached tool_config found for LoRA adapters');
        return;
      }
      final config = jsonDecode(configStr) as Map<String, dynamic>;
      final capabilities =
          (config['capabilities'] as List<dynamic>?) ?? const [];
      for (final cap in capabilities) {
        final models =
            (cap as Map<String, dynamic>)['models'] as List<dynamic>? ??
                const [];
        for (final model in models) {
          final modelMap = model as Map<String, dynamic>;
          final modelId = modelMap['id']?.toString();
          if (modelId == null || modelId.isEmpty) continue;
          final adapters = (modelMap['loraAdapters'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList();
          if (adapters != null && adapters.isNotEmpty) {
            _loraAdaptersByModel[modelId] = adapters;
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load LoRA adapters fallback: $e');
    }
  }

  /// Load styles and quick tags from cached tool_config for OTA updates
  Future<void> _loadStylesFromConfig() async {
    try {
      // Read from SharedPreferences cache (tool_config is fetched from CDN, not bundled as an asset)
      final prefs = await SharedPreferences.getInstance();
      final configStr = prefs.getString('cached_tool_config_v3');
      if (configStr == null || configStr.isEmpty) {
        debugPrint('⚠️ No cached tool_config found for styles/quick tags');
        return;
      }
      final config = jsonDecode(configStr) as Map<String, dynamic>;

      // Load style presets
      final stylePresetsConfig =
          config['stylePresets'] as Map<String, dynamic>?;
      if (stylePresetsConfig != null) {
        final categories = (stylePresetsConfig['categories'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList();
        final presets = (stylePresetsConfig['presets'] as List<dynamic>?)
            ?.map((e) => StylePreset.fromJson(e as Map<String, dynamic>))
            .toList();

        if (categories != null && categories.isNotEmpty) {
          _configStyleCategories = categories;
        }
        if (presets != null && presets.isNotEmpty) {
          _configStyles = presets;
        }
      }

      // Load quick tags
      final quickTagsConfig = config['quickTags'] as List<dynamic>?;
      if (quickTagsConfig != null && quickTagsConfig.isNotEmpty) {
        _configQuickTags = quickTagsConfig
            .map((e) => PromptChip.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      if (mounted) setState(_restoreSelectedStyle);

      debugPrint(
          '✅ Loaded ${_configStyles?.length ?? 0} styles, ${_configQuickTags?.length ?? 0} quick tags from config');
    } catch (e) {
      debugPrint('⚠️ Failed to load styles from config, using fallbacks: $e');
      // Fallbacks are already set as the hardcoded constants
    }
  }

  /// Get the current styles list (config-loaded or fallback)
  List<StylePreset> get _currentStyles => _configStyles ?? allStylePresets;

  /// Capability used to choose image presets vs video presets.
  String get _styleCapabilityId {
    final id = _tool.capabilityId;
    if (id != null && id.isNotEmpty) return id;
    if (_tool.outputType == 'video') {
      return _isAnimateImageTool ? 'animate_image' : 'create_video';
    }
    return _isEditImageTool ? 'edit_image' : 'create_image';
  }

  /// Presets that belong on the open tool.
  List<StylePreset> get _stylesForThisTool {
    final capabilityId = _styleCapabilityId;
    return _currentStyles
        .where((style) => style.capabilities.contains(capabilityId))
        .toList();
  }

  /// Get the current style categories (config-loaded or fallback)
  List<String> get _currentStyleCategories =>
      _configStyleCategories ?? styleCategories;

  /// Category chips that have a preset on this tool. All and Favorites stay.
  List<String> get _visibleStyleCategories {
    final usedCategories =
        _stylesForThisTool.map((style) => style.category).toSet();
    return _currentStyleCategories.where((category) {
      return category == 'All' ||
          category == 'Favorites' ||
          usedCategories.contains(category);
    }).toList();
  }

  /// Load user templates from SharedPreferences
  Future<void> _loadUserTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final templatesJson = prefs.getString('user_templates');
      if (templatesJson != null) {
        final decoded = jsonDecode(templatesJson) as List<dynamic>;
        _userTemplates = decoded
            .map((e) => UserTemplate.fromJson(e as Map<String, dynamic>))
            .toList();
        // Sort by last used (most recent first), then by created date
        _userTemplates.sort((a, b) {
          if (a.lastUsed != null && b.lastUsed != null) {
            return b.lastUsed!.compareTo(a.lastUsed!);
          }
          if (a.lastUsed != null) return -1;
          if (b.lastUsed != null) return 1;
          return b.createdAt.compareTo(a.createdAt);
        });
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load user templates: $e');
    }
  }

  /// Save user templates to SharedPreferences
  Future<void> _saveUserTemplates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final templatesJson =
          jsonEncode(_userTemplates.map((t) => t.toJson()).toList());
      await prefs.setString('user_templates', templatesJson);
    } catch (e) {
      debugPrint('⚠️ Failed to save user templates: $e');
    }
  }

  /// Save current settings as a template
  Future<void> _saveCurrentAsTemplate() async {
    final cs = Theme.of(context).colorScheme;
    final nameController = TextEditingController();
    bool confirmed = false;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Save Template',
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
        ),
        content: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Save your current prompt and settings as a reusable template.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Template Name',
                    hintText: 'e.g., My Portrait Style',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: _clearTextButton(
                      visible: nameController.text.isNotEmpty,
                      onPressed: () {
                        nameController.clear();
                        setDialogState(() {});
                      },
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () {
              if (nameController.text.trim().isNotEmpty) {
                confirmed = true;
                Navigator.pop(context);
              }
            },
            child: Text('Save',
                style:
                    TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (!confirmed || nameController.text.trim().isEmpty) return;

    final template = UserTemplate(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: nameController.text.trim(),
      prompt: _promptController.text,
      modelId: _selectedModelId,
      capabilityId: _tool.capabilityId,
      toolTitle: _tool.title,
      settings: _advancedSettings,
      createdAt: DateTime.now(),
    );

    _userTemplates.insert(0, template);
    await _saveUserTemplates();

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Template "${template.name}" saved!'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Filter template settings to only include compatible settings for current tool category
  AdvancedSettings _filterCompatibleSettings(
      AdvancedSettings templateSettings) {
    // Start with current settings as base
    AdvancedSettings filtered = _advancedSettings.copyWith();

    // Always apply these (universal settings)
    filtered = filtered.copyWith(
      enhancePrompt: templateSettings.enhancePrompt,
      quality: templateSettings.quality,
    );

    // Upscale: Only apply if not a video tool (upscale is hidden for video tools)
    if (!_isVideoTool) {
      filtered =
          filtered.copyWith(upscaleOutput: templateSettings.upscaleOutput);
    } else {
      // For video tools, disable upscale (not available)
      filtered = filtered.copyWith(upscaleOutput: false);
    }

    // Aspect Ratio: Only apply if not hidden for this tool category
    if (!_isEditImageTool &&
        !_isExpandSceneTool &&
        !_isUpscalerTool &&
        !_isInpaintEraseTool &&
        !_isRemoveBackgroundTool) {
      filtered = filtered.copyWith(
        aspectRatio:
            AdvancedSettings.normalizeAspectRatio(templateSettings.aspectRatio),
      );
    }

    // Variations: Apply for both image and video tools
    if (_tool.outputType == 'image' ||
        _tool.outputType == 'video') {
      filtered = filtered.copyWith(variations: templateSettings.variations);
    }

    // Video Duration: Only apply for video tools (5s steps when model allows)
    if (_tool.outputType == 'video') {
      final td = _clampVideoGenDurationSeconds(templateSettings.videoDuration);
      filtered = filtered.copyWith(videoDuration: td);
      // Video enhancement settings (I2V/T2V vs dedicated video upscaler tool).
      // Only the AI Tools "video upscaler" forces enableUpscale on; other video
      // tools keep the saved template values.
      filtered = filtered.copyWith(
        enableInterpolate: templateSettings.enableInterpolate,
        interpolateFps: migrateLegacyInterpolateStorageValue(
          templateSettings.interpolateFps,
        ),
        enableUpscale:
            _isVideoUpscalerTool ? true : templateSettings.enableUpscale,
        upscaleFactor: templateSettings.upscaleFactor,
      );
    }

    // LoRA adapter: Only apply for qwen_image_edit_2511_rapid_aio
    final currentModel = _selectedModelId ?? _tool.model;
    if (currentModel == 'qwen_image_edit_2511_rapid_aio') {
      filtered = filtered.copyWith(loraAdapter: templateSettings.loraAdapter);
    }

    if (currentModel == _kCineRealAnimateModelId) {
      var mode = templateSettings.cineRealMotionMode;
      if (mode != 'flf2v' && mode != 'i2v') mode = 'i2v';
      filtered = filtered.copyWith(cineRealMotionMode: mode);
    }

    // Bulk Edit: Only apply when the current tool supports it.
    if (_supportsBulkEdit) {
      filtered =
          filtered.copyWith(bulkEditEnabled: templateSettings.bulkEditEnabled);
    } else {
      filtered = filtered.copyWith(bulkEditEnabled: false);
    }

    return filtered;
  }

  /// Apply a template to current settings (only compatible settings are applied)
  void _applyTemplate(UserTemplate template) {
    setState(() {
      _promptController.text = template.prompt;
      if (template.modelId != null && _tool.hasMultipleModels) {
        var mid = template.modelId!;
        if (mid == 'ltx2_3_flf2v' ||
            mid == 'ltx2_3_i2v_distilled' ||
            mid == _kLegacyCineRealAnimateModelId ||
            mid == 'ltx25_int8_i2v' ||
            mid == 'ltx25_int8_flf2v') {
          mid = _kCineRealAnimateModelId;
        }
        if (mid == _kLegacyWanI2vModelId ||
            mid == 'wan_22_fp8_lightx2v_t2v') {
          mid = _kCinemotionProModelId;
        }
        if (mid == 'ltx2_3_t2v') {
          mid = 'ltx25_int8_t2v';
        }
        _selectedModelId = mid;
        _selectedModelData = _tool.models?.firstWhere(
          (m) => m['id'] == mid,
          orElse: () => _tool.models!.first,
        );
      }

      // Filter template settings to only apply compatible settings
      var filteredSettings = _filterCompatibleSettings(template.settings);
      if (template.modelId == 'ltx2_3_flf2v' ||
          template.modelId == 'ltx25_int8_flf2v') {
        filteredSettings =
            filteredSettings.copyWith(cineRealMotionMode: 'flf2v');
      }
      _advancedSettings = filteredSettings;
      if (_isVideoTool && !_isVideoUpscalerTool) {
        _inputs['aspect_ratio'] = filteredSettings.aspectRatio;
      }

      // Update upscale-related state (only if upscale is compatible)
      if (!_isVideoTool) {
        _upscaleEnabled = filteredSettings.upscaleOutput;
        _scaleFactor = filteredSettings.upscaleOutput ? 2 : 1;
        _inputs["scale_factor"] =
            filteredSettings.upscaleOutput ? _scaleFactor : 1.0;
        _syncFaceEnhancerFixedParams();
      } else {
        // For video tools, ensure upscale is disabled
        _upscaleEnabled = false;
        _scaleFactor = 1;
        _inputs["scale_factor"] = 1.0;
      }
    });

    // Update last used
    final index = _userTemplates.indexWhere((t) => t.id == template.id);
    if (index != -1) {
      _userTemplates[index] = template.copyWith(lastUsed: DateTime.now());
      _saveUserTemplates();
    }
  }

  /// Delete a template
  Future<void> _deleteTemplate(UserTemplate template) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Delete Template?',
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete "${template.name}"?',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _userTemplates.removeWhere((t) => t.id == template.id);
      await _saveUserTemplates();
      if (mounted) setState(() {});
    }
  }

  /// Format template date
  String _formatTemplateDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  /// Initialize the selected model from config
  void _initializeSelectedModel() {
    if (_tool.models != null && _tool.models!.isNotEmpty) {
      // Filter to only enabled models
      final enabledModels = _tool.models!.where((m) {
        final enabled = m['enabled'];
        return enabled == null ||
            enabled == true; // Default to enabled if not specified
      }).toList();

      if (enabledModels.isEmpty) return;

      // Use default model if specified, otherwise first enabled model
      final defaultId = _tool.defaultModel ?? _tool.model;
      _selectedModelData = enabledModels.firstWhere(
        (m) =>
            m['id'] == defaultId &&
            (m['enabled'] == null || m['enabled'] == true),
        orElse: () => enabledModels.first,
      );
      final resolvedId = _selectedModelData?['id']?.toString();
      _selectedModelId =
          (resolvedId != null && resolvedId.isNotEmpty) ? resolvedId : defaultId;

      // Clamp video duration (min 5s when model allows) for video generation tools
      if (_tool.outputType == 'video' &&
          _selectedModelData != null &&
          !_isVideoUpscalerTool) {
        final clamped =
            _clampVideoGenDurationSeconds(_advancedSettings.videoDuration);
        if (clamped != _advancedSettings.videoDuration) {
          _advancedSettings =
              _advancedSettings.copyWith(videoDuration: clamped);
        }
      }
    }
  }

  /// Defaults for choices that live in Additional Settings, so a job can
  /// submit before that sheet has been opened.
  void _seedInputDefaults() {
    for (final def in _tool.inputs) {
      if (def is! Map) continue;
      final id = def['id'] as String?;
      if (id == null || _inputs.containsKey(id)) continue;
      final type = def['type']?.toString();
      if (type == 'dropdown') {
        final options = _choiceOptions(Map<String, dynamic>.from(def));
        if (options.isEmpty) continue;
        final fallback = def['default']?.toString();
        final match = options.where((o) => o.value == fallback);
        _inputs[id] = match.isEmpty ? options.first.value : match.first.value;
      } else if (type == 'toggle') {
        _inputs[id] = def['default'] == true;
      }
    }
  }

  List<({String value, String label})> _choiceOptions(Map<String, dynamic> input) {
    final raw = input['options'];
    if (raw is! List) return const [];
    final out = <({String value, String label})>[];
    for (final opt in raw) {
      if (opt is Map) {
        final value = '${opt['value'] ?? opt['id'] ?? ''}'.trim();
        if (value.isEmpty) continue;
        final label = '${opt['label'] ?? value}'.trim();
        out.add((value: value, label: label.isEmpty ? value : label));
      } else {
        final value = '$opt'.trim();
        if (value.isEmpty) continue;
        out.add((value: value, label: value));
      }
    }
    return out;
  }

  /// Select a different model
  void _selectModel(Map<String, dynamic> model) {
    setState(() {
      final prevId = _selectedModelId;
      final nextId = model['id'] as String;
      _selectedModelId = nextId;
      _selectedModelData = model;

      if (_tool.outputType == 'image' && !_isFlashOrCanvasModel) {
        final ratio = _inputs['aspect_ratio']?.toString() ?? '';
        if (AdvancedSettings.kFlashCanvasAspectRatioOptions.contains(ratio) &&
            !AdvancedSettings.kAdvancedAspectRatioOptions.contains(ratio)) {
          _inputs['aspect_ratio'] = '1:1';
          _advancedSettings = _advancedSettings.copyWith(aspectRatio: '1:1');
        }
      }

      if (prevId == _kCineRealAnimateModelId &&
          nextId != _kCineRealAnimateModelId) {
        _advancedSettings =
            _advancedSettings.copyWith(cineRealMotionMode: 'i2v');
      }

      if (nextId != 'qwen2_1_i2i') {
        _inputs['background'] = 'opaque';
      }

      if (_isAnimateImageTool) {
        const endFrameModels = {
          _kCineRealAnimateModelId,
          _kLegacyCineRealAnimateModelId,
          _kCinemotionProModelId,
          _kLegacyWanI2vModelId,
        };
        if (!endFrameModels.contains(nextId)) {
          _inputs.remove('last_frame_image');
          _inputs.remove('last_frame_image_path');
        }
      }

      for (final def in _tool.inputs) {
        if (def is! Map) continue;
        final t = def['type']?.toString();
        final sid = def['id'] as String?;
        if (sid == null) continue;
        final sfm = def['showForModels'] as List<dynamic>?;
        if (sfm == null || sfm.isEmpty) continue;
        if (sfm.contains(nextId)) continue;
        if (t == 'audio_upload') {
          _inputs.remove(sid);
          _inputs.remove('${sid}_path');
          _inputs.remove('${sid}_name');
          _inputs.remove('${sid}_mime');
          _inputs.remove('${sid}_duration');
        } else if (t == 'video' || t == 'video_upload') {
          final p = _inputs['${sid}_path'] as String?;
          if (p != null) {
            final c = _userVideoControllers.remove(p);
            c?.dispose();
          }
          _inputs.remove(sid);
          _inputs.remove('${sid}_path');
          _inputs.remove('${sid}_bytes');
          _inputVideoDuration = null;
        }
      }

      // Clamp video duration when switching models (5s steps when model allows)
      if (_tool.outputType == 'video' && !_isVideoUpscalerTool) {
        final clamped =
            _clampVideoGenDurationSeconds(_advancedSettings.videoDuration);
        if (clamped != _advancedSettings.videoDuration) {
          _advancedSettings =
              _advancedSettings.copyWith(videoDuration: clamped);
        }
      }
      if (_isVideoUpscalerTool) {
        _advancedSettings = _advancedSettings.copyWith(enableUpscale: true);
      }
      _syncFaceEnhancerFixedParams();
    });
    if (!_imageStudioSwitching) _rememberImageStudioFamily();
    // Force rebuild of advanced settings sheet if open
    // The StatefulBuilder will pick up the new _selectedModelData
  }

  /// 2K Kala Imagine costs twice the 1K price. Other models are unchanged.
  int _withQwenResolutionPrice(int base) {
    final model = _selectedModelId ?? _tool.model;
    if (model == 'qwen2_1_i2i' && _inputs['resolution'] == '2K') {
      return base * 2;
    }
    return base;
  }

  String get _qwenResolution =>
      _inputs['resolution'] == '2K' ? '2K' : '1K';

  /// Get the current model's cost
  int get _currentModelCost {
    if (_isSunoV6) {
      final action = _sunoSounds
          ? 'sounds'
          : _sunoExtend
              ? 'upload_extend'
              : _sunoMashup
                  ? 'mashup'
                  : 'song';
      return sunoV6CreditCost(action: action);
    }
    return _selectedModelData?['baseCost'] as int? ??
        _selectedModelData?['cost'] as int? ??
        _tool.cost;
  }

  /// Get the current model's upscale cost
  int get _currentModelUpscaleCost =>
      _selectedModelData?['costUpscale'] as int? ?? _tool.costUpscale;

  /// Extra upscale pass the user can add from Additional Settings.
  /// Ids stay internal. Names are the ones shown in the app.
  static const List<Map<String, Object>> _outputUpscaleChoices = [
    {
      'id': 'recraft_crisp_upscale',
      'name': 'Crisp Upscale',
      'cost': 5,
      'blurb': 'Sharper, same size',
    },
    {
      'id': 'realesrgan_upscale',
      'name': 'General Upscale',
      'cost': 5,
      'blurb': 'Clean 2× enlarge',
    },
  ];

  String get _selectedOutputUpscaleId {
    final raw = _inputs['upscale_model'];
    if (raw is String &&
        _outputUpscaleChoices.any((choice) => choice['id'] == raw)) {
      return raw;
    }
    return 'recraft_crisp_upscale';
  }

  Map<String, Object> get _selectedOutputUpscale {
    return _outputUpscaleChoices.firstWhere(
      (choice) => choice['id'] == _selectedOutputUpscaleId,
      orElse: () => _outputUpscaleChoices.first,
    );
  }

  int get _selectedOutputUpscaleCost =>
      (_selectedOutputUpscale['cost'] as int?) ?? 5;

  /// Half-up for positive credit math (12.5 → 13).
  int _halfUp(num value) {
    if (value.isNaN || value.isInfinite || value <= 0) return 0;
    return (value + 0.5).floor();
  }

  /// Listed price for the generate button.
  /// Speech is 15 credits a minute, estimated at 600 characters of the script.
  /// Kala SongFlow scales with the chosen length. Kala BeatWave stays a flat price.
  int _listedGenerationCost() {
    final per60 = _selectedModelData?['costPer60Sec'];
    final charsPerMin = _selectedModelData?['speechCharsPerMin'];
    if (charsPerMin is num &&
        charsPerMin > 0 &&
        per60 is num &&
        per60 > 0) {
      final chars = _promptController.text.trim().length;
      if (chars <= 0) return _halfUp(per60);
      return max(1, _halfUp((per60 * chars) / charsPerMin));
    }
    if (per60 is num && per60 > 0) {
      final raw = _inputs['duration'];
      final seconds = raw is num
          ? raw.round()
          : int.tryParse('${raw ?? ''}') ?? 60;
      final maxSeconds =
          (_selectedModelData?['maxDuration'] as num?)?.toInt() ?? 240;
      final clamped = seconds.clamp(30, maxSeconds);
      return max(1, _halfUp((per60 * clamped) / 60));
    }
    return _withQwenResolutionPrice(_currentModelCost);
  }

  /// Get the current model's effective discount (sale overrides per-model offer)
  int get _currentModelOffer {
    final sale = SaleService().state.value;
    if (sale.isActive && sale.discountPercent > 0) {
      return sale.discountPercent;
    }
    return _selectedModelData?['offer'] as int? ?? _tool.offer;
  }

  /// Optional per-model route flag for backend external API path.
  /// If null, backend decides using its model route policy/defaults.
  bool? get _currentModelUseExternalApi {
    final dynamic raw = _selectedModelData?['useExternalApi'] ??
        _selectedModelData?['use_external_api'];
    if (raw is bool) return raw;
    return null;
  }

  // -------- Prompt Helper Chips --------
  // Note: _appendChipToPrompt removed - quickTags feature deprecated

  // -------- Style Library --------

  /// Get styles filtered by category
  List<StylePreset> _getStylesByCategory(String category) {
    final styles = _stylesForThisTool;
    if (category == 'All') {
      return styles;
    }
    if (category == 'Favorites') {
      return styles.where((s) => _favoriteStyles.contains(s.id)).toList();
    }
    return styles.where((s) => s.category == category).toList();
  }

  /// Select a style and apply its snippet
  void _selectStyle(StylePreset style) {
    setState(() {
      // If same style is selected, deselect it
      if (_selectedStyle?.id == style.id) {
        _removeStyleFromPrompt(_selectedStyle!);
        _selectedStyle = null;
        return;
      }

      // Remove previous style snippet if any
      if (_selectedStyle != null) {
        _removeStyleFromPrompt(_selectedStyle!);
      }

      // Apply new style
      _selectedStyle = style;
      _appendStyleToPrompt(style);
    });
  }

  /// Append style snippet to prompt
  void _appendStyleToPrompt(StylePreset style) {
    final currentText = _promptController.text.trim();
    String newText;

    if (currentText.isEmpty) {
      newText = style.promptSnippet;
    } else if (currentText.endsWith(',')) {
      newText = '$currentText ${style.promptSnippet}';
    } else {
      newText = '$currentText, ${style.promptSnippet}';
    }

    _promptController.text = newText;
    _inputs['prompt'] = newText;
  }

  /// Remove style snippet from prompt
  void _removeStyleFromPrompt(StylePreset style) {
    final currentText = _promptController.text;
    final snippet = style.promptSnippet;

    // Try to remove the snippet with various separators
    String newText = currentText
        .replaceAll(', $snippet', '')
        .replaceAll('$snippet, ', '')
        .replaceAll(snippet, '')
        .trim();

    // Clean up any double commas or trailing commas
    newText = newText.replaceAll(', ,', ',').replaceAll(RegExp(r',\s*$'), '');

    _promptController.text = newText;
    _inputs['prompt'] = newText;
  }

  /// Toggle favorite status for a style
  void _toggleFavoriteStyle(String styleId) {
    setState(() {
      if (_favoriteStyles.contains(styleId)) {
        _favoriteStyles.remove(styleId);
      } else {
        _favoriteStyles.add(styleId);
      }
    });
    HapticFeedback.lightImpact();
    unawaited(saveFavoriteStyleIds(_favoriteStyles));
  }

  Future<void> _loadFavoriteStyles() async {
    final ids = await loadFavoriteStyleIds();
    if (!mounted) return;
    final known = _currentStyles.map((s) => s.id).toSet();
    setState(() {
      _favoriteStyles
        ..clear()
        ..addAll(ids.where(known.contains));
    });
  }

  Map<String, dynamic> _buildSettingsSnapshot({
    Map<String, List<String>>? mediaPaths,
  }) {
    final primary = _bulkPrimaryImageInputRef;
    final inputPaths = primary == null
        ? const <String>[]
        : (mediaPaths?[primary] ?? const <String>[]);
    return sanitizeSettingsSnapshot({
      'prompt': _promptController.text,
      'modelId': _selectedModelId ?? _tool.model,
      'aspectRatio': _advancedSettings.aspectRatio,
      'scaleFactor': _inputs['scale_factor'] ?? _advancedSettings.upscaleFactor,
      'variations': _advancedSettings.variations.clamp(1, getMaxVariations()),
      'upscaleEnabled': _upscaleEnabled ||
          _advancedSettings.upscaleOutput ||
          _advancedSettings.enableUpscale,
      'transparentBackground': _inputs['background'] == 'transparent',
      'outputResolution': _qwenResolution,
      'interpolateEnabled': _advancedSettings.enableInterpolate,
      'quality': _advancedSettings.quality,
      'videoDuration': _advancedSettings.videoDuration,
      'enhancePrompt': _advancedSettings.enhancePrompt,
      'enableUpscale': _advancedSettings.enableUpscale,
      'upscaleFactor': _advancedSettings.upscaleFactor,
      'interpolateFps': _advancedSettings.interpolateFps,
      'loraAdapter': _advancedSettings.loraAdapter,
      'cineRealMotionMode': _advancedSettings.cineRealMotionMode,
      'cfgScale': _advancedSettings.cfgScale,
      'bulkEditEnabled': _advancedSettings.bulkEditEnabled,
      if (_selectedStyle != null) 'styleId': _selectedStyle!.id,
      if (inputPaths.isNotEmpty) 'inputPaths': inputPaths,
      if (mediaPaths != null && mediaPaths.isNotEmpty) 'mediaPaths': mediaPaths,
      if (_textSnapshot('lyrics') != null) 'lyrics': _textSnapshot('lyrics'),
      if (_textSnapshot('negative_prompt') != null)
        'negativePrompt': _textSnapshot('negative_prompt'),
      if (_inputs['vocals'] is bool) 'vocals': _inputs['vocals'],
      if (_inputs['music_mode'] != null) 'musicMode': _inputs['music_mode'],
      if (_isSunoV6) 'musicAction': _inputs['action'] ?? (_sunoSounds
          ? 'sounds'
          : _sunoExtend
              ? 'upload_extend'
              : _sunoMashup
                  ? 'mashup'
                  : 'song'),
      if (_inputs['track_mode'] != null) 'trackMode': _inputs['track_mode'],
      if (_inputs['duration'] is num) 'musicDuration': _inputs['duration'],
      if (_inputs['bpm'] != null) 'bpm': _inputs['bpm'],
      if (_inputs['key_scale'] != null) 'keyScale': _inputs['key_scale'],
    });
  }

  String? _textSnapshot(String id) {
    final value = _inputs[id];
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  String? get _typedPrompt {
    final typed = _promptController.text.trim();
    if (typed.isNotEmpty) return typed;
    final stored = _inputs['prompt'];
    if (stored is String && stored.trim().isNotEmpty) return stored.trim();
    return null;
  }

  List<Uint8List> _bytesOf(dynamic raw) {
    if (raw is Uint8List && raw.isNotEmpty) return [raw];
    if (raw is List) {
      return raw.whereType<Uint8List>().where((b) => b.isNotEmpty).toList();
    }
    return const [];
  }

  List<String> _pathsOf(dynamic raw) {
    if (raw is String && raw.isNotEmpty && File(raw).existsSync()) return [raw];
    if (raw is List) {
      return raw
          .whereType<String>()
          .where((p) => p.isNotEmpty && File(p).existsSync())
          .toList();
    }
    return const [];
  }

  Future<Map<String, List<String>>> _mediaPathsFromInputs() async {
    final media = <String, List<String>>{};
    for (final raw in _tool.inputs) {
      if (raw is! Map) continue;
      final id = raw['id'] as String?;
      final type = raw['type'] as String?;
      if (id == null || type == null) continue;
      if (type != 'image' &&
          type != 'image_upload' &&
          type != 'video' &&
          type != 'video_upload' &&
          type != 'audio_upload' &&
          type != 'file_upload') {
        continue;
      }
      final bytes = _bytesOf(_inputs[id]);
      if (bytes.isNotEmpty) {
        final ext = type.startsWith('video')
            ? 'mp4'
            : (type == 'audio_upload' ? 'm4a' : 'jpg');
        media[id] = await FileService.writeLaunchCopies(
          bytes,
          prefix: 'launch_$id',
          extension: ext,
        );
        continue;
      }
      final paths = _pathsOf(_inputs['${id}_path']);
      if (paths.isNotEmpty) media[id] = paths;
    }
    final mask = _bytesOf(_inputs['mask_image']);
    if (mask.isNotEmpty && media['mask_image'] == null) {
      media['mask_image'] = await FileService.writeLaunchCopies(
        mask,
        prefix: 'launch_mask',
        extension: 'png',
      );
    }
    return media;
  }

  Future<
      ({
        String? primaryPath,
        List<String> bulkPrimaryPaths,
        List<Map<String, List<String>>> perJobMedia,
      })> _saveLaunchMedia({required bool isBulkEdit}) async {
    try {
      final shared = await _mediaPathsFromInputs();
      if (isBulkEdit && _bulkImageJobs.isNotEmpty) {
        final primary = _bulkPrimaryImageInputRef ?? 'init_image';
        final groups = <Map<String, List<String>>>[];
        final thumbs = <String>[];
        for (final jobImages in _bulkImageJobs) {
          final paths = await FileService.writeLaunchCopies(
            jobImages,
            prefix: 'launch_bulk',
          );
          if (paths.isEmpty) continue;
          thumbs.add(paths.first);
          groups.add({
            for (final entry in shared.entries)
              if (entry.key != primary) entry.key: entry.value,
            primary: paths,
          });
        }
        return (
          primaryPath: thumbs.isEmpty ? null : thumbs.first,
          bulkPrimaryPaths: thumbs,
          perJobMedia: groups,
        );
      }
      if (_supportsBulkVideoEdit && _bulkVideoPaths.isNotEmpty) {
        final videoId = _bulkPrimaryVideoInputRef ?? 'input_video';
        final groups = <Map<String, List<String>>>[];
        final thumbs = <String>[];
        for (final path in _bulkVideoPaths) {
          if (!File(path).existsSync()) continue;
          thumbs.add(path);
          groups.add({
            for (final entry in shared.entries)
              if (entry.key != videoId) entry.key: entry.value,
            videoId: [path],
          });
        }
        return (
          primaryPath: thumbs.isEmpty ? null : thumbs.first,
          bulkPrimaryPaths: thumbs,
          perJobMedia: groups,
        );
      }
      final primary = _bulkPrimaryImageInputRef;
      final primaryPaths = primary == null
          ? const <String>[]
          : (shared[primary] ?? const <String>[]);
      return (
        primaryPath: primaryPaths.isEmpty ? null : primaryPaths.first,
        bulkPrimaryPaths: const <String>[],
        perJobMedia: [shared],
      );
    } catch (e) {
      debugPrint('⚠️ Could not save launch media: $e');
      return (
        primaryPath: null,
        bulkPrimaryPaths: const <String>[],
        perJobMedia: const <Map<String, List<String>>>[],
      );
    }
  }

  Map<String, dynamic> _snapshotForSaved(
    ({
      String? primaryPath,
      List<String> bulkPrimaryPaths,
      List<Map<String, List<String>>> perJobMedia,
    }) saved,
    int imageIndex,
  ) {
    if (saved.perJobMedia.isEmpty) return _buildSettingsSnapshot();
    final index = imageIndex.clamp(0, saved.perJobMedia.length - 1);
    return _buildSettingsSnapshot(mediaPaths: saved.perJobMedia[index]);
  }

  void _restoreSelectedStyle() {
    final id = widget.initialSettings?['styleId'] as String?;
    if (id == null || id.isEmpty) return;
    for (final style in _currentStyles) {
      if (style.id == id) {
        _selectedStyle = style;
        return;
      }
    }
  }

  int _snapInt(dynamic value, int fallback) =>
      value is num ? value.toInt() : fallback;

  double _snapDouble(dynamic value, double fallback) =>
      value is num ? value.toDouble() : fallback;

  String? _inputTypeOf(String id) {
    for (final raw in _tool.inputs) {
      if (raw is Map && raw['id'] == id) return raw['type'] as String?;
    }
    return null;
  }

  String? _firstAudioPath(List<String> paths) {
    const extensions = {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'};
    for (final path in paths) {
      final ext = path.split('.').last.toLowerCase();
      if (extensions.contains(ext) && File(path).existsSync()) return path;
    }
    return null;
  }

  bool _isImageLaunchPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  Future<void> _loadImagePaths(String id, List<String> paths,
      {bool asMask = false}) async {
    final bytes = <Uint8List>[];
    for (final path in paths) {
      try {
        final raw = await File(path).readAsBytes();
        bytes.add(asMask ? raw : await _resizeImageSafe(raw));
      } catch (_) {}
    }
    if (bytes.isEmpty || !mounted) return;
    setState(() {
      _inputs[id] = asMask && bytes.length == 1 ? bytes.first : bytes;
      if (!asMask) _inputs['${id}_path'] = paths.first;
    });
  }

  Future<bool> _restoreSavedMedia(dynamic raw) async {
    if (raw is! Map) return false;
    final known = <String>{
      for (final input in _tool.inputs)
        if (input is Map && input['id'] is String) input['id'] as String,
    };
    final leftoverImages = <String>[];
    var loaded = false;
    for (final entry in raw.entries) {
      final id = entry.key.toString();
      final paths = _pathsOf(entry.value);
      if (paths.isEmpty) continue;
      final type = _inputTypeOf(id);
      final knownInput = known.contains(id) || id == 'mask_image';
      if (!knownInput) {
        leftoverImages.addAll(paths.where(_isImageLaunchPath));
        continue;
      }
      if (id == 'mask_image' ||
          type == 'image' ||
          type == 'image_upload') {
        await _loadImagePaths(id, paths, asMask: id == 'mask_image');
        if (_inputs[id] != null) loaded = true;
      } else if (type == 'video' || type == 'video_upload') {
        if (_supportsBulkVideoEdit && id == _bulkPrimaryVideoInputRef) {
          for (final path in paths) {
            try {
              await _appendBulkVideoFromPath(path);
            } catch (e) {
              debugPrint('Could not restore video $path: $e');
            }
          }
          loaded = _bulkVideoPaths.isNotEmpty;
        }
        if (!mounted || paths.isEmpty) continue;
        setState(() => _inputs['${id}_path'] = paths.first);
        loaded = true;
      } else {
        try {
          final bytes = await File(paths.first).readAsBytes();
          if (!mounted) continue;
          setState(() => _inputs[id] = bytes);
          loaded = true;
        } catch (_) {}
      }
    }
    final primary = _bulkPrimaryImageInputRef;
    if (primary != null && _inputs[primary] == null && leftoverImages.isNotEmpty) {
      await _loadImagePaths(primary, leftoverImages);
      loaded = _inputs[primary] != null;
    }
    return loaded;
  }

  Future<void> _finishPendingPrompt() async {
    final pending = widget.pendingPrompt;
    if (pending == null) return;
    if (mounted) setState(() => _promptFilling = true);
    try {
      final written = await pending;
      if (!mounted) return;
      final text = written?.trim() ?? '';
      if (text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not write the cover prompt. Try again.'),
          ),
        );
        return;
      }
      setState(() {
        _promptController.text = text;
        _inputs['prompt'] = text;
      });
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().toLowerCase();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.contains('sign in')
                ? 'Sign in to write a cover prompt.'
                : 'Could not write the cover prompt. Try again.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _promptFilling = false);
    }
  }

  Future<void> _applyLaunchPrefill() async {
    if (!mounted) return;
    final snapshot = widget.initialSettings;
    if (snapshot != null) {
      final aspect = snapshot['aspectRatio'] as String?;
      final quality = snapshot['quality'] as String?;
      final duration = snapshot['videoDuration'];
      final upscale = snapshot['upscaleEnabled'] == true ||
          snapshot['enableUpscale'] == true;
      final interpolate = snapshot['interpolateEnabled'] == true;
      final modelId = snapshot['modelId'] as String?;
      final variations = snapshot['variations'];
      setState(() {
        _advancedSettings = _advancedSettings.copyWith(
          aspectRatio: aspect == null
              ? null
              : AdvancedSettings.normalizeAspectRatio(aspect),
          quality: quality,
          videoDuration: duration is num ? duration.toInt() : null,
          enhancePrompt: snapshot.containsKey('enhancePrompt')
              ? snapshot['enhancePrompt'] == true
              : null,
          enableInterpolate: snapshot.containsKey('interpolateEnabled')
              ? interpolate
              : null,
          interpolateFps: snapshot.containsKey('interpolateFps')
              ? _snapInt(snapshot['interpolateFps'], 2)
              : null,
          cfgScale: snapshot.containsKey('cfgScale')
              ? _snapDouble(snapshot['cfgScale'], _advancedSettings.cfgScale)
              : null,
          loraAdapter: snapshot['loraAdapter'] as String?,
          cineRealMotionMode: snapshot['cineRealMotionMode'] as String?,
          bulkEditEnabled: snapshot.containsKey('bulkEditEnabled')
              ? snapshot['bulkEditEnabled'] == true
              : null,
          variations: variations is num
              ? variations.toInt().clamp(1, getMaxVariations()).toInt()
              : null,
        );
        if (aspect != null && aspect.trim().isNotEmpty) {
          _inputs['aspect_ratio'] =
              AdvancedSettings.normalizeAspectRatio(aspect);
        }
        if (upscale) {
          final savedFactor = _isVideoTool
              ? _snapInt(
                  snapshot['upscaleFactor'] ?? snapshot['scaleFactor'],
                  2,
                )
              : 2;
          _upscaleEnabled = true;
          _scaleFactor = savedFactor;
          _inputs['scale_factor'] = savedFactor.toDouble();
          _advancedSettings = _advancedSettings.copyWith(
            upscaleOutput: true,
            upscaleFactor: savedFactor,
            enableUpscale: _isVideoTool || snapshot['enableUpscale'] == true,
          );
        }
        if (modelId != null && _tool.models != null) {
          final match = _tool.models!.where((m) => m['id'] == modelId);
          if (match.isNotEmpty &&
              (match.first['enabled'] == null ||
                  match.first['enabled'] == true)) {
            _selectedModelId = modelId;
            _selectedModelData = match.first;
          }
        }
        final activeModel = _selectedModelId ?? _tool.model;
        if (snapshot['transparentBackground'] == true &&
            activeModel == 'qwen2_1_i2i') {
          _inputs['background'] = 'transparent';
        }
        if (activeModel == 'qwen2_1_i2i' &&
            snapshot['outputResolution'] == '2K') {
          _inputs['resolution'] = '2K';
        }
        _restoreSelectedStyle();
        if (_isMusicTool) {
          final musicMode = snapshot['musicMode'];
          final trackMode = snapshot['trackMode'];
          final lyrics = snapshot['lyrics'];
          if (musicMode is String && musicMode.isNotEmpty) {
            _inputs['music_mode'] = musicMode;
          }
          if (trackMode is String && trackMode.isNotEmpty) {
            _inputs['track_mode'] = trackMode;
          }
          if (lyrics is String && lyrics.trim().isNotEmpty) {
            _inputs['lyrics'] = lyrics;
          }
        }
      });
    }

    final prompt = widget.initialPrompt ??
        (snapshot?['prompt'] is String ? snapshot!['prompt'] as String : null);
    if (prompt != null) {
      _promptController.text = prompt;
      _inputs['prompt'] = prompt;
    }

    final restoredMedia = await _restoreSavedMedia(snapshot?['mediaPaths']);
    if (restoredMedia) return;

    if (_isMusicTool) {
      final audioPath = _firstAudioPath(widget.initialLocalPaths);
      if (audioPath != null) {
        try {
          final bytes = await File(audioPath).readAsBytes();
          if (!mounted) return;
          final name = audioPath.split(RegExp(r'[\\/]')).last;
          final ext = name.contains('.') ? name.split('.').last : '';
          setState(() {
            _inputs['music_mode'] = _inputs['music_mode'] ?? 'easy';
            _inputs['track_mode'] = _inputs['track_mode'] == 'create'
                ? 'remix'
                : (_inputs['track_mode'] ?? 'remix');
            _inputs['source_audio'] = bytes;
            _inputs['source_audio_path'] = audioPath;
            _inputs['source_audio_name'] = name;
            _inputs['source_audio_mime'] = _guessAudioMime(ext);
          });
        } catch (e) {
          debugPrint('Could not attach remix audio: $e');
        }
        return;
      }
    }

    final wantsImage = _bulkPrimaryImageInputRef != null;
    final wantsVideo = _tool.inputs
        .whereType<Map<String, dynamic>>()
        .any((i) => i['type'] == 'video');
    final matching = existingMatchingPaths(
      paths: widget.initialLocalPaths,
      wantImages: wantsImage || !wantsVideo,
    );
    if (widget.initialLocalPaths.isNotEmpty && matching.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("This file can't be used for this tool")),
      );
      return;
    }
    if (matching.isEmpty) return;

    if (wantsImage) {
      final id = _bulkPrimaryImageInputRef;
      if (id == null) return;
      await _loadImagePaths(id, matching);
      if (_inputs[id] == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This file can't be used for this tool")),
        );
      }
    } else if (wantsVideo) {
      final videoInputs = _tool.inputs
          .whereType<Map<String, dynamic>>()
          .where((i) => i['type'] == 'video')
          .toList();
      final id =
          videoInputs.isNotEmpty ? videoInputs.first['id'] as String? : null;
      if (id == null) return;
      if (_supportsBulkVideoEdit) {
        for (final path in matching) {
          try {
            await _appendBulkVideoFromPath(path);
          } catch (e) {
            debugPrint('Could not restore video $path: $e');
          }
        }
      }
      if (!mounted) return;
      setState(() => _inputs['${id}_path'] = matching.first);
    }
  }

  /// Apply random style
  void _applyRandomStyle() {
    final styles = _stylesForThisTool;
    if (styles.isEmpty) return;
    final random = Random();
    final randomStyle = styles[random.nextInt(styles.length)];
    _selectStyle(randomStyle);

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(LucideIcons.shuffle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Random style: ${randomStyle.name}'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // -------- Advanced Settings --------

  /// Show advanced settings bottom sheet
  Future<void> _showAdvancedSettings() async {
    // ✅ Unfocus any text field to prevent keyboard from re-opening
    FocusScope.of(context).unfocus();

    final cs = Theme.of(context).colorScheme;
    // Use viewPadding (device safe area), not padding, for a tighter footer.
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar (fixed at top)
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
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(LucideIcons.settings,
                                  color: cs.primary, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              'Additional Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Hide all advanced settings for text output tools
                        if (_isTextTool) ...[
                          Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Text(
                              'No advanced settings available for text output tools',
                              style: TextStyle(
                                color: cs.onSurfaceVariant,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ] else ...[
                          // Speech switches Voice / Speech / Clone on the tool itself.
                          if (_tool.hasMultipleModels && !_isSpeechTool) ...[
                            _buildModelSelector(cs, setSheetState),
                            const SizedBox(height: 20),
                          ],

                          if (_isSpeechTool) ...[
                            _buildSpeechStylePicker(setSheetState),
                            _buildSettingsMenu('voice',
                                sheetSetter: setSheetState),
                            _buildSettingsMenu('language',
                                sheetSetter: setSheetState),
                            _buildSettingsMenu('design_language',
                                sheetSetter: setSheetState),
                            _buildSettingsMenu('clone_language',
                                sheetSetter: setSheetState),
                          ],

                          if (_isAudioTool) ...[
                            _buildOffFormChoices(cs, setSheetState),
                          ],

                          if (_isUpscalerTool) ...[
                            _buildUpscaleModelOptions(cs, setSheetState),
                          ],

                          // Enhance Prompt Toggle (only for models with prompt)
                          if (_hasPrompt && !_isAudioTool) ...[
                            _buildSettingToggle(
                              cs: cs,
                              icon: LucideIcons.sparkles,
                              title: 'Enhance Prompt',
                              subtitle: 'AI improves your prompt automatically',
                              value: _advancedSettings.enhancePrompt,
                              onChanged: (v) {
                                setSheetState(() {
                                  setState(() {
                                    _advancedSettings = _advancedSettings
                                        .copyWith(enhancePrompt: v);
                                  });
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Extra upscale pass after an image is created.
                          // The Upscale Image tool picks its model and scale below instead.
                          if (_allowsOutputUpscale) ...[
                            _buildSettingToggle(
                              cs: cs,
                              icon: LucideIcons.maximize2,
                              title: 'Upscale Output',
                              subtitle: _isUpscalerTool
                                  ? 'Always enabled for upscaler tools'
                                  : () {
                                      final extraCost =
                                          _selectedOutputUpscaleCost;
                                      final name = _selectedOutputUpscale['name']
                                          as String;
                                      if (isVipUser()) {
                                        return '$name · free for VIP';
                                      }
                                      return '$name · +$extraCost credits';
                                    }(),
                              value: _advancedSettings.upscaleOutput,
                              locked:
                                  _isUpscalerTool, // Lock for upscaler tools
                              onChanged: _isUpscalerTool
                                  ? null
                                  : (v) {
                                      setSheetState(() {
                                        setState(() {
                                          _advancedSettings = _advancedSettings
                                              .copyWith(
                                            upscaleOutput: v,
                                            upscaleFactor: 2,
                                          );
                                          _upscaleEnabled = v;
                                          _scaleFactor = v ? 2 : 1;
                                          _inputs["scale_factor"] =
                                              v ? 2.0 : 1.0;
                                          _inputs.putIfAbsent(
                                            'upscale_model',
                                            () => 'recraft_crisp_upscale',
                                          );
                                        });
                                      });
                                    },
                            ),
                            if (!_isUpscalerTool &&
                                _advancedSettings.upscaleOutput)
                              _buildCard(
                                margin: EdgeInsets.zero,
                                padding:
                                    const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                child: _buildOutputUpscalePicker(
                                    cs, setSheetState),
                              ),

                            const SizedBox(height: 12),
                            if (_tool.capabilityId == 'edit_image' &&
                                (_selectedModelId ?? _tool.model) ==
                                    'qwen2_1_i2i') ...[
                              _buildSettingToggle(
                                cs: cs,
                                icon: LucideIcons.eraser,
                                title: 'Transparent Background',
                                subtitle:
                                    'Describe only the subject. A painted area is cleared.',
                                value: _inputs['background'] == 'transparent',
                                onChanged: (v) {
                                  setSheetState(() {
                                    setState(() {
                                      _inputs['background'] =
                                          v ? 'transparent' : 'opaque';
                                      if (v) _inputs.remove('mask_image');
                                    });
                                  });
                                },
                              ),
                              const SizedBox(height: 12),
                              _buildCard(
                                margin: EdgeInsets.zero,
                                padding:
                                    const EdgeInsets.fromLTRB(14, 12, 14, 12),
                                child: _buildQwenResolutionChoice(
                                    cs, setSheetState),
                              ),
                              const SizedBox(height: 12),
                            ],
                            const SizedBox(height: 4),
                          ],

                          // Aspect Ratio Selector (hidden for edit_image, expand scene, upscale, inpaint/erase, remove background tools)
                          if (!_isAudioTool &&
                              !_isEditImageTool &&
                              !_isExpandSceneTool &&
                              !_isUpscalerTool &&
                              !_isInpaintEraseTool &&
                              !_isRemoveBackgroundTool) ...[
                            _buildCard(
                              margin: EdgeInsets.zero,
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              child: _buildAdvancedAspectRatioChipSelector(
                                  cs, setSheetState),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (_isMuseModel) ...[
                            _buildMuseCanvasSettings(cs, setSheetState),
                            const SizedBox(height: 16),
                          ],

                          // Variations chips (image + video tools; max from VIP tier)
                          if (_tool.outputType == 'image' ||
                              _tool.outputType == 'video') ...[
                            _buildCard(
                              margin: EdgeInsets.zero,
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              child: _buildVariationsChipSelector(
                                  cs, setSheetState),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Duration chips (create / animate video; min 5s when model allows)
                          if (_tool.outputType == 'video' &&
                              !_isVideoUpscalerTool) ...[
                            _buildCard(
                              margin: EdgeInsets.zero,
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              child:
                                  _buildDurationChipSelector(cs, setSheetState),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Older video engines only. CineReal and Cinemotion Pro hide this.
                          if (_showsVideoEnhancement) ...[
                            _buildVideoUpscaleSettings(cs, setSheetState),
                            const SizedBox(height: 16),
                          ],

                          // LoRA Adapter Selector (only for qwen_image_edit_2511_rapid_aio)
                          if ((_selectedModelId ?? _tool.model) ==
                              'qwen_image_edit_2511_rapid_aio') ...[
                            _buildLoraAdapterSelector(cs, setSheetState),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),

                // Done button (fixed at bottom with safe area)
                Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.35)),
                SafeArea(
                  top: false,
                  minimum: EdgeInsets.fromLTRB(
                    20,
                    10,
                    20,
                    safeBottom > 0 ? safeBottom : 14,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    // ✅ Ensure focus doesn't return to the prompt after closing
    if (mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  Widget _buildQwenResolutionChoice(
    ColorScheme cs,
    void Function(VoidCallback fn) setSheetState,
  ) {
    final selected = _qwenResolution;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.maximize2, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Output size',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '1k or 2k resolution output.',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final size in const ['1K', '2K'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(size),
                  selected: selected == size,
                  onSelected: (_) {
                    setSheetState(() {
                      setState(() => _inputs['resolution'] = size);
                    });
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Build toggle setting widget
  Widget _buildOutputUpscalePicker(ColorScheme cs, StateSetter setSheetState) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Upscale model',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _outputUpscaleChoices.map((choice) {
              final selected = choice['id'] == _selectedOutputUpscaleId;
              final cost = choice['cost'] as int;
              return InkWell(
                onTap: () {
                  setSheetState(() {
                    setState(() {
                      _inputs['upscale_model'] = choice['id'];
                    });
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 148,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.12)
                        : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? cs.primary.withValues(alpha: 0.5)
                          : cs.outlineVariant.withValues(alpha: 0.25),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        choice['name'] as String,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        choice['blurb'] as String,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isVipUser() ? 'Free for VIP' : '+$cost credits',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingToggle({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
    bool locked = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AppStyles.cardDecoration(cs),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                size: 20, color: value ? cs.primary : cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (locked) ...[
                      const SizedBox(width: 6),
                      Icon(LucideIcons.lock, size: 12, color: cs.primary),
                    ],
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: locked ? null : onChanged,
            activeThumbColor: cs.primary,
          ),
        ],
      ),
    );
  }

  /// Aspect ratio in Additional Settings: discrete [SegmentedButton] chips (default 1:1).
  Widget _buildAdvancedAspectRatioChipSelector(
    ColorScheme cs,
    StateSetter setSheetState,
  ) {
    final options = _isVideoTool
        ? _kVideoShapeOptions
        : AdvancedSettings.kAdvancedAspectRatioOptions;
    final currentStr = _selectedShapeRatio;
    final currentIndex = options.indexOf(currentStr);
    final current = currentIndex < 0 ? 0 : currentIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.scaling, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aspect Ratio',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Output frame shape',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          segments: options
              .asMap()
              .entries
              .map(
                (e) => ButtonSegment<int>(
                  value: e.key,
                  label: Text(e.value),
                ),
              )
              .toList(),
          selected: {current},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setSheetState(() {
              setState(() {
                final next = options[s.first];
                _advancedSettings =
                    _advancedSettings.copyWith(aspectRatio: next);
                _inputs['aspect_ratio'] = next;
              });
            });
          },
          showSelectedIcon: false,
        ),
      ],
    );
  }

  /// Variations as segmented chips (same pattern as interpolation strength).
  Widget _buildVariationsChipSelector(
      ColorScheme cs, StateSetter setSheetState) {
    final maxV = getMaxVariations();
    final values = List<int>.generate(maxV, (i) => i + 1);
    final current = _advancedSettings.variations.clamp(1, maxV);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.copy, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Variations',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _priorVariationCount != null
                        ? 'Last run used $_priorVariationCount. This run starts at 1.'
                        : isVipUser()
                            ? 'VIP: up to 4 variations'
                            : 'Up to 2 variations (VIP: 4)',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SegmentedButton<int>(
          segments: values
              .map(
                (v) => ButtonSegment<int>(
                  value: v,
                  label: Text('$v'),
                ),
              )
              .toList(),
          selected: {current},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setSheetState(() {
              setState(() {
                _advancedSettings = _advancedSettings.copyWith(
                  variations: s.first.clamp(1, maxV),
                );
              });
            });
          },
          showSelectedIcon: false,
        ),
      ],
    );
  }

  /// Duration chips in 5s steps, up to the selected model's max.
  Widget _buildDurationChipSelector(ColorScheme cs, StateSetter setSheetState) {
    final maxDuration = _maxVideoGenDurationSeconds();
    final values = _allowedVideoGenDurationSeconds();
    final current =
        _clampVideoGenDurationSeconds(_advancedSettings.videoDuration);
    final modelId = _selectedModelId ?? _tool.model;

    return Column(
      key: ValueKey('duration_chips_${modelId}_$maxDuration'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.timer, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Duration',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (values.length > 5)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final seconds in values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${seconds}s'),
                      selected: current == seconds,
                      onSelected: (_) {
                        setSheetState(() {
                          setState(() {
                            _advancedSettings = _advancedSettings.copyWith(
                              videoDuration:
                                  _clampVideoGenDurationSeconds(seconds),
                            );
                          });
                        });
                      },
                    ),
                  ),
              ],
            ),
          )
        else
          SegmentedButton<int>(
          segments: values
              .map(
                (v) => ButtonSegment<int>(
                  value: v,
                  label: Text('${v}s'),
                ),
              )
              .toList(),
          selected: {current},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setSheetState(() {
              setState(() {
                _advancedSettings = _advancedSettings.copyWith(
                  videoDuration: _clampVideoGenDurationSeconds(s.first),
                );
              });
            });
          },
          showSelectedIcon: false,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(LucideIcons.gem, size: 14, color: cs.primary.withValues(alpha: 0.8)),
            const SizedBox(width: 6),
            Text(
              'Est. cost: ${_calculateTotalCost()} credits',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Build Video Upscale Settings (Interpolate and Upscale)
  /// Build LoRA Adapter selector (only for qwen_image_edit_2511_rapid_aio)
  Widget _buildLoraAdapterSelector(ColorScheme cs, StateSetter setSheetState) {
    // Get LoRA adapter options from model config
    final modelId = _selectedModelId ?? _tool.model;
    Map<String, dynamic> modelData = _selectedModelData ?? <String, dynamic>{};

    // If _selectedModelData is null, try to find model from config
    if (modelData.isEmpty) {
      modelData = _tool.models?.firstWhere(
            (m) => m['id'] == modelId,
            orElse: () => <String, dynamic>{},
          ) ??
          <String, dynamic>{};
    }

    var loraAdapters = (modelData['loraAdapters'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        ['None'];
    // Fallback from local tool_config metadata if model map misses loraAdapters
    if (loraAdapters.length <= 1) {
      loraAdapters = _loraAdaptersByModel[modelId] ?? loraAdapters;
    }
    if (loraAdapters.isEmpty) {
      loraAdapters = ['None'];
    }
    final selected = loraAdapters.contains(_advancedSettings.loraAdapter)
        ? _advancedSettings.loraAdapter
        : loraAdapters.first;

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
              // Show currently selected friendly name as a subtle badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _loraFriendlyNames[selected] ?? selected,
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
          // Scrollable list of modes with friendly names + descriptions
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: loraAdapters.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final option = loraAdapters[index];
                final isSelected = selected == option;
                final friendlyName = _loraFriendlyNames[option] ?? option;
                final description = _loraDescriptions[option];

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setSheetState(() {
                      setState(() {
                        _advancedSettings =
                            _advancedSettings.copyWith(loraAdapter: option);
                      });
                    });
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
                        // Selection indicator
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
                        // Name + description
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
                                    color: cs.onSurfaceVariant.withValues(alpha: 0.6),
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

  Widget _buildVideoUpscaleSettings(ColorScheme cs, StateSetter setSheetState) {
    // Dedicated video upscaler: keep full interpolation + upscale controls.
    if (_isVideoUpscalerTool) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.maximize2, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'Video Enhancement',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSettingToggle(
            cs: cs,
            icon: LucideIcons.zap,
            title: 'Frame Interpolation',
            subtitle: '2x or 4x FPS',
            value: _advancedSettings.enableInterpolate,
            onChanged: (v) {
              setSheetState(() {
                setState(() {
                  _advancedSettings =
                      _advancedSettings.copyWith(enableInterpolate: v);
                });
              });
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _advancedSettings.enableInterpolate
                ? Padding(
                    padding: const EdgeInsets.only(top: 12, left: 8, right: 8),
                    child: RifeMultiplierControl(
                      value: migrateLegacyInterpolateStorageValue(
                        _advancedSettings.interpolateFps,
                      ),
                      onChanged: (m) {
                        setSheetState(() {
                          setState(() {
                            _advancedSettings =
                                _advancedSettings.copyWith(interpolateFps: m);
                          });
                        });
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          _buildSettingToggle(
            cs: cs,
            icon: LucideIcons.maximize2,
            title: 'Upscale Video',
            subtitle: () {
              final extraCost = _currentModelUpscaleCost;
              final base = extraCost > 0
                  ? 'Higher resolution result (+$extraCost credits)'
                  : 'Higher resolution result';
              return '$base · Always on for this tool';
            }(),
            value: true,
            locked: true,
            onChanged: null,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 8, right: 8),
              child: _buildVideoUpscaleFactorSelector(cs, setSheetState),
            ),
          ),
        ],
      );
    }

    // Create Video / Animate Image: one toggle → fixed 2× FPS + 2× upscale in state.
    // LTX 2.3 models: spatial upscale only in submit path (subtitle only; no extra chips).
    final spatialOnly = _isLtx23SpatialOnlyVideoEnhancement;
    final on = _combinedVideoEnhancementSwitchIsOn;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.maximize2, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'Video Enhancement',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSettingToggle(
          cs: cs,
          icon: LucideIcons.sparkles,
          title: 'Enhance output',
          subtitle: spatialOnly
              ? 'Sharper 2× resolution'
              : '2× smoother motion and 2× resolution',
          value: on,
          onChanged: (v) => _setCombinedVideoEnhancement(v, setSheetState),
        ),
      ],
    );
  }

  /// Build Video Upscale Factor Selector (2x, 4x)
  Widget _buildVideoUpscaleFactorSelector(
      ColorScheme cs, StateSetter setSheetState) {
    final factors = [2, 4];
    final currentFactor = _advancedSettings.upscaleFactor.clamp(2, 4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upscale Factor',
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: factors.map((factor) {
            final isSelected = currentFactor == factor;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: factor < 4 ? 8 : 0),
                child: GestureDetector(
                  onTap: () {
                    setSheetState(() {
                      setState(() {
                        _advancedSettings =
                            _advancedSettings.copyWith(upscaleFactor: factor);
                      });
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? cs.primary
                            : cs.outlineVariant.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '${factor}x',
                        style: TextStyle(
                          color: isSelected ? cs.onPrimary : cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Build model selector for advanced settings
  Widget _buildModelSelector(ColorScheme cs, StateSetter setSheetState) {
    final allModels = _tool.models ?? [];
    // Filter to only enabled models
    final models = allModels.where((m) {
      final enabled = m['enabled'];
      return enabled == null ||
          enabled == true; // Default to enabled if not specified
    }).toList();
    if (models.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            Icon(LucideIcons.cpu, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'AI Model',
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choose the AI engine for this task',
          style: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),

        // Model cards - horizontal scrollable
        SizedBox(
          height: 122,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: models.length,
            itemBuilder: (context, index) {
              final model = models[index];
              final isSelected = model['id'] == _selectedModelId;
              final isDefault = model['id'] == _tool.defaultModel;

              return Padding(
                padding: EdgeInsets.only(
                  right: index < models.length - 1 ? 10 : 0,
                ),
                child: _buildModelCard(
                  cs: cs,
                  model: model,
                  isSelected: isSelected,
                  isDefault: isDefault,
                  onTap: () {
                    setSheetState(() {
                      _selectModel(model);
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build individual model card
  Widget _buildModelCard({
    required ColorScheme cs,
    required Map<String, dynamic> model,
    required bool isSelected,
    required bool isDefault,
    required VoidCallback onTap,
  }) {
    final name = model['name'] as String? ?? 'Unknown';
    final description = model['description'] as String? ?? '';
    final cost = _listedGemCostForModel(model);
    final offer = _offerPercentForModelMap(model);
    final discountedCost = offer > 0 ? _applyOfferDiscount(cost, offer) : cost;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 150,
        height: 110, // Fixed height to prevent overflow
        padding: const EdgeInsets.all(10),
        decoration: AppStyles.cardDecoration(cs).copyWith(
          border: Border.all(
            color: isSelected
                ? cs.primary
                : (cs.brightness == Brightness.dark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.white.withValues(alpha: 0.9)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: name + selection indicator
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Model name (takes remaining space)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? cs.primary : cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (isDefault)
                        Text(
                          '★ Best',
                          style: TextStyle(
                            color: cs.secondary,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                // Check indicator
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child:
                        Icon(LucideIcons.check, size: 10, color: cs.onPrimary),
                  ),
              ],
            ),

            const SizedBox(height: 4),

            // Description - 2 lines
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                fontSize: 10,
                height: 1.2,
              ),
            ),

            const Spacer(),

            // Cost row - at bottom
            Row(
              children: [
                Icon(LucideIcons.gem, size: 13, color: cs.primary),
                const SizedBox(width: 4),
                if (offer > 0) ...[
                  Text(
                    '$cost',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$discountedCost',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '-$offer%',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ] else
                  Text(
                    '$cost',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promptFocusNode.removeListener(_onComposerPromptVisualsChanged);
    _promptController.removeListener(_onComposerPromptVisualsChanged);
    _promptFocusNode.dispose();
    _promptController.dispose();
    _sunoStyleController.dispose();
    _previewPageController.dispose();
    _glowAnimationController.dispose();
    isAdFreeNotifier.removeListener(_onAdFreeStatusChanged);
    jobListNotifier.removeListener(_onJobListChanged);
    SaleService().state.removeListener(_onSaleStateChanged);
    // Dispose all user video controllers
    for (final controller in _userVideoControllers.values) {
      controller.dispose();
    }
    _userVideoControllers.clear();
    super.dispose();
  }

  var _resumeUserVideos = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _resumeUserVideos = _userVideoControllers.values.any(
        (controller) =>
            videoFrameIsReady(controller) && controller.value.isPlaying,
      );
      for (final controller in _userVideoControllers.values) {
        unawaited(pauseVideoController(controller));
      }
      unawaited(StylePreviewManager.instance.pauseAll());
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_activeJobId != null && _loading && !_fetchingResult) {
        debugPrint("🔁 Resuming job polling after resume");
      }
      unawaited(_recoverUserVideos());
    }
  }

  Future<void> _recoverUserVideos() async {
    final play = _resumeUserVideos;
    _resumeUserVideos = false;
    final entries = Map<String, VideoPlayerController>.from(
      _userVideoControllers,
    );
    var changed = false;
    for (final entry in entries.entries) {
      final current = entry.value;
      final next = await replaceDeadVideo(current, play: play);
      if (!mounted) {
        if (next != null && !identical(next, current)) await next.dispose();
        return;
      }
      if (next == null || identical(next, current)) continue;
      if (!identical(_userVideoControllers[entry.key], current)) {
        await next.dispose();
        continue;
      }
      _userVideoControllers[entry.key] = next;
      try {
        await current.dispose();
      } catch (_) {}
      changed = true;
    }
    if (mounted && changed) setState(() {});
  }

  // -------- Validation: Check if all required inputs are filled --------
  bool _areRequiredInputsFilled() {
    // Don't allow generation while an image is being processed
    if (_isProcessingImage) return false;

    // Check if bulk edit mode is enabled
    final isBulkMode = _advancedSettings.bulkEditEnabled && _supportsBulkEdit;

    // Calculate total jobs for rate limit check
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());
    final int imageCount =
        isBulkMode && _hasBulkInput ? _bulkActiveMediaCount : 1;
    final int totalJobsToSubmit = imageCount * variations;

    // Check rate limit - don't allow if it would exceed concurrent job limit
    final rateLimitError = checkRateLimitForSubmission(totalJobsToSubmit);
    if (rateLimitError != null) return false;
    if (_sunoExtend || _sunoMashup) return _extendMashupReady();

    // Check total job limit for bulk edit
    if (isBulkMode && _hasBulkInput) {
      final totalJobs = _bulkActiveMediaCount * variations;
      if (totalJobs > _maxTotalJobs) return false;

      if (_supportsBulkVideoEdit) {
        if (_bulkVideoDurations.length != _bulkVideoPaths.length) {
          return false;
        }
        for (final d in _bulkVideoDurations) {
          if (d == null || d.inSeconds <= 0) return false;
        }
      } else {
        // For inpaint tools in bulk mode, all images must have masks
        if (_requiresMask) {
          for (int i = 0; i < _bulkImageJobs.length; i++) {
            if (i >= _bulkMasks.length || _bulkMasks[i] == null) {
              return false;
            }
          }
        }

        // For outpaint tools in bulk mode, all images must have placement config
        if (_isOutpaint) {
          for (int i = 0; i < _bulkImageJobs.length; i++) {
            if (i >= _bulkOutpaintConfigs.length ||
                _bulkOutpaintConfigs[i] == null) {
              return false;
            }
          }
        }

        // Multi-init bulk: each task must be non-empty and within model max
        for (final job in _bulkImageJobs) {
          if (job.isEmpty) return false;
          if (job.length > _bulkMaxInitPerJob) return false;
        }

        if (_isCineRealFlf2vMode) {
          for (final job in _bulkImageJobs) {
            if (job.length != 2 || job[0].isEmpty || job[1].isEmpty) {
              return false;
            }
          }
        }
      }
    }

    if (_isCineRealFlf2vMode || _requiresEndFrame) {
      final bool flf2vBulk =
          isBulkMode && _supportsBulkImageEdit && _hasBulkInput;
      if (!flf2vBulk) {
        bool hasImageBytes(String key) {
          final v = _inputs[key];
          if (v == null) return false;
          if (v is Uint8List) return v.isNotEmpty;
          if (v is List) return v.isNotEmpty && v.first is Uint8List;
          return false;
        }

        if (!hasImageBytes('init_image') ||
            !hasImageBytes('last_frame_image')) {
          return false;
        }
      }
    }

    final elements = _currentElements;

    for (final element in elements) {
      final type = element["type"];
      final inputRef = element["input_ref"];

      // Skip elements without input_ref (like upscale_toggle, generate_button)
      if (inputRef == null) continue;
      final gated = _tool.inputs
          .firstWhere((i) => i["id"] == inputRef, orElse: () => {});
      if (gated is Map &&
          !_elementShouldRender(Map<String, dynamic>.from(gated))) {
        continue;
      }

      // Skip optional inputs like sliders, dropdowns (they have defaults)
      if (type == "slider" || type == "dropdown") continue;
      // Scaffolds with built-in defaults / no required semantics → skip.
      if (type == "number_input" ||
          type == "seed_input" ||
          type == "aspect_ratio" ||
          type == "color_picker" ||
          type == "range_slider" ||
          type == "info_card" ||
          type == "section_header") {
        continue;
      }

      final inputDef = _tool.inputs
          .firstWhere((i) => i["id"] == inputRef, orElse: () => {});
      final isRequired = inputDef["required"] == true;

      switch (type) {
        case "prompt":
          if (_isSunoV6 && !_sunoSounds && !_musicEasy) {
            final lyrics = (_inputs['lyrics'] as String?)?.trim() ?? '';
            final style = _sunoStyleController.text.trim();
            final avoid = (_inputs['negative_prompt'] as String?)?.trim() ?? '';
            final instrumental = _inputs['vocals'] == false;
            final ready = instrumental
                ? style.isNotEmpty || avoid.isNotEmpty
                : lyrics.isNotEmpty || style.isNotEmpty || avoid.isNotEmpty;
            if (!ready) return false;
            break;
          }
          if (_isSunoV6 && !_sunoSounds && _musicEasy) {
            final idea = _promptController.text.trim();
            if (idea.isEmpty && !_sunoHasReference) return false;
            if (idea.isNotEmpty) _inputs['prompt'] = idea;
            break;
          }
          // Check if prompt is optional
          final promptInput = _tool.inputs
              .firstWhere((i) => i["id"] == inputRef, orElse: () => {});
          final isOptional = promptInput["optional"] == true;
          if (!isOptional) {
            // Prompt is required - always use the controller as source of truth
            final promptText = _promptController.text.trim();
            if (promptText.isNotEmpty) {
              _inputs['prompt'] = _promptController.text;
            }
            if (promptText.isEmpty) {
              return false;
            }
          }
          break;

        case "text_input":
          if (inputRef == 'lyrics' && _isSunoV6) break;
          if (isRequired) {
            final v = (_inputs[inputRef] as String?)?.trim() ?? '';
            if (v.isEmpty) return false;
          }
          break;

        case "audio_upload":
        case "file_upload":
          if (isRequired) {
            final v = _inputs[inputRef];
            if (v is! Uint8List || v.isEmpty) return false;
          }
          break;

        case "multi_select":
          final minSel = (inputDef["min"] as int?) ?? 0;
          if (minSel > 0) {
            final v = _inputs[inputRef];
            final n = v is List ? v.length : 0;
            if (n < minSel) return false;
          }
          break;

        case "image_upload":
          // In bulk mode, check bulk images instead of single image
          if (isBulkMode && _supportsBulkEdit) {
            // Bulk mode: require at least one bulk image
            if (!_hasBulkInput) return false;
          } else {
            // Single mode: check normal image input
            final imageData = _inputs[inputRef];
            if (imageData == null) return false;
            if (imageData is List && imageData.isEmpty) return false;
          }
          break;

        case "video_upload":
          if (isBulkMode && _supportsBulkVideoEdit) {
            if (!_hasBulkInput) return false;
            if (_bulkVideoDurations.length != _bulkVideoPaths.length) {
              return false;
            }
            for (final d in _bulkVideoDurations) {
              if (d == null || d.inSeconds <= 0) return false;
            }
          } else {
            final videoData = _inputs[inputRef];
            if (videoData == null) return false;
            if (videoData is List && videoData.isEmpty) return false;
            if (_inputVideoDuration == null ||
                _inputVideoDuration!.inSeconds <= 0) {
              return false;
            }
          }
          break;

        case "painter":
          // Mask is required for inpainting modes (in single mode)
          // In bulk mode, masks are checked separately above
          if (!isBulkMode) {
            final maskData = _inputs[inputRef];
            if (maskData == null) return false;
          }
          break;
      }
    }

    return true;
  }

  // Get list of missing required inputs for user feedback
  bool _extendMashupReady() {
    if (_inputs['confirm_audio_rights'] != true) return false;
    if (_sunoExtend) {
      if (!_filledMedia('extend_audio')) return false;
      final duration = _inputs['extend_audio_duration'];
      if (duration is num && duration > 8 * 60) return false;
      return true;
    }
    if (!_filledMedia('mashup_a') || !_filledMedia('mashup_b')) return false;
    final style = _sunoStyleController.text.trim();
    final title = (_inputs['title'] as String?)?.trim() ?? '';
    return style.isNotEmpty && title.isNotEmpty;
  }

  List<String> _extendMashupMissing() {
    final missing = <String>[];
    if (_sunoExtend) {
      if (!_filledMedia('extend_audio')) missing.add('Audio to extend');
      final duration = _inputs['extend_audio_duration'];
      if (duration is num && duration > 8 * 60) {
        missing.add('Audio must be 8 minutes or less');
      }
    } else {
      if (!_filledMedia('mashup_a')) missing.add('First track');
      if (!_filledMedia('mashup_b')) missing.add('Second track');
      if (_sunoStyleController.text.trim().isEmpty) missing.add('Style');
      if (((_inputs['title'] as String?) ?? '').trim().isEmpty) {
        missing.add('Title');
      }
    }
    if (_inputs['confirm_audio_rights'] != true) {
      missing.add('Confirm you own the audio');
    }
    return missing;
  }

  List<String> _getMissingInputs() {
    final missing = <String>[];

    // Show processing message while image is being loaded
    if (_isProcessingImage) {
      return ["Image loading..."]; // Special message for processing state
    }

    // Check if bulk edit mode is enabled
    final isBulkMode = _advancedSettings.bulkEditEnabled && _supportsBulkEdit;

    // Calculate total jobs for rate limit check
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());
    final int imageCount =
        isBulkMode && _hasBulkInput ? _bulkActiveMediaCount : 1;
    final int totalJobsToSubmit = imageCount * variations;

    // Check rate limit - provide helpful context instead of blocking message
    final rateLimitError = checkRateLimitForSubmission(totalJobsToSubmit);
    if (rateLimitError != null) {
      final status = getRateLimitStatus();
      final current = status['currentProcessing'] as int;
      final available = status['available'] as int;

      // Different messages based on context
      if (available == 0) {
        // No slots available - show friendly waiting message
        return ["⏳ $current jobs running • Wait for completion"];
      } else if (totalJobsToSubmit > available) {
        // Some slots available but not enough
        return [
          "⏳ $available slot${available > 1 ? 's' : ''} free • Need $totalJobsToSubmit"
        ];
      }
      return ["⏳ Processing $current jobs..."];
    }

    if (_sunoExtend || _sunoMashup) return _extendMashupMissing();

    // Check total job limit for bulk edit
    if (isBulkMode && _hasBulkInput) {
      final totalJobs = _bulkActiveMediaCount * variations;
      if (totalJobs > _maxTotalJobs) {
        return ["Max $_maxTotalJobs jobs allowed"];
      }

      if (_supportsBulkVideoEdit) {
        if (_bulkVideoPaths.isEmpty) {
          return ["Videos"];
        }
        if (_bulkVideoDurations.length != _bulkVideoPaths.length) {
          return ["Videos"];
        }
        int bad = 0;
        for (final d in _bulkVideoDurations) {
          if (d == null || d.inSeconds <= 0) bad++;
        }
        if (bad > 0) return ["$bad video(s) need valid duration"];
      } else {
        // Check bulk masks for inpaint tools
        if (_requiresMask) {
          int missingMasks = 0;
          for (int i = 0; i < _bulkImageJobs.length; i++) {
            if (i >= _bulkMasks.length || _bulkMasks[i] == null) {
              missingMasks++;
            }
          }
          if (missingMasks > 0) {
            return ["$missingMasks image(s) need masks"];
          }
        }

        // Check bulk outpaint configs for expand scene
        if (_isOutpaint) {
          int missingConfigs = 0;
          for (int i = 0; i < _bulkImageJobs.length; i++) {
            if (i >= _bulkOutpaintConfigs.length ||
                _bulkOutpaintConfigs[i] == null) {
              missingConfigs++;
            }
          }
          if (missingConfigs > 0) {
            return ["$missingConfigs image(s) need placement"];
          }
        }

        for (final job in _bulkImageJobs) {
          if (job.isEmpty) {
            return ["Each bulk task needs at least one image"];
          }
          if (job.length > _bulkMaxInitPerJob) {
            return [
              "Too many reference images in one task (max $_bulkMaxInitPerJob for this model)",
            ];
          }
        }

        if (_isCineRealFlf2vMode) {
          for (int i = 0; i < _bulkImageJobs.length; i++) {
            final job = _bulkImageJobs[i];
            if (job.length != 2 || job[0].isEmpty || job[1].isEmpty) {
              return [
                "Clip ${i + 1}: add start and end frames",
              ];
            }
          }
        }
      }
    }

    if (_isCineRealFlf2vMode || _requiresEndFrame) {
      final bool flf2vBulk =
          isBulkMode && _supportsBulkImageEdit && _hasBulkInput;
      if (!flf2vBulk) {
        bool missing0(String key) {
          final v = _inputs[key];
          if (v == null) return true;
          if (v is Uint8List) return v.isEmpty;
          if (v is List) return v.isEmpty;
          return true;
        }

        if (missing0('init_image')) missing.add('Start frame');
        if (missing0('last_frame_image')) missing.add('End frame');
      }
    }

    final elements = _currentElements;

    for (final element in elements) {
      final type = element["type"];
      final inputRef = element["input_ref"];

      // Skip elements without input_ref
      if (inputRef == null) continue;
      final gated = _tool.inputs
          .firstWhere((i) => i["id"] == inputRef, orElse: () => {});
      if (gated is Map &&
          !_elementShouldRender(Map<String, dynamic>.from(gated))) {
        continue;
      }

      // Skip optional inputs
      if (type == "slider" || type == "dropdown") continue;
      if (type == "number_input" ||
          type == "seed_input" ||
          type == "aspect_ratio" ||
          type == "color_picker" ||
          type == "range_slider" ||
          type == "info_card" ||
          type == "section_header") {
        continue;
      }

      final inputDef = _tool.inputs
          .firstWhere((i) => i["id"] == inputRef, orElse: () => {});
      final isRequired = inputDef["required"] == true;
      final elementLabel = (inputDef["label"] as String?)?.trim();

      switch (type) {
        case "prompt":
          if (_isSunoV6 && !_sunoSounds && !_musicEasy) {
            final lyrics = (_inputs['lyrics'] as String?)?.trim() ?? '';
            final style = _sunoStyleController.text.trim();
            final avoid = (_inputs['negative_prompt'] as String?)?.trim() ?? '';
            final instrumental = _inputs['vocals'] == false;
            final ready = instrumental
                ? style.isNotEmpty || avoid.isNotEmpty
                : lyrics.isNotEmpty || style.isNotEmpty || avoid.isNotEmpty;
            if (!ready) {
              missing.add(instrumental ? 'Style of Music' : 'Lyrics, style, or what to avoid');
            }
            break;
          }
          if (_isSunoV6 && !_sunoSounds && _musicEasy) {
            final idea = _promptController.text.trim();
            if (idea.isEmpty && !_sunoHasReference) {
              missing.add('A song idea, photo, clip, or track');
            } else if (idea.isNotEmpty) {
              _inputs['prompt'] = idea;
            }
            break;
          }
          // Check if prompt is optional
          final promptInput = _tool.inputs
              .firstWhere((i) => i["id"] == inputRef, orElse: () => {});
          final isOptional = promptInput["optional"] == true;
          if (!isOptional) {
            // Prompt is required - check if filled
            final promptText = _promptController.text.trim();
            if (promptText.isNotEmpty) {
              _inputs['prompt'] = _promptController.text;
            }
            if (promptText.isEmpty) {
              missing.add("Prompt");
            }
          }
          break;

        case "text_input":
          if (inputRef == 'lyrics' && _isSunoV6) break;
          if (isRequired) {
            final v = (_inputs[inputRef] as String?)?.trim() ?? '';
            if (v.isEmpty) missing.add(elementLabel ?? "Text");
          }
          break;

        case "audio_upload":
          if (isRequired) {
            final v = _inputs[inputRef];
            if (v is! Uint8List || v.isEmpty) {
              missing.add(elementLabel ?? "Audio");
            }
          }
          break;

        case "file_upload":
          if (isRequired) {
            final v = _inputs[inputRef];
            if (v is! Uint8List || v.isEmpty) {
              missing.add(elementLabel ?? "File");
            }
          }
          break;

        case "multi_select":
          final minSel = (inputDef["min"] as int?) ?? 0;
          if (minSel > 0) {
            final v = _inputs[inputRef];
            final n = v is List ? v.length : 0;
            if (n < minSel) {
              missing.add(elementLabel ?? "Selections");
            }
          }
          break;

        case "image_upload":
          // In bulk mode, check bulk images instead of single image
          if (isBulkMode && _supportsBulkEdit) {
            if (!_hasBulkInput) {
              missing.add("Images");
            }
          } else {
            final imageData = _inputs[inputRef];
            if (imageData == null || (imageData is List && imageData.isEmpty)) {
              missing.add("Image");
            }
          }
          break;

        case "video_upload":
          if (isBulkMode && _supportsBulkVideoEdit) {
            if (!_hasBulkInput) {
              missing.add("Videos");
            }
          } else {
            final videoData = _inputs[inputRef];
            if (videoData == null || (videoData is List && videoData.isEmpty)) {
              missing.add("Video");
            } else if (_inputVideoDuration == null ||
                _inputVideoDuration!.inSeconds <= 0) {
              missing.add("Video");
            }
          }
          break;

        case "painter":
          // Mask is required for inpainting modes (in single mode)
          // In bulk mode, masks are checked separately above
          if (!isBulkMode) {
            final maskData = _inputs[inputRef];
            if (maskData == null) {
              missing.add("Mask");
            }
          }
          break;
      }
    }

    return missing;
  }

  // -------- Generate Button --------
  Widget _buildGenerateButton() {
    final cs = Theme.of(context).colorScheme;
    final offer = _currentModelOffer;

    // Use unified cost calculation (handles video upscaler + animate/create_video duration-based pricing)
    final int totalCost = _calculateTotalCost();
    // Cost before discount (for strikethrough display)
    int baseTotal;
    if (_isVideoUpscalerTool) {
      baseTotal = _videoUpscalerUndiscountedCreditsTotal();
    } else if (_tool.outputType == 'video' && !_isVideoUpscalerTool) {
      final variations =
          _advancedSettings.variations.clamp(1, getMaxVariations());
      final imageCount = _advancedSettings.bulkEditEnabled && _hasBulkInput
          ? _bulkActiveMediaCount
          : 1;
      final baseCostPerVariation =
          _getDurationBasedCost() + _enhancementUpscaleCreditsPerVariation();
      baseTotal = baseCostPerVariation * variations * imageCount;
    } else {
      final variations =
          _advancedSettings.variations.clamp(1, getMaxVariations());
      final imageCount = _advancedSettings.bulkEditEnabled && _hasBulkInput
          ? _bulkActiveMediaCount
          : 1;
      final baseCostPerVariation = _listedGenerationCost() +
          _enhancementUpscaleCreditsPerVariation() +
          _inputScaleUpscaleCreditsPerVariation();
      baseTotal = baseCostPerVariation * variations * imageCount;
    }

    // Check if button should be enabled
    final isEnabled = _areRequiredInputsFilled() && !_musicExpanding;
    final missingInputs = _getMissingInputs();

    return Container(
      margin: const EdgeInsets.only(top: 20, bottom: 16),
      child: Column(
        children: [
          // Missing inputs hint (shown when button is disabled)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: !isEnabled && missingInputs.isNotEmpty
                ? Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isProcessingImage
                          ? cs.primaryContainer.withValues(alpha: 0.3)
                          : cs.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isProcessingImage
                            ? cs.primary.withValues(alpha: 0.2)
                            : cs.error.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isProcessingImage)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: cs.primary.withValues(alpha: 0.8),
                            ),
                          )
                        else
                          Icon(
                            LucideIcons.alertCircle,
                            size: 16,
                            color: cs.error.withValues(alpha: 0.8),
                          ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _isProcessingImage
                                ? "Processing image..."
                                : "Add ${missingInputs.join(' & ')} to continue",
                            style: TextStyle(
                              color: _isProcessingImage
                                  ? cs.primary.withValues(alpha: 0.9)
                                  : cs.error.withValues(alpha: 0.9),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // Main generate button with integrated cost (Kala AI brand gradient)
          Opacity(
            opacity: isEnabled ? 1.0 : 0.6,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: isEnabled
                      ? KalaColors.brandGradient
                      : [
                          cs.onSurfaceVariant.withValues(alpha: 0.4),
                          cs.onSurfaceVariant.withValues(alpha: 0.3)
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: isEnabled
                    ? [
                        BoxShadow(
                          color: KalaColors.purple.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: KalaColors.cyan.withValues(alpha: 0.2),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : null,
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled ? _runJob : null,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Left: Generate text with icon
                        const Icon(
                          LucideIcons.sparkles,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "Generate",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),

                        // Divider
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          height: 24,
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),

                        // Right: Cost display
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.gem,
                                size: 16,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                              const SizedBox(width: 6),
                              if (offer > 0) ...[
                                Text(
                                  "$baseTotal",
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 14,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor:
                                        Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                "$totalCost",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (offer > 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.greenAccent.withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "-$offer%",
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Upscale info badge (when image upscale is enabled)
          if (_upscaleEnabled &&
              _currentModelUpscaleCost > 0 &&
              _tool.outputType != 'video')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.maximize2,
                    size: 14,
                    color: cs.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "${_scaleFactor}x upscale (+$_currentModelUpscaleCost credits)",
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 🖼️ BUILD UI — Scaffold + Mode Selector + Dynamic Elements
  // ----------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        const Positioned.fill(child: BacklitWash()),
        Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                LucideIcons.sparkles,
                size: 16,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _tool.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  fontSize: 17,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
        actions: [
          // Credits pill
          ValueListenableBuilder<int>(
            valueListenable: userCreditsNotifier,
            builder: (_, credits, __) {
              return Container(
                margin: const EdgeInsets.only(right: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(AppStyles.radiusFull),
                  border: Border.all(
                    color: cs.primary.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.gem,
                      size: 14,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      credits.toString(),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _buildDynamicInputScreen(),
      ),
        ),
      ],
    );
  }

  // -----------------------------------------------
  // 🧠 IMAGE PICKING & INPUT MANAGEMENT
  // -----------------------------------------------

  Future<void> _pickImageFromGallery(Map<String, dynamic> input) async {
    final id = input['id']?.toString();
    if (id == null || id.isEmpty) return;
    final maxRaw = input['max'];
    final maxCount = maxRaw is int
        ? maxRaw
        : maxRaw is num
            ? maxRaw.toInt()
            : 1;
    final allowMulti = maxCount > 1;

    // Increment version and start processing
    final currentVersion = ++_imageProcessingVersion;
    setState(() => _isProcessingImage = true);

    try {
      if (allowMulti) {
        final files = await picker.pickMultiImage(imageQuality: 85);
        if (files.isEmpty) {
          if (mounted) setState(() => _isProcessingImage = false);
          return;
        }

        // Check if this operation is still valid (not superseded by newer pick)
        if (currentVersion != _imageProcessingVersion) {
          // A newer operation started, this one is cancelled - don't reset flag
          return;
        }

        final limited = files.take(maxCount).toList();
        final resized = await Future.wait(limited.map((f) async {
          final b = await f.readAsBytes();
          return _resizeImageSafe(b);
        }));
        final bytesList = id == 'cover_image'
            ? resized.where((bytes) => bytes.length <= 10 * 1024 * 1024).toList()
            : resized;

        // Check again after async operation
        if (currentVersion != _imageProcessingVersion || !mounted) {
          // A newer operation started or widget unmounted
          return;
        }
        if (id == 'cover_image' && bytesList.length != resized.length) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Each photo needs to be under 10 MB.')),
          );
          if (bytesList.isEmpty) {
            setState(() => _isProcessingImage = false);
            return;
          }
        }

        setState(() {
          if (_isAnimateImageTool &&
              _isCineRealAnimateModel &&
              id == 'last_frame_image') {
            _clearCineRealSingleRefVideo();
          }
          _inputs[id] = bytesList;
          _inputs["${id}_path"] = limited.first.path;
          if (_isImageStudio && (id == 'init_image' || id == 'image')) {
            _clearStudioOutpaint();
          }
          // Clear old mask when new image is selected
          _inputs["mask_image"] = null;
          _isProcessingImage = false;
        });
      } else {
        final file = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
        if (file == null) {
          if (mounted) setState(() => _isProcessingImage = false);
          return;
        }

        // Check if this operation is still valid
        if (currentVersion != _imageProcessingVersion) {
          // A newer operation started, this one is cancelled
          return;
        }

        final bytes = await _resizeImageSafe(await file.readAsBytes());

        // Check again after async operation
        if (currentVersion != _imageProcessingVersion || !mounted) {
          // A newer operation started or widget unmounted
          return;
        }

        setState(() {
          if (_isAnimateImageTool &&
              _isCineRealAnimateModel &&
              id == 'last_frame_image') {
            _clearCineRealSingleRefVideo();
          }
          _inputs[id] = [bytes];
          _inputs["${id}_path"] = file.path;
          // Clear old mask when new image is selected
          _inputs["mask_image"] = null;
          if (_isImageStudio && (id == 'init_image' || id == 'image')) {
            _clearStudioOutpaint();
          }
          _isProcessingImage = false;
        });

        if (_tool.model == "diffusers_outpaint" ||
            _tool.capabilityId == 'expand_scene') {
          final result = await Navigator.push<Map<String, String>>(
            context,
            MaterialPageRoute(
              builder: (_) => OutpaintCanvasPage(imageBytes: bytes),
              fullscreenDialog: true,
            ),
          );
          if (result != null && mounted) {
            setState(() {
              // Store all outpaint config values
              _inputs["alignment"] = result["alignment"];
              _inputs["aspect_ratio"] = result["aspect_ratio"];
              _inputs["is_custom"] = result["is_custom"];
              _inputs["custom_scale"] = result["custom_scale"];
              _inputs["norm_offset_x"] = result["norm_offset_x"];
              _inputs["norm_offset_y"] = result["norm_offset_y"];
              _inputs["offset_x"] = result["offset_x"];
              _inputs["offset_y"] = result["offset_y"];
              _inputs["canvas_width"] = result["canvas_width"];
              _inputs["canvas_height"] = result["canvas_height"];
              _inputs["fitted_width"] = result["fitted_width"];
              _inputs["fitted_height"] = result["fitted_height"];
              _inputs["image_width"] = result["image_width"];
              _inputs["image_height"] = result["image_height"];
              _inputs["image_left"] = result["image_left"];
              _inputs["image_top"] = result["image_top"];
              _inputs["outpaint_preview"] = bytes;
            });
          }
        }

        // Automatically open mask editor for inpainting / LaMa models
        final model = _tool.model.toLowerCase();
        final mode = _selectedModeKey?.toLowerCase() ?? "";
        final paramMode =
            (_tool.params?["mode"]?.toString().toLowerCase() ?? "");

        if (model.contains("inpaint") ||
            model.contains("lama") ||
            mode.contains("inpaint") ||
            paramMode.contains("inpaint") ||
            paramMode.contains("lama")) {
          _autoOpenMaskAfterPick = true;
        }

        // --- Auto-open mask editor if required ---
        if (_autoOpenMaskAfterPick) {
          _autoOpenMaskAfterPick = false;
          final baseBytes = _inputs[id]?[0] as Uint8List?;
          if (baseBytes != null) {
            final mask = await _openMaskEditor(baseBytes);
            if (mask != null && mounted) {
              setState(() {
                _inputs["mask_image"] = mask;
              });
              await _showMaskLayout(baseBytes, mask);
            }
          }
        }
      }
      await _maybePromoteCreateToEdit();
    } catch (e) {
      debugPrint("Gallery picker failed: $e");
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Failed to load image: $e")));
      }
    }
  }

  String _messageForCameraPickFailure(Object error) {
    if (error is PlatformException) {
      final code = error.code;
      if (code == 'camera_access_denied' ||
          code == 'permission_denied' ||
          code == 'CameraAccessDenied') {
        return 'Camera access is required to take photos. Please enable it in your device settings and try again.';
      }
    }
    return 'Could not take a photo. Please try again or choose an image from your gallery.';
  }

  Future<void> _pickImageFromCamera(Map<String, dynamic> input) async {
    final id = input['id']?.toString();
    if (id == null || id.isEmpty) return;

    // Increment version and start processing
    final currentVersion = ++_imageProcessingVersion;
    setState(() => _isProcessingImage = true);

    try {
      final file =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (file == null) {
        if (mounted) setState(() => _isProcessingImage = false);
        return;
      }

      // Check if this operation is still valid
      if (currentVersion != _imageProcessingVersion) {
        // A newer operation started, this one is cancelled
        return;
      }

      final bytes = await _resizeImageSafe(await file.readAsBytes());

      // Check again after async operation
      if (currentVersion != _imageProcessingVersion || !mounted) {
        // A newer operation started or widget unmounted
        return;
      }

      setState(() {
        if (_isAnimateImageTool &&
            _isCineRealAnimateModel &&
            id == 'last_frame_image') {
          _clearCineRealSingleRefVideo();
        }
        _inputs[id] = [bytes];
        _inputs["${id}_path"] = file.path;
        if (_isImageStudio && (id == 'init_image' || id == 'image')) {
          _clearStudioOutpaint();
        }
        // Clear old mask when new image is captured
        _inputs["mask_image"] = null;
        _isProcessingImage = false;
      });

      if (_tool.model == "diffusers_outpaint" ||
          _tool.capabilityId == 'expand_scene') {
        final result = await Navigator.push<Map<String, String>>(
          context,
          MaterialPageRoute(
            builder: (_) => OutpaintCanvasPage(imageBytes: bytes),
            fullscreenDialog: true,
          ),
        );
        if (result != null && mounted) {
          setState(() {
            // Store all outpaint config values
            _inputs["alignment"] = result["alignment"];
            _inputs["aspect_ratio"] = result["aspect_ratio"];
            _inputs["is_custom"] = result["is_custom"];
            _inputs["custom_scale"] = result["custom_scale"];
            _inputs["norm_offset_x"] = result["norm_offset_x"];
            _inputs["norm_offset_y"] = result["norm_offset_y"];
            _inputs["offset_x"] = result["offset_x"];
            _inputs["offset_y"] = result["offset_y"];
            _inputs["canvas_width"] = result["canvas_width"];
            _inputs["canvas_height"] = result["canvas_height"];
            _inputs["fitted_width"] = result["fitted_width"];
            _inputs["fitted_height"] = result["fitted_height"];
            _inputs["image_width"] = result["image_width"];
            _inputs["image_height"] = result["image_height"];
            _inputs["image_left"] = result["image_left"];
            _inputs["image_top"] = result["image_top"];
            _inputs["outpaint_preview"] = bytes;
          });
        }
      }

      // Automatically open mask editor for inpainting / LaMa models
      final model = _tool.model.toLowerCase();
      final mode = _selectedModeKey?.toLowerCase() ?? "";
      final paramMode =
          (_tool.params?["mode"]?.toString().toLowerCase() ?? "");

      if (model.contains("inpaint") ||
          model.contains("lama") ||
          mode.contains("inpaint") ||
          paramMode.contains("inpaint") ||
          paramMode.contains("lama")) {
        _autoOpenMaskAfterPick = true;
      }

      // --- Auto-open mask editor if required ---
      if (_autoOpenMaskAfterPick) {
        _autoOpenMaskAfterPick = false;
        final baseBytes = _inputs[id]?[0] as Uint8List?;
        if (baseBytes != null) {
          final mask = await _openMaskEditor(baseBytes);
          if (mask != null && mounted) {
            setState(() {
              _inputs["mask_image"] = mask;
            });
            await _showMaskLayout(baseBytes, mask);
          }
        }
      }
      await _maybePromoteCreateToEdit();
    } catch (e) {
      debugPrint("Camera image failed: $e");
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_messageForCameraPickFailure(e))),
        );
      }
    }
  }

  Future<Uint8List> _resizeImageSafe(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    int width = img.width;
    int height = img.height;

    // HARD CAPS: limit both max dimension AND total pixel area.
    // This avoids OOM spikes for tall images even when one side is within maxDim.
    const int maxDim = 1280;
    const int maxPixels =
        700000; // ~576x1184 = 681k (safe), 800x1184 = 947k (too big)

    // 1) Cap by max dimension
    if (width > maxDim || height > maxDim) {
      final scale = maxDim / max(width, height);
      width = (width * scale).round();
      height = (height * scale).round();
    }

    // 2) Cap by total pixel area
    final int area = width * height;
    if (area > maxPixels) {
      final scale = sqrt(maxPixels / area);
      width = (width * scale).round();
      height = (height * scale).round();
    }

    // Round DOWN to nearest multiple of 32 so we never exceed limits after padding.
    int roundDown32(int x) => max(32, (x ~/ 32) * 32);
    final paddedW = min(maxDim, roundDown32(width));
    final paddedH = min(maxDim, roundDown32(height));

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()..color = const Color(0x00000000);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, paddedW.toDouble(), paddedH.toDouble()), paint);

    // Center the scaled image within the padded canvas.
    final offsetX = (paddedW - width) / 2;
    final offsetY = (paddedH - height) / 2;

    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromLTWH(
      offsetX,
      offsetY,
      width.toDouble().clamp(1, paddedW.toDouble()),
      height.toDouble().clamp(1, paddedH.toDouble()),
    );

    canvas.drawImageRect(img, src, dst, Paint());

    final finalImage = await recorder
        .endRecording()
        .toImage(paddedW, paddedH)
        .then((v) => v.toByteData(format: ui.ImageByteFormat.png));

    img.dispose();
    return finalImage!.buffer.asUint8List();
  }

  Future<ImageSource?> _showImageSourcePickerSheet() {
    return showMediaSourcePickerBottomSheet(
      context,
      title: 'Add a photo',
    );
  }

  /// Theme-aware unified bottom-sheet picker
  Future<void> _pickImage(Map<String, dynamic> input) async {
    try {
      final source = await _showImageSourcePickerSheet();

      if (source == null) return;

      if (source == ImageSource.gallery) {
        await _pickImageFromGallery(input);
      } else {
        await _pickImageFromCamera(input);
      }
    } catch (e) {
      debugPrint('❌ Error picking image: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  /// How many more reference images the user can pick (fills partial tasks, then new tasks).
  int _remainingBulkImagePickSlots() {
    var n = 0;
    for (final j in _bulkImageJobs) {
      n += (_bulkMaxInitPerJob - j.length).clamp(0, _bulkMaxInitPerJob);
    }
    final extraTasks =
        (_maxBulkImages - _bulkImageJobs.length).clamp(0, _maxBulkImages);
    n += extraTasks * _bulkMaxInitPerJob;
    return n;
  }

  void _mergeIncomingBulkImages(List<Uint8List> incoming) {
    if (incoming.isEmpty) return;
    final maxJobs = _maxBulkImages;
    final perJob = _bulkMaxInitPerJob;
    var queue = List<Uint8List>.from(incoming);

    while (queue.isNotEmpty) {
      var placedInExisting = false;
      for (var ji = 0; ji < _bulkImageJobs.length; ji++) {
        final room = perJob - _bulkImageJobs[ji].length;
        if (room > 0) {
          final take = min(room, queue.length);
          _bulkImageJobs[ji] = [
            ..._bulkImageJobs[ji],
            ...queue.sublist(0, take),
          ];
          queue.removeRange(0, take);
          placedInExisting = true;
          if (_isAnimateImageTool &&
              _isCineRealAnimateModel &&
              _bulkCineRealTaskHasEndFrame(ji)) {
            _clearBulkCineRealRefVideoAt(ji);
          }
          break;
        }
      }
      if (queue.isEmpty) break;
      if (!placedInExisting) {
        if (_bulkImageJobs.length >= maxJobs) break;
        final take = min(perJob, queue.length);
        _bulkImageJobs.add(queue.sublist(0, take).toList());
        queue.removeRange(0, take);
      }
    }
    if (_isAnimateImageTool && _isCineRealAnimateModel) {
      _syncBulkCineRealRefVideoListsToJobs();
    }
  }

  /// One composer "+ Task" tap = one new bulk row (does not top up older tasks).
  void _mergeIncomingBulkImagesAsNewTaskOnly(List<Uint8List> incoming) {
    if (incoming.isEmpty) return;
    if (_bulkImageJobs.length >= _maxBulkImages) return;
    final take = min(_bulkMaxInitPerJob, incoming.length);
    _bulkImageJobs.add(incoming.sublist(0, take).toList());
    final idx = _bulkImageJobs.length - 1;
    while (_bulkMasks.length <= idx) {
      _bulkMasks.add(null);
    }
    while (_bulkOutpaintConfigs.length <= idx) {
      _bulkOutpaintConfigs.add(null);
    }
    if (_isAnimateImageTool && _isCineRealAnimateModel) {
      _syncBulkCineRealRefVideoListsToJobs();
    }
  }

  /// Pick multiple images for bulk edit.
  ///
  /// [forNewComposerTask]: when true (composer dashed **+ Task** tile), always
  /// append a new task row and assign up to [_bulkMaxInitPerJob] picks to that
  /// row only — never fill spare slots on previous tasks.
  Future<void> _pickBulkImages({bool forNewComposerTask = false}) async {
    try {
      if (forNewComposerTask && _bulkImageJobs.length >= _maxBulkImages) {
        return;
      }
      final int remainingSlots = forNewComposerTask
          ? _bulkMaxInitPerJob
          : _remainingBulkImagePickSlots();
      if (remainingSlots <= 0) return;

      final List<XFile> files;
      if (remainingSlots == 1) {
        final f = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
        files = f == null ? <XFile>[] : <XFile>[f];
      } else {
        files = await picker.pickMultiImage(
          imageQuality: 85,
          limit: remainingSlots,
        );
      }

      if (files.isEmpty) return;

      setState(() => _isProcessingImage = true);

      final List<Uint8List> newImages = [];
      for (final file in files) {
        if (newImages.length >= remainingSlots) break;
        final bytes = await _resizeImageSafe(await file.readAsBytes());
        newImages.add(bytes);
      }

      if (mounted) {
        setState(() {
          if (forNewComposerTask) {
            _mergeIncomingBulkImagesAsNewTaskOnly(newImages);
          } else {
            _mergeIncomingBulkImages(newImages);
          }
          _isProcessingImage = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error picking bulk images: $e');
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting images: $e')),
        );
      }
    }
  }

  /// Add more reference images to one bulk task (multi-init models only).
  Future<void> _pickMoreForBulkTask(int taskIndex) async {
    if (taskIndex < 0 || taskIndex >= _bulkImageJobs.length) return;
    final room = _bulkMaxInitPerJob - _bulkImageJobs[taskIndex].length;
    if (room <= 0) return;
    try {
      final List<XFile> files;
      if (room == 1) {
        final f = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
        files = f == null ? <XFile>[] : <XFile>[f];
      } else {
        files = await picker.pickMultiImage(imageQuality: 85, limit: room);
      }
      if (files.isEmpty) return;
      setState(() => _isProcessingImage = true);
      final extra = <Uint8List>[];
      for (final f in files) {
        if (extra.length >= room) break;
        extra.add(await _resizeImageSafe(await f.readAsBytes()));
      }
      if (mounted) {
        setState(() {
          _clearBulkCineRealRefVideoAt(taskIndex);
          _bulkImageJobs[taskIndex] = [..._bulkImageJobs[taskIndex], ...extra];
          _isProcessingImage = false;
        });
      }
    } catch (e) {
      debugPrint('❌ _pickMoreForBulkTask: $e');
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting images: $e')),
        );
      }
    }
  }

  /// Clear all bulk images
  void _clearBulkImages() {
    setState(() {
      for (var i = 0; i < _bulkCineRealRefVideoPaths.length; i++) {
        _disposeBulkCineRealRefVideoAt(i);
      }
      _bulkCineRealRefVideoBytes.clear();
      _bulkCineRealRefVideoPaths.clear();
      _bulkCineRealRefVideoDurations.clear();
      _bulkImageJobs.clear();
      _bulkMasks.clear();
      _bulkOutpaintConfigs.clear();
    });
  }

  Widget _buildBulkImagesGrid(ColorScheme cs) {
    if (_bulkSupportsMultiInitPerJob) {
      return _buildBulkMultiInitTasksList(cs);
    }
    // Calculate item height based on whether we need mask/outpaint editing
    final double itemHeight = (_requiresMask || _isOutpaint) ? 130 : 100;

    return SizedBox(
      height: itemHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _bulkImageJobs.length,
        itemBuilder: (context, index) {
          final hasMask =
              index < _bulkMasks.length && _bulkMasks[index] != null;
          final hasOutpaintConfig = index < _bulkOutpaintConfigs.length &&
              _bulkOutpaintConfigs[index] != null;

          return Padding(
            padding: EdgeInsets.only(
                right: index < _bulkImageJobs.length - 1 ? 8 : 0),
            child: Column(
              children: [
                GestureDetector(
                  onLongPressStart: (_) {
                    _showBulkImagePreview(index);
                  },
                  onLongPressEnd: (_) {
                    Navigator.of(context, rootNavigator: true).pop();
                  },
                  child: Stack(
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _requiresMask && !hasMask
                                ? cs.error.withValues(alpha: 0.5)
                                : cs.primary.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                _bulkImageJobs[index].first,
                                fit: BoxFit.cover,
                              ),
                              // Show mask overlay if exists
                              if (hasMask)
                                ColorFiltered(
                                  colorFilter: ColorFilter.mode(
                                    Colors.red.withValues(alpha: 0.3),
                                    BlendMode.srcATop,
                                  ),
                                  child: Image.memory(
                                    _bulkMasks[index]!,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Remove button
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeBulkImageAt(index),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cs.error,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              LucideIcons.x,
                              size: 12,
                              color: cs.onError,
                            ),
                          ),
                        ),
                      ),
                      // Index badge
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      // Mask/Outpaint status badge
                      if (_requiresMask || _isOutpaint)
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            decoration: BoxDecoration(
                              color: (hasMask || hasOutpaintConfig)
                                  ? Colors.green.withValues(alpha: 0.9)
                                  : cs.error.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              (hasMask || hasOutpaintConfig)
                                  ? LucideIcons.check
                                  : LucideIcons.alertCircle,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Edit mask/outpaint button
                if (_requiresMask || _isOutpaint) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _editBulkImageConfig(index),
                    child: Container(
                      width: 100,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: (hasMask || hasOutpaintConfig)
                            ? cs.primaryContainer.withValues(alpha: 0.5)
                            : cs.errorContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _requiresMask
                                ? LucideIcons.paintbrush
                                : LucideIcons.move,
                            size: 12,
                            color: (hasMask || hasOutpaintConfig)
                                ? cs.primary
                                : cs.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _requiresMask
                                ? (hasMask ? 'Edit' : 'Mask')
                                : (hasOutpaintConfig ? 'Edit' : 'Place'),
                            style: TextStyle(
                              fontSize: 10,
                              color: (hasMask || hasOutpaintConfig)
                                  ? cs.primary
                                  : cs.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// Remove bulk task at index along with its mask and outpaint config
  void _removeBulkImageAt(int index) {
    setState(() {
      if (index < _bulkCineRealRefVideoBytes.length) {
        _disposeBulkCineRealRefVideoAt(index);
        _bulkCineRealRefVideoBytes.removeAt(index);
        _bulkCineRealRefVideoPaths.removeAt(index);
        _bulkCineRealRefVideoDurations.removeAt(index);
      }
      _bulkImageJobs.removeAt(index);
      if (index < _bulkMasks.length) {
        _bulkMasks.removeAt(index);
      }
      if (index < _bulkOutpaintConfigs.length) {
        _bulkOutpaintConfigs.removeAt(index);
      }
    });
  }

  void _removeBulkTaskSlot(int taskIndex, int slotIndex) {
    if (taskIndex < 0 || taskIndex >= _bulkImageJobs.length) return;
    final job = _bulkImageJobs[taskIndex];
    if (slotIndex < 0 || slotIndex >= job.length) return;
    setState(() {
      job.removeAt(slotIndex);
      if (job.isEmpty) {
        if (taskIndex < _bulkCineRealRefVideoBytes.length) {
          _disposeBulkCineRealRefVideoAt(taskIndex);
          _bulkCineRealRefVideoBytes.removeAt(taskIndex);
          _bulkCineRealRefVideoPaths.removeAt(taskIndex);
          _bulkCineRealRefVideoDurations.removeAt(taskIndex);
        }
        _bulkImageJobs.removeAt(taskIndex);
        if (taskIndex < _bulkMasks.length) {
          _bulkMasks.removeAt(taskIndex);
        }
        if (taskIndex < _bulkOutpaintConfigs.length) {
          _bulkOutpaintConfigs.removeAt(taskIndex);
        }
      }
    });
  }

  /// One row per bulk task when the model allows multiple reference images per job.
  Widget _buildBulkMultiInitTasksList(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(_bulkImageJobs.length, (taskIdx) {
        final job = _bulkImageJobs[taskIdx];
        final canAdd = job.length < _bulkMaxInitPerJob;
        return Padding(
          padding: EdgeInsets.only(
              bottom: taskIdx < _bulkImageJobs.length - 1 ? 10 : 0),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.layers, size: 16, color: cs.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Task ${taskIdx + 1} · ${job.length}/$_bulkMaxInitPerJob reference images',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove task',
                      onPressed: () => _removeBulkImageAt(taskIdx),
                      icon: Icon(LucideIcons.trash2, size: 18, color: cs.error),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Image 1 = primary. Add 2–3 for multi-reference edits (e.g. person + object).',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant, height: 1.25),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 88,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: job.length + (canAdd ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, slotIdx) {
                      if (slotIdx < job.length) {
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            GestureDetector(
                              onLongPressStart: (_) =>
                                  _showBulkSlotPreview(taskIdx, slotIdx),
                              onLongPressEnd: (_) {
                                Navigator.of(context, rootNavigator: true)
                                    .pop();
                              },
                              child: Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: cs.primary.withValues(alpha: 0.35),
                                      width: 1.5),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.memory(job[slotIdx],
                                      fit: BoxFit.cover),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              left: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.surface.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${slotIdx + 1}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () =>
                                    _removeBulkTaskSlot(taskIdx, slotIdx),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: cs.error,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(LucideIcons.x,
                                      size: 11, color: cs.onError),
                                ),
                              ),
                            ),
                          ],
                        );
                      }
                      return Material(
                        color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () => _pickMoreForBulkTask(taskIdx),
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 88,
                            height: 88,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.plus,
                                    color: cs.primary, size: 22),
                                const SizedBox(height: 4),
                                Text(
                                  'Add',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: cs.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  void _showBulkSlotPreview(int taskIndex, int slotIndex) {
    if (taskIndex < 0 || taskIndex >= _bulkImageJobs.length) return;
    final job = _bulkImageJobs[taskIndex];
    if (slotIndex < 0 || slotIndex >= job.length) return;
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      barrierDismissible: false,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: InteractiveViewer(
              maxScale: 5.0,
              minScale: 0.5,
              child: Image.memory(
                job[slotIndex],
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Show full-screen preview for bulk image (called on long press)
  void _showBulkImagePreview(int index) {
    if (index >= _bulkImageJobs.length) return;
    final job = _bulkImageJobs[index];
    if (job.isEmpty) return;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      barrierDismissible: false,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          color: Colors.transparent,
          child: Center(
            child: InteractiveViewer(
              maxScale: 5.0,
              minScale: 0.5,
              child: Image.memory(
                job.first,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Edit mask or outpaint config for a bulk image
  Future<void> _editBulkImageConfig(int index) async {
    if (index >= _bulkImageJobs.length) return;
    final primary = _bulkImageJobs[index].first;

    if (_requiresMask) {
      // Open mask editor for this specific bulk image
      // CRITICAL: Pass the existing mask for THIS bulk image only
      // Set isBulkMode=true to prevent fallback to single image mask
      final existingMask =
          (index < _bulkMasks.length) ? _bulkMasks[index] : null;
      final mask = await _openMaskEditor(
        primary,
        existingMask: existingMask,
        isBulkMode: true, // CRITICAL: Never use single image mask in bulk mode
      );
      if (mask != null && mounted) {
        setState(() {
          // Ensure list is long enough
          while (_bulkMasks.length <= index) {
            _bulkMasks.add(null);
          }
          _bulkMasks[index] = mask;
          debugPrint(
              "✅ Saved mask for bulk image $index (total masks: ${_bulkMasks.length})");
        });
      }
    } else if (_isOutpaint) {
      // Open outpaint canvas for this image
      final result = await Navigator.push<Map<String, String>>(
        context,
        MaterialPageRoute(
          builder: (_) => OutpaintCanvasPage(imageBytes: primary),
          fullscreenDialog: true,
        ),
      );
      if (result != null && mounted) {
        setState(() {
          // Ensure list is long enough
          while (_bulkOutpaintConfigs.length <= index) {
            _bulkOutpaintConfigs.add(null);
          }
          _bulkOutpaintConfigs[index] = result;
        });
      }
    }
  }

  // ---------- Card (uses shared AppStyles for consistency) ----------
  Widget _buildCard({
    required Widget child,
    EdgeInsets? padding,
    EdgeInsets? margin,
    bool elevated = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin:
          margin ?? const EdgeInsets.symmetric(vertical: AppStyles.spacing8),
      padding: padding ?? const EdgeInsets.all(AppStyles.spacing16),
      decoration: AppStyles.cardDecoration(cs, elevated: elevated),
      child: child,
    );
  }

  Widget _buildElement(Map<String, dynamic> e) {
    final type = e["type"];
    final ref = e["input_ref"];

    switch (type) {
      case "prompt":
        return _buildPrompt(ref);
      case "image_upload":
        return _buildImageUpload(ref);
      case "video_upload":
        return _buildVideoUpload(ref);
      case "slider":
        return _buildSlider(ref);
      case "dropdown":
        return _buildDropdown(ref);
      case "choice_menu":
        return _buildSettingsMenu(ref);
      case "toggle":
        return _buildToggle(ref);
      case "painter":
        return _buildPainter(ref);
      case "generate_button":
        return _buildGenerateButton();
      // ── Phase 2 scaffolds: new dynamic element types ──
      case "audio_upload":
        return _buildAudioUpload(ref);
      case "file_upload":
        return _buildFileUpload(ref);
      case "text_input":
        return _buildTextInput(ref);
      case "number_input":
        return _buildNumberInput(ref);
      case "seed_input":
        return _buildSeedInput(ref);
      case "aspect_ratio":
        if (_isVideoTool && !_isVideoUpscalerTool) {
          return const SizedBox.shrink();
        }
        return _buildAspectRatio(ref);
      case "color_picker":
        return _buildColorPicker(ref);
      case "multi_select":
        return _buildMultiSelect(ref);
      case "range_slider":
        return _buildRangeSlider(ref);
      case "info_card":
        return _buildInfoCard(e);
      case "section_header":
        return _buildSectionHeader(e);
      default:
        return const SizedBox.shrink();
    }
  }

  List<String> _parseComposerHintExamples(Map<String, dynamic> input) {
    final raw = input['hintExamples'];
    if (raw is List) {
      final out = <String>[];
      for (final e in raw) {
        final s = e.toString().trim();
        if (s.isNotEmpty) out.add(s);
      }
      if (out.isNotEmpty) return out;
    }
    final label = (input['label'] as String?)?.trim();
    if (label != null && label.isNotEmpty) return [label];
    return const ['Describe your idea…'];
  }

  List<String> _composerHintExamplesFor(dynamic input, String ref) {
    final Map<String, dynamic> m =
        input is Map ? Map<String, dynamic>.from(input) : <String, dynamic>{};
    final key =
        '${_tool.capabilityId}|$ref|${m['label']}|${m['hintExamples']}';
    if (key != _composerHintExamplesKey) {
      _composerHintExamplesKey = key;
      _composerHintExamplesCache = _parseComposerHintExamples(m);
    }
    return _composerHintExamplesCache;
  }

  bool get _isImageStudio => _imageStudioIds.contains(_tool.capabilityId);

  bool get _isVideoStudio => _videoStudioIds.contains(_tool.capabilityId);

  bool get _showStudioChips =>
      (_isImageStudio || _isVideoStudio) &&
      !(_advancedSettings.bulkEditEnabled && _supportsBulkEdit);

  bool get _imageStudioHidesPrompt {
    final id = _tool.capabilityId;
    return id == 'upscale' || id == 'remove_background' || id == 'glm_ocr';
  }

  void _rememberImageStudioFamily() {
    final id = _tool.capabilityId;
    final name = (_selectedModelData?['name'] as String?)?.trim();
    if (name == null || name.isEmpty) return;
    if (id == 'create_image' || id == 'edit_image') {
      _imageStudioFamilyName = name;
    } else if (id == 'create_video' || id == 'animate_image') {
      _videoStudioFamilyName = name;
    }
  }

  Uint8List? _firstImageBytes(Object? value) {
    if (value is Uint8List && value.isNotEmpty) return value;
    if (value is List) {
      for (final item in value) {
        if (item is Uint8List && item.isNotEmpty) return item;
      }
    }
    return null;
  }

  String? _imageInputIdOf(GenericToolConfig config) {
    for (final input in config.inputs) {
      if (input is! Map) continue;
      final type = input['type']?.toString();
      if (type != 'image' && type != 'image_upload') continue;
      final id = input['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  int _imageInputMax(GenericToolConfig config, String id) {
    for (final input in config.inputs) {
      if (input is! Map || input['id']?.toString() != id) continue;
      final maxCount = input['max'];
      if (maxCount is int && maxCount > 0) return maxCount;
      if (maxCount is num && maxCount > 0) return maxCount.toInt();
    }
    return 1;
  }

  void _placeStudioPhotoOn(GenericToolConfig next) {
    String? sourceRef;
    Object? raw;
    for (final ref in const ['init_image', 'image', 'input_image']) {
      if (_firstImageBytes(_inputs[ref]) == null) continue;
      sourceRef = ref;
      raw = _inputs[ref];
      break;
    }
    if (sourceRef == null || raw == null) return;
    final dest = _imageInputIdOf(next);
    if (dest == null || dest == sourceRef) return;
    final path = _inputs['${sourceRef}_path'];
    _inputs.remove(sourceRef);
    _inputs.remove('${sourceRef}_path');
    final maxCount = _imageInputMax(next, dest);
    if (raw is List && maxCount <= 1) {
      final first = _firstImageBytes(raw);
      if (first != null) _inputs[dest] = [first];
    } else if (raw is Uint8List) {
      _inputs[dest] = [raw];
    } else {
      _inputs[dest] = raw;
    }
    if (path is String && path.isNotEmpty) {
      _inputs['${dest}_path'] = path;
    }
  }

  String? _modelIdNamed(Map<String, dynamic> capability, String name) {
    final models = capability['models'];
    if (models is! List) return null;
    for (final raw in models) {
      if (raw is! Map) continue;
      if (raw['enabled'] == false) continue;
      if ((raw['name'] as String?)?.trim() != name) continue;
      final id = raw['id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    return null;
  }

  List<Map<String, dynamic>> _createImageAttachInputs() {
    return [
      {
        'id': 'init_image',
        'type': 'image',
        'label': 'Photo',
        'min': 1,
        'max': 1,
      },
    ];
  }

  List<Map<String, dynamic>> _composerAttachInputs(
    List<Map<String, dynamic>> declared,
  ) {
    if (_tool.capabilityId == 'create_image') return _createImageAttachInputs();
    if (_tool.capabilityId == 'create_video' &&
        !(_advancedSettings.bulkEditEnabled && _supportsBulkEdit)) {
      return [..._createImageAttachInputs(), ...declared];
    }
    return declared;
  }

  Future<void> _maybePromoteCreateToEdit() async {
    if (!mounted) return;
    if (_advancedSettings.bulkEditEnabled && _supportsBulkEdit) return;
    if (_firstImageBytes(_inputs['init_image']) == null) return;
    final id = _tool.capabilityId;
    if (id == 'create_image') {
      await _switchImageStudio('edit_image');
    } else if (id == 'create_video') {
      await _switchImageStudio('animate_image');
    }
  }

  Future<void> _switchImageStudio(String capabilityId) async {
    if (_imageStudioSwitching || _tool.capabilityId == capabilityId) return;
    if (!_imageStudioIds.contains(capabilityId) &&
        !_videoStudioIds.contains(capabilityId)) {
      return;
    }
    _imageStudioSwitching = true;
    try {
      _rememberImageStudioFamily();
      final book = await loadCachedToolConfig();
      if (!mounted) return;
      final cap = book == null ? null : capabilityById(book, capabilityId);
      if (cap == null || !capabilityHasEnabledModel(cap)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That tool is not available right now.')),
        );
        return;
      }
      final imageDestination =
          capabilityId == 'create_image' || capabilityId == 'edit_image';
      final videoDestination =
          capabilityId == 'create_video' || capabilityId == 'animate_image';
      final family = imageDestination
          ? _imageStudioFamilyName
          : videoDestination
              ? _videoStudioFamilyName
              : null;
      final preferred =
          family == null ? null : _modelIdNamed(cap, family);
      final next = genericConfigFromCapability(
        cap,
        preferredModelId: preferred,
      );
      Map<String, dynamic>? model;
      for (final entry in next.models ?? const <Map<String, dynamic>>[]) {
        if (entry['id'] == next.model) {
          model = entry;
          break;
        }
      }
      _imageStudioConfig = next;
      _placeStudioPhotoOn(next);
      _inputs['prompt'] = _promptController.text;
      if (capabilityId != 'edit_image') {
        _inputs.remove('mask_image');
      }
      if (model != null) {
        _selectModel(model);
      } else {
        setState(() {});
      }
      if (capabilityId == 'expand_scene') {
        await _openExpandCanvasIfNeeded();
      }
    } finally {
      _imageStudioSwitching = false;
    }
  }

  void _clearStudioOutpaint() {
    const keys = [
      'alignment',
      'is_custom',
      'custom_scale',
      'norm_offset_x',
      'norm_offset_y',
      'offset_x',
      'offset_y',
      'canvas_width',
      'canvas_height',
      'fitted_width',
      'fitted_height',
      'image_width',
      'image_height',
      'image_left',
      'image_top',
      'outpaint_preview',
    ];
    for (final key in keys) {
      _inputs.remove(key);
    }
  }

  void _storeOutpaintResult(Map<String, String> result, Uint8List bytes) {
    _inputs['alignment'] = result['alignment'];
    _inputs['aspect_ratio'] = result['aspect_ratio'];
    _inputs['is_custom'] = result['is_custom'];
    _inputs['custom_scale'] = result['custom_scale'];
    _inputs['norm_offset_x'] = result['norm_offset_x'];
    _inputs['norm_offset_y'] = result['norm_offset_y'];
    _inputs['offset_x'] = result['offset_x'];
    _inputs['offset_y'] = result['offset_y'];
    _inputs['canvas_width'] = result['canvas_width'];
    _inputs['canvas_height'] = result['canvas_height'];
    _inputs['fitted_width'] = result['fitted_width'];
    _inputs['fitted_height'] = result['fitted_height'];
    _inputs['image_width'] = result['image_width'];
    _inputs['image_height'] = result['image_height'];
    _inputs['image_left'] = result['image_left'];
    _inputs['image_top'] = result['image_top'];
    _inputs['outpaint_preview'] = bytes;
  }

  Future<void> _openExpandCanvasIfNeeded() async {
    if (!mounted || _tool.capabilityId != 'expand_scene') return;
    final alignment = _inputs['alignment']?.toString().trim() ?? '';
    if (alignment.isNotEmpty) return;
    final bytes = _firstImageBytes(_inputs['init_image']) ??
        _firstImageBytes(_inputs['image']);
    if (bytes == null) return;
    final result = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => OutpaintCanvasPage(imageBytes: bytes),
        fullscreenDialog: true,
      ),
    );
    if (result != null && mounted) {
      setState(() => _storeOutpaintResult(result, bytes));
    }
  }

  List<(String, IconData, String)> get _studioChipOptions {
    if (_isVideoStudio) {
      return const [
        ('create_video', LucideIcons.video, 'Create video'),
        ('animate_image', LucideIcons.film, 'Animate image'),
      ];
    }
    return const [
      ('create_image', LucideIcons.wand2, 'Create image'),
      ('edit_image', LucideIcons.sparkles, 'Edit image'),
      ('upscale', LucideIcons.maximize2, 'Upscale image'),
      ('remove_background', LucideIcons.scissors, 'Remove background'),
      ('expand_scene', LucideIcons.crop, 'Expand scene'),
      ('glm_ocr', LucideIcons.fileText, 'Extract text'),
    ];
  }

  Widget _buildImageStudioChips(ColorScheme cs) {
    final options = _studioChipOptions;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, index) {
          final option = options[index];
          final selected = _tool.capabilityId == option.$1;
          return Semantics(
            button: true,
            selected: selected,
            label: option.$3,
            child: Tooltip(
              message: option.$3,
              child: Material(
                color: selected
                    ? cs.primary
                    : cs.surfaceContainerHigh.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppStyles.radiusFull),
                child: InkWell(
                  onTap: () => unawaited(_switchImageStudio(option.$1)),
                  borderRadius: BorderRadius.circular(AppStyles.radiusFull),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      option.$2,
                      size: 18,
                      color: selected ? cs.onPrimary : cs.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---------- Composer Card ----------
  /// Glass composer card used for the `prompt` element. Combines selected
  /// Style/Template chips, the prompt TextField, and a meta row with
  /// output-type and model badges. Backed by the existing `_promptController`,
  /// `_selectedStyle`, and `_removeStyleFromPrompt` logic.
  Widget _buildComposerCard(String ref) {
    final cs = Theme.of(context).colorScheme;
    final promptLength = _promptController.text.length;
    final effectivePromptInput = _effectiveInputConfig(ref);
    final hintLabel = _sunoSounds
        ? 'Rain on a tin roof, a vinyl crackle, distant thunder'
        : _isMusicTool && !_musicEasy
            ? 'Style, instruments, mood, and how the song moves'
            : ((effectivePromptInput["label"] as String?) ??
                'Describe what you want to create…');
    final hintExamples = _composerHintExamplesFor(effectivePromptInput, ref);
    final showStreamingHint = _promptController.text.isEmpty &&
        !_promptFocusNode.hasFocus &&
        !_promptFilling;

    final modelName = _selectedModelData?['name'] as String? ??
        _tool.models?.firstWhere(
          (m) => m['id'] == (_selectedModelId ?? _tool.model),
          orElse: () => {'name': _tool.model},
        )['name'] as String? ??
        _tool.model;

    final attachments = _collectComposerAttachments();
    final attachInputs = _attachableInputs();
    final canAttach = attachInputs.isNotEmpty;
    final isBulkMode = _advancedSettings.bulkEditEnabled && _supportsBulkEdit;
    final showComposerAttachRow =
        attachments.isNotEmpty || (isBulkMode && canAttach);

    return Stack(
      children: [
        // Subtle radial glow behind the composer (decorative only).
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 1.2,
                  colors: [
                    KalaColors.purple.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: _composerCardDecoration(cs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showStudioChips) ...[
                _buildImageStudioChips(cs),
                const SizedBox(height: 10),
              ],
              // Inline attachment thumbnails (image/video/audio/file) — mirrors
              // _inputs state; tap a chip for actions, × removes it.
              // In bulk mode, keep the row visible (add-task tile) even when empty.
              if (_requiresEndFrame) ...[
                Text(
                  attachments.any((a) => a.ref == 'init_image') &&
                          attachments.any((a) => a.ref == 'last_frame_image')
                      ? 'Start frame and end frame are set.'
                      : 'Pick the start frame, then the end frame.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (showComposerAttachRow) ...[
                _buildComposerAttachmentsRow(cs, attachments),
                const SizedBox(height: 10),
              ] else if (canAttach && !_isVideoStudio) ...[
                _buildMediaComposerEmptyHint(cs, attachInputs),
                const SizedBox(height: 10),
              ],
              if (_tool.capabilityId == 'edit_image') ...[
                _buildEditBrushRow(cs, attachments),
                const SizedBox(height: 8),
              ],

              // Selected Style chip row
              if (_selectedStyle != null) ...[
                _buildComposerChipRow(cs),
                const SizedBox(height: 8),
              ],

              if (_isMusicTool) ...[
                Text(
                  'Prompt',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
              ],

              if (_promptFilling)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Writing the cover prompt…',
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

              // Prompt TextField + cycling typewriter hints from tool_config [hintExamples].
              Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  TextField(
                    focusNode: _promptFocusNode,
                    controller: _promptController,
                    readOnly: _promptFilling,
                    onChanged: (v) {
                      _inputs[ref] = v;
                      setState(() {});
                    },
                    maxLines: _kComposerPromptMaxLines,
                    minLines: (_isImageStudio || _isVideoStudio)
                        ? 8
                        : _kComposerPromptMinLines,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 15,
                      height: 1.45,
                    ),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                      hintText: _promptFocusNode.hasFocus &&
                              _promptController.text.isEmpty
                          ? hintLabel
                          : null,
                      hintStyle: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                        fontSize: 15,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      suffixIcon: _clearTextButton(
                        visible: _promptController.text.isNotEmpty,
                        tooltip: 'Clear prompt',
                        onPressed: () => _clearPromptField(ref),
                      ),
                    ),
                  ),
                  if (showStreamingHint)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: StreamingComposerHint(
                            examples: hintExamples,
                            active: showStreamingHint,
                            textStyle: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                              fontSize: 15,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              if (_isSpeechTool &&
                  (_selectedModelId ?? _tool.model) ==
                      'qwen_voice_clone' &&
                  _inputs['reference_audio'] is! Uint8List)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Attach a few seconds of the voice above',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                      fontSize: 12.5,
                    ),
                  ),
                ),

              // Divider line
              const SizedBox(height: 6),
              Container(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 8),

              // Attach, style, and settings stay on this row. Tool switches sit above.
              Row(
                children: [
                  if (_showStudioChips)
                    const Spacer()
                  else ...[
                    if (canAttach) ...[
                      _ComposerIconButton(
                        icon: LucideIcons.plus,
                        tooltip: 'Attach',
                        onTap: () => _showAttachSheet(attachInputs),
                        active: attachments.isNotEmpty,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (_supportsBulkEdit) ...[
                      _buildImageModeSwitch(
                        cs,
                        isVipUser(),
                        isBulkMode,
                        iconOnly: true,
                        beforeLeaveBulk: _leaveBulkModeCleanup,
                        onEnterBulk: _enterBulkModeSetup,
                      ),
                      const SizedBox(width: 6),
                      _buildComposerBulkModeBadge(cs),
                      const Spacer(),
                    ] else ...[
                      const Spacer(),
                    ],
                  ],
                  if (_showStudioChips && _supportsBulkEdit) ...[
                    _buildImageModeSwitch(
                      cs,
                      isVipUser(),
                      isBulkMode,
                      iconOnly: true,
                      beforeLeaveBulk: _leaveBulkModeCleanup,
                      onEnterBulk: _enterBulkModeSetup,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (_showStudioChips &&
                      (canAttach ||
                          _tool.capabilityId == 'create_image' ||
                          _tool.capabilityId == 'create_video')) ...[
                    _ComposerIconButton(
                      icon: LucideIcons.plus,
                      tooltip: 'Attach',
                      onTap: () =>
                          _showAttachSheet(_composerAttachInputs(attachInputs)),
                      active: attachments.isNotEmpty,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (!_imageStudioHidesPrompt &&
                      !_isAudioTool &&
                      !_hidesStyleAndTags)
                    _ComposerIconButton(
                      icon: LucideIcons.palette,
                      tooltip: _promptStylesVisible
                          ? 'Hide Style & Tags'
                          : 'Show Style & Tags',
                      onTap: () => setState(
                          () => _promptStylesVisible = !_promptStylesVisible),
                      active: _promptStylesVisible,
                    ),
                  if (!_imageStudioHidesPrompt) ...[
                    const SizedBox(width: 6),
                    _autoPromptButton(
                    fieldRef: ref,
                    suggestField: 'prompt',
                    currentText: _promptController.text,
                    apply: (value) {
                      _promptController.value = TextEditingValue(
                        text: value,
                        selection: TextSelection.collapsed(offset: value.length),
                      );
                      _inputs[ref] = value;
                    },
                  ),
                  ],
                  if (!_isInpaintEraseTool) ...[
                    const SizedBox(width: 6),
                    _ComposerIconButton(
                      icon: LucideIcons.settings,
                      tooltip: 'Settings · $modelName',
                      onTap: _showAdvancedSettings,
                      active: false,
                    ),
                  ],
                  const SizedBox(width: 6),
                  // Char counter (only when there is text)
                  AnimatedOpacity(
                    opacity: promptLength > 0 ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      '$promptLength',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One-line hint when no media is attached yet (tools without a prompt).
  Widget _buildMediaComposerEmptyHint(
      ColorScheme cs, List<Map<String, dynamic>> attachInputs) {
    if (attachInputs.isEmpty) return const SizedBox.shrink();
    final first = attachInputs.first;
    final t = first['type'] as String?;
    IconData icon = LucideIcons.imagePlus;
    String line = 'Tap + to add media';
    switch (t) {
      case 'image':
      case 'image_upload':
        icon = LucideIcons.image;
        line = _requiresEndFrame
            ? 'Pick the start frame, then the end frame.'
            : 'Tap + to add an image';
        break;
      case 'video':
      case 'video_upload':
        icon = LucideIcons.video;
        line = 'Tap + to add a video';
        break;
      case 'audio_upload':
        icon = LucideIcons.music;
        line = 'Tap + to add audio';
        break;
      case 'file_upload':
        icon = LucideIcons.fileText;
        line = 'Tap + to add a file';
        break;
    }
    return InkWell(
      onTap: () => _showAttachSheet(attachInputs),
      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
      child: Container(
        height: 62,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: cs.primary.withValues(alpha: 0.65)),
            const SizedBox(width: 10),
            Text(
              line,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Glass card for tools that have **no** `prompt` element but need uploads
  /// (upscale, remove bg, inpaint, video upscale, extract text, etc.).
  /// Tool name lives in the [AppBar] only — no duplicate heading inside the card.
  Widget _buildStandaloneMediaComposer() {
    final cs = Theme.of(context).colorScheme;
    final attachInputs = _attachableInputs();
    if (attachInputs.isEmpty) return const SizedBox.shrink();

    final modelName = _selectedModelData?['name'] as String? ??
        _tool.models?.firstWhere(
          (m) => m['id'] == (_selectedModelId ?? _tool.model),
          orElse: () => {'name': _tool.model},
        )['name'] as String? ??
        _tool.model;

    final attachments = _collectComposerAttachments();
    final canAttach = attachInputs.isNotEmpty;
    final isBulkMode = _advancedSettings.bulkEditEnabled && _supportsBulkEdit;
    final showComposerAttachRow =
        attachments.isNotEmpty || (isBulkMode && canAttach);

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.2),
                  radius: 1.2,
                  colors: [
                    KalaColors.purple.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.surfaceContainerHighest.withValues(alpha: 0.35),
                cs.surfaceContainerHigh.withValues(alpha: 0.18),
              ],
            ),
            borderRadius: BorderRadius.circular(AppStyles.radiusLg),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.22),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: KalaColors.purple.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_showStudioChips) ...[
                _buildImageStudioChips(cs),
                const SizedBox(height: 10),
              ],
              if (_requiresEndFrame) ...[
                Text(
                  attachments.any((a) => a.ref == 'init_image') &&
                          attachments.any((a) => a.ref == 'last_frame_image')
                      ? 'Start frame and end frame are set.'
                      : 'Pick the start frame, then the end frame.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (showComposerAttachRow) ...[
                _buildComposerAttachmentsRow(cs, attachments),
                const SizedBox(height: 10),
              ] else if (canAttach) ...[
                _buildMediaComposerEmptyHint(cs, attachInputs),
                const SizedBox(height: 10),
              ],
              if (_isVideoUpscalerTool &&
                  !isBulkMode &&
                  (_inputs['input_video_path'] as String?)?.isNotEmpty ==
                      true) ...[
                const SizedBox(height: 12),
                _buildVideoPreview('input_video'),
              ],
              const SizedBox(height: 4),
              Container(
                height: 1,
                color: cs.outlineVariant.withValues(alpha: 0.15),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_showStudioChips)
                    const Spacer()
                  else ...[
                    if (canAttach) ...[
                      _ComposerIconButton(
                        icon: LucideIcons.plus,
                        tooltip: 'Add media',
                        onTap: () => _showAttachSheet(attachInputs),
                        active: attachments.isNotEmpty,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (_supportsBulkEdit) ...[
                      _buildImageModeSwitch(
                        cs,
                        isVipUser(),
                        isBulkMode,
                        iconOnly: true,
                        beforeLeaveBulk: _leaveBulkModeCleanup,
                        onEnterBulk: _enterBulkModeSetup,
                      ),
                      const SizedBox(width: 6),
                      _buildComposerBulkModeBadge(cs),
                      const Spacer(),
                    ] else ...[
                      const Spacer(),
                    ],
                  ],
                  if (_showStudioChips &&
                      (canAttach ||
                          _tool.capabilityId == 'create_image' ||
                          _tool.capabilityId == 'create_video')) ...[
                    _ComposerIconButton(
                      icon: LucideIcons.plus,
                      tooltip: 'Add media',
                      onTap: () =>
                          _showAttachSheet(_composerAttachInputs(attachInputs)),
                      active: attachments.isNotEmpty,
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (!_isInpaintEraseTool)
                    _ComposerIconButton(
                      icon: LucideIcons.settings,
                      tooltip: 'Settings · $modelName',
                      onTap: _showAdvancedSettings,
                      active: false,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Composer attachments
  // Build a list of the currently-attached assets (images, videos, audio,
  // files) across every declared upload input so they can be shown inline in
  // the composer without scrolling to a separate upload card.
  // ─────────────────────────────────────────────────────────────────────────

  List<_ComposerAttachment> _collectComposerAttachments() {
    final out = <_ComposerAttachment>[];

    bool isBulkMode = _advancedSettings.bulkEditEnabled && _supportsBulkEdit;

    // Bulk mode → show one tile per bulk job (image or video) only — never fall
    // through to [_inputs] or single-mode chips would reappear after toggling.
    if (isBulkMode) {
      if (_supportsBulkVideoEdit) {
        for (int i = 0; i < _bulkVideoPaths.length; i++) {
          out.add(_ComposerAttachment(
            ref: _bulkPrimaryVideoInputRef ?? 'init_video',
            kind: _ComposerAttachmentKind.bulkVideo,
            index: i,
            label: 'Video ${i + 1}',
            filePath: _bulkVideoPaths[i],
          ));
        }
        return out;
      }
      if (_supportsBulkImageEdit) {
        _syncBulkCineRealRefVideoListsToJobs();
        for (int i = 0; i < _bulkImageJobs.length; i++) {
          final job = _bulkImageJobs[i];
          if (job.isEmpty) continue;
          out.add(_ComposerAttachment(
            ref: _bulkPrimaryImageInputRef ?? 'init_image',
            kind: _ComposerAttachmentKind.bulkImage,
            index: i,
            label: _bulkSupportsMultiInitPerJob
                ? 'Task ${i + 1} · ${job.length}/$_bulkMaxInitPerJob'
                : 'Task ${i + 1}',
            thumbBytes: job.first,
            // Stash the full ref-image group so the tile can render stacked refs.
            extraThumbs: job.length > 1 ? job.skip(1).toList() : null,
          ));
          if (_isAnimateImageTool &&
              _isCineRealAnimateModel &&
              _bulkCineRealTaskHasRefVideo(i)) {
            final p = i < _bulkCineRealRefVideoPaths.length
                ? _bulkCineRealRefVideoPaths[i]
                : null;
            if (p != null && p.isNotEmpty) {
              out.add(_ComposerAttachment(
                ref: 'ref_video',
                kind: _ComposerAttachmentKind.bulkCineRealRefVideo,
                index: i,
                label: 'Clip ${i + 1} · ref',
                filePath: p,
              ));
            }
          }
        }
        return out;
      }
    }

    // Single-mode attachments across all declared inputs.
    for (final i in _tool.inputs) {
      final id = i['id'] as String?;
      final t = i['type'] as String?;
      if (id == null || t == null) continue;
      final v = _inputs[id];
      final path = _inputs['${id}_path'] as String?;
      switch (t) {
        case 'image':
        case 'image_upload':
          // Inpaint / erase: mask is edited from the init image tile, not a second chip.
          if (_requiresMask && id == 'mask_image') {
            break;
          }
          // CineReal: end frame is merged into the init chip in the composer.
          if (_isAnimateImageTool &&
              _isCineRealAnimateModel &&
              id == 'last_frame_image') {
            break;
          }
          if (v is List && v.isNotEmpty && v.first is Uint8List) {
            final list = v.cast<Uint8List>();
            for (int k = 0; k < list.length; k++) {
              out.add(_ComposerAttachment(
                ref: id,
                kind: _ComposerAttachmentKind.image,
                index: k,
                label: list.length > 1 ? 'Image ${k + 1}' : 'Image',
                thumbBytes: list[k],
              ));
            }
          } else if (v is Uint8List && v.isNotEmpty) {
            out.add(_ComposerAttachment(
              ref: id,
              kind: _ComposerAttachmentKind.image,
              index: 0,
              label: 'Image',
              thumbBytes: v,
            ));
          }
          break;
        case 'video':
        case 'video_upload':
          if (path != null && path.isNotEmpty) {
            out.add(_ComposerAttachment(
              ref: id,
              kind: _ComposerAttachmentKind.video,
              index: 0,
              label: 'Video',
              filePath: path,
            ));
          }
          break;
        case 'audio_upload':
          if (_isSpeechTool || _isMusicTool) break;
          if (v is Uint8List && v.isNotEmpty) {
            out.add(_ComposerAttachment(
              ref: id,
              kind: _ComposerAttachmentKind.audio,
              index: 0,
              label: _inputs['${id}_name'] as String? ?? 'Audio',
            ));
          }
          break;
        case 'file_upload':
          if (v is Uint8List && v.isNotEmpty) {
            out.add(_ComposerAttachment(
              ref: id,
              kind: _ComposerAttachmentKind.file,
              index: 0,
              label: _inputs['${id}_name'] as String? ?? 'File',
            ));
          }
          break;
      }
    }
    if (_isAnimateImageTool && _isCineRealAnimateModel) {
      final lastB = _bytesForInputKey('last_frame_image');
      if (lastB != null && lastB.isNotEmpty) {
        final idx = out.indexWhere(
          (a) =>
              a.kind == _ComposerAttachmentKind.image && a.ref == 'init_image',
        );
        if (idx >= 0) {
          final initA = out[idx];
          final tb = initA.thumbBytes;
          if (tb != null && tb.isNotEmpty) {
            out[idx] = _ComposerAttachment(
              ref: 'init_image',
              kind: _ComposerAttachmentKind.image,
              index: 0,
              label: 'Keyframes',
              thumbBytes: tb,
              extraThumbs: [lastB],
            );
          }
        }
      }
    }
    return out;
  }

  bool _isPromptStyleRef(String ref) {
    switch (ref) {
      case 'prompt':
      case 'lyrics':
      case 'style':
      case 'negative':
      case 'negative_prompt':
      case 'negative_tags':
      case 'voice_description':
        return true;
      default:
        return false;
    }
  }

  String _suggestFieldForRef(String ref) {
    switch (ref) {
      case 'lyrics':
      case 'style':
      case 'voice_description':
        return ref;
      case 'negative':
      case 'negative_prompt':
      case 'negative_tags':
        return 'negative';
      default:
        return 'prompt';
    }
  }

  bool get _captionFromAttachment {
    final id = _tool.capabilityId;
    return id == 'edit_image' || id == 'expand_scene' || _isOutpaint;
  }

  Widget _autoPromptButton({
    required String fieldRef,
    required String suggestField,
    required String currentText,
    required void Function(String value) apply,
    StateSetter? sheetSetter,
  }) {
    final busy = _composerAutoPromptLoading && _autoPromptField == fieldRef;
    final empty = currentText.trim().isEmpty;
    return _ComposerIconButton(
      icon: LucideIcons.sparkles,
      tooltip: empty ? 'Write a prompt' : 'Refine this prompt',
      onTap: _composerAutoPromptLoading
          ? () {}
          : () => unawaited(_suggestForField(
                fieldRef: fieldRef,
                suggestField: suggestField,
                currentText: currentText,
                apply: apply,
                sheetSetter: sheetSetter,
              )),
      busy: busy,
      enabled: !_composerAutoPromptLoading,
    );
  }

  Future<String?> _captionForAutoPrompt(Uint8List bytes, String token) async {
    final urls = await MediaUploadService.getMediaUploadUrls(
      count: 1,
      mediaType: 'image',
      authToken: token,
      baseUrl: controllerUrl,
    );
    if (!mounted) return null;
    if (urls == null || urls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not get upload URL. Check your connection.'),
        ),
      );
      return null;
    }
    final putOk = await MediaUploadService.uploadToR2(
      urls.first.uploadUrl,
      bytes,
      contentType: 'image/jpeg',
    );
    if (!mounted) return null;
    if (!putOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload failed. Try again.')),
      );
      return null;
    }
    final (caption, err) = await MediaUploadService.describeAssetForPrompt(
      baseUrl: controllerUrl,
      authToken: token,
      inputR2Key: urls.first.r2Key,
      contentType: 'image/jpeg',
    );
    if (!mounted) return null;
    if (caption == null || caption.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err ?? 'Could not read the picture.')),
      );
      return null;
    }
    return caption.trim();
  }

  Future<void> _suggestForField({
    required String fieldRef,
    required String suggestField,
    required String currentText,
    required void Function(String value) apply,
    StateSetter? sheetSetter,
  }) async {
    if (_composerAutoPromptLoading) return;
    final typed = currentText.trim();
    setState(() {
      _composerAutoPromptLoading = true;
      _autoPromptField = fieldRef;
    });
    sheetSetter?.call(() {});
    try {
      final token = await _authService.getIdToken();
      if (!mounted) return;
      if (token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to use auto-prompt.')),
        );
        return;
      }
      String? caption;
      if (typed.isEmpty && _captionFromAttachment) {
        final bytes = await _bytesForComposerAutoPrompt();
        if (!mounted) return;
        if (bytes != null && bytes.isNotEmpty) {
          caption = await _captionForAutoPrompt(bytes, token);
          if (!mounted || caption == null) return;
        }
      }
      final relate = _relatesMusicFields(fieldRef);
      final filledBoxes = <String, String>{};
      final also = <String>[];
      if (relate) {
        for (final ref in _advancedMusicBoxRefs()) {
          if (ref == fieldRef) continue;
          final value = _musicBoxText(ref).trim();
          if (value.isEmpty) {
            also.add(ref);
          } else {
            filledBoxes[ref] = value;
          }
        }
        if (fieldRef != 'prompt') {
          final idea = _promptController.text.trim();
          if (idea.isNotEmpty) filledBoxes.putIfAbsent('prompt', () => idea);
        }
        if (_isSunoV6 && fieldRef != 'style') {
          final style = _sunoStyleController.text.trim();
          if (style.isNotEmpty) filledBoxes.putIfAbsent('style', () => style);
        }
      }
      final (prompt, err, related) = await MediaUploadService.suggestPrompt(
        baseUrl: controllerUrl,
        authToken: token,
        modelId: _selectedModelId ?? _tool.model,
        field: relate ? fieldRef : suggestField,
        text: typed,
        caption: caption,
        context: filledBoxes,
        also: also,
      );
      if (!mounted) return;
      if (prompt == null || prompt.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err ?? 'Auto-prompt failed.')),
        );
        return;
      }
      apply(prompt.trim());
      if (relate) {
        for (final entry in related.entries) {
          if (entry.key == fieldRef) continue;
          _writeMusicBoxIfEmpty(entry.key, entry.value);
        }
      }
      setState(() {});
      sheetSetter?.call(() {});
    } finally {
      if (mounted) {
        setState(() {
          _composerAutoPromptLoading = false;
          _autoPromptField = null;
        });
        sheetSetter?.call(() {});
      }
    }
  }

  Future<Uint8List?> _bytesForComposerAutoPrompt() async {
    for (final a in _collectComposerAttachments()) {
      if (a.kind == _ComposerAttachmentKind.image ||
          a.kind == _ComposerAttachmentKind.bulkImage) {
        final b = a.thumbBytes;
        if (b != null && b.isNotEmpty) {
          return Uint8List.fromList(b);
        }
      }
      if (!kIsWeb &&
          (a.kind == _ComposerAttachmentKind.video ||
              a.kind == _ComposerAttachmentKind.bulkVideo ||
              a.kind == _ComposerAttachmentKind.bulkCineRealRefVideo)) {
        final path = a.filePath;
        if (path != null && path.isNotEmpty) {
          try {
            final t = await VideoThumbnail.thumbnailData(
              video: path,
              imageFormat: ImageFormat.JPEG,
              maxWidth: 1280,
              quality: 85,
              timeMs: 0,
            );
            if (t != null && t.isNotEmpty) {
              return Uint8List.fromList(t);
            }
          } catch (_) {}
        }
      }
    }
    return null;
  }

  /// Inputs on this tool that can be attached through the composer's + sheet.
  List<Map<String, dynamic>> _attachableInputs() {
    return _tool.inputs
        .where((i) {
          final t = i['type'];
          final ok = t == 'image' ||
              t == 'image_upload' ||
              t == 'video' ||
              t == 'video_upload' ||
              t == 'audio_upload' ||
              t == 'file_upload';
          if (!ok) return false;
          if (_isMusicTool &&
              (t == 'audio_upload' ||
                  t == 'video' ||
                  t == 'image' ||
                  t == 'video_upload' ||
                  t == 'image_upload')) {
            return false;
          }
          if (_isSpeechTool && t == 'audio_upload') {
            return false;
          }
          return _elementShouldRender(Map<String, dynamic>.from(i as Map));
        })
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Widget _buildComposerAttachmentsRow(
      ColorScheme cs, List<_ComposerAttachment> items) {
    final isBulkMode = _advancedSettings.bulkEditEnabled && _supportsBulkEdit;
    // In bulk mode, show an "Add task" tile at the end so the whole bulk flow
    // lives inside the composer without an external upload card.
    final bool showAddTaskTile = isBulkMode &&
        ((_supportsBulkImageEdit && _bulkImageJobs.length < _maxBulkImages) ||
            (_supportsBulkVideoEdit &&
                _bulkVideoPaths.length < _maxBulkImages));

    return SizedBox(
      height: 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length + (showAddTaskTile ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          if (i >= items.length) {
            return _buildAddBulkTaskTile(cs);
          }
          return _buildComposerAttachmentTile(cs, items[i]);
        },
      ),
    );
  }

  /// Dashed "+ Add task" tile at the end of the bulk attachments row.
  Widget _buildAddBulkTaskTile(ColorScheme cs) {
    return InkWell(
      onTap: () {
        if (_supportsBulkVideoEdit) {
          final vi = _tool.inputs.firstWhere(
            (i) => i['type'] == 'video' || i['type'] == 'video_upload',
            orElse: () => <String, dynamic>{},
          );
          if (vi.isNotEmpty) _pickVideosForBulk(Map<String, dynamic>.from(vi));
        } else {
          _pickBulkImages(forNewComposerTask: true);
        }
      },
      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
      child: DottedRoundedContainer(
        width: 62,
        height: 62,
        color: cs.outlineVariant.withValues(alpha: 0.5),
        radius: AppStyles.radiusMd,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.plus,
                size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.85)),
            const SizedBox(height: 2),
            Text(
              'Task',
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mask bytes drawn on top of the init / bulk image tile (not a separate chip).
  Uint8List? _maskBytesOverlayForComposerTile(_ComposerAttachment a) {
    if (a.kind == _ComposerAttachmentKind.bulkImage &&
        _requiresMask &&
        a.index < _bulkMasks.length &&
        _bulkMasks[a.index] != null) {
      final m = _bulkMasks[a.index]!;
      if (m.isNotEmpty) return m;
    }
    if (a.kind == _ComposerAttachmentKind.image &&
        _requiresMask &&
        a.ref == 'init_image') {
      final m = _inputs['mask_image'];
      if (m is Uint8List && m.isNotEmpty) return m;
    }
    return null;
  }

  Widget _composerAttachmentPreviewFill(
    ColorScheme cs,
    _ComposerAttachment a,
    IconData fallbackIcon,
  ) {
    final path = a.filePath;
    final useVideoThumb = !kIsWeb &&
        (a.kind == _ComposerAttachmentKind.video ||
            a.kind == _ComposerAttachmentKind.bulkVideo ||
            a.kind == _ComposerAttachmentKind.bulkCineRealRefVideo) &&
        path != null &&
        path.isNotEmpty;

    if (useVideoThumb) {
      return _BulkVideoStripThumb(
        videoPath: path,
        placeholderColor: cs.onSurfaceVariant.withValues(alpha: 0.55),
      );
    }

    if (a.thumbBytes != null) {
      final maskOv = _maskBytesOverlayForComposerTile(a);
      if (a.kind == _ComposerAttachmentKind.bulkImage &&
          _isOutpaint &&
          a.index < _bulkOutpaintConfigs.length &&
          _bulkOutpaintConfigs[a.index] != null) {
        final cfg = _bulkOutpaintConfigs[a.index]!;
        final alignment = cfg['alignment'] ?? 'Middle';
        final isCustomMode = cfg['is_custom'] == 'true';
        final customScale = isCustomMode
            ? (double.tryParse(cfg['custom_scale'] ?? '0.7') ?? 0.7)
            : 1.0;
        final normOffsetX = double.tryParse(cfg['norm_offset_x'] ?? '0') ?? 0.0;
        final normOffsetY = double.tryParse(cfg['norm_offset_y'] ?? '0') ?? 0.0;
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildOutpaintPreview(
              a.thumbBytes!,
              cs,
              isCustomMode: isCustomMode,
              customScale: customScale,
              normOffsetX: normOffsetX,
              normOffsetY: normOffsetY,
              alignment: alignment,
              compact: true,
            ),
            if (maskOv != null)
              ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.red.withValues(alpha: 0.7),
                  BlendMode.srcATop,
                ),
                child: Image.memory(
                  maskOv,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
          ],
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            a.thumbBytes!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
          if (maskOv != null)
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.red.withValues(alpha: 0.7),
                BlendMode.srcATop,
              ),
              child: Image.memory(
                maskOv,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(fallbackIcon,
            size: 20, color: cs.onSurfaceVariant.withValues(alpha: 0.85)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            a.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComposerAttachmentTile(ColorScheme cs, _ComposerAttachment a) {
    IconData fallbackIcon;
    switch (a.kind) {
      case _ComposerAttachmentKind.video:
      case _ComposerAttachmentKind.bulkVideo:
      case _ComposerAttachmentKind.bulkCineRealRefVideo:
        fallbackIcon = LucideIcons.video;
        break;
      case _ComposerAttachmentKind.audio:
        fallbackIcon = LucideIcons.music;
        break;
      case _ComposerAttachmentKind.file:
        fallbackIcon = LucideIcons.fileText;
        break;
      default:
        fallbackIcon = LucideIcons.image;
    }

    final bool isBulkImage = a.kind == _ComposerAttachmentKind.bulkImage;
    final bool isBulkVideo = a.kind == _ComposerAttachmentKind.bulkVideo;
    final bool isBulkCineRealRef =
        a.kind == _ComposerAttachmentKind.bulkCineRealRefVideo;
    final bool isInpaintBulk = isBulkImage && _requiresMask;
    final bool isOutpaintBulk = isBulkImage && _isOutpaint;
    final bool hasBulkMask = isInpaintBulk &&
        a.index < _bulkMasks.length &&
        _bulkMasks[a.index] != null;
    final bool hasBulkOutpaint = isOutpaintBulk &&
        a.index < _bulkOutpaintConfigs.length &&
        _bulkOutpaintConfigs[a.index] != null;
    final et = a.extraThumbs;
    final bool linkedCineKeyframes = !isBulkImage &&
        _isAnimateImageTool &&
        _isCineRealAnimateModel &&
        a.ref == 'init_image' &&
        et != null &&
        et.length == 1 &&
        et.first.isNotEmpty;
    // Task tiles are wider so we can show task number + stacked refs.
    final double tileWidth = (isBulkImage || isBulkVideo || isBulkCineRealRef)
        ? 78
        : (linkedCineKeyframes ? 102 : 62);

    return InkWell(
      onTap: () => _showAttachmentActionsSheet(a),
      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: tileWidth,
            height: 62,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
            ),
            clipBehavior: Clip.antiAlias,
            child: linkedCineKeyframes && a.thumbBytes != null
                ? Row(
                    children: [
                      Expanded(
                        child: Image.memory(
                          a.thumbBytes!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                      Container(
                        width: 12,
                        color: Colors.black.withValues(alpha: 0.42),
                        alignment: Alignment.center,
                        child: const Icon(
                          LucideIcons.moveRight,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                      Expanded(
                        child: Image.memory(
                          a.extraThumbs!.first,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        ),
                      ),
                    ],
                  )
                : _composerAttachmentPreviewFill(cs, a, fallbackIcon),
          ),
          // Video play-overlay hint.
          if (a.kind == _ComposerAttachmentKind.video ||
              a.kind == _ComposerAttachmentKind.bulkVideo ||
              a.kind == _ComposerAttachmentKind.bulkCineRealRefVideo)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                ),
                alignment: Alignment.center,
                child:
                    const Icon(LucideIcons.play, color: Colors.white, size: 16),
              ),
            ),
          // Stacked extra references (for multi-init-per-job bulk tasks).
          if ((a.extraThumbs?.isNotEmpty ?? false) && !linkedCineKeyframes)
            Positioned(
              bottom: 4,
              right: 4,
              child: _BulkExtraRefsStack(
                refs: a.extraThumbs!,
                cs: cs,
              ),
            ),
          // Task number chip (top-left) for bulk tasks.
          if (isBulkImage || isBulkVideo || isBulkCineRealRef)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isBulkCineRealRef ? 'R${a.index + 1}' : '${a.index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          // Remove × (top-right)
          Positioned(
            top: -6,
            right: -6,
            child: InkWell(
              onTap: () => _removeComposerAttachment(a),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.4), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child:
                    Icon(LucideIcons.x, size: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ),
          // Mask / outpaint status badge.
          if (a.kind == _ComposerAttachmentKind.image && _requiresMask)
            _buildComposerTaskBadge(
              cs,
              label: _inputs['mask_image'] != null ? 'Masked' : 'Mask',
              good: _inputs['mask_image'] != null,
            ),
          if (isInpaintBulk)
            _buildComposerTaskBadge(
              cs,
              label: hasBulkMask ? 'Masked' : 'Mask',
              good: hasBulkMask,
            ),
          if (isOutpaintBulk)
            _buildComposerTaskBadge(
              cs,
              label: hasBulkOutpaint ? 'Placed' : 'Place',
              good: hasBulkOutpaint,
            ),
        ],
      ),
    );
  }

  /// Small colored status pill anchored bottom-left of an attachment tile.
  Widget _buildComposerTaskBadge(ColorScheme cs,
      {required String label, required bool good}) {
    return Positioned(
      bottom: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: (good ? cs.primary : cs.error).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _removeComposerAttachment(_ComposerAttachment a) {
    setState(() {
      switch (a.kind) {
        case _ComposerAttachmentKind.image:
          if (a.ref == 'init_image' &&
              _isCineRealAnimateModel &&
              (a.extraThumbs?.isNotEmpty ?? false)) {
            _inputs.remove('init_image');
            _inputs.remove('init_image_path');
            _inputs.remove('last_frame_image');
            _inputs.remove('last_frame_image_path');
            _inputs.remove('mask_image');
            break;
          }
          final cur = _inputs[a.ref];
          if (cur is List && cur.length > 1) {
            cur.removeAt(a.index);
          } else {
            _inputs.remove(a.ref);
            _inputs.remove('${a.ref}_path');
            _inputs.remove('mask_image');
          }
          break;
        case _ComposerAttachmentKind.video:
          final p = _inputs['${a.ref}_path'] as String?;
          if (p != null) {
            final c = _userVideoControllers.remove(p);
            c?.dispose();
          }
          _inputs.remove(a.ref);
          _inputs.remove('${a.ref}_path');
          _inputs.remove('${a.ref}_bytes');
          _inputVideoDuration = null;
          break;
        case _ComposerAttachmentKind.audio:
        case _ComposerAttachmentKind.file:
          _inputs.remove(a.ref);
          _inputs.remove('${a.ref}_path');
          _inputs.remove('${a.ref}_name');
          _inputs.remove('${a.ref}_mime');
          _inputs.remove('${a.ref}_duration');
          break;
        case _ComposerAttachmentKind.bulkImage:
          if (a.index < _bulkImageJobs.length) {
            if (a.index < _bulkCineRealRefVideoBytes.length) {
              _disposeBulkCineRealRefVideoAt(a.index);
              _bulkCineRealRefVideoBytes.removeAt(a.index);
              _bulkCineRealRefVideoPaths.removeAt(a.index);
              _bulkCineRealRefVideoDurations.removeAt(a.index);
            }
            _bulkImageJobs.removeAt(a.index);
            if (a.index < _bulkMasks.length) _bulkMasks.removeAt(a.index);
            if (a.index < _bulkOutpaintConfigs.length) {
              _bulkOutpaintConfigs.removeAt(a.index);
            }
          }
          break;
        case _ComposerAttachmentKind.bulkVideo:
          if (a.index < _bulkVideoPaths.length) {
            _bulkVideoPaths.removeAt(a.index);
            if (a.index < _bulkVideoDurations.length) {
              _bulkVideoDurations.removeAt(a.index);
            }
          }
          break;
        case _ComposerAttachmentKind.bulkCineRealRefVideo:
          if (a.index >= 0 && a.index < _bulkCineRealRefVideoBytes.length) {
            _clearBulkCineRealRefVideoAt(a.index);
          }
          break;
      }
    });
    final removedStudioPhoto = a.kind == _ComposerAttachmentKind.image &&
        (a.ref == 'init_image' || a.ref == 'image');
    if (removedStudioPhoto &&
        _firstImageBytes(_inputs['init_image']) == null &&
        _firstImageBytes(_inputs['image']) == null) {
      final bulk = _advancedSettings.bulkEditEnabled && _supportsBulkEdit;
      if (_tool.capabilityId == 'edit_image') {
        _clearStudioOutpaint();
        if (!bulk) unawaited(_switchImageStudio('create_image'));
      } else if (_tool.capabilityId == 'animate_image' && !bulk) {
        unawaited(_switchImageStudio('create_video'));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Attach bottom sheet (Gemini-style modular popup)
  // Dynamically shows Camera / Photos / Video / Audio / File entries based on
  // which upload-like inputs the tool declares in tool_config.json.
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showAttachSheet(List<Map<String, dynamic>> attachInputs) async {
    final cs = Theme.of(context).colorScheme;
    var imageInputs = attachInputs.where((i) {
      final t = i['type'];
      return t == 'image' || t == 'image_upload';
    }).toList();
    if (_isAnimateImageTool) {
      final mid = _selectedModelId ?? _tool.model;
      imageInputs = imageInputs.where((i) {
        final id = i['id'] as String?;
        if (id == 'last_frame_image') return false;
        if (id == 'ref_image' && mid != 'dreamid') return false;
        return true;
      }).toList();
    }
    final videoInputs = attachInputs.where((i) {
      final t = i['type'];
      return t == 'video' || t == 'video_upload';
    }).toList();
    final audioInputs =
        attachInputs.where((i) => i['type'] == 'audio_upload').toList();
    final fileInputs =
        attachInputs.where((i) => i['type'] == 'file_upload').toList();

    final hasImage = imageInputs.isNotEmpty;
    final hasVideo = videoInputs.isNotEmpty;
    final hasAudio = audioInputs.isNotEmpty;
    final hasFile = fileInputs.isNotEmpty;

    if (!hasImage && !hasVideo && !hasAudio && !hasFile) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.2)),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                      left: 4, right: 4, top: 2, bottom: 6),
                  child: Row(
                    children: [
                      Text(
                        'Add to prompt',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (_supportsBulkEdit)
                        _AttachBulkTogglePill(
                          on: _advancedSettings.bulkEditEnabled,
                          onTap: () {
                            Navigator.pop(ctx);
                            _toggleBulkModeFromComposer();
                          },
                        ),
                    ],
                  ),
                ),
                // Large primary row (Camera/Photos/Files) like Claude/Gemini.
                if (hasImage || hasVideo || hasFile || hasAudio)
                  Row(
                    children: [
                      if (hasImage)
                        Expanded(
                          child: _AttachBigTile(
                            icon: LucideIcons.camera,
                            label: 'Camera',
                            subtitle: 'Take a new photo',
                            accentColor: cs.secondary,
                            compact: hasAudio,
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickImageFromCamera(
                                  _attachableImageInputResolved(
                                      _rawPrimaryImageAttachRow(imageInputs)));
                            },
                          ),
                        ),
                      if (hasImage) SizedBox(width: hasAudio ? 8 : 12),
                      if (hasImage)
                        Expanded(
                          child: _AttachBigTile(
                            icon: LucideIcons.image,
                            label: _advancedSettings.bulkEditEnabled &&
                                    _supportsBulkImageEdit
                                ? 'Photos (bulk)'
                                : 'Photos',
                            subtitle: _advancedSettings.bulkEditEnabled &&
                                    _supportsBulkImageEdit
                                ? 'Select multiple images'
                                : 'Choose from gallery',
                            accentColor: cs.primary,
                            compact: hasAudio,
                            onTap: () {
                              Navigator.pop(ctx);
                              if (_advancedSettings.bulkEditEnabled &&
                                  _supportsBulkImageEdit) {
                                _pickBulkImages();
                              } else {
                                final eff = _attachableImageInputResolved(
                                    _rawPrimaryImageAttachRow(imageInputs));
                                final id = eff['id'] as String?;
                                final maxC = (eff['max'] ?? 1) as int;
                                if (id != null &&
                                    maxC > 1 &&
                                    _initImageCountForRef(id) > 0 &&
                                    _initImageCountForRef(id) < maxC) {
                                  _pickMorePrimaryInitImages(eff);
                                } else {
                                  _pickImageFromGallery(eff);
                                }
                              }
                            },
                          ),
                        ),
                      if (hasAudio) ...[
                        if (hasImage) const SizedBox(width: 8),
                        Expanded(
                          child: _AttachBigTile(
                            icon: LucideIcons.music,
                            label: 'Audio',
                            subtitle: (audioInputs.first['label'] as String?) ??
                                'Pick audio file',
                            accentColor: cs.secondary,
                            compact: hasImage,
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickAudioForInput(
                                audioInputs.first['id'] as String,
                                audioInputs.first,
                              );
                            },
                          ),
                        ),
                      ],
                      if (hasFile && (hasImage || hasAudio))
                        const SizedBox(width: 12),
                      if (hasFile)
                        Expanded(
                          child: _AttachBigTile(
                            icon: LucideIcons.paperclip,
                            label: 'Files',
                            subtitle: 'Documents & attachments',
                            accentColor: cs.tertiary,
                            onTap: () {
                              Navigator.pop(ctx);
                              _pickGenericFile(fileInputs.first['id'] as String,
                                  fileInputs.first);
                            },
                          ),
                        ),
                      // Tools with video (or bulk video) but no image inputs — e.g. Upscale Video.
                      if (hasVideo && !hasImage) ...[
                        if (hasFile) const SizedBox(width: 12),
                        Expanded(
                          child: _AttachBigTile(
                            icon: LucideIcons.video,
                            label: _advancedSettings.bulkEditEnabled &&
                                    _supportsBulkVideoEdit
                                ? 'Videos (bulk)'
                                : 'Choose video',
                            subtitle: _advancedSettings.bulkEditEnabled &&
                                    _supportsBulkVideoEdit
                                ? 'Select multiple videos'
                                : 'From gallery or camera',
                            accentColor: cs.primary,
                            onTap: () {
                              Navigator.pop(ctx);
                              if (_advancedSettings.bulkEditEnabled &&
                                  _supportsBulkVideoEdit) {
                                _pickVideosForBulk(videoInputs.first);
                              } else {
                                _pickVideo(videoInputs.first);
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                if (hasImage && hasVideo)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(
                        color: cs.outlineVariant.withValues(alpha: 0.25), height: 1),
                  ),
                // Secondary list: video when tool also has image inputs (big row is image-only).
                if (hasVideo &&
                    hasImage &&
                    (!_isAnimateImageTool ||
                        (_selectedModelId ?? _tool.model) ==
                            'dreamid' ||
                        (_isCineRealAnimateModel &&
                            !_advancedSettings.bulkEditEnabled &&
                            !_cineRealSingleHasEndFrameBytes() &&
                            !_cineRealSingleHasRefVideoBytes())))
                  _AttachListRow(
                    icon: LucideIcons.video,
                    label: _advancedSettings.bulkEditEnabled &&
                            _supportsBulkVideoEdit
                        ? 'Videos (bulk)'
                        : 'Video',
                    subtitle: (videoInputs.first['label'] as String?) ??
                        'Pick a video',
                    onTap: () {
                      Navigator.pop(ctx);
                      if (_advancedSettings.bulkEditEnabled &&
                          _supportsBulkVideoEdit) {
                        _pickVideosForBulk(videoInputs.first);
                      } else {
                        _pickVideo(videoInputs.first);
                      }
                    },
                  ),
                if (_isAnimateImageTool &&
                    !_advancedSettings.bulkEditEnabled) ...[
                  Builder(
                    builder: (_) {
                      final mid = _selectedModelId ?? _tool.model;
                      final showEndRow = mid == _kCineRealAnimateModelId ||
                          mid == _kLegacyCineRealAnimateModelId ||
                          mid == _kCinemotionProModelId ||
                          mid == _kLegacyWanI2vModelId;
                      if (!showEndRow) return const SizedBox.shrink();
                      Map<String, dynamic>? lastSpec;
                      for (final i in attachInputs) {
                        if (i['id'] == 'last_frame_image') {
                          lastSpec = Map<String, dynamic>.from(i);
                          break;
                        }
                      }
                      if (lastSpec == null || lastSpec.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final hasLast =
                          _bytesForInputKey('last_frame_image') != null;
                      if (hasLast) return const SizedBox.shrink();
                      final cinerealBlockedByRef =
                          _isCineRealAnimateModel &&
                              _cineRealSingleHasRefVideoBytes();
                      final subtitle = _requiresEndFrame
                          ? 'Required. Pick the start frame, then this end frame.'
                          : (cinerealBlockedByRef
                              ? 'Remove the motion clip before adding an end frame'
                              : (_isCineRealAnimateModel
                                  ? 'Optional second photo (CineReal)'
                                  : 'Optional end frame (Cinemotion Pro)'));
                      return Opacity(
                        opacity: cinerealBlockedByRef ? 0.45 : 1,
                        child: _AttachListRow(
                          icon: LucideIcons.imagePlus,
                          label: 'End frame',
                          subtitle: subtitle,
                          onTap: () {
                            if (cinerealBlockedByRef) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Remove the reference video before adding an end frame.',
                                  ),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(ctx);
                            _pickImage(
                                _attachableImageInputResolved(lastSpec!));
                          },
                        ),
                      );
                    },
                  ),
                ],
                // If there are multiple image inputs (e.g. ref_image), expose them explicitly.
                if (imageInputs.length > 1) ...[
                  for (int i = 1; i < imageInputs.length; i++)
                    _AttachListRow(
                      icon: LucideIcons.image,
                      label: (imageInputs[i]['label'] as String?) ??
                          'Another image',
                      subtitle: 'Optional reference',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickImage(_attachableImageInputResolved(
                            Map<String, dynamic>.from(imageInputs[i])));
                      },
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Clears bulk queues and syncs CineReal single inputs when leaving bulk mode.
  void _leaveBulkModeCleanup() {
    if (_supportsBulkVideoEdit) {
      _disposeBulkVideoListInPlace();
    } else if (_isAnimateImageTool &&
        _isCineRealAnimateModel &&
        _bulkImageJobs.isNotEmpty) {
      final first = _bulkImageJobs.first;
      if (first.length == 2 && first[0].isNotEmpty && first[1].isNotEmpty) {
        _syncCineRealSingleFromFirstBulkRow();
      }
      for (var i = 0; i < _bulkCineRealRefVideoPaths.length; i++) {
        _disposeBulkCineRealRefVideoAt(i);
      }
      _bulkCineRealRefVideoBytes.clear();
      _bulkCineRealRefVideoPaths.clear();
      _bulkCineRealRefVideoDurations.clear();
      _bulkImageJobs.clear();
      _bulkMasks.clear();
      _bulkOutpaintConfigs.clear();
    } else {
      for (var i = 0; i < _bulkCineRealRefVideoPaths.length; i++) {
        _disposeBulkCineRealRefVideoAt(i);
      }
      _bulkCineRealRefVideoBytes.clear();
      _bulkCineRealRefVideoPaths.clear();
      _bulkCineRealRefVideoDurations.clear();
      _bulkImageJobs.clear();
      _bulkMasks.clear();
      _bulkOutpaintConfigs.clear();
    }
  }

  void _enterBulkModeSetup() {
    if (_isAnimateImageTool && _isCineRealAnimateModel) {
      _seedCineRealFlf2vBulkFromInputs();
      // Only strip single-slot bytes after both frames were copied into [_bulkImageJobs].
      final seededTwoFrame = _bulkImageJobs.isNotEmpty &&
          _bulkImageJobs.first.length == 2 &&
          _bulkImageJobs.first[0].isNotEmpty &&
          _bulkImageJobs.first[1].isNotEmpty;
      if (seededTwoFrame) {
        _clearSingleModeComposerMediaFromInputs();
      }
    } else {
      _clearSingleModeComposerMediaFromInputs();
    }
  }

  /// Drops single-mode image/video bytes from [_inputs] when entering bulk so
  /// the composer and submit path stay bulk-only (CineReal: see [_enterBulkModeSetup]).
  void _clearSingleModeComposerMediaFromInputs() {
    for (final raw in _tool.inputs) {
      final m = Map<String, dynamic>.from(raw as Map);
      final id = m['id'] as String?;
      final t = m['type'] as String?;
      if (id == null || t == null) continue;
      if (t == 'image' || t == 'image_upload') {
        _inputs.remove(id);
        _inputs.remove('${id}_path');
      }
      if (_supportsBulkVideoEdit && (t == 'video' || t == 'video_upload')) {
        final p = _inputs['${id}_path'] as String?;
        if (p != null) {
          _userVideoControllers.remove(p)?.dispose();
        }
        _inputs.remove(id);
        _inputs.remove('${id}_path');
        _inputs.remove('${id}_bytes');
        _inputs.remove('${id}_name');
        _inputs.remove('${id}_mime');
        _inputs.remove('${id}_duration');
      }
    }
    if (_requiresMask) {
      _inputs.remove('mask_image');
    }
    _inputs.remove('video_duration');
    if (_supportsBulkVideoEdit) {
      _inputVideoDuration = null;
    }
  }

  /// Full hint for the compact bulk/single badge (shown on long-press / hover).
  String _composerBulkModeTooltip() {
    if (!_supportsBulkEdit) return '';
    if (!_advancedSettings.bulkEditEnabled) {
      return 'Single: one generation from the composer.';
    }
    if (_supportsBulkVideoEdit) {
      return 'Bulk: up to $_maxBulkImages videos — one job per clip.';
    }
    if (_isAnimateImageTool && _isCineRealAnimateModel) {
      return 'Bulk: up to $_maxBulkImages clips. Tap a clip → Add end frame or Add reference video (one per clip, not both).';
    }
    return 'Bulk: up to $_maxBulkImages tasks with the same settings.';
  }

  /// Tiny pill beside the single/bulk switch (icon + capacity). Keeps the row calm.
  Widget _buildComposerBulkModeBadge(ColorScheme cs) {
    if (!_supportsBulkEdit) return const SizedBox.shrink();
    final bulk = _advancedSettings.bulkEditEnabled;
    return Tooltip(
      message: _composerBulkModeTooltip(),
      waitDuration: const Duration(milliseconds: 350),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              bulk ? LucideIcons.layers : LucideIcons.image,
              size: 13,
              color: cs.onSurfaceVariant.withValues(alpha: 0.88),
            ),
            const SizedBox(width: 4),
            Text(
              bulk ? '$_maxBulkImages' : '1',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: cs.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleBulkModeFromComposer() {
    final on = _advancedSettings.bulkEditEnabled;
    setState(() {
      if (on) {
        _leaveBulkModeCleanup();
        _advancedSettings = _advancedSettings.copyWith(bulkEditEnabled: false);
      } else {
        _advancedSettings = _advancedSettings.copyWith(bulkEditEnabled: true);
        _enterBulkModeSetup();
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Attachment actions sheet — shown on chip tap in the composer. Offers
  // flow-specific actions (view, edit mask, edit outpaint, change, remove).
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _showAttachmentActionsSheet(_ComposerAttachment a) async {
    final cs = Theme.of(context).colorScheme;
    final isImage = a.kind == _ComposerAttachmentKind.image ||
        a.kind == _ComposerAttachmentKind.bulkImage;
    final isVideo = a.kind == _ComposerAttachmentKind.video ||
        a.kind == _ComposerAttachmentKind.bulkVideo ||
        a.kind == _ComposerAttachmentKind.bulkCineRealRefVideo;
    final int viewGroupCount = _imageCountInSameGroup(a);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (isImage && _requiresMask)
                _AttachListRow(
                  icon: LucideIcons.brush,
                  label: a.kind == _ComposerAttachmentKind.bulkImage
                      ? ((_bulkMasks.length > a.index &&
                              _bulkMasks[a.index] != null)
                          ? 'Re-edit mask'
                          : 'Edit mask')
                      : (_inputs['mask_image'] != null
                          ? 'Re-edit mask'
                          : 'Edit mask'),
                  subtitle: 'Paint the area to modify',
                  onTap: () async {
                    Navigator.pop(ctx);
                    final base = a.thumbBytes;
                    if (base == null) return;
                    if (a.kind == _ComposerAttachmentKind.bulkImage) {
                      final idx = a.index;
                      final existing =
                          idx < _bulkMasks.length ? _bulkMasks[idx] : null;
                      final mask = await _openMaskEditor(
                        base,
                        existingMask: existing,
                        isBulkMode: true,
                      );
                      if (mask != null && mounted) {
                        setState(() {
                          while (_bulkMasks.length <= idx) {
                            _bulkMasks.add(null);
                          }
                          _bulkMasks[idx] = mask;
                        });
                        await _showMaskLayout(base, mask);
                      }
                    } else {
                      final mask = await _openMaskEditor(base);
                      if (mask != null && mounted) {
                        setState(() => _inputs['mask_image'] = mask);
                        await _showMaskLayout(base, mask);
                      }
                    }
                  },
                ),
              if (isImage && _requiresMask && a.thumbBytes != null)
                Builder(
                  builder: (context) {
                    final Uint8List? painted = a.kind ==
                            _ComposerAttachmentKind.bulkImage
                        ? (a.index < _bulkMasks.length ? _bulkMasks[a.index] : null)
                        : (_inputs['mask_image'] is Uint8List
                            ? _inputs['mask_image'] as Uint8List
                            : null);
                    if (painted == null || painted.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final photo = a.thumbBytes!;
                    return _AttachListRow(
                      icon: LucideIcons.eye,
                      label: 'View mask on photo',
                      subtitle: 'Check the painted area lines up',
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _showMaskLayout(photo, painted);
                      },
                    );
                  },
                ),
              if (isImage &&
                  (_isOutpaint || _tool.capabilityId == 'expand_scene'))
                _AttachListRow(
                  icon: LucideIcons.expand,
                  label: 'Adjust placement',
                  subtitle: 'Open outpaint canvas',
                  onTap: () async {
                    Navigator.pop(ctx);
                    final base = a.thumbBytes;
                    if (base == null) return;
                    final result = await Navigator.push<Map<String, String>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OutpaintCanvasPage(imageBytes: base),
                        fullscreenDialog: true,
                      ),
                    );
                    if (result != null && mounted) {
                      if (a.kind == _ComposerAttachmentKind.bulkImage) {
                        final idx = a.index;
                        setState(() {
                          while (_bulkOutpaintConfigs.length <= idx) {
                            _bulkOutpaintConfigs.add(null);
                          }
                          _bulkOutpaintConfigs[idx] = result;
                        });
                      } else {
                        setState(() {
                          _inputs["alignment"] = result["alignment"];
                          _inputs["aspect_ratio"] = result["aspect_ratio"];
                          _inputs["is_custom"] = result["is_custom"];
                          _inputs["custom_scale"] = result["custom_scale"];
                          _inputs["norm_offset_x"] = result["norm_offset_x"];
                          _inputs["norm_offset_y"] = result["norm_offset_y"];
                          _inputs["offset_x"] = result["offset_x"];
                          _inputs["offset_y"] = result["offset_y"];
                          _inputs["canvas_width"] = result["canvas_width"];
                          _inputs["canvas_height"] = result["canvas_height"];
                          _inputs["fitted_width"] = result["fitted_width"];
                          _inputs["fitted_height"] = result["fitted_height"];
                          _inputs["image_width"] = result["image_width"];
                          _inputs["image_height"] = result["image_height"];
                          _inputs["image_left"] = result["image_left"];
                          _inputs["image_top"] = result["image_top"];
                          _inputs["outpaint_preview"] = base;
                        });
                      }
                    }
                  },
                ),
              if (a.kind == _ComposerAttachmentKind.bulkImage &&
                  _isAnimateImageTool &&
                  _isCineRealAnimateModel &&
                  a.index < _bulkImageJobs.length &&
                  _bulkImageJobs[a.index].length == 1 &&
                  _bulkImageJobs[a.index].first.isNotEmpty) ...[
                Builder(
                  builder: (_) {
                    final ti = a.index;
                    final blockedByRef = _bulkCineRealTaskHasRefVideo(ti);
                    return Opacity(
                      opacity: blockedByRef ? 0.45 : 1,
                      child: _AttachListRow(
                        icon: LucideIcons.imagePlus,
                        label: 'Add end frame',
                        subtitle: blockedByRef
                            ? 'Remove reference video first'
                            : 'Second keyframe for this clip',
                        onTap: () {
                          if (blockedByRef) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Remove the reference video from this clip before adding an end frame.',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          _pickMoreForBulkTask(ti);
                        },
                      ),
                    );
                  },
                ),
                Builder(
                  builder: (_) {
                    final ti = a.index;
                    final blockedByEnd = _bulkCineRealTaskHasEndFrame(ti);
                    return Opacity(
                      opacity: blockedByEnd ? 0.45 : 1,
                      child: _AttachListRow(
                        icon: LucideIcons.video,
                        label: 'Add reference video',
                        subtitle: blockedByEnd
                            ? 'Remove end frame first'
                            : 'Motion reference for this clip (CineReal)',
                        onTap: () {
                          if (blockedByEnd) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Remove the end frame from this clip before adding a reference video.',
                                ),
                              ),
                            );
                            return;
                          }
                          Navigator.pop(ctx);
                          _pickRefVideoForBulkTask(ti);
                        },
                      ),
                    );
                  },
                ),
              ],
              _AttachListRow(
                icon: isVideo ? LucideIcons.play : LucideIcons.maximize2,
                label: isVideo
                    ? 'Preview'
                    : (viewGroupCount > 1 ? 'View all images' : 'View full'),
                subtitle: isVideo
                    ? 'Open video preview'
                    : (viewGroupCount > 1
                        ? '$viewGroupCount images · swipe to browse'
                        : 'Open the attachment in full view'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openAttachmentFullView(a);
                },
              ),
              if (isImage &&
                  a.kind == _ComposerAttachmentKind.image &&
                  !_advancedSettings.bulkEditEnabled) ...[
                Builder(
                  builder: (_) {
                    final inputDef = _tool.inputs.firstWhere(
                        (i) => i['id'] == a.ref,
                        orElse: () => <String, dynamic>{});
                    if (inputDef.isEmpty) return const SizedBox.shrink();
                    final eff = _attachableImageInputResolved(
                        Map<String, dynamic>.from(inputDef));
                    final maxC = (eff['max'] ?? 1) as int;
                    final id = eff['id'] as String?;
                    if (maxC <= 1 ||
                        id == null ||
                        _initImageCountForRef(id) >= maxC) {
                      return const SizedBox.shrink();
                    }
                    final n = _initImageCountForRef(id);
                    return _AttachListRow(
                      icon: LucideIcons.imagePlus,
                      label: 'Add more images',
                      subtitle: 'Up to $maxC total ($n/$maxC)',
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickMorePrimaryInitImages(eff);
                      },
                    );
                  },
                ),
              ],
              _AttachListRow(
                icon: LucideIcons.replace,
                label: 'Change',
                subtitle: 'Pick a different file',
                onTap: () {
                  Navigator.pop(ctx);
                  _replaceAttachment(a);
                },
              ),
              _AttachListRow(
                icon: LucideIcons.trash2,
                label: 'Remove',
                subtitle: 'Detach from this prompt',
                destructive: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _removeComposerAttachment(a);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// How many images belong to the same task / input as [a] (for preview UX).
  int _imageCountInSameGroup(_ComposerAttachment a) {
    switch (a.kind) {
      case _ComposerAttachmentKind.bulkImage:
        if (a.index >= 0 && a.index < _bulkImageJobs.length) {
          return _bulkImageJobs[a.index].where((b) => b.isNotEmpty).length;
        }
        return 1;
      case _ComposerAttachmentKind.image:
        if (_isAnimateImageTool &&
            _isCineRealAnimateModel &&
            a.ref == 'init_image' &&
            (a.extraThumbs?.isNotEmpty ?? false)) {
          return 2;
        }
        return _initImageCountForRef(a.ref);
      default:
        return 1;
    }
  }

  /// All image bytes for full-screen preview (single multi-ref or one bulk task).
  List<Uint8List> _allImageBytesForFullView(_ComposerAttachment a) {
    switch (a.kind) {
      case _ComposerAttachmentKind.bulkImage:
        if (a.index >= 0 && a.index < _bulkImageJobs.length) {
          return _bulkImageJobs[a.index]
              .where((b) => b.isNotEmpty)
              .toList(growable: false);
        }
        final out = <Uint8List>[];
        if (a.thumbBytes != null && a.thumbBytes!.isNotEmpty) {
          out.add(a.thumbBytes!);
        }
        if (a.extraThumbs != null) {
          for (final t in a.extraThumbs!) {
            if (t.isNotEmpty) out.add(t);
          }
        }
        return out;
      case _ComposerAttachmentKind.image:
        if (a.extraThumbs != null && a.extraThumbs!.isNotEmpty) {
          final out = <Uint8List>[];
          if (a.thumbBytes != null && a.thumbBytes!.isNotEmpty) {
            out.add(a.thumbBytes!);
          }
          for (final t in a.extraThumbs!) {
            if (t.isNotEmpty) out.add(t);
          }
          if (out.isNotEmpty) return out;
        }
        final v = _inputs[a.ref];
        if (v is List) {
          return v
              .whereType<Uint8List>()
              .where((b) => b.isNotEmpty)
              .toList(growable: false);
        }
        if (v is Uint8List && v.isNotEmpty) return [v];
        if (a.thumbBytes != null && a.thumbBytes!.isNotEmpty) {
          return [a.thumbBytes!];
        }
        return [];
      default:
        if (a.thumbBytes != null && a.thumbBytes!.isNotEmpty) {
          return [a.thumbBytes!];
        }
        return [];
    }
  }

  void _openAttachmentFullView(_ComposerAttachment a) {
    final cs = Theme.of(context).colorScheme;
    final isVideo = a.kind == _ComposerAttachmentKind.video ||
        a.kind == _ComposerAttachmentKind.bulkVideo ||
        a.kind == _ComposerAttachmentKind.bulkCineRealRefVideo;

    if (isVideo) {
      final p = a.filePath;
      if (!kIsWeb && p != null && p.isNotEmpty) {
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierColor: Colors.black87,
          builder: (_) => _VideoAttachmentFullScreenDialog(videoPath: p),
        );
        return;
      }
      showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            color: Colors.transparent,
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppStyles.radiusLg),
                child: a.thumbBytes != null
                    ? Image.memory(a.thumbBytes!, fit: BoxFit.contain)
                    : Container(
                        color: cs.surfaceContainerHigh,
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.file,
                                size: 40, color: cs.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(a.label,
                                style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                )),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
      return;
    }

    final gallery = _allImageBytesForFullView(a);
    if (gallery.isEmpty) {
      showDialog<void>(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            color: Colors.transparent,
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppStyles.radiusLg),
                child: Container(
                  color: cs.surfaceContainerHigh,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.file,
                          size: 40, color: cs.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(a.label,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return;
    }

    final initial = a.index.clamp(0, gallery.length - 1);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _ComposerImageGalleryDialog(
        images: gallery,
        initialIndex: initial,
        title: a.label,
      ),
    );
  }

  void _replaceAttachment(_ComposerAttachment a) {
    final inputDef = _tool.inputs
        .firstWhere((i) => i['id'] == a.ref, orElse: () => {});
    if (inputDef.isEmpty) return;
    switch (a.kind) {
      case _ComposerAttachmentKind.image:
      case _ComposerAttachmentKind.bulkImage:
        _pickImage(
            _attachableImageInputResolved(Map<String, dynamic>.from(inputDef)));
        break;
      case _ComposerAttachmentKind.video:
      case _ComposerAttachmentKind.bulkVideo:
        _pickVideo(Map<String, dynamic>.from(inputDef));
        break;
      case _ComposerAttachmentKind.bulkCineRealRefVideo:
        _pickRefVideoForBulkTask(a.index);
        break;
      case _ComposerAttachmentKind.audio:
        _pickAudioForInput(a.ref, Map<String, dynamic>.from(inputDef));
        break;
      case _ComposerAttachmentKind.file:
        _pickGenericFile(a.ref, Map<String, dynamic>.from(inputDef));
        break;
    }
  }

  /// Row of removable chips (currently just the selected Style) for the composer.
  Widget _buildComposerChipRow(ColorScheme cs) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (_selectedStyle != null)
          _buildRemovableComposerChip(
            cs,
            icon: _selectedStyle!.icon,
            label: _selectedStyle!.name,
            onRemove: () {
              _removeStyleFromPrompt(_selectedStyle!);
              setState(() => _selectedStyle = null);
            },
          ),
      ],
    );
  }

  Widget _buildRemovableComposerChip(
    ColorScheme cs, {
    required String icon,
    required String label,
    required VoidCallback onRemove,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppStyles.radiusFull),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: cs.primary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(10),
            child: Icon(LucideIcons.x, size: 13, color: cs.primary),
          ),
        ],
      ),
    );
  }

  // ---------- Section Shortcut Bar ----------
  /// Horizontal pill of circular icon buttons that smooth-scroll to each section
  /// below the composer. Icons are derived from [contentElements] types plus mode.
  Widget _buildSectionShortcutBar(List<Map<String, dynamic>> contentElements) {
    final cs = Theme.of(context).colorScheme;
    final shortcuts = <_ShortcutEntry>[];

    // Mode section
    if (_tool.modes != null && _tool.modes!.isNotEmpty) {
      shortcuts.add(_ShortcutEntry(
        id: 'mode',
        icon: LucideIcons.layers,
        tooltip: 'Mode',
        key: _modeSectionKey,
      ));
    }

    bool hasType(String t) => contentElements.any((e) => e['type'] == t);

    // NOTE: image / video / audio / file uploads are no longer scroll targets;
    // they now live in the composer as inline attachments and open a popup
    // picker via the composer's + button. Keeping them out of the shortcut
    // bar avoids dead icons pointing at nothing.
    if (hasType('text_input')) {
      shortcuts.add(_ShortcutEntry(
        id: 'text',
        icon: LucideIcons.type,
        tooltip: 'Text',
        key: _textInputKey,
      ));
    }
    if (hasType('aspect_ratio') && !(_isVideoTool && !_isVideoUpscalerTool)) {
      shortcuts.add(_ShortcutEntry(
        id: 'ratio',
        icon: LucideIcons.maximize,
        tooltip: 'Aspect Ratio',
        key: _aspectRatioKey,
      ));
    }
    if (hasType('color_picker')) {
      shortcuts.add(_ShortcutEntry(
        id: 'color',
        icon: LucideIcons.paintbrush,
        tooltip: 'Color',
        key: _colorPickerKey,
      ));
    }
    if (hasType('multi_select')) {
      shortcuts.add(_ShortcutEntry(
        id: 'multi',
        icon: LucideIcons.checkSquare,
        tooltip: 'Select',
        key: _multiSelectKey,
      ));
    }
    if (hasType('range_slider')) {
      shortcuts.add(_ShortcutEntry(
        id: 'range',
        icon: LucideIcons.gitCommit,
        tooltip: 'Range',
        key: _rangeSliderKey,
      ));
    }
    if (hasType('slider')) {
      shortcuts.add(_ShortcutEntry(
        id: 'sliders',
        icon: LucideIcons.sliders,
        tooltip: 'Sliders',
        key: _slidersKey,
      ));
    }
    if (hasType('number_input') || hasType('seed_input')) {
      shortcuts.add(_ShortcutEntry(
        id: 'numeric',
        icon: LucideIcons.hash,
        tooltip: 'Numbers',
        key: _numericKey,
      ));
    }
    if (hasType('dropdown')) {
      shortcuts.add(_ShortcutEntry(
        id: 'dropdowns',
        icon: LucideIcons.list,
        tooltip: 'Choices',
        key: _dropdownsKey,
      ));
    }
    if (hasType('toggle')) {
      shortcuts.add(_ShortcutEntry(
        id: 'toggles',
        icon: LucideIcons.toggleRight,
        tooltip: 'Toggles',
        key: _togglesKey,
      ));
    }

    // Not worth showing a bar for 1 shortcut.
    if (shortcuts.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(AppStyles.radiusFull),
            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < shortcuts.length; i++) ...[
                _buildShortcutButton(cs, shortcuts[i]),
                if (i < shortcuts.length - 1)
                  Container(
                    width: 1,
                    height: 18,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: cs.outlineVariant.withValues(alpha: 0.2),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutButton(ColorScheme cs, _ShortcutEntry entry) {
    final isActive = _pulseSectionId == entry.id;
    return Tooltip(
      message: entry.tooltip,
      child: InkWell(
        onTap: () => _scrollToSection(entry.key, entry.id),
        borderRadius: BorderRadius.circular(AppStyles.radiusFull),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isActive
                ? const LinearGradient(colors: KalaColors.brandGradient)
                : null,
            color: isActive ? null : Colors.transparent,
          ),
          child: Icon(
            entry.icon,
            size: 16,
            color:
                isActive ? Colors.white : cs.onSurfaceVariant.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  Future<void> _scrollToSection(GlobalKey key, String id) async {
    final ctx = key.currentContext;
    if (ctx == null) return;
    HapticFeedback.selectionClick();
    setState(() => _pulseSectionId = id);
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    if (_pulseSectionId == id) {
      setState(() => _pulseSectionId = null);
    }
  }

  // ======================================================================
  // Phase 2 — Preemptive input-type scaffolds
  // Each builder mirrors the conventions of the existing ones: reads from
  // `_tool.inputs`, writes to `_inputs[ref]` (and secondary keys
  // like `${ref}_path` where applicable), honors `showWhen` / `showForModels`
  // and config-provided `required` / `default` values.
  // ======================================================================

  /// Returns the input spec for [ref] from tool_config, or an empty map.
  Map<String, dynamic> _inputSpec(String ref) => Map<String, dynamic>.from(
      _tool.inputs.firstWhere((i) => i['id'] == ref, orElse: () => {}));

  /// Shared gate that every dynamic element honors: hides the widget if the
  /// input config declares `showWhen` or `showForModels` and the condition
  /// isn't met.
  bool _elementShouldRender(Map<String, dynamic> input) {
    if (_isMusicTool && _inputs['vocals'] == false) {
      final id = input['id'];
      if (id == 'lyrics' ||
          id == 'vocal_language' ||
          id == 'lyrics_optimizer') {
        return false;
      }
    }
    if (_isMusicTool) {
      const advancedOnly = {
        'lyrics',
        'negative_prompt',
      };
      final id = input['id'];
      if (id == 'lyrics' && _inputs['vocals'] == false) return false;
      if (advancedOnly.contains(id) && _inputs['music_mode'] != 'advanced') {
        return false;
      }
      if ((id == 'source_audio' || id == 'strength') && !_musicUsesAudio) {
        return false;
      }
      if ((id == 'repaint_start' || id == 'repaint_end') && !_musicRepaint) {
        return false;
      }
      if (id == 'duration' && _musicUsesAudio) return false;
    }
    if (_isSunoV6) {
      final sounds = _sunoSounds;
      final id = input['id'];
      if ((_sunoExtend || _sunoMashup) &&
          id != 'extend_audio' &&
          id != 'mashup_a' &&
          id != 'mashup_b' &&
          (id == 'vocals' ||
              id == 'lyrics' ||
              id == 'negative_prompt' ||
              id == 'prompt')) {
        return false;
      }
      const soundOnly = {'sound_loop', 'sound_tempo', 'sound_key'};
      const songOnly = {
        'suno_length',
        'vocal_gender',
        'variety',
        'cover',
        'cover_image',
        'clip',
        'reference_audio',
        'title',
      };
      if (sounds && (songOnly.contains(id) || id == 'vocals')) return false;
      if (!sounds && soundOnly.contains(id)) return false;
      if (!sounds &&
          (id == 'cover' ||
              id == 'cover_image' ||
              id == 'clip' ||
              id == 'reference_audio' ||
              id == 'title')) {
        return false;
      }
      if (!sounds && _musicEasy &&
          (id == 'suno_length' || id == 'vocal_gender' || id == 'variety')) {
        return false;
      }
      if (!sounds && id == 'vocal_gender' && _inputs['vocals'] == false) {
        return false;
      }
    }
    final showForModels = input['showForModels'] as List<dynamic>?;
    if (showForModels != null && showForModels.isNotEmpty) {
      final currentModel = _selectedModelId ?? _tool.model;
      if (!showForModels.contains(currentModel)) return false;
    }
    final showWhen = input['showWhen'] as Map<String, dynamic>?;
    if (showWhen != null && showWhen.isNotEmpty) {
      final key = showWhen.keys.first;
      final expected = showWhen[key];
      if (_inputs[key] != expected) return false;
    }
    return true;
  }

  // ── 1. audio_upload ─────────────────────────────────────────────────────
  Widget _buildAudioUpload(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? 'Upload Audio';
    final bytes = _inputs[ref];
    final hasAudio = bytes is Uint8List && bytes.isNotEmpty;
    final fileName = _inputs['${ref}_name'] as String?;
    final sizeKb = hasAudio ? (bytes.lengthInBytes / 1024).round() : 0;

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.mic,
                  size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (input['required'] == true)
                Text(
                  'Required',
                  style: TextStyle(
                    color: cs.error.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasAudio) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.music, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName ?? 'Audio file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$sizeKb KB',
                          style: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: Icon(LucideIcons.trash2,
                        size: 16, color: cs.error.withValues(alpha: 0.8)),
                    onPressed: () {
                      setState(() {
                        _inputs.remove(ref);
                        _inputs.remove('${ref}_path');
                        _inputs.remove('${ref}_name');
                        _inputs.remove('${ref}_mime');
                        _inputs.remove('${ref}_duration');
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GradientButton(
              icon: LucideIcons.imagePlus,
              label: 'Change Audio',
              onPressed: () => _pickAudioForInput(ref, input),
              variant: ButtonVariant.secondary,
              size: ButtonSize.medium,
              expanded: true,
            ),
          ] else
            GradientButton(
              icon: LucideIcons.mic,
              label: label,
              onPressed: () => _pickAudioForInput(ref, input),
              variant: ButtonVariant.primary,
              size: ButtonSize.medium,
              expanded: true,
            ),
        ],
      ),
    );
  }

  Future<void> _pickAudioForInput(
      String ref, Map<String, dynamic> input) async {
    try {
      final accept = (input['accept'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'];
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: accept,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final data = f.bytes;
      if (data == null) return;
      setState(() {
        _inputs[ref] = data;
        _inputs['${ref}_path'] = f.path;
        _inputs['${ref}_name'] = f.name;
        _inputs['${ref}_mime'] = _guessAudioMime(f.extension ?? '');
        _inputs.remove('${ref}_duration');
      });
      if (ref == 'extend_audio' && f.path != null && f.path!.isNotEmpty) {
        unawaited(_rememberExtendDuration(f.path!));
      }
    } catch (e) {
      debugPrint('Audio pick failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick audio: $e')),
        );
      }
    }
  }

  Future<void> _rememberExtendDuration(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final raw = session.getMediaInformation()?.getDuration();
      final seconds = raw == null ? null : double.tryParse(raw);
      if (!mounted || seconds == null || seconds <= 0) return;
      if (seconds > 8 * 60) {
        setState(() {
          _inputs.remove('extend_audio');
          _inputs.remove('extend_audio_path');
          _inputs.remove('extend_audio_name');
          _inputs.remove('extend_audio_mime');
          _inputs.remove('extend_audio_duration');
          _inputs.remove('continue_at');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Audio to extend must be 8 minutes or less.'),
          ),
        );
        return;
      }
      setState(() {
        _inputs['extend_audio_duration'] = seconds;
        final start = seconds - 1;
        _inputs['continue_at'] = start < 1 ? 1.0 : start;
      });
    } catch (e) {
      debugPrint('Extend duration probe failed: $e');
    }
  }

  String _guessAudioMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'ogg':
        return 'audio/ogg';
      case 'flac':
        return 'audio/flac';
      default:
        return 'application/octet-stream';
    }
  }

  // ── 2. file_upload (generic) ────────────────────────────────────────────
  Widget _buildFileUpload(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? 'Choose File';
    final bytes = _inputs[ref];
    final hasFile = bytes is Uint8List && bytes.isNotEmpty;
    final fileName = _inputs['${ref}_name'] as String?;
    final mime = _inputs['${ref}_mime'] as String?;
    final sizeKb = hasFile ? (bytes.lengthInBytes / 1024).round() : 0;

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.fileUp,
                  size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (input['required'] == true)
                Text(
                  'Required',
                  style: TextStyle(
                    color: cs.error.withValues(alpha: 0.8),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasFile) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.fileText, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName ?? 'file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$sizeKb KB${mime != null ? ' · $mime' : ''}',
                          style: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    icon: Icon(LucideIcons.trash2,
                        size: 16, color: cs.error.withValues(alpha: 0.8)),
                    onPressed: () {
                      setState(() {
                        _inputs.remove(ref);
                        _inputs.remove('${ref}_path');
                        _inputs.remove('${ref}_name');
                        _inputs.remove('${ref}_mime');
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            GradientButton(
              icon: LucideIcons.upload,
              label: 'Replace',
              onPressed: () => _pickGenericFile(ref, input),
              variant: ButtonVariant.secondary,
              size: ButtonSize.medium,
              expanded: true,
            ),
          ] else
            GradientButton(
              icon: LucideIcons.upload,
              label: label,
              onPressed: () => _pickGenericFile(ref, input),
              variant: ButtonVariant.primary,
              size: ButtonSize.medium,
              expanded: true,
            ),
        ],
      ),
    );
  }

  Future<void> _pickGenericFile(String ref, Map<String, dynamic> input) async {
    try {
      final accept = (input['accept'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList();
      final maxSizeMb = (input['maxSizeMb'] as num?)?.toDouble();
      final res = await FilePicker.platform.pickFiles(
        type: accept != null && accept.isNotEmpty
            ? FileType.custom
            : FileType.any,
        allowedExtensions: accept,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      final data = f.bytes;
      if (data == null) return;
      if (maxSizeMb != null && data.lengthInBytes > maxSizeMb * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File exceeds ${maxSizeMb}MB limit')),
          );
        }
        return;
      }
      setState(() {
        _inputs[ref] = data;
        _inputs['${ref}_path'] = f.path;
        _inputs['${ref}_name'] = f.name;
        _inputs['${ref}_mime'] = _guessGenericMime(f.extension ?? '');
      });
    } catch (e) {
      debugPrint('File pick failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick file: $e')),
        );
      }
    }
  }

  String _guessGenericMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'json':
        return 'application/json';
      case 'txt':
        return 'text/plain';
      case 'srt':
        return 'application/x-subrip';
      case 'safetensors':
      case 'bin':
      case 'ckpt':
        return 'application/octet-stream';
      case 'pdf':
        return 'application/pdf';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  /// Same clear control as the Create Image prompt, for every free-text field.
  Widget? _clearTextButton({
    required bool visible,
    required VoidCallback onPressed,
    String tooltip = 'Clear text',
  }) {
    if (!visible) return null;
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        LucideIcons.x,
        size: 16,
        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      onPressed: onPressed,
    );
  }

  void _clearPromptField(String ref) {
    _promptController.clear();
    _inputs[ref] = '';
    setState(() => _selectedStyle = null);
  }

  void _clearBoundText(String ref, {StateSetter? sheetSetter}) {
    void apply() {
      _inputs[ref] = '';
      _promptFillTicks[ref] = (_promptFillTicks[ref] ?? 0) + 1;
    }

    if (sheetSetter != null) {
      sheetSetter(() => setState(apply));
    } else {
      setState(apply);
    }
  }

  // ── 3. text_input ───────────────────────────────────────────────────────
  Widget _buildTextInput(String ref, {StateSetter? sheetSetter}) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? ref;
    final placeholder = input['placeholder'] as String? ?? '';
    final multiline = input['multiline'] == true;
    final minLines = (input['minLines'] as int?) ?? (multiline ? 3 : 1);
    final maxLines = (input['maxLines'] as int?) ?? (multiline ? 6 : 1);
    final maxLength = input['maxLength'] as int?;
    _inputs[ref] ??= input['default']?.toString() ?? '';
    final currentText = _inputs[ref] as String? ?? '';
    final suggestThis = _isPromptStyleRef(ref);

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('$ref-${_promptFillTicks[ref] ?? 0}'),
            initialValue: currentText,
            onChanged: (v) {
              void apply() => _inputs[ref] = v;
              if (sheetSetter != null) {
                sheetSetter(() => setState(apply));
              } else {
                setState(apply);
              }
            },
            minLines: minLines,
            maxLines: maxLines,
            maxLength: maxLength,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              height: 1.4,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: placeholder,
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                fontSize: 14,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.45),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                borderSide:
                    BorderSide(color: cs.outlineVariant.withValues(alpha: 0.22)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                borderSide:
                    BorderSide(color: cs.primary.withValues(alpha: 0.5), width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: _clearTextButton(
                visible: currentText.isNotEmpty,
                onPressed: () =>
                    _clearBoundText(ref, sheetSetter: sheetSetter),
              ),
            ),
          ),
          if (suggestThis) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _autoPromptButton(
                fieldRef: ref,
                suggestField: _suggestFieldForRef(ref),
                currentText: currentText,
                sheetSetter: sheetSetter,
                apply: (value) {
                  _inputs[ref] = value;
                  _promptFillTicks[ref] = (_promptFillTicks[ref] ?? 0) + 1;
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 4. number_input ─────────────────────────────────────────────────────
  Widget _buildNumberInput(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? ref;
    final isInt = input['integer'] == true;
    final minV = (input['min'] as num?)?.toDouble();
    final maxV = (input['max'] as num?)?.toDouble();
    final step = (input['step'] as num?)?.toDouble() ?? (isInt ? 1.0 : 0.1);
    _inputs[ref] ??= input['default'] ?? (minV ?? 0);
    final current = (_inputs[ref] as num).toDouble();

    void commit(num next) {
      var v = next.toDouble();
      if (minV != null && v < minV) v = minV;
      if (maxV != null && v > maxV) v = maxV;
      setState(() => _inputs[ref] = isInt ? v.round() : v);
    }

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _numericStepperButton(
            cs,
            icon: LucideIcons.minus,
            onTap: () => commit(current - step),
          ),
          const SizedBox(width: 8),
          Container(
            constraints: const BoxConstraints(minWidth: 60),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
            ),
            child: Text(
              isInt
                  ? current.round().toString()
                  : current.toStringAsFixed(current % 1 == 0 ? 0 : 2),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _numericStepperButton(
            cs,
            icon: LucideIcons.plus,
            onTap: () => commit(current + step),
          ),
        ],
      ),
    );
  }

  Widget _numericStepperButton(ColorScheme cs,
      {required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppStyles.radiusFull),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surfaceContainerHigh.withValues(alpha: 0.7),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, size: 14, color: cs.onSurfaceVariant),
      ),
    );
  }

  // ── 5. seed_input ───────────────────────────────────────────────────────
  Widget _buildSeedInput(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? 'Seed';
    _inputs[ref] ??= input['default'] ?? -1;
    _inputs['${ref}_locked'] ??= false;
    final current = (_inputs[ref] as num).toInt();
    final locked = _inputs['${ref}_locked'] == true;
    final controller = TextEditingController(text: current.toString());
    controller.selection =
        TextSelection.collapsed(offset: controller.text.length);

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Row(
        children: [
          Icon(LucideIcons.sprout,
              size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(signed: true),
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (v) {
                final parsed = int.tryParse(v) ?? -1;
                setState(() => _inputs[ref] = parsed);
              },
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Randomize',
            icon: Icon(LucideIcons.dices, size: 16, color: cs.primary),
            onPressed: () {
              final r = Random().nextInt(0x7fffffff);
              setState(() {
                _inputs[ref] = r;
              });
            },
          ),
          IconButton(
            tooltip: locked ? 'Unlock seed' : 'Lock seed',
            icon: Icon(
              locked ? LucideIcons.lock : LucideIcons.unlock,
              size: 16,
              color: locked ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            onPressed: () {
              setState(() => _inputs['${ref}_locked'] = !locked);
            },
          ),
        ],
      ),
    );
  }

  // ── 6. aspect_ratio ─────────────────────────────────────────────────────
  Widget _buildAspectRatio(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? 'Aspect Ratio';
    final rawPresets = (input['presets'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['1:1', '16:9', '9:16', '4:3', '3:4', '2:3', '21:9'];
    final presets =
        rawPresets.where((p) => p.trim().toLowerCase() != 'default').toList();
    final presetsEffective = presets.isNotEmpty
        ? presets
        : (rawPresets.isNotEmpty ? rawPresets : const ['1:1']);
    final outputAs = (input['outputAs'] as String?) ?? 'string';
    final baseDim = (input['baseDim'] as int?) ?? 1024;

    String defaultPreset() {
      final d = input['default']?.toString().trim() ?? '';
      if (d.isNotEmpty &&
          d.toLowerCase() != 'default' &&
          presetsEffective.contains(d)) {
        return d;
      }
      if (presetsEffective.contains('1:1')) return '1:1';
      return presetsEffective.first;
    }

    String selectedPreset() {
      final v = _inputs[ref];
      if (v is Map) {
        final r = v['ratio']?.toString().trim();
        if (r != null && presetsEffective.contains(r)) return r;
      } else if (v is String) {
        final s = v.trim();
        if (s.toLowerCase() == 'default') return defaultPreset();
        if (presetsEffective.contains(s)) return s;
      }
      return defaultPreset();
    }

    _inputs[ref] ??= defaultPreset();
    if (_inputs[ref] is String &&
        (_inputs[ref] as String).trim().toLowerCase() == 'default') {
      _inputs[ref] = defaultPreset();
    }

    final selected = selectedPreset();
    var selectedIndex = presetsEffective.indexOf(selected);
    if (selectedIndex < 0) selectedIndex = 0;

    void onPick(int index) {
      final p = presetsEffective[index];
      setState(() {
        _applyAspectRatioPreset(
          ref: ref,
          preset: p,
          outputAs: outputAs,
          baseDim: baseDim,
        );
      });
    }

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose output shape',
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: List.generate(
              presetsEffective.length,
              (i) {
                final p = presetsEffective[i];
                return ButtonSegment<int>(
                  value: i,
                  label: Text(
                    p,
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              },
            ),
            selected: {selectedIndex},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              onPick(s.first);
            },
            showSelectedIcon: false,
          ),
        ],
      ),
    );
  }

  void _applyAspectRatioPreset({
    required String ref,
    required String preset,
    required String outputAs,
    required int baseDim,
  }) {
    final p = preset;
    final parts = p.split(':');
    final w = double.tryParse(parts[0]) ?? 1;
    final h = double.tryParse(parts.length > 1 ? parts[1] : '1') ?? 1;
    if (outputAs == 'dimensions') {
      final long = w >= h ? baseDim : (baseDim * w / h).round();
      final short = h >= w ? baseDim : (baseDim * h / w).round();
      _inputs[ref] = {
        'width': w >= h ? long : short,
        'height': h >= w ? long : short,
        'ratio': p,
      };
    } else {
      _inputs[ref] = p;
    }
  }

  // ── 7. color_picker ─────────────────────────────────────────────────────
  Widget _buildColorPicker(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? 'Color';
    _inputs[ref] ??= input['default'] ?? '#FFFFFF';
    final hex = (_inputs[ref] as String?) ?? '#FFFFFF';
    final color = _parseHexColor(hex);

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hex.toUpperCase(),
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                    fontSize: 11.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: () => _openColorPickerSheet(ref, input),
            borderRadius: BorderRadius.circular(AppStyles.radiusMd),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _parseHexColor(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16) ?? 0xFFFFFFFF;
    return Color(v);
  }

  void _openColorPickerSheet(String ref, Map<String, dynamic> input) {
    final cs = Theme.of(context).colorScheme;
    final presets = (input['presetColors'] as List<dynamic>?)
            ?.map((e) => _parseHexColor(e.toString()))
            .toList() ??
        const [
          Color(0xFFFFFFFF),
          Color(0xFF000000),
          Color(0xFFFF3B30),
          Color(0xFFFF9500),
          Color(0xFFFFCC00),
          Color(0xFF34C759),
          Color(0xFF5AC8FA),
          Color(0xFF007AFF),
          Color(0xFF5856D6),
          Color(0xFFAF52DE),
          Color(0xFFFF2D55),
          Color(0xFF8E8E93),
        ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pick a color',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: presets.map((c) {
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _inputs[ref] = _colorToHex(c);
                        });
                        Navigator.pop(ctx);
                      },
                      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius:
                              BorderRadius.circular(AppStyles.radiusMd),
                          border: Border.all(
                              color: cs.outlineVariant.withValues(alpha: 0.3)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _colorToHex(Color c) {
    final value = c.toARGB32() & 0xFFFFFF;
    return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  // ── 8. multi_select ─────────────────────────────────────────────────────
  Widget _buildMultiSelect(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? ref;
    final rawOptions = (input['options'] as List<dynamic>?) ?? const [];
    // Each option is either a plain string or `{id, label, icon?}`.
    final options = rawOptions.map((o) {
      if (o is String) return {'id': o, 'label': o};
      return Map<String, dynamic>.from(o as Map);
    }).toList();
    final minSel = (input['min'] as int?) ?? 0;
    final maxSel = (input['max'] as int?);
    _inputs[ref] ??= List<String>.from(
        (input['default'] as List<dynamic>?)?.map((e) => e.toString()) ?? []);
    final selected = List<String>.from(_inputs[ref] as List);

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${selected.length}${maxSel != null ? " / $maxSel" : ""}',
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((o) {
              final id = o['id'] as String;
              final lbl = (o['label'] as String?) ?? id;
              final isOn = selected.contains(id);
              return InkWell(
                onTap: () {
                  setState(() {
                    if (isOn) {
                      if (selected.length <= minSel) return;
                      selected.remove(id);
                    } else {
                      if (maxSel != null && selected.length >= maxSel) return;
                      selected.add(id);
                    }
                    _inputs[ref] = selected;
                  });
                },
                borderRadius: BorderRadius.circular(AppStyles.radiusFull),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isOn
                        ? cs.primary.withValues(alpha: 0.14)
                        : cs.surfaceContainerHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppStyles.radiusFull),
                    border: Border.all(
                      color: isOn
                          ? cs.primary.withValues(alpha: 0.55)
                          : cs.outlineVariant.withValues(alpha: 0.25),
                      width: isOn ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOn ? LucideIcons.check : LucideIcons.plus,
                        size: 12,
                        color: isOn
                            ? cs.primary
                            : cs.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        lbl,
                        style: TextStyle(
                          color: isOn
                              ? cs.primary
                              : cs.onSurfaceVariant.withValues(alpha: 0.9),
                          fontSize: 12.5,
                          fontWeight: isOn ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── 9. range_slider ─────────────────────────────────────────────────────
  Widget _buildRangeSlider(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label'] ?? ref;
    final minV = (input['min'] as num?)?.toDouble() ?? 0;
    final maxV = (input['max'] as num?)?.toDouble() ?? 100;
    final defMin = (input['defaultMin'] as num?)?.toDouble() ?? minV;
    final defMax = (input['defaultMax'] as num?)?.toDouble() ?? maxV;
    _inputs[ref] ??= {'start': defMin, 'end': defMax};
    final cur = _inputs[ref] as Map;
    final start = (cur['start'] as num?)?.toDouble() ?? defMin;
    final end = (cur['end'] as num?)?.toDouble() ?? defMax;

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${start.toStringAsFixed(start % 1 == 0 ? 0 : 1)}'
                ' – '
                '${end.toStringAsFixed(end % 1 == 0 ? 0 : 1)}',
                style: TextStyle(
                  color: cs.primary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.25),
              thumbColor: cs.primary,
              overlayColor: cs.primary.withValues(alpha: 0.12),
              trackHeight: 4,
              rangeThumbShape:
                  const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: RangeSlider(
              min: minV,
              max: maxV,
              values:
                  RangeValues(start.clamp(minV, maxV), end.clamp(minV, maxV)),
              onChanged: (v) {
                setState(() {
                  _inputs[ref] = {'start': v.start, 'end': v.end};
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── 10. info_card ──────────────────────────────────────────────────────
  Widget _buildInfoCard(Map<String, dynamic> e) {
    final cs = Theme.of(context).colorScheme;
    final title = e['title'] as String?;
    final body = e['body'] as String?;
    final variant = (e['variant'] as String?) ?? 'info';
    Color tint;
    IconData defaultIcon;
    switch (variant) {
      case 'warn':
        tint = Colors.amber;
        defaultIcon = LucideIcons.alertTriangle;
        break;
      case 'tip':
        tint = KalaColors.purple;
        defaultIcon = LucideIcons.lightbulb;
        break;
      case 'success':
        tint = Colors.green;
        defaultIcon = LucideIcons.checkCircle;
        break;
      default:
        tint = cs.primary;
        defaultIcon = LucideIcons.info;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        border: Border.all(color: tint.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(defaultIcon, size: 16, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null && title.isNotEmpty)
                  Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (body != null && body.isNotEmpty) ...[
                  if (title != null && title.isNotEmpty)
                    const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.85),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 11. section_header ─────────────────────────────────────────────────
  Widget _buildSectionHeader(Map<String, dynamic> e) {
    final cs = Theme.of(context).colorScheme;
    final title = e['title'] as String? ?? '';
    final subtitle = e['subtitle'] as String?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // -------- Prompt Input Section --------
  /// The prompt element now renders as a polished "composer card" that includes
  /// selected Style chips, the prompt TextField, and a model/output meta row.
  /// The previously inline Style & Tags enhancer is rendered as a separate
  /// section below the shortcut bar (see `_buildDynamicInputScreen`).
  Widget _buildPrompt(String ref) => _buildComposerCard(ref);

  /// Build the Prompt content with guided input and style pills.
  ///
  /// NOTE: Since the UI redesign, the prompt renders through
  /// `_buildComposerCard`. This method is retained as a fallback reference
  /// implementation but is no longer called.
  // ignore: unused_element
  Widget _buildPromptContent(String ref, String label) {
    final cs = Theme.of(context).colorScheme;
    final promptLength = _promptController.text.length;
    final showCharCounter = promptLength > 0;

    return _buildCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Explore link
          Row(
            children: [
              Icon(LucideIcons.penTool, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Prompt',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Link to Explore for templates
              GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  selectedIndexNotifier.value = AppTabs.explore;
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        KalaColors.purple.withValues(alpha: 0.15),
                        KalaColors.magenta.withValues(alpha: 0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: KalaColors.purple.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.sparkles,
                          size: 12, color: KalaColors.purple),
                      SizedBox(width: 4),
                      Text(
                        'Browse Templates',
                        style: TextStyle(
                          color: KalaColors.purple,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(LucideIcons.arrowRight,
                          size: 10, color: KalaColors.purple),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Applied style indicator (only for styles now)
          if (_selectedStyle != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _selectedStyle!.icon,
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Style: ${_selectedStyle!.name}',
                      style: TextStyle(
                        color: cs.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      _removeStyleFromPrompt(_selectedStyle!);
                      setState(() => _selectedStyle = null);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.x,
                        size: 16,
                        color: cs.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Prompt text field with guided placeholder
          TextField(
            controller: _promptController,
            onChanged: (v) {
              _inputs[ref] = v;
              setState(() {}); // Trigger rebuild
            },
            maxLines: _kComposerPromptMaxLines,
            minLines: _kComposerPromptMinLines,
            decoration: InputDecoration(
              hintText: 'Describe what you want to create...',
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 15,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHigh.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffixIcon: _clearTextButton(
                visible: _promptController.text.isNotEmpty,
                tooltip: 'Clear prompt',
                onPressed: () => _clearPromptField(ref),
              ),
            ),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 8),

          // Example text and character counter row
          Row(
            children: [
              // Example subtext
              Expanded(
                child: Text(
                  'e.g. "Anime portrait, cinematic lighting, dramatic pose"',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              // Character counter (only shown when typing)
              AnimatedOpacity(
                opacity: showCharCounter ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$promptLength',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Style & Tags section (Quick style presets + helper tags)
          _buildPromptEnhancerSection(cs),
        ],
      ),
    );
  }

  /// Build unified Style & Tags section (Visual styles + Quick helper tags)
  Widget _buildPromptEnhancerSection(ColorScheme cs) {
    final bool showAds = shouldShowNativeBannerAds();
    final styles = _getStylesByCategory(_selectedStyleCategory);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  KalaColors.purple.withValues(alpha: 0.08),
                  KalaColors.magenta.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.sparkle,
                    size: 16, color: KalaColors.purple),
                const SizedBox(width: 6),
                Text(
                  'Style & Tags',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_selectedStyle != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_selectedStyle!.icon,
                              style: const TextStyle(fontSize: 10)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              _selectedStyle!.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                const Spacer(),
                GestureDetector(
                  onTap: _stylesForThisTool.isEmpty ? null : _applyRandomStyle,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          KalaColors.purple.withValues(alpha: 0.15),
                          KalaColors.magenta.withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: KalaColors.purple.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.shuffle,
                            size: 12, color: KalaColors.purple),
                        SizedBox(width: 4),
                        Text(
                          'Random',
                          style: TextStyle(
                            color: KalaColors.purple,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    _buildEnhancerTab(
                        cs, 0, 'Styles', LucideIcons.palette, styles.length),
                    const SizedBox(width: 8),
                    _buildEnhancerTab(cs, 1, 'My Templates',
                        LucideIcons.bookmark, _userTemplates.length),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _enhancerTabIndex == 0
                    ? _buildStylesContent(cs, styles)
                    : _buildMyTemplatesContent(cs),
              ),
              const SizedBox(height: 8),
              if (showAds)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: const ThemedNativeAd(
                      height: 100,
                      useSmallTemplate: true,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build enhancer tab button
  Widget _buildEnhancerTab(
      ColorScheme cs, int index, String label, IconData icon, int count) {
    final isSelected = _enhancerTabIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _enhancerTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary.withValues(alpha: 0.12)
                : cs.surfaceContainerHigh.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.4)
                  : cs.outlineVariant.withValues(alpha: 0.15),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? cs.primary
                    : cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? cs.primary
                      : cs.onSurfaceVariant.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary.withValues(alpha: 0.2)
                      : cs.onSurfaceVariant.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected
                        ? cs.primary
                        : cs.onSurfaceVariant.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build styles content with categories and style cards
  Widget _buildStylesContent(ColorScheme cs, List<StylePreset> styles) {
    return Padding(
      key: const ValueKey('styles'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category filter
          SizedBox(
            height: 32,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _visibleStyleCategories.length,
              itemBuilder: (context, index) {
                final category = _visibleStyleCategories[index];
                final isSelected = _selectedStyleCategory == category;
                final isFavorites = category == 'Favorites';
                final favCount = _stylesForThisTool
                    .where((style) => _favoriteStyles.contains(style.id))
                    .length;

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedStyleCategory = category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isFavorites
                                ? Colors.red.withValues(alpha: 0.15)
                                : cs.secondary.withValues(alpha: 0.15))
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? (isFavorites
                                  ? Colors.red.withValues(alpha: 0.4)
                                  : cs.secondary.withValues(alpha: 0.4))
                              : cs.outlineVariant.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isFavorites) ...[
                            Icon(
                              Icons.favorite,
                              size: 12,
                              color: isSelected
                                  ? Colors.red
                                  : cs.onSurfaceVariant.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            isFavorites ? 'Favorites ($favCount)' : category,
                            style: TextStyle(
                              color: isSelected
                                  ? (isFavorites ? Colors.red : cs.secondary)
                                  : cs.onSurfaceVariant.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),

          // Empty state for favorites
          if (styles.isEmpty && _selectedStyleCategory == 'Favorites')
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.heart,
                      size: 28,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No favorites yet',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Long-press any style to add to favorites',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (styles.isNotEmpty)
            // Styles grid (2 rows of scrollable cards)
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: styles.length,
                itemBuilder: (context, index) {
                  final style = styles[index];
                  final isSelected = _selectedStyle?.id == style.id;
                  final isFavorite = _favoriteStyles.contains(style.id);

                  return _buildStyleChip(cs, style, isSelected, isFavorite);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Build individual style chip with favorite support
  Widget _buildStyleChip(
      ColorScheme cs, StylePreset style, bool isSelected, bool isFavorite) {
    // Get category color
    final categoryColors = {
      'Fun': const Color(0xFFFF6B6B),
      'Realistic': const Color(0xFF3B82F6),
      'Artistic': const Color(0xFF8B5CF6),
      'Anime': const Color(0xFFEC4899),
      'Cinematic': const Color(0xFFF59E0B),
      'Motion': const Color(0xFF14B8A6),
      'Stylized': const Color(0xFFA855F7),
    };
    final accentColor = categoryColors[style.category] ?? cs.secondary;
    final hasPreview = style.previewUrl != null && style.previewUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: () => _selectStyle(style),
        onLongPress: () {
          _toggleFavoriteStyle(style.id);
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    _favoriteStyles.contains(style.id)
                        ? Icons.favorite
                        : LucideIcons.heart,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _favoriteStyles.contains(style.id)
                        ? 'Added "${style.name}" to favorites'
                        : 'Removed "${style.name}" from favorites',
                  ),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
              backgroundColor: _favoriteStyles.contains(style.id)
                  ? Colors.red
                  : cs.inverseSurface,
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 100,
          height: 90,
          decoration: BoxDecoration(
            gradient: isSelected && !hasPreview
                ? LinearGradient(
                    colors: [
                      accentColor.withValues(alpha: 0.2),
                      accentColor.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: (isSelected || hasPreview) ? null : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? accentColor.withValues(alpha: 0.6)
                  : cs.outlineVariant.withValues(alpha: 0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background: Preview image/video or gradient
                if (hasPreview)
                  _StylePreviewImage(
                    style: style,
                    accentColor: accentColor,
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withValues(alpha: 0.15),
                          accentColor.withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                // Overlay gradient for text readability
                if (hasPreview)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                          ],
                          stops: const [0.3, 1.0],
                        ),
                      ),
                    ),
                  ),
                // Content overlay
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: Icon + Favorite/Check
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (!hasPreview)
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(style.icon,
                                  style: const TextStyle(fontSize: 12)),
                            )
                          else
                            const SizedBox(width: 20),
                          if (isSelected)
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: accentColor,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(LucideIcons.check,
                                  size: 10, color: Colors.white),
                            )
                          else if (isFavorite)
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.3),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.favorite,
                                  size: 12, color: Colors.red),
                            ),
                        ],
                      ),
                      const Spacer(),
                      // Name
                      Text(
                        style.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasPreview
                              ? Colors.white
                              : (isSelected ? accentColor : cs.onSurface),
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          shadows: hasPreview
                              ? [
                                  Shadow(
                                      color: Colors.black.withValues(alpha: 0.5),
                                      blurRadius: 2),
                                ]
                              : null,
                        ),
                      ),
                      // Category badge
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: hasPreview
                              ? Colors.black.withValues(alpha: 0.4)
                              : accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          style.category,
                          style: TextStyle(
                            color: hasPreview
                                ? Colors.white.withValues(alpha: 0.9)
                                : accentColor.withValues(alpha: 0.8),
                            fontSize: 8,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
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

  /// Build my templates content
  Widget _buildMyTemplatesContent(ColorScheme cs) {
    return Padding(
      key: const ValueKey('templates'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Save current as template button
          GestureDetector(
            onTap: _saveCurrentAsTemplate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: cs.primary.withValues(alpha: 0.3),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.plus, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Save Current Settings as Template',
                    style: TextStyle(
                      color: cs.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Templates list
          if (_userTemplates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      LucideIcons.bookmark,
                      size: 48,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No templates yet',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Save your settings to create one',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: _userTemplates.length,
                itemBuilder: (context, index) {
                  final template = _userTemplates[index];
                  return _buildTemplateCard(cs, template);
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Build template card
  Widget _buildTemplateCard(ColorScheme cs, UserTemplate template) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => _applyTemplate(template),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  LucideIcons.bookmark,
                  size: 16,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      template.prompt.isEmpty
                          ? 'No prompt'
                          : template.prompt.length > 40
                              ? '${template.prompt.substring(0, 40)}...'
                              : template.prompt,
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (template.lastUsed != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Last used: ${_formatTemplateDate(template.lastUsed!)}',
                        style: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Delete button
              IconButton(
                icon: Icon(
                  LucideIcons.trash2,
                  size: 16,
                  color: cs.error.withValues(alpha: 0.7),
                ),
                onPressed: () => _deleteTemplate(template),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------- Image Upload with Bulk Edit Support --------
  Widget _buildImageUpload(String ref) {
    final input = _effectiveInputConfig(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final hasImage = _inputs[ref] != null &&
        (_inputs[ref] is List && (_inputs[ref] as List).isNotEmpty);
    final isVip = isVipUser();
    final isBulkMode =
        _advancedSettings.bulkEditEnabled && _supportsBulkImageEdit;
    final showBulkOption =
        _supportsBulkImageEdit && ref == _bulkPrimaryImageInputRef;
    final label = input["label"] ?? "Upload Image";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact section header for optional reference inputs.
        if (ref == 'ref_image') ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(
              children: [
                Icon(LucideIcons.image,
                    size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '· Optional',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        _buildCard(
          elevated: hasImage || _hasBulkInput,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mode Switch (Single / Bulk)
              if (showBulkOption) ...[
                _buildImageModeSwitch(
                  cs,
                  isVip,
                  isBulkMode,
                  beforeLeaveBulk: _leaveBulkModeCleanup,
                  onEnterBulk: _enterBulkModeSetup,
                ),
                const SizedBox(height: 14),
              ],

              // Content based on mode
              if (isBulkMode)
                _buildBulkImagesContent(cs)
              else ...[
                // Single image mode - normal upload
                _buildImagePreview(ref),
                const SizedBox(height: 14),
                // Buttons row
                if (hasImage)
                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          icon: LucideIcons.imagePlus,
                          label: "Change",
                          onPressed: () => _pickImage(input),
                          variant: ButtonVariant.primary,
                          size: ButtonSize.medium,
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GradientButton(
                        icon: LucideIcons.trash2,
                        label: "Remove",
                        onPressed: () {
                          setState(() {
                            _inputs.remove(ref);
                            _inputs.remove("${ref}_path");
                          });
                        },
                        variant: ButtonVariant.secondary,
                        size: ButtonSize.medium,
                        expanded: false,
                      ),
                    ],
                  )
                else
                  GradientButton(
                    icon: LucideIcons.upload,
                    label: label,
                    onPressed: () => _pickImage(input),
                    variant: ButtonVariant.primary,
                    size: ButtonSize.medium,
                    expanded: true,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build video upload widget
  Widget _buildVideoUpload(String ref) {
    final input = _effectiveInputConfig(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final pathEarly = _inputs['${ref}_path'] as String?;
    final hasVideo = (pathEarly != null && pathEarly.isNotEmpty) ||
        (_inputs[ref] != null &&
            _inputs[ref] is String &&
            (_inputs[ref] as String).isNotEmpty);
    final label = input["label"] ?? "Upload Video";
    final isVip = isVipUser();
    final isBulkMode =
        _advancedSettings.bulkEditEnabled && _supportsBulkVideoEdit;
    final showBulkOption =
        _supportsBulkVideoEdit && ref == _bulkPrimaryVideoInputRef;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Compact section header for optional reference inputs.
        if (ref == 'ref_image' || ref == 'ref_video') ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(
              children: [
                Icon(
                  ref == 'ref_image' ? LucideIcons.image : LucideIcons.video,
                  size: 12,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '· Optional',
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
        _buildCard(
          elevated: hasVideo ||
              (showBulkOption && _hasBulkInput && _bulkVideoPaths.isNotEmpty),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showBulkOption) ...[
                _buildImageModeSwitch(
                  cs,
                  isVip,
                  isBulkMode,
                  beforeLeaveBulk: _leaveBulkModeCleanup,
                  onEnterBulk: _enterBulkModeSetup,
                ),
                const SizedBox(height: 14),
              ],
              if (isBulkMode)
                _buildBulkVideosContent(cs, input)
              else ...[
                _buildVideoPreview(ref),
                const SizedBox(height: 14),
                if (hasVideo)
                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          icon: LucideIcons.video,
                          label: "Change",
                          onPressed: () => _pickVideo(input),
                          variant: ButtonVariant.primary,
                          size: ButtonSize.medium,
                          expanded: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      GradientButton(
                        icon: LucideIcons.trash2,
                        label: "Remove",
                        onPressed: () {
                          setState(() {
                            final p = _inputs["${ref}_path"] as String?;
                            if (p != null) {
                              final c = _userVideoControllers.remove(p);
                              c?.dispose();
                            }
                            _inputs.remove(ref);
                            _inputs.remove("${ref}_path");
                            _inputs.remove("${ref}_bytes");
                            _inputVideoDuration = null;
                          });
                        },
                        variant: ButtonVariant.secondary,
                        size: ButtonSize.medium,
                        expanded: false,
                      ),
                    ],
                  )
                else
                  GradientButton(
                    icon: LucideIcons.video,
                    label: label,
                    onPressed: () => _pickVideo(input),
                    variant: ButtonVariant.primary,
                    size: ButtonSize.medium,
                    expanded: true,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Build video preview widget
  Widget _buildVideoPreview(String ref) {
    final cs = Theme.of(context).colorScheme;
    final videoPath = _inputs["${ref}_path"] as String?;
    final hasVideo = videoPath != null && videoPath.isNotEmpty;

    if (!hasVideo) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.2),
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.video,
                size: 48,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'No video selected',
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final controller = _userVideoControllers[videoPath];

    return Container(
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: controller != null && _isVideoUpscalerTool
            ? GestureDetector(
                onTap: () {
                  if (controller.value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SafeVideoView(
                      controller: controller,
                      fit: BoxFit.contain,
                      fallback: const ColoredBox(color: Colors.black),
                    ),
                    // Play/Pause button overlay
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        // Show overlay when paused, hide when playing
                        final showOverlay = !value.isPlaying;
                        return AnimatedOpacity(
                          opacity: showOverlay ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.3),
                            child: Center(
                              child: Icon(
                                value.isPlaying
                                    ? LucideIcons.pause
                                    : LucideIcons.play,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  // Video player
                  if (controller != null)
                    SafeVideoView(
                      controller: controller,
                      fit: BoxFit.contain,
                      fallback: const ColoredBox(color: Colors.black),
                    ),
                  // For non-upscaler tools, show static play icon (existing behavior)
                  if (controller != null && !_isVideoUpscalerTool)
                    Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: const Center(
                        child: Icon(
                          LucideIcons.play,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// Pick video from gallery or camera.
  /// [bulkAllowMultiSelect]: gallery flow can select several files (bulk video upscale).
  Future<ImageSource?> _promptVideoPickSource(
      {bool bulkAllowMultiSelect = false}) {
    return showMediaSourcePickerBottomSheet(
      context,
      title: 'Add a video',
      galleryLabel: 'Videos',
      gallerySublabel: bulkAllowMultiSelect
          ? 'Select one or more videos'
          : 'Choose from gallery',
      cameraSublabel: 'Record a new video',
      galleryIcon: LucideIcons.film,
      cameraIcon: LucideIcons.video,
    );
  }

  Future<void> _pickVideo(Map<String, dynamic> input) async {
    try {
      final source = await _promptVideoPickSource();
      if (source == null) return;

      final file = await picker.pickVideo(source: source);
      if (file == null) return;

      final videoPath = file.path;

      // Initialize video player to get duration
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      final originalDuration = controller.value.duration;

      // For video upscaler: check maxDuration cap from tool_config.json (default 2 minutes = 120 seconds)
      if (_isVideoUpscalerTool) {
        // Get maxDuration from tool_config.json
        final modelId = _selectedModelId ?? _tool.model;
        final modelData = _tool.models?.firstWhere(
              (m) => m['id'] == modelId,
              orElse: () => <String, dynamic>{},
            ) ??
            <String, dynamic>{};
        final maxDurationSeconds = (modelData['maxDuration'] as int?) ?? 120;
        final maxDuration = Duration(seconds: maxDurationSeconds);

        if (originalDuration > maxDuration) {
          // Warn user and ask to proceed with trimmed video
          final shouldProceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Video Too Long'),
              content: Text(
                'Your video is ${_formatDuration(originalDuration)} long. '
                'Only the first ${_formatDuration(maxDuration)} will be processed. '
                'Do you want to continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          );

          if (shouldProceed != true) {
            await controller.dispose();
            return;
          }

          // Store the trimmed duration
          _inputVideoDuration = maxDuration;
        } else {
          _inputVideoDuration = originalDuration;
        }
      } else {
        _inputVideoDuration = originalDuration;
      }

      // Read video bytes (for video upscaler, we'll use the full file path)
      // The backend will handle trimming if needed
      final videoBytes = await file.readAsBytes();
      if (_isSunoV6 && input['id'] == 'clip') {
        if (originalDuration.inSeconds > 241 ||
            videoBytes.length > 100 * 1024 * 1024) {
          await controller.dispose();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Use a clip up to 4 minutes and 100 MB.'),
              ),
            );
          }
          return;
        }
      }
      final base64Video = base64Encode(videoBytes);

      // For video upscaler: disable looping and don't auto-play (user controls playback)
      if (_isVideoUpscalerTool) {
        controller.setLooping(false);
      } else {
        controller.setLooping(true);
      }
      controller.setVolume(0);

      final vidId = input['id'] as String?;
      if (_isAnimateImageTool &&
          _isCineRealAnimateModel &&
          vidId == 'ref_video') {
        _inputs.remove('last_frame_image');
        _inputs.remove('last_frame_image_path');
        _clearCineRealSingleRefVideo();
      }

      setState(() {
        _inputs[input['id']] = base64Video;
        _inputs["${input['id']}_bytes"] = videoBytes; // raw bytes for R2 upload
        _inputs["${input['id']}_path"] = videoPath;
        _userVideoControllers[videoPath] = controller;
        // Store duration for cost calculation and backend
        if (_inputVideoDuration != null) {
          final durationSeconds = _inputVideoDuration!.inSeconds;
          _inputs["${input['id']}_duration"] = durationSeconds;
          // Also store as video_duration for template resolution
          if (_isVideoUpscalerTool) {
            // Get maxDuration from tool_config.json (default 2 minutes = 120 seconds)
            final modelId = _selectedModelId ?? _tool.model;
            final modelData = _tool.models?.firstWhere(
                  (m) => m['id'] == modelId,
                  orElse: () => <String, dynamic>{},
                ) ??
                <String, dynamic>{};
            final maxDurationSeconds =
                (modelData['maxDuration'] as int?) ?? 120;
            final maxDuration = Duration(seconds: maxDurationSeconds);

            // Cap at maxDuration for backend
            final actualDuration = _inputVideoDuration! > maxDuration
                ? maxDuration.inSeconds
                : durationSeconds;
            _inputs["video_duration"] = actualDuration;
          }
        }
      });

      // Don't auto-play for video upscaler - let user control playback
      if (!_isVideoUpscalerTool) {
        controller.play();
      }
    } catch (e) {
      debugPrint('❌ Error picking video: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking video: $e')),
        );
      }
    }
  }

  int _modelMaxVideoDurationSeconds() {
    final modelId = _selectedModelId ?? _tool.model;
    final modelData = _tool.models?.firstWhere(
          (m) => m['id'] == modelId,
          orElse: () => <String, dynamic>{},
        ) ??
        <String, dynamic>{};
    return (modelData['maxDuration'] as int?) ?? 120;
  }

  void _disposeBulkVideoListInPlace() {
    for (final p in List<String>.from(_bulkVideoPaths)) {
      _userVideoControllers.remove(p)?.dispose();
    }
    _bulkVideoPaths.clear();
    _bulkVideoDurations.clear();
  }

  void _clearBulkVideos() {
    setState(_disposeBulkVideoListInPlace);
  }

  Future<void> _hydrateVideoUpscalerBulkIndex(int index) async {
    final ref = _bulkPrimaryVideoInputRef!;
    if (index < 0 || index >= _bulkVideoPaths.length) {
      throw StateError('Invalid bulk video index');
    }
    final videoPath = _bulkVideoPaths[index];
    final stored =
        index < _bulkVideoDurations.length ? _bulkVideoDurations[index] : null;
    if (stored == null || stored.inSeconds <= 0) {
      throw StateError('Missing duration for bulk video');
    }

    final oldPath = _inputs['${ref}_path'] as String?;
    if (oldPath != null && oldPath != videoPath) {
      final c = _userVideoControllers.remove(oldPath);
      await c?.dispose();
    }

    final file = File(videoPath);
    final videoBytes = await file.readAsBytes();
    final base64Video = base64Encode(videoBytes);

    final controller = VideoPlayerController.file(file);
    await controller.initialize();
    controller.setLooping(false);
    controller.setVolume(0);

    final maxDuration = Duration(seconds: _modelMaxVideoDurationSeconds());
    final effectiveDuration = stored > maxDuration ? maxDuration : stored;
    _inputVideoDuration = effectiveDuration;

    if (!mounted) return;
    setState(() {
      _inputs[ref] = base64Video;
      _inputs['${ref}_bytes'] = videoBytes;
      _inputs['${ref}_path'] = videoPath;
      _userVideoControllers[videoPath] = controller;
      _inputs['${ref}_duration'] = stored.inSeconds;
      _inputs['video_duration'] = effectiveDuration.inSeconds;
    });
  }

  void _removeBulkVideoAt(int index) {
    if (index < 0 || index >= _bulkVideoPaths.length) return;
    final p = _bulkVideoPaths[index];
    final c = _userVideoControllers.remove(p);
    c?.dispose();
    setState(() {
      _bulkVideoPaths.removeAt(index);
      if (index < _bulkVideoDurations.length) {
        _bulkVideoDurations.removeAt(index);
      }
    });
  }

  /// Writable path for a picked video (handles web / missing path via temp file).
  Future<String?> _materializePickedVideoFile(PlatformFile f) async {
    if (f.path != null && f.path!.isNotEmpty) {
      return f.path;
    }
    if (f.bytes != null && f.bytes!.isNotEmpty) {
      final dir = await getTemporaryDirectory();
      final name = f.name.isNotEmpty
          ? f.name
          : 'bulk_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final out = File('${dir.path}/$name');
      await out.writeAsBytes(f.bytes!, flush: true);
      return out.path;
    }
    return null;
  }

  /// Probe duration, confirm if over max, append to bulk lists. Returns true if added.
  Future<bool> _appendBulkVideoFromPath(String videoPath) async {
    if (_bulkVideoPaths.contains(videoPath)) return false;

    final probe = VideoPlayerController.file(File(videoPath));
    await probe.initialize();
    final originalDuration = probe.value.duration;
    await probe.dispose();

    final maxDuration = Duration(seconds: _modelMaxVideoDurationSeconds());
    late final Duration storedDuration;
    if (originalDuration > maxDuration) {
      if (!mounted) return false;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Video Too Long'),
          content: Text(
            'This video is ${_formatDuration(originalDuration)} long. '
            'Only the first ${_formatDuration(maxDuration)} will be processed. Add anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      if (proceed != true) return false;
      storedDuration = maxDuration;
    } else {
      storedDuration = originalDuration;
    }

    if (!mounted) return false;
    setState(() {
      _bulkVideoPaths.add(videoPath);
      _bulkVideoDurations.add(storedDuration);
    });
    return true;
  }

  static bool _xFileLooksLikeVideo(XFile f) {
    final mime = f.mimeType?.toLowerCase();
    if (mime != null && mime.startsWith('video/')) return true;
    final n = f.name.toLowerCase();
    const ext = [
      '.mp4',
      '.mov',
      '.m4v',
      '.webm',
      '.mkv',
      '.avi',
      '.3gp',
      '.mpeg',
      '.mpg',
    ];
    for (final e in ext) {
      if (n.endsWith(e)) return true;
    }
    return false;
  }

  Future<void> _pickVideosForBulk(Map<String, dynamic> input) async {
    if (!_supportsBulkVideoEdit) return;
    if (_bulkVideoPaths.length >= _maxBulkImages) return;
    try {
      final source = await _promptVideoPickSource(bulkAllowMultiSelect: true);
      if (source == null) return;

      if (source == ImageSource.gallery) {
        final countBefore = _bulkVideoPaths.length;
        var remaining = _maxBulkImages - _bulkVideoPaths.length;

        // 1) System photo library — true multi-select on iOS 14+ / Android (videos + photos; we keep videos).
        try {
          final media = await picker.pickMultipleMedia(
            limit: remaining.clamp(1, 99),
            requestFullMetadata: true,
          );
          if (media.isEmpty) return;

          final videos = media.where(_xFileLooksLikeVideo).toList();
          if (videos.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Selection had no videos. Opening file browser — pick .mp4, .mov, etc.',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          } else {
            for (final xf in videos) {
              if (remaining <= 0) break;
              final path = xf.path;
              if (path.isEmpty) continue;
              final ok = await _appendBulkVideoFromPath(path);
              if (ok) {
                remaining--;
              }
            }
          }
        } catch (e, st) {
          debugPrint('pickMultipleMedia (bulk video): $e\n$st');
        }

        // 2) Files / storage — explicit extensions; Android often needs this for multi-select.
        if (_bulkVideoPaths.length == countBefore) {
          final result = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            allowedExtensions: [
              'mp4',
              'mov',
              'm4v',
              'webm',
              'mkv',
              'avi',
              '3gp',
              'mpeg',
              'mpg',
            ],
            allowMultiple: true,
          );
          if (result == null || result.files.isEmpty) return;

          remaining = _maxBulkImages - _bulkVideoPaths.length;
          for (final pf in result.files) {
            if (remaining <= 0) break;
            final path = await _materializePickedVideoFile(pf);
            if (path == null) continue;
            final ok = await _appendBulkVideoFromPath(path);
            if (ok) {
              remaining--;
            }
          }
        }

        if (!mounted) return;
        final addedTotal = _bulkVideoPaths.length - countBefore;
        if (addedTotal > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                addedTotal == 1 ? 'Added 1 video' : 'Added $addedTotal videos',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (_bulkVideoPaths.length == countBefore) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No videos were added.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        final file = await picker.pickVideo(source: source);
        if (file == null) return;
        await _appendBulkVideoFromPath(file.path);
      }
    } catch (e) {
      debugPrint('❌ Error adding bulk video: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding video: $e')),
        );
      }
    }
  }

  Widget _buildBulkVideosContent(ColorScheme cs, Map<String, dynamic> input) {
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());
    final totalJobs = !_hasBulkInput ? 0 : _bulkVideoPaths.length * variations;
    final exceedsLimit = totalJobs > _maxTotalJobs;
    final maxVideosForVariations =
        (_maxTotalJobs / variations).floor().clamp(1, _maxBulkImages);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasBulkInput)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: exceedsLimit
                  ? cs.errorContainer.withValues(alpha: 0.3)
                  : cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: exceedsLimit
                    ? cs.error.withValues(alpha: 0.3)
                    : cs.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  exceedsLimit ? LucideIcons.alertTriangle : LucideIcons.info,
                  size: 16,
                  color: exceedsLimit ? cs.error : cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_bulkVideoPaths.length} videos × $variations variations = $totalJobs jobs',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _clearBulkVideos,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(LucideIcons.trash2, size: 14, color: cs.error),
                  ),
                ),
              ],
            ),
          ),
        if (_hasBulkInput) const SizedBox(height: 12),
        if (!_hasBulkInput)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Add videos to process in bulk',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          )
        else
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _bulkVideoPaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final path = _bulkVideoPaths[i];
                final name = path.split(Platform.pathSeparator).last;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 132,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              height: 56,
                              width: double.infinity,
                              child: _BulkVideoStripThumb(
                                videoPath: path,
                                placeholderColor: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10, color: cs.onSurface),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _removeBulkVideoAt(i),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: cs.errorContainer,
                              shape: BoxShape.circle,
                            ),
                            child:
                                Icon(LucideIcons.x, size: 14, color: cs.error),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        const SizedBox(height: 12),
        GradientButton(
          icon: !_hasBulkInput ? LucideIcons.video : LucideIcons.plus,
          label: !_hasBulkInput
              ? 'Select videos (up to $maxVideosForVariations)'
              : 'Add more (${_bulkVideoPaths.length}/$_maxBulkImages)',
          onPressed: () async {
            if (_bulkVideoPaths.length >= _maxBulkImages || exceedsLimit) {
              return;
            }
            await _pickVideosForBulk(input);
          },
          variant: ButtonVariant.primary,
          size: ButtonSize.medium,
          expanded: true,
        ),
      ],
    );
  }

  /// Build the mode switch between Single Image and Bulk Edit
  Widget _buildImageModeSwitch(
    ColorScheme cs,
    bool isVip,
    bool isBulkMode, {
    bool compact = false,
    bool iconOnly = false,
    VoidCallback? beforeLeaveBulk,
    VoidCallback? onEnterBulk,
  }) {
    final cap = isVip ? _maxBulkImagesVip : _maxBulkImagesNonVip;
    if (iconOnly) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Single image',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  if (isBulkMode) {
                    setState(() {
                      beforeLeaveBulk?.call();
                      _advancedSettings =
                          _advancedSettings.copyWith(bulkEditEnabled: false);
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: !isBulkMode ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    LucideIcons.image,
                    size: 16,
                    color: !isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Tooltip(
              message: 'Bulk batch (up to $cap tasks)',
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  if (!isBulkMode) {
                    setState(() {
                      onEnterBulk?.call();
                      _advancedSettings =
                          _advancedSettings.copyWith(bulkEditEnabled: true);
                    });
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isBulkMode ? cs.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    LucideIcons.layers,
                    size: 16,
                    color: isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final vPad = compact ? 6.0 : 10.0;
    final iconSize = compact ? 14.0 : 16.0;
    final titleSize = compact ? 11.5 : 13.0;
    final capSize = compact ? 10.0 : 11.0;
    final innerRadius = compact ? 8.0 : 10.0;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Single Image option
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (isBulkMode) {
                  setState(() {
                    beforeLeaveBulk?.call();
                    _advancedSettings =
                        _advancedSettings.copyWith(bulkEditEnabled: false);
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: vPad),
                decoration: BoxDecoration(
                  color: !isBulkMode ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(innerRadius),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.image,
                      size: iconSize,
                      color: !isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                    SizedBox(width: compact ? 4 : 6),
                    Text(
                      'Single',
                      style: TextStyle(
                        color: !isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: titleSize,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bulk Edit option
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isBulkMode) {
                  setState(() {
                    onEnterBulk?.call();
                    _advancedSettings =
                        _advancedSettings.copyWith(bulkEditEnabled: true);
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: vPad),
                decoration: BoxDecoration(
                  color: isBulkMode ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(innerRadius),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.layers,
                      size: iconSize,
                      color: isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                    SizedBox(width: compact ? 4 : 6),
                    Text(
                      'Bulk',
                      style: TextStyle(
                        color: isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: titleSize,
                      ),
                    ),
                    SizedBox(width: compact ? 2 : 4),
                    Text(
                      '(${isVip ? _maxBulkImagesVip : _maxBulkImagesNonVip})',
                      style: TextStyle(
                        color: isBulkMode
                            ? cs.onPrimary.withValues(alpha: 0.9)
                            : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: capSize,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the bulk images content (replaces single image upload when bulk mode enabled)
  Widget _buildBulkImagesContent(ColorScheme cs) {
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());
    final totalJobs = !_hasBulkInput ? 0 : _bulkImageJobs.length * variations;
    final bool exceedsLimit = totalJobs > _maxTotalJobs;

    // Calculate max images allowed based on current variations
    final int maxImagesForVariations = (_maxTotalJobs / variations).floor();
    final int effectiveMaxImages =
        maxImagesForVariations.clamp(1, _maxBulkImages);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Info bar showing count and jobs
        if (_hasBulkInput) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: exceedsLimit
                  ? cs.errorContainer.withValues(alpha: 0.3)
                  : cs.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: exceedsLimit
                    ? cs.error.withValues(alpha: 0.3)
                    : cs.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  exceedsLimit ? LucideIcons.alertTriangle : LucideIcons.info,
                  size: 16,
                  color: exceedsLimit ? cs.error : cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _bulkSupportsMultiInitPerJob
                            ? '${_bulkImageJobs.length} tasks × $variations variations = $totalJobs jobs'
                            : '${_bulkImageJobs.length} images × $variations variations = $totalJobs jobs',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (exceedsLimit)
                        Text(
                          'Max $_maxTotalJobs jobs allowed. Reduce images or variations.',
                          style: TextStyle(
                            color: cs.error,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _clearBulkImages,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(LucideIcons.trash2, size: 14, color: cs.error),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Images grid or empty state
        if (!_hasBulkInput)
          _buildBulkEmptyState(cs)
        else
          _buildBulkImagesGrid(cs),

        const SizedBox(height: 12),

        // Add images button (limit based on variations)
        GradientButton(
          icon: !_hasBulkInput ? LucideIcons.imagePlus : LucideIcons.plus,
          label: !_hasBulkInput
              ? (_bulkSupportsMultiInitPerJob
                  ? 'Select images'
                  : 'Select Images')
              : (_bulkSupportsMultiInitPerJob
                  ? 'Add more references (${_remainingBulkImagePickSlots()} left)'
                  : 'Add More (${_bulkImageJobs.length}/$effectiveMaxImages)'),
          onPressed: (_bulkSupportsMultiInitPerJob
                  ? _remainingBulkImagePickSlots() <= 0
                  : _bulkImageJobs.length >= effectiveMaxImages)
              ? null
              : _pickBulkImages,
          variant:
              !_hasBulkInput ? ButtonVariant.primary : ButtonVariant.secondary,
          size: ButtonSize.medium,
          expanded: true,
        ),
      ],
    );
  }

  /// Build empty state for bulk images
  Widget _buildBulkEmptyState(ColorScheme cs) {
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());
    final int maxImagesForVariations = (_maxTotalJobs / variations).floor();
    final int effectiveMaxImages =
        maxImagesForVariations.clamp(1, _maxBulkImages);

    // Hint for tools that need per-image configuration
    String? extraHint;
    if (_requiresMask) {
      extraHint = 'You\'ll draw a mask for each image';
    } else if (_isOutpaint) {
      extraHint = 'You\'ll set placement for each image';
    }

    return Container(
      height: extraHint != null ? 200 : 180,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.surfaceContainerHigh.withValues(alpha: 0.8),
            cs.surfaceContainerHighest.withValues(alpha: 0.4),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                cs.primary.withValues(alpha: 0.2),
                cs.tertiary.withValues(alpha: 0.1)
              ]),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.layers, size: 32, color: cs.primary),
          ),
          const SizedBox(height: 12),
          Text(
            _bulkSupportsMultiInitPerJob
                ? 'Bulk tasks with multiple references'
                : 'Select multiple images',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _bulkSupportsMultiInitPerJob
                ? 'Up to $_bulkMaxInitPerJob images per task (e.g. combine references). Max $effectiveMaxImages tasks × $variations var = ${effectiveMaxImages * variations} jobs.'
                : 'Up to $effectiveMaxImages images × $variations var = ${effectiveMaxImages * variations} jobs max',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          if (extraHint != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _requiresMask ? LucideIcons.paintbrush : LucideIcons.move,
                  size: 12,
                  color: cs.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  extraHint,
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Reusable action button - uses consistent button variants
  Widget _buildImagePreview(String ref) {
    final cs = Theme.of(context).colorScheme;
    final data = _inputs[ref];

    // Show loading state while processing
    if (_isProcessingImage) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.surfaceContainerHigh.withValues(alpha: 0.8),
              cs.surfaceContainerHighest.withValues(alpha: 0.4),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Processing image...",
              style: TextStyle(
                color: cs.primary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (data == null || (data is List && data.isEmpty)) {
      return Container(
        height: 220,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              cs.surfaceContainerHigh.withValues(alpha: 0.8),
              cs.surfaceContainerHighest.withValues(alpha: 0.4),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.imagePlus,
                color: cs.primary.withValues(alpha: 0.6),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "Tap to upload an image",
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Supports PNG, JPG, WEBP",
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    // unwrap
    final list =
        (data is List) ? List<Uint8List>.from(data) : [data as Uint8List];
    final mask = _inputs["mask_image"];

    final bool isOutpaint = _tool.model == "diffusers_outpaint";

    // Read outpaint config (from OutpaintCanvasPage)
    final String alignment =
        isOutpaint ? (_inputs["alignment"] ?? "Middle") : "Middle";
    final String ratioStr =
        isOutpaint ? (_inputs["aspect_ratio"] ?? "1:1") : "1:1";
    final bool isCustomMode = isOutpaint && (_inputs["is_custom"] == "true");
    final double customScale = isCustomMode
        ? (double.tryParse(_inputs["custom_scale"] ?? "0.7") ?? 0.7)
        : 1.0;
    final double normOffsetX =
        double.tryParse(_inputs["norm_offset_x"] ?? "0") ?? 0.0;
    final double normOffsetY =
        double.tryParse(_inputs["norm_offset_y"] ?? "0") ?? 0.0;

    final ratioParts = ratioStr.split(":");
    final double aspectRatio = (ratioParts.length == 2)
        ? (double.tryParse(ratioParts[0]) ?? 1) /
            (double.tryParse(ratioParts[1]) ?? 1)
        : 1.0;

    // Check if this is a multi-image input
    final input = _effectiveInputConfig(ref);
    final maxImages = input["max"] ?? 1;
    final isMultiImage = maxImages > 1 && list.length > 1;

    // For multi-image inputs, show a grid of thumbnails
    if (isMultiImage) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.3),
            width: 2,
          ),
          color: cs.surfaceContainerHigh,
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with count
            Row(
              children: [
                Icon(LucideIcons.galleryVertical, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  '${list.length} images selected',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check,
                          size: 12, color: Colors.green.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Ready',
                        style: TextStyle(
                          color: Colors.green.shade600,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Image grid
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: list.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: EdgeInsets.only(
                        right: index < list.length - 1 ? 10 : 0),
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.primary.withValues(alpha: 0.3),
                              width: 1.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(11),
                            child: Image.memory(
                              list[index],
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // Image number badge
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    // Single image preview (original behavior)
    // Check if this tool requires a mask (inpaint/erase)
    final bool requiresMaskForTool = _requiresMask;
    final bool hasMask = mask != null;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasMask
              ? Colors.green.withValues(alpha: 0.5)
              : cs.primary.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: aspectRatio.clamp(0.5, 2.0),
          child: isOutpaint
              ? _buildOutpaintPreview(
                  list.first,
                  cs,
                  isCustomMode: isCustomMode,
                  customScale: customScale,
                  normOffsetX: normOffsetX,
                  normOffsetY: normOffsetY,
                  alignment: alignment,
                )
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: cs.surfaceContainerHigh),
                    Image.memory(
                      list.first,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                    // Mask overlay with red tint
                    if (hasMask)
                      Positioned.fill(
                        child: ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Color(0x66FF0000),
                            BlendMode.srcATop,
                          ),
                          child: Opacity(
                            opacity: 0.6,
                            child: Image.memory(mask as Uint8List,
                                fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    // Status badge (top right)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasMask
                                  ? LucideIcons.paintbrush
                                  : LucideIcons.check,
                              size: 14,
                              color: hasMask
                                  ? Colors.red.shade300
                                  : Colors.green.shade300,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              hasMask ? "Mask applied" : "Image ready",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Edit/Draw Mask button (bottom right) - only for inpaint tools
                    if (requiresMaskForTool)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: GestureDetector(
                          onTap: () async {
                            final base = list.first;
                            final newMask = await _openMaskEditor(base);
                            if (newMask != null && mounted) {
                              setState(() {
                                _inputs["mask_image"] = newMask;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: hasMask
                                  ? cs.surfaceContainerHigh
                                  : cs.primary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: hasMask
                                    ? cs.outline.withValues(alpha: 0.3)
                                    : cs.primary,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasMask
                                      ? LucideIcons.edit3
                                      : LucideIcons.paintbrush,
                                  size: 16,
                                  color: hasMask ? cs.onSurface : cs.onPrimary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  hasMask ? "Edit Mask" : "Draw Mask",
                                  style: TextStyle(
                                    color:
                                        hasMask ? cs.onSurface : cs.onPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Build outpaint preview with accurate positioning
  Widget _buildOutpaintPreview(
    Uint8List imageBytes,
    ColorScheme cs, {
    required bool isCustomMode,
    required double customScale,
    required double normOffsetX,
    required double normOffsetY,
    required String alignment,
    bool compact = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxSize = constraints.biggest;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Checker background
            const CustomPaint(painter: _CheckerPainter()),

            // Image with accurate positioning
            if (isCustomMode)
              // Custom mode: use scale and offset
              Center(
                child: Transform.translate(
                  offset: Offset(
                    normOffsetX * (boxSize.width / 2),
                    normOffsetY * (boxSize.height / 2),
                  ),
                  child: Transform.scale(
                    scale: customScale,
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              )
            else
              // Fixed aspect mode: use normalized offset for accurate position
              Center(
                child: Transform.translate(
                  offset: Offset(
                    normOffsetX * (boxSize.width * 0.15),
                    normOffsetY * (boxSize.height * 0.15),
                  ),
                  child: Padding(
                    padding: _getOutpaintPadding(alignment),
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),

            // Expansion direction indicator
            if (!compact) _buildExpansionIndicator(alignment, cs),

            // Image ready indicator
            if (!compact)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.check,
                        size: 14,
                        color: Colors.green.shade300,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isCustomMode ? "Custom" : alignment,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Positioned(
                right: 4,
                top: 4,
                child: Icon(
                  LucideIcons.check,
                  size: 14,
                  color: Colors.green.shade300,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 4),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  EdgeInsets _getOutpaintPadding(String alignment) {
    const double pad = 40;
    switch (alignment) {
      case "Left":
        return const EdgeInsets.only(right: pad);
      case "Right":
        return const EdgeInsets.only(left: pad);
      case "Top":
        return const EdgeInsets.only(bottom: pad);
      case "Bottom":
        return const EdgeInsets.only(top: pad);
      case "All Sides":
        return const EdgeInsets.all(pad * 0.5);
      default:
        return EdgeInsets.zero;
    }
  }

  Widget _buildExpansionIndicator(String alignment, ColorScheme cs) {
    if (alignment == "Middle") return const SizedBox();

    IconData icon;
    Alignment position;

    switch (alignment) {
      case "Left":
        icon = LucideIcons.arrowRight;
        position = Alignment.centerRight;
        break;
      case "Right":
        icon = LucideIcons.arrowLeft;
        position = Alignment.centerLeft;
        break;
      case "Top":
        icon = LucideIcons.arrowDown;
        position = Alignment.bottomCenter;
        break;
      case "Bottom":
        icon = LucideIcons.arrowUp;
        position = Alignment.topCenter;
        break;
      case "All Sides":
        icon = LucideIcons.expand;
        position = Alignment.center;
        break;
      default:
        return const SizedBox();
    }

    return Align(
      alignment: position,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.8),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: cs.onPrimary),
        ),
      ),
    );
  }

  // -------- Slider --------
  Widget _buildSlider(String ref, {StateSetter? sheetSetter}) {
    final cs = Theme.of(context).colorScheme;
    final input = _tool.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    if (!_elementShouldRender(Map<String, dynamic>.from(input))) {
      return const SizedBox.shrink();
    }

    final label = input["label"] ?? ref;
    _inputs[ref] ??= input["default"] ?? input["min"] ?? 1.0;
    final minVal = (input["min"] as num?)?.toDouble() ?? 0;
    final maxVal = (input["max"] as num?)?.toDouble() ?? 100;
    final step = (input["step"] as num?)?.toDouble();
    final raw = _inputs[ref];
    var currentVal =
        raw is num ? raw.toDouble() : double.tryParse('$raw') ?? minVal;
    currentVal = currentVal.clamp(minVal, maxVal);
    String formatValue(double value) {
      if (ref == 'duration' || ref == 'suno_length') {
        return _musicLengthLabel(value.round());
      }
      if (ref == 'strength') return value.toStringAsFixed(2);
      if (ref == 'repaint_start' || ref == 'repaint_end') {
        return '${value.round()} sec';
      }
      return value.toStringAsFixed(value % 1 == 0 ? 0 : 1);
    }

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Text(
                formatValue(currentVal),
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (input['description'] is String &&
              (input['description'] as String).isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              input['description'] as String,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                fontSize: 11.5,
              ),
            ),
          ],
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.outlineVariant.withValues(alpha: 0.25),
              thumbColor: cs.primary,
              overlayColor: cs.primary.withValues(alpha: 0.12),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(
              value: currentVal.clamp(minVal, maxVal),
              min: minVal,
              max: maxVal,
              divisions: step != null && step > 0
                  ? ((maxVal - minVal) / step).round().clamp(1, 240)
                  : ((maxVal - minVal) * 10).round().clamp(1, 100),
              onChanged: (v) {
                final snapped = step != null && step > 0
                    ? minVal + ((v - minVal) / step).round() * step
                    : v;
                final stored = ref == 'duration' ||
                        ref == 'suno_length' ||
                        ref == 'repaint_start' ||
                        ref == 'repaint_end'
                    ? snapped.round()
                    : snapped;
                void apply() => _inputs[ref] = stored;
                if (sheetSetter != null) {
                  sheetSetter(() => setState(apply));
                } else {
                  setState(apply);
                }
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  formatValue(minVal),
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  formatValue(maxVal),
                  style: TextStyle(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------- Toggle (Switch) --------
  Widget _buildToggle(String ref, {StateSetter? sheetSetter}) {
    final cs = Theme.of(context).colorScheme;
    final input = _tool.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    final label = input["label"] ?? ref;
    final description = input["description"] as String?;
    final showForModels = input["showForModels"] as List<dynamic>?;

    // Check if toggle should be shown for current model
    if (showForModels != null && showForModels.isNotEmpty) {
      final currentModel = _selectedModelId ?? _tool.model;
      if (!showForModels.contains(currentModel)) {
        return const SizedBox.shrink();
      }
    }

    // Check showWhen condition
    final showWhen = input["showWhen"] as Map<String, dynamic>?;
    if (showWhen != null) {
      final conditionKey = showWhen.keys.first;
      final conditionValue = showWhen[conditionKey];
      final actualValue = _inputs[conditionKey];
      if (actualValue != conditionValue) {
        return const SizedBox.shrink();
      }
    }

    // Initialize with default value
    _inputs[ref] ??= input["default"] ?? false;
    final isEnabled = _inputs[ref] == true;

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Transform.scale(
            scale: 0.9,
            child: Switch.adaptive(
              value: isEnabled,
              onChanged: (v) {
                void apply() {
                  _inputs[ref] = v;
                  if (ref == 'vocals' && _isMusicTool) {
                    _keepLyricsAcrossVocals(v);
                  }
                }
                if (sheetSetter != null) {
                  sheetSetter(() => setState(apply));
                } else {
                  setState(apply);
                }
              },
              activeColor: cs.primary,
            ),
          ),
        ],
      ),
    );
  }

  // -------- Dropdown (ChoiceChips) --------
  Widget _buildDropdown(String ref, {StateSetter? sheetSetter}) {
    final cs = Theme.of(context).colorScheme;
    final input = _tool.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input["label"] ?? ref;
    final options = _choiceOptions(Map<String, dynamic>.from(input));
    if (options.isNotEmpty &&
        !options.any((o) => o.value == _inputs[ref]?.toString())) {
      _inputs[ref] = options.first.value;
    }

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final isSelected = _inputs[ref]?.toString() == opt.value;
              return InkWell(
                onTap: () {
                  void apply() => _inputs[ref] = opt.value;
                  if (sheetSetter != null) {
                    sheetSetter(() => setState(apply));
                  } else {
                    setState(apply);
                  }
                },
                borderRadius: BorderRadius.circular(AppStyles.radiusFull),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(colors: KalaColors.brandGradient)
                        : null,
                    color: isSelected
                        ? null
                        : cs.surfaceContainerHigh.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(AppStyles.radiusFull),
                    border: Border.all(
                      color: isSelected
                          ? Colors.transparent
                          : cs.outlineVariant.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSelected) ...[
                        const Icon(LucideIcons.check,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        opt.label,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : cs.onSurfaceVariant.withValues(alpha: 0.9),
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPainter(String ref) {
    // Mask region section is removed - mask editing is now integrated into image preview
    // Return empty widget as mask functionality moved to _buildImagePreview
    return const SizedBox.shrink();
  }

  void _seedCineRealFlf2vBulkFromInputs() {
    final a = _bytesForInputKey('init_image');
    final b = _bytesForInputKey('last_frame_image');
    if (a != null && b != null) {
      _bulkImageJobs
        ..clear()
        ..add([a, b]);
    } else {
      _bulkImageJobs.clear();
    }
  }

  void _syncCineRealSingleFromFirstBulkRow() {
    if (_bulkImageJobs.isEmpty) return;
    final job = _bulkImageJobs.first;
    if (job.length == 2 && job[0].isNotEmpty && job[1].isNotEmpty) {
      _inputs['init_image'] = job[0];
      _inputs['last_frame_image'] = job[1];
    }
  }

  Uint8List? _bytesForInputKey(String key) {
    final v = _inputs[key];
    if (v == null) return null;
    if (v is Uint8List) return v.isEmpty ? null : v;
    if (v is List && v.isNotEmpty && v.first is Uint8List) {
      final u = v.first as Uint8List;
      return u.isEmpty ? null : u;
    }
    return null;
  }

  Widget _buildDynamicInputScreen() {
    final cs = Theme.of(context).colorScheme;
    // Get safe area padding for devices with home bar/navigation buttons
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;

    // Filter elements: generate_button is rendered in the sticky footer;
    // the `prompt` element is rendered at the top as a composer card.
    final contentElements =
        _currentElements.where((e) => e["type"] != "generate_button").toList();
    Map<String, dynamic>? promptElement;
    for (final e in contentElements) {
      if (e['type'] == 'prompt') {
        promptElement = e;
        break;
      }
    }
    // Hide upload-type elements from the main scroll entirely. Both single
    // mode and bulk mode are now handled inline in the composer (picker is
    // opened via the composer's + button; inline chips show the attachments
    // and expose per-task actions like mask / outpaint / add-refs / remove).
    bool isUploadCardHidden(Map<String, dynamic> e) {
      final t = e['type'];
      return t == 'image_upload' ||
          t == 'video_upload' ||
          t == 'audio_upload' ||
          t == 'file_upload';
    }

    const speechLeadRefs = {
      'voice',
      'language',
      'voice_description',
      'design_language',
      'reference_audio',
      'clone_language',
    };
    final afterPromptElements = contentElements.where((e) {
      if (e['type'] == 'prompt' || isUploadCardHidden(e)) return false;
      if (_isSpeechTool && speechLeadRefs.contains(e['input_ref'])) {
        return false;
      }
      if (_isMusicTool &&
          (e['input_ref'] == 'lyrics' || e['input_ref'] == 'negative_prompt')) {
        return false;
      }
      return true;
    }).toList();
    final bool hasPromptElement = promptElement != null;
    final attachInputsStandalone = _attachableInputs();
    final bool showStandaloneMediaComposer =
        !hasPromptElement && attachInputsStandalone.isNotEmpty;

    // Track which element types have already received a shortcut GlobalKey so
    // we only attach it to the first occurrence of each type (groups collapse
    // onto the first widget of that kind).
    final attachedKeys = <String>{};

    Widget renderElement(Map<String, dynamic> e) {
      final type = e['type'] as String?;
      GlobalKey? sectionKey;
      if (type != null && !attachedKeys.contains(type)) {
        switch (type) {
          case 'image_upload':
            sectionKey = _imageUploadKey;
            break;
          case 'video_upload':
            sectionKey = _videoUploadKey;
            break;
          case 'audio_upload':
            sectionKey = _audioUploadKey;
            break;
          case 'file_upload':
            sectionKey = _fileUploadKey;
            break;
          case 'text_input':
            sectionKey = _textInputKey;
            break;
          case 'number_input':
          case 'seed_input':
            sectionKey = _numericKey;
            break;
          case 'slider':
            sectionKey = _slidersKey;
            break;
          case 'range_slider':
            sectionKey = _rangeSliderKey;
            break;
          case 'dropdown':
            sectionKey = _dropdownsKey;
            break;
          case 'toggle':
            sectionKey = _togglesKey;
            break;
          case 'aspect_ratio':
            sectionKey = _aspectRatioKey;
            break;
          case 'color_picker':
            sectionKey = _colorPickerKey;
            break;
          case 'multi_select':
            sectionKey = _multiSelectKey;
            break;
        }
        if (sectionKey != null) {
          attachedKeys.add(type);
        }
      }

      final child = _buildElement(e);
      final pulse =
          _pulseSectionId != null && _sectionIdMatches(_pulseSectionId!, type);
      final wrapped = AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
          border: Border.all(
            color: pulse ? cs.primary.withValues(alpha: 0.55) : Colors.transparent,
            width: pulse ? 1.5 : 0,
          ),
        ),
        child: child,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: sectionKey != null
            ? KeyedSubtree(key: sectionKey, child: wrapped)
            : wrapped,
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.surface,
            cs.surfaceContainerLowest,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          // Scrollable content area
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                top: 4,
                bottom: 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Mode selector (self-contained pill)
                  if (_tool.modes != null &&
                      _tool.modes!.isNotEmpty)
                    KeyedSubtree(
                      key: _modeSectionKey,
                      child: _buildModeSelector(),
                    ),
                  if (_isSpeechTool) _buildSpeechModeBar(),
                  if (_isSpeechTool) _buildSpeechLeadFields(),
                  if (_isMusicTool && _sunoSongKind) _buildMusicModeBar(),
                  if (_isMusicTool && !_isSunoV6 && !_sunoSounds) _buildMusicModeBar(),
                  if (_isSunoV6) _buildHitMakerKindBar(),
                  if (_sunoExtend || _sunoMashup) _buildHitMakerExtendMashup(),
                  if (_isMusicTool &&
                      !_musicEasy &&
                      !_sunoSounds &&
                      !_sunoExtend &&
                      !_sunoMashup) ...[
                    _buildMusicBoundField('lyrics'),
                    _buildMusicComposerField(
                      label: _isSunoV6 ? 'Style of Music' : 'Prompt',
                      hint: _isSunoV6
                          ? 'Genre, mood, and instruments'
                          : _isKalaSongPro
                              ? 'Key, tempo, instruments, and how it should feel'
                              : 'Style, instruments, mood, and how the song moves',
                      controller:
                          _isSunoV6 ? _sunoStyleController : _promptController,
                      showSettings: true,
                    ),
                    if (_isSunoV6)
                      _buildMusicComposerField(
                        label: 'Avoid',
                        hint: 'Styles or traits to leave out',
                        inputId: 'negative_prompt',
                        minLines: 3,
                      )
                    else
                      _buildMusicBoundField('negative_prompt'),
                  ],

                  if (_sunoSongKind && _musicEasy)
                    _buildHitMakerEasyComposer()
                  else if (hasPromptElement &&
                      !_sunoExtend &&
                      !_sunoMashup &&
                      !(_isMusicTool && !_musicEasy && !_sunoSounds))
                    _buildElement(promptElement),
                  if (_isMusicTool && _musicUsesAudio)
                    _buildAudioUpload('source_audio'),

                  // 2b. Media-only composer (hidden upload cards + no prompt — upscale, OCR, etc.)
                  if (showStandaloneMediaComposer)
                    _buildStandaloneMediaComposer(),

                  if ((hasPromptElement || showStandaloneMediaComposer) &&
                      !_isMusicTool)
                    _buildSectionShortcutBar(contentElements),

                  // 5. Rest of the dynamic elements (no prompt, no generate_button)
                  ...afterPromptElements.map(renderElement),

                  // 6. Relocated Style & Tags panel — only when a prompt exists.
                  if (hasPromptElement &&
                      _promptStylesVisible &&
                      !_isAudioTool &&
                      !_hidesStyleAndTags) ...[
                    const SizedBox(height: 10),
                    KeyedSubtree(
                      key: _stylesSectionKey,
                      child: _buildPromptEnhancerSection(cs),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Sticky bottom area with settings + generate button (unchanged logic)
          _buildStickyGenerateFooter(bottomSafeArea),
        ],
      ),
    );
  }

  /// Helper used by `_buildDynamicInputScreen` to decide whether the most
  /// recently targeted shortcut pulse matches an element `type`. It honors the
  /// fact that `number_input` and `seed_input` share a single pulse id
  /// (`numeric`).
  bool _sectionIdMatches(String pulseId, String? type) {
    if (type == null) return false;
    switch (pulseId) {
      case 'image':
        return type == 'image_upload';
      case 'video':
        return type == 'video_upload';
      case 'audio':
        return type == 'audio_upload';
      case 'file':
        return type == 'file_upload';
      case 'text':
        return type == 'text_input';
      case 'sliders':
        return type == 'slider';
      case 'range':
        return type == 'range_slider';
      case 'numeric':
        return type == 'number_input' || type == 'seed_input';
      case 'dropdowns':
        return type == 'dropdown';
      case 'toggles':
        return type == 'toggle';
      case 'ratio':
        return type == 'aspect_ratio';
      case 'color':
        return type == 'color_picker';
      case 'multi':
        return type == 'multi_select';
      default:
        return false;
    }
  }

  /// Build the sticky footer with settings and generate button
  Widget _buildStickyGenerateFooter(double bottomSafeArea) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = _areRequiredInputsFilled() && !_musicExpanding;
    final missingInputs = _getMissingInputs();

    return Container(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 10,
        bottom: 10 + bottomSafeArea,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isMusicTool && !_sunoSounds) ...[
            _buildMusicModeLink(),
            const SizedBox(height: 6),
          ],
          // Status hint (shown when button is disabled)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: !isEnabled && missingInputs.isNotEmpty
                ? Builder(
                    builder: (context) {
                      // Check if this is a rate limit message (contains ⏳)
                      final isRateLimitHint = missingInputs.first.contains('⏳');
                      final isProcessing = _isProcessingImage;

                      // Choose colors based on hint type
                      final Color bgColor;
                      final Color borderColor;
                      final Color textColor;
                      final IconData hintIcon;

                      if (isProcessing) {
                        bgColor = cs.primaryContainer.withValues(alpha: 0.3);
                        borderColor = cs.primary.withValues(alpha: 0.2);
                        textColor = cs.primary.withValues(alpha: 0.9);
                        hintIcon = LucideIcons.loader;
                      } else if (isRateLimitHint) {
                        // Rate limit - use amber/orange for "busy" feeling
                        bgColor = Colors.amber.withValues(alpha: 0.15);
                        borderColor = Colors.amber.withValues(alpha: 0.3);
                        textColor = Colors.amber.shade800;
                        hintIcon = LucideIcons.sparkles;
                      } else {
                        // Missing input - use subtle red
                        bgColor = cs.errorContainer.withValues(alpha: 0.3);
                        borderColor = cs.error.withValues(alpha: 0.2);
                        textColor = cs.error.withValues(alpha: 0.9);
                        hintIcon = LucideIcons.alertCircle;
                      }

                      // Format message for display
                      final String displayMessage;
                      if (isProcessing) {
                        displayMessage = "Processing image...";
                      } else if (isRateLimitHint) {
                        // Remove emoji and show cleaner message
                        displayMessage =
                            missingInputs.first.replaceAll('⏳ ', '');
                      } else {
                        displayMessage =
                            "Add ${missingInputs.join(' & ')} to continue";
                      }

                      // Calculate jobs for rate limit sheet
                      final variations = _advancedSettings.variations
                          .clamp(1, getMaxVariations());
                      final int imageCount =
                          _advancedSettings.bulkEditEnabled && _hasBulkInput
                              ? _bulkActiveMediaCount
                              : 1;
                      final int totalJobsToSubmit = imageCount * variations;

                      return GestureDetector(
                        onTap: isRateLimitHint
                            ? () =>
                                _showRateLimitErrorSheet('', totalJobsToSubmit)
                            : null,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: borderColor,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isProcessing)
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.primary.withValues(alpha: 0.8),
                                  ),
                                )
                              else
                                Icon(
                                  hintIcon,
                                  size: 14,
                                  color: textColor,
                                ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  displayMessage,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              // Add "tap for details" indicator for rate limit hints
                              if (isRateLimitHint) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  LucideIcons.chevronRight,
                                  size: 14,
                                  color: textColor.withValues(alpha: 0.6),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
          ),

          // Settings summary row (model + upscale indicator)
          if (_showAdvancedControls) _buildSettingsSummary(cs),

          // Settings button + Generate button row
          Row(
            children: [
              if (_showAdvancedControls) ...[
                Tooltip(
                  message: 'Additional Settings',
                  child: InkWell(
                  onTap: _showAdvancedSettings,
                  borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Icon(
                      LucideIcons.settings,
                      size: 20,
                      color: cs.onSurfaceVariant,
                      semanticLabel: 'Additional Settings',
                    ),
                  ),
                ),
                ),
                const SizedBox(width: 10),
              ],
              // Generate button with glow
              Expanded(
                child: _buildAnimatedGenerateButton(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build settings summary showing model name and upscale status
  Widget _buildSettingsSummary(ColorScheme cs) {
    // Get model name
    final modelName = _selectedModelData?['name'] as String? ??
        _tool.models?.firstWhere(
          (m) => m['id'] == _tool.model,
          orElse: () => {'name': _tool.model},
        )['name'] as String? ??
        _tool.model;

    // Check upscale status
    final isUpscaled = _isVideoUpscalerTool
        ? true
        : (_isVideoTool
            ? _advancedSettings.enableUpscale
            : _advancedSettings.upscaleOutput);
    final scaleFactor = (_isVideoUpscalerTool || _isVideoTool)
        ? _advancedSettings.upscaleFactor
        : _scaleFactor;
    final variations = _advancedSettings.variations;
    final hideVideoEnhancementSummaryChips = _isVideoTool &&
        !_isVideoUpscalerTool &&
        _combinedVideoEnhancementSwitchIsOn;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: _showAdvancedSettings,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.info,
                size: 14,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildSummaryChip(
                      cs,
                      icon: LucideIcons.cpu,
                      label: _isSpeechTool ? _speechSettingsSummary() : modelName,
                      highlight: true,
                    ),
                    // Upscale status chip (skip when combined video enhancement is on; subtitle covers it)
                    if (!hideVideoEnhancementSummaryChips && !_isAudioTool)
                      _buildSummaryChip(
                        cs,
                        icon: isUpscaled
                            ? LucideIcons.maximize2
                            : LucideIcons.minimize2,
                        label: isUpscaled
                            ? '${scaleFactor}x Upscale'
                            : 'No Upscale',
                        highlight: isUpscaled,
                        isPositive: isUpscaled,
                      ),
                    // Frame interpolation chip (for video tools)
                    if (_isVideoTool &&
                        _advancedSettings.enableInterpolate &&
                        !hideVideoEnhancementSummaryChips)
                      _buildSummaryChip(
                        cs,
                        icon: LucideIcons.zap,
                        label:
                            '${migrateLegacyInterpolateStorageValue(_advancedSettings.interpolateFps)}× FPS ',
                        highlight: true,
                      ),
                    // Variations (if > 1)
                    if (variations > 1)
                      _buildSummaryChip(
                        cs,
                        icon: LucideIcons.copy,
                        label: '${variations}x Variants',
                        highlight: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a small chip for settings summary
  Widget _buildSummaryChip(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    bool highlight = false,
    bool isPositive = true,
  }) {
    final chipColor = highlight
        ? (isPositive ? cs.primary : cs.tertiary)
        : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: highlight
            ? chipColor.withValues(alpha: 0.1)
            : cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight
              ? chipColor.withValues(alpha: 0.2)
              : cs.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: chipColor.withValues(alpha: highlight ? 1.0 : 0.6),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: chipColor.withValues(alpha: highlight ? 0.9 : 0.7),
              fontSize: 11,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build the animated generate button with glow effect
  Widget _buildAnimatedGenerateButton() {
    final cs = Theme.of(context).colorScheme;
    final offer = _currentModelOffer;
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());

    // VIP benefits
    final int imageCount = _advancedSettings.bulkEditEnabled && _hasBulkInput
        ? _bulkActiveMediaCount
        : 1;

    // Total jobs = images × variations
    final int totalJobs = imageCount * variations;

    // Use the unified cost calculation that includes variations
    final totalCost = _calculateTotalCost();

    // Calculate cost before discount (for showing strikethrough if offer or VIP free upscale)
    int totalBeforeDiscount;
    if (_isVideoUpscalerTool) {
      totalBeforeDiscount = _videoUpscalerUndiscountedCreditsTotal();
    } else if (_tool.outputType == 'video' && !_isVideoUpscalerTool) {
      final baseCostPerVariation =
          _getDurationBasedCost() + _enhancementUpscaleCreditsPerVariation();
      totalBeforeDiscount = baseCostPerVariation * variations * imageCount;
    } else {
      final baseCostPerVariation = _listedGenerationCost() +
          _enhancementUpscaleCreditsPerVariation() +
          _inputScaleUpscaleCreditsPerVariation();
      totalBeforeDiscount = baseCostPerVariation * variations * imageCount;
    }

    // Check if button should be enabled
    final isEnabled = _areRequiredInputsFilled() && !_musicExpanding;

    // Check if we have multiple images or variations (show compact summary)
    final bool showJobCount = totalJobs > 1;

    return AnimatedBuilder(
      animation: _glowAnimationController,
      builder: (context, child) {
        final glowOpacity =
            isEnabled ? 0.3 + (_glowAnimationController.value * 0.2) : 0.0;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: KalaColors.purple.withValues(alpha: glowOpacity),
                      blurRadius: 16 + (_glowAnimationController.value * 8),
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: KalaColors.cyan.withValues(alpha: glowOpacity * 0.6),
                      blurRadius: 20 + (_glowAnimationController.value * 10),
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Opacity(
            opacity: isEnabled ? 1.0 : 0.6,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: isEnabled
                      ? KalaColors.brandGradient
                      : [
                          cs.onSurfaceVariant.withValues(alpha: 0.4),
                          cs.onSurfaceVariant.withValues(alpha: 0.3)
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isEnabled
                      ? _handleGenerateTap
                      : () {
                          // When disabled, check if it's due to rate limit and show the sheet
                          final rateLimitError =
                              checkRateLimitForSubmission(totalJobs);
                          if (rateLimitError != null) {
                            _showRateLimitErrorSheet(rateLimitError, totalJobs);
                          }
                        },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Sparkles icon
                        const Icon(
                          LucideIcons.sparkles,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        // Generate text
                        Text(
                          _musicExpanding ? "Writing the song" : "Generate",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),

                        // Divider
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          height: 20,
                          width: 1,
                          color: Colors.white.withValues(alpha: 0.3),
                        ),

                        // Compact job count badge (when multiple jobs)
                        if (showJobCount) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "${totalJobs}x",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],

                        // Cost display (compact)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.gem,
                              size: 14,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            const SizedBox(width: 3),
                            if (offer > 0 &&
                                totalBeforeDiscount > totalCost) ...[
                              Text(
                                "$totalBeforeDiscount",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor:
                                      Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                              const SizedBox(width: 2),
                            ],
                            Text(
                              "$totalCost",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (offer > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "-$offer%",
                                  style: const TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Handle generate tap with haptic feedback
  void _handleGenerateTap() async {
    // Trigger haptic feedback
    HapticFeedback.mediumImpact();

    // Check if bulk mode is enabled - show confirmation dialog
    final isBulkMode = _advancedSettings.bulkEditEnabled && _hasBulkInput;
    if (isBulkMode) {
      final confirmed = await _showBulkConfirmationDialog();
      if (!confirmed) return; // User cancelled
    }

    // Call the actual job runner
    _runJob();
  }

  /// Show confirmation dialog for bulk mode with job details
  Future<bool> _showBulkConfirmationDialog() async {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Gather job information
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());
    final imageCount = _bulkActiveMediaCount;
    final totalJobs = imageCount * variations;
    final totalCost = _calculateTotalCost();
    final freeUpscale = isUpscaleFree();
    final bulkVideoConfirm =
        _supportsBulkVideoEdit && _bulkVideoPaths.isNotEmpty;
    final showEnhancementConfirm = _videoGenEnhancementEnabled ||
        _isVideoUpscalerTool ||
        (_advancedSettings.upscaleOutput && _scaleFactor > 1);

    // Get model name
    final modelName = _selectedModelData?['name'] as String? ??
        _tool.models?.firstWhere(
          (m) => m['id'] == _tool.model,
          orElse: () => {'name': _tool.title},
        )['name'] as String? ??
        _tool.title;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            // Account for both keyboard (viewInsets) and system nav bar (viewPadding)
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).viewPadding.bottom +
                20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Header with icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      KalaColors.purple.withValues(alpha: 0.2),
                      KalaColors.cyan.withValues(alpha: 0.2),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.layers,
                  size: 32,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Confirm Bulk Generation',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You\'re about to generate multiple results',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 24),

              // Job details card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.outline.withValues(alpha: 0.1),
                  ),
                ),
                child: Column(
                  children: [
                    // Tool name
                    _buildConfirmDetailRow(
                      cs,
                      icon: LucideIcons.sparkles,
                      label: 'Tool',
                      value: _tool.title,
                      iconColor: KalaColors.purple,
                    ),
                    const SizedBox(height: 12),

                    // Model
                    _buildConfirmDetailRow(
                      cs,
                      icon: LucideIcons.cpu,
                      label: 'Model',
                      value: modelName,
                      iconColor: KalaColors.cyan,
                    ),
                    const SizedBox(height: 12),

                    // Images / videos (bulk)
                    _buildConfirmDetailRow(
                      cs,
                      icon: bulkVideoConfirm
                          ? LucideIcons.video
                          : LucideIcons.image,
                      label: bulkVideoConfirm ? 'Videos' : 'Images',
                      value: bulkVideoConfirm
                          ? '$imageCount video${imageCount > 1 ? 's' : ''}'
                          : '$imageCount image${imageCount > 1 ? 's' : ''}',
                      iconColor: Colors.blue,
                    ),
                    const SizedBox(height: 12),

                    // Variations
                    _buildConfirmDetailRow(
                      cs,
                      icon: LucideIcons.copy,
                      label: 'Variations',
                      value: bulkVideoConfirm
                          ? '$variations per video'
                          : '$variations per image',
                      iconColor: Colors.orange,
                    ),
                    // Duration (video tools only: upscaler = input video duration, image/text-to-video = selected duration)
                    if (_isVideoTool) ...[
                      const SizedBox(height: 12),
                      _buildConfirmDetailRow(
                        cs,
                        icon: LucideIcons.clock,
                        label:
                            _isVideoUpscalerTool ? 'Input video' : 'Duration',
                        value: _isVideoUpscalerTool
                            ? (bulkVideoConfirm
                                ? 'Batch (${_bulkVideoPaths.length} files)'
                                : (_inputVideoDuration != null &&
                                        _inputVideoDuration!.inSeconds > 0
                                    ? _formatDuration(_inputVideoDuration!)
                                    : '—'))
                            : '${_advancedSettings.videoDuration}s',
                        iconColor: Colors.teal,
                      ),
                    ],
                    const SizedBox(height: 12),

                    // Enhancement / upscale
                    if (showEnhancementConfirm)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildConfirmDetailRow(
                          cs,
                          icon: LucideIcons.zap,
                          label: _videoGenEnhancementEnabled
                              ? 'Enhancement'
                              : 'Upscale',
                          value: _enhancementConfirmDetailValue(freeUpscale),
                          iconColor: Colors.green,
                          valueColor: freeUpscale ? Colors.green : null,
                        ),
                      ),

                    // Divider
                    Divider(color: cs.outline.withValues(alpha: 0.2)),
                    const SizedBox(height: 12),

                    // Total jobs
                    _buildConfirmDetailRow(
                      cs,
                      icon: LucideIcons.layoutGrid,
                      label: 'Total Jobs',
                      value: '$totalJobs',
                      iconColor: cs.primary,
                      isBold: true,
                    ),
                    // Cost breakup (video tools only)
                    if (_isVideoTool) ...[
                      const SizedBox(height: 12),
                      _buildVideoCostBreakup(
                          cs, totalCost, variations, imageCount, freeUpscale),
                    ],
                    const SizedBox(height: 12),

                    // Total cost
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            LucideIcons.gem,
                            size: 18,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Total Cost',
                          style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.withValues(alpha: 0.2),
                                Colors.orange.withValues(alpha: 0.2),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                LucideIcons.gem,
                                size: 16,
                                color: Colors.amber,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$totalCost',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Confirm button
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [KalaColors.purple, KalaColors.cyan],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: KalaColors.purple.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.pop(ctx, true),
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  LucideIcons.sparkles,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Generate',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return result ?? false;
  }

  String _enhancementConfirmDetailValue(bool freeUpscale) {
    if (_videoGenEnhancementEnabled) {
      final parts = <String>[];
      if (_advancedSettings.enableInterpolate) {
        parts.add(
          '${migrateLegacyInterpolateStorageValue(_advancedSettings.interpolateFps)}× interp.',
        );
      }
      if (_advancedSettings.enableUpscale) {
        parts.add('${_advancedSettings.upscaleFactor}x upscale');
      }
      final core = parts.isEmpty ? 'On' : parts.join(' · ');
      return '$core${freeUpscale ? ' (FREE VIP)' : ''}';
    }
    if (_isVideoUpscalerTool) {
      final interp = _advancedSettings.enableInterpolate
          ? ' · ${migrateLegacyInterpolateStorageValue(_advancedSettings.interpolateFps)}× interp.'
          : '';
      return '${_advancedSettings.upscaleFactor}x upscale$interp${freeUpscale ? ' (FREE VIP)' : ''}';
    }
    return '${_scaleFactor}x upscale${freeUpscale ? ' (FREE VIP)' : ''}';
  }

  /// Cost breakup for video tools only (image-to-video, text-to-video, video upscaler).
  /// Shows how duration/variations/images affect total cost.
  Widget _buildVideoCostBreakup(
    ColorScheme cs,
    int totalCost,
    int variations,
    int imageCount,
    bool freeUpscale,
  ) {
    final offer = _currentModelOffer;
    final smallStyle = TextStyle(
      color: cs.onSurface.withValues(alpha: 0.7),
      fontSize: 12,
    );
    final lineStyle = TextStyle(
      color: cs.onSurface.withValues(alpha: 0.85),
      fontSize: 13,
    );

    if (_isVideoUpscalerTool) {
      if (_inputVideoDuration == null || _inputVideoDuration!.inSeconds <= 0) {
        return Text('Cost based on input video length (per 5s)',
            style: smallStyle);
      }
      final baseCostPer5Sec = _currentModelCost;
      final units = (_inputVideoDuration!.inSeconds / 5).ceil().clamp(1, 10000);
      final subTotal = baseCostPer5Sec * units;
      final parts = <String>[
        '$units unit${units > 1 ? 's' : ''} × $baseCostPer5Sec = $subTotal'
      ];
      if (offer > 0) {
        parts.add(' (−$offer% offer) = $totalCost');
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cost breakup',
              style: smallStyle.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(parts.join(), style: lineStyle),
        ],
      );
    }

    // Image-to-video / text-to-video: duration → per variation, × variations × images
    final durationCost = _getDurationBasedCost();
    final extraEnhancement = _enhancementUpscaleCreditsPerVariation();
    final basePerVariation = durationCost + extraEnhancement;
    final costPerVariation = offer > 0
        ? _applyOfferDiscount(basePerVariation, offer)
        : basePerVariation;
    final vipEnhancementNote =
        freeUpscale && _videoGenEnhancementEnabled && extraEnhancement == 0
            ? ' · enhancement FREE VIP'
            : '';
    final enhancementFrag = extraEnhancement > 0
        ? ' + $extraEnhancement enhancement'
        : vipEnhancementNote;
    final lines = <Widget>[
      Text(
        '${_advancedSettings.videoDuration}s → $durationCost per variation'
        '$enhancementFrag'
        '${offer > 0 ? ' (−$offer% offer)' : ''} = $costPerVariation each',
        style: lineStyle,
      ),
      const SizedBox(height: 2),
      Text(
        '× $variations variation${variations > 1 ? 's' : ''} × $imageCount image${imageCount > 1 ? 's' : ''} = $totalCost credits',
        style: lineStyle,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cost breakup',
            style: smallStyle.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ...lines,
      ],
    );
  }

  /// Helper to build a detail row in the confirmation dialog
  Widget _buildConfirmDetailRow(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: cs.onSurface.withValues(alpha: 0.7),
            fontSize: 14,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? cs.onSurface,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            fontSize: isBold ? 16 : 14,
          ),
        ),
      ],
    );
  }

  BoxDecoration _composerCardDecoration(ColorScheme cs) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          cs.surfaceContainerHighest.withValues(alpha: 0.35),
          cs.surfaceContainerHigh.withValues(alpha: 0.18),
        ],
      ),
      borderRadius: BorderRadius.circular(AppStyles.radiusLg),
      border: Border.all(
        color: cs.outlineVariant.withValues(alpha: 0.22),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: KalaColors.purple.withValues(alpha: 0.06),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }

  /// Lyrics and Avoid use the same card as the song prompt, with their own label.
  Widget _buildMusicBoundField(String ref) {
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final label = input['label']?.toString().trim();
    final hint = input['placeholder']?.toString() ?? '';
    return _buildMusicComposerField(
      label: (label == null || label.isEmpty) ? ref : label,
      hint: hint,
      inputId: ref,
      minLines: _kComposerPromptMinLines,
    );
  }

  Widget _buildMusicComposerField({
    required String label,
    required String hint,
    TextEditingController? controller,
    String? inputId,
    int minLines = 6,
    bool showSettings = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final modelName = _selectedModelData?['name'] as String? ?? '';
    final current = controller?.text ?? (_inputs[inputId] as String? ?? '');
    final fieldStyle = TextStyle(
      color: cs.onSurface,
      fontSize: 15,
      height: 1.45,
    );
    InputDecoration fieldDecoration({
      required bool showClear,
      required VoidCallback onClear,
    }) {
      return InputDecoration(
        isCollapsed: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        hintText: hint,
        hintStyle: TextStyle(
          color: cs.onSurfaceVariant.withValues(alpha: 0.55),
          fontSize: 15,
          height: 1.45,
        ),
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        suffixIcon: _clearTextButton(visible: showClear, onPressed: onClear),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: _composerCardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (controller != null)
            TextField(
              controller: controller,
              minLines: minLines,
              maxLines: _kComposerPromptMaxLines,
              style: fieldStyle,
              decoration: fieldDecoration(
                showClear: controller.text.isNotEmpty,
                onClear: () {
                  final clearsPrompt =
                      !identical(controller, _sunoStyleController);
                  controller.clear();
                  if (clearsPrompt) {
                    _inputs['prompt'] = '';
                    _selectedStyle = null;
                  } else {
                    _inputs['style'] = '';
                  }
                  setState(() {});
                },
              ),
              onChanged: (value) {
                if (identical(controller, _sunoStyleController)) {
                  _inputs['style'] = value;
                } else {
                  _inputs['prompt'] = value;
                }
                setState(() {});
              },
            )
          else
            TextFormField(
              key: ValueKey('$inputId-${_promptFillTicks[inputId] ?? 0}'),
              initialValue: current,
              minLines: minLines,
              maxLines: _kComposerPromptMaxLines,
              style: fieldStyle,
              decoration: fieldDecoration(
                showClear: current.isNotEmpty,
                onClear: () {
                  if (inputId == null) return;
                  _clearBoundText(inputId);
                },
              ),
              onChanged: (value) {
                if (inputId == null) return;
                setState(() => _inputs[inputId] = value);
              },
            ),
          const SizedBox(height: 6),
          Container(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.15),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              _autoPromptButton(
                fieldRef: inputId ??
                    (identical(controller, _sunoStyleController)
                        ? 'style'
                        : 'prompt'),
                suggestField: _suggestFieldForRef(
                  inputId ??
                      (identical(controller, _sunoStyleController)
                          ? 'style'
                          : 'prompt'),
                ),
                currentText: current,
                apply: (value) {
                  if (controller != null) {
                    controller.value = TextEditingValue(
                      text: value,
                      selection:
                          TextSelection.collapsed(offset: value.length),
                    );
                    if (identical(controller, _sunoStyleController)) {
                      _inputs['style'] = value;
                    } else {
                      _inputs['prompt'] = value;
                    }
                  } else if (inputId != null) {
                    _inputs[inputId] = value;
                    _promptFillTicks[inputId] =
                        (_promptFillTicks[inputId] ?? 0) + 1;
                  }
                },
              ),
              if (showSettings) ...[
                const SizedBox(width: 6),
                _ComposerIconButton(
                  icon: LucideIcons.settings,
                  tooltip: modelName.isEmpty
                      ? 'Settings'
                      : 'Settings · $modelName',
                  onTap: _showAdvancedSettings,
                  active: false,
                ),
              ],
              const SizedBox(width: 6),
              Text(
                current.isEmpty ? '' : '${current.length}',
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int get _sunoImageCount {
    final value = _inputs['cover_image'];
    if (value is List) return value.length;
    if (value is Uint8List && value.isNotEmpty) return 1;
    return 0;
  }

  /// Easy HitMaker composer: the idea and one row for photos, a clip, or a track.
  Widget _buildHitMakerEasyComposer() {
    final cs = Theme.of(context).colorScheme;
    final idea = _promptController.text;
    final images = _sunoImageCount;
    final hasClip = _filledMedia('clip');
    final hasTrack = _filledMedia('reference_audio');
    final clipName = (_inputs['clip_path'] as String?)
            ?.split(RegExp(r'[\\/]'))
            .last ??
        'Clip';
    final trackName = (_inputs['reference_audio_name'] as String?) ?? 'Track';
    final fieldStyle = TextStyle(
      color: cs.onSurface,
      fontSize: 15,
      height: 1.45,
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: _composerCardDecoration(cs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Song idea',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _promptController,
            minLines: _kComposerPromptMinLines,
            maxLines: _kComposerPromptMaxLines,
            style: fieldStyle,
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              hintText: 'A late-night drive through rain, hopeful by the last chorus',
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                fontSize: 15,
                height: 1.45,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              suffixIcon: _clearTextButton(
                visible: _promptController.text.isNotEmpty,
                tooltip: 'Clear prompt',
                onPressed: () => _clearPromptField('prompt'),
              ),
            ),
            onChanged: (value) {
              _inputs['prompt'] = value;
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Add a photo, a clip, or a track. Any one of these, or the idea, is enough. A short idea is turned into lyrics before the song.',
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (images > 0)
                _hitMakerFileChip(
                  label: images == 1 ? '1 photo' : '$images photos',
                  onClear: () => setState(() {
                    _inputs.remove('cover_image');
                    _inputs.remove('cover_image_path');
                  }),
                )
              else
                _hitMakerAddChip(
                  icon: LucideIcons.image,
                  label: 'Photo',
                  onTap: () {
                    final spec =
                        Map<String, dynamic>.from(_inputSpec('cover_image'));
                    spec['max'] = 5;
                    _pickImage(spec);
                  },
                ),
              if (hasClip)
                _hitMakerFileChip(
                  label: clipName,
                  onClear: () => setState(() {
                    _inputs.remove('clip');
                    _inputs.remove('clip_path');
                    _inputs.remove('clip_bytes');
                  }),
                )
              else
                _hitMakerAddChip(
                  icon: LucideIcons.clapperboard,
                  label: 'Clip',
                  onTap: () => _pickVideo(
                    Map<String, dynamic>.from(_inputSpec('clip')),
                  ),
                ),
              if (hasTrack)
                _hitMakerFileChip(
                  label: trackName,
                  onClear: () => setState(() {
                    _inputs.remove('reference_audio');
                    _inputs.remove('reference_audio_path');
                    _inputs.remove('reference_audio_name');
                    _inputs.remove('reference_audio_mime');
                  }),
                )
              else
                _hitMakerAddChip(
                  icon: LucideIcons.music,
                  label: 'Track',
                  onTap: () => _pickAudioForInput(
                    'reference_audio',
                    _inputSpec('reference_audio'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Up to 5 photos, one clip under 4 minutes and 100 MB, one track from 6 seconds to 30 minutes.',
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(),
              _autoPromptButton(
                fieldRef: 'prompt',
                suggestField: 'prompt',
                currentText: idea,
                apply: (value) {
                  _promptController.value = TextEditingValue(
                    text: value,
                    selection: TextSelection.collapsed(offset: value.length),
                  );
                  _inputs['prompt'] = value;
                },
              ),
              const SizedBox(width: 6),
              _ComposerIconButton(
                icon: LucideIcons.settings,
                tooltip: 'Settings',
                onTap: _showAdvancedSettings,
                active: false,
              ),
              const SizedBox(width: 6),
              Text(
                idea.isEmpty ? '' : '${idea.length}',
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hitMakerAddChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: cs.primary),
      label: Text(label),
      onPressed: onTap,
    );
  }

  Widget _hitMakerFileChip({
    required String label,
    required VoidCallback onClear,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputChip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      deleteIconColor: cs.onSurfaceVariant,
      onDeleted: onClear,
    );
  }

  /// Easy is the default. The other mode is a text link above Generate.
  Widget _buildMusicModeLink() {
    final cs = Theme.of(context).colorScheme;
    final toAdvanced = _musicEasy;
    return Center(
      child: TextButton(
        onPressed: () {
          setState(() {
            _inputs['music_mode'] = toAdvanced ? 'advanced' : 'easy';
            if (!toAdvanced) _easyMusicPrompt = null;
          });
        },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          toAdvanced ? 'Advanced' : 'Easy',
          style: TextStyle(
            color: cs.primary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: cs.primary,
          ),
        ),
      ),
    );
  }

  /// HitMaker can write a song, a sound, an extension, or a mashup.
  Widget _buildHitMakerKindBar() {
    final cs = Theme.of(context).colorScheme;
    const kinds = [
      ('song', 'Song'),
      ('sound', 'Sounds'),
      ('extend', 'Extend'),
      ('mashup', 'Mashup'),
    ];
    final raw = _inputs['suno_kind'];
    final selected = raw is String && kinds.any((kind) => kind.$1 == raw)
        ? raw
        : 'song';
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(4),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: kinds.map((kind) {
            final on = selected == kind.$1;
            return GestureDetector(
              onTap: () => setState(() => _inputs['suno_kind'] = kind.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  gradient: on
                      ? const LinearGradient(
                          colors: KalaColors.brandGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(AppStyles.radiusMd - 2),
                ),
                child: Text(
                  kind.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: on ? cs.onPrimary : cs.onSurfaceVariant,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildHitMakerExtendMashup() {
    final cs = Theme.of(context).colorScheme;
    final owned = _inputs['confirm_audio_rights'] == true;
    final duration = _inputs['extend_audio_duration'];
    final seconds = duration is num ? duration.toDouble() : null;
    final canSlide = _sunoExtend && seconds != null && seconds > 2 && seconds <= 8 * 60;
    final continueAt = (_inputs['continue_at'] as num?)?.toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_sunoExtend) _buildAudioUpload('extend_audio'),
        if (_sunoMashup) ...[
          _buildAudioUpload('mashup_a'),
          _buildAudioUpload('mashup_b'),
        ],
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: owned,
          onChanged: (value) =>
              setState(() => _inputs['confirm_audio_rights'] = value == true),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'This audio is mine and is not copyrighted',
            style: TextStyle(color: cs.onSurface, fontSize: 14),
          ),
        ),
        _buildMusicComposerField(
          label: _sunoMashup ? 'Style' : 'Style (optional)',
          hint: 'Genre, mood, and instruments',
          controller: _sunoStyleController,
          minLines: 2,
        ),
        _buildMusicComposerField(
          label: _sunoMashup ? 'Title' : 'Title (optional)',
          hint: 'Name for the new track',
          inputId: 'title',
          minLines: 1,
        ),
        _buildMusicComposerField(
          label: _sunoMashup ? 'Idea (optional)' : 'How it should continue (optional)',
          hint: _sunoMashup
              ? 'What the blend should feel like'
              : 'What should happen after the original',
          controller: _promptController,
          minLines: 3,
        ),
        if (canSlide)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Continue from ${((continueAt ?? (seconds - 1)).clamp(1, seconds - 0.5)).toStringAsFixed(0)}s',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Slider(
                  min: 1,
                  max: seconds - 0.5,
                  value: (continueAt ?? (seconds - 1))
                      .clamp(1, seconds - 0.5)
                      .toDouble(),
                  onChanged: (value) => setState(
                    () => _inputs['continue_at'] =
                        double.parse(value.toStringAsFixed(1)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Track choices for SongFlow. Easy and Advanced switch from the footer link.
  Widget _buildMusicModeBar() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        children: [
          if (_isKalaSong)
            _modePills(
              items: [
                (
                  id: 'create',
                  label: 'New',
                  selected: _musicTrackMode == 'create',
                ),
                (
                  id: 'remix',
                  label: 'Remix',
                  selected: _musicTrackMode == 'remix',
                ),
                (
                  id: 'repaint',
                  label: 'Repaint',
                  selected: _musicTrackMode == 'repaint',
                ),
              ],
              onPick: (id) {
                setState(() {
                  _inputs['track_mode'] = id;
                  final current = (_inputs['strength'] as num?)?.toDouble();
                  if (id == 'repaint' &&
                      (current == null || (current - 0.55).abs() < 0.001)) {
                    _inputs['strength'] = 0.75;
                  } else if (id == 'remix' &&
                      (current == null || (current - 0.75).abs() < 0.001)) {
                    _inputs['strength'] = 0.55;
                  }
                });
              },
            ),
          const SizedBox(height: 8),
          Text(
            _musicCaption(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  String _musicCaption() {
    if (_isSunoV6 && _sunoSounds) {
      return 'Describe the sound. Loop, tempo, and key are in settings.';
    }
    if (_isSunoV6) {
      return _musicEasy
          ? 'Describe the song, or add a photo, clip, or track. A short idea is turned into lyrics.'
          : 'Lyrics, a style, or what to leave out. The song is named for you.';
    }
    if (_musicRepaint) {
      return _musicEasy
          ? 'Describe the passage to replace, then add the track.'
          : 'Lyrics lead. Describe the passage, what to avoid, and add the track.';
    }
    if (_musicUsesAudio) {
      return _musicEasy
          ? 'Describe the new version, then add the track.'
          : 'Lyrics lead. Describe the new version, what to avoid, and add the track.';
    }
    if (_isKalaSongPro) {
      return _musicEasy
          ? 'Describe the song. The lyrics can be written for you.'
          : 'Lyrics lead. Add the style underneath.';
    }
    return _musicEasy
        ? 'A song idea is enough. We write the rest.'
        : 'Lyrics lead. Add the style, and what to leave out.';
  }

  String _musicLengthLabel(int seconds) {
    final whole = seconds < 0 ? 0 : seconds;
    final minutes = whole ~/ 60;
    final remainder = whole % 60;
    if (remainder == 0) {
      return minutes == 1 ? '1 min' : '$minutes min';
    }
    return '$minutes min $remainder sec';
  }

  Map<String, dynamic>? _speechModel(String id) {
    for (final model in _tool.models ?? const <Map<String, dynamic>>[]) {
      if (model['id'] == id && model['enabled'] != false) return model;
    }
    return null;
  }

  String _nearestImageFrame(int width, int height) {
    const frames = <String, double>{
      '1:1': 1,
      '16:9': 16 / 9,
      '9:16': 9 / 16,
      '4:3': 4 / 3,
      '3:4': 3 / 4,
    };
    if (width <= 0 || height <= 0) return '1:1';
    final target = width / height;
    var best = '1:1';
    var gap = double.infinity;
    for (final frame in frames.entries) {
      final next = (frame.value - target).abs();
      if (next < gap) {
        gap = next;
        best = frame.key;
      }
    }
    return best;
  }

  String _aspectFromAttachedPhoto() {
    final raw = _inputs['init_image'];
    Uint8List? bytes;
    if (raw is Uint8List && raw.isNotEmpty) {
      bytes = raw;
    } else if (raw is List) {
      for (final item in raw) {
        if (item is Uint8List && item.isNotEmpty) {
          bytes = item;
          break;
        }
      }
    }
    if (bytes == null) return '1:1';
    final decoded = imglib.decodeImage(bytes);
    if (decoded == null) return '1:1';
    return _nearestImageFrame(decoded.width, decoded.height);
  }

  Widget _modePills({
    required List<({String id, String label, bool selected})> items,
    required ValueChanged<String> onPick,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onPick(item.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: item.selected
                        ? const LinearGradient(
                            colors: KalaColors.brandGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    borderRadius:
                        BorderRadius.circular(AppStyles.radiusMd - 2),
                  ),
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: item.selected ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight:
                          item.selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Description or sample for the model selected above.
  /// Voice and language live in Additional Settings.
  Widget _buildSpeechLeadFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextInput('voice_description'),
        _buildAudioUpload('reference_audio'),
      ],
    );
  }

  String _speechChoiceLabel(String ref) {
    final input = _inputSpec(ref);
    final current =
        _inputs[ref]?.toString() ?? input['default']?.toString() ?? '';
    for (final option in _choiceOptions(input)) {
      if (option.value == current) return option.label;
    }
    return current;
  }

  String _speechSettingsSummary() {
    final current = _selectedModelId ?? _tool.model;
    if (current == 'qwen_voice_clone') {
      return 'Clone · ${_speechChoiceLabel('clone_language')}';
    }
    if (current == 'qwen_voice_design') {
      return 'Describe · ${_speechChoiceLabel('design_language')}';
    }
    return '${_speechChoiceLabel('voice')} · ${_speechChoiceLabel('language')}';
  }

  /// Same pill control as Pre Made Voice / Clone a Voice.
  /// Shown in Additional Settings while a premade voice is selected.
  Widget _buildSpeechStylePicker(StateSetter setSheetState) {
    final current = _selectedModelId ?? _tool.model;
    if (current == 'qwen_voice_clone') return const SizedBox.shrink();
    final describe = current == 'qwen_voice_design';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _modePills(
        items: [
          (id: 'preset', label: 'Pick a voice', selected: !describe),
          (id: 'describe', label: 'Describe a voice', selected: describe),
        ],
        onPick: (id) {
          final model = _speechModel(
            id == 'describe' ? 'qwen_voice_design' : 'xai_tts',
          );
          if (model == null) return;
          _selectModel(model);
          setSheetState(() {});
        },
      ),
    );
  }

  /// Pre Made Voice and Clone a Voice. Voice style is chosen in settings.
  Widget _buildSpeechModeBar() {
    final cs = Theme.of(context).colorScheme;
    if ((_tool.models ?? []).length < 2) return const SizedBox.shrink();
    final current = _selectedModelId ?? _tool.model;
    final clone = current == 'qwen_voice_clone';
    final description = _selectedModelData?['description'] as String?;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _modePills(
            items: [
              (id: 'voice', label: 'Pre Made Voice', selected: !clone),
              (id: 'clone', label: 'Clone a Voice', selected: clone),
            ],
            onPick: (id) {
              if (id == 'clone') {
                final model = _speechModel('qwen_voice_clone');
                if (model != null) _selectModel(model);
                return;
              }
              if (clone) {
                final model = _speechModel('xai_tts');
                if (model != null) _selectModel(model);
              }
            },
          ),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                fontSize: 12.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsMenu(String ref, {StateSetter? sheetSetter}) {
    final cs = Theme.of(context).colorScheme;
    final input = _inputSpec(ref);
    if (!_elementShouldRender(input)) return const SizedBox.shrink();
    final options = _choiceOptions(input);
    if (options.isEmpty) return const SizedBox.shrink();
    final label = input['label']?.toString() ?? ref;
    final hint = input['description'] as String?;
    _inputs[ref] ??= input['default']?.toString() ?? options.first.value;
    final current = _inputs[ref]?.toString() ?? '';
    var valueLabel = current;
    for (final option in options) {
      if (option.value == current) {
        valueLabel = option.label;
        break;
      }
    }

    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: InkWell(
        onTap: () async {
          final picked = await showModalBottomSheet<String>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheetContext) {
              final sheetScheme = Theme.of(sheetContext).colorScheme;
              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            label,
                            style: TextStyle(
                              color: sheetScheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final selected = option.value == current;
                            return ListTile(
                              title: Text(option.label),
                              trailing: selected
                                  ? Icon(LucideIcons.check,
                                      color: sheetScheme.primary, size: 18)
                                  : null,
                              selected: selected,
                              onTap: () =>
                                  Navigator.pop(sheetContext, option.value),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
          if (picked == null || !mounted) return;
          void apply() => _inputs[ref] = picked;
          if (sheetSetter != null) {
            sheetSetter(() => setState(apply));
          } else {
            setState(apply);
          }
        },
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (hint != null && hint.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hint,
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                valueLabel,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(
              LucideIcons.chevronDown,
              size: 16,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMuseCanvasSettings(ColorScheme cs, StateSetter setSheetState) {
    _inputs['thinking_level'] ??= 'high';
    _inputs['web_search'] ??= true;
    _inputs['image_search'] ??= true;
    _inputs['layout_tools'] ??= true;
    _inputs['moderation'] ??= 'auto';
    final thinking = _inputs['thinking_level'] == 'low' ? 'Low' : 'High';
    final filter = _inputs['moderation'] == 'low' ? 'Light' : 'Standard';

    return Column(
      children: [
        _buildCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: InkWell(
            onTap: () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                builder: (sheetContext) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final option in const [
                          ('high', 'High'),
                          ('low', 'Low'),
                        ])
                          ListTile(
                            title: Text(option.$2),
                            subtitle: Text(
                              option.$1 == 'high'
                                  ? 'More planning before the picture'
                                  : 'A faster, lighter pass',
                            ),
                            trailing: _inputs['thinking_level'] == option.$1
                                ? Icon(LucideIcons.check,
                                    color: Theme.of(sheetContext)
                                        .colorScheme
                                        .primary)
                                : null,
                            onTap: () => Navigator.pop(sheetContext, option.$1),
                          ),
                      ],
                    ),
                  );
                },
              );
              if (picked == null || !mounted) return;
              setSheetState(() {
                setState(() => _inputs['thinking_level'] = picked);
              });
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Reasoning',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'How much planning happens before the picture',
                        style: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  thinking,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronDown,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildSettingToggle(
          cs: cs,
          icon: LucideIcons.search,
          title: 'Look up facts',
          subtitle: 'Use current information when the picture needs it',
          value: _inputs['web_search'] == true,
          onChanged: (value) {
            setSheetState(() => setState(() => _inputs['web_search'] = value));
          },
        ),
        const SizedBox(height: 12),
        _buildSettingToggle(
          cs: cs,
          icon: LucideIcons.image,
          title: 'Look up pictures',
          subtitle: 'Find visual references for real places and products',
          value: _inputs['image_search'] == true,
          onChanged: (value) {
            setSheetState(
                () => setState(() => _inputs['image_search'] = value));
          },
        ),
        const SizedBox(height: 12),
        _buildSettingToggle(
          cs: cs,
          icon: LucideIcons.table,
          title: 'Charts and layouts',
          subtitle: 'Build tables and diagrams before drawing',
          value: _inputs['layout_tools'] == true,
          onChanged: (value) {
            setSheetState(
                () => setState(() => _inputs['layout_tools'] = value));
          },
        ),
        const SizedBox(height: 12),
        _buildCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: InkWell(
            onTap: () async {
              final picked = await showModalBottomSheet<String>(
                context: context,
                showDragHandle: true,
                builder: (sheetContext) {
                  return SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final option in const [
                          ('auto', 'Standard'),
                          ('low', 'Light'),
                        ])
                          ListTile(
                            title: Text(option.$2),
                            trailing: _inputs['moderation'] == option.$1
                                ? Icon(LucideIcons.check,
                                    color: Theme.of(sheetContext)
                                        .colorScheme
                                        .primary)
                                : null,
                            onTap: () => Navigator.pop(sheetContext, option.$1),
                          ),
                      ],
                    ),
                  );
                },
              );
              if (picked == null || !mounted) return;
              setSheetState(() {
                setState(() => _inputs['moderation'] = picked);
              });
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Content filter',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'How strictly the picture is filtered',
                        style: TextStyle(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.65),
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  filter,
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(LucideIcons.chevronDown,
                    size: 16,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOffFormChoices(ColorScheme cs, StateSetter setSheetState) {
    final onForm = <String>{
      for (final element in _currentElements)
        if (element['input_ref'] is String) element['input_ref'] as String,
    };
    final fields = <Map<String, dynamic>>[];
    for (final input in _tool.inputs) {
      if (input is! Map) continue;
      final type = input['type'];
      if (type != 'dropdown' &&
          type != 'text' &&
          type != 'toggle' &&
          type != 'slider') {
        continue;
      }
      final id = input['id'] as String?;
      if (id == null || id == 'prompt' || onForm.contains(id)) continue;
      if (_isSpeechTool &&
          (id == 'voice' ||
              id == 'language' ||
              id == 'design_language' ||
              id == 'clone_language')) {
        continue;
      }
      final spec = Map<String, dynamic>.from(input);
      if (!_elementShouldRender(spec)) continue;
      fields.add(spec);
    }
    if (fields.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final spec in fields) ...[
          if (spec['type'] == 'dropdown')
            _buildSettingsMenu(spec['id'] as String, sheetSetter: setSheetState)
          else if (spec['type'] == 'toggle')
            _buildToggle(spec['id'] as String, sheetSetter: setSheetState)
          else if (spec['type'] == 'slider')
            _buildSlider(spec['id'] as String, sheetSetter: setSheetState)
          else
            _buildTextInput(spec['id'] as String, sheetSetter: setSheetState),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// Scale and detail controls for the upscaler selected in this sheet.
  Widget _buildUpscaleModelOptions(ColorScheme cs, StateSetter setSheetState) {
    const ids = ['upscale_factor', 'enhance_details', 'realism'];
    final children = <Widget>[];
    for (final id in ids) {
      final input = _tool.inputs.cast<dynamic>().firstWhere(
            (i) => i is Map && i['id'] == id,
            orElse: () => null,
          );
      if (input is! Map) continue;
      final spec = Map<String, dynamic>.from(input);
      if (!_elementShouldRender(spec)) continue;
      final type = spec['type']?.toString();
      if (type == 'dropdown') {
        children.add(_buildDropdown(id, sheetSetter: setSheetState));
      } else if (type == 'toggle') {
        children.add(_buildToggle(id, sheetSetter: setSheetState));
      } else {
        continue;
      }
      children.add(const SizedBox(height: 12));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildModeSelector() {
    final cs = Theme.of(context).colorScheme;
    final modes = _tool.modes!;
    final modeKeys = modes.keys.toList();

    // The segmented pill is already self-explanatory; skip the bulky header.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: modeKeys.map((key) {
          final selected = _selectedModeKey == key;
          final label = modes[key]?["label"] ?? key;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedModeKey = key;
                  _promptController.clear();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(
                          colors: KalaColors.brandGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(AppStyles.radiusMd - 2),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: KalaColors.purple.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ----------------------------------------------------
  // 💎 INSUFFICIENT CREDITS SHEET
  // ----------------------------------------------------

  void _showInsufficientCreditsSheet({
    required int requiredCredits,
    required int currentCredits,
  }) {
    final cs = Theme.of(context).colorScheme;
    final shortage = requiredCredits - currentCredits;

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.gem,
                  size: 40,
                  color: Colors.orange.shade600,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Insufficient Credits',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Details
              Text(
                'You need $requiredCredits credits for this action',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Credit comparison
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Flexible(
                      child: _buildCreditInfo(
                        cs,
                        label: 'You have',
                        value: currentCredits.toString(),
                        color: cs.primary,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: cs.outlineVariant,
                    ),
                    Flexible(
                      child: _buildCreditInfo(
                        cs,
                        label: 'Need',
                        value: '+$shortage',
                        color: Colors.orange.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Get Credits Button
              SizedBox(
                width: double.infinity,
                child: GradientButton(
                  label: 'Get Credits',
                  icon: LucideIcons.gem,
                  onPressed: () {
                    Navigator.pop(context); // Close bottom sheet
                    // Navigate to main app's credits tab (index 2) instead of standalone page
                    // This ensures bottom app bar is visible and back button works correctly
                    Navigator.popUntil(context, (route) => route.isFirst);
                    selectedIndexNotifier.value = AppTabs.credits;
                  },
                  variant: ButtonVariant.primary,
                  size: ButtonSize.large,
                  expanded: true,
                ),
              ),
              const SizedBox(height: 8),

              // Cancel button
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditInfo(
    ColorScheme cs, {
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: cs.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.gem, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ----------------------------------------------------
  // ⏱️ RATE LIMIT STATUS SHEET
  // ----------------------------------------------------

  void _showRateLimitErrorSheet(String errorMessage, int jobsRequested) {
    final cs = Theme.of(context).colorScheme;
    final status = getRateLimitStatus();
    final isVip = status['isVip'] as bool;
    final maxJobs = status['maxJobs'] as int;
    final currentProcessing = status['currentProcessing'] as int;
    final available = status['available'] as int;
    final percentUsed = status['percentUsed'] as int;

    // Dynamic title and subtitle based on situation
    final String title;
    final String subtitle;
    final IconData icon;
    final Color iconColor;

    if (available == 0) {
      title = 'Your Jobs Are Running! 🚀';
      subtitle = 'All $maxJobs slots are busy processing your creations';
      icon = LucideIcons.sparkles;
      iconColor = cs.primary;
    } else if (jobsRequested > available) {
      title = 'Almost There! ⏳';
      subtitle =
          'You want $jobsRequested jobs but only $available slot${available > 1 ? 's' : ''} available';
      icon = LucideIcons.clock;
      iconColor = Colors.amber.shade600;
    } else {
      title = 'Processing Jobs';
      subtitle = '$currentProcessing jobs currently running';
      icon = LucideIcons.loader;
      iconColor = cs.tertiary;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated icon container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      iconColor.withValues(alpha: 0.15),
                      iconColor.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, size: 36, color: iconColor),
              ),
              const SizedBox(height: 16),

              // Dynamic title
              Text(
                title,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),

              // Subtitle
              Text(
                subtitle,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Live status display with animated progress
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    // Progress bar with gradient
                    Stack(
                      children: [
                        Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: cs.outlineVariant.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor:
                              maxJobs > 0 ? currentProcessing / maxJobs : 0,
                          child: Container(
                            height: 12,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: percentUsed >= 100
                                    ? [Colors.orange, Colors.red.shade400]
                                    : percentUsed >= 75
                                        ? [Colors.amber, Colors.orange]
                                        : [cs.primary, cs.tertiary],
                              ),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: (percentUsed >= 100
                                          ? Colors.orange
                                          : cs.primary)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Percentage text
                    Text(
                      '$percentUsed% capacity used',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Status pills row
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatusPill(
                            cs,
                            icon: LucideIcons.loader,
                            label: 'Running',
                            value: currentProcessing,
                            color: cs.tertiary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatusPill(
                            cs,
                            icon: LucideIcons.plus,
                            label: 'Available',
                            value: available,
                            color: available > 0 ? cs.primary : cs.error,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatusPill(
                            cs,
                            icon: LucideIcons.gauge,
                            label: 'Limit',
                            value: maxJobs,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Helpful suggestion
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.lightbulb, size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        available == 0
                            ? 'Jobs complete quickly! Check Results to see progress.'
                            : jobsRequested > available
                                ? 'Reduce to $available job${available > 1 ? 's' : ''} or wait for others to finish.'
                                : 'Your jobs are processing. New results will appear soon!',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: GradientButton(
                      icon: LucideIcons.eye,
                      label: 'Results',
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        // Navigate to result manager
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ResultManagerPage(),
                          ),
                        );
                      },
                      variant: ButtonVariant.secondary,
                      size: ButtonSize.large,
                      expanded: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (!isVip)
                    Expanded(
                      child: GradientButton(
                        icon: LucideIcons.crown,
                        label: 'Get VIP',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          // Navigate to credits page for VIP purchase
                          selectedIndexNotifier.value = AppTabs.credits;
                        },
                        variant: ButtonVariant.primary,
                        size: ButtonSize.large,
                        expanded: true,
                      ),
                    )
                  else
                    Expanded(
                      child: GradientButton(
                        icon: LucideIcons.checkCircle,
                        label: 'OK',
                        onPressed: () => Navigator.pop(sheetContext),
                        variant: ButtonVariant.primary,
                        size: ButtonSize.large,
                        expanded: true,
                      ),
                    ),
                ],
              ),

              // Tip for VIP users
              if (isVip) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.lightbulb, size: 18, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'As a VIP, you can have up to $maxJobs concurrent jobs. Wait for some to complete or check the Results page.',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Upgrade tip for non-VIP
              if (!isVip) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.amber.withValues(alpha: 0.15),
                        Colors.orange.withValues(alpha: 0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.crown,
                          size: 18, color: Colors.amber.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Upgrade to VIP for 15 concurrent jobs (3x more!), higher bulk limits, free upscale & more!',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(
    ColorScheme cs, {
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.8),
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // 🛰️ JOB SUBMISSION + POLLING
  // ----------------------------------------------------

  // Track if a job submission is in progress to prevent double execution
  bool _isSubmittingJob = false;

  /// Audio, Flash, Canvas, and Upscale Image only send keys from that model's params.
  void _keepListedParams(Map<String, dynamic> resolved) {
    final template = _selectedModelData?['params'];
    if (template is! Map) return;
    final listed = _isAudioTool ||
        _isFlashOrCanvasModel ||
        _tool.capabilityId == 'upscale';
    if (!listed) return;
    final allowed = <String>{
      for (final key in template.keys) key.toString(),
      if (_currentModelUseExternalApi != null) 'use_external_api',
    };
    if (_upscaleEnabled && _allowsOutputUpscale) {
      allowed.add('scale_factor');
      allowed.add('upscale_model');
    }
    resolved.removeWhere((key, _) => !allowed.contains(key));
    if (_isMusicTool) {
      for (final key in ['bpm', 'key_scale', 'time_signature']) {
        final value = resolved[key]?.toString().trim().toLowerCase();
        if (value == null || value.isEmpty || value == 'auto') {
          resolved.remove(key);
        }
      }
      if (_inputs['vocals'] == false) {
        resolved.remove('lyrics');
        resolved.remove('vocal_language');
      }
      if (!_musicUsesAudio) {
        resolved.remove('source_audio');
        resolved.remove('strength');
        resolved.remove('repaint_start');
        resolved.remove('repaint_end');
      } else {
        resolved.remove('duration');
        if (!_musicRepaint) {
          resolved.remove('repaint_start');
          resolved.remove('repaint_end');
        } else {
          final start = int.tryParse('${resolved['repaint_start']}') ?? 8;
          var end = int.tryParse('${resolved['repaint_end']}') ?? 18;
          if (end <= start) end = start + 5;
          resolved['repaint_start'] = start;
          resolved['repaint_end'] = end;
        }
      }
      if (_isKalaSongPro) {
        resolved.remove('negative_prompt');
      }
      _prepareSunoParams(resolved);
    }
    resolved.removeWhere((_, value) {
      if (value is! String) return false;
      return RegExp(r'^\{\{[\w\-]+\}\}$').hasMatch(value.trim());
    });
  }

  void _prepareSunoExtendOrMashup(Map<String, dynamic> resolved) {
    resolved['action'] = _sunoExtend ? 'upload_extend' : 'mashup';
    resolved['confirm_audio_rights'] = _inputs['confirm_audio_rights'] == true;
    resolved
      ..remove('mode')
      ..remove('duration')
      ..remove('vocal_gender')
      ..remove('variety')
      ..remove('sound_loop')
      ..remove('sound_tempo')
      ..remove('sound_key')
      ..remove('grab_lyrics')
      ..remove('instrumental')
      ..remove('negative_tags')
      ..remove('audio_id')
      ..remove('source_task_id')
      ..remove('lyrics');
    final style = _sunoStyleController.text.trim();
    if (style.isEmpty) {
      resolved.remove('style');
    } else {
      resolved['style'] = style.length > 1000 ? style.substring(0, 1000) : style;
    }
    final title = (_inputs['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) {
      resolved.remove('title');
    } else {
      resolved['title'] = title.length > 100 ? title.substring(0, 100) : title;
    }
    final idea = _promptController.text.trim();
    if (idea.isEmpty) {
      resolved.remove('prompt');
    } else {
      resolved['prompt'] = idea.length > 5000 ? idea.substring(0, 5000) : idea;
    }
    if (!_sunoExtend) return;
    final duration = _inputs['extend_audio_duration'];
    if (duration is num && duration > 0 && duration <= 8 * 60) {
      resolved['source_duration'] = duration;
    } else {
      resolved.remove('source_duration');
    }
    final continueAt = _inputs['continue_at'];
    if (continueAt is num) {
      resolved['continue_at'] = continueAt;
    } else {
      resolved.remove('continue_at');
    }
  }

  /// HitMaker fields that the shared music form does not share with other models.
  void _prepareSunoParams(Map<String, dynamic> resolved) {
    if (!_isSunoV6) return;
    resolved['variant'] = 'V6';
    if (_sunoExtend || _sunoMashup) {
      _prepareSunoExtendOrMashup(resolved);
      return;
    }
    resolved['action'] = _sunoSounds ? 'sounds' : 'song';
    if (_sunoSounds) {
      resolved
        ..remove('mode')
        ..remove('style')
        ..remove('lyrics')
        ..remove('title')
        ..remove('duration')
        ..remove('vocal_gender')
        ..remove('instrumental')
        ..remove('negative_tags')
        ..remove('variety');
      resolved['grab_lyrics'] = false;
      resolved['sound_loop'] = _inputs['sound_loop'] == true;
      final tempo = int.tryParse('${resolved['sound_tempo']}');
      if (tempo == null) {
        resolved.remove('sound_tempo');
      } else {
        resolved['sound_tempo'] = tempo;
      }
      final key = resolved['sound_key']?.toString().trim();
      if (key == null || key.isEmpty || key == 'Any') {
        resolved.remove('sound_key');
      }
      return;
    }

    resolved
      ..remove('sound_loop')
      ..remove('sound_tempo')
      ..remove('sound_key')
      ..remove('grab_lyrics');
    resolved['mode'] = _musicEasy ? 'easy' : 'custom';
    if (_inputs['vocals'] == false) {
      resolved['instrumental'] = true;
      resolved.remove('vocal_gender');
      resolved.remove('lyrics');
    } else {
      resolved.remove('instrumental');
    }
    final gender = resolved['vocal_gender']?.toString().trim().toLowerCase();
    if (gender == null || gender.isEmpty || gender == 'auto') {
      resolved.remove('vocal_gender');
    }
    if (_musicEasy) {
      resolved
        ..remove('style')
        ..remove('title')
        ..remove('negative_tags')
        ..remove('duration')
        ..remove('vocal_gender')
        ..remove('variety');
    } else {
      final style = _sunoStyleController.text.trim();
      if (style.isEmpty) {
        resolved.remove('style');
      } else {
        resolved['style'] =
            style.length > 1000 ? style.substring(0, 1000) : style;
      }
      final avoid = (_inputs['negative_prompt'] as String?)?.trim() ?? '';
      if (avoid.isEmpty) {
        resolved.remove('negative_tags');
      } else {
        resolved['negative_tags'] = avoid;
      }
      resolved.remove('title');
      final variety = int.tryParse('${resolved['variety']}');
      if (variety == null) {
        resolved.remove('variety');
      } else {
        resolved['variety'] = variety.clamp(0, 4);
      }
    }
    if (!_musicEasy) {
      final length = int.tryParse('${resolved['duration']}');
      if (length == null) {
        resolved.remove('duration');
      } else {
        resolved['duration'] = length.clamp(10, 360);
      }
    } else {
      resolved.remove('duration');
    }
  }

  void _syncLiveSubmitInputsFromUi() {
    if (_hasPrompt) {
      final expanded = _easyMusicPrompt?.trim();
      _inputs["prompt"] = (expanded != null && expanded.length >= 2)
          ? expanded
          : _promptController.text.trim();
    }
    final activeModel = _selectedModelId ?? _tool.model;
    if (activeModel == 'flux2_klein_9b_edit') {
      _inputs['aspect_ratio'] = _aspectFromAttachedPhoto();
    } else if (_isFlashOrCanvasModel && !_isEditImageTool) {
      final ratio = _inputs['aspect_ratio']?.toString().trim() ?? '';
      if (ratio.isEmpty || ratio == 'auto') {
        _inputs['aspect_ratio'] = _selectedShapeRatio;
      }
    }
    if (_isMuseModel) {
      _inputs['thinking_level'] ??= 'high';
      _inputs['web_search'] ??= true;
      _inputs['image_search'] ??= true;
      _inputs['layout_tools'] ??= true;
      _inputs['moderation'] ??= 'auto';
    }
    if (_isMusicTool) {
      if (_isSunoV6) {
        _inputs['suno_kind'] ??= 'song';
        final cap = _sunoSounds ? 500 : 5000;
        var prompt = _inputs['prompt']?.toString().trim() ?? '';
        if (prompt.length > cap) prompt = prompt.substring(0, cap);
        _inputs['prompt'] = prompt;
        _inputs['action'] = _sunoSounds
            ? 'sounds'
            : _sunoExtend
                ? 'upload_extend'
                : _sunoMashup
                    ? 'mashup'
                    : 'song';
        _inputs['mode'] = _musicEasy ? 'easy' : 'custom';
        _inputs['variant'] = 'V6';
        if (!_sunoSounds && !_sunoExtend && !_sunoMashup && !_musicEasy) {
          _inputs['prompt'] = '';
          _inputs['style'] = _sunoStyleController.text.trim();
        }
      }
      final vocals = _inputs['vocals'] != false;
      _inputs['instrumental'] = !vocals;
      if (!vocals) {
        _keepLyricsAcrossVocals(false);
        _inputs['lyrics_optimizer'] = false;
      } else if (_isKalaSongPro && _musicEasy) {
        _inputs['lyrics_optimizer'] ??= true;
      }
    }
    if (!_hasScaleFactor && _inputs.containsKey("scale_factor")) {
      _inputs["scale_factor"] = _upscaleEnabled ? _scaleFactor : 1;
    }
    _syncFaceEnhancerFixedParams();
  }

  static String _encodeBytesToCleanBase64ForSubmit(Uint8List bytes) {
    String b64 = base64Encode(bytes);
    b64 = b64.replaceAll(RegExp(r'\s+'), '');
    final len = b64.length;
    final mod4 = len % 4;
    if (mod4 != 0) {
      final stripped = b64.replaceAll('=', '');
      final strippedMod4 = stripped.length % 4;
      if (strippedMod4 == 0) {
        b64 = stripped;
      } else {
        b64 = stripped + ('=' * (4 - strippedMod4));
      }
      debugPrint('⚠️ Fixed base64 padding: $len → ${b64.length} chars');
    }
    final isValid = RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(b64);
    final ends = b64.length > 12 ? b64.substring(b64.length - 12) : b64;
    debugPrint(
        '📦 Base64: ${bytes.length} bytes → ${b64.length} chars, mod4=${b64.length % 4}, valid=$isValid, ends: $ends');
    if (!isValid) {
      debugPrint(
          '⚠️ Invalid base64! First 50 chars: ${b64.substring(0, min(50, b64.length))}');
    }
    return b64;
  }

  void _applyBinaryFieldsToBase64InSubmitMap(Map<String, dynamic> encoded) {
    for (final key in encoded.keys.toList()) {
      final val = encoded[key];
      if (val is Uint8List) {
        encoded[key] = _encodeBytesToCleanBase64ForSubmit(val);
      } else if (val is List) {
        if (val.isEmpty) {
          encoded.remove(key);
          continue;
        }
        if (val.first is Uint8List) {
          encoded[key] = val.length == 1
              ? _encodeBytesToCleanBase64ForSubmit(val.first as Uint8List)
              : val
                  .map(
                      (e) => _encodeBytesToCleanBase64ForSubmit(e as Uint8List))
                  .toList();
        } else {
          encoded[key] = val.length == 1 ? val.first : val;
        }
      }
    }
  }

  /// CPU-heavy base64 encoding of image/mask fields, overlapping with the rewarded ad for heavy tier.
  Future<Map<String, dynamic>> _buildMediaEncodedSubmitMapClone() async {
    final encoded = Map<String, dynamic>.from(_inputs);
    if (_hasPrompt &&
        (encoded["prompt"] == null ||
            (encoded["prompt"] is String &&
                (encoded["prompt"] as String).isEmpty))) {
      encoded["prompt"] = _promptController.text.trim();
    }
    if (_tool.params?.containsKey("mode") == true &&
        _selectedModeKey != null &&
        !_inputs.containsKey("mode")) {
      encoded["mode"] = _selectedModeKey;
      debugPrint('🧩 Injected mode (prefetch): $_selectedModeKey');
    }
    _applyBinaryFieldsToBase64InSubmitMap(encoded);
    return encoded;
  }

  Future<bool> _runHeavyTierRewardedGateWithParallelMediaEncode() async {
    if (!shouldRequireHeavyTierRewardedAd()) return true;
    try {
      final results = await Future.wait<Object>([
        completeHeavyTierRewardedAdIfNeeded(context),
        _buildMediaEncodedSubmitMapClone(),
      ]);
      final adOk = results[0] as bool;
      if (!adOk) return false;
      _prefetchedEncodedInputsForSubmit = results[1] as Map<String, dynamic>;
      return true;
    } catch (e, st) {
      debugPrint('❌ Parallel ad gate / media encode failed: $e\n$st');
      rethrow;
    }
  }

  /// ACE-Step treats the prompt as a caption and the lyrics as a timed script.
  /// Tempo and key stay in their own fields. Source: ACE-Step 1.5 tutorial.
  String _aceMusicSkill({required bool vocals, required int seconds}) {
    final form = seconds <= 45
        ? 'Intro, one verse, chorus, outro.'
        : seconds <= 90
            ? 'Intro, verse, chorus, verse, chorus, outro.'
            : 'Intro, verse, pre-chorus, chorus, verse, chorus, bridge, final chorus, outro.';
    return '''
You write inputs for ACE-Step 1.5. Follow this skill exactly.

Caption (the prompt field):
- This is the song's overall portrait: genre, emotion, instruments, timbre, era, production, and vocal character.
- Do not write BPM, key, or time signature in the prompt. Those go only in bpm, keyScale, and timeSignature.
- Be specific. "Sad piano ballad, female breathy vocal, close and dry" is better than "a sad song".
- Combine genre, emotion, instruments, and texture. Do not ask for two conflicting styles unless the caption says the style changes over time.
- Comma-separated tags or one short paragraph. Under 2500 characters.

Lyrics are the timeline, not a second caption:
- Structure tags: [Intro], [Verse], [Pre-Chorus], [Chorus], [Bridge], [Outro], [Build], [Drop], [Breakdown], [Instrumental]. A solo may be [Guitar Solo] or [Piano Solo].
- One short hint after a dash is allowed, such as [Chorus - anthemic]. Do not stack many adjectives in one tag.
- Sung lines are 6 to 10 syllables. Leave a blank line between sections.
- Parentheses are background vocals. Capital letters mean a shout, so use them rarely.
- Keep one metaphor. Do not stack vague images.
- The caption and the lyrics must agree on instruments, energy, and the singer.
- ${vocals ? 'Write sung lyrics for about $seconds seconds. Shape: $form' : 'This is instrumental. Leave lyrics empty. The caption must describe an instrumental with no singer. Set vocalLanguage to unknown.'}

negativePrompt is a short exclusion list, under 200 characters, or an empty string. It must not contradict the caption.

bpm is one of 70, 80, 90, 100, 110, 120, 128, 140, 160. Match the energy, but do not repeat it in the caption.
keyScale is one of C major, G major, D major, A major, F major, Bb major, A minor, E minor, D minor, B minor, F# minor.
timeSignature is 4 unless the idea clearly needs 3 or 6. 2 is only for a march.
vocalLanguage is ${vocals ? 'en, es, fr, de, hi, ja, ko, zh, pt, it, ru, or ar, chosen from the idea, otherwise en' : 'unknown'}.
''';
  }

  /// MiniMax Music 2.6 reads key and BPM from the prompt itself, and uses its own lyric tags.
  String _minimaxMusicSkill({required bool vocals}) {
    return '''
You write inputs for MiniMax Music 2.6. Follow this skill exactly.

Prompt:
- A producer note, comma-separated, under 1800 characters. Not an essay and not a section-by-section story.
- Put the key and the BPM in the prompt. This model follows those words. Shape: "D minor, 90 BPM, acoustic ballad, intimate, female vocal, breathy, acoustic guitar, piano, dry studio".
- Order: key, BPM, genre, mood, vocal description, instruments, production.
- ${vocals ? 'Name the singer, for example female vocal or male vocal, and how they sing.' : 'Start the style with Instrumental. The prompt must describe an instrumental with no singer.'}

Lyrics:
- Use only these tags: [Intro], [Verse], [Pre Chorus], [Chorus], [Post Chorus], [Hook], [Bridge], [Interlude], [Break], [Transition], [Build Up], [Inst], [Solo], [Outro].
- One newline between lines. A blank line between sections. The tags are not sung.
- Parentheses are backing vocals or a performance note, such as (ooh) or (whispered).
- ${vocals ? 'Write a complete song: intro, verse, pre-chorus, chorus, second verse, chorus, bridge, final chorus, outro. Repeat the chorus words. At least 80 characters and under 3500.' : 'Leave lyrics empty.'}
- The prompt and the lyrics must share one mood. Do not mix conflicting styles.

negativePrompt is a short comma list of things to leave out, under 200 characters, or an empty string. Do not restate the style there.

bpm, keyScale, and vocalLanguage must match the prompt. bpm is one of 70, 80, 90, 100, 110, 120, 128, 140, 160.
keyScale is one of C major, G major, D major, A major, F major, Bb major, A minor, E minor, D minor, B minor, F# minor.
timeSignature is 4 unless the idea clearly needs 3 or 6.
vocalLanguage is ${vocals ? 'en, es, fr, de, hi, ja, ko, zh, pt, it, ru, or ar, otherwise en' : 'unknown'}.
''';
  }

  Future<bool> _fillEasyMusicFromIdea() async {
    final idea = _promptController.text.trim();
    if (idea.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a song idea first.')),
        );
      }
      return false;
    }
    final vocals = _inputs['vocals'] != false;
    final model = _selectedModelId ?? _tool.model;
    final isPro = model == 'minimax_music_26';
    final writeLyrics =
        vocals && !(isPro && _inputs['lyrics_optimizer'] != false);
    final seconds = int.tryParse('${_inputs['duration'] ?? ''}') ?? 60;
    _easyMusicPrompt = null;
    final skill = isPro
        ? _minimaxMusicSkill(vocals: vocals)
        : _aceMusicSkill(vocals: vocals, seconds: seconds);
    final trackNote = _musicRepaint
        ? 'This rewrites only the passage from ${_inputs['repaint_start'] ?? 8} to ${_inputs['repaint_end'] ?? 18} seconds of an uploaded track. Describe that passage. Do not set a new duration.'
        : _musicUsesAudio
            ? 'This reinterprets an entire uploaded track. Describe the new version and what should stay recognizable. Do not set a new duration. If the idea includes words to speak, keep those words in the prompt.'
            : '';
    final task = '''
Song idea: $idea
Vocals: ${vocals ? 'yes' : 'instrumental only'}
${isPro ? 'Length: a full song.' : _musicUsesAudio ? 'Length: follow the uploaded track.' : 'Length: $seconds seconds.'}
${writeLyrics ? '' : 'Leave lyrics empty. The song model will write them.'}
$trackNote
Return only the JSON fields.
''';
    try {
      final result = await GeminiDirector().generate(
        step: 'music_easy',
        systemInstruction: skill,
        // The live worker forwards this message. The system field is used
        // once that worker is deployed with system-instruction support.
        instruction: '$skill\n\nTask:\n$task',
        schema: {
          'type': 'OBJECT',
          'properties': {
            'prompt': {'type': 'STRING'},
            'lyrics': {'type': 'STRING'},
            'bpm': {'type': 'INTEGER'},
            'keyScale': {'type': 'STRING'},
            'timeSignature': {'type': 'INTEGER'},
            'vocalLanguage': {'type': 'STRING'},
            'negativePrompt': {'type': 'STRING'},
          },
          'required': [
            'prompt',
            if (writeLyrics) 'lyrics',
            'bpm',
            'keyScale',
            'timeSignature',
            'vocalLanguage',
          ],
        },
      );
      final prompt = (result['prompt'] ?? '').toString().trim();
      if (prompt.length < 2) {
        throw StateError('The song brief was too short. Try again.');
      }
      var lyrics = (result['lyrics'] ?? '').toString().trim();
      final vocalsOn = vocals;
      if (vocalsOn && !writeLyrics) lyrics = '';
      if (writeLyrics && lyrics.length < 10) {
        throw StateError('The lyrics were too short. Try the idea again.');
      }
      const tempos = [70, 80, 90, 100, 110, 120, 128, 140, 160];
      final bpmRaw = result['bpm'];
      final bpmNum =
          bpmRaw is num ? bpmRaw.round() : int.tryParse('$bpmRaw') ?? 100;
      var tempo = tempos.first;
      var gap = 1 << 30;
      for (final candidate in tempos) {
        final next = (candidate - bpmNum).abs();
        if (next < gap) {
          tempo = candidate;
          gap = next;
        }
      }
      const keys = {
        'C major',
        'G major',
        'D major',
        'A major',
        'F major',
        'Bb major',
        'A minor',
        'E minor',
        'D minor',
        'B minor',
        'F# minor',
      };
      final key = (result['keyScale'] ?? '').toString().trim();
      final meterRaw = result['timeSignature'];
      final meter =
          meterRaw is num ? meterRaw.round() : int.tryParse('$meterRaw');
      const languages = {
        'en',
        'es',
        'fr',
        'de',
        'hi',
        'ja',
        'ko',
        'zh',
        'pt',
        'it',
        'ru',
        'ar',
        'unknown',
      };
      var language =
          (result['vocalLanguage'] ?? '').toString().trim().toLowerCase();
      if (!languages.contains(language)) language = vocals ? 'en' : 'unknown';
      if (!vocals) language = 'unknown';
      final lockedDuration = _inputs['duration'];
      final lockedVocals = _inputs['vocals'];
      _easyMusicPrompt = prompt;
      if (vocalsOn) {
        _inputs['lyrics'] = lyrics;
        _inputs['vocal_language'] = language;
      } else {
        _keepLyricsAcrossVocals(false);
      }
      _inputs['bpm'] = '$tempo';
      _inputs['key_scale'] = keys.contains(key) ? key : 'C major';
      _inputs['time_signature'] =
          const {2, 3, 4, 6}.contains(meter) ? '$meter' : '4';
      _inputs['negative_prompt'] = isPro
          ? ''
          : (result['negativePrompt'] ?? '').toString().trim();
      if (!isPro || !vocals) {
        _inputs['lyrics_optimizer'] = false;
      }
      _inputs['duration'] = lockedDuration;
      _inputs['vocals'] = lockedVocals;
      return true;
    } on StateError catch (error) {
      _easyMusicPrompt = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message)),
        );
      }
      return false;
    } catch (_) {
      _easyMusicPrompt = null;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not write the song. Try again.')),
        );
      }
      return false;
    }
  }

  Future<void> _runJob() async {
    if (_musicEasy && !_isSunoV6 && !_musicExpanding && !_isSubmittingJob) {
      final signedIn = await requireSignIn(context, feature: 'AI Tools');
      if (!signedIn || !mounted) return;
      setState(() => _musicExpanding = true);
      final ready = await _fillEasyMusicFromIdea();
      if (mounted) setState(() => _musicExpanding = false);
      if (!ready || !mounted) return;
    }
    // Video upscaler bulk: validate once, then run one [_runJob] per queued file.
    if (!_videoBulkSequentialActive &&
        _isVideoUpscalerTool &&
        _advancedSettings.bulkEditEnabled &&
        _supportsBulkVideoEdit &&
        _bulkVideoPaths.isNotEmpty) {
      if (_isSubmittingJob) {
        debugPrint("⚠️ Job submission already in progress, ignoring tap");
        return;
      }
      _videoBulkSequentialActive = true;
      try {
        final variations =
            _advancedSettings.variations.clamp(1, getMaxVariations());
        final totalJobs = _bulkVideoPaths.length * variations;
        final rateLimitError = checkRateLimitForSubmission(totalJobs);
        if (rateLimitError != null) {
          if (mounted) {
            _showRateLimitErrorSheet(rateLimitError, totalJobs);
          }
          return;
        }
        if (!AuthService().isSignedIn) {
          final signedIn = await requireSignIn(context, feature: 'AI Tools');
          if (!signedIn) return;
        }
        final totalCostAll = _calculateTotalCost();
        final currentCredits = userCreditsNotifier.value;
        if (!UserService().hasEnoughCredits(totalCostAll)) {
          if (mounted) {
            _showInsufficientCreditsSheet(
              requiredCredits: totalCostAll,
              currentCredits: currentCredits,
            );
          }
          return;
        }
        _syncLiveSubmitInputsFromUi();
        final adGateOk =
            await _runHeavyTierRewardedGateWithParallelMediaEncode();
        if (!adGateOk) return;

        for (var i = 0; i < _bulkVideoPaths.length; i++) {
          if (!mounted) break;
          try {
            await _hydrateVideoUpscalerBulkIndex(i);
          } catch (e, st) {
            debugPrint('❌ Bulk video hydrate failed: $e\n$st');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Could not load video ${i + 1}: $e')),
              );
            }
            continue;
          }
          _isSubmittingJob = false;
          await _runJob();
        }
      } finally {
        _videoBulkSequentialActive = false;
        _isSubmittingJob = false;
      }
      return;
    }

    // Prevent double execution from rapid taps
    if (_isSubmittingJob) {
      debugPrint("⚠️ Job submission already in progress, ignoring tap");
      return;
    }
    _isSubmittingJob = true;

    final cs = Theme.of(context).colorScheme;

    // --- Calculate total jobs for rate limiting ---
    final variations =
        _advancedSettings.variations.clamp(1, getMaxVariations());
    final int imageCount = _advancedSettings.bulkEditEnabled && _hasBulkInput
        ? _bulkActiveMediaCount
        : 1;
    final int totalJobsToSubmit = imageCount * variations;

    // --- RATE LIMITING CHECK ---
    if (!_videoBulkSequentialActive) {
      final rateLimitError = checkRateLimitForSubmission(totalJobsToSubmit);
      if (rateLimitError != null) {
        _isSubmittingJob = false;
        if (mounted) {
          _showRateLimitErrorSheet(rateLimitError, totalJobsToSubmit);
        }
        return;
      }
    }

    // --- Check if user is signed in ---
    if (!_videoBulkSequentialActive && !AuthService().isSignedIn) {
      final signedIn = await requireSignIn(context, feature: 'AI Tools');
      if (!signedIn) {
        _isSubmittingJob = false;
        return;
      }
    }

    // --- Check credits ---
    final totalCost = _calculateTotalCost();
    final currentCredits = userCreditsNotifier.value;
    if (!UserService().hasEnoughCredits(totalCost)) {
      _isSubmittingJob = false;
      if (mounted) {
        _showInsufficientCreditsSheet(
          requiredCredits: totalCost,
          currentCredits: currentCredits,
        );
      }
      return;
    }

    _syncLiveSubmitInputsFromUi();
    if (!_videoBulkSequentialActive) {
      final adGateOk = await _runHeavyTierRewardedGateWithParallelMediaEncode();
      if (!adGateOk) {
        _isSubmittingJob = false;
        return;
      }
    }

    // --- Show progress dialog ---
    final ValueNotifier<String> dialogMessage = ValueNotifier<String>(
      "Hang tight while we queue and process your request.\nAvoid pressing back or closing the app.",
    );
    Timer? messageTimer;
    messageTimer = Timer(const Duration(seconds: 45), () {
      dialogMessage.value =
          "Still working... It's taking a bit longer than usual.\nPlease stay on this screen.";
    });

    // Track dialog visibility for safe dismissal
    bool dialogShowing = false;

    // Helper to safely dismiss the dialog
    void dismissDialog() {
      messageTimer?.cancel();
      if (dialogShowing && mounted) {
        dialogShowing = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!mounted) {
      _isSubmittingJob = false;
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        dialogShowing = true;
        return Dialog(
          backgroundColor: cs.surface,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated progress indicator with glow
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      color: cs.primary,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Title with icon
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.sparkles,
                      size: 20,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Creating Magic",
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Description
                ValueListenableBuilder<String>(
                  valueListenable: dialogMessage,
                  builder: (_, value, __) => Text(
                    value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    const int maxRetries = 3;
    int attempt = 0;

    while (attempt < maxRetries) {
      attempt++;
      try {
        // --- Clone _inputs for encoding (base64 may have run in parallel with the rewarded ad) ---
        final bool usedEncodedPrefetch =
            _prefetchedEncodedInputsForSubmit != null;
        final Map<String, dynamic> encoded;
        if (usedEncodedPrefetch) {
          encoded =
              Map<String, dynamic>.from(_prefetchedEncodedInputsForSubmit!);
          _prefetchedEncodedInputsForSubmit = null;
        } else {
          encoded = Map<String, dynamic>.from(_inputs);
        }

        // 🩵 Ensure prompt is included even if empty in _inputs
        if (_hasPrompt &&
            (encoded["prompt"] == null ||
                (encoded["prompt"] is String &&
                    (encoded["prompt"] as String).isEmpty))) {
          encoded["prompt"] = _promptController.text.trim();
        }

        // 🩵 Auto-inject mode for multi-mode tools (WAN / SDXL)
        if (_tool.params?.containsKey("mode") == true &&
            _selectedModeKey != null &&
            !_inputs.containsKey("mode")) {
          encoded["mode"] = _selectedModeKey;
          debugPrint("🧩 Injected mode: $_selectedModeKey");
        }

        // 🩵 Fallback: make sure root_params prompt is filled
        if (_tool.rootParams != null &&
            !_tool.rootParams!.containsKey("prompt")) {
          _tool.rootParams!["prompt"] = "{{prompt}}";
        }

        if (!usedEncodedPrefetch) {
          _applyBinaryFieldsToBase64InSubmitMap(encoded);
        }

        // 🩵 Safe default for sliders (avoid missing scale_factor)
        if (!encoded.containsKey("scale_factor")) {
          final def = _tool.inputs.firstWhere(
              (i) => i["id"] == "scale_factor",
              orElse: () => {"default": 1});
          encoded["scale_factor"] = def["default"] ?? 1;
        }

        // --- Auto width/height inference (with null safety) ---
        try {
          final imgInput = _tool.inputs
              .firstWhere((i) => i["type"] == "image", orElse: () => {});
          final id = imgInput["id"];
          if (encoded.containsKey(id)) {
            final imgVal = encoded[id];
            Uint8List? firstImg;
            if (imgVal is String) {
              if (imgVal.isNotEmpty) firstImg = base64Decode(imgVal);
            } else if (imgVal is List &&
                imgVal.isNotEmpty &&
                imgVal.first is String) {
              final s = imgVal.first as String;
              if (s.isNotEmpty) firstImg = base64Decode(s);
            }

            if (firstImg != null && firstImg.isNotEmpty) {
              final codec = await ui.instantiateImageCodec(firstImg);
              final frame = await codec.getNextFrame();
              final img = frame.image;
              int roundTo32(int x) => ((x / 32).round() * 32).clamp(32, 2048);
              encoded["width"] = roundTo32(img.width);
              encoded["height"] = roundTo32(img.height);
              img.dispose();
            }
          }
        } catch (_) {}

        // --- Build params dynamically ---
        final Map<String, dynamic> resolvedParams = {};
        final Set<String> consumedInputs = {};

        dynamic getInputValue(String refId) {
          if (encoded.containsKey(refId)) return encoded[refId];

          // Support model-specific input overrides (e.g. qwen_image_edit_2509 references {{images}}
          // but the base input id is init_image).
          try {
            final overrides =
                _selectedModelData?['inputOverrides'] as Map<String, dynamic>?;
            if (overrides != null && overrides.isNotEmpty) {
              for (final entry in overrides.entries) {
                final baseId = entry.key;
                final o = entry.value;
                if (o is Map && o['id'] is String) {
                  final overrideId = o['id'] as String;

                  // If template asks for overrideId (e.g. "images"), return the base value ("init_image").
                  if (overrideId == refId ||
                      overrideId.replaceAll('-', '_') ==
                          refId.replaceAll('-', '_')) {
                    if (encoded.containsKey(baseId)) return encoded[baseId];
                  }

                  // If template asks for baseId, return overrideId value (in case UI stored it there).
                  if (baseId == refId ||
                      baseId.replaceAll('-', '_') ==
                          refId.replaceAll('-', '_')) {
                    if (encoded.containsKey(overrideId)) {
                      return encoded[overrideId];
                    }
                  }
                }
              }
            }
          } catch (_) {}

          final aliases = [
            refId,
            refId.replaceAll('-', '_'),
            refId.replaceAll('_factor', ''),
            '${refId}_factor',
          ];
          for (final alias in aliases) {
            if (encoded.containsKey(alias)) return encoded[alias];
          }
          try {
            final def = _tool.inputs.firstWhere(
              (i) =>
                  i is Map &&
                  (i['id'] == refId || i['id'] == refId.replaceAll('-', '_')),
              orElse: () => null,
            );
            if (def != null && def is Map && def.containsKey('default')) {
              return def['default'];
            }
          } catch (_) {}
          return null;
        }

        // Get params from selected model or fallback to config
        Map<String, dynamic>? modelParams =
            _selectedModelData?['params'] as Map<String, dynamic>? ??
                _tool.params;
        if (_isCineRealAnimateModel && _isCineRealFlf2vMode) {
          final p = _selectedModelData?['paramsFlf2v'] as Map<String, dynamic>?;
          if (p != null && p.isNotEmpty) {
            modelParams = Map<String, dynamic>.from(p);
          }
        }
        final Map<String, dynamic>? modelRootParams =
            _selectedModelData?['rootParams'] as Map<String, dynamic>? ??
                _tool.rootParams;

        // Resolve {{template}} placeholders
        modelParams?.forEach((key, value) {
          dynamic val = value;
          if (val is String) {
            final reg = RegExp(r"\{\{([\w\-]+)\}\}");
            for (final m in reg.allMatches(val)) {
              final ref = m.group(1)!;
              final fetched = getInputValue(ref);
              if (fetched != null) {
                val = fetched;
                consumedInputs.add(ref);
              } else {
                debugPrint(
                    '⚠️ Unresolved param placeholder {{$ref}} for key="$key" (model=${_selectedModelId ?? _tool.model})');
              }
            }
          }
          resolvedParams[key] = val;
        });

        // --- Root params ---
        final Map<String, dynamic> rootParams = {};
        modelRootParams?.forEach((key, value) {
          dynamic val = value;
          if (val is String && val.startsWith("{{") && val.endsWith("}}")) {
            final refId = val.substring(2, val.length - 2);
            final fetched = getInputValue(refId);
            if (fetched != null) {
              val = fetched;
              consumedInputs.add(refId);
            } else {
              debugPrint(
                  '⚠️ Unresolved root placeholder {{$refId}} for key="$key" (model=${_selectedModelId ?? _tool.model})');
            }
          }
          rootParams[key] = val;
        });

        // ✅ Ensure root prompt present even if not resolved
        if (!rootParams.containsKey("prompt") &&
            encoded.containsKey("prompt")) {
          rootParams["prompt"] = encoded["prompt"];
        }

        // --- FCM token ---
        final prefs = await SharedPreferences.getInstance();
        String? fcmToken = prefs.getString("fcm_token");
        if (fcmToken == null) {
          fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) await prefs.setString("fcm_token", fcmToken);
        }

        // --- Apply advanced settings to params ---
        // On-device inpaint uses a minimal flow (no prompt/styles/advanced controls).
        if (!_isOnDeviceInpaintTool) {
          // CFG scale is fixed (advanced UI removed); backend expects a numeric value.
          resolvedParams["cfg_scale"] = 1.0;

          // Scale factor: main slider (e.g. Remove Background) keeps template-resolved value.
          if (!_hasScaleFactor) {
            resolvedParams["scale_factor"] =
                _advancedSettings.upscaleOutput ? _scaleFactor : 1;
          }
          resolvedParams["scale_image"] = true;
        }

        // Get model ID for model-specific handling
        final currentModelId = _selectedModelId ?? _tool.model;

        // LoRA adapter for qwen_image_edit_2511_rapid_aio
        if (currentModelId == 'qwen_image_edit_2511_rapid_aio') {
          resolvedParams['lora_adapter'] = _advancedSettings.loraAdapter;
        }

        // Calculate height/width based on selected aspect ratio (default 1:1; legacy `Default` → 1:1).
        if (!_isOnDeviceInpaintTool) {
          final selectedRatio = _selectedShapeRatio;
          final ratioParts = selectedRatio.split(':');
          if (ratioParts.length == 2) {
            final ratioW = double.tryParse(ratioParts[0]) ?? 1;
            final ratioH = double.tryParse(ratioParts[1]) ?? 1;
            final targetRatio = ratioW / ratioH;

            // Get current dimensions (may have been inferred from image)
            final currentWidth = resolvedParams["width"] as int? ?? 896;
            final currentHeight = resolvedParams["height"] as int? ?? 896;

            // Calculate new dimensions maintaining the larger dimension
            int newWidth, newHeight;
            if (targetRatio >= 1.0) {
              // Landscape or square - base on width
              newWidth = currentWidth;
              newHeight = (currentWidth / targetRatio).round();
            } else {
              // Portrait - base on height
              newHeight = currentHeight;
              newWidth = (currentHeight * targetRatio).round();
            }

            // Round to nearest 32 (required by most models) or 8 (for Hunyuan)
            int roundTo32(int x) => ((x / 32).round() * 32).clamp(32, 2048);
            int roundTo8(int x) => ((x / 8).round() * 8).clamp(8, 2048);

            // Model-specific handling for aspect ratio
            if (currentModelId == 'dreamid') {
              // DreamID uses "size" parameter in format "width*height" (string)
              final finalWidth = roundTo32(newWidth);
              final finalHeight = roundTo32(newHeight);
              resolvedParams["size"] = "$finalWidth*$finalHeight";
              // Remove height/width if they exist (DreamID doesn't use them)
              resolvedParams.remove("width");
              resolvedParams.remove("height");
              debugPrint(
                  "🎬 DreamID: aspect ratio $selectedRatio → size=$finalWidth*$finalHeight");
            } else if (currentModelId == 'hunyan15_480p_i2v_step_distilled' ||
                currentModelId == 'hunyan15_480p_t2v_distilled') {
              // Hunyuan models require dimensions rounded to 8
              resolvedParams["width"] = roundTo8(newWidth);
              resolvedParams["height"] = roundTo8(newHeight);
              debugPrint(
                  "🎬 Hunyuan: aspect ratio $selectedRatio → ${roundTo8(newWidth)}x${roundTo8(newHeight)}");
            } else if (currentModelId == 'ltx2_3_t2v') {
              // Create Video: honor aspect ratio but never exceed 720p-class bounds
              final wh = _ltx23T2vPixelsForAspectRatio(selectedRatio);
              _applyLtx23T2vFloor32ToParams(resolvedParams, wh.$1, wh.$2);
              debugPrint(
                "🎬 LTX 2.3 T2V: aspect $selectedRatio → ${resolvedParams['width']}x${resolvedParams['height']} (max 720p)",
              );
            } else if (_isLtx25Model) {
              final wh = _ltx25PixelsForAspectRatio(selectedRatio);
              _applyLtx25CanvasToParams(resolvedParams, wh.$1, wh.$2);
              debugPrint(
                "🎬 CineReal: aspect $selectedRatio → ${resolvedParams['width']}x${resolvedParams['height']}",
              );
            } else if (currentModelId.startsWith('ltx2_3')) {
              // Animate / other LTX: worker dims floored to multiples of 32
              int floorTo32(int x) => ((x / 32).floor() * 32).clamp(32, 2048);
              resolvedParams["width"] = floorTo32(newWidth);
              resolvedParams["height"] = floorTo32(newHeight);
              debugPrint(
                "🎬 LTX 2.3: aspect ratio $selectedRatio → ${resolvedParams['width']}x${resolvedParams['height']}",
              );
            } else if (_isMinimaxH3Model) {
              resolvedParams.remove("width");
              resolvedParams.remove("height");
              resolvedParams["aspect_ratio"] =
                  _kH3AspectSelectorLabels[selectedRatio] ?? selectedRatio;
              debugPrint(
                "🎬 Cinemotion Pro: aspect $selectedRatio → ${resolvedParams['aspect_ratio']}",
              );
            } else {
              // Fastwan and other models use height and width (integers, rounded to 32)
              resolvedParams["width"] = roundTo32(newWidth);
              resolvedParams["height"] = roundTo32(newHeight);
              debugPrint(
                  "📐 Model $currentModelId: aspect ratio $selectedRatio → ${roundTo32(newWidth)}x${roundTo32(newHeight)}");
            }
          }
        }

        // --- Add outpaint-specific params ---
        // IMPORTANT: For outpaint tools, we need to set alignment and aspect_ratio in base params
        // In bulk mode, per-image configs in bulk_outpaint_configs will override these defaults
        final bool isBulkEditEnabled = _advancedSettings.bulkEditEnabled &&
            _hasBulkInput &&
            canUseBulkEdit();

        if (_isOutpaint) {
          // Custom mode params (only for single mode, bulk mode uses bulk_outpaint_configs)
          if (!isBulkEditEnabled) {
            // Single mode: set alignment and aspect_ratio in base params
            resolvedParams["alignment"] = _inputs["alignment"] ?? "Middle";
            resolvedParams["aspect_ratio"] = _inputs["aspect_ratio"] ?? "1:1";

            final bool isCustomMode = _inputs["is_custom"] == "true";
            if (isCustomMode) {
              resolvedParams["is_custom_mode"] = true;
              resolvedParams["custom_scale"] =
                  double.tryParse(_inputs["custom_scale"] ?? "0.7") ?? 0.7;
              resolvedParams["norm_offset_x"] =
                  double.tryParse(_inputs["norm_offset_x"] ?? "0") ?? 0.0;
              resolvedParams["norm_offset_y"] =
                  double.tryParse(_inputs["norm_offset_y"] ?? "0") ?? 0.0;
              // Canvas and image dimensions for backend calculation
              resolvedParams["canvas_width"] =
                  double.tryParse(_inputs["canvas_width"] ?? "0");
              resolvedParams["canvas_height"] =
                  double.tryParse(_inputs["canvas_height"] ?? "0");
              resolvedParams["image_width"] =
                  double.tryParse(_inputs["image_width"] ?? "0");
              resolvedParams["image_height"] =
                  double.tryParse(_inputs["image_height"] ?? "0");
              resolvedParams["image_left"] =
                  double.tryParse(_inputs["image_left"] ?? "0");
              resolvedParams["image_top"] =
                  double.tryParse(_inputs["image_top"] ?? "0");
            }

            debugPrint(
                "🖼️ Outpaint params (single): alignment=${resolvedParams["alignment"]}, "
                "aspect=${resolvedParams["aspect_ratio"]}, custom=$isCustomMode");
          } else {
            // Bulk mode: don't set alignment/aspect_ratio in base params
            // They will be provided per-image in bulk_outpaint_configs
            debugPrint(
                "🖼️ Outpaint params (bulk): ${_bulkOutpaintConfigs.length} per-image configs will be sent");
          }
        }

        // --- Build payload ---
        // Send ONE request with variations: N, server creates N jobs internally
        final modelId = _selectedModelId ?? _tool.model;

        // LoRA adapter for qwen_image_edit_2511_rapid_aio
        if (modelId == 'qwen_image_edit_2511_rapid_aio') {
          resolvedParams['lora_adapter'] = _advancedSettings.loraAdapter;
        }

        // Duration handling for video models (animate_image, create_video — not video upscaler)
        if (_tool.outputType == 'video' && !_isVideoUpscalerTool) {
          final duration =
              _clampVideoGenDurationSeconds(_advancedSettings.videoDuration);

          if (_isLtx25Model) {
            resolvedParams['duration_seconds'] = duration;
            resolvedParams.remove('duration');
            resolvedParams.remove('num_frames');
            resolvedParams.remove('frame_rate');
            resolvedParams.remove('fps');
            debugPrint('🎬 CineReal: duration_seconds=$duration');
          } else if (_isMinimaxH3Model) {
            resolvedParams['seconds'] = duration;
            resolvedParams.remove('duration');
            resolvedParams.remove('duration_seconds');
            debugPrint('🎬 Cinemotion Pro: seconds=$duration');
          } else if (modelId.startsWith('ltx2_3')) {
            // LTX 2.3 worker: frame_rate + num_frames (8k+1); no legacy duration/rife keys
            final fpsVal =
                resolvedParams['frame_rate'] ?? resolvedParams['fps'];
            final fps = (fpsVal is num) ? fpsVal.toDouble() : 24.0;
            resolvedParams['frame_rate'] = fps;
            resolvedParams.remove('fps');
            final rawFrames = (duration * fps).round();
            resolvedParams['num_frames'] = _alignLtx23NumFrames(rawFrames);
            debugPrint(
              "🎬 LTX 2.3: duration=${duration}s frame_rate=$fps num_frames=${resolvedParams['num_frames']}",
            );
          } else {
            // Add duration key for non-LTX animate/create_video models (from UI slider)
            resolvedParams['duration'] = duration;

            // Fastwan models use duration_seconds
            if (modelId == 'fastwan_21_1b' || modelId == 'fastwan_22_5b') {
              resolvedParams["duration_seconds"] = duration;
            }

            // Hunyuan models: calculate num_frames from duration and fps
            if (modelId == 'hunyan15_480p_i2v_step_distilled' ||
                modelId == 'hunyan15_480p_t2v_distilled') {
              final fps = (resolvedParams["fps"] as num?)?.toInt() ?? 24;
              final numFrames = (duration * fps).round();
              resolvedParams["num_frames"] = numFrames;
              debugPrint(
                  "🎬 Hunyuan: duration=${duration}s, fps=$fps, num_frames=$numFrames");
            }

            // DreamID: calculate frame_num from duration and fps
            if (modelId == 'dreamid') {
              final fps = (resolvedParams["sample_fps"] as num?)?.toInt() ?? 24;
              final frameNum = (duration * fps).round();
              resolvedParams["frame_num"] = frameNum;
              debugPrint(
                  "🎬 DreamID: duration=${duration}s, fps=$fps, frame_num=$frameNum");
            }
          }

          // Video upscale / RIFE (not used by LTX 2.3 worker stack)
          if (!_isVideoUpscalerTool &&
              !modelId.startsWith('ltx2_3') &&
              !_isComfyVideoWorker) {
            if (_advancedSettings.enableInterpolate) {
              final mult = migrateLegacyInterpolateStorageValue(
                _advancedSettings.interpolateFps,
              );
              final baseFps = estimatedBaseFpsForRife(
                modelId: modelId,
                modelParams: resolvedParams,
                isVideoUpscalerTool: false,
              );
              resolvedParams["enable_rife"] = true;
              resolvedParams["rife_target_fps"] = rifeTargetFpsForSubmit(
                multiplier: mult,
                baseFps: baseFps,
                forUpscalerTargetFps: false,
              );
            } else {
              resolvedParams["enable_rife"] = false;
            }

            if (_advancedSettings.enableUpscale) {
              resolvedParams["enable_upscaling"] = true;
              resolvedParams["upscale_factor"] =
                  _advancedSettings.upscaleFactor;
            } else {
              resolvedParams["enable_upscaling"] = false;
            }
          }
        }

        if (_isLtx25Model) {
          for (final k in _kLtx25WorkerOmitParams) {
            resolvedParams.remove(k);
          }
        } else if (_isMinimaxH3Model) {
          for (final k in _kH3WorkerOmitParams) {
            resolvedParams.remove(k);
          }
        } else if (modelId.startsWith('ltx2_3')) {
          for (final k in _kLtx25WorkerOmitParams) {
            resolvedParams.remove(k);
          }
          // LTX 2.3: spatial 2× upsampler (not Real-ESRGAN/RIFE).
          if (_tool.outputType == 'video' && !_isVideoUpscalerTool) {
            if (_advancedSettings.enableUpscale) {
              resolvedParams['use_spatial_upsampler'] = true;
              resolvedParams['offload'] = 'model';
              resolvedParams['stage2_offload'] = 'sequential';
            } else {
              resolvedParams['use_spatial_upsampler'] = false;
              resolvedParams['offload'] = 'model';
              resolvedParams.remove('stage2_offload');
            }
          }
        }

        // Video upscaler tool: map Additional Settings directly to backend params
        if (_isVideoUpscalerTool) {
          resolvedParams['enable_interpolation'] =
              _advancedSettings.enableInterpolate;
          final mult = migrateLegacyInterpolateStorageValue(
            _advancedSettings.interpolateFps,
          );
          final baseFps = estimatedBaseFpsForRife(
            modelId: modelId,
            modelParams: resolvedParams,
            isVideoUpscalerTool: true,
          );
          resolvedParams['target_fps'] = _advancedSettings.enableInterpolate
              ? rifeTargetFpsForSubmit(
                  multiplier: mult,
                  baseFps: baseFps,
                  forUpscalerTargetFps: true,
                )
              : 30;
          resolvedParams['enable_upscaling'] = true;
          resolvedParams['upscale_factor'] = _advancedSettings.upscaleFactor;
          // User should not control this; keep deterministic backend behavior.
          resolvedParams['postprocess_interpolate_first'] = false;

          // Add video duration for backend cost calculation
          if (_inputVideoDuration != null) {
            // Get maxDuration from tool_config.json (default to 2 minutes = 120 seconds)
            final modelId = _selectedModelId ?? _tool.model;
            final modelData = _tool.models?.firstWhere(
                  (m) => m['id'] == modelId,
                  orElse: () => <String, dynamic>{},
                ) ??
                <String, dynamic>{};
            final maxDurationSeconds =
                (modelData['maxDuration'] as int?) ?? 120;
            final maxDuration = Duration(seconds: maxDurationSeconds);

            // Send actual video duration in seconds (capped at maxDuration)
            final actualDuration = _inputVideoDuration! > maxDuration
                ? maxDuration
                : _inputVideoDuration!;
            resolvedParams['video_duration'] = actualDuration.inSeconds;

            // Also send max_duration_seconds if video was trimmed
            if (_inputVideoDuration! > maxDuration) {
              resolvedParams['max_duration_seconds'] = maxDuration.inSeconds;
            }
          }
        }

        // Server enforces max variations: 2 for non-VIP, 4 for VIP
        // Client-side clamp is just for preview - server is authoritative
        final int requestedVariations = _isMusicTool
            ? 1
            : _advancedSettings.variations.clamp(1, getMaxVariations());

        // Check if bulk edit is enabled
        final bool isBulkEdit = _advancedSettings.bulkEditEnabled &&
            _hasBulkInput &&
            canUseBulkEdit();

        // enhance_prompt is a top-level SubmitRequest field (not params).

        // Optional external route switch (forwarded as params.use_external_api).
        final bool? useExternalApi = _currentModelUseExternalApi;
        if (useExternalApi != null) {
          resolvedParams['use_external_api'] = useExternalApi;
        }
        if (_tool.capabilityId == 'edit_image' &&
            (_selectedModelId ?? _tool.model) != 'qwen2_1_i2i' &&
            (_selectedModelId ?? _tool.model) !=
                'flux2_klein_9b_edit') {
          resolvedParams['aspect_ratio'] = 'auto';
        }
        if (_upscaleEnabled && _allowsOutputUpscale) {
          resolvedParams['scale_factor'] = 2;
          resolvedParams['upscale_model'] = _selectedOutputUpscaleId;
        } else if (_allowsOutputUpscale || _isUpscalerTool) {
          resolvedParams.remove('scale_factor');
          resolvedParams.remove('upscale_model');
          resolvedParams.remove('scale_image');
        }
        _keepListedParams(resolvedParams);

        final filteredRootParams = filterSubmitRootParams(rootParams);

        // Root payload only — `params` attached after R2 upload as `paramsForSubmit`
        // (server SubmitRequest.extra=forbid; embedded media in params is rejected).
        final basePayload = <String, dynamic>{
          ...filteredRootParams,
          "model": _workerModelIdForSubmit,
          "fcm_token": fcmToken,
          "variations": requestedVariations,
          "is_bulk": isBulkEdit,
          "enhance_prompt":
              _isAudioTool ? false : _advancedSettings.enhancePrompt,
        };

        // Bulk (R2-only): strip single-task media keys; masks via bulk_mask_r2_keys after upload.
        if (isBulkEdit) {
          resolvedParams.remove("init_image");
          resolvedParams.remove("image");

          if (_isCineRealFlf2vMode) {
            resolvedParams.remove("first_frame_image_r2_key");
            resolvedParams.remove("last_frame_image_r2_key");
            resolvedParams.remove("first_frame_image_r2_keys");
          }

          if (_requiresMask) {
            resolvedParams.remove("mask_image");
            resolvedParams.remove("mask");
            debugPrint(
                "🎭 Removed single mask_image — bulk uses bulk_mask_r2_keys");
          }

          if (_isOutpaint) {
            resolvedParams.remove("alignment");
            resolvedParams.remove("aspect_ratio");
            resolvedParams.remove("is_custom_mode");
            resolvedParams.remove("custom_scale");
            resolvedParams.remove("norm_offset_x");
            resolvedParams.remove("norm_offset_y");
            resolvedParams.remove("canvas_width");
            resolvedParams.remove("canvas_height");
            resolvedParams.remove("image_width");
            resolvedParams.remove("image_height");
            resolvedParams.remove("image_left");
            resolvedParams.remove("image_top");
            debugPrint(
                "🖼️ Removed outpaint params from base — bulk_outpaint_configs per image");
          }

          debugPrint(
            "📦 Bulk edit: ${_bulkImageJobs.length} task(s), "
            "multi-init=$_bulkSupportsMultiInitPerJob (R2 keys only)",
          );

          if (_isOutpaint && _bulkOutpaintConfigs.isNotEmpty) {
            final List<Map<String, String>?> configs = [];
            for (int i = 0; i < _bulkImageJobs.length; i++) {
              if (i < _bulkOutpaintConfigs.length &&
                  _bulkOutpaintConfigs[i] != null) {
                // Create a copy of the config and filter based on is_custom mode
                final Map<String, String> config =
                    Map<String, String>.from(_bulkOutpaintConfigs[i]!);
                final isCustom = config["is_custom"] ?? "false";
                final isCustomMode = config["is_custom_mode"] ?? "false";
                final bool isActuallyCustom =
                    (isCustom == "true" || isCustom == "True") ||
                        (isCustomMode == "true" || isCustomMode == "True");

                // Only keep is_custom/is_custom_mode if it's true
                if (!isActuallyCustom) {
                  config.remove("is_custom");
                  config.remove("is_custom_mode");

                  // Remove custom positioning params when not in custom mode
                  config.remove("norm_offset_x");
                  config.remove("norm_offset_y");
                  config.remove("offset_x");
                  config.remove("offset_y");
                  config.remove("canvas_width");
                  config.remove("canvas_height");
                  config.remove("fitted_width");
                  config.remove("fitted_height");
                  config.remove("image_width");
                  config.remove("image_height");
                  config.remove("image_left");
                  config.remove("image_top");
                  config.remove("custom_scale");
                } else {
                  // In custom mode, ensure is_custom_mode is set correctly
                  if (isCustom == "true" || isCustom == "True") {
                    config["is_custom"] = "true";
                  }
                  if (isCustomMode == "true" || isCustomMode == "True") {
                    config["is_custom_mode"] = "true";
                  }
                }

                configs.add(config);
              } else {
                configs.add(null);
              }
            }
            basePayload["bulk_outpaint_configs"] = configs;
            debugPrint(
                "🖼️ Added ${configs.where((c) => c != null).length} outpaint configs for bulk edit");
          }
        }

        debugPrint(
          "🎯 Using model: $modelId (submit=$_workerModelIdForSubmit)",
        );
        debugPrint(
          "🔧 Advanced settings - enhance: ${_advancedSettings.enhancePrompt}, "
          "variations: $requestedVariations, bulk: $isBulkEdit, "
          "cfg_scale: 1.0, aspect: ${_advancedSettings.aspectRatio}",
        );

        // --- Firebase Auth ---
        final firebaseToken = await _authService.getIdToken();
        if (firebaseToken == null) {
          throw Exception("Not authenticated. Please sign in first.");
        }

        final headers = {
          "Content-Type": "application/json",
          "Authorization": "Bearer $firebaseToken",
        };

        // ─── R2 presigned upload (required; server rejects embedded media in params) ───
        final paramsForSubmit = Map<String, dynamic>.from(resolvedParams);
        paramsForSubmit.remove("images");
        List<dynamic>? bulkGroupedImageR2Keys;
        var skipMainMultipartSubmit = false;
        dynamic cinerealBulkSequentialResponse;

        dialogMessage.value =
            "Uploading media…\nPlease be patient if your internet connection is slow.";

        if (!isBulkEdit) {
          Uint8List? qwenMaskForUpload;
          final imageInputDef = _tool.inputs.firstWhere(
              (i) => i["type"] == "image",
              orElse: () => <String, dynamic>{});
          final String? imageInputId =
              imageInputDef.isNotEmpty ? imageInputDef["id"] as String? : null;

          if (imageInputId != null &&
              (_elementShouldRender(Map<String, dynamic>.from(imageInputDef)) ||
                  (_isSunoV6 &&
                      _musicEasy &&
                      !_sunoSounds &&
                      imageInputId == 'cover_image' &&
                      _filledMedia('cover_image')))) {
            final rawImageData = _inputs[imageInputId];
            List<Uint8List>? rawImageList;
            if (rawImageData is List &&
                rawImageData.isNotEmpty &&
                rawImageData.first is Uint8List) {
              rawImageList = rawImageData.cast<Uint8List>().toList();
            } else if (rawImageData is Uint8List) {
              rawImageList = [rawImageData];
            }

            if (rawImageList != null && rawImageList.isNotEmpty) {
              if (_tool.capabilityId == 'edit_image' &&
                  (_selectedModelId ?? _tool.model) == 'qwen2_1_i2i') {
                final qwenResolution = _qwenResolution;
                paramsForSubmit['resolution'] = qwenResolution;
                final fit = fitImageToQwenRatio(
                  rawImageList.first,
                  resolution: qwenResolution,
                );
                if (fit != null) {
                  final fitted = <Uint8List>[fit.image];
                  for (var i = 1; i < rawImageList.length; i++) {
                    fitted.add(
                      fitBytesToAspect(
                            rawImageList[i],
                            fit.aspectRatio,
                            resolution: qwenResolution,
                          ) ??
                          rawImageList[i],
                    );
                  }
                  rawImageList = fitted;
                  paramsForSubmit['aspect_ratio'] = fit.aspectRatio;
                }
                final mask = _inputs['mask_image'];
                if (mask is Uint8List && rawImageList.length == 1) {
                  qwenMaskForUpload = qwenLocalEditMask(
                    mask,
                    width: fit?.width,
                    height: fit?.height,
                  );
                }
                final wantsTransparent = _inputs['background'] == 'transparent';
                paramsForSubmit['background'] =
                    wantsTransparent && qwenMaskForUpload == null
                        ? 'transparent'
                        : 'opaque';
                paramsForSubmit['output_format'] = 'png';
              }
              if (_tool.capabilityId == 'expand_scene') {
                final modelId = _selectedModelId ?? _tool.model;
                final runwareExpand = modelId == 'juggernaut_lightning_expand' ||
                    modelId == 'z_image_turbo_expand';
                if (runwareExpand) {
                  final plan = buildRunwareOutpaint(rawImageList.first, _inputs);
                  if (plan.error != null || plan.image == null) {
                    throw Exception(
                      plan.error ?? 'Could not prepare that image to expand.',
                    );
                  }
                  rawImageList = [plan.image!];
                  paramsForSubmit
                    ..['outpaint_top'] = plan.top
                    ..['outpaint_bottom'] = plan.bottom
                    ..['outpaint_left'] = plan.left
                    ..['outpaint_right'] = plan.right
                    ..['outpaint_blur'] = 16
                    ..['width'] = plan.width
                    ..['height'] = plan.height
                    ..remove('aspect_ratio');
                } else {
                final modelId = _selectedModelId ?? _tool.model;
                if (modelId == 'grok_imagine_edit') {
                  const allowed = {
                    '1:1',
                    '2:3',
                    '3:2',
                    '16:9',
                    '9:16',
                  };
                  final raw = _inputs['aspect_ratio']?.toString() ?? '';
                  if (raw.isNotEmpty && !allowed.contains(raw)) {
                    const snap = {
                      '4:3': '3:2',
                      '3:4': '2:3',
                      '21:9': '16:9',
                      '9:21': '9:16',
                    };
                    _inputs['aspect_ratio'] = snap[raw] ?? '16:9';
                  }
                }
                final built = buildExpandPair(rawImageList.first, _inputs);
                if (built != null) {
                  rawImageList = [built.canvas];
                  if (modelId == 'qwen2_1_i2i') {
                    _inputs['mask_image'] = built.mask;
                  }
                  final existing =
                      (basePayload['prompt'] as String?)?.trim() ?? '';
                  const instruction =
                      'Outpaint the image: replace the flat gray border with a seamless continuation of the scene. Keep the existing picture unchanged.';
                  basePayload['prompt'] = existing.isEmpty
                      ? instruction
                      : '$instruction $existing';
                  final ratio = _inputs['aspect_ratio']?.toString();
                  if (ratio != null &&
                      ratio.isNotEmpty &&
                      ratio.toLowerCase() != 'custom') {
                    paramsForSubmit['aspect_ratio'] = ratio;
                  }
                }
                }
              }
              final imageKeys = await MediaUploadService.uploadMediaBatch(
                files: rawImageList,
                mediaType: "image",
                authToken: firebaseToken,
              );
              if (imageKeys == null ||
                  imageKeys.length != rawImageList.length) {
                throw Exception(
                  "Could not upload images to cloud storage. Check your connection and try again.",
                );
              }
              basePayload.remove("input_image_r2_keys");
              for (final k in kForbiddenMediaParamKeys) {
                paramsForSubmit.remove(k);
              }
              if (imageKeys.length == 1) {
                if (_isCineRealFlf2vMode) {
                  paramsForSubmit['first_frame_image_r2_key'] = imageKeys.first;
                } else {
                  paramsForSubmit["init_image_r2_key"] = imageKeys.first;
                }
              } else {
                if (_isCineRealFlf2vMode) {
                  paramsForSubmit['first_frame_image_r2_key'] = imageKeys.first;
                  paramsForSubmit['first_frame_image_r2_keys'] = imageKeys;
                } else {
                  paramsForSubmit["init_image_r2_keys"] = imageKeys;
                }
              }
              if (_isSunoV6) {
                paramsForSubmit['init_image_r2_keys'] = imageKeys;
                paramsForSubmit.remove('init_image_r2_key');
                basePayload['input_image_r2_keys'] = imageKeys;
              }
              debugPrint("☁️ R2: uploaded ${imageKeys.length} init image(s)");
            }
          }

          if (_isAnimateImageTool &&
              (_isCineRealFlf2vMode ||
                  _isMinimaxH3Model ||
                  (_selectedModelId ?? _tool.model) ==
                      _kLegacyWanI2vModelId)) {
            final lastRaw = _inputs['last_frame_image'];
            List<Uint8List>? lastList;
            if (lastRaw is List &&
                lastRaw.isNotEmpty &&
                lastRaw.first is Uint8List) {
              lastList = lastRaw.cast<Uint8List>().toList();
            } else if (lastRaw is Uint8List) {
              lastList = [lastRaw];
            }
            if (lastList != null && lastList.isNotEmpty) {
              final lastKeys = await MediaUploadService.uploadMediaBatch(
                files: lastList,
                mediaType: "image",
                authToken: firebaseToken,
              );
              if (lastKeys == null || lastKeys.length != lastList.length) {
                throw Exception(
                  "Could not upload last-frame image to cloud storage. Check your connection and try again.",
                );
              }
              paramsForSubmit['last_frame_image_r2_key'] = lastKeys.first;
              debugPrint("☁️ R2: uploaded last-frame image");
            }
          }

          final rawMask = qwenMaskForUpload ?? _inputs["mask_image"];
          final photos = _inputs['init_image'];
          final photoCount = photos is List ? photos.length : (photos is Uint8List ? 1 : 0);
          final qwenBrush = _tool.capabilityId == 'edit_image' && (_selectedModelId ?? _tool.model) == 'qwen2_1_i2i';
          final sendMask = rawMask is Uint8List && (!qwenBrush || photoCount == 1);
          if (sendMask) {
            final maskKeys = await MediaUploadService.uploadMediaBatch(
              files: [rawMask],
              mediaType: "image",
              authToken: firebaseToken,
            );
            if (maskKeys == null || maskKeys.isEmpty) {
              throw Exception(
                "Could not upload mask to cloud storage. Check your connection and try again.",
              );
            }
            basePayload["mask_image_r2_key"] = maskKeys.first;
            paramsForSubmit.remove("mask_image");
            paramsForSubmit.remove("mask");
            debugPrint("☁️ R2: uploaded mask image");
          }
        } else {
          if (_hasBulkInput) {
            final flatBytes = _bulkImageJobs.expand((e) => e).toList();
            if (flatBytes.isEmpty) {
              throw Exception("No images selected for bulk edit.");
            }
            final bulkImageKeys = await MediaUploadService.uploadMediaBatch(
              files: flatBytes,
              mediaType: "image",
              authToken: firebaseToken,
            );
            if (bulkImageKeys == null ||
                bulkImageKeys.length != flatBytes.length) {
              throw Exception(
                "Could not upload bulk images to cloud storage. Check your connection and try again.",
              );
            }
            var off = 0;
            bulkGroupedImageR2Keys = <dynamic>[];
            for (final job in _bulkImageJobs) {
              final n = job.length;
              if (n == 1) {
                bulkGroupedImageR2Keys.add(bulkImageKeys[off]);
              } else {
                bulkGroupedImageR2Keys.add(bulkImageKeys.sublist(off, off + n));
              }
              off += n;
            }
            basePayload["input_image_r2_keys"] = bulkGroupedImageR2Keys;
            for (final k in kForbiddenMediaParamKeys) {
              paramsForSubmit.remove(k);
            }
            debugPrint(
              "☁️ R2: uploaded ${bulkImageKeys.length} image(s) in ${bulkGroupedImageR2Keys.length} bulk task(s)",
            );
          }

          if (_requiresMask && _bulkMasks.isNotEmpty) {
            final bulkMaskKeys =
                await MediaUploadService.uploadNullableMediaBatch(
              files: _bulkMasks,
              mediaType: "image",
              authToken: firebaseToken,
            );
            if (bulkMaskKeys == null) {
              throw Exception(
                "Could not upload bulk masks to cloud storage. Check your connection and try again.",
              );
            }
            basePayload["bulk_mask_r2_keys"] = bulkMaskKeys;
            debugPrint("☁️ R2: uploaded bulk masks");
          }
        }

        final videoInputDef = _tool.inputs.firstWhere(
            (i) => i["type"] == "video",
            orElse: () => <String, dynamic>{});
        if (videoInputDef.isNotEmpty &&
            (_elementShouldRender(Map<String, dynamic>.from(videoInputDef)) ||
                (_isSunoV6 &&
                    _musicEasy &&
                    !_sunoSounds &&
                    videoInputDef['id'] == 'clip' &&
                    _filledMedia('clip'))) &&
            !(isBulkEdit &&
                _isCineRealAnimateModel &&
                _bulkCineRealAnyRefVideoBytes())) {
          final videoId = videoInputDef["id"] as String?;
          if (videoId != null) {
            final rawVideoBytes = _inputs["${videoId}_bytes"] as Uint8List?;
            if (rawVideoBytes != null && rawVideoBytes.isNotEmpty) {
              final videoKeys = await MediaUploadService.uploadMediaBatch(
                files: [rawVideoBytes],
                mediaType: "video",
                authToken: firebaseToken,
              );
              if (videoKeys == null || videoKeys.isEmpty) {
                throw Exception(
                  "Could not upload video to cloud storage. Check your connection and try again.",
                );
              }
              basePayload["input_video_r2_key"] = videoKeys.first;
              if (_isSunoV6) {
                paramsForSubmit['input_video_r2_key'] = videoKeys.first;
              }
              for (final k in ["init_video", "input_video", "ref_video"]) {
                paramsForSubmit.remove(k);
              }
              debugPrint("☁️ R2: uploaded video");
            }
          }
        }

        // ─── Phase 2 scaffolds: audio_upload / file_upload → R2 upload ───
        // For each tool_config input whose type is audio_upload or file_upload
        // and whose bytes are loaded into _inputs[id], request a presigned URL
        // (reusing the "image" media-type bucket) and PUT the bytes with the
        // correct MIME type recorded at pick-time. The resulting R2 key is
        // written under "${id}_r2_key" in basePayload and also mirrored in
        // paramsForSubmit so the backend can pick it up via its template.
        for (final inputDef in _tool.inputs) {
          final t = inputDef["type"];
          if (t != "audio_upload" && t != "file_upload") continue;
          final id = inputDef["id"] as String?;
          if (id == null) continue;
          if (!_elementShouldRender(Map<String, dynamic>.from(inputDef)) &&
              !(_isSunoV6 &&
                  _musicEasy &&
                  !_sunoSounds &&
                  id == 'reference_audio' &&
                  _filledMedia('reference_audio'))) {
            continue;
          }
          if (id == 'source_audio' && !_musicUsesAudio) continue;
          final rawBytes = _inputs[id];
          if (rawBytes is! Uint8List || rawBytes.isEmpty) continue;
          final mime = (_inputs["${id}_mime"] as String?) ??
              (t == "audio_upload" ? "audio/mpeg" : "application/octet-stream");
          final urls = await MediaUploadService.getMediaUploadUrls(
            count: 1,
            mediaType: "image",
            authToken: firebaseToken,
          );
          if (urls == null || urls.isEmpty) {
            throw Exception(
              "Could not reserve cloud-storage slot for $id. Check your connection and try again.",
            );
          }
          final ok = await MediaUploadService.uploadToR2(
            urls.first.uploadUrl,
            rawBytes,
            contentType: mime,
          );
          if (!ok) {
            throw Exception(
              "Could not upload $id to cloud storage. Check your connection and try again.",
            );
          }
          paramsForSubmit["${id}_r2_key"] = urls.first.r2Key;
          // Never ship raw bytes in params.
          paramsForSubmit.remove(id);
          debugPrint("☁️ R2: uploaded $id ($t, ${rawBytes.length} bytes)");
        }
        if (_sunoExtend) {
          final key = paramsForSubmit['extend_audio_r2_key'];
          if (key is String && key.isNotEmpty) {
            paramsForSubmit['reference_audio_r2_key'] = key;
          }
        }
        if (_sunoMashup) {
          final first = paramsForSubmit['mashup_a_r2_key'];
          final second = paramsForSubmit['mashup_b_r2_key'];
          if (first is String && second is String) {
            paramsForSubmit['audio_r2_keys'] = [first, second];
          }
        }

        stripForbiddenMediaFromParams(paramsForSubmit);

        if (isBulkEdit &&
            _isCineRealAnimateModel &&
            _supportsBulkImageEdit &&
            bulkGroupedImageR2Keys != null &&
            _bulkCineRealAnyRefVideoBytes()) {
          cinerealBulkSequentialResponse =
              await _submitCineRealBulkSequentialWithRefVideos(
            controllerUrl: controllerUrl,
            headers: headers,
            firebaseToken: firebaseToken,
            filteredRootParams: filteredRootParams,
            paramsTemplate: Map<String, dynamic>.from(paramsForSubmit),
            groupedKeys: bulkGroupedImageR2Keys,
            requestedVariations: requestedVariations,
            maxRetries: maxRetries,
          );
          skipMainMultipartSubmit = true;
        }

        if (isBulkEdit &&
            _hasBulkInput &&
            basePayload["input_image_r2_keys"] == null) {
          throw Exception(
            "Bulk edit requires uploading images to cloud storage. Please try again.",
          );
        }

        dialogMessage.value =
            "Hang tight while we queue and process your request.\nAvoid pressing back or closing the app.";

        // On-device inpaint: same R2 contract as server dispatch; processing stays local.
        if (_isOnDeviceInpaintTool) {
          final onDevicePayload = <String, dynamic>{
            ...basePayload,
            "params": paramsForSubmit,
            "on_device": true,
          };

          final submitResp = await http
              .post(
                Uri.parse('$controllerUrl/submit'),
                headers: headers,
                body: jsonEncode(onDevicePayload),
              )
              .timeout(const Duration(seconds: 60));
          if (submitResp.statusCode != 200) {
            throw Exception(
                "On-device submit failed: ${submitResp.statusCode} ${submitResp.body}");
          }

          final data = jsonDecode(submitResp.body);
          final bool promptWasEnhanced = data["prompt_enhanced"] ?? false;
          final String? enhancedPromptFromServer = data["enhanced_prompt"];
          final List<String> jobIds = [];
          if (data["job_ids"] != null && data["job_ids"] is List) {
            jobIds.addAll((data["job_ids"] as List).map((e) => e.toString()));
          } else if (data["job_id"] != null) {
            jobIds.add(data["job_id"].toString());
          }
          if (jobIds.isEmpty) {
            throw Exception("No job IDs returned for on-device request");
          }

          final saved = await _saveLaunchMedia(isBulkEdit: isBulkEdit);
          final String? originalPrompt = _typedPrompt;
          final List<JobModel> localJobs = [];
          final String? onDeviceBatchId = jobIds.length > 1
              ? 'batch_${DateTime.now().microsecondsSinceEpoch}'
              : null;
          final perJobCredits = jobIds.isEmpty
              ? _calculateTotalCost()
              : (_calculateTotalCost() / jobIds.length).round();
          for (int i = 0; i < jobIds.length; i++) {
            final imageIndex = isBulkEdit ? (i ~/ requestedVariations) : 0;
            final inputPath = isBulkEdit
                ? (imageIndex < saved.bulkPrimaryPaths.length
                    ? saved.bulkPrimaryPaths[imageIndex]
                    : null)
                : saved.primaryPath;
            final job = JobModel(
              jobId: jobIds[i],
              title: await generateFriendlyJobName(),
              model: _selectedModelId ?? _tool.model,
              outputType: _tool.outputType,
              status: 'processing',
              inputImagePath: inputPath,
              variations: 1,
              allCompleted: false,
              enhancedPrompt: enhancedPromptFromServer,
              promptEnhanced: promptWasEnhanced,
              originalPrompt: originalPrompt,
              templateId: widget.launchTemplateId,
              templateTitle: widget.launchTemplateTitle,
              capabilityId: _tool.capabilityId,
              settingsSnapshot: _snapshotForSaved(saved, imageIndex),
              creditsCharged: perJobCredits,
              parentJobId: widget.sourceJobId,
              batchId: onDeviceBatchId,
            );
            localJobs.add(job);
            await addOrUpdateJob(job);
          }

          final List<Uint8List> bulkImagesSnapshot =
              _bulkImageJobs.map((j) => j.first).toList();
          final List<Uint8List?> bulkMasksSnapshot = List<Uint8List?>.generate(
            bulkImagesSnapshot.length,
            (i) => i < _bulkMasks.length ? _bulkMasks[i] : null,
          );
          final Uint8List? singleImageSnapshot =
              isBulkEdit ? null : await _extractSingleInputImageBytes();
          final Uint8List? singleMaskSnapshot =
              isBulkEdit ? null : (_inputs["mask_image"] as Uint8List?);

          // Do processing in background so UI redirects immediately.
          unawaited(
            _processOnDeviceJobsInBackground(
              localJobs: localJobs,
              isBulkEdit: isBulkEdit,
              requestedVariations: requestedVariations,
              headers: headers,
              bulkImages: bulkImagesSnapshot,
              bulkMasks: bulkMasksSnapshot,
              singleImage: singleImageSnapshot,
              singleMask: singleMaskSnapshot,
            ),
          );

          recordBatchSubmission(localJobs.length);
          dismissDialog();
          _isSubmittingJob = false;
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ResultManagerPage()),
            );
          }
          return;
        }

        final saved = await _saveLaunchMedia(isBulkEdit: isBulkEdit && _hasBulkInput);
        final String? originalPrompt = _typedPrompt;
        final List<JobModel> createdJobs = [];

        debugPrint(
          "🖼️ Submit variations=$requestedVariations "
          "r2_bulk=${basePayload['input_image_r2_keys'] != null} "
          "init_r2_key=${paramsForSubmit['init_image_r2_key'] != null} "
          "init_r2_keys=${paramsForSubmit['init_image_r2_keys'] != null}",
        );

        // Submit ONE request - server creates N jobs internally (or sequential
        // CineReal bulk when any clip uses a per-task reference video).
        dynamic data;
        if (!skipMainMultipartSubmit) {
          for (int submitAttempt = 1;
              submitAttempt <= maxRetries;
              submitAttempt++) {
            debugPrint(
              "🚀 Submitting job (variations=$requestedVariations, attempt $submitAttempt/$maxRetries)",
            );
            final resp = await http
                .post(
                  Uri.parse('$controllerUrl/submit'),
                  headers: headers,
                  body: jsonEncode(<String, dynamic>{
                    ...basePayload,
                    "params": paramsForSubmit,
                  }),
                )
                .timeout(const Duration(seconds: 60));

            if (resp.statusCode == 200) {
              data = jsonDecode(resp.body);
              break;
            }

            debugPrint("❌ Submit failed: ${resp.statusCode} ${resp.body}");
            if (submitAttempt < maxRetries) {
              await Future.delayed(const Duration(seconds: 2));
            }
          }
        } else {
          data = cinerealBulkSequentialResponse;
        }

        if (data == null) {
          throw Exception("Failed to submit job after $maxRetries retries");
        }

        // Parse response - server may return single job_id or array of job_ids
        final bool promptWasEnhanced = data["prompt_enhanced"] ?? false;
        final String? enhancedPromptFromServer = data["enhanced_prompt"];

        // Handle both single and multiple job_ids from response
        final List<String> jobIds = [];
        final List<String?> downloadUrls = [];

        if (data["job_ids"] != null && data["job_ids"] is List) {
          // Server returned multiple job_ids for variations
          jobIds.addAll((data["job_ids"] as List).map((e) => e.toString()));
          if (data["download_urls"] != null && data["download_urls"] is List) {
            downloadUrls.addAll(
                (data["download_urls"] as List).map((e) => e?.toString()));
          }
        } else if (data["job_id"] != null) {
          // Single job_id (backwards compatibility or variations=1)
          jobIds.add(data["job_id"].toString());
          downloadUrls.add(data["download_url"]?.toString() ??
              data["downloadUrl"]?.toString());
        }

        if (jobIds.isEmpty) {
          throw Exception("No job_id(s) returned from submit");
        }

        debugPrint("✅ Server created ${jobIds.length} job(s): $jobIds");

        final String? submitBatchId = jobIds.length > 1
            ? 'batch_${DateTime.now().microsecondsSinceEpoch}'
            : null;
        final perJobCredits =
            jobIds.isEmpty ? totalCost : (totalCost / jobIds.length).round();

        // Create a JobModel for each job_id returned
        // For bulk edit: jobs are ordered as [img1_var1, img1_var2, ..., img2_var1, img2_var2, ...]
        for (int i = 0; i < jobIds.length; i++) {
          final jobId = jobIds[i];
          final downloadUrl = i < downloadUrls.length ? downloadUrls[i] : null;

          final imageIndex = isBulkEdit ? i ~/ requestedVariations : 0;
          final String? jobInputImagePath = isBulkEdit
              ? (imageIndex < saved.bulkPrimaryPaths.length
                  ? saved.bulkPrimaryPaths[imageIndex]
                  : null)
              : saved.primaryPath;

          final String title = await generateFriendlyJobName();
          // Use selected model ID if available, otherwise fall back to config default
          final actualModelId = _selectedModelId ?? _tool.model;
          final newJob = JobModel(
            jobId: jobId,
            title: title,
            model: actualModelId,
            outputType: _tool.outputType,
            downloadUrl: downloadUrl,
            status: 'processing',
            inputImagePath: jobInputImagePath,
            variations: 1, // Each job is a single variation
            allCompleted: false,
            enhancedPrompt: enhancedPromptFromServer,
            promptEnhanced: promptWasEnhanced,
            originalPrompt: originalPrompt,
            templateId: widget.launchTemplateId,
            templateTitle: widget.launchTemplateTitle,
            capabilityId: _tool.capabilityId,
            settingsSnapshot: _snapshotForSaved(saved, imageIndex),
            creditsCharged: perJobCredits,
            parentJobId: widget.sourceJobId,
            batchId: submitBatchId,
          );

          createdJobs.add(newJob);

          // ✅ Add job to notifier IMMEDIATELY so FCM handlers find it
          // This prevents ghost records from being created by FCM race conditions
          await addOrUpdateJob(newJob);

          final jobContext = {
            "title": _tool.title,
            "model": _tool.model,
            "inputs": _tool.inputs,
            "params": _tool.params,
            "outputType": _tool.outputType,
          };
          await prefs.setString("notify_job_$jobId", jsonEncode(jobContext));
        }

        // Jobs are already persisted via addOrUpdateJob - no need for redundant saves

        // Record batch submission for rate limiting cooldown
        recordBatchSubmission(createdJobs.length);

        // Credits are deducted server-side during job processing
        await UserService().refreshCredits();

        dismissDialog();

        _isSubmittingJob = false;
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ResultManagerPage()),
          );
        }

        debugPrint(
            "✅ Submitted 1 request, created ${createdJobs.length} job(s) for $requestedVariations variation(s)");
        return;
      } catch (e) {
        debugPrint("❌ Job submission attempt $attempt failed: $e");
        final raw = e.toString();
        final localPrep = raw.contains('too large for that shape') ||
            raw.contains('too small to expand') ||
            raw.contains('Could not read that image') ||
            raw.contains('Could not prepare that image');
        if (localPrep || attempt >= maxRetries) {
          dismissDialog();
          _isSubmittingJob = false;
          if (mounted) {
            final shown = localPrep
                ? raw.replaceFirst('Exception: ', '')
                : "Error submitting job after $maxRetries retries: $e";
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(shown)),
            );
          }
          return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    // Safety reset in case loop exits without returning
    _isSubmittingJob = false;
  }

  Future<void> _notifyOnDeviceJobStarted({
    required String jobId,
    required Map<String, String> headers,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$controllerUrl/on_device/job_started'),
            headers: headers,
            body: jsonEncode(<String, dynamic>{'job_id': jobId}),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('⚠️ on-device job_started failed for $jobId: $e');
    }
  }

  Future<void> _notifyOnDeviceJobComplete({
    required String jobId,
    required bool success,
    required Map<String, String> headers,
    String? error,
  }) async {
    try {
      await http
          .post(
            Uri.parse('$controllerUrl/on_device/job_complete'),
            headers: headers,
            body: jsonEncode(<String, dynamic>{
              'job_id': jobId,
              'success': success,
              if (error != null && error.isNotEmpty) 'error': error,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('⚠️ on-device job_complete failed for $jobId: $e');
    }
  }

  Future<Uint8List?> _extractSingleInputImageBytes() async {
    final imageInput = _tool.inputs.firstWhere(
      (i) => i["type"] == "image",
      orElse: () => <String, dynamic>{},
    );
    if (imageInput.isEmpty) return null;
    final id = imageInput["id"];
    final dat = _inputs[id];
    if (dat is List && dat.isNotEmpty && dat.first is Uint8List) {
      return dat.first as Uint8List;
    }
    if (dat is Uint8List) {
      return dat;
    }
    return null;
  }

  Future<String> _writeOnDeviceOutput(Uint8List bytes, String jobId) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/on_device_${jobId}_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<void> _processOnDeviceJobsInBackground({
    required List<JobModel> localJobs,
    required bool isBulkEdit,
    required int requestedVariations,
    required Map<String, String> headers,
    required List<Uint8List> bulkImages,
    required List<Uint8List?> bulkMasks,
    required Uint8List? singleImage,
    required Uint8List? singleMask,
  }) async {
    for (int i = 0; i < localJobs.length; i++) {
      final job = localJobs[i];
      final imageIndex = isBulkEdit ? (i ~/ requestedVariations) : 0;
      try {
        await _notifyOnDeviceJobStarted(jobId: job.jobId, headers: headers);

        final Uint8List? imageBytes = isBulkEdit
            ? (imageIndex < bulkImages.length ? bulkImages[imageIndex] : null)
            : singleImage;
        final Uint8List? maskBytes = isBulkEdit
            ? (imageIndex < bulkMasks.length ? bulkMasks[imageIndex] : null)
            : singleMask;

        if (imageBytes == null || imageBytes.isEmpty) {
          throw Exception('Input image is required for on-device erase');
        }
        if (maskBytes == null || maskBytes.isEmpty) {
          throw Exception('Mask is required for on-device erase');
        }

        final outputBytes = await OnDeviceInpaintService.inpaint(
          imageBytes: imageBytes,
          maskBytes: maskBytes,
        );
        final localPath = await _writeOnDeviceOutput(outputBytes, job.jobId);

        job.localFilePath = localPath;
        job.status = 'completed';
        job.allCompleted = true;
        await addOrUpdateJob(job);
        await _notifyOnDeviceJobComplete(
          jobId: job.jobId,
          success: true,
          headers: headers,
        );
      } catch (e, st) {
        debugPrint('❌ On-device inpaint failed for job ${job.jobId}: $e');
        debugPrintStack(stackTrace: st, label: 'On-device inpaint stack');
        job.status = 'failed';
        job.allCompleted = true;
        await addOrUpdateJob(job);
        await _notifyOnDeviceJobComplete(
          jobId: job.jobId,
          success: false,
          error: e.toString(),
          headers: headers,
        );
      }
    }

    try {
      await UserService().refreshCredits();
    } catch (e) {
      debugPrint('⚠️ Failed to refresh credits after on-device processing: $e');
    }
  }

  bool _qwenEditBrush(List<_ComposerAttachment> attachments) {
    final model = _selectedModelId ?? _tool.model;
    if (model != 'qwen2_1_i2i') return false;
    final photos = attachments.where((a) => a.ref == 'init_image' && a.kind == _ComposerAttachmentKind.image);
    return photos.length == 1;
  }

  Widget _buildEditBrushRow(ColorScheme cs, List<_ComposerAttachment> attachments) {
    final model = _selectedModelId ?? _tool.model;
    if (model != 'qwen2_1_i2i') return const SizedBox.shrink();
    final photos = attachments.where((a) => a.ref == 'init_image' && a.kind == _ComposerAttachmentKind.image).toList();
    final painted = _inputs['mask_image'] is Uint8List;
    if (photos.length != 1) {
      return Text(
        photos.length > 1
            ? 'With several photos, name each one in the prompt. Paint an area when a single photo is attached.'
            : 'Add one photo, then paint the area the prompt should change.',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35),
      );
    }
    return Row(
      children: [
        Icon(LucideIcons.brush, size: 16, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            painted ? 'An area is painted. The prompt changes only that area.' : 'Paint the area to change, then describe the edit.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13, height: 1.35),
          ),
        ),
        TextButton(
          onPressed: () async {
            final base = photos.first.thumbBytes;
            if (base == null) return;
            final mask = await _openMaskEditor(base, brushOnly: true);
            if (mask != null && mounted) {
              setState(() {
                _inputs['mask_image'] = mask;
                _inputs['background'] = 'opaque';
              });
            }
          },
          child: Text(painted ? 'Edit area' : 'Paint'),
        ),
        if (painted)
          IconButton(
            tooltip: 'Clear painted area',
            onPressed: () => setState(() => _inputs.remove('mask_image')),
            icon: Icon(LucideIcons.x, size: 16, color: cs.onSurfaceVariant),
          ),
      ],
    );
  }

  // -------- Painter (Mask Editor) --------
  Future<void> _showMaskLayout(Uint8List photo, Uint8List mask) async {
    if (!mounted) return;
    final qwen = _tool.capabilityId == 'edit_image' &&
        (_selectedModelId ?? _tool.model) == 'qwen2_1_i2i';
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MaskLayoutPreviewPage(
          photo: photo,
          brushMask: mask,
          fitToQwenFrame: qwen,
          resolution: _qwenResolution,
        ),
      ),
    );
  }

  /// Opens mask editor with optional existing mask
  /// [base] - The base image to draw mask on
  /// [existingMask] - Optional existing mask to load
  /// [isBulkMode] - If true, this is for a bulk image (never use single image mask)
  ///                If false, use _inputs["mask_image"] for single mode
  Future<Uint8List?> _openMaskEditor(
    Uint8List base, {
    Uint8List? existingMask,
    bool isBulkMode = false,
    bool brushOnly = false,
  }) async {
    try {
      // CRITICAL: For bulk mode, NEVER use single image mask
      // If existingMask is null in bulk mode, start with empty mask
      // For single mode, fall back to _inputs["mask_image"] if no existingMask provided
      final maskToLoad = isBulkMode
          ? existingMask // Bulk mode: only use the provided mask (or null for fresh start)
          : (existingMask ??
              (_inputs["mask_image"]
                  as Uint8List?)); // Single mode: use provided or fall back to _inputs

      return await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (_) => MaskEditorPage(
            baseImageBytes: base,
            existingMask: maskToLoad,
            brushOnly: brushOnly,
          ),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      debugPrint("Mask editor failed: $e");
      return null;
    }
  }
}

// ---------------------------------------------------
// 🎨 Checker pattern background (used for Outpaint preview)
// ---------------------------------------------------
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 32;
    final paint1 = Paint()..color = const Color(0xFF2A2A2A);
    final paint2 = Paint()..color = const Color(0xFF1E1E1E);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final usePaint = ((x / cell).floor() + (y / cell).floor()) % 2 == 0
            ? paint1
            : paint2;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), usePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ------------------ STYLE PREVIEW IMAGE WIDGET ------------------
/// Widget for loading and displaying cached style preview images/videos
class _StylePreviewImage extends StatefulWidget {
  final StylePreset style;
  final Color accentColor;

  const _StylePreviewImage({
    required this.style,
    required this.accentColor,
  });

  @override
  State<_StylePreviewImage> createState() => _StylePreviewImageState();
}

class _StylePreviewImageState extends State<_StylePreviewImage>
    with WidgetsBindingObserver {
  Uint8List? _imageBytes;
  VideoPlayerController? _videoController;
  bool _loading = true;
  bool _isVideo = false;
  var _playOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPreview();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.pause();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isVideo) return;
    final current = _videoController;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (current != null &&
          videoFrameIsReady(current) &&
          current.value.isPlaying) {
        _playOnResume = true;
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _recoverStyleVideo();
    }
  }

  Future<void> _recoverStyleVideo() async {
    final play = _playOnResume;
    _playOnResume = false;
    final next = await StylePreviewManager.instance.recover(
      widget.style.id,
      play: play,
    );
    if (!mounted) return;
    setState(() {
      if (next != null) _videoController = next;
    });
  }

  Future<void> _loadPreview() async {
    final url = widget.style.previewUrl;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _isVideo = url.endsWith('.mp4') || url.endsWith('.webm');

    if (_isVideo) {
      // Load video with caching
      final controller = await StylePreviewManager.instance.getVideoController(
        widget.style.id,
        url,
      );
      if (mounted && controller != null) {
        setState(() {
          _videoController = controller;
          _loading = false;
        });
        controller.play();
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } else {
      // Load image with caching
      final bytes = await StylePreviewManager.instance.getImagePreview(url);
      if (mounted && bytes != null) {
        setState(() {
          _imageBytes = bytes;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              widget.accentColor.withValues(alpha: 0.15),
              widget.accentColor.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: widget.accentColor.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    if (_isVideo && _videoController != null) {
      return SafeVideoView(
        controller: _videoController,
        fallback: _buildFallback(),
      );
    }

    if (_imageBytes != null) {
      return Image.memory(
        _imageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallback(),
      );
    }

    return _buildFallback();
  }

  Widget _buildFallback() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.accentColor.withValues(alpha: 0.15),
            widget.accentColor.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(widget.style.icon, style: const TextStyle(fontSize: 20)),
      ),
    );
  }
}

// ------------------ MASK EDITOR ------------------
class MaskEditorPage extends StatefulWidget {
  final Uint8List baseImageBytes;
  final Uint8List? existingMask;
  final bool brushOnly;

  const MaskEditorPage({
    super.key,
    required this.baseImageBytes,
    this.existingMask,
    this.brushOnly = false,
  });

  @override
  State<MaskEditorPage> createState() => _MaskEditorPageState();
}

enum _EraseMaskMode { removeObject, removePeople, manual }

class _MaskEditorPageState extends State<MaskEditorPage> {
  ui.Image? _image;
  bool _loading = true;
  bool _peopleLoading = false;
  ui.Image? _maskOverlay;

  // strokes: list of drawn strokes (in image pixel coordinates)
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;
  List<Offset> _lassoPoints = [];
  bool _isDrawingLasso = false;
  _EraseMaskMode _mode = _EraseMaskMode.removeObject;

  final SelfieSegmentationService _peopleSegmenter =
      SelfieSegmentationService();
  List<DetectedPersonRegion> _detectedPeople = [];
  final Set<int> _selectedPeople = <int>{};

  double _brushSize = 50.0;
  bool _eraser = false;

  // Zoom and pan state
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  Offset _focalPointStart = Offset.zero; // Focal point at start of gesture
  bool _isZooming = false;
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.brushOnly) _mode = _EraseMaskMode.manual;
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      // Dispose old images to avoid GPU cache artifacts
      _image?.dispose();
      _maskOverlay?.dispose();

      // Load existing mask if provided (preserve previous mask)
      _maskOverlay = null;
      if (widget.existingMask != null) {
        final maskCodec = await ui.instantiateImageCodec(widget.existingMask!);
        final maskFrame = await maskCodec.getNextFrame();
        _maskOverlay = maskFrame.image;
      }

      // Decode the base image
      final codec = await ui.instantiateImageCodec(widget.baseImageBytes);
      final frame = await codec.getNextFrame();
      _image = frame.image;

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint("Failed to decode image in mask editor: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setMode(_EraseMaskMode mode) async {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _currentStroke = null;
      _lassoPoints = [];
      _isDrawingLasso = false;
    });
    if (mode == _EraseMaskMode.removePeople) {
      await _detectPeople();
    }
  }

  Future<void> _detectPeople() async {
    if (_peopleLoading) return;
    setState(() => _peopleLoading = true);
    try {
      final regions =
          await _peopleSegmenter.detectPeople(widget.baseImageBytes);
      if (!mounted) return;
      setState(() {
        _detectedPeople = regions;
        _selectedPeople.clear();
      });
    } catch (e) {
      debugPrint('❌ Remove People detection error: $e');
      debugPrintStack(label: 'Remove People stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('People detection failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _peopleLoading = false);
    }
  }

  // Local coords are in the fitted [contain] rect (same as [CustomPaint] size).
  Offset _toImageCoords(Offset localPos, Size fitSize) {
    final centerX = fitSize.width / 2;
    final centerY = fitSize.height / 2;
    final unscaledX = (localPos.dx - centerX - _offset.dx) / _scale + centerX;
    final unscaledY = (localPos.dy - centerY - _offset.dy) / _scale + centerY;
    final iw = _image!.width.toDouble();
    final ih = _image!.height.toDouble();
    final xInImageSpace = (unscaledX / fitSize.width) * iw;
    final yInImageSpace = (unscaledY / fitSize.height) * ih;
    return Offset(
      xInImageSpace.clamp(0.0, iw),
      yInImageSpace.clamp(0.0, ih),
    );
  }

  void _resetZoom() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  Future<Uint8List> _exportMask() async {
    final img = _image!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());

    canvas.saveLayer(rect, Paint());
    final paintSrc = Paint()..blendMode = BlendMode.src;

    if (_maskOverlay != null) {
      // draw existing mask at 1:1 (no scaling needed here)
      canvas.drawImage(_maskOverlay!, Offset.zero, paintSrc);
    }

    for (final s in _strokes) {
      if (s.points.length < 2) continue;

      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.size // image-space size (you stored image coords)
        ..isAntiAlias = true
        ..blendMode = s.eraser ? BlendMode.clear : BlendMode.src
        ..color = s.eraser ? const Color(0x00000000) : const Color(0xFFFFFFFF);

      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) {
        final a = s.points[i - 1];
        final b = s.points[i];
        final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        path.quadraticBezierTo(a.dx, a.dy, mid.dx, mid.dy);
      }
      canvas.drawPath(path, p);
    }

    canvas.restore();

    final picture = recorder.endRecording();
    final maskImage = await picture.toImage(img.width, img.height);
    final byteData = await maskImage.toByteData(format: ui.ImageByteFormat.png);
    final composedBytes = byteData!.buffer.asUint8List();

    final maskDecoded = imglib.decodeImage(composedBytes);
    if (maskDecoded == null) {
      throw Exception('Failed to decode composed mask');
    }

    // Remove Object mode: lasso polygon fill.
    if (_mode == _EraseMaskMode.removeObject && _lassoPoints.length >= 3) {
      for (var y = 0; y < maskDecoded.height; y++) {
        for (var x = 0; x < maskDecoded.width; x++) {
          if (_pointInPolygon(x.toDouble(), y.toDouble(), _lassoPoints)) {
            maskDecoded.setPixelRgba(x, y, 255, 255, 255, 255);
          }
        }
      }
    }

    // Remove People mode: union selected component masks.
    if (_mode == _EraseMaskMode.removePeople && _selectedPeople.isNotEmpty) {
      for (final region in _detectedPeople) {
        if (!_selectedPeople.contains(region.id)) continue;
        final regionMask = region.mask;
        final len = regionMask.length;
        final max = maskDecoded.width * maskDecoded.height;
        final n = len < max ? len : max;
        for (var i = 0; i < n; i++) {
          if (regionMask[i] == 0) continue;
          final x = i % maskDecoded.width;
          final y = i ~/ maskDecoded.width;
          maskDecoded.setPixelRgba(x, y, 255, 255, 255, 255);
        }
      }
    }

    return Uint8List.fromList(imglib.encodePng(maskDecoded));
  }

  bool _pointInPolygon(double px, double py, List<Offset> poly) {
    var inside = false;
    var j = poly.length - 1;
    for (var i = 0; i < poly.length; j = i++) {
      final xi = poly[i].dx;
      final yi = poly[i].dy;
      final xj = poly[j].dx;
      final yj = poly[j].dy;
      final intersects = ((yi > py) != (yj > py)) &&
          (px <
              (xj - xi) * (py - yi) / ((yj - yi) == 0 ? 1e-6 : (yj - yi)) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  void _clearAll() {
    setState(() {
      _strokes.clear();
      _lassoPoints.clear();
      _selectedPeople.clear();
      _maskOverlay?.dispose();
      _maskOverlay = null;
    });
  }

  @override
  void dispose() {
    _peopleSegmenter.dispose();
    _image?.dispose();
    _maskOverlay?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : cs.surface,
        appBar: AppBar(
          title: Text(widget.brushOnly ? 'Paint what to change' : 'Draw Mask'),
          backgroundColor: Colors.transparent,
          foregroundColor: cs.onSurface,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_image == null) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : cs.surface,
        appBar: AppBar(
          title: Text(widget.brushOnly ? 'Paint what to change' : 'Draw Mask'),
          backgroundColor: Colors.transparent,
          foregroundColor: cs.onSurface,
          elevation: 0,
        ),
        body: Center(
          child: Text("Failed to load image",
              style: TextStyle(color: cs.onSurface)),
        ),
      );
    }

    final hasMask = _strokes.isNotEmpty ||
        _maskOverlay != null ||
        _lassoPoints.length >= 3 ||
        _selectedPeople.isNotEmpty;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : cs.surface,
      appBar: AppBar(
        title: Text(widget.brushOnly ? 'Paint what to change' : 'Draw Mask'),
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : cs.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.x, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: hasMask
                ? () async {
                    try {
                      final maskBytes = await _exportMask();
                      Navigator.pop(context, maskBytes);
                    } catch (e) {
                      debugPrint("Error exporting mask: $e");
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("Export failed: $e")));
                    }
                  }
                : null,
            icon: Icon(LucideIcons.check,
                size: 18, color: hasMask ? cs.primary : cs.onSurfaceVariant),
            label: Text(
              "Done",
              style: TextStyle(
                color: hasMask ? cs.primary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final widgetSize = constraints.biggest;
                        final imgW = _image!.width.toDouble();
                        final imgH = _image!.height.toDouble();
                        final imgAspect = imgW / imgH;
                        final widgetAspect =
                            widgetSize.width / widgetSize.height;

                        double fitW;
                        double fitH;
                        if (imgAspect > widgetAspect) {
                          fitW = widgetSize.width;
                          fitH = fitW / imgAspect;
                        } else {
                          fitH = widgetSize.height;
                          fitW = fitH * imgAspect;
                        }

                        final fitSize = Size(fitW, fitH);

                        return Stack(
                          fit: StackFit.expand,
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ClipRect(
                                  child: ImageFiltered(
                                    imageFilter: ui.ImageFilter.blur(
                                      sigmaX: 18,
                                      sigmaY: 18,
                                    ),
                                    child: CustomPaint(
                                      painter: _CoverFillImagePainter(
                                        image: _image!,
                                      ),
                                      size: widgetSize,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: cs.outline.withValues(alpha: 0.3),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRect(
                                  child: SizedBox(
                                    width: fitW,
                                    height: fitH,
                                    child: Listener(
                                      onPointerDown: (_) {
                                        _pointerCount++;
                                        if (_pointerCount >= 2) {
                                          // Cancel current stroke if user starts zooming
                                          _currentStroke = null;
                                          _isZooming = true;
                                        }
                                      },
                                      onPointerUp: (_) {
                                        _pointerCount =
                                            (_pointerCount - 1).clamp(0, 10);
                                        if (_pointerCount < 2) {
                                          _isZooming = false;
                                        }
                                      },
                                      onPointerCancel: (_) {
                                        _pointerCount =
                                            (_pointerCount - 1).clamp(0, 10);
                                        if (_pointerCount < 2) {
                                          _isZooming = false;
                                        }
                                      },
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTapDown: _mode ==
                                                _EraseMaskMode.removePeople
                                            ? (details) {
                                                final imgPos = _toImageCoords(
                                                    details.localPosition,
                                                    fitSize);
                                                for (final p
                                                    in _detectedPeople) {
                                                  if (p.bounds
                                                      .contains(imgPos)) {
                                                    setState(() {
                                                      if (_selectedPeople
                                                          .contains(p.id)) {
                                                        _selectedPeople
                                                            .remove(p.id);
                                                      } else {
                                                        _selectedPeople
                                                            .add(p.id);
                                                      }
                                                    });
                                                    break;
                                                  }
                                                }
                                              }
                                            : null,
                                        onScaleStart: (details) {
                                          _baseScale = _scale;
                                          _baseOffset = _offset;
                                          _focalPointStart =
                                              details.localFocalPoint;
                                          if (_pointerCount < 2 &&
                                              _mode !=
                                                  _EraseMaskMode.removePeople) {
                                            // Single finger: start drawing
                                            final local =
                                                details.localFocalPoint;
                                            final imgPos =
                                                _toImageCoords(local, fitSize);
                                            if (_mode ==
                                                _EraseMaskMode.removeObject) {
                                              setState(() {
                                                _isDrawingLasso = true;
                                                _lassoPoints = [imgPos];
                                              });
                                            } else {
                                              _currentStroke = _Stroke(
                                                points: [imgPos],
                                                size: _brushSize,
                                                eraser: _eraser,
                                              );
                                              setState(() => _strokes
                                                  .add(_currentStroke!));
                                            }
                                          }
                                        },
                                        onScaleUpdate: (details) {
                                          if (_pointerCount >= 2 ||
                                              details.scale != 1.0) {
                                            // Multi-finger: zoom and pan
                                            setState(() {
                                              final newScale =
                                                  (_baseScale * details.scale)
                                                      .clamp(1.0, 5.0);
                                              final scaleDelta =
                                                  newScale / _baseScale;
                                              _scale = newScale;

                                              // Calculate the center of the display area
                                              final centerX = fitSize.width / 2;
                                              final centerY =
                                                  fitSize.height / 2;

                                              // Calculate the focal point relative to center
                                              final focalPointRelativeToCenter =
                                                  _focalPointStart -
                                                      Offset(centerX, centerY);

                                              // When zooming, adjust offset so the point under the focal point stays fixed
                                              // The offset needs to compensate for the scale change at the focal point
                                              final offsetDelta =
                                                  focalPointRelativeToCenter *
                                                      (1 - scaleDelta);

                                              // Also account for pan gesture (focal point movement)
                                              final panDelta =
                                                  details.localFocalPoint -
                                                      _focalPointStart;

                                              // Calculate new offset
                                              final maxOffsetX =
                                                  (fitSize.width * _scale -
                                                          fitSize.width) /
                                                      2;
                                              final maxOffsetY =
                                                  (fitSize.height * _scale -
                                                          fitSize.height) /
                                                      2;

                                              final newOffset = _baseOffset +
                                                  offsetDelta +
                                                  panDelta;
                                              _offset = Offset(
                                                newOffset.dx.clamp(
                                                    -maxOffsetX, maxOffsetX),
                                                newOffset.dy.clamp(
                                                    -maxOffsetY, maxOffsetY),
                                              );
                                            });
                                            _currentStroke =
                                                null; // Cancel any stroke
                                          } else if (_mode ==
                                                  _EraseMaskMode.removeObject &&
                                              _isDrawingLasso &&
                                              !_isZooming) {
                                            final local =
                                                details.localFocalPoint;
                                            final imgPos =
                                                _toImageCoords(local, fitSize);
                                            setState(
                                                () => _lassoPoints.add(imgPos));
                                          } else if (_currentStroke != null &&
                                              _mode == _EraseMaskMode.manual &&
                                              !_isZooming) {
                                            // Single finger: continue drawing
                                            final local =
                                                details.localFocalPoint;
                                            final imgPos =
                                                _toImageCoords(local, fitSize);
                                            setState(() => _currentStroke!
                                                .points
                                                .add(imgPos));
                                          }
                                        },
                                        onScaleEnd: (_) {
                                          _currentStroke = null;
                                          _isZooming = false;
                                          _isDrawingLasso = false;
                                        },
                                        child: Transform.translate(
                                          offset: _offset,
                                          child: Transform.scale(
                                            alignment: Alignment.center,
                                            scale: _scale,
                                            child: CustomPaint(
                                              painter: _MaskEditorPainter(
                                                baseImage: _image!,
                                                displaySize: fitSize,
                                                strokes: _strokes,
                                                maskOverlay: _maskOverlay,
                                                lassoPoints: _lassoPoints,
                                                showLasso: _mode ==
                                                    _EraseMaskMode.removeObject,
                                                people: _detectedPeople,
                                                selectedPeople: _selectedPeople,
                                                showPeople: _mode ==
                                                    _EraseMaskMode.removePeople,
                                              ),
                                              size: fitSize,
                                            ),
                                          ),
                                        ),
                                      ),
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
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  top: 6,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 1,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cs.primary.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.info, size: 16, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _mode == _EraseMaskMode.removePeople
                                  ? (_peopleLoading
                                      ? "Detecting people…"
                                      : "Tap person boxes to select • Pinch to zoom")
                                  : widget.brushOnly
                                      ? "Paint the area the prompt may change. The rest of the photo stays."
                                      : _mode == _EraseMaskMode.removeObject
                                      ? "Draw closed lasso around object • Pinch to zoom"
                                      : (_eraser
                                          ? "Manual erase mode • Pinch to zoom"
                                          : "Manual draw mode • Pinch to zoom"),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurface.withValues(alpha: 0.88),
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (_scale != 1.0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "${(_scale * 100).toInt()}%",
                                style: TextStyle(
                                  color: cs.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tool bar (keep clear of gesture/nav insets)
          SafeArea(
            top: false,
            minimum: EdgeInsets.zero,
            child: _buildToolBar(cs),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBar(ColorScheme cs) {
    final hasAnything = _strokes.isNotEmpty ||
        _maskOverlay != null ||
        _lassoPoints.isNotEmpty ||
        _selectedPeople.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          if (!widget.brushOnly) ...[
            Row(
              children: [
                Expanded(
                  child: _buildModeChip(
                    cs: cs,
                    label: 'Remove Object',
                    active: _mode == _EraseMaskMode.removeObject,
                    onTap: () => _setMode(_EraseMaskMode.removeObject),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildModeChip(
                    cs: cs,
                    label: 'Remove People',
                    active: _mode == _EraseMaskMode.removePeople,
                    onTap: () => _setMode(_EraseMaskMode.removePeople),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildModeChip(
                    cs: cs,
                    label: 'Manual',
                    active: _mode == _EraseMaskMode.manual,
                    onTap: () => _setMode(_EraseMaskMode.manual),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          // Brush size slider
          if (_mode == _EraseMaskMode.manual)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.circle,
                      size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text("Size",
                      style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  Expanded(
                    child: Slider(
                      value: _brushSize,
                      min: 10,
                      max: 150,
                      onChanged: (v) => setState(() => _brushSize = v),
                      activeColor: cs.primary,
                      inactiveColor: cs.onSurfaceVariant.withValues(alpha: 0.2),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "${_brushSize.toInt()}",
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            children: [
              // Undo button
              Expanded(
                child: _buildToolButton(
                  icon: LucideIcons.undo2,
                  label: "Undo",
                  onTap: _canUndo ? _undoCurrentMode : null,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 8),
              // Reset Zoom button
              Expanded(
                child: _buildToolButton(
                  icon: LucideIcons.minimize2,
                  label: "Fit",
                  onTap: _scale != 1.0 ? _resetZoom : null,
                  cs: cs,
                ),
              ),
              const SizedBox(width: 8),
              if (_mode == _EraseMaskMode.manual) ...[
                // Draw/Erase toggle
                Expanded(
                  child: _buildToolButton(
                    icon: _eraser ? LucideIcons.paintbrush : LucideIcons.eraser,
                    label: _eraser ? "Draw" : "Erase",
                    onTap: () => setState(() => _eraser = !_eraser),
                    cs: cs,
                    isActive: _eraser,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // Clear button
              Expanded(
                child: _buildToolButton(
                  icon: LucideIcons.trash2,
                  label: "Clear",
                  onTap: hasAnything ? _clearAll : null,
                  cs: cs,
                  isDanger: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required ColorScheme cs,
    bool isActive = false,
    bool isDanger = false,
  }) {
    final isEnabled = onTap != null;
    final Color bgColor = isActive
        ? cs.primary
        : isDanger
            ? (isEnabled ? cs.errorContainer : cs.surfaceContainerHighest)
            : cs.surfaceContainerHighest;
    final Color fgColor = isActive
        ? cs.onPrimary
        : isDanger
            ? (isEnabled
                ? cs.onErrorContainer
                : cs.onSurfaceVariant.withValues(alpha: 0.5))
            : (isEnabled
                ? cs.onSurfaceVariant
                : cs.onSurfaceVariant.withValues(alpha: 0.5));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? cs.primary : cs.outline.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: fgColor),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: fgColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canUndo {
    if (_mode == _EraseMaskMode.manual) return _strokes.isNotEmpty;
    if (_mode == _EraseMaskMode.removeObject) return _lassoPoints.isNotEmpty;
    if (_mode == _EraseMaskMode.removePeople) return _selectedPeople.isNotEmpty;
    return false;
  }

  void _undoCurrentMode() {
    setState(() {
      if (_mode == _EraseMaskMode.manual && _strokes.isNotEmpty) {
        _strokes.removeLast();
      } else if (_mode == _EraseMaskMode.removeObject &&
          _lassoPoints.isNotEmpty) {
        _lassoPoints.removeLast();
      } else if (_mode == _EraseMaskMode.removePeople &&
          _selectedPeople.isNotEmpty) {
        _selectedPeople.remove(_selectedPeople.last);
      }
    });
  }

  Widget _buildModeChip({
    required ColorScheme cs,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: active ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? cs.primary : cs.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: active ? cs.onPrimary : cs.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// small helper data class
class _Stroke {
  final List<Offset> points;
  final double size;
  final bool eraser;
  _Stroke({required this.points, required this.size, required this.eraser});
}

/// Blurred [BoxFit.cover] layer behind the sharp contain rect (fills “empty” bands visually).
class _CoverFillImagePainter extends CustomPainter {
  _CoverFillImagePainter({required this.image});

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    paintImage(
      canvas: canvas,
      rect: dst,
      image: image,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(covariant _CoverFillImagePainter oldDelegate) =>
      oldDelegate.image != image;
}

/// Painter used inside MaskEditorPage ([BoxFit.contain]-sized rect; full image visible).
class _MaskEditorPainter extends CustomPainter {
  final ui.Image baseImage;
  final ui.Image? maskOverlay;
  final Size displaySize;

  final List<_Stroke> strokes;
  final List<Offset> lassoPoints;
  final bool showLasso;
  final List<DetectedPersonRegion> people;
  final Set<int> selectedPeople;
  final bool showPeople;

  _MaskEditorPainter({
    required this.baseImage,
    required this.displaySize,
    required this.strokes,
    required this.lassoPoints,
    required this.showLasso,
    required this.people,
    required this.selectedPeople,
    required this.showPeople,
    this.maskOverlay,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, displaySize.width, displaySize.height);
    canvas.clipRect(dst);
    const fq = FilterQuality.medium;
    paintImage(
      canvas: canvas,
      rect: dst,
      image: baseImage,
      fit: BoxFit.fill,
      filterQuality: fq,
    );

    final sx = displaySize.width / baseImage.width.toDouble();
    final sy = displaySize.height / baseImage.height.toDouble();

    // --- Build the red overlay by COMPOSITING mask + strokes together ---
    if (maskOverlay != null || strokes.isNotEmpty) {
      canvas.saveLayer(dst, Paint());

      if (maskOverlay != null) {
        final src = Rect.fromLTWH(
          0,
          0,
          maskOverlay!.width.toDouble(),
          maskOverlay!.height.toDouble(),
        );
        final paintSrc = Paint()..blendMode = BlendMode.src;
        canvas.drawImageRect(maskOverlay!, src, dst, paintSrc);
      }

      for (final s in strokes) {
        if (s.points.length < 2) continue;

        final strokeWidth = s.size * ((sx + sy) / 2);

        final p = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = strokeWidth
          ..isAntiAlias = true
          ..blendMode = s.eraser ? BlendMode.clear : BlendMode.srcOver
          ..color =
              s.eraser ? const Color(0x00000000) : const Color(0xFFFFFFFF);

        final path = Path()
          ..moveTo(s.points.first.dx * sx, s.points.first.dy * sy);
        for (int i = 1; i < s.points.length; i++) {
          final a = s.points[i - 1];
          final b = s.points[i];
          final mid = Offset((a.dx + b.dx) / 2 * sx, (a.dy + b.dy) / 2 * sy);
          path.quadraticBezierTo(a.dx * sx, a.dy * sy, mid.dx, mid.dy);
        }
        canvas.drawPath(path, p);
      }

      final tint = Paint()
        ..color = const Color(0x55FF0000)
        ..blendMode = BlendMode.srcIn;
      canvas.drawRect(dst, tint);

      canvas.restore();
    }

    if (showLasso && lassoPoints.length >= 2) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFFFD166);
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0x33FFD166);
      final path = Path()
        ..moveTo(lassoPoints.first.dx * sx, lassoPoints.first.dy * sy);
      for (var i = 1; i < lassoPoints.length; i++) {
        path.lineTo(lassoPoints[i].dx * sx, lassoPoints[i].dy * sy);
      }
      if (lassoPoints.length > 2) {
        path.close();
        canvas.drawPath(path, fill);
      }
      canvas.drawPath(path, p);
    }

    if (showPeople) {
      for (final region in people) {
        final rect = Rect.fromLTRB(
          region.bounds.left * sx,
          region.bounds.top * sy,
          region.bounds.right * sx,
          region.bounds.bottom * sy,
        );
        final selected = selectedPeople.contains(region.id);
        final stroke = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1.5
          ..color =
              selected ? const Color(0xFFFF5252) : const Color(0xFF4FC3F7);
        final peopleFill = Paint()
          ..style = PaintingStyle.fill
          ..color =
              (selected ? const Color(0x55FF5252) : const Color(0x224FC3F7));
        canvas.drawRect(rect, peopleFill);
        canvas.drawRect(rect, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskEditorPainter oldDelegate) => true;
}

/// First-frame preview for video upscaler bulk strip.
class _BulkVideoStripThumb extends StatefulWidget {
  final String videoPath;
  final Color placeholderColor;

  const _BulkVideoStripThumb({
    required this.videoPath,
    required this.placeholderColor,
  });

  @override
  State<_BulkVideoStripThumb> createState() => _BulkVideoStripThumbState();
}

class _BulkVideoStripThumbState extends State<_BulkVideoStripThumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    try {
      final b = await VideoThumbnail.thumbnailData(
        video: widget.videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 65,
        timeMs: 0,
      );
      if (mounted && b != null) {
        setState(() => _bytes = b);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child:
            Icon(LucideIcons.video, color: widget.placeholderColor, size: 28),
      ),
    );
  }
}

/// Dashed rounded rectangle used for the bulk “+ Task” tile in the composer.
class DottedRoundedContainer extends StatelessWidget {
  final double width;
  final double height;
  final Color color;
  final double radius;
  final Widget child;

  const DottedRoundedContainer({
    super.key,
    required this.width,
    required this.height,
    required this.color,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _DottedRoundedRectPainter(
          color: color,
          radius: radius,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _DottedRoundedRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DottedRoundedRectPainter({
    required this.color,
    required this.radius,
  });

  static const double _dash = 4;
  static const double _gap = 3;
  static const double _stroke = 1.25;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _stroke / 2,
      _stroke / 2,
      size.width - _stroke,
      size.height - _stroke,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final chunk = draw ? _dash : _gap;
        if (draw) {
          final extract = metric.extractPath(
              distance, min(distance + chunk, metric.length));
          canvas.drawPath(extract, paint);
        }
        distance += chunk;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DottedRoundedRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

/// Small overlapping thumbnails for extra reference images on a bulk task tile.
class _BulkExtraRefsStack extends StatelessWidget {
  final List<Uint8List> refs;
  final ColorScheme cs;

  const _BulkExtraRefsStack({
    required this.refs,
    required this.cs,
  });

  static const int _maxVisible = 2;
  static const double _thumb = 14;

  @override
  Widget build(BuildContext context) {
    if (refs.isEmpty) return const SizedBox.shrink();
    final show = refs.length.clamp(1, _maxVisible);
    final overflow = refs.length - show;
    final stackW = _thumb + (show - 1) * 6.0 + (overflow > 0 ? 16.0 : 0.0);

    return SizedBox(
      width: stackW,
      height: _thumb,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          for (int i = 0; i < show; i++)
            Positioned(
              left: i * 6.0,
              child: Container(
                width: _thumb,
                height: _thumb,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: cs.surface, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.memory(
                  refs[i],
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: show * 6.0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: cs.surface.withValues(alpha: 0.35), width: 0.5),
                ),
                child: Text(
                  '+$overflow',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen style dialog: swipe between images, pinch-zoom, close control.
class _ComposerImageGalleryDialog extends StatefulWidget {
  final List<Uint8List> images;
  final int initialIndex;
  final String title;

  const _ComposerImageGalleryDialog({
    required this.images,
    required this.initialIndex,
    required this.title,
  });

  @override
  State<_ComposerImageGalleryDialog> createState() =>
      _ComposerImageGalleryDialogState();
}

class _ComposerImageGalleryDialogState
    extends State<_ComposerImageGalleryDialog> {
  late final PageController _pageController;
  late int _pageIndex;

  @override
  void initState() {
    super.initState();
    final maxI = widget.images.length - 1;
    _pageIndex = widget.initialIndex.clamp(0, maxI < 0 ? 0 : maxI);
    _pageController = PageController(initialPage: _pageIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final maxH = h * 0.78;
    final n = widget.images.length;
    final pageH = max(220.0, min(maxH * 0.82, h * 0.58));

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (n > 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${_pageIndex + 1} / $n',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: pageH,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _pageIndex = i),
                itemCount: n,
                itemBuilder: (context, i) {
                  return InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Center(
                        child: Image.memory(
                          widget.images[i],
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (n > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12, top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    n,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _pageIndex ? 8 : 6,
                      height: i == _pageIndex ? 8 : 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _pageIndex ? Colors.white : Colors.white38,
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// Full-screen preview for a local video path (composer chips, etc.).
class _VideoAttachmentFullScreenDialog extends StatefulWidget {
  final String videoPath;

  const _VideoAttachmentFullScreenDialog({required this.videoPath});

  @override
  State<_VideoAttachmentFullScreenDialog> createState() =>
      _VideoAttachmentFullScreenDialogState();
}

class _VideoAttachmentFullScreenDialogState
    extends State<_VideoAttachmentFullScreenDialog>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  var _playOnResume = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final controller = VideoPlayerController.file(File(widget.videoPath));
    _controller = controller;
    controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
    controller.setLooping(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final current = _controller;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (current != null &&
          videoFrameIsReady(current) &&
          current.value.isPlaying) {
        _playOnResume = true;
      }
      unawaited(pauseVideoController(current));
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_recoverAttachment());
    }
  }

  Future<void> _recoverAttachment() async {
    final current = _controller;
    final play = _playOnResume;
    _playOnResume = false;
    final next = await replaceDeadVideo(current, play: play);
    if (!mounted) {
      if (next != null && !identical(next, current)) await next.dispose();
      return;
    }
    if (next != null && !identical(next, current)) {
      _controller = next;
      try {
        await current?.dispose();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          if (videoFrameIsReady(_controller))
            GestureDetector(
              onTap: () {
                final current = _controller;
                if (current == null) return;
                if (current.value.isPlaying) {
                  current.pause();
                } else {
                  current.play();
                }
              },
              child: SafeVideoView(
                controller: _controller,
                layout: SafeVideoLayout.aspect,
                fit: BoxFit.contain,
                fallback: const Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: Colors.white54),
            ),
        ],
      ),
    );
  }
}

/// Internal: a single circular-icon shortcut on the section shortcut bar.
class _ShortcutEntry {
  final String id;
  final IconData icon;
  final String tooltip;
  final GlobalKey key;

  const _ShortcutEntry({
    required this.id,
    required this.icon,
    required this.tooltip,
    required this.key,
  });
}

/// Kinds of attachment the composer can render inline.
enum _ComposerAttachmentKind {
  image,
  video,
  audio,
  file,
  bulkImage,
  bulkVideo,

  /// CineReal bulk: optional reference video for task [index] (parallel to [_bulkImageJobs]).
  bulkCineRealRefVideo,
}

/// Snapshot of one attachment shown inline in the composer.
class _ComposerAttachment {
  final String ref;
  final _ComposerAttachmentKind kind;
  final int index;
  final String label;
  final Uint8List? thumbBytes;
  final String? filePath;

  /// For bulk-image tasks on multi-init-per-job models (e.g. Vectra/Revia),
  /// the additional reference images in the same task beyond the primary.
  /// Displayed as small stacked previews on the tile.
  final List<Uint8List>? extraThumbs;

  const _ComposerAttachment({
    required this.ref,
    required this.kind,
    required this.index,
    required this.label,
    this.thumbBytes,
    this.filePath,
    this.extraThumbs,
  });
}

/// Compact round icon-button used inside the composer meta row (+ / bulk).
class _ComposerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool busy;
  final bool enabled;

  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.busy = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveOnTap = (enabled && !busy) ? onTap : () {};
    final iconColor = enabled
        ? (active ? Colors.white : cs.onSurfaceVariant)
        : cs.onSurfaceVariant.withValues(alpha: 0.35);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: effectiveOnTap,
        borderRadius: BorderRadius.circular(100),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: active
                ? const LinearGradient(colors: KalaColors.brandGradient)
                : null,
            color: active ? null : cs.surfaceContainerHigh.withValues(alpha: 0.55),
            border: Border.all(
              color: active
                  ? Colors.transparent
                  : cs.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(7),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.onSurfaceVariant,
                  ),
                )
              : Icon(
                  icon,
                  size: 16,
                  color: iconColor,
                ),
        ),
      ),
    );
  }
}

/// Large tile in the attach sheet — same layout as [MediaSourcePickerTile].
class _AttachBigTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final bool compact;

  const _AttachBigTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return MediaSourcePickerTile(
      icon: icon,
      label: label,
      sublabel: subtitle,
      accentColor: accentColor,
      onTap: onTap,
      compact: compact,
    );
  }
}

/// List-row used in the attach bottom sheet (Video / Audio / extra image inputs).
class _AttachListRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  const _AttachListRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = destructive ? cs.error : cs.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh.withValues(alpha: 0.65),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 11.5,
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
}

/// Small pill shown in the attach sheet header to toggle Bulk mode.
class _AttachBulkTogglePill extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;

  const _AttachBulkTogglePill({required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(100),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? cs.primary.withValues(alpha: 0.15) : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: on
                ? cs.primary.withValues(alpha: 0.45)
                : cs.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.layers,
              size: 12,
              color: on ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              on ? 'Bulk on' : 'Bulk',
              style: TextStyle(
                color: on ? cs.primary : cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// lib/features/ai_tools/generic_tool_page.dart
// FULL THEME-AWARE REWRITE — logic unchanged, UI fully Material 3 + ColorScheme

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart'
    hide userCreditsNotifier, currentUserNotifier, isLoadingUserNotifier, UserData;
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/themed_native_ad.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/outpaint_canvas_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/credits/credits_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/result_manager_page.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
      models: json["models"] != null
          ? List<Map<String, dynamic>>.from(json["models"])
          : null,
      defaultModel: json["defaultModel"],
    );
  }
}

/// --------------------------------------
///  PROMPT HELPER CHIPS (Quick-add tags)
/// --------------------------------------

class PromptChip {
  final String label;
  final String snippet;
  final String icon;
  
  const PromptChip({
    required this.label,
    required this.snippet,
    required this.icon,
  });
}

const List<PromptChip> promptHelperChips = [
  PromptChip(label: 'Cinematic', snippet: 'cinematic lighting, film grain', icon: '🎬'),
  PromptChip(label: 'Anime', snippet: 'anime style, vibrant colors', icon: '🎌'),
  PromptChip(label: 'Portrait', snippet: 'portrait photography, sharp focus', icon: '👤'),
  PromptChip(label: 'Soft Light', snippet: 'soft diffused lighting, gentle shadows', icon: '💡'),
  PromptChip(label: 'High Detail', snippet: '8K, ultra detailed, intricate details', icon: '🔍'),
  PromptChip(label: 'Studio', snippet: 'professional studio lighting, clean background', icon: '📸'),
  PromptChip(label: 'Dramatic', snippet: 'dramatic lighting, high contrast', icon: '🌟'),
  PromptChip(label: 'Dreamy', snippet: 'dreamy atmosphere, ethereal glow', icon: '✨'),
  PromptChip(label: 'Vintage', snippet: 'vintage aesthetic, retro film look', icon: '📼'),
  PromptChip(label: 'Neon', snippet: 'neon lights, cyberpunk vibes', icon: '🌃'),
  PromptChip(label: 'Nature', snippet: 'natural lighting, outdoor setting', icon: '🌿'),
  PromptChip(label: 'Minimal', snippet: 'minimalist, clean composition', icon: '⬜'),
];

/// --------------------------------------
///  STYLE PRESETS (Visual Styles)
///  - Pre-configured style snippets with previews
/// --------------------------------------

class StylePreset {
  final String id;
  final String name;
  final String category;
  final String promptSnippet;
  final String icon; // emoji fallback
  final String? previewUrl; // preview image URL
  final bool isFeatured;
  
  const StylePreset({
    required this.id,
    required this.name,
    required this.category,
    required this.promptSnippet,
    required this.icon,
    this.previewUrl,
    this.isFeatured = false,
  });
}

const List<String> styleCategories = ['All', 'Favorite', 'Fun', 'Realistic', 'Painting', 'Anime', 'Cinematic'];

const List<StylePreset> allStylePresets = [
  // Fun
  StylePreset(
    id: 'cartoon_3d', name: '3D Cartoon', category: 'Fun',
    promptSnippet: 'Pixar 3D animation style, colorful, rounded shapes, playful lighting',
    icon: '🎪', isFeatured: true,
  ),
  StylePreset(
    id: 'comic_book', name: 'Comic Book', category: 'Fun',
    promptSnippet: 'comic book style, bold outlines, halftone dots, speech bubbles aesthetic',
    icon: '💥',
  ),
  StylePreset(
    id: 'clay_render', name: 'Clay Render', category: 'Fun',
    promptSnippet: 'claymation style, soft clay texture, stop motion aesthetic, handcrafted look',
    icon: '🎨',
  ),
  StylePreset(
    id: 'sticker', name: 'Sticker Style', category: 'Fun',
    promptSnippet: 'cute sticker design, white outline, kawaii aesthetic, glossy finish',
    icon: '🏷️',
  ),
  
  // Realistic
  StylePreset(
    id: 'photo_real', name: 'Photorealistic', category: 'Realistic',
    promptSnippet: 'photorealistic, DSLR quality, natural lighting, 8K resolution, sharp details',
    icon: '📷', isFeatured: true,
  ),
  StylePreset(
    id: 'product_shot', name: 'Product Shot', category: 'Realistic',
    promptSnippet: 'professional product photography, studio lighting, clean white background',
    icon: '🛍️',
  ),
  StylePreset(
    id: 'fashion', name: 'Fashion Editorial', category: 'Realistic',
    promptSnippet: 'high fashion editorial, Vogue magazine quality, dramatic pose, designer aesthetic',
    icon: '👗',
  ),
  StylePreset(
    id: 'documentary', name: 'Documentary', category: 'Realistic',
    promptSnippet: 'documentary photography style, candid moment, natural light, authentic',
    icon: '🎞️',
  ),
  
  // Painting
  StylePreset(
    id: 'oil_classic', name: 'Oil Painting', category: 'Painting',
    promptSnippet: 'classical oil painting, rich brush strokes, Renaissance masters style, museum quality',
    icon: '🖼️', isFeatured: true,
  ),
  StylePreset(
    id: 'watercolor', name: 'Watercolor', category: 'Painting',
    promptSnippet: 'watercolor painting, soft color blends, paper texture, artistic drips',
    icon: '🎨',
  ),
  StylePreset(
    id: 'impressionist', name: 'Impressionist', category: 'Painting',
    promptSnippet: 'impressionist painting, visible brush strokes, light and color emphasis, Monet style',
    icon: '🌸',
  ),
  StylePreset(
    id: 'digital_art', name: 'Digital Art', category: 'Painting',
    promptSnippet: 'professional digital art, trending on ArtStation, concept art quality',
    icon: '💻',
  ),
  
  // Anime
  StylePreset(
    id: 'anime_modern', name: 'Modern Anime', category: 'Anime',
    promptSnippet: 'modern anime style, detailed shading, vibrant colors, high quality animation',
    icon: '🎌', isFeatured: true,
  ),
  StylePreset(
    id: 'ghibli', name: 'Studio Ghibli', category: 'Anime',
    promptSnippet: 'Studio Ghibli style, Hayao Miyazaki aesthetic, magical realism, detailed backgrounds',
    icon: '🏯',
  ),
  StylePreset(
    id: 'manga', name: 'Manga Panel', category: 'Anime',
    promptSnippet: 'manga illustration style, black and white, screentones, dynamic composition',
    icon: '📖',
  ),
  StylePreset(
    id: 'chibi', name: 'Chibi', category: 'Anime',
    promptSnippet: 'chibi style, cute proportions, big head small body, kawaii expressions',
    icon: '🥰',
  ),
  
  // Cinematic
  StylePreset(
    id: 'film_noir', name: 'Film Noir', category: 'Cinematic',
    promptSnippet: 'film noir style, black and white, dramatic shadows, 1940s detective aesthetic',
    icon: '🎬', isFeatured: true,
  ),
  StylePreset(
    id: 'blockbuster', name: 'Blockbuster', category: 'Cinematic',
    promptSnippet: 'Hollywood blockbuster look, epic scale, cinematic color grading, anamorphic lens',
    icon: '🎥',
  ),
  StylePreset(
    id: 'scifi', name: 'Sci-Fi Epic', category: 'Cinematic',
    promptSnippet: 'science fiction aesthetic, futuristic technology, epic space opera, blade runner vibes',
    icon: '🚀',
  ),
  StylePreset(
    id: 'horror', name: 'Horror', category: 'Cinematic',
    promptSnippet: 'horror movie aesthetic, unsettling atmosphere, dark shadows, eerie lighting',
    icon: '👻',
  ),
];

/// --------------------------------------
///  ADVANCED SETTINGS MODEL
/// --------------------------------------

class AdvancedSettings {
  bool enhancePrompt;
  bool upscaleOutput;
  String quality; // 'Low', 'Medium', 'High'
  String aspectRatio; // 'Default', '1:1', '9:16', '16:9', '4:3', '3:4'
  int variations; // 1-4 (VIP: max 4, non-VIP: max 2)
  int videoDuration; // 3, 5, 8 seconds
  double cfgScale; // 0.1 - 15.0
  bool bulkEditEnabled; // VIP only - process multiple images with same settings
  
  AdvancedSettings({
    this.enhancePrompt = false,
    this.upscaleOutput = false,
    this.quality = 'High',
    this.aspectRatio = 'Default',
    this.variations = 1,
    this.videoDuration = 5,
    this.cfgScale = 1.0,
    this.bulkEditEnabled = false,
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
    );
  }
}

class GenericToolPage extends StatefulWidget {
  final GenericToolConfig config;
  final String? restoreJobId;
  const GenericToolPage({
    super.key,
    required this.config,
    this.restoreJobId,
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
  final picker = ImagePicker();
  final Map<String, dynamic> _inputs = {};
  bool _loading = false;
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

  // -------- Style Library --------
  String _selectedStyleCategory = 'All';
  StylePreset? _selectedStyle;
  final Set<String> _favoriteStyles = {};
  
  // -------- Prompt Enhancer Section --------
  bool _isEnhancerExpanded = true;
  int _enhancerTabIndex = 0; // 0 = Styles, 1 = Quick Tags

  // -------- Advanced Settings --------
  late AdvancedSettings _advancedSettings;

  // -------- Model Selection --------
  String? _selectedModelId;
  Map<String, dynamic>? _selectedModelData;

  // -------- Generate Button Animation --------
  late AnimationController _glowAnimationController;

  // API config
  static const String controllerUrl = "https://genedit.mooo.com";
  final AuthService _authService = AuthService();

  // -------- Upscale (2x/4x switch) --------
  int _scaleFactor = 2;
  bool _upscaleEnabled = false;
  
  // -------- Bulk Edit (VIP only) --------
  // Stores multiple images for bulk processing (max 10 for VIP)
  List<Uint8List> _bulkImages = [];
  // Stores masks for each bulk image (for inpaint/erase tools)
  final List<Uint8List?> _bulkMasks = [];
  // Stores outpaint configurations for each bulk image (for expand scene)
  final List<Map<String, String>?> _bulkOutpaintConfigs = [];
  static const int _maxBulkImages = 10;
  // Max total jobs per submission (images × variations) to prevent server overload
  static const int _maxTotalJobs = 25;
  
  /// Check if tool requires mask for each image (inpaint/erase tools)
  bool get _requiresMask {
    final model = widget.config.model.toLowerCase();
    final mode = _selectedModeKey?.toLowerCase() ?? "";
    final paramMode = (widget.config.params?["mode"]?.toString().toLowerCase() ?? "");
    return model.contains("inpaint") ||
           model.contains("lama") ||
           mode.contains("inpaint") ||
           paramMode.contains("inpaint") ||
           paramMode.contains("lama");
  }
  
  /// Check if tool is outpaint (expand scene)
  bool get _isOutpaint => widget.config.model == "diffusers_outpaint";
  
  /// Check if this is an upscaler tool (e.g., "Upscale Image")
  /// Upscalers have upscale always enabled by default
  bool get _isUpscalerTool {
    final title = widget.config.title.toLowerCase();
    final model = widget.config.model.toLowerCase();
    // Check by title or model name
    return title.contains('upscale') || 
           model == 'aurasrv2' || 
           model == 'swin2sr' || 
           model == 'realesrgan';
  }
  
  /// Check if bulk mode should be available for this tool
  bool get _supportsBulkEdit {
    // Check if tool has init_image OR image input (image/video editing tools)
    // Upscale tool uses 'image' instead of 'init_image'
    final hasInitImage = widget.config.inputs.any((i) => i['id'] == 'init_image');
    final hasImageInput = widget.config.inputs.any((i) => i['id'] == 'image' && i['type'] == 'image');
    // Bulk edit is for editing tools that take images as input
    // This includes image editing, inpainting, outpainting, upscaling, and video animation
    return hasInitImage || hasImageInput;
  }

  /// Calculate the total credit cost for this job
  /// VIP users get FREE upscale
  int _calculateTotalCost() {
    // Use model-specific cost if available
    final baseCost = _currentModelCost;
    final upscaleCost = _currentModelUpscaleCost;
    final offer = _currentModelOffer;
    final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
    
    // Check if upscale is enabled - use advanced settings, not _inputs
    final bool isUpscaled = _advancedSettings.upscaleOutput && _scaleFactor > 1;
    
    // VIP users get FREE upscale
    final bool freeUpscale = isUpscaleFree();

    // Base cost per variation (VIP: no upscale cost)
    final int basePerVariation = baseCost + (isUpscaled && !freeUpscale ? upscaleCost : 0);
    
    // Apply offer discount
    int costPerVariation = basePerVariation;
    if (offer > 0) {
      costPerVariation = (basePerVariation * (1 - offer / 100)).round();
    }
    
    // Calculate total images (1 for normal, N for bulk edit)
    final int imageCount = _advancedSettings.bulkEditEnabled && _bulkImages.isNotEmpty 
        ? _bulkImages.length 
        : 1;
    
    // Total = cost per variation × variations × number of images
    // For bulk edit: each image gets processed with N variations
    return costPerVariation * variations * imageCount;
  }

  // Dynamic element cache
  List<Map<String, dynamic>> get _currentElements {
    if (widget.config.modes != null &&
        _selectedModeKey != null &&
        widget.config.modes!.containsKey(_selectedModeKey)) {
      return List<Map<String, dynamic>>.from(
          widget.config.modes![_selectedModeKey]!["elements"] ?? []);
    }
    return List<Map<String, dynamic>>.from(widget.config.elements ?? []);
  }

  bool get _hasPrompt => widget.config.inputs.any((i) => i['id'] == 'prompt');
  bool get _hasScaleFactor =>
      widget.config.inputs.any((i) => i['id'] == 'scale_factor');

  /// Returns the effective input config for a given base input id.
  ///
  /// Some models override UI behavior (label/max) via `inputOverrides` in tool_config.json
  /// (e.g. `qwen_image_edit_2509` supports up to 3 images). We apply those overrides
  /// to the base input while keeping the *storage id* unchanged (so elements using
  /// `input_ref: "init_image"` keep working).
  Map<String, dynamic> _effectiveInputConfig(String baseId) {
    final base = Map<String, dynamic>.from(
      widget.config.inputs.firstWhere((i) => i["id"] == baseId, orElse: () => {}),
    );

    try {
      final overrides = _selectedModelData?['inputOverrides'] as Map<String, dynamic>?;
      final o = overrides != null ? overrides[baseId] : null;
      if (o is Map) {
        // Apply only UI/selection behavior overrides; keep the actual id stable.
        if (o['label'] != null) base['label'] = o['label'];
        if (o['max'] != null) base['max'] = o['max'];
        if (o['min'] != null) base['min'] = o['min'];
        // Do NOT apply o['id'] here (it is an alias used by templates/server).
      }
    } catch (_) {}

    return base;
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
    if (widget.config.modes != null && widget.config.modes!.isNotEmpty) {
      _selectedModeKey = widget.config.modes!.keys.first;
    }

    // Initialize selected model
    _initializeSelectedModel();

    if (widget.restoreJobId != null) {
      _activeJobId = widget.restoreJobId;
      _loading = true;
    }
    
    // Listen for ad-free status changes to hide/show native ads
    isAdFreeNotifier.addListener(_onAdFreeStatusChanged);
    
    // Listen for job list changes to update rate limit status in real-time
    jobListNotifier.addListener(_onJobListChanged);

    debugPrint("🔧 Config for ${widget.config.model}");
    debugPrint("  title=${widget.config.title}");
    debugPrint("  elements=${widget.config.elements?.length}");
    debugPrint("  modes=${widget.config.modes?.keys}");
    debugPrint("  models=${widget.config.models?.length ?? 0}");
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

  /// Initialize the selected model from config
  void _initializeSelectedModel() {
    if (widget.config.models != null && widget.config.models!.isNotEmpty) {
      // Use default model if specified, otherwise first model
      final defaultId = widget.config.defaultModel ?? widget.config.model;
      _selectedModelId = defaultId;
      _selectedModelData = widget.config.models!.firstWhere(
        (m) => m['id'] == defaultId,
        orElse: () => widget.config.models!.first,
      );
    }
  }

  /// Select a different model
  void _selectModel(Map<String, dynamic> model) {
    setState(() {
      _selectedModelId = model['id'] as String;
      _selectedModelData = model;
    });
  }

  /// Get the current model's cost
  int get _currentModelCost => 
      _selectedModelData?['cost'] as int? ?? widget.config.cost;

  /// Get the current model's upscale cost
  int get _currentModelUpscaleCost => 
      _selectedModelData?['costUpscale'] as int? ?? widget.config.costUpscale;

  /// Get the current model's offer discount
  int get _currentModelOffer => 
      _selectedModelData?['offer'] as int? ?? widget.config.offer;

  // -------- Prompt Helper Chips --------
  
  /// Append a chip's snippet to the prompt intelligently
  void _appendChipToPrompt(PromptChip chip) {
    final currentText = _promptController.text.trim();
    String newText;
    
    if (currentText.isEmpty) {
      newText = chip.snippet;
    } else if (currentText.endsWith(',')) {
      newText = '$currentText ${chip.snippet}';
    } else {
      newText = '$currentText, ${chip.snippet}';
    }
    
    _promptController.text = newText;
    _inputs['prompt'] = newText;
    setState(() {});
  }

  // -------- Style Library --------
  
  /// Get styles filtered by category
  List<StylePreset> _getStylesByCategory(String category) {
    if (category == 'All') {
      return allStylePresets;
    }
    if (category == 'Favorite') {
      return allStylePresets.where((s) => _favoriteStyles.contains(s.id)).toList();
    }
    return allStylePresets.where((s) => s.category == category).toList();
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
  }

  /// Apply random style
  void _applyRandomStyle() {
    final random = Random();
    final randomStyle = allStylePresets[random.nextInt(allStylePresets.length)];
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                      color: cs.outlineVariant.withOpacity(0.5),
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
                                color: cs.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(LucideIcons.settings, color: cs.primary, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              'Advanced Settings',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: cs.onSurface,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        
                        // Model Selector (only if multiple models available)
                        if (widget.config.hasMultipleModels) ...[
                          _buildModelSelector(cs, setSheetState),
                          const SizedBox(height: 20),
                        ],
                        
                        // Enhance Prompt Toggle (only for models with prompt)
                        if (_hasPrompt) ...[
                          _buildSettingToggle(
                            cs: cs,
                            icon: LucideIcons.sparkles,
                            title: 'Enhance Prompt',
                            subtitle: 'AI improves your prompt automatically',
                            value: _advancedSettings.enhancePrompt,
                            onChanged: (v) {
                              setSheetState(() {
                                setState(() {
                                  _advancedSettings = _advancedSettings.copyWith(enhancePrompt: v);
                                });
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        
                        // Upscale Toggle (locked for upscaler tools)
                        _buildSettingToggle(
                          cs: cs,
                          icon: LucideIcons.maximize2,
                          title: 'Upscale Output',
                          subtitle: _isUpscalerTool 
                              ? 'Always enabled for upscaler tools' 
                              : 'Higher resolution result (+5 credits) - Free for VIP users',
                          value: _advancedSettings.upscaleOutput,
                          locked: _isUpscalerTool, // Lock for upscaler tools
                          onChanged: _isUpscalerTool ? null : (v) {
                            setSheetState(() {
                              setState(() {
                                _advancedSettings = _advancedSettings.copyWith(upscaleOutput: v);
                                _upscaleEnabled = v;
                                _inputs["scale_factor"] = v ? _scaleFactor : 1.0;
                              });
                            });
                          },
                        ),
                        
                        // Upscale Factor Selector (2x/4x) - shown when upscale is enabled
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          child: _advancedSettings.upscaleOutput
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12, left: 8, right: 8),
                                  child: _buildUpscaleFactorSelector(cs, setSheetState),
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 16),
                        
                        // Aspect Ratio Selector
                        _buildSettingSelector(
                          cs: cs,
                          icon: LucideIcons.scaling,
                          title: 'Aspect Ratio',
                          options: ['Default', '1:1', '9:16', '16:9', '4:3', '3:4'],
                          selected: _advancedSettings.aspectRatio,
                          onChanged: (v) {
                            setSheetState(() {
                              setState(() {
                                _advancedSettings = _advancedSettings.copyWith(aspectRatio: v);
                              });
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                        
                        // CFG Scale Slider
                        _buildCfgSlider(cs, setSheetState),
                        const SizedBox(height: 16),
                        
                        // Variations Slider (for image generation)
                        // VIP users: max 4, Non-VIP: max 2
                        if (widget.config.outputType == 'image') ...[
                          _buildSettingSlider(
                            cs: cs,
                            icon: LucideIcons.copy,
                            title: 'Variations',
                            subtitle: isVipUser() 
                                ? 'VIP: Up to 4 variations' 
                                : 'Up to 2 variations (VIP: 4)',
                            value: _advancedSettings.variations.toDouble().clamp(1, getMaxVariations().toDouble()),
                            min: 1,
                            max: getMaxVariations().toDouble(),
                            divisions: getMaxVariations() - 1,
                            onChanged: (v) {
                              setSheetState(() {
                                setState(() {
                                  _advancedSettings = _advancedSettings.copyWith(
                                    variations: v.round().clamp(1, getMaxVariations()),
                                  );
                                });
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                        
                        // Duration Selector (for video generation)
                        if (widget.config.outputType == 'video') ...[
                          _buildSettingSelector(
                            cs: cs,
                            icon: LucideIcons.timer,
                            title: 'Duration',
                            options: ['3s', '5s', '8s'],
                            selected: '${_advancedSettings.videoDuration}s',
                            onChanged: (v) {
                              setSheetState(() {
                                setState(() {
                                  _advancedSettings = _advancedSettings.copyWith(
                                    videoDuration: int.parse(v.replaceAll('s', '')),
                                  );
                                });
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                        ],
                      ],
                    ),
                  ),
                ),
                
                // Done button (fixed at bottom with safe area)
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.35)),
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
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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

  /// Build toggle setting widget
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
      decoration: BoxDecoration(
        color: value ? cs.primaryContainer.withOpacity(0.3) : cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? cs.primary.withOpacity(0.3) : cs.outlineVariant.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: value ? cs.primary.withOpacity(0.15) : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: value ? cs.primary : cs.onSurfaceVariant),
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
                    color: cs.onSurfaceVariant.withOpacity(0.7),
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

  /// Build bulk edit toggle with VIP badge (VIP only feature)
  /// Show dialog prompting user to upgrade to VIP
  void _showVipRequiredDialog(ColorScheme cs, String featureName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with crown icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.amber.shade600, Colors.orange.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.crown, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 16),
              
              // Title
              Text(
                'VIP Feature',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              
              // Description
              Text(
                '$featureName requires VIP membership',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),
              
              // Benefits container
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    _buildVipBenefit(cs, LucideIcons.layers, 'Bulk edit up to 10 images'),
                    _buildVipBenefit(cs, LucideIcons.copy, 'Up to 4 variations'),
                    _buildVipBenefit(cs, LucideIcons.maximize2, 'Free upscaling'),
                    _buildVipBenefit(cs, LucideIcons.zap, '25 concurrent jobs (5x more!)'),
                    _buildVipBenefit(cs, LucideIcons.eyeOff, 'Ad-free experience'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        side: BorderSide(color: cs.outlineVariant),
                      ),
                      child: Text(
                        'Maybe Later',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.amber.shade600, Colors.orange.shade700],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.amber.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            // Close the dialog first
                            Navigator.pop(ctx);
                            // Navigate back to main page and then to Credits tab
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              // Pop the GenericToolPage to go back to main scaffold
                              if (Navigator.canPop(context)) {
                                Navigator.pop(context);
                              }
                              // Then navigate to Credits page (index 2)
                              selectedIndexNotifier.value = 2;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.crown, color: Colors.white, size: 18),
                                SizedBox(width: 6),
                                Text(
                                  'Get VIP',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
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
  }

  Widget _buildVipBenefit(ColorScheme cs, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// Build selector setting widget
  Widget _buildSettingSelector({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            children: options.map((opt) {
              final isSelected = selected == opt;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(opt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? cs.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: Text(
                        opt,
                        style: TextStyle(
                          color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// Build slider setting widget
  Widget _buildSettingSlider({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                value.round().toString(),
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.outlineVariant.withOpacity(0.3),
            thumbColor: cs.primary,
            overlayColor: cs.primary.withOpacity(0.15),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  /// Build CFG Scale slider for advanced settings
  Widget _buildCfgSlider(ColorScheme cs, StateSetter setSheetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.sliders, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CFG Scale',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'How closely to follow prompt (1.0 = default)',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _advancedSettings.cfgScale.toStringAsFixed(1),
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.outlineVariant.withOpacity(0.3),
            thumbColor: cs.primary,
            overlayColor: cs.primary.withOpacity(0.15),
          ),
          child: Slider(
            value: _advancedSettings.cfgScale,
            min: 0.1,
            max: 15.0,
            divisions: 149, // 0.1 increments
            onChanged: (v) {
              setSheetState(() {
                setState(() {
                  _advancedSettings = _advancedSettings.copyWith(cfgScale: double.parse(v.toStringAsFixed(1)));
                });
              });
            },
          ),
        ),
      ],
    );
  }

  /// Build upscale factor selector (2x/4x) for advanced settings
  Widget _buildUpscaleFactorSelector(ColorScheme cs, StateSetter setSheetState) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Row(
        children: [2, 4].map((scale) {
          final isSelected = _scaleFactor == scale;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setSheetState(() {
                  setState(() {
                    _scaleFactor = scale;
                    _inputs["scale_factor"] = scale;
                  });
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: cs.primary.withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.maximize2,
                        size: 16,
                        color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${scale}x',
                        style: TextStyle(
                          color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Build model selector for advanced settings
  Widget _buildModelSelector(ColorScheme cs, StateSetter setSheetState) {
    final models = widget.config.models ?? [];
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
            color: cs.onSurfaceVariant.withOpacity(0.7),
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
              final isDefault = model['id'] == widget.config.defaultModel;
              
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
    final cost = model['cost'] as int? ?? 10;
    final offer = model['offer'] as int? ?? 0;
    final discountedCost = offer > 0 ? (cost * (1 - offer / 100)).round() : cost;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 150,
        height: 110, // Fixed height to prevent overflow
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withOpacity(0.12)
              : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? cs.primary.withOpacity(0.5)
                : cs.outlineVariant.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: cs.primary.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
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
                    child: Icon(LucideIcons.check, size: 10, color: cs.onPrimary),
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
                color: cs.onSurfaceVariant.withOpacity(0.8),
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
                      color: cs.onSurfaceVariant.withOpacity(0.5),
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
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
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
    _promptController.dispose();
    _previewPageController.dispose();
    _glowAnimationController.dispose();
    isAdFreeNotifier.removeListener(_onAdFreeStatusChanged);
    jobListNotifier.removeListener(_onJobListChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_activeJobId != null && _loading && !_fetchingResult) {
        debugPrint("🔁 Resuming job polling after resume");
      }
    }
  }

  // -------- Validation: Check if all required inputs are filled --------
  bool _areRequiredInputsFilled() {
    // Don't allow generation while an image is being processed
    if (_isProcessingImage) return false;
    
    // Check if bulk edit mode is enabled
    final isBulkMode = _advancedSettings.bulkEditEnabled && isVipUser();
    
    // Calculate total jobs for rate limit check
    final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
    final int imageCount = isBulkMode && _bulkImages.isNotEmpty ? _bulkImages.length : 1;
    final int totalJobsToSubmit = imageCount * variations;
    
    // Check rate limit - don't allow if it would exceed concurrent job limit
    final rateLimitError = checkRateLimitForSubmission(totalJobsToSubmit);
    if (rateLimitError != null) return false;
    
    // Check total job limit for bulk edit
    if (isBulkMode && _bulkImages.isNotEmpty) {
      final totalJobs = _bulkImages.length * variations;
      if (totalJobs > _maxTotalJobs) return false;
      
      // For inpaint tools in bulk mode, all images must have masks
      if (_requiresMask) {
        for (int i = 0; i < _bulkImages.length; i++) {
          if (i >= _bulkMasks.length || _bulkMasks[i] == null) {
            return false;
          }
        }
      }
      
      // For outpaint tools in bulk mode, all images must have placement config
      if (_isOutpaint) {
        for (int i = 0; i < _bulkImages.length; i++) {
          if (i >= _bulkOutpaintConfigs.length || _bulkOutpaintConfigs[i] == null) {
            return false;
          }
        }
      }
    }
    
    final elements = _currentElements;
    
    for (final element in elements) {
      final type = element["type"];
      final inputRef = element["input_ref"];
      
      // Skip elements without input_ref (like upscale_toggle, generate_button)
      if (inputRef == null) continue;
      
      // Skip optional inputs like sliders, dropdowns (they have defaults)
      if (type == "slider" || type == "dropdown") continue;
      
      switch (type) {
        case "prompt":
          // Check if prompt is optional
          final promptInput = widget.config.inputs
              .firstWhere((i) => i["id"] == inputRef, orElse: () => {});
          final isOptional = promptInput["optional"] == true;
          if (!isOptional) {
            // Prompt is required - always use the controller as source of truth
            final promptText = _promptController.text.trim();
            if (promptText.isEmpty) {
              return false;
            }
          }
          break;
          
        case "image_upload":
          // In bulk mode, check bulk images instead of single image
          if (isBulkMode && _supportsBulkEdit) {
            // Bulk mode: require at least one bulk image
            if (_bulkImages.isEmpty) return false;
          } else {
            // Single mode: check normal image input
            final imageData = _inputs[inputRef];
            if (imageData == null) return false;
            if (imageData is List && imageData.isEmpty) return false;
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
  List<String> _getMissingInputs() {
    final missing = <String>[];
    
    // Show processing message while image is being loaded
    if (_isProcessingImage) {
      return ["Image loading..."]; // Special message for processing state
    }
    
    // Check if bulk edit mode is enabled
    final isBulkMode = _advancedSettings.bulkEditEnabled && isVipUser();
    
    // Calculate total jobs for rate limit check
    final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
    final int imageCount = isBulkMode && _bulkImages.isNotEmpty ? _bulkImages.length : 1;
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
        return ["⏳ $available slot${available > 1 ? 's' : ''} free • Need $totalJobsToSubmit"];
      }
      return ["⏳ Processing $current jobs..."];
    }
    
    // Check total job limit for bulk edit
    if (isBulkMode && _bulkImages.isNotEmpty) {
      final totalJobs = _bulkImages.length * variations;
      if (totalJobs > _maxTotalJobs) {
        return ["Max $_maxTotalJobs jobs allowed"];
      }
      
      // Check bulk masks for inpaint tools
      if (_requiresMask) {
        int missingMasks = 0;
        for (int i = 0; i < _bulkImages.length; i++) {
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
        for (int i = 0; i < _bulkImages.length; i++) {
          if (i >= _bulkOutpaintConfigs.length || _bulkOutpaintConfigs[i] == null) {
            missingConfigs++;
          }
        }
        if (missingConfigs > 0) {
          return ["$missingConfigs image(s) need placement"];
        }
      }
    }
    
    final elements = _currentElements;
    
    for (final element in elements) {
      final type = element["type"];
      final inputRef = element["input_ref"];
      
      // Skip elements without input_ref
      if (inputRef == null) continue;
      
      // Skip optional inputs
      if (type == "slider" || type == "dropdown") continue;
      
      switch (type) {
        case "prompt":
          // Check if prompt is optional
          final promptInput = widget.config.inputs
              .firstWhere((i) => i["id"] == inputRef, orElse: () => {});
          final isOptional = promptInput["optional"] == true;
          if (!isOptional) {
            // Prompt is required - check if filled
            final promptText = _promptController.text.trim();
            if (promptText.isEmpty) {
              missing.add("Prompt");
            }
          }
          break;
          
        case "image_upload":
          // In bulk mode, check bulk images instead of single image
          if (isBulkMode && _supportsBulkEdit) {
            if (_bulkImages.isEmpty) {
              missing.add("Images");
            }
          } else {
            final imageData = _inputs[inputRef];
            if (imageData == null || (imageData is List && imageData.isEmpty)) {
              missing.add("Image");
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
    final baseCost = widget.config.cost;
    final upscaleCost = widget.config.costUpscale;
    final offer = widget.config.offer;
    final scaleFactor = _inputs["scale_factor"] ?? 1.0;

    // Calculate costs
    final int baseTotal = baseCost + ((scaleFactor > 1) ? upscaleCost : 0);
    int totalCost = baseTotal;
    if (offer > 0) {
      totalCost = (baseTotal * (1 - offer / 100)).round();
    }

    // Check if button should be enabled
    final isEnabled = _areRequiredInputsFilled();
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _isProcessingImage 
                          ? cs.primaryContainer.withOpacity(0.3)
                          : cs.errorContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isProcessingImage
                            ? cs.primary.withOpacity(0.2)
                            : cs.error.withOpacity(0.2),
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
                              color: cs.primary.withOpacity(0.8),
                            ),
                          )
                        else
                Icon(
                            LucideIcons.alertCircle,
                            size: 16,
                            color: cs.error.withOpacity(0.8),
                ),
                const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _isProcessingImage 
                                ? "Processing image..."
                                : "Add ${missingInputs.join(' & ')} to continue",
                              style: TextStyle(
                              color: _isProcessingImage
                                  ? cs.primary.withOpacity(0.9)
                                  : cs.error.withOpacity(0.9),
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
                      : [cs.onSurfaceVariant.withOpacity(0.4), cs.onSurfaceVariant.withOpacity(0.3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: isEnabled
                    ? [
                        BoxShadow(
                          color: KalaColors.purple.withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: KalaColors.cyan.withOpacity(0.2),
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
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
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
                          color: Colors.white.withOpacity(0.3),
                        ),
                        
                        // Right: Cost display
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.gem,
                                size: 16,
                                color: Colors.white.withOpacity(0.9),
                              ),
                              const SizedBox(width: 6),
                              if (offer > 0) ...[
                                Text(
                                  "$baseTotal",
                              style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 14,
                                decoration: TextDecoration.lineThrough,
                                    decorationColor: Colors.white.withOpacity(0.6),
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
                                    color: Colors.greenAccent.withOpacity(0.25),
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
          
          // Upscale info badge (when upscale is enabled)
          if (_upscaleEnabled && upscaleCost > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    LucideIcons.maximize2,
                    size: 14,
                    color: cs.primary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    "${_scaleFactor}x upscale (+$upscaleCost credits)",
                      style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.7),
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

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primary.withOpacity(0.15),
                    cs.secondary.withOpacity(0.1),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                LucideIcons.sparkles,
                size: 18,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
          widget.config.title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  fontSize: 18,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
        actions: [
          // Credits display
          ValueListenableBuilder<int>(
            valueListenable: userCreditsNotifier,
            builder: (_, credits, __) {
              return Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: cs.primary.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.gem,
                      size: 16,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      credits.toString(),
                      style: TextStyle(
                        color: cs.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _buildDynamicInputScreen(),
    );
  }

  // -----------------------------------------------
  // 🧠 IMAGE PICKING & INPUT MANAGEMENT
  // -----------------------------------------------

  Future<void> _pickImageFromGallery(Map<String, dynamic> input) async {
    final id = input['id'];
    final maxCount = (input['max'] ?? 1) as int;
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
        final bytesList = await Future.wait(limited.map((f) async {
          final b = await f.readAsBytes();
          return _resizeImageSafe(b);
        }));

        // Check again after async operation
        if (currentVersion != _imageProcessingVersion || !mounted) {
          // A newer operation started or widget unmounted
          return;
        }

          setState(() {
            _inputs[id] = bytesList;
            _inputs["${id}_path"] = limited.first.path;
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
            _inputs[id] = [bytes];
            _inputs["${id}_path"] = file.path;
            // Clear old mask when new image is selected
            _inputs["mask_image"] = null;
          _isProcessingImage = false;
          });

        if (widget.config.model == "diffusers_outpaint") {
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
        final model = widget.config.model.toLowerCase();
        final mode = _selectedModeKey?.toLowerCase() ?? "";
        final paramMode =
            (widget.config.params?["mode"]?.toString().toLowerCase() ?? "");

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
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Gallery picker failed: $e");
      if (mounted) {
        setState(() => _isProcessingImage = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to load image: $e")));
      }
    }
  }

  Future<void> _pickImageFromCamera(Map<String, dynamic> input) async {
    final id = input['id'];
    
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
          _inputs[id] = [bytes];
          _inputs["${id}_path"] = file.path;
          // Clear old mask when new image is captured
          _inputs["mask_image"] = null;
        _isProcessingImage = false;
        });

      if (widget.config.model == "diffusers_outpaint") {
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
      final model = widget.config.model.toLowerCase();
      final mode = _selectedModeKey?.toLowerCase() ?? "";
      final paramMode =
          (widget.config.params?["mode"]?.toString().toLowerCase() ?? "");

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
          }
        }
      }
    } catch (e) {
      debugPrint("Camera image failed: $e");
      if (mounted) {
        setState(() => _isProcessingImage = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Camera capture failed: $e")));
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
    const int maxDim = 1536;
    const int maxPixels = 700000; // ~576x1184 = 681k (safe), 800x1184 = 947k (too big)

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

  /// Theme-aware unified bottom-sheet picker
  Future<void> _pickImage(Map<String, dynamic> input) async {
    final cs = Theme.of(context).colorScheme;
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) {
          return Container(
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                    // Handle bar
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Title
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cs.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            LucideIcons.imagePlus,
                            color: cs.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          'Choose Image Source',
                    style: TextStyle(
                      fontSize: 18,
                            fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    // Options
                    Row(
                      children: [
                        // Gallery option
                        Expanded(
                          child: _buildPickerOption(
                            icon: LucideIcons.image,
                            label: 'Gallery',
                            sublabel: 'Choose from photos',
                            color: cs.primary,
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                        ),
                        const SizedBox(width: 12),
                        
                        // Camera option
                        Expanded(
                          child: _buildPickerOption(
                            icon: LucideIcons.camera,
                            label: 'Camera',
                            sublabel: 'Take a new photo',
                            color: cs.secondary,
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                          ),
                        ),
                      ],
                ),
                const SizedBox(height: 8),
              ],
                ),
              ),
            ),
          );
        },
      );

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

  /// Pick multiple images for bulk edit (VIP only)
  Future<void> _pickBulkImages() async {
    if (!canUseBulkEdit()) {
      final cs = Theme.of(context).colorScheme;
      _showVipRequiredDialog(cs, 'Bulk Edit');
      return;
    }
    
    try {
      // Calculate how many more images can be added
      final int currentCount = _bulkImages.length;
      final int remainingSlots = _maxBulkImages - currentCount;
      
      if (remainingSlots <= 0) return;
      
      final files = await picker.pickMultiImage(
        imageQuality: 85,
        limit: remainingSlots,
      );
      
      if (files.isEmpty) return;
      
      setState(() => _isProcessingImage = true);
      
      final List<Uint8List> newImages = [];
      for (final file in files) {
        if (newImages.length >= remainingSlots) break;
        final bytes = await file.readAsBytes();
        newImages.add(bytes);
      }
      
      if (mounted) {
        setState(() {
          // Append new images to existing ones instead of replacing
          _bulkImages.addAll(newImages);
          _isProcessingImage = false;
        });
        
        // ScaffoldMessenger.of(context).showSnackBar(
        //   SnackBar(
        //     content: Text('${newImages.length} image${newImages.length == 1 ? '' : 's'} added (${_bulkImages.length}/$_maxBulkImages total)'),
        //     backgroundColor: Theme.of(context).colorScheme.primary,
        //   ),
        // );
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

  /// Clear all bulk images
  void _clearBulkImages() {
    setState(() {
      _bulkImages.clear();
      _bulkMasks.clear();
      _bulkOutpaintConfigs.clear();
    });
  }

  Widget _buildBulkImagesGrid(ColorScheme cs) {
    // Calculate item height based on whether we need mask/outpaint editing
    final double itemHeight = (_requiresMask || _isOutpaint) ? 130 : 100;
    
    return SizedBox(
      height: itemHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _bulkImages.length,
        itemBuilder: (context, index) {
          final hasMask = index < _bulkMasks.length && _bulkMasks[index] != null;
          final hasOutpaintConfig = index < _bulkOutpaintConfigs.length && _bulkOutpaintConfigs[index] != null;
          
          return Padding(
            padding: EdgeInsets.only(right: index < _bulkImages.length - 1 ? 8 : 0),
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
                                ? cs.error.withOpacity(0.5)
                                : cs.primary.withOpacity(0.3),
                            width: 1.5,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                _bulkImages[index],
                                fit: BoxFit.cover,
                              ),
                              // Show mask overlay if exists
                              if (hasMask)
                                ColorFiltered(
                                  colorFilter: ColorFilter.mode(
                                    Colors.red.withOpacity(0.3),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.surface.withOpacity(0.9),
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
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: (hasMask || hasOutpaintConfig)
                                ? Colors.green.withOpacity(0.9)
                                : cs.error.withOpacity(0.9),
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
                            ? cs.primaryContainer.withOpacity(0.5)
                            : cs.errorContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _requiresMask ? LucideIcons.paintbrush : LucideIcons.move,
                            size: 12,
                            color: (hasMask || hasOutpaintConfig) ? cs.primary : cs.error,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _requiresMask 
                                ? (hasMask ? 'Edit' : 'Mask')
                                : (hasOutpaintConfig ? 'Edit' : 'Place'),
                            style: TextStyle(
                              fontSize: 10,
                              color: (hasMask || hasOutpaintConfig) ? cs.primary : cs.error,
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
  
  /// Remove bulk image at index along with its mask and outpaint config
  void _removeBulkImageAt(int index) {
    setState(() {
      _bulkImages.removeAt(index);
      if (index < _bulkMasks.length) {
        _bulkMasks.removeAt(index);
      }
      if (index < _bulkOutpaintConfigs.length) {
        _bulkOutpaintConfigs.removeAt(index);
      }
    });
  }
  
  /// Show full-screen preview for bulk image (called on long press)
  void _showBulkImagePreview(int index) {
    if (index >= _bulkImages.length) return;
    
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
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
                _bulkImages[index],
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
    if (index >= _bulkImages.length) return;
    
    if (_requiresMask) {
      // Open mask editor for this image
      final mask = await _openMaskEditor(_bulkImages[index]);
      if (mask != null && mounted) {
        setState(() {
          // Ensure list is long enough
          while (_bulkMasks.length <= index) {
            _bulkMasks.add(null);
          }
          _bulkMasks[index] = mask;
        });
      }
    } else if (_isOutpaint) {
      // Open outpaint canvas for this image
      final result = await Navigator.push<Map<String, String>>(
        context,
        MaterialPageRoute(
          builder: (_) => OutpaintCanvasPage(imageBytes: _bulkImages[index]),
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

  // Picker option card for bottom sheet
  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
        border: Border.all(
              color: cs.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
          ),
              ),
              const SizedBox(height: 4),
              Text(
                sublabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
          ),
        ],
      ),
        ),
      ),
    );
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
      margin: margin ?? const EdgeInsets.symmetric(vertical: AppStyles.spacing8),
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
      case "slider":
        return _buildSlider(ref);
      case "dropdown":
        return _buildDropdown(ref);
      case "painter":
        return _buildPainter(ref);
      case "generate_button":
        return _buildGenerateButton();
      default:
        return const SizedBox.shrink();
    }
  }

  // -------- Prompt Input Section --------
  Widget _buildPrompt(String ref) {
    final label = widget.config.inputs
            .firstWhere((i) => i["id"] == ref, orElse: () => {})["label"] ??
        "Describe what you want to create";

    return _buildPromptContent(ref, label);
  }

  /// Build the Prompt content with guided input and style pills
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        KalaColors.purple.withOpacity(0.15),
                        KalaColors.magenta.withOpacity(0.15),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: KalaColors.purple.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.sparkles, size: 12, color: KalaColors.purple),
                      const SizedBox(width: 4),
                      Text(
                        'Browse Templates',
                        style: TextStyle(
                          color: KalaColors.purple,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(LucideIcons.arrowRight, size: 10, color: KalaColors.purple),
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
                color: cs.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.primary.withOpacity(0.3),
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
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: 'Describe what you want to create...',
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.5),
                fontSize: 15,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHigh.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.2),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: cs.primary.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              suffixIcon: _promptController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        LucideIcons.x,
                        size: 18,
                        color: cs.onSurfaceVariant.withOpacity(0.6),
                      ),
                      onPressed: () {
                        _promptController.clear();
                        _inputs[ref] = '';
                        if (_selectedStyle != null) {
                          setState(() => _selectedStyle = null);
                        }
                        setState(() {});
                      },
                    )
                  : null,
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
                    color: cs.onSurfaceVariant.withOpacity(0.5),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$promptLength',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(0.6),
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
    final bool showAds = shouldShowAds();
    final styles = _getStylesByCategory(_selectedStyleCategory);
    
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle and actions
          GestureDetector(
            onTap: () => setState(() => _isEnhancerExpanded = !_isEnhancerExpanded),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    KalaColors.purple.withOpacity(0.08),
                    KalaColors.magenta.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(16),
                  bottom: _isEnhancerExpanded ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  // Animated chevron
                  AnimatedRotation(
                    turns: _isEnhancerExpanded ? 0 : -0.25,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: KalaColors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 14,
                        color: KalaColors.purple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Title with icon
                  Icon(LucideIcons.sparkle, size: 16, color: KalaColors.purple),
                  const SizedBox(width: 6),
                  Text(
                    'Style & Tags',
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // Selected style indicator (flexible to prevent overflow)
                  if (_selectedStyle != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_selectedStyle!.icon, style: const TextStyle(fontSize: 10)),
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
                  // Random button
                  if (_isEnhancerExpanded)
                    GestureDetector(
                      onTap: _applyRandomStyle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              KalaColors.purple.withOpacity(0.15),
                              KalaColors.magenta.withOpacity(0.15),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: KalaColors.purple.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.shuffle, size: 12, color: KalaColors.purple),
                            const SizedBox(width: 4),
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
          ),
          
          // Expandable content
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _isEnhancerExpanded
                ? Column(
                    children: [
                      // Tab selector (Styles / Quick Tags)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            _buildEnhancerTab(cs, 0, 'Styles', LucideIcons.palette, styles.length),
                            const SizedBox(width: 8),
                            _buildEnhancerTab(cs, 1, 'Quick Tags', LucideIcons.tag, promptHelperChips.length),
                          ],
                        ),
                      ),
                      
                      // Content based on selected tab
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: _enhancerTabIndex == 0
                            ? _buildStylesContent(cs, styles)
                            : _buildQuickTagsContent(cs),
                      ),
                      
                      // Show ad when collapsed (if applicable)
                      const SizedBox(height: 8),
                    ],
                  )
                : showAds
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: const ThemedNativeAd(
                            height: 100,
                            useSmallTemplate: true,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  /// Build enhancer tab button
  Widget _buildEnhancerTab(ColorScheme cs, int index, String label, IconData icon, int count) {
    final isSelected = _enhancerTabIndex == index;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _enhancerTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? cs.primary.withOpacity(0.12)
                : cs.surfaceContainerHigh.withOpacity(0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected 
                  ? cs.primary.withOpacity(0.4)
                  : cs.outlineVariant.withOpacity(0.15),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? cs.primary : cs.onSurfaceVariant.withOpacity(0.7),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? cs.primary : cs.onSurfaceVariant.withOpacity(0.8),
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? cs.primary.withOpacity(0.2)
                      : cs.onSurfaceVariant.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected ? cs.primary : cs.onSurfaceVariant.withOpacity(0.6),
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
              itemCount: styleCategories.length,
              itemBuilder: (context, index) {
                final category = styleCategories[index];
                final isSelected = _selectedStyleCategory == category;
                final isFavorites = category == 'Favorites';
                final favCount = _favoriteStyles.length;
                
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedStyleCategory = category),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected 
                            ? (isFavorites ? Colors.red.withOpacity(0.15) : cs.secondary.withOpacity(0.15))
                            : cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected 
                              ? (isFavorites ? Colors.red.withOpacity(0.4) : cs.secondary.withOpacity(0.4))
                              : cs.outlineVariant.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isFavorites) ...[
                            Icon(
                              Icons.favorite,
                              size: 12,
                              color: isSelected ? Colors.red : cs.onSurfaceVariant.withOpacity(0.6),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            isFavorites ? 'Favorites ($favCount)' : category,
                            style: TextStyle(
                              color: isSelected 
                                  ? (isFavorites ? Colors.red : cs.secondary)
                                  : cs.onSurfaceVariant.withOpacity(0.8),
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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
                      color: cs.onSurfaceVariant.withOpacity(0.3),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No favorites yet',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.5),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Long-press any style to add to favorites',
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
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
  Widget _buildStyleChip(ColorScheme cs, StylePreset style, bool isSelected, bool isFavorite) {
    // Get category color
    final categoryColors = {
      'Fun': const Color(0xFFFF6B6B),
      'Realistic': const Color(0xFF3B82F6),
      'Artistic': const Color(0xFF8B5CF6),
      'Anime': const Color(0xFFEC4899),
      'Cinematic': const Color(0xFFF59E0B),
    };
    final accentColor = categoryColors[style.category] ?? cs.secondary;
    
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
                    _favoriteStyles.contains(style.id) ? Icons.favorite : LucideIcons.heart,
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 2),
              backgroundColor: _favoriteStyles.contains(style.id) ? Colors.red : cs.inverseSurface,
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 100,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    colors: [
                      accentColor.withOpacity(0.2),
                      accentColor.withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isSelected ? null : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected 
                  ? accentColor.withOpacity(0.5)
                  : cs.outlineVariant.withOpacity(0.2),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Icon + Favorite/Check
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(style.icon, style: const TextStyle(fontSize: 14)),
                  ),
                  if (isSelected)
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.check, size: 10, color: Colors.white),
                    )
                  else if (isFavorite)
                    const Icon(Icons.favorite, size: 14, color: Colors.red),
                ],
              ),
              const Spacer(),
              // Name
              Text(
                style.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isSelected ? accentColor : cs.onSurface,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              // Category badge
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  style.category,
                  style: TextStyle(
                    color: accentColor.withOpacity(0.8),
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build quick tags content
  Widget _buildQuickTagsContent(ColorScheme cs) {
    // Split chips into 2 rows
    final midPoint = (promptHelperChips.length / 2).ceil();
    final firstRow = promptHelperChips.sublist(0, midPoint);
    final secondRow = promptHelperChips.sublist(midPoint);
    
    return Padding(
      key: const ValueKey('tags'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tap to add to your prompt',
            style: TextStyle(
              color: cs.onSurfaceVariant.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          // 2 rows of horizontal scrollable chips
          SizedBox(
            height: 90,
            child: Column(
              children: [
                // First row
                SizedBox(
                  height: 45,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: firstRow.length,
                    itemBuilder: (context, index) {
                      final chip = firstRow[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8, bottom: 8),
                        child: GestureDetector(
                          onTap: () => _appendChipToPrompt(chip),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: cs.outlineVariant.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(chip.icon, style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                Text(
                                  chip.label,
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
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
                // Second row
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: secondRow.length,
                    itemBuilder: (context, index) {
                      final chip = secondRow[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _appendChipToPrompt(chip),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: cs.outlineVariant.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(chip.icon, style: const TextStyle(fontSize: 14)),
                                const SizedBox(width: 6),
                                Text(
                                  chip.label,
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // -------- Image Upload with Bulk Edit Support --------
  Widget _buildImageUpload(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = _effectiveInputConfig(ref);
    final hasImage = _inputs[ref] != null && 
        (_inputs[ref] is List && (_inputs[ref] as List).isNotEmpty);
    final isVip = isVipUser();
    final isBulkMode = _advancedSettings.bulkEditEnabled && isVip;
    
    // Only show bulk mode option for tools that support it (have init_image input)
    final showBulkOption = _supportsBulkEdit;

    return _buildCard(
      elevated: hasImage || _bulkImages.isNotEmpty,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode Switch (Single / Bulk) - only for VIP with image output
          if (showBulkOption) ...[
            _buildImageModeSwitch(cs, isVip, isBulkMode),
            const SizedBox(height: 16),
          ],
          
          // Content based on mode
          if (isBulkMode)
            _buildBulkImagesContent(cs)
          else ...[
            // Single image mode - normal upload
            _buildImagePreview(ref),
            const SizedBox(height: 16),
            // Buttons row
            if (hasImage)
              Row(
                children: [
                  // Change image button
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
                  // Remove button
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
                label: "Upload Image",
                onPressed: () => _pickImage(input),
                variant: ButtonVariant.primary,
                size: ButtonSize.medium,
                expanded: true,
              ),
          ],
        ],
      ),
    );
  }

  /// Build the mode switch between Single Image and Bulk Edit
  Widget _buildImageModeSwitch(ColorScheme cs, bool isVip, bool isBulkMode) {
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
                    _advancedSettings = _advancedSettings.copyWith(bulkEditEnabled: false);
                  });
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !isBulkMode ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.image,
                      size: 16,
                      color: !isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Single',
                      style: TextStyle(
                        color: !isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
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
                if (isVip) {
                  if (!isBulkMode) {
                    setState(() {
                      _advancedSettings = _advancedSettings.copyWith(bulkEditEnabled: true);
                    });
                  }
                } else {
                  _showVipRequiredDialog(cs, 'Bulk Edit');
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isBulkMode ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      LucideIcons.layers,
                      size: 16,
                      color: isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Bulk',
                      style: TextStyle(
                        color: isBulkMode ? cs.onPrimary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    // VIP badge for non-VIP users
                    if (!isVip) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [cs.primary, cs.tertiary]),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'VIP',
                          style: TextStyle(
                            color: cs.onPrimary,
                            fontSize: 8,
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
    );
  }

  /// Build the bulk images content (replaces single image upload when bulk mode enabled)
  Widget _buildBulkImagesContent(ColorScheme cs) {
    final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
    final totalJobs = _bulkImages.isEmpty ? 0 : _bulkImages.length * variations;
    final bool exceedsLimit = totalJobs > _maxTotalJobs;
    
    // Calculate max images allowed based on current variations
    final int maxImagesForVariations = (_maxTotalJobs / variations).floor();
    final int effectiveMaxImages = maxImagesForVariations.clamp(1, _maxBulkImages);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Info bar showing count and jobs
        if (_bulkImages.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: exceedsLimit 
                  ? cs.errorContainer.withOpacity(0.3) 
                  : cs.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: exceedsLimit 
                    ? cs.error.withOpacity(0.3)
                    : cs.primary.withOpacity(0.2),
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
                        '${_bulkImages.length} images × $variations variations = $totalJobs jobs',
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
                      color: cs.errorContainer.withOpacity(0.5),
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
        if (_bulkImages.isEmpty)
          _buildBulkEmptyState(cs)
        else
          _buildBulkImagesGrid(cs),
        
        const SizedBox(height: 12),
        
        // Add images button (limit based on variations)
        GradientButton(
          icon: _bulkImages.isEmpty ? LucideIcons.imagePlus : LucideIcons.plus,
          label: _bulkImages.isEmpty 
              ? 'Select Images (up to $effectiveMaxImages)' 
              : 'Add More (${_bulkImages.length}/$effectiveMaxImages)',
          onPressed: _bulkImages.length >= effectiveMaxImages ? null : _pickBulkImages,
          variant: _bulkImages.isEmpty ? ButtonVariant.primary : ButtonVariant.secondary,
          size: ButtonSize.medium,
          expanded: true,
        ),
      ],
    );
  }

  /// Build empty state for bulk images
  Widget _buildBulkEmptyState(ColorScheme cs) {
    final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
    final int maxImagesForVariations = (_maxTotalJobs / variations).floor();
    final int effectiveMaxImages = maxImagesForVariations.clamp(1, _maxBulkImages);
    
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
            cs.surfaceContainerHigh.withOpacity(0.8),
            cs.surfaceContainerHighest.withOpacity(0.4),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [cs.primary.withOpacity(0.2), cs.tertiary.withOpacity(0.1)]),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.layers, size: 32, color: cs.primary),
          ),
          const SizedBox(height: 12),
          Text(
            'Select multiple images',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Up to $effectiveMaxImages images × $variations var = ${effectiveMaxImages * variations} jobs max',
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
              cs.surfaceContainerHigh.withOpacity(0.8),
              cs.surfaceContainerHighest.withOpacity(0.4),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.primary.withOpacity(0.3),
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
              cs.surfaceContainerHigh.withOpacity(0.8),
              cs.surfaceContainerHighest.withOpacity(0.4),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.imagePlus,
                color: cs.primary.withOpacity(0.6),
                size: 40,
              ),
            ),
            const SizedBox(height: 16),
              Text(
              "Tap to upload an image",
              style: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.7),
                fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
              "Supports PNG, JPG, WEBP",
              style: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.5),
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

    final bool isOutpaint = widget.config.model == "diffusers_outpaint";

    // Read outpaint config (from OutpaintCanvasPage)
    final String alignment =
        isOutpaint ? (_inputs["alignment"] ?? "Middle") : "Middle";
    final String ratioStr =
        isOutpaint ? (_inputs["aspect_ratio"] ?? "1:1") : "1:1";
    final bool isCustomMode = 
        isOutpaint && (_inputs["is_custom"] == "true");
    final double customScale = 
        isCustomMode ? (double.tryParse(_inputs["custom_scale"] ?? "0.7") ?? 0.7) : 1.0;
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
            color: cs.primary.withOpacity(0.3),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.check, size: 12, color: Colors.green.shade600),
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
                    padding: EdgeInsets.only(right: index < list.length - 1 ? 10 : 0),
                    child: Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: cs.primary.withOpacity(0.3),
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
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
              ? Colors.green.withOpacity(0.5)
              : cs.primary.withOpacity(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.08),
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
                            child: Image.memory(mask as Uint8List, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    // Status badge (top right)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasMask ? LucideIcons.paintbrush : LucideIcons.check,
                              size: 14,
                              color: hasMask ? Colors.red.shade300 : Colors.green.shade300,
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
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: hasMask 
                                  ? cs.surfaceContainerHigh 
                                  : cs.primary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: hasMask 
                                    ? cs.outline.withOpacity(0.3)
                                    : cs.primary,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasMask ? LucideIcons.edit3 : LucideIcons.paintbrush,
                                  size: 16,
                                  color: hasMask ? cs.onSurface : cs.onPrimary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  hasMask ? "Edit Mask" : "Draw Mask",
                                  style: TextStyle(
                                    color: hasMask ? cs.onSurface : cs.onPrimary,
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
            _buildExpansionIndicator(alignment, cs),
            
            // Image ready indicator
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
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
            color: cs.primary.withOpacity(0.8),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: cs.onPrimary),
        ),
      ),
    );
  }

  // -------- Slider --------
  Widget _buildSlider(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    final label = input["label"] ?? ref;
    _inputs[ref] ??= input["default"] ?? input["min"] ?? 1.0;
    final minVal = (input["min"] as num?)?.toDouble() ?? 0;
    final maxVal = (input["max"] as num?)?.toDouble() ?? 100;
    final currentVal = (_inputs[ref] as num).toDouble();
    
    return _buildCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.sliders,
                    size: 18,
                    color: cs.primary,
                  ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                    label,
                  style: TextStyle(
                      color: cs.onSurface,
                    fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  currentVal.toStringAsFixed(currentVal % 1 == 0 ? 0 : 1),
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: cs.primary,
              inactiveTrackColor: cs.outlineVariant.withOpacity(0.3),
              thumbColor: cs.primary,
              overlayColor: cs.primary.withOpacity(0.15),
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            ),
            child: Slider(
              value: currentVal.clamp(minVal, maxVal),
              min: minVal,
              max: maxVal,
              divisions: ((maxVal - minVal) * 10).round().clamp(1, 100),
              onChanged: (v) => setState(() => _inputs[ref] = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  minVal.toStringAsFixed(minVal % 1 == 0 ? 0 : 1),
                  style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.6),
                    fontSize: 12,
                ),
              ),
              Text(
                  maxVal.toStringAsFixed(maxVal % 1 == 0 ? 0 : 1),
                  style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.6),
                    fontSize: 12,
                ),
              ),
            ],
            ),
          ),
        ],
      ),
    );
  }

  // -------- Dropdown (ChoiceChips) --------
  Widget _buildDropdown(String ref) {
    final cs = Theme.of(context).colorScheme;
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    final label = input["label"] ?? ref;
    final options = List<String>.from(input["options"] ?? []);
    _inputs[ref] ??= options.isNotEmpty ? options.first : null;

    return _buildCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                LucideIcons.list,
                size: 18,
                  color: cs.secondary,
              ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: options.map((opt) {
                  final isSelected = _inputs[ref] == opt;
              return Material(
                color: isSelected
                    ? cs.primary
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                    onTap: () => setState(() => _inputs[ref] = opt),
                    borderRadius: BorderRadius.circular(12),
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                            ? cs.primary
                            : cs.outlineVariant.withOpacity(0.3),
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: cs.primary.withOpacity(0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) ...[
                          Icon(
                            LucideIcons.check,
                            size: 16,
                            color: cs.onPrimary,
                      ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                        opt,
                          style: TextStyle(
                          color: isSelected
                                ? cs.onPrimary
                              : cs.onSurfaceVariant,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                        ),
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

  Widget _buildDynamicInputScreen() {
    final cs = Theme.of(context).colorScheme;
    // Get safe area padding for devices with home bar/navigation buttons
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    
    // Filter out generate_button from elements (will be rendered in sticky footer)
    final contentElements = _currentElements
        .where((e) => e["type"] != "generate_button")
        .toList();
    
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
                top: 8,
                bottom: 8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Mode selector (if applicable)
                  if (widget.config.modes != null && widget.config.modes!.isNotEmpty) ...[
                    _buildModeSelector(),
                    const SizedBox(height: 4),
                  ],
                  
                  // Dynamic elements (without generate button)
                  ...contentElements.map((e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _buildElement(e),
                    );
                  }),
                ],
              ),
            ),
          ),
          
          // Sticky bottom area with settings + generate button
          _buildStickyGenerateFooter(bottomSafeArea),
        ],
      ),
    );
  }

  /// Build the sticky footer with settings and generate button
  Widget _buildStickyGenerateFooter(double bottomSafeArea) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = _areRequiredInputsFilled();
    final missingInputs = _getMissingInputs();
    
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + bottomSafeArea,
      ),
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: cs.outlineVariant.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
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
                        bgColor = cs.primaryContainer.withOpacity(0.3);
                        borderColor = cs.primary.withOpacity(0.2);
                        textColor = cs.primary.withOpacity(0.9);
                        hintIcon = LucideIcons.loader;
                      } else if (isRateLimitHint) {
                        // Rate limit - use amber/orange for "busy" feeling
                        bgColor = Colors.amber.withOpacity(0.15);
                        borderColor = Colors.amber.withOpacity(0.3);
                        textColor = Colors.amber.shade800;
                        hintIcon = LucideIcons.sparkles;
                      } else {
                        // Missing input - use subtle red
                        bgColor = cs.errorContainer.withOpacity(0.3);
                        borderColor = cs.error.withOpacity(0.2);
                        textColor = cs.error.withOpacity(0.9);
                        hintIcon = LucideIcons.alertCircle;
                      }
                      
                      // Format message for display
                      final String displayMessage;
                      if (isProcessing) {
                        displayMessage = "Processing image...";
                      } else if (isRateLimitHint) {
                        // Remove emoji and show cleaner message
                        displayMessage = missingInputs.first.replaceAll('⏳ ', '');
                      } else {
                        displayMessage = "Add ${missingInputs.join(' & ')} to continue";
                      }
                      
                      // Calculate jobs for rate limit sheet
                      final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
                      final int imageCount = _advancedSettings.bulkEditEnabled && _bulkImages.isNotEmpty 
                          ? _bulkImages.length 
                          : 1;
                      final int totalJobsToSubmit = imageCount * variations;
                      
                      return GestureDetector(
                        onTap: isRateLimitHint ? () => _showRateLimitErrorSheet('', totalJobsToSubmit) : null,
                        child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                              color: cs.primary.withOpacity(0.8),
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
                            color: textColor.withOpacity(0.6),
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
          _buildSettingsSummary(cs),
          
          // Settings button + Generate button row
          Row(
            children: [
              // Settings button
              InkWell(
                onTap: _showAdvancedSettings,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.3),
                    ),
                  ),
                  child: Icon(
                    LucideIcons.settings,
                    size: 22,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              
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
        widget.config.models?.firstWhere(
          (m) => m['id'] == widget.config.model,
          orElse: () => {'name': widget.config.model},
        )['name'] as String? ?? 
        widget.config.model;
    
    // Check upscale status
    final isUpscaled = _advancedSettings.upscaleOutput;
    final scaleFactor = _scaleFactor;
    final variations = _advancedSettings.variations;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: _showAdvancedSettings,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.15),
            ),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.info,
                size: 14,
                color: cs.onSurfaceVariant.withOpacity(0.6),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Model name chip
                    _buildSummaryChip(
                      cs,
                      icon: LucideIcons.cpu,
                      label: modelName,
                      highlight: true,
                    ),
                    // Upscale status chip
                    _buildSummaryChip(
                      cs,
                      icon: isUpscaled ? LucideIcons.maximize2 : LucideIcons.minimize2,
                      label: isUpscaled ? '${scaleFactor}x Upscale' : 'No Upscale',
                      highlight: isUpscaled,
                      isPositive: isUpscaled,
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
                color: cs.onSurfaceVariant.withOpacity(0.4),
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
            ? chipColor.withOpacity(0.1)
            : cs.surfaceContainerHigh.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: highlight 
              ? chipColor.withOpacity(0.2)
              : cs.outlineVariant.withOpacity(0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: chipColor.withOpacity(highlight ? 1.0 : 0.6),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: chipColor.withOpacity(highlight ? 0.9 : 0.7),
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
    final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
    
    // Check if upscale is enabled
    final bool isUpscaled = _advancedSettings.upscaleOutput && _scaleFactor > 1;
    
    // VIP benefits
    final int imageCount = _advancedSettings.bulkEditEnabled && _bulkImages.isNotEmpty 
        ? _bulkImages.length 
        : 1;
    
    // Total jobs = images × variations
    final int totalJobs = imageCount * variations;

    // Use the unified cost calculation that includes variations
    final totalCost = _calculateTotalCost();
    
    // Calculate cost before discount (for showing strikethrough if offer or VIP free upscale)
    final baseCostPerVariation = _currentModelCost + (isUpscaled ? _currentModelUpscaleCost : 0);
    final totalBeforeDiscount = baseCostPerVariation * variations * imageCount;

    // Check if button should be enabled
    final isEnabled = _areRequiredInputsFilled();
    
    // Check if we have multiple images or variations (show compact summary)
    final bool showJobCount = totalJobs > 1;

    return AnimatedBuilder(
      animation: _glowAnimationController,
      builder: (context, child) {
        final glowOpacity = isEnabled 
            ? 0.3 + (_glowAnimationController.value * 0.2) 
            : 0.0;
        
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: KalaColors.purple.withOpacity(glowOpacity),
                      blurRadius: 16 + (_glowAnimationController.value * 8),
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: KalaColors.cyan.withOpacity(glowOpacity * 0.6),
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
                      : [cs.onSurfaceVariant.withOpacity(0.4), cs.onSurfaceVariant.withOpacity(0.3)],
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
                          final rateLimitError = checkRateLimitForSubmission(totalJobs);
                          if (rateLimitError != null) {
                            _showRateLimitErrorSheet(rateLimitError, totalJobs);
                          }
                        },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                        const Text(
                          "Generate",
                          style: TextStyle(
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
                          color: Colors.white.withOpacity(0.3),
                        ),
                        
                        // Compact job count badge (when multiple jobs)
                        if (showJobCount) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
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
                              color: Colors.white.withOpacity(0.9),
                            ),
                            const SizedBox(width: 3),
                            if (offer > 0 && totalBeforeDiscount != totalCost) ...[
                              Text(
                                "$totalBeforeDiscount",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 11,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.white.withOpacity(0.5),
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
    final isBulkMode = _advancedSettings.bulkEditEnabled && _bulkImages.isNotEmpty;
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
    final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
    final imageCount = _bulkImages.length;
    final totalJobs = imageCount * variations;
    final totalCost = _calculateTotalCost();
    final isUpscaled = _advancedSettings.upscaleOutput && _scaleFactor > 1;
    final freeUpscale = isUpscaleFree();
    
    // Get model name
    final modelName = _selectedModelData?['name'] as String? ?? 
        widget.config.models?.firstWhere(
          (m) => m['id'] == widget.config.model,
          orElse: () => {'name': widget.config.title},
        )['name'] as String? ?? 
        widget.config.title;
    
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A2E) : cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: cs.primary.withOpacity(0.2),
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
                    MediaQuery.of(ctx).viewPadding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
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
                      KalaColors.purple.withOpacity(0.2),
                      KalaColors.cyan.withOpacity(0.2),
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
                  color: cs.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 24),
              
              // Job details card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.outline.withOpacity(0.1),
                  ),
                ),
                child: Column(
                  children: [
                    // Tool name
                    _buildConfirmDetailRow(
                      cs,
                      icon: LucideIcons.sparkles,
                      label: 'Tool',
                      value: widget.config.title,
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
                    
                    // Images
                    _buildConfirmDetailRow(
                      cs,
                      icon: LucideIcons.image,
                      label: 'Images',
                      value: '$imageCount image${imageCount > 1 ? 's' : ''}',
                      iconColor: Colors.blue,
                    ),
                    const SizedBox(height: 12),
                    
                    // Variations
                    _buildConfirmDetailRow(
                      cs,
                      icon: LucideIcons.copy,
                      label: 'Variations',
                      value: '$variations per image',
                      iconColor: Colors.orange,
                    ),
                    const SizedBox(height: 12),
                    
                    // Upscale
                    if (isUpscaled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildConfirmDetailRow(
                          cs,
                          icon: LucideIcons.maximize,
                          label: 'Upscale',
                          value: '${_scaleFactor}x${freeUpscale ? ' (FREE VIP)' : ''}',
                          iconColor: Colors.green,
                          valueColor: freeUpscale ? Colors.green : null,
                        ),
                      ),
                    
                    // Divider
                    Divider(color: cs.outline.withOpacity(0.2)),
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
                    const SizedBox(height: 12),
                    
                    // Total cost
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
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
                            color: cs.onSurface.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.amber.withOpacity(0.2),
                                Colors.orange.withOpacity(0.2),
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
                        side: BorderSide(color: cs.outline.withOpacity(0.3)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.7),
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
                            color: KalaColors.purple.withOpacity(0.3),
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
            color: iconColor.withOpacity(0.15),
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
            color: cs.onSurface.withOpacity(0.7),
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

  Widget _buildModeSelector() {
    final cs = Theme.of(context).colorScheme;
    final modes = widget.config.modes!;
    final modeKeys = modes.keys.toList();

    return _buildCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                LucideIcons.layers,
                size: 18,
                color: cs.primary,
              ),
              ),
              const SizedBox(width: 12),
              Text(
                "Mode",
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Mode pills
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh.withOpacity(0.6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
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
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                                colors: KalaColors.brandGradient,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: KalaColors.purple.withOpacity(0.35),
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
                            color: selected
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
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
                  color: Colors.orange.withOpacity(0.1),
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
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CreditsPage()),
                    );
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
      subtitle = 'You want $jobsRequested jobs but only $available slot${available > 1 ? 's' : ''} available';
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
                      iconColor.withOpacity(0.15),
                      iconColor.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withOpacity(0.2),
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
                  color: cs.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.2),
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
                            color: cs.outlineVariant.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: maxJobs > 0 ? currentProcessing / maxJobs : 0,
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
                                  color: (percentUsed >= 100 ? Colors.orange : cs.primary)
                                      .withOpacity(0.3),
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
                        color: cs.onSurfaceVariant.withOpacity(0.7),
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
                  color: cs.primaryContainer.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.2)),
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
                          selectedIndexNotifier.value = 2;
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
                    color: cs.primaryContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: cs.primary.withOpacity(0.3)),
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
                        Colors.amber.withOpacity(0.15),
                        Colors.orange.withOpacity(0.1),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(LucideIcons.crown, size: 18, color: Colors.amber.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Upgrade to VIP for 25 concurrent jobs (5x more!) plus bulk edit, free upscale & more!',
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
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
              color: cs.onSurfaceVariant.withOpacity(0.8),
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

  Future<void> _runJob() async {
    // Prevent double execution from rapid taps
    if (_isSubmittingJob) {
      debugPrint("⚠️ Job submission already in progress, ignoring tap");
      return;
    }
    _isSubmittingJob = true;

    final cs = Theme.of(context).colorScheme;

    // --- Calculate total jobs for rate limiting ---
    final variations = _advancedSettings.variations.clamp(1, getMaxVariations());
    final int imageCount = _advancedSettings.bulkEditEnabled && _bulkImages.isNotEmpty 
        ? _bulkImages.length 
        : 1;
    final int totalJobsToSubmit = imageCount * variations;
    
    // --- RATE LIMITING CHECK ---
    // Prevents server overload by limiting concurrent processing jobs
    // Non-VIP: max 5 processing, VIP: max 25 processing
    final rateLimitError = checkRateLimitForSubmission(totalJobsToSubmit);
    if (rateLimitError != null) {
      _isSubmittingJob = false;
      if (mounted) {
        _showRateLimitErrorSheet(rateLimitError, totalJobsToSubmit);
      }
      return;
    }

    // --- Check if user is signed in ---
    if (!AuthService().isSignedIn) {
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

    // --- Ensure all live UI values are captured ---
    if (_hasPrompt) {
      _inputs["prompt"] = _promptController.text.trim();
    }
    if (_hasScaleFactor || _inputs.containsKey("scale_factor")) {
      _inputs["scale_factor"] = _upscaleEnabled ? _scaleFactor : 1;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outlineVariant.withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withOpacity(0.08),
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
                    color: cs.primary.withOpacity(0.08),
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
                      color: cs.onSurfaceVariant.withOpacity(0.8),
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
        // --- Clone _inputs for encoding ---
        final encoded = Map<String, dynamic>.from(_inputs);

        // 🩵 Ensure prompt is included even if empty in _inputs
        if (_hasPrompt &&
            (encoded["prompt"] == null ||
                (encoded["prompt"] is String &&
                    (encoded["prompt"] as String).isEmpty))) {
          encoded["prompt"] = _promptController.text.trim();
        }

        // 🩵 Auto-inject mode for multi-mode tools (WAN / SDXL)
        if (widget.config.params?.containsKey("mode") == true &&
            _selectedModeKey != null &&
            !_inputs.containsKey("mode")) {
          encoded["mode"] = _selectedModeKey;
          debugPrint("🧩 Injected mode: $_selectedModeKey");
        }

        // 🩵 Fallback: make sure root_params prompt is filled
        if (widget.config.rootParams != null &&
            !widget.config.rootParams!.containsKey("prompt")) {
          widget.config.rootParams!["prompt"] = "{{prompt}}";
        }

        // Helper to ensure clean base64 encoding with proper padding
        String encodeToCleanBase64(Uint8List bytes) {
          // Encode to base64 (standard RFC 4648)
          // Dart's base64Encode always produces correctly padded base64
          String b64 = base64Encode(bytes);
          
          // Remove any whitespace (shouldn't be there, but just in case)
          b64 = b64.replaceAll(RegExp(r'\s+'), '');
          
          // Validate: length should be multiple of 4
          final len = b64.length;
          final mod4 = len % 4;
          
          // If not multiple of 4, fix padding
          if (mod4 != 0) {
            // Strip existing = and recalculate
            final stripped = b64.replaceAll('=', '');
            final strippedMod4 = stripped.length % 4;
            if (strippedMod4 == 0) {
              b64 = stripped; // No padding needed
            } else {
              b64 = stripped + ('=' * (4 - strippedMod4));
            }
            debugPrint('⚠️ Fixed base64 padding: $len → ${b64.length} chars');
          }
          
          // Final validation
          final isValid = RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(b64);
          final ends = b64.length > 12 ? b64.substring(b64.length - 12) : b64;
          
          debugPrint('📦 Base64: ${bytes.length} bytes → ${b64.length} chars, mod4=${b64.length % 4}, valid=$isValid, ends: $ends');
          
          if (!isValid) {
            debugPrint('⚠️ Invalid base64! First 50 chars: ${b64.substring(0, min(50, b64.length))}');
          }
          
          return b64;
        }

        // Encode Uint8List images → base64
        for (final key in encoded.keys.toList()) {
          final val = encoded[key];
          if (val is Uint8List) {
            encoded[key] = encodeToCleanBase64(val);
          } else if (val is List) {
            if (val.isEmpty) {
              encoded.remove(key);
              continue;
            }
            if (val.first is Uint8List) {
              encoded[key] = val.length == 1
                  ? encodeToCleanBase64(val.first as Uint8List)
                  : val.map((e) => encodeToCleanBase64(e as Uint8List)).toList();
            } else {
              encoded[key] = val.length == 1 ? val.first : val;
            }
          }
        }

        // 🩵 Safe default for sliders (avoid missing scale_factor)
        if (!encoded.containsKey("scale_factor")) {
          final def = widget.config.inputs.firstWhere(
              (i) => i["id"] == "scale_factor",
              orElse: () => {"default": 1});
          encoded["scale_factor"] = def["default"] ?? 1;
        }

        // --- Auto width/height inference (with null safety) ---
        try {
          final imgInput = widget.config.inputs
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
            final overrides = _selectedModelData?['inputOverrides'] as Map<String, dynamic>?;
            if (overrides != null && overrides.isNotEmpty) {
              for (final entry in overrides.entries) {
                final baseId = entry.key;
                final o = entry.value;
                if (o is Map && o['id'] is String) {
                  final overrideId = o['id'] as String;

                  // If template asks for overrideId (e.g. "images"), return the base value ("init_image").
                  if (overrideId == refId ||
                      overrideId.replaceAll('-', '_') == refId.replaceAll('-', '_')) {
                    if (encoded.containsKey(baseId)) return encoded[baseId];
                  }

                  // If template asks for baseId, return overrideId value (in case UI stored it there).
                  if (baseId == refId ||
                      baseId.replaceAll('-', '_') == refId.replaceAll('-', '_')) {
                    if (encoded.containsKey(overrideId)) return encoded[overrideId];
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
            final def = widget.config.inputs.firstWhere(
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
        final Map<String, dynamic>? modelParams = 
            _selectedModelData?['params'] as Map<String, dynamic>? ?? 
            widget.config.params;
        final Map<String, dynamic>? modelRootParams = 
            _selectedModelData?['rootParams'] as Map<String, dynamic>? ?? 
            widget.config.rootParams;

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
                debugPrint('⚠️ Unresolved param placeholder {{$ref}} for key="$key" (model=${_selectedModelId ?? widget.config.model})');
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
              debugPrint('⚠️ Unresolved root placeholder {{$refId}} for key="$key" (model=${_selectedModelId ?? widget.config.model})');
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
        // CFG Scale
        resolvedParams["cfg_scale"] = _advancedSettings.cfgScale;
        
        // Scale factor from upscale settings (1 = off, 2 or 4 = on)
        // scale_image is always true, only scale_factor changes
        resolvedParams["scale_factor"] = _advancedSettings.upscaleOutput ? _scaleFactor : 1;
        resolvedParams["scale_image"] = true;
        
        // Calculate height/width based on aspect ratio selection
        // If "Default" - use image's original dimensions (already set from image inference above)
        // Otherwise - calculate based on selected aspect ratio
        if (_advancedSettings.aspectRatio != 'Default') {
          final selectedRatio = _advancedSettings.aspectRatio;
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
            
            // Round to nearest 32 (required by most models)
            int roundTo32(int x) => ((x / 32).round() * 32).clamp(32, 2048);
            resolvedParams["width"] = roundTo32(newWidth);
            resolvedParams["height"] = roundTo32(newHeight);
          }
        }
        
        // --- Add outpaint-specific params ---
        if (_isOutpaint) {
          // Basic outpaint params
          resolvedParams["alignment"] = _inputs["alignment"] ?? "Middle";
          resolvedParams["aspect_ratio"] = _inputs["aspect_ratio"] ?? "1:1";
          
          // Custom mode params
          final bool isCustomMode = _inputs["is_custom"] == "true";
          if (isCustomMode) {
            resolvedParams["is_custom_mode"] = true;
            resolvedParams["custom_scale"] = double.tryParse(_inputs["custom_scale"] ?? "0.7") ?? 0.7;
            resolvedParams["norm_offset_x"] = double.tryParse(_inputs["norm_offset_x"] ?? "0") ?? 0.0;
            resolvedParams["norm_offset_y"] = double.tryParse(_inputs["norm_offset_y"] ?? "0") ?? 0.0;
            // Canvas and image dimensions for backend calculation
            resolvedParams["canvas_width"] = double.tryParse(_inputs["canvas_width"] ?? "0");
            resolvedParams["canvas_height"] = double.tryParse(_inputs["canvas_height"] ?? "0");
            resolvedParams["image_width"] = double.tryParse(_inputs["image_width"] ?? "0");
            resolvedParams["image_height"] = double.tryParse(_inputs["image_height"] ?? "0");
            resolvedParams["image_left"] = double.tryParse(_inputs["image_left"] ?? "0");
            resolvedParams["image_top"] = double.tryParse(_inputs["image_top"] ?? "0");
          }
          
          debugPrint("🖼️ Outpaint params: alignment=${resolvedParams["alignment"]}, "
              "aspect=${resolvedParams["aspect_ratio"]}, custom=$isCustomMode");
        }

        // --- Build payload ---
        // Send ONE request with variations: N, server creates N jobs internally
        final modelId = _selectedModelId ?? widget.config.model;
        // Server enforces max variations: 2 for non-VIP, 4 for VIP
        // Client-side clamp is just for preview - server is authoritative
        final int requestedVariations =
            _advancedSettings.variations.clamp(1, getMaxVariations());
        
        // Check if bulk edit is enabled (VIP only)
        final bool isBulkEdit = _advancedSettings.bulkEditEnabled && 
            _bulkImages.isNotEmpty && 
            canUseBulkEdit();

        final basePayload = <String, dynamic>{
          "model": modelId,
          "params": resolvedParams,
          "fcm_token": fcmToken,
          // Root level settings (not in params)
          "enhance_prompt": _advancedSettings.enhancePrompt,
          // Server will create N jobs internally based on variations count
          // Server enforces VIP limits (max 2 for non-VIP, max 4 for VIP)
          "variations": requestedVariations,
          // Bulk edit flag - server validates VIP status before processing
          "is_bulk": isBulkEdit,
          ...rootParams,
        };
        
        // Add bulk images if bulk edit is enabled
        if (isBulkEdit) {
          // Convert bulk images to base64 for submission
          final List<String> bulkImagesBase64 = _bulkImages
              .map((bytes) => base64Encode(bytes))
              .toList();
          basePayload["bulk_images"] = bulkImagesBase64;
          
          // Remove single init_image from params when bulk edit is enabled
          // Server will use bulk_images instead
          resolvedParams.remove("init_image");
          resolvedParams.remove("image");
          debugPrint("📦 Bulk edit enabled: ${_bulkImages.length} images");
          
          // Add bulk masks if this is an inpaint tool
          if (_requiresMask && _bulkMasks.isNotEmpty) {
            final List<String?> bulkMasksBase64 = [];
            for (int i = 0; i < _bulkImages.length; i++) {
              if (i < _bulkMasks.length && _bulkMasks[i] != null) {
                bulkMasksBase64.add(base64Encode(_bulkMasks[i]!));
              } else {
                bulkMasksBase64.add(null);
              }
            }
            basePayload["bulk_masks"] = bulkMasksBase64;
            debugPrint("🎭 Added ${bulkMasksBase64.where((m) => m != null).length} masks for bulk edit");
          }
          
          // Add bulk outpaint configs if this is an outpaint tool
          if (_isOutpaint && _bulkOutpaintConfigs.isNotEmpty) {
            final List<Map<String, String>?> configs = [];
            for (int i = 0; i < _bulkImages.length; i++) {
              if (i < _bulkOutpaintConfigs.length) {
                configs.add(_bulkOutpaintConfigs[i]);
              } else {
                configs.add(null);
              }
            }
            basePayload["bulk_outpaint_configs"] = configs;
            debugPrint("🖼️ Added ${configs.where((c) => c != null).length} outpaint configs for bulk edit");
          }
        }

        debugPrint("🎯 Using model: $modelId");
        debugPrint(
          "🔧 Advanced settings - enhance: ${_advancedSettings.enhancePrompt}, "
          "variations: $requestedVariations, bulk: $isBulkEdit, "
          "cfg: ${_advancedSettings.cfgScale}, aspect: ${_advancedSettings.aspectRatio}",
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

        // Save input preview(s) - for bulk edit, save each image separately
        String? inputImageLocalPath;
        List<String> bulkImagePaths = [];
        
        try {
          final tmpDir = await FileService.getTempDir();
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          
          if (isBulkEdit && _bulkImages.isNotEmpty) {
            // For bulk edit: save each bulk image to disk for preview
            for (int imgIdx = 0; imgIdx < _bulkImages.length; imgIdx++) {
              final thumbFile = File(
                  '${tmpDir.path}/bulk_thumb_${timestamp}_$imgIdx.jpg');
              await thumbFile.writeAsBytes(_bulkImages[imgIdx], flush: true);
              bulkImagePaths.add(thumbFile.path);
            }
            debugPrint("📷 Saved ${bulkImagePaths.length} bulk image previews");
          } else {
            // For single image: save the input image
            final imageInput = widget.config.inputs
                .firstWhere((i) => i["type"] == "image", orElse: () => {});
            if (imageInput.isNotEmpty) {
              final id = imageInput["id"];
              final dat = _inputs[id];
              if (dat != null &&
                  dat is List &&
                  dat.isNotEmpty &&
                  dat.first is Uint8List) {
                final thumbFile = File(
                    '${tmpDir.path}/thumb_$timestamp.jpg');
                await thumbFile.writeAsBytes(dat.first as Uint8List, flush: true);
                inputImageLocalPath = thumbFile.path;
              } else {
                final existingPath = _inputs["${id}_path"];
                if (existingPath != null && File(existingPath).existsSync()) {
                  inputImageLocalPath = existingPath;
                }
              }
            }
          }
        } catch (e) {
          debugPrint("⚠️ Could not save stable input preview: $e");
        }

        final String? originalPrompt = _inputs["prompt"] as String?;
        final List<JobModel> createdJobs = [];

        // Clone params for submit to avoid any accidental mutation.
        final paramsForSubmit = Map<String, dynamic>.from(resolvedParams);
        if (paramsForSubmit["init_image"] is List) {
          paramsForSubmit["init_image"] = List<dynamic>.from(paramsForSubmit["init_image"] as List);
        }

        // Backend only expects init_image (not images). If images was set, move it to init_image.
        if (!paramsForSubmit.containsKey("init_image") &&
            paramsForSubmit.containsKey("images")) {
          paramsForSubmit["init_image"] = paramsForSubmit["images"];
        }
        // Always remove the "images" key - backend expects only init_image.
        paramsForSubmit.remove("images");

        final dynamic ii = paramsForSubmit["init_image"];
        final int iiCount = ii is List
            ? ii.length
            : (ii is String && ii.isNotEmpty ? 1 : 0);
        debugPrint(
          "🖼️ Submit with variations=$requestedVariations, init_image_count=$iiCount type=${ii.runtimeType}",
        );

        // Submit ONE request - server creates N jobs internally
        dynamic data;
        for (int submitAttempt = 1; submitAttempt <= maxRetries; submitAttempt++) {
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
            downloadUrls.addAll((data["download_urls"] as List).map((e) => e?.toString()));
          }
        } else if (data["job_id"] != null) {
          // Single job_id (backwards compatibility or variations=1)
          jobIds.add(data["job_id"].toString());
          downloadUrls.add(data["download_url"]?.toString() ?? data["downloadUrl"]?.toString());
        }

        if (jobIds.isEmpty) {
          throw Exception("No job_id(s) returned from submit");
        }

        debugPrint("✅ Server created ${jobIds.length} job(s): $jobIds");

        // Create a JobModel for each job_id returned
        // For bulk edit: jobs are ordered as [img1_var1, img1_var2, ..., img2_var1, img2_var2, ...]
        for (int i = 0; i < jobIds.length; i++) {
          final jobId = jobIds[i];
          final downloadUrl = i < downloadUrls.length ? downloadUrls[i] : null;
          
          // Determine which input image this job corresponds to
          String? jobInputImagePath;
          if (isBulkEdit && bulkImagePaths.isNotEmpty) {
            // Calculate which bulk image this job belongs to
            // Server creates jobs in order: img0_var0, img0_var1, img1_var0, img1_var1, ...
            final imageIndex = i ~/ requestedVariations;
            if (imageIndex < bulkImagePaths.length) {
              jobInputImagePath = bulkImagePaths[imageIndex];
            }
          } else {
            jobInputImagePath = inputImageLocalPath;
          }
          
          final String title = await generateFriendlyJobName();
          final newJob = JobModel(
            jobId: jobId,
            title: title,
            model: widget.config.model,
            outputType: widget.config.outputType,
            downloadUrl: downloadUrl,
            status: 'processing',
            inputImagePath: jobInputImagePath,
            variations: 1, // Each job is a single variation
            allCompleted: false,
            enhancedPrompt: enhancedPromptFromServer,
            promptEnhanced: promptWasEnhanced,
            originalPrompt: originalPrompt,
          );

          createdJobs.add(newJob);
          
          // ✅ Add job to notifier IMMEDIATELY so FCM handlers find it
          // This prevents ghost records from being created by FCM race conditions
          await addOrUpdateJob(newJob);

          final jobContext = {
            "title": widget.config.title,
            "model": widget.config.model,
            "inputs": widget.config.inputs,
            "params": widget.config.params,
            "outputType": widget.config.outputType,
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

        debugPrint("✅ Submitted 1 request, created ${createdJobs.length} job(s) for $requestedVariations variation(s)");
        return;
      } catch (e) {
        debugPrint("❌ Job submission attempt $attempt failed: $e");
        if (attempt >= maxRetries) {
          dismissDialog();
          _isSubmittingJob = false;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      "Error submitting job after $maxRetries retries: $e")),
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

  // -------- Painter (Mask Editor) --------
  Future<Uint8List?> _openMaskEditor(Uint8List base) async {
    try {
      return await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (_) => MaskEditorPage(
            baseImageBytes: base,
            existingMask: _inputs["mask_image"],
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

// ------------------ MASK EDITOR ------------------
class MaskEditorPage extends StatefulWidget {
  final Uint8List baseImageBytes;
  final Uint8List? existingMask;

  const MaskEditorPage({
    super.key,
    required this.baseImageBytes,
    this.existingMask,
  });

  @override
  State<MaskEditorPage> createState() => _MaskEditorPageState();
}

class _MaskEditorPageState extends State<MaskEditorPage> {
  ui.Image? _image;
  bool _loading = true;
  ui.Image? _maskOverlay;

  // strokes: list of drawn strokes (in image pixel coordinates)
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;

  double _brushSize = 50.0;
  bool _eraser = false;
  
  // Zoom and pan state
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  Offset _baseOffset = Offset.zero;
  bool _isZooming = false;
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
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

  // Convert local widget pos to image pixel coords (accounting for zoom/pan)
  Offset _toImageCoords(Offset localPos, Size displaySize) {
    // First, reverse the pan and scale transformations
    // The canvas center is at displaySize / 2
    final centerX = displaySize.width / 2;
    final centerY = displaySize.height / 2;
    
    // Transform local position back to unscaled/unpanned coordinates
    // localPos is relative to the top-left of the display area
    // The transform is: scaled around center, then translated by offset
    final unscaledX = (localPos.dx - centerX - _offset.dx) / _scale + centerX;
    final unscaledY = (localPos.dy - centerY - _offset.dy) / _scale + centerY;
    
    // Now convert to image coordinates
    final xInImageSpace = (unscaledX / displaySize.width) * _image!.width;
    final yInImageSpace = (unscaledY / displaySize.height) * _image!.height;
    return Offset(
      xInImageSpace.clamp(0.0, _image!.width.toDouble()),
      yInImageSpace.clamp(0.0, _image!.height.toDouble()),
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
    return byteData!.buffer.asUint8List();
  }

  void _clearAll() {
    setState(() {
      _strokes.clear();
      _maskOverlay?.dispose();
      _maskOverlay = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF0D0D0D) : cs.surface,
        appBar: AppBar(
          title: const Text("Draw Mask"),
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
          title: const Text("Draw Mask"),
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

    final hasMask = _strokes.isNotEmpty || _maskOverlay != null;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D0D) : cs.surface,
      appBar: AppBar(
        title: const Text("Draw Mask"),
        backgroundColor: Colors.transparent,
        foregroundColor: cs.onSurface,
        elevation: 0,
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
      body: SafeArea(
        child: Column(
          children: [
            // Instructions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.info, size: 18, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _eraser
                            ? "Erase mode • Pinch to zoom"
                            : "Draw to mask • Pinch to zoom",
                        style: TextStyle(
                          color: cs.onSurface.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    // Zoom indicator
                    if (_scale != 1.0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "${(_scale * 100).toInt()}%",
                          style: TextStyle(
                            color: cs.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Canvas area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: LayoutBuilder(builder: (context, constraints) {
                    final widgetSize = constraints.biggest;
                    final imgW = _image!.width.toDouble();
                    final imgH = _image!.height.toDouble();
                    final imgAspect = imgW / imgH;
                    final widgetAspect = widgetSize.width / widgetSize.height;

                    double displayW, displayH;
                    if (imgAspect > widgetAspect) {
                      displayW = widgetSize.width;
                      displayH = displayW / imgAspect;
                    } else {
                      displayH = widgetSize.height;
                      displayW = displayH * imgAspect;
                    }

                    final displaySize = Size(displayW, displayH);

                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: cs.outline.withOpacity(0.3),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRect(
                        child: SizedBox(
                          width: displayW,
                          height: displayH,
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
                              _pointerCount = (_pointerCount - 1).clamp(0, 10);
                              if (_pointerCount < 2) {
                                _isZooming = false;
                              }
                            },
                            onPointerCancel: (_) {
                              _pointerCount = (_pointerCount - 1).clamp(0, 10);
                              if (_pointerCount < 2) {
                                _isZooming = false;
                              }
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: (details) {
                                _baseScale = _scale;
                                _baseOffset = _offset;
                                if (_pointerCount < 2) {
                                  // Single finger: start drawing
                                  final local = details.localFocalPoint;
                                  final imgPos = _toImageCoords(local, displaySize);
                                  _currentStroke = _Stroke(
                                    points: [imgPos],
                                    size: _brushSize,
                                    eraser: _eraser,
                                  );
                                  setState(() => _strokes.add(_currentStroke!));
                                }
                              },
                              onScaleUpdate: (details) {
                                if (_pointerCount >= 2 || details.scale != 1.0) {
                                  // Multi-finger: zoom and pan
                                  setState(() {
                                    _scale = (_baseScale * details.scale).clamp(1.0, 5.0);
                                    
                                    // Calculate pan with bounds
                                    final maxOffsetX = (displayW * _scale - displayW) / 2;
                                    final maxOffsetY = (displayH * _scale - displayH) / 2;
                                    
                                    final newOffset = _baseOffset + (details.focalPoint - details.localFocalPoint);
                                    _offset = Offset(
                                      newOffset.dx.clamp(-maxOffsetX, maxOffsetX),
                                      newOffset.dy.clamp(-maxOffsetY, maxOffsetY),
                                    );
                                  });
                                  _currentStroke = null; // Cancel any stroke
                                } else if (_currentStroke != null && !_isZooming) {
                                  // Single finger: continue drawing
                                  final local = details.localFocalPoint;
                                  final imgPos = _toImageCoords(local, displaySize);
                                  setState(() => _currentStroke!.points.add(imgPos));
                                }
                              },
                              onScaleEnd: (_) {
                                _currentStroke = null;
                                _isZooming = false;
                              },
                              child: Transform.translate(
                                offset: _offset,
                                child: Transform.scale(
                                  scale: _scale,
                                  child: CustomPaint(
                                    painter: _MaskEditorPainter(
                                      baseImage: _image!,
                                      strokes: _strokes,
                                      displaySize: displaySize,
                                      maskOverlay: _maskOverlay,
                                    ),
                                    size: displaySize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),

            // Tool bar
            _buildToolBar(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildToolBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // Brush size slider
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outline.withOpacity(0.2)),
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
                    inactiveColor: cs.onSurfaceVariant.withOpacity(0.2),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
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
                  onTap: _strokes.isNotEmpty
                      ? () => setState(() => _strokes.removeLast())
                      : null,
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
              // Clear button
              Expanded(
                child: _buildToolButton(
                  icon: LucideIcons.trash2,
                  label: "Clear",
                  onTap: (_strokes.isNotEmpty || _maskOverlay != null)
                      ? _clearAll
                      : null,
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
            ? (isEnabled ? cs.onErrorContainer : cs.onSurfaceVariant.withOpacity(0.5))
            : (isEnabled ? cs.onSurfaceVariant : cs.onSurfaceVariant.withOpacity(0.5));

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? cs.primary
                : cs.outline.withOpacity(0.2),
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
}

// small helper data class
class _Stroke {
  final List<Offset> points;
  final double size;
  final bool eraser;
  _Stroke({required this.points, required this.size, required this.eraser});
}

/// Painter used inside MaskEditorPage to show base image and overlay strokes scaled to the display size.
class _MaskEditorPainter extends CustomPainter {
  final ui.Image baseImage;
  final ui.Image? maskOverlay;

  final List<_Stroke> strokes;
  final Size displaySize;

  _MaskEditorPainter({
    required this.baseImage,
    required this.strokes,
    required this.displaySize,
    this.maskOverlay,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, displaySize.width, displaySize.height);
    paintImage(canvas: canvas, rect: dst, image: baseImage, fit: BoxFit.fill);

    final sx = displaySize.width / baseImage.width.toDouble();
    final sy = displaySize.height / baseImage.height.toDouble();

    // --- Build the red overlay by COMPOSITING mask + strokes together ---
    if (maskOverlay != null || strokes.isNotEmpty) {
      // 1) New layer to hold: (existing mask) +/- (strokes with erase)
      canvas.saveLayer(dst, Paint());

      // 1a) Draw the existing mask into the layer (scaled to dst)
      if (maskOverlay != null) {
        final src = Rect.fromLTWH(
          0,
          0,
          maskOverlay!.width.toDouble(),
          maskOverlay!.height.toDouble(),
        );
        // draw as pure alpha (no tint yet)
        final paintSrc = Paint()..blendMode = BlendMode.src;
        canvas.drawImageRect(maskOverlay!, src, dst, paintSrc);
      }

      // 1b) Apply strokes on the SAME layer so clear erases old mask too
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
          ..color = s.eraser
              ? const Color(0x00000000)
              : const Color(0xFFFFFFFF); // white = add to mask alpha

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

      // 2) Tint the current layer’s alpha in red so user sees the mask area
      final tint = Paint()
        ..color = const Color(0x55FF0000)
        ..blendMode = BlendMode.srcIn;
      canvas.drawRect(dst, tint);

      // 3) Flatten back
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MaskEditorPainter oldDelegate) => true;
}

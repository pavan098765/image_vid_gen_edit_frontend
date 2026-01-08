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
  });

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
  bool _fetchingResult = false;
  
  // Track image processing state to prevent race conditions
  bool _isProcessingImage = false;
  int _imageProcessingVersion = 0; // Increment to invalidate stale operations

  // for multi-image preview
  late PageController _previewPageController;

  // Controllers
  final TextEditingController _promptController = TextEditingController();

  // API config
  static const String controllerUrl = "https://genedit.mooo.com";
  final AuthService _authService = AuthService();

  // -------- Upscale (2x/4x switch) --------
  int _scaleFactor = 2;
  bool _upscaleEnabled = false;

  /// Calculate the total credit cost for this job
  int _calculateTotalCost() {
    final baseCost = widget.config.cost;
    final upscaleCost = widget.config.costUpscale;
    final offer = widget.config.offer;
    final scaleFactor = _inputs["scale_factor"] ?? 1.0;

    final int baseTotal = baseCost + ((scaleFactor is num && scaleFactor > 1) ? upscaleCost : 0);
    int totalCost = baseTotal;
    if (offer > 0) {
      totalCost = (baseTotal * (1 - offer / 100)).round();
    }
    return totalCost;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _previewPageController = PageController();

    // Default mode
    if (widget.config.modes != null && widget.config.modes!.isNotEmpty) {
      _selectedModeKey = widget.config.modes!.keys.first;
    }

    if (widget.restoreJobId != null) {
      _activeJobId = widget.restoreJobId;
      _loading = true;
    }

    debugPrint("🔧 Config for ${widget.config.model}");
    debugPrint("  title=${widget.config.title}");
    debugPrint("  elements=${widget.config.elements?.length}");
    debugPrint("  modes=${widget.config.modes?.keys}");
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promptController.dispose();
    _previewPageController.dispose();
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
          // Prompt is required - always use the controller as source of truth
          final promptText = _promptController.text.trim();
          if (promptText.isEmpty) {
            return false;
          }
          break;
          
        case "image_upload":
          // Image is required - check if it exists and is not empty
          final imageData = _inputs[inputRef];
          if (imageData == null) return false;
          if (imageData is List && imageData.isEmpty) return false;
          break;
          
        case "painter":
          // Mask is required for inpainting modes
          final maskData = _inputs[inputRef];
          if (maskData == null) return false;
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
          // Always use the controller as source of truth
          final promptText = _promptController.text.trim();
          if (promptText.isEmpty) {
            missing.add("Prompt");
          }
          break;
          
        case "image_upload":
          final imageData = _inputs[inputRef];
          if (imageData == null || (imageData is List && imageData.isEmpty)) {
            missing.add("Image");
          }
          break;
          
        case "painter":
          final maskData = _inputs[inputRef];
          if (maskData == null) {
            missing.add("Mask");
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
                        Icon(
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
        if (currentVersion != _imageProcessingVersion) return;

        final limited = files.take(maxCount).toList();
        final bytesList = await Future.wait(limited.map((f) async {
          final b = await f.readAsBytes();
          return _resizeImageSafe(b);
        }));

        // Check again after async operation
        if (currentVersion != _imageProcessingVersion || !mounted) return;

          setState(() {
            _inputs[id] = bytesList;
            _inputs["${id}_path"] = limited.first.path;
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
        if (currentVersion != _imageProcessingVersion) return;

        final bytes = await _resizeImageSafe(await file.readAsBytes());

        // Check again after async operation
        if (currentVersion != _imageProcessingVersion || !mounted) return;

          setState(() {
            _inputs[id] = [bytes];
            _inputs["${id}_path"] = file.path;
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
              _inputs["alignment"] = result["alignment"];
              _inputs["aspect_ratio"] = result["aspect_ratio"];
              _inputs["outpaint_preview"] = bytes; // keep for visual cue
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
      if (currentVersion != _imageProcessingVersion) return;

      final bytes = await _resizeImageSafe(await file.readAsBytes());

      // Check again after async operation
      if (currentVersion != _imageProcessingVersion || !mounted) return;

        setState(() {
          _inputs[id] = [bytes];
          _inputs["${id}_path"] = file.path;
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
            _inputs["alignment"] = result["alignment"];
            _inputs["aspect_ratio"] = result["aspect_ratio"];
            _inputs["outpaint_preview"] = bytes; // keep for visual cue
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

    if (width > 1536 || height > 1536) {
      final scale = 1536 / max(width, height);
      width = (width * scale).round();
      height = (height * scale).round();
    }

    int roundUp32(int x) => ((x + 31) ~/ 32) * 32;
    final paddedW = roundUp32(width);
    final paddedH = roundUp32(height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()..color = const Color(0x00000000);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, paddedW.toDouble(), paddedH.toDouble()), paint);

    final offsetX = (paddedW - width) / 2;
    final offsetY = (paddedH - height) / 2;

    final src =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    final dst =
        Rect.fromLTWH(offsetX, offsetY, width.toDouble(), height.toDouble());

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
      case "upscale_toggle":
        return _buildUpscaleToggle();
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

  // -------- Standalone Upscale Toggle (for text-to-image modes) --------
  Widget _buildUpscaleToggle() {
    final cs = Theme.of(context).colorScheme;
    return _buildCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row with toggle
          Material(
            color: _upscaleEnabled
                ? cs.primaryContainer.withOpacity(0.3)
                : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: () {
                setState(() {
                  _upscaleEnabled = !_upscaleEnabled;
                  _inputs["scale_factor"] = _upscaleEnabled ? _scaleFactor : 1.0;
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                    color: _upscaleEnabled
                        ? cs.primary.withOpacity(0.4)
                        : cs.outlineVariant.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _upscaleEnabled
                            ? cs.primary.withOpacity(0.15)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        LucideIcons.maximize2,
                        size: 20,
                        color: _upscaleEnabled ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                    Text(
                            "Upscale Output",
                            style: TextStyle(
                        color: cs.onSurface,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                      ),
                    ),
                          const SizedBox(height: 2),
                          Text(
                            _upscaleEnabled
                                ? "Enhanced ${_scaleFactor}x resolution"
                                : "Standard resolution",
                            style: TextStyle(
                              color: cs.onSurfaceVariant.withOpacity(0.7),
                              fontSize: 12,
                            ),
                ),
              ],
            ),
          ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: _upscaleEnabled
                            ? cs.primary
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _upscaleEnabled ? LucideIcons.check : LucideIcons.plus,
                        size: 18,
                        color: _upscaleEnabled ? cs.onPrimary : cs.onSurfaceVariant,
                      ),
                          ),
                  ],
                ),
              ),
            ),
          ),

          // Scale factor selector (animated)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: _upscaleEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _buildScaleFactorSelector(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  // -------- Prompt --------
  Widget _buildPrompt(String ref) {
    final cs = Theme.of(context).colorScheme;
    final label = widget.config.inputs
            .firstWhere((i) => i["id"] == ref, orElse: () => {})["label"] ??
        "Describe the edit";

    return _buildCard(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
            child: Row(
            children: [
                Icon(LucideIcons.sparkles, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                  "Prompt",
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          ),
          TextField(
            controller: _promptController,
            onChanged: (v) {
                _inputs[ref] = v;
              setState(() {}); // Trigger rebuild to update generate button validation
            },
            maxLines: 4,
            minLines: 3,
            decoration: InputDecoration(
              hintText: label,
              hintStyle: TextStyle(
                color: cs.onSurfaceVariant.withOpacity(0.6),
                fontSize: 15,
              ),
              filled: true,
              fillColor: cs.surfaceContainerHigh.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.2),
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: cs.primary.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // -------- Image Upload --------
  Widget _buildImageUpload(String ref) {
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    final hasImage = _inputs[ref] != null && 
        (_inputs[ref] is List && (_inputs[ref] as List).isNotEmpty);

    return _buildCard(
      elevated: hasImage,
      padding: const EdgeInsets.all(16),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
          // Image preview with elegant border
          _buildImagePreview(ref),
          const SizedBox(height: 16),

          // Action buttons row
              Row(
                children: [
              // Pick Image button
              Expanded(
                flex: 3,
                child: _buildActionButton(
                  icon: hasImage ? LucideIcons.imagePlus : LucideIcons.upload,
                  label: hasImage ? "Change" : "Upload Image",
                  onPressed: () => _pickImage(input),
                  isPrimary: true,
                ),
                  ),
              const SizedBox(width: 12),

              // Upscale toggle
              Expanded(
                flex: 2,
                child: _buildUpscaleChip(),
                    ),
                ],
              ),

          // Scale factor selector (animated)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            child: _upscaleEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _buildScaleFactorSelector(),
                  )
                : const SizedBox.shrink(),
          ),
            ],
          ),
    );
  }

  // Reusable action button - uses consistent button variants
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    if (isPrimary) {
      return GradientButton(
        icon: icon,
        label: label,
        onPressed: onPressed,
        variant: ButtonVariant.primary,
        size: ButtonSize.medium,
        expanded: true,
      );
    }
    
    return GradientButton(
      icon: icon,
      label: label,
      onPressed: onPressed,
      variant: ButtonVariant.secondary,
      size: ButtonSize.medium,
      expanded: true,
    );
  }

  // Upscale toggle chip
  Widget _buildUpscaleChip() {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: _upscaleEnabled
          ? cs.primaryContainer.withOpacity(0.4)
          : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          setState(() {
            _upscaleEnabled = !_upscaleEnabled;
            _inputs["scale_factor"] = _upscaleEnabled ? _scaleFactor : 1.0;
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _upscaleEnabled
                  ? cs.primary.withOpacity(0.4)
                  : cs.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.maximize2,
                size: 16,
                color: _upscaleEnabled ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  "Upscale",
                  style: TextStyle(
                    color: _upscaleEnabled ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_upscaleEnabled) ...[
                const SizedBox(width: 4),
                Icon(LucideIcons.check, size: 14, color: cs.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // Scale factor selector
  Widget _buildScaleFactorSelector() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
                            ),
      child: Row(
                              children: [
                                Expanded(
            child: _buildScaleOption(2),
                                  ),
          const SizedBox(width: 8),
                                Expanded(
            child: _buildScaleOption(4),
                                ),
                              ],
                            ),
    );
  }

  Widget _buildScaleOption(int scale) {
    final cs = Theme.of(context).colorScheme;
    final isSelected = _scaleFactor == scale;
    
    return Material(
      color: isSelected ? cs.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          setState(() {
            _scaleFactor = scale;
            _inputs["scale_factor"] = scale;
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: cs.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
              ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              "${scale}x",
              style: TextStyle(
                color: isSelected ? cs.onPrimary : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }

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

    // read alignment & aspect ratio (from OutpaintCanvasPage)
    final String alignment =
        isOutpaint ? (_inputs["alignment"] ?? "Middle") : "Middle";
    final String ratioStr =
        isOutpaint ? (_inputs["aspect_ratio"] ?? "1:1") : "1:1";

    final ratioParts = ratioStr.split(":");
    final double aspectRatio = (ratioParts.length == 2)
        ? (double.tryParse(ratioParts[0]) ?? 1) /
            (double.tryParse(ratioParts[1]) ?? 1)
        : 1.0;

    // Simple padding logic — show empty area on the expansion side
    EdgeInsets imgPadding = EdgeInsets.zero;
    if (isOutpaint) {
      switch (alignment) {
        case "Left":
          imgPadding = const EdgeInsets.only(right: 60); // expand right
          break;
        case "Right":
          imgPadding = const EdgeInsets.only(left: 60); // expand left
          break;
        case "Top":
          imgPadding = const EdgeInsets.only(bottom: 60); // expand down
          break;
        case "All Sides":
          imgPadding = const EdgeInsets.all(60);
          break;
        case "Bottom":
          imgPadding = const EdgeInsets.only(top: 60); // expand up
          break;
        default:
          imgPadding = EdgeInsets.zero;
      }
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.primary.withOpacity(0.3),
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Checker background only for outpaint
              if (isOutpaint)
                const CustomPaint(painter: _CheckerPainter())
              else
                Container(color: cs.surfaceContainerHigh),

              // Base image
              Padding(
                padding: imgPadding,
                child: Image.memory(
                  list.first,
                  fit: BoxFit.contain,
                  alignment: _convertAlignment(alignment),
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),

              // Mask overlay (other models)
              if (mask != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.6,
                    child: Image.memory(mask as Uint8List, fit: BoxFit.contain),
                  ),
                ),
              
              // Image loaded indicator
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
                      const Text(
                        "Image ready",
                        style: TextStyle(
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
          ),
        ),
      ),
    );
  }

  Alignment _convertAlignment(String a) {
    switch (a) {
      case "Left":
        return Alignment.centerLeft;
      case "Right":
        return Alignment.centerRight;
      case "Top":
        return Alignment.topCenter;
      case "Bottom":
        return Alignment.bottomCenter;
      case "All Sides":
        return Alignment.center;
      default:
        return Alignment.center;
    }
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
    final cs = Theme.of(context).colorScheme;

    // Find the image input for mask base
    Map<String, dynamic>? baseImageInput;
    for (final i in widget.config.inputs) {
      if (i["type"] == "image" && i["id"] != ref) {
        baseImageInput = i;
        break;
      }
    }

    final raw = baseImageInput != null ? _inputs[baseImageInput["id"]] : null;

    Uint8List? baseBytes;
    if (raw is List && raw.isNotEmpty) {
      baseBytes = raw.first as Uint8List;
    } else if (raw is Uint8List) {
      baseBytes = raw;
    }

    final hasMask = _inputs["mask_image"] != null;

    // Hide button entirely until image is selected
    if (baseBytes == null && !hasMask) {
      return const SizedBox.shrink();
    }

    return _buildCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasMask
                      ? Colors.green.withOpacity(0.12)
                      : cs.tertiary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasMask ? LucideIcons.checkCircle : LucideIcons.paintbrush,
                size: 18,
                  color: hasMask ? Colors.green : cs.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              Text(
                      "Mask Region",
                      style: TextStyle(
                      color: cs.onSurface,
                        fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
              ),
                    const SizedBox(height: 2),
                    Text(
                      hasMask
                          ? "Mask created - tap to edit"
                          : "Draw over areas to modify",
                      style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.7),
                        fontSize: 12,
                    ),
              ),
            ],
          ),
              ),
              Material(
                color: hasMask
                    ? cs.surfaceContainerHigh
                    : cs.tertiary,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () async {
              final base = baseBytes ?? (_inputs["init_image"]?[0] as Uint8List?);
              if (base != null) {
                final mask = await _openMaskEditor(base);
                if (mask != null) {
                  setState(() {
                    _inputs["mask_image"] = mask;
                  });
                }
              }
            },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          hasMask ? LucideIcons.edit3 : LucideIcons.paintbrush,
                          size: 18,
                          color: hasMask ? cs.onSurfaceVariant : Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          hasMask ? "Edit" : "Draw Mask",
                          style: TextStyle(
                            color: hasMask ? cs.onSurfaceVariant : Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Show mask preview if available
          if (hasMask) ...[
            const SizedBox(height: 12),
            Container(
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.withOpacity(0.3),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (baseBytes != null)
                      Image.memory(
                        baseBytes,
                        fit: BoxFit.cover,
                      ),
                    Container(
                      color: Colors.black.withOpacity(0.3),
                    ),
                    ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Colors.red,
                        BlendMode.srcATop,
                      ),
                      child: Opacity(
                        opacity: 0.5,
                        child: Image.memory(
                          _inputs["mask_image"] as Uint8List,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              LucideIcons.check,
                              size: 12,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Mask applied",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
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
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicInputScreen() {
    final cs = Theme.of(context).colorScheme;
    // Get safe area padding for devices with home bar/navigation buttons
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    
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
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          // Add extra padding for devices with gesture navigation/home bar
          bottom: 20 + bottomSafeArea,
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            // Mode selector (if applicable)
            if (widget.config.modes != null && widget.config.modes!.isNotEmpty) ...[
            _buildModeSelector(),
          const SizedBox(height: 4),
            ],
            
            // Dynamic elements with smooth spacing
            ..._currentElements.map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _buildElement(e),
              );
            }),
          ],
        ),
      ),
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
  // 🛰️ JOB SUBMISSION + POLLING
  // ----------------------------------------------------

  Future<void> _runJob() async {
    final cs = Theme.of(context).colorScheme;

    // --- Check if user is signed in ---
    if (!AuthService().isSignedIn) {
      final signedIn = await requireSignIn(context, feature: 'AI Tools');
      if (!signedIn) return;
    }

    // --- Check credits ---
    final totalCost = _calculateTotalCost();
    final currentCredits = userCreditsNotifier.value;
    if (!UserService().hasEnoughCredits(totalCost)) {
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
    Timer(const Duration(seconds: 45), () {
      dialogMessage.value =
          "Still working... It's taking a bit longer than usual.\nPlease stay on this screen.";
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
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
      ),
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

        // Encode Uint8List images → base64
        for (final key in encoded.keys.toList()) {
          final val = encoded[key];
          if (val is Uint8List) {
            encoded[key] = base64Encode(val);
          } else if (val is List) {
            if (val.isEmpty) {
              encoded.remove(key);
              continue;
            }
            if (val.first is Uint8List) {
              encoded[key] = val.length == 1
                  ? base64Encode(val.first as Uint8List)
                  : val.map((e) => base64Encode(e as Uint8List)).toList();
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

        // Resolve {{template}} placeholders
        widget.config.params?.forEach((key, value) {
          dynamic val = value;
          if (val is String) {
            final reg = RegExp(r"\{\{([\w\-]+)\}\}");
            for (final m in reg.allMatches(val)) {
              final ref = m.group(1)!;
              final fetched = getInputValue(ref);
              if (fetched != null) {
                val = fetched;
                consumedInputs.add(ref);
              }
            }
          }
          resolvedParams[key] = val;
        });

        // --- Root params ---
        final Map<String, dynamic> rootParams = {};
        widget.config.rootParams?.forEach((key, value) {
          dynamic val = value;
          if (val is String && val.startsWith("{{") && val.endsWith("}}")) {
            final refId = val.substring(2, val.length - 2);
            final fetched = getInputValue(refId);
            if (fetched != null) {
              val = fetched;
              consumedInputs.add(refId);
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

        // --- Build payload ---
        final payload = <String, dynamic>{
          "model": widget.config.model,
          "params": resolvedParams,
          "fcm_token": fcmToken,
          ...rootParams,
        };

        final payloadJson = jsonEncode(payload);

        // --- Firebase Auth ---
        final firebaseToken = await _authService.getIdToken();
        if (firebaseToken == null) {
          throw Exception("Not authenticated. Please sign in first.");
        }

        final headers = {
          "Content-Type": "application/json",
          "Authorization": "Bearer $firebaseToken",
        };

        debugPrint("🚀 Submitting job (attempt $attempt/$maxRetries)");
        final resp = await http
            .post(Uri.parse('$controllerUrl/submit'),
                headers: headers, body: payloadJson)
            .timeout(const Duration(seconds: 60));

        if (mounted) Navigator.pop(context);

        if (resp.statusCode != 200) {
          throw Exception("Server error ${resp.statusCode}: ${resp.body}");
        }

        final data = jsonDecode(resp.body);
        final jobId = data["job_id"];
        final downloadUrl = data["download_url"] ?? data["downloadUrl"];
        if (jobId == null) throw Exception("No job_id returned from submit");

        // --- Save job metadata ---
        String title = await generateFriendlyJobName();
        String? inputImageLocalPath;

        try {
          final imageInput = widget.config.inputs
              .firstWhere((i) => i["type"] == "image", orElse: () => {});
          if (imageInput.isNotEmpty) {
            final id = imageInput["id"];
            final dat = _inputs[id];
            if (dat != null &&
                dat is List &&
                dat.isNotEmpty &&
                dat.first is Uint8List) {
              final tmpDir = await FileService.getTempDir();
              final thumbFile = File(
                  '${tmpDir.path}/thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
              await thumbFile.writeAsBytes(dat.first as Uint8List, flush: true);
              inputImageLocalPath = thumbFile.path;
            } else {
              final existingPath = _inputs["${id}_path"];
              if (existingPath != null && File(existingPath).existsSync()) {
                inputImageLocalPath = existingPath;
              }
            }
          }
        } catch (e) {
          debugPrint("⚠️ Could not save stable input preview: $e");
        }

        final newJob = JobModel(
          jobId: jobId,
          title: title,
          model: widget.config.model,
          outputType: widget.config.outputType,
          downloadUrl: downloadUrl,
          status: 'processing',
          inputImagePath: inputImageLocalPath,
        );

        jobListNotifier.value = [newJob, ...jobListNotifier.value];
        await saveJobsToPrefs();
        await addOrUpdateJob(newJob);
        await saveJobsToPrefs();

        final jobContext = {
          "title": widget.config.title,
          "model": widget.config.model,
          "inputs": widget.config.inputs,
          "params": widget.config.params,
          "outputType": widget.config.outputType,
        };
        await prefs.setString("notify_job_$jobId", jsonEncode(jobContext));
        await loadJobsFromPrefs();

        // Credits are deducted server-side during job processing
        // Refresh balance to reflect the deduction
        await UserService().refreshCredits();

        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ResultManagerPage()),
          );
        }

        debugPrint("✅ Job submitted successfully (attempt $attempt): $jobId");
        return;
      } catch (e) {
        debugPrint("❌ Job submission attempt $attempt failed: $e");
        if (attempt >= maxRetries) {
          if (mounted) {
            Navigator.pop(context);
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
  int? _lastImageHash;
  bool _eraser = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  int _hashBytes(Uint8List bytes) {
    int hash = 0;
    for (final b in bytes) {
      hash = (hash * 31 + b) & 0xFFFFFFFF;
    }
    return hash;
  }

  Future<void> _loadImage() async {
    try {
      final currentHash = _hashBytes(widget.baseImageBytes);
      final isNewImage =
          _lastImageHash == null || currentHash != _lastImageHash;
      _lastImageHash = currentHash;

      // Dispose old images to avoid GPU cache artifacts
      _image?.dispose();
      _maskOverlay?.dispose();

      // Always clear strokes for (re)open
      _strokes.clear();
      _currentStroke = null;
      _eraser = false;

      // If it's a NEW image, force-start fresh (ignore any existingMask)
      if (isNewImage) {
        _maskOverlay = null;
      } else {
        // Same image: load existingMask if provided
        _maskOverlay = null;
        if (widget.existingMask != null) {
          final maskCodec =
              await ui.instantiateImageCodec(widget.existingMask!);
          final maskFrame = await maskCodec.getNextFrame();
          _maskOverlay = maskFrame.image;
        }
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

  // Convert local widget pos to image pixel coords
  Offset _toImageCoords(Offset localPos, Size displaySize) {
    final xInImageSpace = (localPos.dx / displaySize.width) * _image!.width;
    final yInImageSpace = (localPos.dy / displaySize.height) * _image!.height;
    return Offset(
      xInImageSpace.clamp(0.0, _image!.width.toDouble()),
      yInImageSpace.clamp(0.0, _image!.height.toDouble()),
    );
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

  bool _showSlider = true;
  Timer? _hideTimer;

  void _scheduleHideSlider() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showSlider = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text("Draw Mask", style: TextStyle(color: cs.onSurface)),
          backgroundColor: cs.surface,
          iconTheme: IconThemeData(color: cs.onSurface),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_image == null) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          title: Text("Draw Mask", style: TextStyle(color: cs.onSurface)),
          backgroundColor: cs.surface,
          iconTheme: IconThemeData(color: cs.onSurface),
        ),
        body: Center(
          child: Text("Failed to load image",
              style: TextStyle(color: cs.onSurface)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text("Draw Mask", style: TextStyle(color: cs.onSurface)),
        backgroundColor: cs.surface,
        iconTheme: IconThemeData(color: cs.onSurface),
        actions: [
          IconButton(
            tooltip: "Undo",
            icon: Icon(Icons.undo, color: cs.onSurface),
            onPressed: () {
              if (_strokes.isNotEmpty) setState(() => _strokes.removeLast());
            },
          ),
          IconButton(
            tooltip: "Clear",
            icon: Icon(Icons.layers_clear, color: cs.onSurface),
            onPressed: () => setState(() => _strokes.clear()),
          ),
          IconButton(
            tooltip: "Toggle Eraser",
            icon: Icon(_eraser ? Icons.brush : Icons.auto_fix_high,
                color: cs.onSurface),
            onPressed: () => setState(() => _eraser = !_eraser),
          ),
          IconButton(
            tooltip: "Save Mask",
            icon: Icon(Icons.check, color: cs.primary),
            onPressed: () async {
              try {
                final maskBytes = await _exportMask();
                Navigator.pop(context, maskBytes);
              } catch (e) {
                debugPrint("Error exporting mask: $e");
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text("Export failed: $e")));
              }
            },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final widgetSize = Size(constraints.maxWidth,
            constraints.maxHeight - 60); // leave space for ad
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

        return GestureDetector(
          onTap: () {
            // toggle slider visibility manually on single tap
            setState(() => _showSlider = !_showSlider);
            if (_showSlider) _scheduleHideSlider();
          },
          child: Stack(
            children: [
              // --- MAIN IMAGE + MASK ---
              Positioned.fill(
                top: 0,
                bottom: 60, // reserved for ad
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: displaySize.width,
                      height: displaySize.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanStart: (details) {
                          // hide slider immediately when drawing starts
                          setState(() => _showSlider = false);

                          final local = details.localPosition;

                          final imgPos = _toImageCoords(local, displaySize);
                          _currentStroke = _Stroke(
                            points: [imgPos],
                            size: _brushSize,
                            eraser: _eraser,
                          );
                          setState(() => _strokes.add(_currentStroke!));
                        },
                        onPanUpdate: (details) {
                          final local = details.localPosition;

                          final imgPos = _toImageCoords(local, displaySize);
                          if (_currentStroke != null) {
                            setState(() => _currentStroke!.points.add(imgPos));
                          }
                        },
                        onPanEnd: (_) {
                          _currentStroke = null;
                          _scheduleHideSlider(); // hide again after inactivity
                        },
                        child: ClipRect(
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

              // --- SLIDER (auto-hide with smooth fade) ---
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                left: 12,
                right: 12,
                bottom: _showSlider ? 75 : -100, // slide out smoothly
                child: AnimatedOpacity(
                  opacity: _showSlider ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: IgnorePointer(
                    ignoring: !_showSlider,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.brush, color: cs.onSurfaceVariant),
                          Expanded(
                            child: Slider(
                              value: _brushSize,
                              min: 4,
                              max: 120,
                              onChanged: (v) => setState(() => _brushSize = v),
                              activeColor: cs.primary,
                              inactiveColor:
                                  cs.onSurfaceVariant.withOpacity(0.3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text("${_brushSize.toInt()}",
                              style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // --- OPTIONAL AD BANNER ---
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 60,
                child: Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: Text("Ad Banner",
                      style: TextStyle(color: Colors.black54)),
                ),
              ),
            ],
          ),
        );
      }),
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

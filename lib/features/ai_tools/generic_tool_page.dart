// lib/features/ai_tools/generic_tool_page.dart
// FULL THEME-AWARE REWRITE — logic unchanged, UI fully Material 3 + ColorScheme

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_vid_gen_edit_frontend/core/app_state.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:image_vid_gen_edit_frontend/features/result_manager/result_manager_page.dart';
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

  const GenericToolConfig({
    required this.title,
    required this.model,
    required this.inputs,
    this.params,
    this.rootParams,
    this.modes,
    this.elements,
    required this.outputType,
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
  Uint8List? _resultData;
  String? _activeJobId;
  bool _fetchingResult = false;

  // for multi-image preview
  late PageController _previewPageController;

  // Controllers
  final TextEditingController _promptController = TextEditingController();

  // HMAC config
  static const String controllerUrl = "https://genedit.mooo.com";
  static const String controllerApiKey = "SECRETKEY";
  static const String controllerSharedSecret = "SECRETKEY";

  // -------- Upscale (2x/4x switch) --------
  int _scaleFactor = 2;
  bool _upscaleEnabled = false;

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

  // -----------------------------------------------
  // 🧠 IMAGE PICKING & INPUT MANAGEMENT
  // -----------------------------------------------

  Future<void> _pickImageFromGallery(Map<String, dynamic> input) async {
    final id = input['id'];
    final maxCount = (input['max'] ?? 1) as int;
    final allowMulti = maxCount > 1;

    try {
      if (allowMulti) {
        final files = await picker.pickMultiImage(imageQuality: 85);
        if (files.isEmpty) return;

        final limited = files.take(maxCount).toList();
        final bytesList = await Future.wait(limited.map((f) async {
          final b = await f.readAsBytes();
          return _resizeImageSafe(b);
        }));

        if (mounted) {
          setState(() {
            _inputs[id] = bytesList;
            _inputs["${id}_path"] = limited.first.path;
          });
        }
      } else {
        final file = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
        if (file == null) return;

        final bytes = await _resizeImageSafe(await file.readAsBytes());

        if (mounted) {
          setState(() {
            _inputs[id] = [bytes];
            _inputs["${id}_path"] = file.path;
          });
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to load image: $e")));
    }
  }

  Future<void> _pickImageFromCamera(Map<String, dynamic> input) async {
    final id = input['id'];
    try {
      final file =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (file == null) return;

      final bytes = await _resizeImageSafe(await file.readAsBytes());

      if (mounted) {
        setState(() {
          _inputs[id] = [bytes];
          _inputs["${id}_path"] = file.path;
        });
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Camera capture failed: $e")));
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
        backgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8),
                  child: Text(
                    'Select Image Source',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.photo_library, color: cs.primary),
                  title: Text('Gallery', style: TextStyle(color: cs.onSurface)),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt, color: cs.primary),
                  title: Text('Camera', style: TextStyle(color: cs.onSurface)),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                const SizedBox(height: 8),
              ],
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

  // -----------------------------------------------
  // 🧱 ELEMENT BUILDERS (core dynamic UI logic)
  // -----------------------------------------------

  // ---------- Card (theme-aware glass-ish) ----------
  Widget _buildCard({required Widget child}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.surfaceContainerHighest.withOpacity(0.10),
            cs.surface.withOpacity(0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
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
      case "output_preview":
        return _buildOutputPreview();
      default:
        return const SizedBox.shrink();
    }
  }

  // -------- Standalone Upscale Toggle (for text-to-image modes) --------
  Widget _buildUpscaleToggle() {
    final cs = Theme.of(context).colorScheme;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Upscale",
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 14.5)),
                      Switch(
                        value: _upscaleEnabled,
                        onChanged: (v) => setState(() => _upscaleEnabled = v),
                        activeThumbColor: cs.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _upscaleEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text("2x"),
                          selected: _scaleFactor == 2,
                          onSelected: (_) => setState(() => _scaleFactor = 2),
                          selectedColor: cs.primary,
                          backgroundColor: cs.surfaceContainerHigh,
                          labelStyle: TextStyle(
                            color: _scaleFactor == 2
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: const Text("4x"),
                          selected: _scaleFactor == 4,
                          onSelected: (_) => setState(() => _scaleFactor = 4),
                          selectedColor: cs.primary,
                          backgroundColor: cs.surfaceContainerHigh,
                          labelStyle: TextStyle(
                            color: _scaleFactor == 4
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: TextField(
        controller: _promptController,
        onChanged: (v) => _inputs[ref] = v,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: label,
          hintStyle: TextStyle(color: cs.onSurfaceVariant),
          filled: true,
          fillColor: cs.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        style: TextStyle(color: cs.onSurface, fontSize: 16),
      ),
    );
  }

  // -------- Image Upload --------
  Widget _buildImageUpload(String ref) {
    final cs = Theme.of(context).colorScheme;
    final mode = _selectedModeKey?.toLowerCase() ?? "";
    final paramMode =
        (widget.config.params?["mode"]?.toString().toLowerCase() ?? "");
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildImagePreview(ref),
          const SizedBox(height: 16),
          Row(
            children: [
              // Pick Image
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add_photo_alternate_outlined,
                        size: 22),
                    label: const Text("Pick Image"),
                    onPressed: () => _pickImage(input),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Upscale toggle
              Expanded(
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Upscale",
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 14.5)),
                      Switch(
                        value: _upscaleEnabled,
                        onChanged: (v) => setState(() => _upscaleEnabled = v),
                        activeThumbColor: cs.primary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // factor
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _upscaleEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ChoiceChip(
                          label: const Text("2x"),
                          selected: _scaleFactor == 2,
                          onSelected: (_) => setState(() => _scaleFactor = 2),
                          selectedColor: cs.primary,
                          backgroundColor: cs.surfaceContainerHigh,
                          labelStyle: TextStyle(
                            color: _scaleFactor == 2
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: const Text("4x"),
                          selected: _scaleFactor == 4,
                          onSelected: (_) => setState(() => _scaleFactor = 4),
                          selectedColor: cs.primary,
                          backgroundColor: cs.surfaceContainerHigh,
                          labelStyle: TextStyle(
                            color: _scaleFactor == 4
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(String ref) {
    final cs = Theme.of(context).colorScheme;
    final data = _inputs[ref];
    if (data == null || (data is List && data.isEmpty)) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.image_outlined, color: cs.onSurfaceVariant, size: 60),
      );
    }

    final list =
        (data is List) ? List<Uint8List>.from(data) : [data as Uint8List];
    final mask = _inputs["mask_image"];

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        children: [
          Center(
            child: Image.memory(
              list.first,
              fit: BoxFit.contain,
              width: double.infinity,
              height: 220,
            ),
          ),
          if (mask != null)
            Positioned.fill(
              child: Opacity(
                opacity: 0.6,
                child: Image.memory(mask as Uint8List, fit: BoxFit.contain),
              ),
            ),
        ],
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
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label: ${(_inputs[ref] as num).toStringAsFixed(1)}",
              style: TextStyle(color: cs.onSurface)),
          Slider(
            value: (_inputs[ref] as num).toDouble(),
            min: (input["min"] as num?)?.toDouble() ?? 0,
            max: (input["max"] as num?)?.toDouble() ?? 100,
            divisions: 10,
            activeColor: cs.primary,
            onChanged: (v) => setState(() => _inputs[ref] = v),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: options
                .map((opt) => ChoiceChip(
                      label: Text(opt),
                      selected: _inputs[ref] == opt,
                      onSelected: (_) => setState(() => _inputs[ref] = opt),
                      selectedColor: cs.primary,
                      labelStyle: TextStyle(
                        color: _inputs[ref] == opt
                            ? cs.onPrimary
                            : cs.onSurfaceVariant,
                      ),
                      backgroundColor: cs.surfaceContainerHigh,
                    ))
                .toList(),
          )
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

    // 🧠 Hide button entirely until image is selected
    if (baseBytes == null && !hasMask) {
      return const SizedBox.shrink();
    }

    // Label dynamically changes
    final buttonLabel = hasMask ? "Edit Mask" : "Draw Mask";
    final buttonIcon = hasMask ? Icons.edit_note_rounded : Icons.brush;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: FilledButton.icon(
        icon: Icon(buttonIcon),
        label: Text(buttonLabel),
        onPressed: () async {
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
        style: FilledButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // -------- Generate Button --------
  Widget _buildGenerateButton() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: FilledButton.icon(
          icon: const Icon(Icons.flash_on),
          label: const Text("Generate ✨"),
          onPressed: _runJob,
        ),
      );

  // -------- Output Preview --------
  Widget _buildOutputPreview() {
    final cs = Theme.of(context).colorScheme;
    if (_resultData == null) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: 20),
        Text(
          "✨ Result Ready!",
          style: TextStyle(
            fontSize: 20,
            color: cs.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        if (widget.config.outputType == "image")
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_resultData!, fit: BoxFit.contain),
          ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            widget.config.model.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
            await FileService.saveFile(context, _resultData!);
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text("Save Result"),
        )
      ],
    );
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

  // ----------------------------------------------------
  // 🛰️ JOB SUBMISSION + POLLING
  // ----------------------------------------------------

  Future<void> _runJob() async {
    final cs = Theme.of(context).colorScheme;

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
          "Still working... It’s taking a bit longer than usual.\nPlease stay on this screen.";
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: cs.surface,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
              const SizedBox(height: 22),
              Text(
                "Submitting your job...",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<String>(
                valueListenable: dialogMessage,
                builder: (_, value, __) => Text(
                  value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13.5,
                    height: 1.4,
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

        // --- HMAC Auth ---
        final sigBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
            .convert(utf8.encode(payloadJson));
        final signature = "sha256=${sigBytes.toString()}";

        final headers = {
          "Content-Type": "application/json",
          "Authorization": "Bearer $controllerApiKey",
          "X-Signature": signature
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

  // ----------------------------------------------------
  // 🖼️ BUILD UI — Scaffold + Mode Selector + Dynamic Elements
  // ----------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.config.title,
          style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.onSurface),
      ),
      body: _buildDynamicInputScreen(),
    );
  }

  Widget _buildDynamicInputScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.config.modes != null && widget.config.modes!.isNotEmpty)
            _buildModeSelector(),
          const SizedBox(height: 8),
          ..._currentElements.map(_buildElement).toList(),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    final cs = Theme.of(context).colorScheme;
    final modes = widget.config.modes!;
    final modeKeys = modes.keys.toList();

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Mode",
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),

          // Compact Segmented Button Bar
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(3),
            child: Row(
              children: modeKeys.map((key) {
                final selected = _selectedModeKey == key;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedModeKey = key;
                        _resultData = null;
                        _promptController.clear();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeInOut,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.primary.withOpacity(0.95)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: cs.primary.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : [],
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Text(
                            modes[key]?["label"] ?? key,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: selected
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant.withOpacity(0.9),
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              fontSize: 12.5, // ↓ smaller for one-row fit
                              letterSpacing: -0.2,
                            ),
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

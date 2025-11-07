// lib/features/ai_tools/generic_tool_page.dart
// FULL THEME-AWARE REWRITE — logic unchanged, UI fully Material 3 + ColorScheme

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_vid_gen_edit_frontend/core/app_state.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:image_vid_gen_edit_frontend/core/services/notification_service.dart';
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
  final bool _submittingJob = false;
  String? _selectedModeKey;
  Uint8List? _resultData;
  String? _activeJobId;
  bool _fetchingResult = false;

  // for multi-image preview
  final int _previewPageIndex = 0;
  late PageController _previewPageController;

  // Controllers
  final TextEditingController _promptController = TextEditingController();

  // HMAC config
  static const String controllerUrl = "https://genedit.mooo.com";
  static const String controllerApiKey = "SECRETKEY";
  static const String controllerSharedSecret = "SECRETKEY";

  bool _restoringInProgress = false;

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

    _restoreJobIfExists();
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

  Future<void> _waitForNetworkThenRetry(String payloadJson) async {
    if (_restoringInProgress) return;
    _restoringInProgress = true;
    final connectivity = Connectivity();
    final current = await connectivity.checkConnectivity();

    if (current != ConnectivityResult.none) {
      debugPrint("🌐 Network available, retrying submit immediately...");
      await _retrySubmit(payloadJson);
      _restoringInProgress = false;
      return;
    }

    // else wait until connectivity resumes
    debugPrint("📴 Offline — waiting for network to restore submission...");
    final sub = connectivity.onConnectivityChanged.listen(null);
    sub.onData((result) async {
      if (result != ConnectivityResult.none) {
        await sub.cancel();
        debugPrint("🌐 Network restored — retrying job submit...");
        await _retrySubmit(payloadJson);
      }
    });
  }

  Future<void> _retrySubmit(String payloadJson) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sigBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
          .convert(utf8.encode(payloadJson));
      final signature = "sha256=${sigBytes.toString()}";

      final headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer $controllerApiKey",
        "X-Signature": signature,
      };

      final resp = await http
          .post(Uri.parse('$controllerUrl/submit'),
              headers: headers, body: payloadJson)
          .timeout(const Duration(seconds: 20));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final jobId = data["job_id"];
        final downloadUrl = data["download_url"];

        await prefs.setString("active_job_id", jobId ?? "");
        await prefs.remove("job_submitting");
        await prefs.remove("pending_payload");

        if (mounted) {
          setState(() {
            _activeJobId = jobId;
            _loading = true;
          });
        }

        if (downloadUrl != null) {
          await prefs.setString("pending_download_url", downloadUrl);
        }

        debugPrint("✅ Retried submit successfully for job $jobId");
      } else {
        throw Exception("Server responded ${resp.statusCode}");
      }
    } catch (e) {
      debugPrint("⚠️ Retry submit failed: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Retry failed: $e")),
      );
    }
  }

  // 🧠 Restore previous job or submission state
  Future<void> _restoreJobIfExists() async {
    final prefs = await SharedPreferences.getInstance();

    final savedJobId = prefs.getString("active_job_id");
    final pendingUrl = prefs.getString("pending_download_url");
    final cached = prefs.getString("cached_result_bytes");

    final wasSubmitting = prefs.getBool("job_submitting") ?? false;
    final pendingPayload = prefs.getString("pending_payload");

    final lastStatus = prefs.getString("job_last_status");

    debugPrint(
      "🔄 Restoring job state: "
      "jobId=$savedJobId, wasSubmitting=$wasSubmitting, "
      "hasCached=${cached != null}, hasPendingUrl=${pendingUrl != null}, lastStatus=$lastStatus",
    );

    // 1) If cached result exists → show instantly
    if (cached != null && cached.isNotEmpty) {
      try {
        final bytes = base64Decode(cached);
        setState(() {
          _resultData = bytes;
          _loading = false;
        });

        await prefs.remove("cached_result_bytes");
        await prefs.remove("pending_download_url");
        await prefs.remove("active_job_id");
        await prefs.remove("notify_requested");
        await prefs.remove("job_submitting");
        await prefs.remove("pending_payload");
        await prefs.remove("job_last_status");
        return;
      } catch (e) {
        debugPrint("⚠️ Failed to decode cached result: $e");
      }
    }

    // 2) If pending download URL exists → fetch result
    if (pendingUrl != null && pendingUrl.isNotEmpty) {
      try {
        await _fetchResult({
          "download_url": pendingUrl,
          "status": "completed",
        });

        await prefs.remove("pending_download_url");
        await prefs.remove("cached_result_bytes");
        await prefs.remove("active_job_id");
        await prefs.remove("notify_requested");
        await prefs.remove("job_submitting");
        await prefs.remove("pending_payload");
        await prefs.remove("job_last_status");
        return;
      } catch (e) {
        debugPrint("⚠️ Failed to download pending result: $e");
      }
    }

    // 3) If we were submitting but no job_id → retry submit
    if (wasSubmitting && pendingPayload != null && pendingPayload.isNotEmpty) {
      if (lastStatus == "completed" || lastStatus == "failed") {
        await prefs.remove("job_submitting");
        await prefs.remove("pending_payload");
        await prefs.remove("job_last_status");
        return;
      }
      setState(() => _loading = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⏳ Restoring interrupted submission...")),
      );
      await _waitForNetworkThenRetry(pendingPayload);
      return;
    }

    debugPrint("ℹ️ No active, cached, or pending job to restore");
  }

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

  Widget _buildElement(Map<String, dynamic> e) {
    final type = e["type"];
    final ref = e["input_ref"];

    switch (type) {
      case "prompt":
        return _buildPrompt(ref);
      case "image_upload":
        return _buildImageUpload(ref);
      // case "upscale":
      //   return _buildUpscale(ref);
      case "slider":
        return _buildSlider(ref);
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

  // -------- Upscale (2x/4x switch) --------
  int _scaleFactor = 2;
  bool _upscaleEnabled = false;

  Widget _buildUpscale(String ref) {
    final cs = Theme.of(context).colorScheme;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: Text(
              "Upscale Output",
              style: TextStyle(color: cs.onSurface),
            ),
            value: _upscaleEnabled,
            onChanged: (v) => setState(() => _upscaleEnabled = v),
            activeThumbColor: cs.primary,
            contentPadding: EdgeInsets.zero,
          ),
          if (_upscaleEnabled)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text("2x"),
                  selected: _scaleFactor == 2,
                  onSelected: (_) => setState(() => _scaleFactor = 2),
                  selectedColor: cs.primary,
                  labelStyle: TextStyle(
                    color:
                        _scaleFactor == 2 ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text("4x"),
                  selected: _scaleFactor == 4,
                  onSelected: (_) => setState(() => _scaleFactor = 4),
                  selectedColor: cs.primary,
                  labelStyle: TextStyle(
                    color:
                        _scaleFactor == 4 ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ],
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
                opacity: 0.7,
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

  // -------- Painter (Mask Editor) --------
  Future<Uint8List?> _openMaskEditor(Uint8List base) async {
    try {
      return await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(
          builder: (_) => MaskEditorPage(baseImageBytes: base),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      debugPrint("Mask editor failed: $e");
      return null;
    }
  }

  Widget _buildPainter(String ref) {
    final cs = Theme.of(context).colorScheme;

    Map<String, dynamic>? baseImageInput;
    for (final i in widget.config.inputs) {
      if (i["type"] == "image") {
        baseImageInput = i;
        break;
      }
    }

    final raw = baseImageInput != null ? _inputs[baseImageInput["id"]] : null;

    Uint8List? baseBytes;
    if (raw == null) {
      baseBytes = null;
    } else if (raw is List && raw.isNotEmpty) {
      baseBytes = raw.first as Uint8List;
    } else if (raw is Uint8List) {
      baseBytes = raw;
    }

    return FilledButton.icon(
      icon: const Icon(Icons.edit),
      label: const Text("Draw Mask"),
      onPressed: baseBytes == null
          ? null
          : () async {
              final mask = await _openMaskEditor(baseBytes!);
              if (mask != null) {
                setState(() {
                  _inputs["mask_image"] = mask;
                });
              }
            },
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Future<void> _fetchResult(Map<String, dynamic> data) async {
    if (_fetchingResult) return;
    _fetchingResult = true;

    try {
      String? downloadUrl = data["download_url"];
      final prefs = await SharedPreferences.getInstance();

      downloadUrl ??= prefs.getString("pending_download_url");
      if (downloadUrl == null || downloadUrl.isEmpty) {
        throw Exception("Missing download URL");
      }

      debugPrint("⬇️ Downloading result from: $downloadUrl");
      final resp = await http.get(Uri.parse(downloadUrl));
      if (resp.statusCode != 200) {
        throw Exception("Download failed (${resp.statusCode})");
      }

      final bytes = resp.bodyBytes;

      if (mounted) {
        setState(() {
          _resultData = bytes;
          _loading = false;
        });
      }

      final jobId = _activeJobId;

      bool readyToNotify = false;
      if (jobId != null) {
        readyToNotify = prefs.getBool("notify_requested_$jobId") ?? false;
      }

      if (readyToNotify) {
        await NotificationService.showNotification(
          title: "Processing Complete",
          body: "Tap to view your result.",
          payload: jobId ?? "",
        );
        await prefs.remove("notify_requested_$jobId");
      }

      if (jobId != null) {
        await prefs.remove("notify_job_$jobId");
        await prefs.remove("notify_requested_$jobId");

        final activeJobs = prefs.getStringList("notify_jobs_list") ?? [];
        if (activeJobs.contains(jobId)) {
          activeJobs.remove(jobId);
          await prefs.setStringList("notify_jobs_list", activeJobs);
        }
      }

      await prefs.remove("active_job_id");
      await prefs.remove("cached_result_bytes");
      await prefs.remove("pending_download_url");
      await prefs.remove("selected_images");
      await prefs.remove("job_submitting");
      await prefs.remove("pending_payload");
      await prefs.remove("ready_to_notify");

      debugPrint("✅ Result image fetched & displayed successfully");
    } catch (e) {
      _onJobFailed(e.toString());
    } finally {
      _fetchingResult = false;
    }
  }

  void _onJobFailed(String error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Job failed: $error")));
    setState(() {
      _loading = false;
      _resultData = null;
    });
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
      body: _resultData != null
          ? _buildResultScreen()
          : _buildDynamicInputScreen(),
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
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Mode", style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: modes.entries
                .map(
                  (entry) => ChoiceChip(
                    label: Text(entry.value["label"] ?? entry.key),
                    selected: _selectedModeKey == entry.key,
                    onSelected: (_) {
                      setState(() {
                        _selectedModeKey = entry.key;
                        _resultData = null;
                        _promptController.clear();
                      });
                    },
                    selectedColor: cs.primary,
                    backgroundColor: cs.surfaceContainerHigh,
                    labelStyle: TextStyle(
                      color: _selectedModeKey == entry.key
                          ? cs.onPrimary
                          : cs.onSurfaceVariant,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // 🌈 RESULT SCREEN (theme-aware)
  // ----------------------------------------------------
  Widget _buildResultScreen() {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "✨ Result Ready!",
              style: TextStyle(
                fontSize: 22,
                color: cs.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.config.outputType == "image" && _resultData != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  _resultData!,
                  height: 360,
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                final _ = widget.config.model
                    .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
                await FileService.saveFile(context, _resultData!);
              },
              icon: const Icon(Icons.download_rounded),
              label: const Text("Save Result"),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                Future.microtask(() {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) => GenericToolPage(config: widget.config),
                    ),
                  );
                });
              },
              icon: Icon(Icons.refresh, color: cs.primary),
              label: Text("Try Again", style: TextStyle(color: cs.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------ MASK EDITOR ------------------
class MaskEditorPage extends StatefulWidget {
  final Uint8List baseImageBytes;
  const MaskEditorPage({super.key, required this.baseImageBytes});

  @override
  State<MaskEditorPage> createState() => _MaskEditorPageState();
}

class _MaskEditorPageState extends State<MaskEditorPage> {
  ui.Image? _image;
  bool _loading = true;

  // strokes: list of drawn strokes (in image pixel coordinates)
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;

  double _brushSize = 30.0;
  bool _eraser = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.baseImageBytes);
      final frame = await codec.getNextFrame();
      setState(() {
        _image = frame.image;
        _loading = false;
      });
    } catch (e) {
      debugPrint("Failed to decode image in mask editor: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // Convert local widget pos to image pixel coords
  Offset _toImageCoords(Offset localPos, Size widgetSize, Size displaySize) {
    final dx = (widgetSize.width - displaySize.width) / 2;
    final dy = (widgetSize.height - displaySize.height) / 2;
    final xInImageSpace =
        ((localPos.dx - dx) / displaySize.width) * _image!.width;
    final yInImageSpace =
        ((localPos.dy - dy) / displaySize.height) * _image!.height;
    final x = xInImageSpace.clamp(0.0, _image!.width.toDouble());
    final y = yInImageSpace.clamp(0.0, _image!.height.toDouble());
    return Offset(x, y);
  }

  Future<Uint8List> _exportMask() async {
    final img = _image!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final rect =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.saveLayer(rect, Paint());

    // no background -> transparent

    for (final s in _strokes) {
      if (s.points.isEmpty) continue;

      final pathPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.size
        ..isAntiAlias = true;

      final capPaint = Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      if (s.eraser) {
        pathPaint.blendMode = BlendMode.clear;
        capPaint.blendMode = BlendMode.clear;
      } else {
        pathPaint.color = Colors.white.withOpacity(0.7);
        capPaint.color = Colors.white.withOpacity(0.7);
        pathPaint.blendMode = BlendMode.srcOver;
        capPaint.blendMode = BlendMode.srcOver;
      }

      final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
      for (int i = 1; i < s.points.length; i++) {
        path.lineTo(s.points[i].dx, s.points[i].dy);
      }

      canvas.drawPath(path, pathPaint);

      for (final p in s.points) {
        canvas.drawCircle(Offset(p.dx, p.dy), s.size / 2, capPaint);
      }
    }

    canvas.restore();

    final picture = recorder.endRecording();
    final maskImage = await picture.toImage(img.width, img.height);
    final byteData = await maskImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
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
        final widgetSize = Size(constraints.maxWidth, constraints.maxHeight);
        final imgW = _image!.width.toDouble();
        final imgH = _image!.height.toDouble();
        final widgetAspect = widgetSize.width / widgetSize.height;
        final imgAspect = imgW / imgH;
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
          onPanStart: (details) {
            final local = details.localPosition;
            final imgPos = _toImageCoords(local, widgetSize, displaySize);
            _currentStroke =
                _Stroke(points: [imgPos], size: _brushSize, eraser: _eraser);
            setState(() => _strokes.add(_currentStroke!));
          },
          onPanUpdate: (details) {
            final local = details.localPosition;
            final imgPos = _toImageCoords(local, widgetSize, displaySize);
            if (_currentStroke != null) {
              setState(() => _currentStroke!.points.add(imgPos));
            }
          },
          onPanEnd: (_) {
            _currentStroke = null;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: cs.surface,
                  child: Center(
                    child: SizedBox(
                      width: displaySize.width,
                      height: displaySize.height,
                      child: CustomPaint(
                        painter: _MaskEditorPainter(
                          baseImage: _image!,
                          strokes: _strokes,
                          displaySize: displaySize,
                        ),
                        size: displaySize,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 18,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
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
                  ],
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
  final List<_Stroke> strokes;
  final Size displaySize;

  _MaskEditorPainter({
    required this.baseImage,
    required this.strokes,
    required this.displaySize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dst = Rect.fromLTWH(0, 0, displaySize.width, displaySize.height);
    paintImage(canvas: canvas, rect: dst, image: baseImage, fit: BoxFit.fill);

    final sx = displaySize.width / baseImage.width.toDouble();
    final sy = displaySize.height / baseImage.height.toDouble();

    for (final s in strokes) {
      if (s.points.isEmpty) continue;

      final strokeWidth = s.size * ((sx + sy) / 2);

      final paint = Paint()
        ..color = s.eraser
            ? Colors.black.withOpacity(0.35)
            : Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true;

      final path = Path();
      final first = s.points.first;
      path.moveTo(first.dx * sx, first.dy * sy);
      for (int i = 1; i < s.points.length; i++) {
        final p = s.points[i];
        path.lineTo(p.dx * sx, p.dy * sy);
      }
      canvas.drawPath(path, paint);

      final capPaint = Paint()
        ..color = s.eraser
            ? Colors.black.withOpacity(0.35)
            : Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      for (final p in s.points) {
        canvas.drawCircle(
          Offset(p.dx * sx, p.dy * sy),
          strokeWidth / 2,
          capPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MaskEditorPainter oldDelegate) => true;
}

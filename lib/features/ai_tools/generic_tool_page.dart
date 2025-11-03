// generic_tool_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_vid_gen_edit_frontend/core/app_state.dart';
import 'package:image_vid_gen_edit_frontend/core/services/notification_service.dart';
// import 'package:image_vid_gen_edit_frontend/core/services/polling_service.dart';
import 'package:image_vid_gen_edit_frontend/features/result_manager/result_manager_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:crypto/crypto.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

/// --------------------------------------
///  GENERIC TOOL PAGE (Dynamic Version)
///  - Fully driven by tool_config.json
///  - Dynamically renders all UI elements & modes
///  - Keeps all animations, HMAC submit, job polling, etc.
///
/// TODO: Bring sparkle effects from flux_editor to here - done
/// TODO: Add blurred videos in background during loading/processing?
/// TODO: Add cancel job functionality?
/// TODO: After 2 minutes, ask user if they want to continue waiting or notified later once done via notification - done
/// TODO: Implement user feedback for long-running tasks
/// TODO: Add retry button on job failure
///
/// --------------------------------------

class GenericToolConfig {
  final String title;
  final String model;
  final List<dynamic> inputs;
  final Map<String, dynamic>? params;
  final Map<String, dynamic>? modes; // dynamic modes
  final List<dynamic>? elements; // fallback if no modes
  final String outputType;

  const GenericToolConfig({
    required this.title,
    required this.model,
    required this.inputs,
    this.params,
    this.modes,
    this.elements,
    required this.outputType,
  });
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
  int _previewPageIndex = 0;
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
    if (state == AppLifecycleState.paused) {
    } else if (state == AppLifecycleState.resumed) {
      // ✅ Re-attach polling if we were mid-loading
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

  // 🧠 Restores previous job or submission state safely and intelligently
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
      "jobId=$savedJobId, "
      "wasSubmitting=$wasSubmitting, "
      "hasCached=${cached != null}, "
      "hasPendingUrl=${pendingUrl != null}, "
      "lastStatus=$lastStatus",
    );

    // ✅ 1️⃣ If cached result exists → show instantly
    if (cached != null && cached.isNotEmpty) {
      try {
        final bytes = base64Decode(cached);
        setState(() {
          _resultData = bytes;
          _loading = false;
        });

        debugPrint("✅ Loaded cached result instantly from PollingService");

        // Clean all flags (job is done)
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
        // continue to next fallback
      }
    }

    // ✅ 2️⃣ If pending download URL exists → fetch result
    if (pendingUrl != null && pendingUrl.isNotEmpty) {
      try {
        debugPrint("🌐 Found pending URL — downloading result...");
        await _fetchResult({
          "download_url": pendingUrl,
          "status": "completed",
        });

        // Clean flags after successful fetch
        await prefs.remove("pending_download_url");
        await prefs.remove("cached_result_bytes");
        await prefs.remove("active_job_id");
        await prefs.remove("notify_requested");
        await prefs.remove("job_submitting");
        await prefs.remove("pending_payload");
        await prefs.remove("job_last_status");
        debugPrint("✅ Restored from pending URL and cleaned up prefs");
        return;
      } catch (e) {
        debugPrint("⚠️ Failed to download pending result: $e");
        // continue fallback
      }
    }

    // ✅ 4️⃣ Only if job_id is missing but we were submitting → retry submission
    if (wasSubmitting && pendingPayload != null && pendingPayload.isNotEmpty) {
      // Avoid retry if last status shows completion/failure
      if (lastStatus == "completed" || lastStatus == "failed") {
        debugPrint(
            "🛑 Skipping stale submission restore (job already finished).");
        await prefs.remove("job_submitting");
        await prefs.remove("pending_payload");
        await prefs.remove("job_last_status");
        return;
      }

      debugPrint(
          "📦 No active job found — restoring interrupted submission...");
      setState(() => _loading = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⏳ Restoring interrupted submission...")),
      );

      await _waitForNetworkThenRetry(pendingPayload);
      return;
    }

    // ✅ 5️⃣ Nothing to restore
    debugPrint("ℹ️ No active, cached, or pending job to restore");
  }

  Widget _buildCard({required Widget child}) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

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

        if (mounted) setState(() => _inputs[id] = bytesList);
      } else {
        final file = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
        if (file == null) return;

        final bytes = await _resizeImageSafe(await file.readAsBytes());

        // 🔧 Normalize: always store as a list
        if (mounted) setState(() => _inputs[id] = [bytes]);
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

      // 🔧 Normalize: always store as a list
      if (mounted) setState(() => _inputs[id] = [bytes]);
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

    // ✅ 1. Scale down if larger than 1536 px in either dimension
    if (width > 1536 || height > 1536) {
      final scale = 1536 / max(width, height);
      width = (width * scale).round();
      height = (height * scale).round();
    }

    // ✅ 2. Compute padding to reach next multiple of 32 (no cropping!)
    int roundUp32(int x) => ((x + 31) ~/ 32) * 32;
    final paddedW = roundUp32(width);
    final paddedH = roundUp32(height);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // ✅ 3. Fill transparent background (or black if needed)
    final paint = Paint()..color = const Color(0x00000000);
    canvas.drawRect(
        Rect.fromLTWH(0, 0, paddedW.toDouble(), paddedH.toDouble()), paint);

    // ✅ 4. Center original image into padded canvas (no cropping)
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
      case "image_preview":
        return _buildImagePreview(ref);
      case "upscale":
        return _buildUpscale(ref);
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

  // -------- Prompt --------
  Widget _buildPrompt(String ref) {
    final label = widget.config.inputs
            .firstWhere((i) => i["id"] == ref, orElse: () => {})["label"] ??
        "Prompt";
    return _buildCard(
      child: TextField(
        controller: _promptController,
        onChanged: (v) => _inputs[ref] = v,
        style: const TextStyle(color: Colors.white),
        maxLines: 3,
        decoration: InputDecoration(
          hintText: label,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white.withOpacity(0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  // -------- Image Upload --------
  Widget _buildImageUpload(String ref) {
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    return _buildCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.photo),
                  label: const Text("Gallery"),
                  onPressed: () => _pickImageFromGallery(input),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text("Camera"),
                onPressed: () => _pickImageFromCamera(input),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // -------- Image Preview --------
  Widget _buildImagePreview(String ref) {
    final data = _inputs[ref];
    if (data == null || (data is List && data.isEmpty)) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.image, color: Colors.white30, size: 60),
        ),
      );
    }

    // ensure it's a List<Uint8List>
    final list =
        (data is List) ? List<Uint8List>.from(data) : [data as Uint8List];

    final mask = _inputs["mask"]; // mask stays Uint8List

    if (list.length == 1) {
      // single image (same appearance as before)
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
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
                child: Center(
                  child: Opacity(
                    opacity: 0.85,
                    child: Image.memory(
                      mask as Uint8List,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: 220,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Multi-image: PageView with small dot indicator
    return Column(
      children: [
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: PageView.builder(
              controller: _previewPageController,
              itemCount: list.length,
              onPageChanged: (idx) => setState(() => _previewPageIndex = idx),
              itemBuilder: (context, idx) {
                final imgBytes = list[idx];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Image.memory(
                        imgBytes,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: 220,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(list.length, (i) {
            final active = i == _previewPageIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 10 : 8,
              height: active ? 10 : 8,
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        ),
      ],
    );
  }

  // -------- Upscale (2x/4x switch) --------
  int _scaleFactor = 2;
  bool _upscaleEnabled = false;
  Widget _buildUpscale(String ref) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text("Upscale Output",
                style: TextStyle(color: Colors.white)),
            value: _upscaleEnabled,
            onChanged: (v) => setState(() => _upscaleEnabled = v),
            activeThumbColor: Colors.deepPurpleAccent,
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
                  selectedColor: Colors.deepPurpleAccent,
                  labelStyle: TextStyle(
                      color: _scaleFactor == 2 ? Colors.white : Colors.white70),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text("4x"),
                  selected: _scaleFactor == 4,
                  onSelected: (_) => setState(() => _scaleFactor = 4),
                  selectedColor: Colors.deepPurpleAccent,
                  labelStyle: TextStyle(
                      color: _scaleFactor == 4 ? Colors.white : Colors.white70),
                ),
              ],
            )
        ],
      ),
    );
  }

  // -------- Slider --------
  Widget _buildSlider(String ref) {
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    final label = input["label"] ?? ref;
    _inputs[ref] ??= input["default"] ?? input["min"] ?? 1.0;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label: ${_inputs[ref].toStringAsFixed(1)}",
              style: const TextStyle(color: Colors.white)),
          Slider(
            value: (_inputs[ref] as num).toDouble(),
            min: (input["min"] as num?)?.toDouble() ?? 0,
            max: (input["max"] as num?)?.toDouble() ?? 100,
            divisions: 10,
            activeColor: Colors.deepPurpleAccent,
            onChanged: (v) => setState(() => _inputs[ref] = v),
          ),
        ],
      ),
    );
  }

  // -------- Dropdown (rendered as ChoiceChips) --------
  Widget _buildDropdown(String ref) {
    final input = widget.config.inputs
        .firstWhere((i) => i["id"] == ref, orElse: () => {});
    final label = input["label"] ?? ref;
    final options = List<String>.from(input["options"] ?? []);
    _inputs[ref] ??= options.isNotEmpty ? options.first : null;

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: options
                .map((opt) => ChoiceChip(
                      label: Text(opt),
                      selected: _inputs[ref] == opt,
                      onSelected: (_) => setState(() => _inputs[ref] = opt),
                      selectedColor: Colors.deepPurpleAccent,
                      labelStyle: TextStyle(
                          color: _inputs[ref] == opt
                              ? Colors.white
                              : Colors.white70),
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
    // find base image input first (init_image or image or images)
    Map<String, dynamic>? baseImageInput;
    for (final i in widget.config.inputs) {
      if (i["type"] == "image") {
        baseImageInput = i;
        break;
      }
    }

    final raw = baseImageInput != null ? _inputs[baseImageInput["id"]] : null;

    // normalize to list and get first
    Uint8List? baseBytes;
    if (raw == null) {
      baseBytes = null;
    } else if (raw is List && raw.isNotEmpty) {
      baseBytes = raw.first as Uint8List;
    } else if (raw is Uint8List) {
      baseBytes = raw;
    }

    return ElevatedButton.icon(
      icon: const Icon(Icons.edit),
      label: const Text("Draw Mask"),
      onPressed: baseBytes == null
          ? null
          : () async {
              final mask = await _openMaskEditor(baseBytes!);
              if (mask != null) {
                setState(() {
                  _inputs["mask"] = mask;
                });
              }
            },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurpleAccent,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // -------- Generate Button --------
  Widget _buildGenerateButton() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: ElevatedButton.icon(
          icon: const Icon(Icons.flash_on),
          label: const Text("Generate ✨"),
          onPressed: _runJob,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      );

  // -------- Output Preview --------
  Widget _buildOutputPreview() {
    if (_resultData == null) return const SizedBox.shrink();
    return Column(
      children: [
        const SizedBox(height: 20),
        const Text("✨ Result Ready!",
            style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        if (widget.config.outputType == "image")
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_resultData!, fit: BoxFit.contain),
          ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () async {
            final prefix =
                widget.config.model.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
            await FileService.saveFile(context, _resultData!, prefix: prefix);
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text("Save Result"),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.deepPurple),
        )
      ],
    );
  }

  // ----------------------------------------------------
  // 🛰️ JOB SUBMISSION + POLLING
  // ----------------------------------------------------

  Future<void> _runJob() async {
    String? prompt;
    if (_hasPrompt) {
      prompt = _promptController.text.trim();
      _inputs["prompt"] = prompt;
    }

    _inputs["scale_image"] = true;
    if (_hasScaleFactor) {
      _inputs["scale_factor"] = _upscaleEnabled ? _scaleFactor : 1;
    }

    // 🕐 Dynamic message that changes after 45s
    final ValueNotifier<String> dialogMessage = ValueNotifier<String>(
      "Hang tight while we queue and process your request.\n"
      "Avoid pressing back or closing the app.",
    );

    // 🔁 Track if 45 seconds have passed
    Timer(const Duration(seconds: 45), () {
      dialogMessage.value =
          "Still working... It’s taking a bit longer than usual.\nPlease stay on this screen.";
    });

    // 🟣 Elegant animated progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                Colors.deepPurple.withOpacity(0.9),
                Colors.black.withOpacity(0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.deepPurpleAccent.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🔮 Animated progress ring
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(seconds: 1),
                curve: Curves.easeInOut,
                builder: (context, value, _) => Transform.scale(
                  scale: 1 + value * 0.05,
                  child: const CircularProgressIndicator(
                    color: Colors.amberAccent,
                    strokeWidth: 3,
                  ),
                ),
              ),
              const SizedBox(height: 22),

              const Text(
                "Submitting your job...",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 10),

              // 💬 Dynamic message (changes after 45 seconds)
              ValueListenableBuilder<String>(
                valueListenable: dialogMessage,
                builder: (_, value, __) => Text(
                  value,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ✨ Animated dots
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: 3),
                duration: const Duration(milliseconds: 1200),
                builder: (context, value, _) {
                  final dots = "." * (value + 1);
                  return Text(
                    "Processing$dots",
                    style: const TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    // 🔁 Retry logic (up to 3 attempts)
    const int maxRetries = 3;
    int attempt = 0;
    while (attempt < maxRetries) {
      attempt++;
      try {
        // 🔹 Clone inputs
        final encoded = Map<String, dynamic>.from(_inputs);

        // Encode image & list inputs
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

        // Extract & sanitize prompt
        String? promptForPayload;
        if (encoded.containsKey("prompt")) {
          final p = encoded.remove("prompt");
          if (p is String && p.isNotEmpty) promptForPayload = p;
        }
        if (prompt != null && prompt.isNotEmpty) promptForPayload = prompt;

        // Attempt width/height inference
        try {
          final imgInput = widget.config.inputs
              .firstWhere((i) => i["type"] == "image", orElse: () => {});
          final id = imgInput["id"];
          if (encoded.containsKey(id)) {
            final imgVal = encoded[id];
            Uint8List? firstImg;
            if (imgVal is String) {
              firstImg = base64Decode(imgVal);
            } else if (imgVal is List &&
                imgVal.isNotEmpty &&
                imgVal.first is String) {
              firstImg = base64Decode(imgVal.first);
            }

            if (firstImg != null) {
              final codec = await ui.instantiateImageCodec(firstImg);
              final frame = await codec.getNextFrame();
              final img = frame.image;
              int roundTo32(int x) => ((x / 32).round() * 32).clamp(32, 2048);
              encoded["width"] = roundTo32(img.width);
              encoded["height"] = roundTo32(img.height);
              img.dispose();
            }
          }
        } catch (e) {
          debugPrint("⚠️ Skipped width/height detection: $e");
        }

        // Merge params
        final prefs = await SharedPreferences.getInstance();
        final params = {...?widget.config.params, ...encoded};
        params.updateAll(
            (k, v) => v == "random" ? Random().nextInt(99999999) : v);

        // Get FCM token
        String? fcmToken = prefs.getString("fcm_token");
        if (fcmToken == null) {
          fcmToken = await FirebaseMessaging.instance.getToken();
          if (fcmToken != null) await prefs.setString("fcm_token", fcmToken);
          debugPrint("🔑 Refreshed FCM token before submit: $fcmToken");
        }

        // Build payload
        final payload = <String, dynamic>{
          "model": widget.config.model,
          if (promptForPayload?.isNotEmpty ?? false)
            "prompt": promptForPayload
          else if (_hasPrompt)
            "prompt": "Enhance this image creatively.",
          "params": params,
          "fcm_token": fcmToken,
        };
        final payloadJson = jsonEncode(payload);

        // HMAC sign
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

        if (resp.statusCode != 200) {
          throw Exception("Server error ${resp.statusCode}: ${resp.body}");
        }

        if (mounted) Navigator.pop(context); // close dialog

        final data = jsonDecode(resp.body);
        final jobId = data["job_id"];
        final downloadUrl = data["download_url"] ?? data["downloadUrl"];
        if (jobId == null) throw Exception("No job_id returned from submit");

// ✅ Create persistent job entry (single source of truth)
        final newJob = JobModel(
          jobId: jobId,
          title: widget.config.title,
          model: widget.config.model,
          outputType: widget.config.outputType,
          downloadUrl: downloadUrl, // may be null if not ready yet
          status: 'processing',
        );
        await addOrUpdateJob(newJob);

        // ✅ Persist context for FCM taps
        final jobContext = {
          "title": widget.config.title,
          "model": widget.config.model,
          "inputs": widget.config.inputs,
          "params": widget.config.params,
          "outputType": widget.config.outputType,
        };
        await prefs.setString("notify_job_$jobId", jsonEncode(jobContext));

        // ✅ Navigate to results manager
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ResultManagerPage()),
          );
        }

        debugPrint("✅ Job submitted successfully (attempt $attempt): $jobId");
        return; // exit loop on success
      } catch (e) {
        debugPrint("❌ Job submission attempt $attempt failed: $e");
        if (attempt >= maxRetries) {
          if (mounted) Navigator.pop(context);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      "Error submitting job after $maxRetries retries: $e")),
            );
          }
          return;
        }

        // Wait before retry
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

      // 🔹 Fallback if download URL not in data
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

      // 🔹 Check if this job was marked for notification
      bool readyToNotify = false;
      if (jobId != null) {
        readyToNotify = prefs.getBool("notify_requested_$jobId") ?? false;
      }

      // 🔔 Show notification if needed
      if (readyToNotify) {
        await NotificationService.showNotification(
          title: "Processing Complete",
          body: "Tap to view your result.",
          payload: jobId ?? "",
        );
        await prefs.remove("notify_requested_$jobId");
        debugPrint("🔔 Notification shown for completed job $jobId");
      }

      // 🔹 Cleanup: Remove per-job context and metadata
      if (jobId != null) {
        await prefs.remove("notify_job_$jobId");
        await prefs.remove("notify_requested_$jobId");

        final activeJobs = prefs.getStringList("notify_jobs_list") ?? [];
        if (activeJobs.contains(jobId)) {
          activeJobs.remove(jobId);
          await prefs.setStringList("notify_jobs_list", activeJobs);
        }

        debugPrint("🧹 Cleaned up job context for job=$jobId");
      }

      // 🔹 Cleanup generic temp keys (safe even if reused for other jobs)
      await prefs.remove("active_job_id");
      await prefs.remove("cached_result_bytes");
      await prefs.remove("pending_download_url");
      await prefs.remove("selected_images");
      await prefs.remove("job_submitting");
      await prefs.remove("pending_payload");
      await prefs.remove("ready_to_notify");

      // Keep job-independent config keys intact (e.g. last_model)

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
    // _pollTimer?.cancel();
  }

  // ----------------------------------------------------
  // 🖼️ BUILD UI — Scaffold + Mode Selector + Dynamic Elements
  // ----------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config.title),
        backgroundColor: Colors.deepPurple,
      ),
      body: _resultData != null
          ? _buildResultScreen()
          : _buildDynamicInputScreen(),
    );
  }

  Widget _buildDynamicInputScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          if (widget.config.modes != null && widget.config.modes!.isNotEmpty)
            _buildModeSelector(),
          const SizedBox(height: 10),
          ..._currentElements.map(_buildElement).toList(),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    final modes = widget.config.modes!;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Mode", style: TextStyle(color: Colors.white70)),
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

                        // 🧩 ensure all image inputs are initialized properly
                        for (final input in widget.config.inputs) {
                          if (input['type'] == 'image') {
                            final id = input['id'];
                            debugPrint(
                                "🔄 Mode switch: initialized image input '$id'");
                          }
                        }
                      });
                    },
                    selectedColor: Colors.deepPurpleAccent,
                    labelStyle: TextStyle(
                      color: _selectedModeKey == entry.key
                          ? Colors.white
                          : Colors.white70,
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
  // 💫 LOADING SCREEN
  // ----------------------------------------------------

  // ----------------------------------------------------
  // 🌈 RESULT SCREEN
  // ----------------------------------------------------
  Widget _buildResultScreen() {
    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Colors.deepPurple, Colors.purpleAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight)),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text("✨ Result Ready!",
                  style: TextStyle(
                      fontSize: 22,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              if (widget.config.outputType == "image" && _resultData != null)
                ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(_resultData!,
                        height: 360, fit: BoxFit.contain)),
              const SizedBox(height: 25),
              ElevatedButton.icon(
                onPressed: () async {
                  final prefix = widget.config.model
                      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
                  await FileService.saveFile(context, _resultData!,
                      prefix: prefix);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text("Save Result"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepPurple),
              ),
              const SizedBox(height: 12),
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
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text("Try Again",
                    style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(height: 20),
            ],
          ),
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

    // Work in image pixel coordinates. Use saveLayer so blend modes (clear) work.
    final rect =
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
    canvas.saveLayer(rect, Paint());

    // Do NOT draw a background — leave it transparent.

    for (final s in _strokes) {
      if (s.points.isEmpty) continue;

      // Paint for path (stroke)
      final pathPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.size
        ..isAntiAlias = true;

      // Paint for round caps (fill)
      final capPaint = Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      if (s.eraser) {
        // Eraser: clear pixels
        pathPaint.blendMode = BlendMode.clear;
        capPaint.blendMode = BlendMode.clear;
      } else {
        // Mask stroke: semi-transparent white
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

      // draw round caps to ensure endpoints are filled
      for (final p in s.points) {
        canvas.drawCircle(Offset(p.dx, p.dy), s.size / 2, capPaint);
      }
    }

    canvas.restore(); // apply saveLayer

    final picture = recorder.endRecording();
    final maskImage = await picture.toImage(img.width, img.height);
    final byteData = await maskImage.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            title: const Text("Draw Mask"), backgroundColor: Colors.deepPurple),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_image == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            title: const Text("Draw Mask"), backgroundColor: Colors.deepPurple),
        body: const Center(
            child: Text("Failed to load image",
                style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Draw Mask"),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            tooltip: "Undo",
            icon: const Icon(Icons.undo),
            onPressed: () {
              if (_strokes.isNotEmpty) setState(() => _strokes.removeLast());
            },
          ),
          IconButton(
            tooltip: "Clear",
            icon: const Icon(Icons.layers_clear),
            onPressed: () => setState(() => _strokes.clear()),
          ),
          IconButton(
            tooltip: "Toggle Eraser",
            icon: Icon(_eraser ? Icons.brush : Icons.auto_fix_high),
            onPressed: () => setState(() => _eraser = !_eraser),
          ),
          IconButton(
            tooltip: "Save Mask",
            icon: const Icon(Icons.check),
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
                  color: Colors.black,
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
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.brush, color: Colors.white70),
                          Expanded(
                            child: Slider(
                              value: _brushSize,
                              min: 4,
                              max: 120,
                              onChanged: (v) => setState(() => _brushSize = v),
                              activeColor: Colors.white,
                              inactiveColor: Colors.white24,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text("${_brushSize.toInt()}",
                              style: const TextStyle(color: Colors.white70)),
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

      // draw round caps as semi-transparent fill
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

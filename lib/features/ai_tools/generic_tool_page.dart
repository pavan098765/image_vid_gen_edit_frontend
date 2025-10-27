// generic_tool_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:image_vid_gen_edit_frontend/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:crypto/crypto.dart';

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
  bool _submittingJob = false;
  bool _notifyLater = false;
  String? _selectedModeKey;
  Uint8List? _resultData;
  String? _activeJobId;
  Timer? _pollTimer;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _sparkleController;
  late AnimationController _progressController;

  // for multi-image preview
  int _previewPageIndex = 0;
  late PageController _previewPageController;

  // Controllers
  final TextEditingController _promptController = TextEditingController();

  // HMAC config
  static const String baseUrl = "https://genedit.mooo.com";
  static const String controllerUrl = "https://genedit.mooo.com";
  static const String controllerApiKey = "SECRETKEY";
  static const String controllerSharedSecret = "SECRET";
  static const int pollIntervalSec = 10;
  static const int processingDurationSec = 120;

  // Dynamic text & animations
  final List<String> _loadingTexts = [
    "✨ Processing input...",
    "🎨 Merging creative decisions...",
    "🧠 Tuning model parameters...",
    "🔍 Checking details...",
    "🌟 Finalizing output...",
    "✨ Polishing pixels...",
    "🎨 Asking AI gods for creative blessings...",
    "🪄 Mixing colors from another dimension...",
    "🔍 Looking for perfect lighting...",
    "🧠 Teaching model some art sense...",
    "🐢 Patience is an art too...",
    "🌌 Summoning creative spirits...",
    "🎶 Humming creativity tune...",
  ];

  final List<String> _funFacts = [
    "The first digital image was created in 1957.",
    "AI learns styles from examples.",
    "A detailed prompt can yield clearer results.",
    "Van Gogh sold only one painting in his life.",
    "The word 'Pixel' means 'Picture Element'.",
    "Monet painted the same scene over 250 times!",
    "Cinematic lighting can double engagement.",
  ];

  final List<String> _aiChats = [
    "🤖 Fine-tuning the output...",
    "🪄 Blending textures...",
    "💫 Adjusting color balance...",
    "✨ Adding final touches...",
    "🤖 Hmm… these colors are blending nicely.",
    "🪄 I’m tweaking the lighting — almost perfect!",
    "🎨 Ooo, this palette looks stunning already.",
    "💫 Adding a bit of dreamlike glow…",
    "✨ Fine-tuning those highlights!",
    "🔥 I think you’ll love this one!",
  ];

  final List<String> _waitingMessages = [
    "⏳ This is taking a bit longer — almost done!",
    "🚀 Doing heavy-lift processing...",
    "🔮 Precision adjustments underway...",
    "⏳ Still cooking something special for you...",
    "🚀 This one’s taking a little longer — hang tight!",
    "✨ The AI is adding some finishing touches...",
    "🔮 Complex masterpiece detected — stay with us!",
    "🧘‍♂️ Patience level: Artist-grade!",
  ];

  final List<String> _stages = [
    "Analyzing",
    "Enhancing",
    "Coloring",
    "Detailing",
    "Finalizing"
  ];

  final List<IconData> _loadingIcons = [
    Icons.auto_awesome,
    Icons.stars_rounded,
    Icons.bolt,
    Icons.color_lens,
  ];

  int _loadingTextIndex = 0;
  int _iconIndex = 0;
  String _currentFunFact = "";
  String _currentAiChat = "";
  final Random _rand = Random();

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

    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _sparkleController =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: processingDurationSec),
    );

    _previewPageController = PageController();

    // Default mode
    if (widget.config.modes != null && widget.config.modes!.isNotEmpty) {
      _selectedModeKey = widget.config.modes!.keys.first;
    }

    if (widget.restoreJobId != null) {
      _activeJobId = widget.restoreJobId;
      _loading = true;
      _pollJobStatus(); // resume polling immediately
    }

    _sparkleController.addListener(() {
      if (mounted) setState(() {});
    });

    _restoreJobIfExists();
    debugPrint("🔧 Config for ${widget.config.model}");
    debugPrint("  title=${widget.config.title}");
    debugPrint("  elements=${widget.config.elements?.length}");
    debugPrint("  modes=${widget.config.modes?.keys}");
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _sparkleController.dispose();
    _progressController.dispose();
    _pollTimer?.cancel();
    _promptController.dispose();
    _previewPageController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pulseController.stop();
      _sparkleController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _pulseController.repeat(reverse: true);
      _sparkleController.repeat();
      if (!_submittingJob && _activeJobId != null && _loading) {
        _pollJobStatus();
      }
    }
  }

  // restore job state if interrupted
  Future<void> _restoreJobIfExists() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString("active_job_id");
    if (jobId == null) return;

    try {
      final url = '$baseUrl/job_status?job_id=$jobId';
      final payloadJson = jsonEncode({"job_id": jobId});
      final signatureBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
          .convert(utf8.encode(payloadJson));
      final signature = "sha256=${signatureBytes.toString()}";
      final headers = {
        "Authorization": "Bearer $controllerApiKey",
        "X-Signature": signature,
      };

      final response = await http.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) {
        await prefs.remove("active_job_id");
        return;
      }

      final data = jsonDecode(response.body);
      final status = data['status'];
      if (status == 'running' || status == 'queued') {
        setState(() {
          _activeJobId = jobId;
          _loading = true;
        });
        _progressController.forward(from: 0);
        _startTextRotation();
        _pollJobStatus();
      } else {
        await prefs.remove("active_job_id");
      }
    } catch (e) {
      debugPrint("Failed to restore job: $e");
    }
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
    if (width > 1536 || height > 1536) {
      final scale = 1536 / max(width, height);
      width = (width * scale).floor();
      height = (height * scale).floor();
    }
    width = (width ~/ 32) * 32;
    height = (height ~/ 32) * 32;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint());
    final result = await recorder
        .endRecording()
        .toImage(width, height)
        .then((v) => v.toByteData(format: ui.ImageByteFormat.png));
    img.dispose();
    return result!.buffer.asUint8List();
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
            activeColor: Colors.deepPurpleAccent,
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
          label: Text("Generate ✨"),
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
    // attach prompt text to _inputs for UI use, but send top-level in payload
    String? prompt;
    if (_hasPrompt) {
      prompt = _promptController.text.trim();
      _inputs["prompt"] = prompt;
    }

    _inputs["scale_image"] = true;
    if (_hasScaleFactor) {
      _inputs["scale_factor"] = _upscaleEnabled ? _scaleFactor : 1;
    }

    setState(() {
      _loading = true;
      _loadingTextIndex = 0;
      _iconIndex = 0;
      _currentFunFact = _funFacts[_rand.nextInt(_funFacts.length)];
      _currentAiChat = _aiChats[_rand.nextInt(_aiChats.length)];
    });

    _progressController.forward(from: 0);
    _startTextRotation();
    _submittingJob = true;

    try {
      // -------------------------
      // ENCODE INPUTS
      // -------------------------
      final encoded = Map<String, dynamic>.from(_inputs);
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
            final List<String> b64List =
                val.map((e) => base64Encode(e as Uint8List)).toList();
            encoded[key] = (b64List.length == 1) ? b64List.first : b64List;
          } else {
            final listStr = List<String>.from(val);
            encoded[key] = (listStr.length == 1) ? listStr.first : listStr;
          }
        }
      }

      // Extract prompt for payload (top-level)
      String? promptForPayload;
      if (encoded.containsKey("prompt")) {
        final p = encoded.remove("prompt");
        if (p is String && p.isNotEmpty) promptForPayload = p;
      }
      if (prompt != null && prompt.isNotEmpty) promptForPayload = prompt;

      // -------------------------
      // OPTIONAL: infer image width/height for diffusion models
      // -------------------------
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
            int width = img.width;
            int height = img.height;
            int roundTo32(int x) => ((x / 32).round() * 32).clamp(32, 2048);
            encoded["width"] = roundTo32(width);
            encoded["height"] = roundTo32(height);
            img.dispose();
          }
        }
      } catch (e) {
        debugPrint("⚠️ Skipped width/height detection: $e");
      }

      // -------------------------
      // Merge static params
      // -------------------------
      final params = {...?widget.config.params, ...encoded};
      params.forEach((k, v) {
        if (v == "random") params[k] = Random().nextInt(99999999);
      });

      // -------------------------
      // Build payload (prompt top-level)
      // -------------------------
      final payload = <String, dynamic>{
        "model": widget.config.model,
        if (promptForPayload != null && promptForPayload.isNotEmpty)
          "prompt": promptForPayload
        else if (_hasPrompt)
          "prompt": "Enhance this image creatively.",
        "params": params,
      };

      final payloadJson = jsonEncode(payload);

      // Sign request
      final sigBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
          .convert(utf8.encode(payloadJson));
      final signature = "sha256=${sigBytes.toString()}";

      final headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer $controllerApiKey",
        "X-Signature": signature
      };

      // -------------------------
      // SUBMIT JOB
      // -------------------------
      final resp = await http.post(Uri.parse('$controllerUrl/submit'),
          headers: headers, body: payloadJson);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        final jobId = data["job_id"];
        final downloadUrl = data["download_url"];
        if (jobId == null) throw Exception("No job_id returned from submit");

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("active_job_id", jobId);

        // 🧠 Save last used model config for auto-restore later
        await prefs.setString("last_model", widget.config.model);
        if (widget.config.params != null) {
          await prefs.setString(
              "last_model_params", jsonEncode(widget.config.params));
        }
        if (widget.config.inputs.isNotEmpty) {
          await prefs.setString(
              "last_model_inputs", jsonEncode(widget.config.inputs));
        }

        if (downloadUrl != null &&
            downloadUrl is String &&
            downloadUrl.isNotEmpty) {
          await prefs.setString("pending_download_url", downloadUrl);
        }

        // Save selected images
        final savedImages = <String>[];
        for (final input in widget.config.inputs) {
          if (input['type'] == 'image') {
            final id = input['id'];
            if (encoded.containsKey(id)) {
              final v = encoded[id];
              if (v is String) savedImages.add(v);
              if (v is List) savedImages.addAll(List<String>.from(v));
            }
          }
        }
        if (savedImages.isNotEmpty) {
          await prefs.setStringList("selected_images", savedImages);
        }

        setState(() {
          _activeJobId = jobId;
          _submittingJob = false;
        });

        _pollJobStatus();
        _startTimeoutCheck();
      } else {
        throw Exception("Server error ${resp.statusCode}");
      }
    } catch (e) {
      debugPrint("Submit failed: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
      setState(() {
        _loading = false;
        _submittingJob = false;
      });
    }
  }

  void _startTimeoutCheck() {
    // Wait for 2 minutes
    Future.delayed(const Duration(minutes: 2), () async {
      // Only trigger if still waiting and page is active
      if (!mounted || !_loading || !_activeJobIdSet()) return;

      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            backgroundColor: Colors.deepPurple.shade50,
            title: const Text("Still processing..."),
            content: const Text(
              "This job is taking longer than usual.\n"
              "Would you like to continue waiting or get notified later when it’s ready?",
            ),
            actions: [
              TextButton(
                child: const Text("Continue waiting"),
                onPressed: () => Navigator.of(context).pop("continue"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                child: const Text("Notify me later"),
                onPressed: () => Navigator.of(context).pop("notify"),
              ),
            ],
          );
        },
      );

      if (choice == "notify") {
        setState(() => _notifyLater = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You'll be notified once the result is ready."),
          ),
        );
        // let user freely navigate
        Navigator.of(context).maybePop();
      }
    });
  }

  bool _activeJobIdSet() => _activeJobId != null && _activeJobId!.isNotEmpty;

  void _pollJobStatus() {
    if (_submittingJob) return;
    _pollTimer?.cancel();

    _pollTimer =
        Timer.periodic(const Duration(seconds: pollIntervalSec), (_) async {
      if (_activeJobId == null) return;
      try {
        final payloadJson = jsonEncode({"job_id": _activeJobId});
        final sigBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
            .convert(utf8.encode(payloadJson));
        final sig = "sha256=${sigBytes.toString()}";

        final headers = {
          "Authorization": "Bearer $controllerApiKey",
          "X-Signature": sig
        };
        final url = "$baseUrl/job_status?job_id=$_activeJobId";
        final resp = await http.get(Uri.parse(url), headers: headers);
        if (resp.statusCode != 200) return;

        final data = jsonDecode(resp.body);
        if (data["download_url"] != null) {
          final prefs = await SharedPreferences.getInstance();
          prefs.setString("pending_download_url", data["download_url"]);
        }
        final status = data["status"];
        if (status == "completed") {
          _pollTimer?.cancel();
          _fetchResult(data);
          if (_notifyLater) {
            await _showNotification(_activeJobId!);
          }
        } else if (status == "failed") {
          _pollTimer?.cancel();
          _onJobFailed(data["error"] ?? "Unknown error");
        }
      } catch (e) {
        debugPrint("pollJob error: $e");
      }
    });
  }

  Future<void> _showNotification(String jobId) async {
    const androidDetails = AndroidNotificationDetails(
      'job_results',
      'AI Job Results',
      channelDescription: 'Notifications for completed AI jobs',
      importance: Importance.max,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    NotificationService.showNotification(
      title: "Processing Complete",
      body: "Tap to view your result",
      payload: jobId,
    );
  }

  Future<void> _fetchResult(Map<String, dynamic> data) async {
    try {
      String? downloadUrl = data["download_url"];
      if (downloadUrl == null) {
        final prefs = await SharedPreferences.getInstance();
        downloadUrl = prefs.getString("pending_download_url");
      }
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

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove("active_job_id");
      await prefs.remove("pending_download_url");
      await prefs.remove("selected_images");
      await prefs.remove("last_model");
      await prefs.remove("last_model_params");
      await prefs.remove("last_model_inputs");

      _progressController.stop();
      _progressController.reset();
      debugPrint("✅ Result image fetched & displayed successfully");
    } catch (e) {
      _onJobFailed(e.toString());
    }
  }

  void _onJobFailed(String error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Job failed: $error")));
    setState(() {
      _loading = false;
      _resultData = null;
    });
    _pollTimer?.cancel();
  }

  // ----------------------------------------------------
  // ⏱️ TEXT ROTATION + LOADING ANIMATION
  // ----------------------------------------------------
  void _startTextRotation() async {
    while (_loading && mounted) {
      await Future.delayed(const Duration(seconds: 5));
      if (!_loading) break;
      setState(() {
        _loadingTextIndex = (_loadingTextIndex + 1) % _loadingTexts.length;
        _iconIndex = (_iconIndex + 1) % _loadingIcons.length;
        if (_rand.nextBool()) {
          _currentFunFact = _funFacts[_rand.nextInt(_funFacts.length)];
          _currentAiChat = "";
        } else {
          _currentAiChat = _aiChats[_rand.nextInt(_aiChats.length)];
          _currentFunFact = "";
        }
      });
    }
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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: _loading
            ? _buildLoadingScreen()
            : (_resultData != null
                ? _buildResultScreen()
                : _buildDynamicInputScreen()),
      ),
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
                            _inputs[id] ??= null;
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
  String _formatRemainingTime() {
    final remaining =
        ((1.0 - _progressController.value) * processingDurationSec).ceil();
    final m = (remaining ~/ 60).toString().padLeft(2, "0");
    final s = (remaining % 60).toString().padLeft(2, "0");
    return "$m:$s left";
  }

  Widget _buildStageIndicator() {
    final v = _progressController.value;
    int active = (v * _stages.length).clamp(0, _stages.length - 1).floor();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_stages.length, (i) {
        final activeColor =
            i <= active ? Colors.white : Colors.white.withOpacity(0.3);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              Icon(Icons.circle, size: 10, color: activeColor),
              const SizedBox(height: 4),
              Text(_stages[i],
                  style: TextStyle(color: activeColor, fontSize: 11)),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildLoadingScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black.withOpacity(0.8)),
        BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.transparent)),
        Positioned.fill(
          child: IgnorePointer(
              child: CustomPaint(
                  painter: _SparklePainter(_sparkleController.value))),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween(begin: 0.9, end: 1.15).animate(CurvedAnimation(
                    parent: _pulseController, curve: Curves.easeInOut)),
                child: Icon(_loadingIcons[_iconIndex],
                    color: Colors.white, size: 90),
              ),
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: Text(_loadingTexts[_loadingTextIndex],
                    key: ValueKey<int>(_loadingTextIndex),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: Text(
                    _currentAiChat.isNotEmpty
                        ? _currentAiChat
                        : "💡 $_currentFunFact",
                    key: ValueKey<String>(_currentAiChat.isNotEmpty
                        ? _currentAiChat
                        : _currentFunFact),
                    style: const TextStyle(
                        color: Colors.white70,
                        fontStyle: FontStyle.italic,
                        fontSize: 16)),
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                      value: _progressController.value,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation(Colors.white)),
                ),
              ),
              const SizedBox(height: 8),
              Text(_formatRemainingTime(),
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              _buildStageIndicator(),
            ],
          ),
        ),
      ],
    );
  }

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
                  setState(() {
                    _resultData = null;
                    _inputs.clear();
                    _promptController.clear();
                    _upscaleEnabled = false;
                    _scaleFactor = 2;
                  });
                },
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text("Try Another",
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

// ------------------ SPARKLE EFFECT ------------------
class _SparklePainter extends CustomPainter {
  final double progress;
  _SparklePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    const int numSparkles = 24;
    final baseColor =
        Color.lerp(Colors.deepPurpleAccent, Colors.amberAccent, progress)!;
    final rnd = Random((progress * 1000).toInt());

    for (int i = 0; i < numSparkles; i++) {
      final phase = (progress + i / numSparkles) % 1.0;
      final eased = Curves.easeOut.transform(1.0 - phase);

      final xBase = size.width * (i / (numSparkles - 1));
      final xJitter = (rnd.nextDouble() * 40 - 20) * (0.6 + 0.4 * eased);
      final dx = (xBase + xJitter).clamp(0.0, size.width);
      final dy = (size.height * (1.0 - eased)).clamp(0.0, size.height);

      final coreRadius = (1.0 + rnd.nextDouble() * 2.5) * (0.6 + 1.4 * eased);
      final glowRadius = coreRadius * (2.5 + rnd.nextDouble() * 1.5);
      final alpha = ((0.25 + rnd.nextDouble() * 0.6) * (0.8 + 0.2 * eased))
          .clamp(0.05, 1.0);

      final baseHsv = HSVColor.fromColor(baseColor);
      final hue = (baseHsv.hue + i * 6) % 360;
      final col =
          HSVColor.fromAHSV(1.0, hue, baseHsv.saturation * 0.95, 1.0).toColor();

      final glowPaint = Paint()
        ..color = col.withOpacity((alpha * 0.6).clamp(0.05, 0.6))
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 8)
        ..blendMode = BlendMode.plus
        ..isAntiAlias = true;

      final corePaint = Paint()
        ..color = col.withOpacity((alpha * 1.0).clamp(0.2, 1.0))
        ..blendMode = BlendMode.plus
        ..isAntiAlias = true;

      canvas.drawCircle(Offset(dx, dy), glowRadius, glowPaint);
      canvas.drawCircle(Offset(dx, dy), coreRadius, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
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

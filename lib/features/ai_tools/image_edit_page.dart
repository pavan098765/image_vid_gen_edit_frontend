import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:crypto/crypto.dart';

// ---------------- CONFIG CLASS ----------------
class ImageEditConfig {
  final String title;
  final String model;
  final int maxImages;

  const ImageEditConfig({
    required this.title,
    required this.model,
    this.maxImages = 1,
  });
}

// ---------------- MAIN PAGE ----------------
class ImageEditPage extends StatefulWidget {
  final ImageEditConfig config;
  const ImageEditPage({super.key, required this.config});

  @override
  State<ImageEditPage> createState() => _ImageEditPageState();
}

class _ImageEditPageState extends State<ImageEditPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  List<Uint8List> _selectedImages = [];
  Uint8List? _resultImage;
  final picker = ImagePicker();
  final TextEditingController _promptController = TextEditingController();

  bool _loading = false;
  bool _submittingJob = false;
  String? _activeJobId;
  Timer? _pollTimer;
  bool _scaleImage = false;
  int _scaleFactor = 2;

  late AnimationController _pulseController;
  late AnimationController _sparkleController;
  late AnimationController _progressController;

  final List<String> _loadingTexts = [
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
    "Van Gogh sold only one painting in his life.",
    "The word 'Pixel' means 'Picture Element'.",
    "First digital image was created in 1957.",
    "Monet painted the same scene over 250 times!",
    "Cinematic lighting can double engagement.",
  ];

  final List<String> _aiChats = [
    "🤖 Hmm… these colors are blending nicely.",
    "🪄 I’m tweaking the lighting — almost perfect!",
    "🎨 Ooo, this palette looks stunning already.",
    "💫 Adding a bit of dreamlike glow…",
    "✨ Fine-tuning those highlights!",
    "🔥 I think you’ll love this one!",
  ];

  final List<String> _waitingMessages = [
    "⏳ Still cooking something special for you...",
    "🚀 This one’s taking a little longer — hang tight!",
    "✨ The AI is adding some finishing touches...",
    "🔮 Complex masterpiece detected — stay with us!",
    "🧘‍♂️ Patience level: Artist-grade!",
  ];

  final List<IconData> _loadingIcons = [
    Icons.auto_awesome,
    Icons.stars_rounded,
    Icons.bolt,
    Icons.color_lens,
    Icons.blur_on,
  ];

  int _loadingTextIndex = 0;
  int _iconIndex = 0;
  String _currentFunFact = "";
  String _currentAiChat = "";
  final Random _rand = Random();

  static const String baseUrl = "https://genedit.mooo.com";
  static const String controllerUrl = "https://genedit.mooo.com";
  static const String controllerApiKey = "SECRETKEY";
  static const String controllerSharedSecret = "SECRET";
  static const int pollIntervalSec = 10;
  static const int processingDurationSec = 120;

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

    _sparkleController.addListener(() {
      if (mounted) setState(() {});
    });

    _restoreJobIfExists();
  }

  @override
  void didUpdateWidget(covariant ImageEditPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.model != widget.config.model) {
      debugPrint(
          "🔁 Model changed from ${oldWidget.config.model} to ${widget.config.model}");
      setState(() {
        _selectedImages.clear();
        _resultImage = null;
        _promptController.clear();
        _loading = false;
        _activeJobId = null;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pulseController.dispose();
    _sparkleController.dispose();
    _progressController.dispose();
    _promptController.dispose();
    _pollTimer?.cancel();

    // 🧹 Cleanup saved images on exit
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove("selected_images");
      prefs.remove("active_job_id");
      prefs.remove("pending_download_url");
    });
    super.dispose();
  }

  // ---------------- LIFECYCLE ----------------
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pauseAnimations();
    } else if (state == AppLifecycleState.resumed) {
      _resumeAnimations();
      if (!_submittingJob && _activeJobId != null && _loading) {
        _pollJobStatus();
      } else if (_submittingJob) {
        debugPrint("🕓 App resumed but still submitting — not polling yet");
      }
    }
  }

  void _pauseAnimations() {
    _pulseController.stop();
    _sparkleController.stop();
  }

  void _resumeAnimations() {
    _pulseController.repeat(reverse: true);
    _sparkleController.repeat();
  }

  // ---------------- RESTORE JOB ----------------
  Future<void> _restoreJobIfExists() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString("active_job_id");
    if (jobId == null) return;

    try {
      final savedImagesBase64 = prefs.getStringList("selected_images");
      if (savedImagesBase64 != null) {
        _selectedImages = savedImagesBase64.map(base64Decode).toList();
      }

      final url = '$baseUrl/job_status?job_id=$jobId';
      final payload = {"job_id": jobId};
      final payloadJson = jsonEncode(payload);

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
      debugPrint("⚠️ Failed to restore job: $e");
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove("active_job_id");
    }
  }

  // ---------------- IMAGE PICK (unified) ----------------
  /// Picks images. For gallery: uses multi-image if config.maxImages > 1.
  /// For camera: picks a single image.
  Future<void> _pickImages(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        // Camera always returns a single image
        final picked = await picker.pickImage(
            source: ImageSource.camera, imageQuality: 90);
        if (picked == null) return;
        final bytes = await picked.readAsBytes();
        setState(() {
          _selectedImages = [bytes];
          _resultImage = null;
        });
      } else {
        // Gallery: allow multi when maxImages > 1
        if (widget.config.maxImages == 1) {
          final picked = await picker.pickImage(
              source: ImageSource.gallery, imageQuality: 90);
          if (picked == null) return;
          final bytes = await picked.readAsBytes();
          setState(() {
            _selectedImages = [bytes];
            _resultImage = null;
          });
        } else {
          final pickedFiles = await picker.pickMultiImage(imageQuality: 90);
          if (pickedFiles.isEmpty) return;
          final max = widget.config.maxImages;
          final limited = pickedFiles.take(max).toList();
          final bytesList = <Uint8List>[];
          for (final f in limited) {
            bytesList.add(await f.readAsBytes());
          }
          setState(() {
            _selectedImages = bytesList;
            _resultImage = null;
          });
        }
      }
    } catch (e) {
      debugPrint("❌ Image pick failed: $e");
    }
  }

  // ---------------- RUN MODEL ----------------
  Future<void> _runEditJob() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one image.')));
      return;
    }

    setState(() {
      _loading = true;
      _loadingTextIndex = 0;
      _iconIndex = 0;
      _resultImage = null;
      _currentFunFact = _funFacts[_rand.nextInt(_funFacts.length)];
      _currentAiChat = _aiChats[_rand.nextInt(_aiChats.length)];
    });

    _progressController.forward(from: 0);
    _startTextRotation();
    _submittingJob = true;

    try {
      // Get size from first image
      final codec = await ui.instantiateImageCodec(_selectedImages.first);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final inputWidth = image.width;
      final inputHeight = image.height;
      int roundTo32(int x) => ((x / 32).round() * 32).clamp(32, 2048);
      final height = roundTo32(inputHeight);
      final width = roundTo32(inputWidth);

      // Prepare payload
      final base64Images = _selectedImages.map(base64Encode).toList();
      final params = {
        if (widget.config.model == 'flux_kontext_dev')
          "steps": 28
        else
          "steps": 8,
        "guidance_scale": 3.0,
        "seed":
            Random().nextInt(1000000000), // random seed between 0 and 1 billion
        "scale_image": true,
        "scale_factor": _scaleImage ? _scaleFactor : 1,
        "height": height,
        "width": width,
        "negative_prompt": "blurry, distorted, lowres",
        "timeout": 300,
        if (base64Images.length == 1)
          "init_image": base64Images.first
        else
          "images": base64Images,
      };

      final payload = {
        "model": widget.config.model,
        "prompt": _promptController.text.trim().isNotEmpty
            ? _promptController.text.trim()
            : "Enhance this image creatively.",
        "params": params,
      };

      final payloadJson = jsonEncode(payload);
      final signatureBytes = Hmac(sha256, utf8.encode(controllerSharedSecret))
          .convert(utf8.encode(payloadJson));
      final signature = "sha256=${signatureBytes.toString()}";

      final headers = {
        "Content-Type": "application/json",
        "X-Signature": signature,
        "Authorization": "Bearer $controllerApiKey",
      };

      final response = await http.post(
        Uri.parse('$controllerUrl/submit'),
        headers: headers,
        body: payloadJson,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final jobId = data['job_id'];
        final downloadUrl = data['download_url'];
        if (jobId == null) throw Exception("No job_id in response");

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("active_job_id", jobId);
        await prefs.setStringList(
            "selected_images", _selectedImages.map(base64Encode).toList());

        if (downloadUrl != null) {
          await prefs.setString("pending_download_url", downloadUrl);
        }

        setState(() => _activeJobId = jobId);
        _submittingJob = false;
        _pollJobStatus();
      } else {
        throw Exception("Job submission failed (${response.statusCode})");
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _loading = false);
      _submittingJob = false;
    }
  }

  // ---------------- POLLING ----------------
  void _pollJobStatus() {
    if (_submittingJob) return;
    _pollTimer?.cancel();

    _pollTimer = Timer.periodic(
      const Duration(seconds: pollIntervalSec),
      (_) async {
        if (_activeJobId == null) return;

        try {
          final url = '$baseUrl/job_status?job_id=$_activeJobId';
          final payload = {"job_id": _activeJobId};
          final payloadJson = jsonEncode(payload);
          final signatureBytes =
              Hmac(sha256, utf8.encode(controllerSharedSecret))
                  .convert(utf8.encode(payloadJson));
          final signature = "sha256=${signatureBytes.toString()}";

          final headers = {
            "Authorization": "Bearer $controllerApiKey",
            "X-Signature": signature,
          };

          final response = await http.get(Uri.parse(url), headers: headers);
          if (response.statusCode != 200) return;
          final data = jsonDecode(response.body);
          final status = data['status'];

          if (status == 'completed') {
            _pollTimer?.cancel();
            _fetchResultImage(data);
          } else if (status == 'failed') {
            _pollTimer?.cancel();
            _onJobFailed(data['error'] ?? 'Unknown error');
          }
        } catch (e) {
          debugPrint("❌ Error checking job status: $e");
        }
      },
    );
  }

  // ---------------- FETCH RESULT ----------------
  Future<void> _fetchResultImage(Map<String, dynamic> jobData) async {
    try {
      String? downloadUrl = jobData['download_url'];
      if (downloadUrl == null) {
        final prefs = await SharedPreferences.getInstance();
        downloadUrl = prefs.getString("pending_download_url");
      }
      if (downloadUrl == null || downloadUrl.isEmpty) return;

      final resp = await http.get(Uri.parse(downloadUrl));
      final bytes = resp.bodyBytes;

      setState(() {
        _resultImage = bytes;
        _loading = false;
      });

      final prefs = await SharedPreferences.getInstance();
      prefs.remove("active_job_id");
      prefs.remove("pending_download_url");
      prefs.remove("selected_images");

      _progressController.stop();
      _progressController.reset();
    } catch (e) {
      _onJobFailed(e.toString());
    }
  }

  void _onJobFailed(String error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Job failed: $error')));
    setState(() {
      _loading = false;
      _selectedImages.clear();
      _resultImage = null;
    });
  }

  // ---------------- LOADING TEXT ----------------
  void _startTextRotation() {
    Future(() async {
      while (_loading && mounted) {
        await Future.delayed(const Duration(seconds: 5));
        if (!_loading || !mounted) break;
        setState(() {
          _loadingTextIndex = (_loadingTextIndex + 1) % _loadingTexts.length;
          _iconIndex = (_iconIndex + 1) % _loadingIcons.length;
          if (_rand.nextBool()) {
            _currentFunFact = "";
            _currentAiChat = _aiChats[_rand.nextInt(_aiChats.length)];
          } else {
            _currentAiChat = "";
            _currentFunFact = _funFacts[_rand.nextInt(_funFacts.length)];
          }
          if (_progressController.isCompleted) {
            final msg =
                _waitingMessages[_rand.nextInt(_waitingMessages.length)];
            _currentAiChat = msg;
            _currentFunFact = "";
          }
        });
      }
    });
  }

  // ---------------- UI ----------------
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
            : (_resultImage != null
                ? _buildResultScreen()
                : _buildImageSelection()),
      ),
    );
  }

  Widget _buildStageIndicator() {
    final value = _progressController.value;
    const stages = [
      "Analyzing",
      "Enhancing",
      "Coloring",
      "Detailing",
      "Finalizing"
    ];
    int activeStage =
        (value * stages.length).clamp(0, stages.length - 1).floor();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(stages.length, (i) {
        final isActive = i <= activeStage;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              Icon(Icons.circle,
                  size: 10, color: isActive ? Colors.white : Colors.white30),
              const SizedBox(height: 4),
              Text(stages[i],
                  style: TextStyle(
                      color: isActive ? Colors.white : Colors.white38,
                      fontSize: 11)),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildLoadingScreen() {
    final firstSelected =
        _selectedImages.isNotEmpty ? _selectedImages.first : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (firstSelected != null) ...[
          Image.memory(firstSelected, fit: BoxFit.cover),
          Container(color: Colors.black.withOpacity(0.45)),
          BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(color: Colors.transparent)),
        ],
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
                scale: Tween<double>(begin: 0.9, end: 1.15).animate(
                    CurvedAnimation(
                        parent: _pulseController, curve: Curves.easeInOut)),
                child: Icon(_loadingIcons[_iconIndex],
                    color: Colors.white, size: 90),
              ),
              const SizedBox(height: 25),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: Text(_loadingTexts[_loadingTextIndex],
                    key: ValueKey<int>(_loadingTextIndex),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        shadows: [
                          Shadow(blurRadius: 6, color: Colors.black54)
                        ])),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 800),
                child: Text(
                  _currentAiChat.isNotEmpty
                      ? _currentAiChat
                      : (_currentFunFact.isNotEmpty
                          ? "💡 $_currentFunFact"
                          : ""),
                  key: ValueKey<String>(_currentAiChat.isNotEmpty
                      ? _currentAiChat
                      : _currentFunFact),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 35),
              SizedBox(
                width: 260,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                    value: _progressController.value,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(_formatRemainingTime(),
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              _buildStageIndicator(),
            ],
          ),
        ),
      ],
    );
  }

  String _formatRemainingTime() {
    final remaining =
        ((1.0 - _progressController.value) * processingDurationSec).ceil();
    final minutes = (remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (remaining % 60).toString().padLeft(2, '0');
    return "$minutes:$seconds left";
  }

  Widget _buildImageSelection() {
    final firstSelected =
        _selectedImages.isNotEmpty ? _selectedImages.first : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // ----- IMAGE PREVIEW (single) -----
          if (firstSelected != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.memory(firstSelected, fit: BoxFit.contain),
                ),
              ),
            )
          else
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.black12,
              ),
              child: const Center(
                child: Icon(Icons.image, color: Colors.white30, size: 50),
              ),
            ),

          const SizedBox(height: 12),

          // If multiple images allowed, show thumbnails
          if (widget.config.maxImages > 1 && _selectedImages.isNotEmpty)
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final img = _selectedImages[idx];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(img,
                        width: 90, height: 90, fit: BoxFit.cover),
                  );
                },
              ),
            ),

          const SizedBox(height: 20),

          // ----- PICK BUTTONS -----
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImages(ImageSource.gallery),
                  icon: const Icon(Icons.photo),
                  label: Text(widget.config.maxImages > 1
                      ? "Pick from Gallery (up to ${widget.config.maxImages})"
                      : "Pick from Gallery"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurpleAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _pickImages(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text("Camera"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ----- PROMPT INPUT -----
          TextField(
            controller: _promptController,
            decoration: InputDecoration(
              hintText: "Describe how you'd like to edit this image...",
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
          ),

          const SizedBox(height: 20),

          // ----- UPSCALE TOGGLE -----
          SwitchListTile(
            title: const Text(
              "Upscale output image",
              style: TextStyle(color: Colors.white),
            ),
            value: _scaleImage,
            onChanged: (v) => setState(() => _scaleImage = v),
            activeThumbColor: Colors.deepPurpleAccent,
            contentPadding: EdgeInsets.zero,
          ),

          // ----- UPSCALE FACTOR -----
          if (_scaleImage)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text("2x"),
                  selected: _scaleFactor == 2,
                  onSelected: (_) => setState(() => _scaleFactor = 2),
                  selectedColor: Colors.deepPurpleAccent,
                  labelStyle: TextStyle(
                    color: _scaleFactor == 2 ? Colors.white : Colors.white70,
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text("4x"),
                  selected: _scaleFactor == 4,
                  onSelected: (_) => setState(() => _scaleFactor = 4),
                  selectedColor: Colors.deepPurpleAccent,
                  labelStyle: TextStyle(
                    color: _scaleFactor == 4 ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 30),

          // ----- GENERATE BUTTON -----
          ElevatedButton.icon(
            onPressed: _runEditJob,
            icon: const Icon(Icons.flash_on),
            label: Text("Generate with ${widget.config.title} ✨"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            "Show a fun tip while you wait",
            style: TextStyle(color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildResultScreen() {
    return Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.deepPurple, Colors.purpleAccent])),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Text("✨ Your AI Masterpiece is Ready!",
                  style: TextStyle(
                      fontSize: 22,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _resultImage != null
                    ? Image.memory(_resultImage!,
                        height: 360, fit: BoxFit.contain)
                    : const SizedBox(height: 360),
              ),
              const SizedBox(height: 25),
              ElevatedButton.icon(
                onPressed: () async {
                  final prefix = widget.config.model
                      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
                  await FileService.saveFile(context, _resultImage!);
                },
                icon: const Icon(Icons.download_rounded),
                label: const Text("Save Image"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _resultImage = null;
                    _selectedImages = [];
                    _promptController.clear();
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
    final paint = Paint()
      ..color =
          Color.lerp(Colors.deepPurpleAccent, Colors.amberAccent, progress)!
              .withOpacity(0.6);
    const int numSparkles = 20;
    final random = Random(progress.hashCode);
    for (int i = 0; i < numSparkles; i++) {
      final t = (progress + i / numSparkles) % 1.0;
      final dx =
          (size.width / numSparkles) * i + (random.nextDouble() * 30 - 15);
      final dy = size.height * (1 - t);
      final radius = (1.5 + random.nextDouble() * 2.5) * (1 - t);
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

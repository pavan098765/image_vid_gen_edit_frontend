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
class UpscaleConfig {
  final String title;
  final String model;

  const UpscaleConfig({
    required this.title,
    required this.model,
  });
}

// ---------------- MAIN PAGE ----------------
class UpscalePage extends StatefulWidget {
  final UpscaleConfig config;
  const UpscalePage({super.key, required this.config});

  @override
  State<UpscalePage> createState() => _UpscalePageState();
}

class _UpscalePageState extends State<UpscalePage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  Uint8List? _selectedImage;
  Uint8List? _resultImage;
  final picker = ImagePicker();

  bool _loading = false;
  bool _submittingJob = false;
  String? _activeJobId;
  Timer? _pollTimer;
  int _scaleFactor = 2;

  late AnimationController _pulseController;
  late AnimationController _sparkleController;
  late AnimationController _progressController;

  final Random _rand = Random();

  static const String baseUrl = "https://genedit.mooo.com";
  static const String controllerUrl = "https://genedit.mooo.com";
  static const String controllerApiKey = "SECRETKEY";
  static const String controllerSharedSecret = "SECRET";
  static const int pollIntervalSec = 10;
  static const int processingDurationSec = 120;

  final List<String> _loadingTexts = [
    "🚀 Enhancing resolution...",
    "✨ Sharpening details...",
    "🧠 Predicting lost pixels...",
    "🔍 Restoring texture and color...",
    "🎨 Cleaning up artifacts...",
    "🌟 Almost done upscaling...",
  ];

  final List<String> _funFacts = [
    "💡 Higher resolution boosts engagement by 40%.",
    "💡 Real-ESRGAN can recover fine hair details!",
    "💡 Swin2SR was inspired by Swin Transformers.",
    "💡 Aura SR V2 blends classical and neural upscaling.",
  ];

  final List<IconData> _loadingIcons = [
    Icons.auto_awesome,
    Icons.high_quality,
    Icons.bolt,
    Icons.upgrade,
    Icons.blur_on,
  ];

  int _loadingTextIndex = 0;
  int _iconIndex = 0;
  String _currentFact = "";

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
  void didUpdateWidget(covariant UpscalePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.model != widget.config.model) {
      debugPrint(
          "🔁 Model changed from ${oldWidget.config.model} to ${widget.config.model}");
      setState(() {
        _selectedImage=null;
        _resultImage = null;
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
    _pollTimer?.cancel();

    // 🧹 Cleanup saved images on exit
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove("upscale_image");
      prefs.remove("upscale_job_id");
      prefs.remove("pending_upscale_url");
    });
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

  // ---------------- RESTORE JOB ----------------
  Future<void> _restoreJobIfExists() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString("upscale_job_id");
    if (jobId == null) return;

    try {
      final savedImageBase64 = prefs.getString("upscale_image");
      if (savedImageBase64 != null) {
        _selectedImage = base64Decode(savedImageBase64);
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
        await prefs.remove("upscale_job_id");
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
        await prefs.remove("upscale_job_id");
      }
    } catch (e) {
      debugPrint("⚠️ Failed to restore job: $e");
      await prefs.remove("upscale_job_id");
    }
  }

  // ---------------- PICK IMAGE ----------------
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await picker.pickImage(source: source, imageQuality: 95);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() {
        _selectedImage = bytes;
        _resultImage = null;
      });
    } catch (e) {
      debugPrint("❌ Image pick failed: $e");
    }
  }

  // ---------------- UPSCALE ----------------
  Future<void> _runUpscale() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Select an image first.")));
      return;
    }

    setState(() {
      _loading = true;
      _loadingTextIndex = 0;
      _iconIndex = 0;
      _currentFact = _funFacts[_rand.nextInt(_funFacts.length)];
    });

    _progressController.forward(from: 0);
    _startTextRotation();
    _submittingJob = true;

    try {
      final base64Image = base64Encode(_selectedImage!);

      // ✅ Build params based on model type
      late final Map<String, dynamic> params;
      switch (widget.config.model) {
        case "aurasrv2":
          params = {
            "init_image": base64Image,
            "scale": _scaleFactor,
          };
          break;

        case "swin2sr":
          params = {
            "init_image": base64Image,
            "scale": _scaleFactor == 2 ? "swin2sr_x2" : "swin2sr_x4",
          };
          break;

        case "realesrgan":
          params = {
            "init_image": base64Image,
            "model_name": "RealESRGAN_x4plus",
            "outscale": _scaleFactor.toDouble(),
            "face_enhance": false,
            "tile": 0,
            "tile_pad": 10,
            "fp32": false,
          };
          break;

        default:
          throw Exception("Unknown upscaler model: ${widget.config.model}");
      }

      final payload = {
        "model": widget.config.model,
        "prompt": "",
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
        await prefs.setString("upscale_job_id", jobId);
        await prefs.setString("upscale_image", base64Image);
        if (downloadUrl != null) {
          await prefs.setString("pending_upscale_url", downloadUrl);
        }

        setState(() => _activeJobId = jobId);
        _submittingJob = false;
        _pollJobStatus();
      } else {
        throw Exception("Upscale failed (${response.statusCode})");
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _loading = false);
      _submittingJob = false;
    }
  }

  // ---------------- TEXT ROTATION ----------------
  void _startTextRotation() {
    Future(() async {
      while (_loading && mounted) {
        await Future.delayed(const Duration(seconds: 5));
        if (!_loading || !mounted) break;
        setState(() {
          _loadingTextIndex = (_loadingTextIndex + 1) % _loadingTexts.length;
          _iconIndex = (_iconIndex + 1) % _loadingIcons.length;
          _currentFact = _funFacts[_rand.nextInt(_funFacts.length)];
        });
      }
    });
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
            _fetchUpscaledImage(data);
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
  Future<void> _fetchUpscaledImage(Map<String, dynamic> jobData) async {
    try {
      String? downloadUrl = jobData['download_url'];
      if (downloadUrl == null) {
        final prefs = await SharedPreferences.getInstance();
        downloadUrl = prefs.getString("pending_upscale_url");
      }
      if (downloadUrl == null || downloadUrl.isEmpty) return;

      final resp = await http.get(Uri.parse(downloadUrl));
      final bytes = resp.bodyBytes;

      setState(() {
        _resultImage = bytes;
        _loading = false;
      });

      final prefs = await SharedPreferences.getInstance();
      prefs.remove("upscale_job_id");
      prefs.remove("pending_upscale_url");
      prefs.remove("upscale_image");

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
      _selectedImage = null;
      _resultImage = null;
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
                : _buildSelectionScreen()),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_selectedImage != null) ...[
          Image.memory(_selectedImage!, fit: BoxFit.cover),
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
                  _currentFact,
                  key: ValueKey<String>(_currentFact),
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

  Widget _buildSelectionScreen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          if (_selectedImage != null)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.memory(_selectedImage!, fit: BoxFit.contain),
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
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo),
                  label: const Text("Pick from Gallery"),
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
                onPressed: () => _pickImage(ImageSource.camera),
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
          const Text(
            "Upscale Factor",
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 10),
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
          ElevatedButton.icon(
            onPressed: _runUpscale,
            icon: const Icon(Icons.flash_on),
            label: Text("Upscale with ${widget.config.title} ✨"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
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
              const Text("✨ Your Upscaled Image is Ready!",
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
                  await FileService.saveFile(context, _resultImage!,
                      prefix: prefix);
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
                    _selectedImage = null;
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

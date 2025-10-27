import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class VideoGenPage extends StatefulWidget {
  const VideoGenPage({super.key});

  @override
  State<VideoGenPage> createState() => _VideoGenPageState();
}

class _VideoGenPageState extends State<VideoGenPage> {
  final TextEditingController _promptController = TextEditingController();
  bool _loading = false;
  Uint8List? _previewImage;
  String? _videoUrl;

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _previewImage = result.files.first.bytes);
    }
  }

  Future<void> _generateVideo({required bool fromImage}) async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a prompt")),
      );
      return;
    }

    setState(() {
      _loading = true;
      _videoUrl = null;
    });

    try {
      final body = {
        "model": "wan_2_1",
        "params": {
          "mode": fromImage ? "image_to_video" : "text_to_video",
          "prompt": prompt,
        },
      };

      if (fromImage && _previewImage != null) {
        body["init_image"] = base64Encode(_previewImage!);
      }

      final response = await http.post(
        Uri.parse('https://your-server-controller-domain/submit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() => _videoUrl = data['download_url']);
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed: $e")),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Video Generator (WAN 2.1)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                "Enter your prompt:",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _promptController,
                decoration: InputDecoration(
                  hintText: "A cinematic view of mountains at sunset...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                minLines: 1,
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Image Preview & Upload
              if (_previewImage != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_previewImage!, height: 200, fit: BoxFit.cover),
                ),
              TextButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: const Text("Upload Image (optional)"),
                onPressed: _pickImage,
              ),

              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loading ? null : () => _generateVideo(fromImage: false),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text("Generate Video from Text"),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _loading || _previewImage == null
                    ? null
                    : () => _generateVideo(fromImage: true),
                icon: const Icon(Icons.video_call_outlined),
                label: const Text("Generate Video from Image"),
              ),

              const SizedBox(height: 30),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_videoUrl != null)
                Column(
                  children: [
                    const Text("✅ Video Ready!", style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 10),
                    SelectableText(_videoUrl!, style: const TextStyle(color: Colors.blueAccent)),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_new),
                      label: const Text("Open Video"),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: _videoUrl!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Video URL copied to clipboard")),
                        );
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/music_video/music_video_page.dart';
import 'package:uuid/uuid.dart';

/// Studio entry for a song the user already has. No HitMaker task, so no
/// timed lyrics and no cloud render.
class StudioMusicVideoPage extends StatefulWidget {
  const StudioMusicVideoPage({super.key});

  @override
  State<StudioMusicVideoPage> createState() => _StudioMusicVideoPageState();
}

class _StudioMusicVideoPageState extends State<StudioMusicVideoPage> {
  final _title = TextEditingController();
  final _artist = TextEditingController();
  String? _audioPath;
  String? _coverPath;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  Future<void> _pickAudio() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'],
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    setState(() => _audioPath = path);
    if (_title.text.trim().isEmpty) {
      final name = path.split(RegExp(r'[\\/]')).last;
      final bare = name.replaceAll(RegExp(r'\.[^.]+$'), '').replaceAll('_', ' ').trim();
      if (bare.isNotEmpty) _title.text = bare;
    }
  }

  Future<void> _pickCover() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;
    setState(() => _coverPath = file.path);
  }

  void _continue() {
    final audio = _audioPath;
    if (audio == null || !File(audio).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose the song first.')),
      );
      return;
    }
    final title = _title.text.trim().isEmpty ? 'Music video' : _title.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MusicVideoPage(
          parentJobId: const Uuid().v4(),
          title: title,
          artist: _artist.text.trim().isEmpty ? 'Kala AI' : _artist.text.trim(),
          audioPath: audio,
          coverUrl: _coverPath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final audioName = _audioPath?.split(RegExp(r'[\\/]')).last;
    return Scaffold(
      appBar: AppBar(title: const Text('Music video')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            'Use a song you already have. Pick a style on the next screen.',
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.35),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _pickAudio,
            icon: const Icon(Icons.audio_file_outlined),
            label: Text(audioName ?? 'Choose song'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'Track name',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _artist,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Artist',
              hintText: 'Optional',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickCover,
            icon: const Icon(Icons.image_outlined),
            label: Text(_coverPath == null ? 'Cover image, optional' : 'Cover chosen'),
          ),
          if (_coverPath != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_coverPath!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Synced lyrics need a HitMaker song. A file from your phone is pictured without them.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _continue,
            child: const Text('Choose a style'),
          ),
        ],
      ),
    );
  }
}

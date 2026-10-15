import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/user_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/studio/studio_api.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/studio/studio_models.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/sign_in_prompt.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/studio/studio_job_page.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StudioPage extends StatefulWidget {
  final String? initialExploreJobId;
  final String? initialAssetKey;
  final String? initialLocalPath;
  final int? initialSceneIndex;

  const StudioPage({
    super.key,
    this.initialExploreJobId,
    this.initialAssetKey,
    this.initialLocalPath,
    this.initialSceneIndex,
  });

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _form = GlobalKey<FormState>();
  final _prefs = StudioPrefs(mode: 'from_topic');
  String _pipeline = 'auto';
  bool _reviewMode = true;
  bool _busy = false;
  final List<File> _localUploads = [];
  File? _reference;
  String? _error;

  int get _cost => studioCreditEstimate(
        durationSeconds: _prefs.durationSeconds,
        tier: _prefs.qualityTier,
        emitShorts: _prefs.emitShorts || _prefs.nativeShort,
      );

  List<String> get _voices =>
      kStudioVoicesByEngine[_prefs.ttsProvider] ?? kStudioVoicesByEngine['kokoro']!;

  @override
  void initState() {
    super.initState();
    _prefs.voiceId = _voices.first;
    final path = widget.initialLocalPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      _localUploads.add(File(path));
    }
  }

  Future<void> _pickFootage() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _localUploads.add(File(file.path)));
  }

  Future<void> _pickReference() async {
    final picker = ImagePicker();
    final file = await picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => _reference = File(file.path));
  }

  Future<void> _submit() async {
    final signedIn = await requireSignIn(context, feature: 'Studio');
    if (!signedIn || !mounted) return;
    if (!_form.currentState!.validate()) return;

    final needsFootage = kFootageRequiredPipelines.contains(_pipeline) ||
        _prefs.mode == 'from_footage';
    if (needsFootage &&
        _localUploads.isEmpty &&
        (widget.initialAssetKey == null || widget.initialAssetKey!.isEmpty)) {
      setState(() => _error = 'This mode needs footage. Upload a clip first.');
      return;
    }

    if (!UserService().hasEnoughCredits(_cost)) {
      setState(() => _error = 'Not enough credits ($_cost required).');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final assetKeys = <String>[
        if (widget.initialAssetKey != null && widget.initialAssetKey!.isNotEmpty)
          widget.initialAssetKey!,
      ];
      for (final file in _localUploads) {
        assetKeys.add(await StudioApi.instance.uploadFile(
          jobId: 'inbox',
          file: file,
        ));
      }
      if (_reference != null) {
        _prefs.referenceKey = await StudioApi.instance.uploadFile(
          jobId: 'inbox',
          file: _reference!,
        );
      }
      String? fcmToken;
      try {
        final sp = await SharedPreferences.getInstance();
        fcmToken = sp.getString('fcm_token') ??
            await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      final created = await StudioApi.instance.createJob(
        pipeline: _pipeline,
        prefs: _prefs,
        reviewMode: _reviewMode,
        assetKeys: assetKeys,
        fcmToken: fcmToken,
      );
      final jobId = created['job_id'] as String;

      await addOrUpdateJob(
        JobModel(
          jobId: jobId,
          title: _prefs.topic.isEmpty ? 'Studio' : _prefs.topic,
          model: 'studio',
          outputType: 'studio_video',
          status: mapStudioStatus((created['status'] ?? 'queued').toString()),
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => StudioJobPage(jobId: jobId, reviewMode: _reviewMode),
        ),
      );
    } on StudioApiException catch (e) {
      setState(() {
        _error = e.statusCode == 402
            ? 'Not enough credits. Studio uses the same gem wallet as Explore.'
            : e.message;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Studio')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text(
              'Topic-specific 1080p video. Draft can look similar; Studio/Hero must not.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _prefs.mode ?? 'from_topic',
              decoration: const InputDecoration(labelText: 'Mode'),
              items: const [
                DropdownMenuItem(
                    value: 'from_topic', child: Text('Create from idea')),
                DropdownMenuItem(
                    value: 'from_footage', child: Text('Edit my footage')),
                DropdownMenuItem(
                    value: 'from_evidence', child: Text('Documentary')),
                DropdownMenuItem(value: 'shorts', child: Text('Shorts')),
              ],
              onChanged: (v) => setState(() {
                _prefs.mode = v;
                _prefs.nativeShort = v == 'shorts';
                if (v == 'shorts') {
                  _prefs.platformProfile = '9:16';
                  _prefs.durationSeconds =
                      _prefs.durationSeconds.clamp(15, 60);
                }
                if (v == 'from_evidence') _prefs.realFootageOnly = true;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _prefs.qualityTier,
              decoration: const InputDecoration(labelText: 'Quality tier'),
              items: const [
                DropdownMenuItem(value: 'draft', child: Text('Draft')),
                DropdownMenuItem(value: 'studio', child: Text('Studio')),
                DropdownMenuItem(value: 'hero', child: Text('Hero')),
              ],
              onChanged: (v) =>
                  setState(() => _prefs.qualityTier = v ?? 'studio'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              decoration: const InputDecoration(
                labelText: 'Topic',
                hintText: 'What should this video be about?',
              ),
              onChanged: (v) => _prefs.topic = v,
              validator: (v) {
                if (kFootageRequiredPipelines.contains(_pipeline) ||
                    _prefs.mode == 'from_footage') {
                  return null;
                }
                if ((v ?? '').trim().isEmpty) return 'Topic is required';
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Duration: ${_prefs.durationSeconds}s (max ${_prefs.mode == 'shorts' ? 60 : 1200}s)',
            ),
            Slider(
              min: 5,
              max: _prefs.mode == 'shorts' ? 60 : 1200,
              divisions: _prefs.mode == 'shorts' ? 11 : 239,
              value: _prefs.durationSeconds
                  .clamp(5, _prefs.mode == 'shorts' ? 60 : 1200)
                  .toDouble(),
              label: '${_prefs.durationSeconds}s',
              onChanged: (v) =>
                  setState(() => _prefs.durationSeconds = v.round()),
            ),
            DropdownButtonFormField<String>(
              value: _prefs.platformProfile,
              decoration: const InputDecoration(labelText: 'Platform / aspect'),
              items: kStudioPlatforms
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) =>
                  setState(() => _prefs.platformProfile = v ?? '16:9'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _prefs.ttsProvider,
              decoration: const InputDecoration(labelText: 'Voice engine'),
              items: const [
                DropdownMenuItem(value: 'kokoro', child: Text('Kokoro (ONNX)')),
                DropdownMenuItem(value: 'piper', child: Text('Piper')),
                DropdownMenuItem(
                    value: 'elevenlabs', child: Text('ElevenLabs')),
              ],
              onChanged: (v) => setState(() {
                _prefs.ttsProvider = v ?? 'kokoro';
                _prefs.voiceId = _voices.first;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _voices.contains(_prefs.voiceId)
                  ? _prefs.voiceId
                  : _voices.first,
              decoration: const InputDecoration(labelText: 'Voice'),
              items: _voices
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _prefs.voiceId = v),
            ),
            SwitchListTile(
              title: const Text('Karaoke captions'),
              value: _prefs.karaoke,
              onChanged: (v) => setState(() {
                _prefs.karaoke = v;
                _prefs.captions = v || _prefs.captions;
              }),
            ),
            SwitchListTile(
              title: const Text('Also emit shorts pack'),
              value: _prefs.emitShorts,
              onChanged: (v) => setState(() => _prefs.emitShorts = v),
            ),
            SwitchListTile(
              title: const Text('Review scenes before stitch'),
              value: _reviewMode,
              onChanged: (v) => setState(() => _reviewMode = v),
            ),
            DropdownButtonFormField<String>(
              value: _prefs.deliveryPromise,
              decoration: const InputDecoration(labelText: 'Delivery promise'),
              items: const [
                DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                DropdownMenuItem(
                    value: 'motion_led', child: Text('Motion-led (no slideshow)')),
              ],
              onChanged: (v) =>
                  setState(() => _prefs.deliveryPromise = v ?? 'mixed'),
            ),
            ExpansionTile(
              title: const Text('Advanced'),
              children: [
                DropdownButtonFormField<String>(
                  value: _pipeline,
                  decoration: const InputDecoration(
                    labelText: 'Preset (compatibility)',
                    helperText: 'Prefer Mode on the happy path.',
                  ),
                  items: kStudioPipelines
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => _pipeline = v ?? 'auto'),
                ),
                DropdownButtonFormField<String?>(
                  value: _prefs.renderRuntime,
                  decoration: const InputDecoration(
                    labelText: 'Render runtime override',
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Auto')),
                    DropdownMenuItem(value: 'remotion', child: Text('Remotion')),
                    DropdownMenuItem(
                        value: 'hyperframes', child: Text('HyperFrames')),
                    DropdownMenuItem(value: 'ffmpeg', child: Text('FFmpeg')),
                    DropdownMenuItem(
                        value: 'motion_canvas', child: Text('Motion Canvas')),
                  ],
                  onChanged: (v) => setState(() => _prefs.renderRuntime = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickFootage,
              icon: const Icon(LucideIcons.upload),
              label: Text(
                _localUploads.isEmpty
                    ? 'Upload footage (required for Edit my footage)'
                    : '${_localUploads.length} file(s) selected',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickReference,
              icon: const Icon(LucideIcons.film),
              label: Text(
                _reference == null
                    ? 'Optional: upload a reference clip (structure only)'
                    : 'Reference selected',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: cs.error)),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Create video · $_cost gems'),
            ),
          ],
        ),
      ),
    );
  }
}

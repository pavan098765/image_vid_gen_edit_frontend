import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/cached_tool_config.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/tool_launch.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/user_template_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/image_editor/image_editor_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/save_size_sheet.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/video_editor_page.dart';

class JobNextActions extends StatefulWidget {
  final JobModel job;

  const JobNextActions({super.key, required this.job});

  @override
  State<JobNextActions> createState() => _JobNextActionsState();
}

class _JobNextActionsState extends State<JobNextActions> {
  Map<String, dynamic>? _config;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await loadCachedToolConfig();
    if (mounted) setState(() => _config = config);
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int? _cost(String capabilityId, {String? modelId, bool upscale = false}) {
    final config = _config;
    if (config == null) return null;
    return liveCapabilityCost(
      config,
      capabilityId,
      modelId: modelId,
      upscaleEnabled: upscale,
    );
  }

  bool _capEnabled(String id) {
    final config = _config;
    if (config == null) return false;
    final cap = capabilityById(config, id);
    return cap != null && capabilityHasEnabledModel(cap);
  }

  File? get _resultFile {
    final p = widget.job.localFilePath;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  File? get _sourceFile {
    final p = widget.job.inputImagePath;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  }

  String? get _prompt {
    final snap = widget.job.settingsSnapshot?['prompt'] as String?;
    if (snap != null && snap.trim().isNotEmpty) return snap;
    return widget.job.originalPrompt;
  }

  Future<void> _openCapability(
    String capabilityId, {
    List<String> paths = const [],
    String? prompt,
    Map<String, dynamic>? settings,
    bool emptyPrompt = false,
  }) async {
    final config = _config;
    if (config == null) return;
    final cap = capabilityById(config, capabilityId);
    if (cap == null || !capabilityHasEnabledModel(cap)) return;
    if (!mounted) return;
    await openGenericTool(
      context,
      config: genericConfigFromCapability(
        cap,
        preferredModelId: settings?['modelId'] as String? ?? widget.job.model,
      ),
      initialLocalPaths: paths,
      initialPrompt: prompt,
      initialSettings: settings,
      sourceJobId: widget.job.jobId,
      launchTemplateId: widget.job.templateId,
      launchTemplateTitle: widget.job.templateTitle,
      emptyPrompt: emptyPrompt,
    );
  }

  Future<void> _useAgain({required bool afterFailure}) async {
    final cost = _cost(
      widget.job.capabilityId ?? '',
      modelId: widget.job.model,
      upscale: widget.job.settingsSnapshot?['upscaleEnabled'] == true,
    );
    if (afterFailure && mounted && cost != null) {
      final go = await showModalBottomSheet<bool>(
        context: context,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'The failed attempt was refunded. This new one costs $cost credits.',
                    style: TextStyle(color: cs.onSurface, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          );
        },
      );
      if (go != true) return;
    }

    final capId = widget.job.capabilityId;
    if (capId == null || capId.isEmpty) {
      final resolved = await resolveRecipeLaunch(
        capabilityId: null,
        modelId: widget.job.model,
      );
      if (!mounted) return;
      if (resolved == null) {
        await showModelUnavailableDialog(context);
        return;
      }
      final source = _sourceFile;
      await openGenericTool(
        context,
        config: resolved.config,
        initialLocalPaths: source != null ? [source.path] : const [],
        initialPrompt: _prompt,
        initialSettings: widget.job.settingsSnapshot,
        sourceJobId: widget.job.jobId,
      );
      return;
    }

    if (!_capEnabled(capId)) {
      if (mounted) await showModelUnavailableDialog(context);
      return;
    }

    final isCreate = capId == 'create_image' || capId == 'create_video';
    final source = _sourceFile;
    await _openCapability(
      capId,
      paths: isCreate ? const [] : (source != null ? [source.path] : const []),
      prompt: _prompt,
      settings: widget.job.settingsSnapshot,
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final cs = Theme.of(context).colorScheme;
    final result = _resultFile;
    final expired = job.isCloudExpired && !job.isSavedLocally;

    if (job.status == 'failed') {
      final amount = job.creditsCharged;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              amount != null
                  ? "This didn't finish. $amount credits were returned."
                  : "This didn't finish. Failed jobs are refunded.",
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            if (_prompt != null || _sourceFile != null) ...[
              const SizedBox(height: 8),
              _chip(
                cs,
                label: job.creditsCharged != null
                    ? 'Try again · ${_cost(job.capabilityId ?? '', modelId: job.model) ?? '—'}'
                    : 'Try again',
                onTap: () => _guard(() => _useAgain(afterFailure: true)),
              ),
            ],
          ],
        ),
      );
    }

    if (job.status != 'completed') return const SizedBox.shrink();

    if (expired) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The cloud copy expired after 24 hours.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            if (_prompt != null || _sourceFile != null) ...[
              const SizedBox(height: 8),
              Text('New generation',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              const SizedBox(height: 6),
              _chip(
                cs,
                label:
                    'Use again · ${_cost(job.capabilityId ?? '', modelId: job.model) ?? '—'}',
                onTap: () => _guard(() => _useAgain(afterFailure: false)),
              ),
            ],
          ],
        ),
      );
    }

    if (result == null) return const SizedBox.shrink();

    final free = <Widget>[];
    final paid = <Widget>[];

    if (job.isImageOutput) {
      free.add(_chip(cs, label: 'Add text', onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditorPage(
              initialImage: result,
              initialTool: ImageEditorInitialTool.text,
              historyId: widget.job.jobId,
            ),
          ),
        );
      }));
      free.add(_chip(cs, label: 'Crop', onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditorPage(
              initialImage: result,
              initialTool: ImageEditorInitialTool.crop,
              historyId: widget.job.jobId,
            ),
          ),
        );
      }));
      free.add(_chip(cs, label: 'Save sizes', onTap: () {
        showSaveSizeSheet(context, result);
      }));
      free.add(_chip(cs, label: 'Use as sticker', onTap: () {
        _guard(_useAsSticker);
      }));
      free.add(_chip(cs, label: 'Place on video', onTap: () {
        _guard(_placeOnVideo);
      }));

      if (_capEnabled('upscale')) {
        final c = _cost('upscale');
        if (c != null) {
          paid.add(_chip(cs, label: 'Upscale · $c', onTap: () {
            _guard(() => _openCapability('upscale', paths: [result.path]));
          }));
        }
      }
      if (_capEnabled('remove_background')) {
        final c = _cost('remove_background');
        if (c != null) {
          paid.add(_chip(cs, label: 'Remove background · $c', onTap: () {
            _guard(() =>
                _openCapability('remove_background', paths: [result.path]));
          }));
        }
      }
      if (_capEnabled('animate_image')) {
        final c = _cost('animate_image');
        if (c != null) {
          paid.add(_chip(cs, label: 'Animate · $c', onTap: () {
            _guard(() => _openCapability('animate_image',
                paths: [result.path], prompt: ''));
          }));
        }
      }
      if (_capEnabled('edit_image')) {
        final c = _cost('edit_image');
        if (c != null) {
          paid.add(_chip(cs, label: 'Another style · $c', onTap: () {
            _guard(() => _openCapability(
                  'edit_image',
                  paths: [result.path],
                  emptyPrompt: true,
                ));
          }));
        }
      }
    } else if (job.isVideoOutput) {
      free.add(_chip(cs, label: 'Add text', onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoEditorPage(
              initialVideoPath: result.path,
              initialTool: VideoEditorInitialTool.text,
              jobId: widget.job.jobId,
            ),
          ),
        );
      }));
      free.add(_chip(cs, label: 'Open editor', onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VideoEditorPage(
              initialVideoPath: result.path,
              jobId: widget.job.jobId,
            ),
          ),
        );
      }));
      final source = _sourceFile;
      if (source != null &&
          pathLooksLikeImage(source.path) &&
          _capEnabled('edit_image')) {
        final c = _cost('edit_image');
        if (c != null) {
          paid.add(_chip(cs, label: 'Use the photo · $c', onTap: () {
            _guard(() => _openCapability('edit_image', paths: [source.path]));
          }));
        }
      }
    }

    final againCost = _cost(job.capabilityId ?? '', modelId: job.model);
    if (job.capabilityId != null || job.model.isNotEmpty) {
      paid.add(_chip(
        cs,
        label: againCost != null ? 'Use again · $againCost' : 'Use again',
        onTap: () => _guard(() => _useAgain(afterFailure: false)),
      ));
    }

    final canSaveSetup = _prompt != null && _prompt!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (free.isNotEmpty) ...[
            Text(
              'On this phone · 0 credits',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: free),
            const SizedBox(height: 12),
          ],
          if (paid.isNotEmpty) ...[
            Text(
              'New generation',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: paid),
          ],
          if (canSaveSetup)
            SizedBox(
              height: 44,
              child: TextButton(
                onPressed: _saveSetup,
                child: const Text('Save setup'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip(ColorScheme cs,
      {required String label, required VoidCallback onTap}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: ActionChip(
        label: Text(label),
        onPressed: _busy
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap();
              },
      ),
    );
  }

  Future<void> _useAsSticker() async {
    final sticker = _resultFile;
    if (sticker == null) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditorPage(
          initialImage: File(picked.path),
          stickerImage: sticker,
          initialTool: ImageEditorInitialTool.sticker,
        ),
      ),
    );
  }

  Future<void> _placeOnVideo() async {
    final sticker = _resultFile;
    if (sticker == null) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoEditorPage(initialStickerPath: sticker.path),
      ),
    );
  }

  Future<void> _saveSetup() async {
    final nameController = TextEditingController(
      text: widget.job.templateTitle ?? widget.job.title,
    );
    nameController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: nameController.text.length,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surface,
          title: Text('Save setup', style: TextStyle(color: cs.onSurface)),
          content: TextField(
            controller: nameController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || nameController.text.trim().isEmpty) return;
    await appendUserTemplateRecord(
      UserTemplateRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameController.text.trim(),
        prompt: _prompt ?? '',
        modelId: widget.job.model,
        capabilityId: widget.job.capabilityId,
        toolTitle: widget.job.templateTitle,
        settings: settingsFromJobSnapshot(widget.job.settingsSnapshot),
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Setup saved')),
    );
  }
}

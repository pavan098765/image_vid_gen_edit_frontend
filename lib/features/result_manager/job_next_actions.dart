import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/cached_tool_config.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/tool_launch.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/user_template_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/media_editor/editor_tab_launch.dart';

class JobNextActions extends StatefulWidget {
  final JobModel job;

  const JobNextActions({super.key, required this.job});

  @override
  State<JobNextActions> createState() => _JobNextActionsState();
}

class _JobNextActionsState extends State<JobNextActions> {
  Map<String, dynamic>? _config;
  bool _busy = false;
  bool _optionsOpen = false;

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
      await openGenericTool(
        context,
        config: resolved.config,
        initialLocalPaths: launchPathsFromJob(widget.job),
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

    await _openCapability(
      capId,
      paths: launchPathsFromJob(widget.job),
      prompt: _prompt,
      settings: widget.job.settingsSnapshot,
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final cs = Theme.of(context).colorScheme;
    final result = _resultFile;
    final expired = job.showsCloudExpiry;

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
                icon: Icons.refresh_rounded,
                label: 'Try again',
                detail: job.creditsCharged != null
                    ? '${_cost(job.capabilityId ?? '', modelId: job.model) ?? '—'} gems'
                    : null,
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
              widget.job.usesKieCloud
                  ? 'The cloud copy expired after 14 days on server then deleted.'
                  : 'The cloud copy expired after 14 days on server then deleted.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            if (_prompt != null || _sourceFile != null) ...[
              const SizedBox(height: 8),
              Text('New generation',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
              const SizedBox(height: 6),
              _chip(
                cs,
                icon: Icons.refresh_rounded,
                label: 'Regenerate',
                detail:
                    '${_cost(job.capabilityId ?? '', modelId: job.model) ?? '—'} gems',
                onTap: () => _guard(() => _useAgain(afterFailure: false)),
              ),
            ],
          ],
        ),
      );
    }

    if (result == null) return const SizedBox.shrink();

    final rows = <Widget>[];

    if (job.isImageOutput) {
      rows.add(_aiRow(
        cs,
        icon: Icons.edit_rounded,
        label: 'Edit in Editor',
        onTap: () => _openInEditorTab(image: result),
      ));

      if (_capEnabled('upscale')) {
        final c = _cost('upscale');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.hd_rounded, label: 'Upscale', detail: '$c gems', onTap: () {
            _guard(() => _openCapability('upscale', paths: [result.path]));
          }));
        }
      }
      if (_capEnabled('remove_background')) {
        final c = _cost('remove_background');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.auto_fix_high_rounded, label: 'Remove background', detail: '$c gems', onTap: () {
            _guard(() =>
                _openCapability('remove_background', paths: [result.path]));
          }));
        }
      }
      if (_capEnabled('animate_image')) {
        final c = _cost('animate_image');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.play_circle_outline_rounded, label: 'Animate', detail: '$c gems', onTap: () {
            _guard(() => _openCapability('animate_image',
                paths: [result.path], prompt: ''));
          }));
        }
      }
      if (_capEnabled('edit_image')) {
        final c = _cost('edit_image');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.palette_outlined, label: 'Another style', detail: '$c gems', onTap: () {
            _guard(() => _openCapability(
                  'edit_image',
                  paths: [result.path],
                  emptyPrompt: true,
                ));
          }));
        }
      }
    } else if (job.isVideoOutput) {
      rows.add(_aiRow(
        cs,
        icon: Icons.movie_creation_outlined,
        label: 'Edit in Editor',
        onTap: () => _openInEditorTab(videoPath: result.path),
      ));
      final source = _sourceFile;
      if (source != null &&
          pathLooksLikeImage(source.path) &&
          _capEnabled('edit_image')) {
        final c = _cost('edit_image');
        if (c != null) {
          rows.add(_aiRow(cs, icon: Icons.photo_outlined, label: 'Use the photo', detail: '$c gems', onTap: () {
            _guard(() => _openCapability('edit_image', paths: [source.path]));
          }));
        }
      }
    }

    final againCost = _cost(job.capabilityId ?? '', modelId: job.model);
    if (job.capabilityId != null || job.model.isNotEmpty) {
      rows.add(_aiRow(
        cs,
        icon: Icons.refresh_rounded,
        label: 'Regenerate',
        detail: againCost != null ? '$againCost gems' : null,
        onTap: () => _guard(() => _useAgain(afterFailure: false)),
      ));
    }

    final canSaveSetup = _prompt != null && _prompt!.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _optionsOpen = !_optionsOpen),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Next actions',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(
                      _optionsOpen
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_optionsOpen) ...[
            const SizedBox(height: 10),
            ...rows,
            if (canSaveSetup)
              TextButton(
                onPressed: _saveSetup,
                child: const Text('Save setup'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _aiRow(
    ColorScheme cs, {
    required String label,
    required VoidCallback onTap,
    required IconData icon,
    String? detail,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _busy
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (detail != null)
                  Text(
                    detail,
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(
    ColorScheme cs, {
    required String label,
    required VoidCallback onTap,
    IconData icon = Icons.arrow_forward_rounded,
    String? detail,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 0),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _busy
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  onTap();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  detail == null ? label : '$label · $detail',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openInEditorTab({File? image, String? videoPath}) {
    final previousTab = selectedIndexNotifier.value;
    requestEditorTabLaunch(
      image: image,
      videoPath: videoPath,
      historyId: widget.job.jobId,
      jobId: widget.job.jobId,
      returnToResultManager: true,
      restoreTabIndex: previousTab,
    );
    selectedIndexNotifier.value = AppTabs.editor;
    Navigator.of(context).popUntil((route) => route.isFirst);
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

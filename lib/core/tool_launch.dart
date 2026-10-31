import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/cached_tool_config.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/job_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/ai_tools_page.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/ai_tools/generic_tool_page.dart';

class RecipeLaunchResult {
  final GenericToolConfig config;
  final String? warning;

  const RecipeLaunchResult({required this.config, this.warning});
}

Future<RecipeLaunchResult?> resolveRecipeLaunch({
  required String? capabilityId,
  required String? modelId,
}) async {
  final config = await loadCachedToolConfig();
  if (config == null) return null;

  Map<String, dynamic>? cap;
  String? warning;
  if (capabilityId != null && capabilityId.isNotEmpty) {
    cap = capabilityById(config, capabilityId);
    if (cap != null && modelId != null && modelId.isNotEmpty) {
      final model = enabledModelById(cap, modelId);
      if (model == null || model['id'] != modelId) {
        return null;
      }
    }
  } else if (modelId != null && modelId.isNotEmpty) {
    cap = capabilityContainingModel(config, modelId);
  }

  if (cap == null || !capabilityHasEnabledModel(cap)) return null;
  return RecipeLaunchResult(
    config: genericConfigFromCapability(cap, preferredModelId: modelId),
    warning: warning,
  );
}

GenericToolConfig genericConfigFromCapability(
  Map<String, dynamic> capability, {
  String? preferredModelId,
}) {
  final allModelsJson = capability['models'] as List<dynamic>? ?? [];
  final enabledModelsJson = allModelsJson.where((m) {
    if (m is! Map) return false;
    final enabled = m['enabled'];
    return enabled == null || enabled == true;
  }).toList();
  final models = enabledModelsJson
      .map((m) => ModelOption.fromJson(Map<String, dynamic>.from(m as Map)))
      .toList();
  final defaultModelId =
      preferredModelId ?? capability['defaultModel'] as String?;
  final defaultModel = models.isNotEmpty
      ? models.firstWhere(
          (m) => m.id == defaultModelId,
          orElse: () => models.first,
        )
      : null;
  return GenericToolConfig(
    title: capability['name'] as String? ?? 'Tool',
    model: defaultModel?.id ?? defaultModelId ?? '',
    inputs: capability['inputs'] ?? [],
    params: defaultModel?.params,
    rootParams: defaultModel?.rootParams,
    elements: capability['elements'] ?? [],
    outputType: capability['outputType'] as String? ?? 'image',
    cost: defaultModel?.cost ?? 10,
    costUpscale: defaultModel?.costUpscale ?? 0,
    offer: (defaultModel?.rawJson['offer'] as num?)?.toInt() ?? 0,
    capabilityId: capability['id'] as String?,
    models: models.map((m) => m.toJson()).toList(),
    defaultModel: defaultModelId ?? '',
  );
}

Future<void> showModelUnavailableDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'This model is no longer available.',
          style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: TextStyle(color: cs.primary)),
          ),
        ],
      );
    },
  );
}

bool pathLooksLikeVideo(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mkv');
}

bool pathLooksLikeImage(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif');
}

List<String> existingMatchingPaths({
  required List<String> paths,
  required bool wantImages,
}) {
  return paths.where((p) {
    if (p.isEmpty || !File(p).existsSync()) return false;
    if (wantImages) {
      if (pathLooksLikeVideo(p)) return false;
      return pathLooksLikeImage(p) || !pathLooksLikeVideo(p);
    }
    return pathLooksLikeVideo(p);
  }).toList();
}

Future<void> openTemplateInTool(
  BuildContext context, {
  required Map<String, dynamic> template,
  required Map<String, dynamic>? capability,
}) async {
  if (capability == null) return;
  final modelId = template['model'] as String? ??
      template['preferred_model'] as String? ??
      capability['defaultModel'] as String?;
  final jobConfig = template['job_config'] as Map<String, dynamic>? ?? {};
  await openGenericTool(
    context,
    config: genericConfigFromCapability(
      Map<String, dynamic>.from(capability),
      preferredModelId: modelId,
    ),
    initialPrompt: jobConfig['prompt'] as String?,
    initialSettings: {
      'modelId': modelId,
      'aspectRatio': jobConfig['aspect_ratio'],
      'videoDuration': jobConfig['videoDuration'],
      'require_end_frame': template['require_end_frame'] == true,
    },
    launchTemplateId: template['id'] as String?,
    launchTemplateTitle: template['title'] as String?,
  );
}

String? _existingFile(String? path) {
  if (path == null || path.isEmpty) return null;
  return File(path).existsSync() ? path : null;
}

/// Every saved reference that still exists, then the original input, then
/// the result file when the job has no saved inputs.
List<String> launchPathsFromJob(JobModel job) {
  final paths = <String>[];
  void addPath(String? raw) {
    final ok = _existingFile(raw);
    if (ok != null && !paths.contains(ok)) paths.add(ok);
  }

  void walk(dynamic raw) {
    if (raw is String) {
      addPath(raw);
    } else if (raw is List) {
      for (final item in raw) {
        walk(item);
      }
    } else if (raw is Map) {
      for (final value in raw.values) {
        walk(value);
      }
    }
  }

  final snap = job.settingsSnapshot;
  walk(snap?['mediaPaths']);
  if (paths.isEmpty) walk(snap?['inputPaths']);
  final isCreate =
      job.capabilityId == 'create_image' || job.capabilityId == 'create_video';
  if (paths.isEmpty) addPath(job.inputImagePath);
  if (paths.isEmpty && !isCreate) addPath(job.localFilePath);
  return paths;
}

/// Reopens the tool that made [job], with the prompt, settings, and photos
/// the user already had.
Future<void> openJobForContinue(BuildContext context, JobModel job) async {
  final snapPrompt = job.settingsSnapshot?['prompt'] as String?;
  final prompt = (snapPrompt != null && snapPrompt.trim().isNotEmpty)
      ? snapPrompt
      : job.originalPrompt;
  final settings = job.settingsSnapshot;
  final paths = launchPathsFromJob(job);

  Future<void> launch(GenericToolConfig config, String? capabilityId) async {
    if (!context.mounted) return;
    await openGenericTool(
      context,
      config: config,
      initialLocalPaths: paths,
      initialPrompt: prompt,
      initialSettings: settings,
      sourceJobId: job.jobId,
      launchTemplateId: job.templateId,
      launchTemplateTitle: job.templateTitle,
    );
  }

  final capId = job.capabilityId;
  if (capId == null || capId.isEmpty) {
    final resolved = await resolveRecipeLaunch(
      capabilityId: null,
      modelId: job.model,
    );
    if (!context.mounted) return;
    if (resolved == null) {
      await showModelUnavailableDialog(context);
      return;
    }
    await launch(resolved.config, resolved.config.capabilityId);
    return;
  }

  final config = await loadCachedToolConfig();
  if (!context.mounted) return;
  final cap = config == null ? null : capabilityById(config, capId);
  if (cap == null || !capabilityHasEnabledModel(cap)) {
    await showModelUnavailableDialog(context);
    return;
  }
  await launch(
    genericConfigFromCapability(
      cap,
      preferredModelId: settings?['modelId'] as String? ?? job.model,
    ),
    capId,
  );
}

const Set<String> _musicModelIds = {
  'ace_step_music',
  'minimax_music_26',
  'suno_v6',
};

/// Opens Music with an existing track attached as a remix source.
Future<void> openMusicRemix(
  BuildContext context, {
  required String filePath,
  String? prompt,
  String? lyrics,
  String? modelId,
}) async {
  final preferred =
      modelId != null && _musicModelIds.contains(modelId) ? modelId : null;
  final resolved = await resolveRecipeLaunch(
    capabilityId: 'create_music',
    modelId: preferred,
  );
  if (!context.mounted) return;
  if (resolved == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Music is not available right now.')),
    );
    return;
  }
  await openGenericTool(
    context,
    config: resolved.config,
    initialLocalPaths: [filePath],
    initialPrompt: prompt,
    initialSettings: {
      if (prompt != null && prompt.isNotEmpty) 'prompt': prompt,
      'musicMode': 'easy',
      'trackMode': 'remix',
      if (lyrics != null && lyrics.isNotEmpty) 'lyrics': lyrics,
      if (preferred != null) 'modelId': preferred,
    },
  );
}

Future<void> openGenericTool(
  BuildContext context, {
  required GenericToolConfig config,
  List<String> initialLocalPaths = const [],
  String? initialPrompt,
  Map<String, dynamic>? initialSettings,
  String? sourceJobId,
  String? launchTemplateId,
  String? launchTemplateTitle,
  bool emptyPrompt = false,
  Future<String?>? pendingPrompt,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => GenericToolPage(
        config: config,
        initialLocalPaths: initialLocalPaths,
        initialPrompt: emptyPrompt ? '' : initialPrompt,
        initialSettings: initialSettings,
        sourceJobId: sourceJobId,
        launchTemplateId: launchTemplateId,
        launchTemplateTitle: launchTemplateTitle,
        focusPrompt: emptyPrompt,
        pendingPrompt: pendingPrompt,
      ),
    ),
  );
}

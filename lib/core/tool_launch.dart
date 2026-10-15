import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/cached_tool_config.dart';
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
      ),
    ),
  );
}

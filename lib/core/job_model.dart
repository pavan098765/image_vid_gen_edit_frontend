import 'dart:io';

/// Represents a single variation result from the backend
class VariationResult {
  final int variationIndex;
  final String status; // 'queued', 'running', 'completed', 'failed'
  final String? resultUrl;
  final String? error;
  String? localFilePath; // Local file path for saved variation

  VariationResult({
    required this.variationIndex,
    required this.status,
    this.resultUrl,
    this.error,
    this.localFilePath,
  });

  Map<String, dynamic> toJson() => {
        'variationIndex': variationIndex,
        'status': status,
        'resultUrl': resultUrl,
        'error': error,
        'localFilePath': localFilePath,
      };

  factory VariationResult.fromJson(Map<String, dynamic> json) {
    return VariationResult(
      variationIndex: json['variationIndex'] ?? json['variation_index'] ?? 0,
      status: json['status'] ?? 'queued',
      resultUrl: json['resultUrl'] ?? json['result_url'],
      error: json['error'],
      localFilePath: json['localFilePath'],
    );
  }

  bool get isCompleted => status == 'completed' && resultUrl != null;
  bool get isFailed => status == 'failed';
  bool get isSavedLocally =>
      localFilePath != null && File(localFilePath!).existsSync();
}

Map<String, dynamic>? _readSettingsSnapshot(dynamic raw) {
  if (raw is Map) {
    return sanitizeSettingsSnapshot(Map<String, dynamic>.from(raw));
  }
  return null;
}

/// Keep only the snapshot keys that are safe to persist on a job.
Map<String, dynamic> sanitizeSettingsSnapshot(Map<String, dynamic>? raw) {
  if (raw == null) return <String, dynamic>{};
  const keys = {
    'prompt',
    'modelId',
    'aspectRatio',
    'scaleFactor',
    'variations',
    'upscaleEnabled',
    'interpolateEnabled',
    'quality',
    'videoDuration',
    'enhancePrompt',
    'transparentBackground',
    'enableUpscale',
    'upscaleFactor',
    'interpolateFps',
    'loraAdapter',
    'cineRealMotionMode',
    'cfgScale',
    'bulkEditEnabled',
    'styleId',
    'inputPaths',
    'mediaPaths',
  };
  final out = <String, dynamic>{};
  for (final key in keys) {
    if (raw.containsKey(key) && raw[key] != null) {
      out[key] = raw[key];
    }
  }
  return out;
}

/// Represents an AI job (image/video generation, etc.)
class JobModel {
  final String jobId;
  final String title;
  final String model;
  final String outputType;
  String? downloadUrl;
  String status; // 'pending', 'processing', 'completed', 'failed'
  DateTime createdAt;
  String? localFilePath; // store preview/download file path
  String? inputImagePath;
  int? estimatedWaitSeconds;
  int? queuePosition;

  int variations; // Number of variations requested (1-4)
  List<VariationResult>? variationResults;
  bool allCompleted;

  String? enhancedPrompt;
  bool promptEnhanced;
  String? originalPrompt;

  String? templateId;
  String? templateTitle;
  String? capabilityId;
  Map<String, dynamic>? settingsSnapshot;
  int? creditsCharged;
  String? parentJobId;
  String? batchId;
  DateTime? readyAt;

  /// QuickPod results stay in the cloud for a day.
  static const Duration cloudLifetime = Duration(hours: 24);

  /// Kie download links last 20 minutes. Save the file at 17 minutes.
  static const Duration kieCloudLifetime = Duration(minutes: 20);
  static const Duration kieAutoSaveAfter = Duration(minutes: 17);

  static const Set<String> kieModels = {
    'qwen2_1_t2i',
    'qwen2_1_i2i',
    'grok_imagine_t2i',
    'grok_imagine_edit',
    'recraft_crisp_upscale',
    'recraft_remove_background',
    'gemini_tts',
    'suno_music',
    'suno_sfx',
  };

  JobModel({
    required this.jobId,
    required this.title,
    required this.model,
    required this.outputType,
    this.downloadUrl,
    this.status = 'processing',
    DateTime? createdAt,
    this.localFilePath,
    this.inputImagePath,
    this.estimatedWaitSeconds,
    this.queuePosition,
    this.variations = 1,
    this.variationResults,
    this.allCompleted = false,
    this.enhancedPrompt,
    this.promptEnhanced = false,
    this.originalPrompt,
    this.templateId,
    this.templateTitle,
    this.capabilityId,
    this.settingsSnapshot,
    this.creditsCharged,
    this.parentJobId,
    this.batchId,
    this.readyAt,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get usesKieCloud => kieModels.contains(model);

  DateTime get cloudReadyAt => readyAt ?? createdAt;

  Duration get resultLifetime => usesKieCloud ? kieCloudLifetime : cloudLifetime;

  void stampCloudReady() {
    if (status == 'completed' && readyAt == null) {
      readyAt = DateTime.now();
    }
  }

  bool get isCloudExpired {
    return DateTime.now().difference(cloudReadyAt) >= resultLifetime;
  }

  bool get isSavedLocally {
    if (localFilePath == null || localFilePath!.isEmpty) return false;
    return File(localFilePath!).existsSync();
  }

  Duration get timeUntilExpiry {
    final expiryTime = cloudReadyAt.add(resultLifetime);
    final remaining = expiryTime.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Kie results that are still only in the cloud after 17 minutes.
  bool get shouldAutoSave {
    if (!usesKieCloud || status != 'completed' || isSavedLocally) return false;
    if (isCloudExpired) return false;
    return DateTime.now().difference(cloudReadyAt) >= kieAutoSaveAfter;
  }

  String get expiryTimeFormatted {
    final remaining = timeUntilExpiry;
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes % 60}m';
    } else if (remaining.inMinutes > 0) {
      return '${remaining.inMinutes}m';
    } else if (remaining.inSeconds > 0) {
      return '${remaining.inSeconds}s';
    } else {
      return 'Expired';
    }
  }

  bool get isImageOutput {
    final t = outputType.toLowerCase();
    return t == 'image' || t == 'img' || t == 'png' || t == 'jpg';
  }

  bool get isVideoOutput {
    final t = outputType.toLowerCase();
    return t == 'video' || t == 'studio_video' || t == 'mp4';
  }

  /// Unsaved completed results with under 6 hours of cloud life left.
  String? get expiryCue {
    if (status != 'completed' || isSavedLocally) return null;
    if (timeUntilExpiry >= const Duration(hours: 6)) return null;
    return 'Save to keep it · $expiryTimeFormatted left';
  }

  bool get expiryCueUrgent {
    if (expiryCue == null) return false;
    if (usesKieCloud) return timeUntilExpiry < const Duration(minutes: 5);
    return timeUntilExpiry < const Duration(hours: 2);
  }

  /// Keeps launch details when a status update arrives with a thinner record.
  JobModel mergePreservingLaunch(JobModel other) {
    return copyWith(
      localFilePath: other.localFilePath ?? localFilePath,
      inputImagePath: other.inputImagePath ?? inputImagePath,
      originalPrompt: originalPrompt ?? other.originalPrompt,
      enhancedPrompt: enhancedPrompt ?? other.enhancedPrompt,
      capabilityId: capabilityId ?? other.capabilityId,
      templateId: templateId ?? other.templateId,
      templateTitle: templateTitle ?? other.templateTitle,
      settingsSnapshot: settingsSnapshot ?? other.settingsSnapshot,
      creditsCharged: creditsCharged ?? other.creditsCharged,
      parentJobId: parentJobId ?? other.parentJobId,
      batchId: batchId ?? other.batchId,
      readyAt: readyAt ?? other.readyAt,
    );
  }

  JobModel copyWith({
    String? jobId,
    String? title,
    String? model,
    String? outputType,
    String? downloadUrl,
    String? status,
    DateTime? createdAt,
    String? localFilePath,
    String? inputImagePath,
    int? estimatedWaitSeconds,
    int? queuePosition,
    int? variations,
    List<VariationResult>? variationResults,
    bool? allCompleted,
    String? enhancedPrompt,
    bool? promptEnhanced,
    String? originalPrompt,
    String? templateId,
    String? templateTitle,
    String? capabilityId,
    Map<String, dynamic>? settingsSnapshot,
    int? creditsCharged,
    String? parentJobId,
    String? batchId,
    DateTime? readyAt,
  }) {
    return JobModel(
      jobId: jobId ?? this.jobId,
      title: title ?? this.title,
      model: model ?? this.model,
      outputType: outputType ?? this.outputType,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      localFilePath: localFilePath ?? this.localFilePath,
      inputImagePath: inputImagePath ?? this.inputImagePath,
      estimatedWaitSeconds: estimatedWaitSeconds ?? this.estimatedWaitSeconds,
      queuePosition: queuePosition ?? this.queuePosition,
      variations: variations ?? this.variations,
      variationResults: variationResults ?? this.variationResults,
      allCompleted: allCompleted ?? this.allCompleted,
      enhancedPrompt: enhancedPrompt ?? this.enhancedPrompt,
      promptEnhanced: promptEnhanced ?? this.promptEnhanced,
      originalPrompt: originalPrompt ?? this.originalPrompt,
      templateId: templateId ?? this.templateId,
      templateTitle: templateTitle ?? this.templateTitle,
      capabilityId: capabilityId ?? this.capabilityId,
      settingsSnapshot: settingsSnapshot ?? this.settingsSnapshot,
      creditsCharged: creditsCharged ?? this.creditsCharged,
      parentJobId: parentJobId ?? this.parentJobId,
      batchId: batchId ?? this.batchId,
      readyAt: readyAt ?? this.readyAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'title': title,
        'model': model,
        'outputType': outputType,
        'downloadUrl': downloadUrl,
        'status': status,
        'createdAt': createdAt.toIso8601String(),
        'localFilePath': localFilePath,
        'inputImagePath': inputImagePath,
        'estimatedWaitSeconds': estimatedWaitSeconds,
        'queuePosition': queuePosition,
        'variations': variations,
        'variationResults': variationResults?.map((v) => v.toJson()).toList(),
        'allCompleted': allCompleted,
        'enhancedPrompt': enhancedPrompt,
        'promptEnhanced': promptEnhanced,
        'originalPrompt': originalPrompt,
        'templateId': templateId,
        'templateTitle': templateTitle,
        'capabilityId': capabilityId,
        'settingsSnapshot': settingsSnapshot,
        'creditsCharged': creditsCharged,
        'parentJobId': parentJobId,
        'batchId': batchId,
        'readyAt': readyAt?.toIso8601String(),
      };

  factory JobModel.fromJson(Map<String, dynamic> json) {
    String rawStatus =
        (json['status'] ?? 'processing').toString().toLowerCase();
    const allowed = [
      'processing',
      'completed',
      'failed',
      'reviewing',
      'provisioning',
      'queued',
      'running',
      'stitching',
      'uploading',
    ];
    if (!allowed.contains(rawStatus)) {
      if (rawStatus == 'done') {
        rawStatus = 'completed';
      } else if (rawStatus == 'review') {
        rawStatus = 'reviewing';
      } else {
        rawStatus = 'processing';
      }
    }

    List<VariationResult>? variationResults;
    if (json['variationResults'] != null || json['variation_results'] != null) {
      final resultsList = json['variationResults'] ?? json['variation_results'];
      if (resultsList is List) {
        variationResults = resultsList
            .map((v) => VariationResult.fromJson(Map<String, dynamic>.from(v)))
            .toList();
      }
    }

    return JobModel(
      jobId: json['jobId'] ?? json['job_id'],
      title: json['title'] ?? 'Untitled',
      model: json['model'] ?? 'unknown',
      outputType: json['outputType'] ?? json['output_type'] ?? 'image',
      downloadUrl: json['downloadUrl'] ?? json['download_url'],
      status: rawStatus,
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? json['created_at'] ?? '') ??
              DateTime.now(),
      localFilePath: json['localFilePath'],
      inputImagePath: json['inputImagePath'] as String?,
      estimatedWaitSeconds: (json['estimatedWaitSeconds'] ??
              json['estimated_wait_seconds']) is num
          ? (json['estimatedWaitSeconds'] ?? json['estimated_wait_seconds'])
              .toInt()
          : null,
      queuePosition: (json['queuePosition'] ?? json['queue_position']) is num
          ? (json['queuePosition'] ?? json['queue_position']).toInt()
          : null,
      variations: json['variations'] ?? 1,
      variationResults: variationResults,
      allCompleted: json['allCompleted'] ?? json['all_completed'] ?? false,
      enhancedPrompt: json['enhancedPrompt'] ?? json['enhanced_prompt'],
      promptEnhanced:
          json['promptEnhanced'] ?? json['prompt_enhanced'] ?? false,
      originalPrompt: json['originalPrompt'] ?? json['original_prompt'],
      templateId: json['templateId'] ?? json['template_id'],
      templateTitle: json['templateTitle'] ?? json['template_title'],
      capabilityId: json['capabilityId'] ?? json['capability_id'],
      settingsSnapshot: _readSettingsSnapshot(
          json['settingsSnapshot'] ?? json['settings_snapshot']),
      creditsCharged: (json['creditsCharged'] ?? json['credits_charged']) is num
          ? (json['creditsCharged'] ?? json['credits_charged']).toInt()
          : null,
      parentJobId: json['parentJobId'] ?? json['parent_job_id'],
      batchId: json['batchId'] ?? json['batch_id'],
      readyAt: DateTime.tryParse(json['readyAt']?.toString() ?? ''),
    );
  }

  int get successfulVariationsCount {
    if (variationResults == null || variationResults!.isEmpty) {
      return status == 'completed' ? 1 : 0;
    }
    return variationResults!.where((v) => v.isCompleted).length;
  }

  int get failedVariationsCount {
    if (variationResults == null || variationResults!.isEmpty) {
      return status == 'failed' ? 1 : 0;
    }
    return variationResults!.where((v) => v.isFailed).length;
  }

  bool get hasMultipleVariations => variations > 1;

  List<String> get allSuccessfulUrls {
    if (variationResults == null || variationResults!.isEmpty) {
      return downloadUrl != null ? [downloadUrl!] : [];
    }
    return variationResults!
        .where((v) => v.isCompleted && v.resultUrl != null)
        .map((v) => v.resultUrl!)
        .toList();
  }
}

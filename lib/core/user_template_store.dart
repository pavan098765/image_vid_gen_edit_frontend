import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const kUserTemplatesPrefsKey = 'user_templates';

class UserTemplateRecord {
  final String id;
  final String name;
  final String prompt;
  final String? modelId;
  final String? capabilityId;
  final String? toolTitle;
  final Map<String, dynamic> settings;
  final DateTime createdAt;
  final DateTime? lastUsed;

  UserTemplateRecord({
    required this.id,
    required this.name,
    required this.prompt,
    this.modelId,
    this.capabilityId,
    this.toolTitle,
    required this.settings,
    required this.createdAt,
    this.lastUsed,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'prompt': prompt,
        'modelId': modelId,
        'capabilityId': capabilityId,
        'toolTitle': toolTitle,
        'settings': settings,
        'createdAt': createdAt.toIso8601String(),
        'lastUsed': lastUsed?.toIso8601String(),
      };

  factory UserTemplateRecord.fromJson(Map<String, dynamic> json) {
    return UserTemplateRecord(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Setup',
      prompt: json['prompt'] as String? ?? '',
      modelId: json['modelId'] as String?,
      capabilityId: json['capabilityId'] as String?,
      toolTitle: json['toolTitle'] as String?,
      settings: json['settings'] is Map
          ? Map<String, dynamic>.from(json['settings'] as Map)
          : <String, dynamic>{},
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      lastUsed: json['lastUsed'] != null
          ? DateTime.tryParse(json['lastUsed'] as String)
          : null,
    );
  }
}

Future<List<UserTemplateRecord>> loadUserTemplateRecords() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kUserTemplatesPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final list = decoded
        .whereType<Map>()
        .map((e) => UserTemplateRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    list.sort((a, b) {
      if (a.lastUsed != null && b.lastUsed != null) {
        return b.lastUsed!.compareTo(a.lastUsed!);
      }
      if (a.lastUsed != null) return -1;
      if (b.lastUsed != null) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  } catch (_) {
    return [];
  }
}

const _dismissedContinueJobsKey = 'explore_dismissed_continue_jobs';

Future<Set<String>> loadDismissedContinueJobIds() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_dismissedContinueJobsKey)?.toSet() ?? {};
  } catch (_) {
    return {};
  }
}

/// Hides a job from Explore "Continue creating" without deleting the result.
Future<void> dismissContinueJob(String jobId) async {
  final prefs = await SharedPreferences.getInstance();
  final ids = prefs.getStringList(_dismissedContinueJobsKey)?.toList() ?? [];
  if (!ids.contains(jobId)) ids.add(jobId);
  final trimmed = ids.length > 200 ? ids.sublist(ids.length - 200) : ids;
  await prefs.setStringList(_dismissedContinueJobsKey, trimmed);
}

Future<void> deleteUserTemplateRecord(String id) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = await loadUserTemplateRecords();
  existing.removeWhere((record) => record.id == id);
  await prefs.setString(
    kUserTemplatesPrefsKey,
    jsonEncode(existing.map((e) => e.toJson()).toList()),
  );
}

Future<void> appendUserTemplateRecord(UserTemplateRecord record) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = await loadUserTemplateRecords();
  existing.insert(0, record);
  await prefs.setString(
    kUserTemplatesPrefsKey,
    jsonEncode(existing.map((e) => e.toJson()).toList()),
  );
}

Map<String, dynamic> settingsFromJobSnapshot(Map<String, dynamic>? snapshot) {
  final s = snapshot ?? const <String, dynamic>{};
  int asInt(dynamic value, int fallback) =>
      value is num ? value.toInt() : fallback;
  double asDouble(dynamic value, double fallback) =>
      value is num ? value.toDouble() : fallback;
  return {
    'enhancePrompt': s['enhancePrompt'] == true,
    'upscaleOutput': s['upscaleEnabled'] == true,
    'quality': s['quality'] as String? ?? 'High',
    'aspectRatio': s['aspectRatio'] as String? ?? '1:1',
    'variations': asInt(s['variations'], 1),
    'videoDuration': asInt(s['videoDuration'], 5),
    'cfgScale': asDouble(s['cfgScale'], 1.0),
    'bulkEditEnabled': s['bulkEditEnabled'] == true,
    'enableInterpolate': s['interpolateEnabled'] == true,
    'interpolateFps': asInt(s['interpolateFps'], 2),
    'enableUpscale':
        s['enableUpscale'] == true || s['upscaleEnabled'] == true,
    'upscaleFactor': asInt(s['upscaleFactor'] ?? s['scaleFactor'], 2),
    'loraAdapter': s['loraAdapter'] as String? ?? 'None',
    'cineRealMotionMode': s['cineRealMotionMode'] as String? ?? 'i2v',
  };
}

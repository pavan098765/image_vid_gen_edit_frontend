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
  return {
    'enhancePrompt': false,
    'upscaleOutput': s['upscaleEnabled'] == true,
    'quality': s['quality'] as String? ?? 'High',
    'aspectRatio': s['aspectRatio'] as String? ?? '1:1',
    'variations': 1,
    'videoDuration': s['videoDuration'] as int? ?? 5,
    'cfgScale': 1.0,
    'bulkEditEnabled': false,
    'enableInterpolate': s['interpolateEnabled'] == true,
    'interpolateFps': 2,
    'enableUpscale': s['upscaleEnabled'] == true,
    'upscaleFactor': (s['scaleFactor'] as num?)?.toInt() ?? 2,
    'loraAdapter': 'None',
    'cineRealMotionMode': 'i2v',
  };
}

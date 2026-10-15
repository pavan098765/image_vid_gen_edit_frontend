const String kStudioBaseUrl = 'https://genedit.mooo.com';

const List<String> kStudioModes = [
  'from_topic',
  'from_footage',
  'from_evidence',
  'shorts',
];

const List<String> kStudioPipelines = [
  'auto',
  'animated-explainer',
  'animation',
  'character-animation',
  'clip-factory',
  'documentary-montage',
  'hybrid',
  'podcast-repurpose',
  'screen-demo',
  'talking-head',
  'shorts',
];

const List<String> kFootageRequiredPipelines = [
  'talking-head',
  'clip-factory',
  'hybrid',
  'podcast-repurpose',
];

const List<String> kStudioPlatforms = ['16:9', '9:16', '1:1', '21:9'];

const List<String> kStudioTiers = ['draft', 'studio', 'hero'];

const List<String> kTtsProviders = ['kokoro', 'piper', 'elevenlabs'];

const Map<String, List<String>> kStudioVoicesByEngine = {
  'kokoro': ['af_heart', 'am_michael', 'bf_emma', 'bm_george'],
  'piper': ['en_US-lessac-medium', 'en_US-amy-medium', 'en_GB-alan-medium'],
  'elevenlabs': ['Rachel', 'Adam', 'Elli'],
};

int studioCreditEstimate({
  required int durationSeconds,
  required String tier,
  required bool emitShorts,
}) {
  final minutes = ((durationSeconds + 59) ~/ 60).clamp(1, 20);
  const perMin = {'draft': 8, 'studio': 15, 'hero': 28};
  final extra = emitShorts ? 10 : 0;
  final total = minutes * (perMin[tier] ?? 15) + extra;
  return total < 10 ? 10 : total;
}

const List<String> kStudioJobStatuses = [
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

String mapStudioStatus(String raw) {
  final s = raw.toLowerCase();
  switch (s) {
    case 'done':
      return 'completed';
    case 'review':
      return 'reviewing';
    case 'pending':
      return 'queued';
    case 'dispatching':
      return 'provisioning';
    default:
      return kStudioJobStatuses.contains(s) ? s : 'processing';
  }
}

class StudioPrefs {
  String topic;
  String audience;
  int durationSeconds;
  String language;
  String platformProfile;
  String stylePlaybook;
  String? voiceId;
  String ttsProvider;
  bool captions;
  bool karaoke;
  bool music;
  bool realFootageOnly;
  double budgetCapUsd;
  String deliveryPromise;
  String? renderRuntime;
  bool talking;
  bool longVideo;
  String qualityTier;
  bool emitShorts;
  bool nativeShort;
  String? referenceKey;
  String? mode;

  StudioPrefs({
    this.topic = '',
    this.audience = '',
    this.durationSeconds = 30,
    this.language = 'en',
    this.platformProfile = '16:9',
    this.stylePlaybook = 'clean-professional',
    this.voiceId,
    this.ttsProvider = 'kokoro',
    this.captions = true,
    this.karaoke = true,
    this.music = true,
    this.realFootageOnly = false,
    this.budgetCapUsd = 2.0,
    this.deliveryPromise = 'mixed',
    this.renderRuntime,
    this.talking = false,
    this.longVideo = false,
    this.qualityTier = 'studio',
    this.emitShorts = false,
    this.nativeShort = false,
    this.referenceKey,
    this.mode,
  });

  Map<String, dynamic> toJson() => {
        'topic': topic,
        'audience': audience.isEmpty ? null : audience,
        'duration_seconds': durationSeconds.clamp(5, 1200),
        'language': language,
        'platform_profile': platformProfile,
        'style_playbook': stylePlaybook,
        'voice_id': voiceId,
        'tts_provider': ttsProvider,
        'captions': captions,
        'karaoke': karaoke,
        'music': music,
        'real_footage_only': realFootageOnly,
        'budget_cap_usd': budgetCapUsd,
        'delivery_promise': deliveryPromise,
        'render_runtime': renderRuntime,
        'talking': talking,
        'long_video': longVideo,
        'quality_tier': qualityTier,
        'emit_shorts': emitShorts,
        'native_short': nativeShort,
        'reference_key': referenceKey,
        'mode': mode,
      };
}

class StudioScene {
  final String id;
  final String? scriptLine;
  final double? duration;
  final bool approved;
  final String? posterUrl;
  final String? previewUrl;
  final String? replaceR2Key;

  StudioScene({
    required this.id,
    this.scriptLine,
    this.duration,
    this.approved = false,
    this.posterUrl,
    this.previewUrl,
    this.replaceR2Key,
  });

  factory StudioScene.fromJson(Map<String, dynamic> json) {
    return StudioScene(
      id: (json['id'] ?? '').toString(),
      scriptLine: json['script_line'] as String?,
      duration: (json['duration'] is num)
          ? (json['duration'] as num).toDouble()
          : null,
      approved: json['approved'] == true,
      posterUrl: json['poster_url'] as String?,
      previewUrl: json['preview_url'] as String?,
      replaceR2Key: json['replace_r2_key'] as String?,
    );
  }
}

class StudioStoryboard {
  final String jobId;
  final List<StudioScene> scenes;
  final String composeStrategy;

  StudioStoryboard({
    required this.jobId,
    required this.scenes,
    this.composeStrategy = 'single_runtime',
  });

  factory StudioStoryboard.fromJson(Map<String, dynamic> json) {
    final scenes = (json['scenes'] as List? ?? [])
        .whereType<Map>()
        .map((e) => StudioScene.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return StudioStoryboard(
      jobId: (json['job_id'] ?? '').toString(),
      scenes: scenes,
      composeStrategy: (json['compose_strategy'] ?? 'single_runtime').toString(),
    );
  }

  bool get allApproved =>
      scenes.isNotEmpty && scenes.every((s) => s.approved);
}

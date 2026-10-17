import 'workflow_models.dart';
import 'workflow_rules.dart';

class CostTable {
  final int imageCost;
  final int h3Base5;
  final int ltxBase5;
  final int speechCost;
  final int musicCost;
  final int sfxCost;

  const CostTable({
    this.imageCost = 18,
    this.h3Base5 = 35,
    this.ltxBase5 = 35,
    this.speechCost = 12,
    this.musicCost = 15,
    this.sfxCost = 8,
  });

  factory CostTable.fromModelCosts(Map<String, dynamic> models) {
    int cost(String id, int fallback) {
      final raw = models[id];
      if (raw is Map && raw['cost'] is num) return (raw['cost'] as num).round();
      return fallback;
    }

    int base5(String id, int fallback) {
      final raw = models[id];
      if (raw is Map) {
        final b = raw['baseCost5Sec'] ?? raw['cost'];
        if (b is num && b > 0) return b.round();
      }
      return fallback;
    }

    return CostTable(
      imageCost: cost('qwen2_1_t2i', 18),
      h3Base5: base5('minimax_h3', 35),
      ltxBase5: base5('ltx25_int8_t2v', 35),
      speechCost: cost('gemini_tts', 12),
      musicCost: cost('suno_music', 15),
      sfxCost: cost('suno_sfx', 8),
    );
  }
}

class QuoteLine {
  final String label;
  final int gems;
  const QuoteLine(this.label, this.gems);
}

class FilmQuote {
  final List<QuoteLine> lines;
  const FilmQuote(this.lines);
  int get total => lines.fold(0, (sum, line) => sum + line.gems);
}

int videoGems(int base5, int seconds) {
  final d = seconds.clamp(1, 20);
  return ((base5 * d) / 5).round();
}

FilmQuote priceFilm({
  required List<ShotCard> shots,
  required CostTable costs,
  required int speechTasks,
  required bool music,
  required int musicBeds,
  required int sfxCount,
  int lookGems = 0,
  String lookLabel = 'Look',
}) {
    var picture = 0;
    var keyframes = 0;
    for (final shot in shots) {
      if (shot.dropped || shot.kind == 'user') continue;
      if (shot.kind == 'video') {
        final base = shot.model.startsWith('ltx') ? costs.ltxBase5 : costs.h3Base5;
        picture += videoGems(base, shot.durationSeconds) * renderMultiplier(shot.quality);
        if (shot.makeKeyframe) keyframes += costs.imageCost;
      } else {
        picture += costs.imageCost;
      }
    }
    final lines = <QuoteLine>[
      if (lookGems > 0) QuoteLine(lookLabel, lookGems),
      if (picture > 0) QuoteLine('Picture', picture),
      if (keyframes > 0) QuoteLine('Keyframes', keyframes),
    if (speechTasks > 0) QuoteLine('Voice', speechTasks * costs.speechCost),
    if (music && musicBeds > 0) QuoteLine('Music', musicBeds * costs.musicCost),
    if (sfxCount > 0) QuoteLine('Sting', sfxCount * costs.sfxCost),
  ];
  return FilmQuote(lines);
}

int renderMultiplier(String quality) {
  switch (quality) {
    case 'fast_refine':
      return 2;
    case 'full_refine':
      return 4;
    default:
      return 1;
  }
}

int speechTaskCount(WorkflowSpec spec, FilmDraft draft) {
  if (spec.speech == 'none') return 0;
  if (spec.speech == 'optional' && !draft.narratorOn) return 0;
  final chapters = draft.shots
      .where((s) => !s.dropped && s.line.trim().isNotEmpty && isNarrationLine(s))
      .map((s) => s.chapter)
      .toSet();
  if (chapters.isEmpty) return spec.speech == 'optional' ? 0 : 1;
  return chapters.length;
}

int musicBedCount(int durationSeconds, bool music) {
  if (!music) return 0;
  return durationSeconds > 360 ? 2 : 1;
}

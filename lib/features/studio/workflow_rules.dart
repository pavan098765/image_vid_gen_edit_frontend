import 'workflow_models.dart';

class RuleFailure implements Exception {
  final List<String> reasons;
  RuleFailure(this.reasons);
  @override
  String toString() => reasons.join(' ');
}

const _vague = ['throughout history', 'many people', "in today's world"];

/// Spoken line must never be copied into a clip prompt when a speech track exists.
String worldVideoPrompt({
  required String lock,
  required String action,
  required String sound,
  required bool speechTrack,
  String reference = '',
}) {
  final gate = speechTrack ? 'No speech. No music.' : 'No music.';
  return [lock.trim(), reference.trim(), action.trim(), 'Sound: ${sound.trim()}', gate]
      .where((s) => s.isNotEmpty)
      .join('\n');
}

List<String> checkResearch(
  Map<String, dynamic> research, {
  required int minFindings,
  bool full = true,
}) {
  final findings = (research['findings'] as List?) ?? const [];
  final reasons = <String>[];
  if (findings.length < minFindings) {
    reasons.add('Research needs at least $minFindings findings.');
  }
  var disagreements = 0;
  for (final raw in findings) {
    if (raw is! Map) {
      reasons.add('A finding is missing its source.');
      continue;
    }
    final fact = (raw['fact'] as String?) ?? '';
    final url = (raw['url'] as String?) ?? '';
    if (!url.startsWith('http')) reasons.add('A finding has no source link.');
    final lower = fact.toLowerCase();
    if (_vague.any(lower.contains)) {
      reasons.add('Replace a vague line with a specific fact.');
    }
    if (raw['disagrees'] == true) disagreements++;
  }
  if (full && disagreements < 2) {
    reasons.add('Include two findings that disagree.');
  }
  return reasons;
}

List<String> checkHook(List<ShotCard> shots) {
  final live = shots.where((s) => !s.dropped).toList();
  if (live.isEmpty) return ['Add a hook in the first three seconds.'];
  final first = live.first;
  if (first.line.trim().isEmpty && first.action.trim().isEmpty) {
    return ['The hook has to be spoken or shown in the first three seconds.'];
  }
  return [];
}

List<String> checkClaims(List<ShotCard> shots, List<Map<String, dynamic>> findings) {
  if (findings.isEmpty) return [];
  final ids = findings.map((f) => (f['id'] ?? '').toString()).where((s) => s.isNotEmpty).toSet();
  final reasons = <String>[];
  for (final shot in shots.where((s) => !s.dropped)) {
    final hasNumber = RegExp(r'\d').hasMatch(shot.line);
    if (!hasNumber) continue;
    if (shot.cites.isEmpty || (ids.isNotEmpty && shot.cites.every((id) => !ids.contains(id)))) {
      reasons.add('A number in the script is not tied to a finding.');
    }
  }
  return reasons;
}

const _exportableMoves = {'cut', 'dissolve', 'dip', 'fade', 'push'};

List<String> checkEditPlan(Map<String, dynamic> plan, int durationSeconds) {
  final transitions = ((plan['transitions'] as List?) ?? const []).map((e) => e.toString()).toList();
  final reasons = <String>[];
  if (durationSeconds > 30 && transitions.isNotEmpty && transitions.every((t) => t == 'cut')) {
    reasons.add('A film this long needs more than straight cuts.');
  }
  for (final move in transitions) {
    if (!_exportableMoves.contains(move)) {
      reasons.add('That move cannot be exported.');
    }
  }
  return reasons;
}

List<String> checkShots(List<ShotCard> shots, {required bool speechTrack}) {
  final reasons = <String>[];
  final live = shots.where((s) => !s.dropped).toList();
  if (live.isEmpty) return ['Add at least one shot.'];
  final locks = live.map((s) => s.lock.trim()).where((s) => s.isNotEmpty).toSet();
  if (locks.length > 1) {
    reasons.add('The character description changed between shots.');
  }
  for (final shot in live) {
    if (shot.action.trim().isEmpty) reasons.add('A shot has nothing to see.');
    final cap = shot.model.startsWith('ltx') ? 20 : 15;
    if (shot.kind == 'video' && shot.durationSeconds > cap) {
      reasons.add('A shot is longer than the model can hold.');
    }
    if (shot.kind == 'user' && (shot.videoPrompt ?? '').trim().isNotEmpty) {
      reasons.add('A file you attached was given a replacement prompt.');
    }
    final spoken = shot.line.trim();
    final video = shot.videoPrompt ?? '';
    if (speechTrack && spoken.isNotEmpty && video.contains(spoken)) {
      reasons.add('A spoken line was copied into the clip prompt.');
    }
  }
  return reasons;
}

int wordCount(List<ShotCard> shots) {
  return shots
      .where((s) => !s.dropped)
      .map((s) => s.line.trim())
      .where((s) => s.isNotEmpty)
      .join(' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;
}

List<String> checkSpokenLength(List<ShotCard> shots, int durationSeconds) {
  final words = wordCount(shots);
  if (words == 0) return [];
  final target = (durationSeconds / 60 * 150).round();
  if (target == 0) return [];
  final delta = (words - target).abs() / target;
  if (delta > 0.10) {
    return ['The script length does not match the film length.'];
  }
  return [];
}

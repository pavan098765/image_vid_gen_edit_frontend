import 'workflow_models.dart';
import 'workflow_rules.dart';

bool isVideoAssetPath(String path) {
  final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
  return RegExp(r'\.(mp4|mov|webm|mkv|m4v)$').hasMatch(name);
}

UserAsset classifyAsset(String path) {
  final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
  if (isVideoAssetPath(path)) {
    return UserAsset(
      path: path,
      role: 'footage',
      note: 'Cut in as picture. The rest of the film is still made around it.',
    );
  }
  if (name.contains('character') || name.contains('sheet') || name.contains('portrait') || name.contains('face')) {
    return UserAsset(
      path: path,
      role: 'character',
      note: 'Used as the face and look of every generated shot.',
    );
  }
  if (name.contains('product') || name.contains('pack') || name.contains('sku')) {
    return UserAsset(
      path: path,
      role: 'product',
      note: 'Used on every shot that shows the product.',
    );
  }
  if (name.contains('background') || name.contains('bg') || name.contains('set') || name.contains('plate')) {
    return UserAsset(
      path: path,
      role: 'background',
      note: 'Used as the set, not as a single pasted card.',
    );
  }
  return UserAsset(path: path, role: 'other', note: '');
}

List<UserAsset> classifyAssets(List<String> paths) {
  final assets = paths.map(classifyAsset).toList();
  final unlabeled = assets.where((a) => a.role == 'other').toList();
  if (unlabeled.length == 1) {
    unlabeled.first.role = 'reference';
    unlabeled.first.note = 'Used as the look of every generated shot.';
  } else if (unlabeled.length > 1) {
    unlabeled.first.role = 'reference';
    unlabeled.first.note = 'Used as the look of every generated shot.';
    for (final asset in unlabeled.skip(1)) {
      asset.role = 'background';
      asset.note = 'Used as the set, not as a single pasted card.';
    }
  }
  return assets;
}

/// A file the user placed in a named slot. [role] empty means the name is still a guess.
List<UserAsset> assetsFromLabels(List<({String path, String role, String label})> picks) {
  return [
    for (final pick in picks)
      pick.role.isEmpty ? _guess(pick.path, pick.label) : _named(pick.path, pick.role, pick.label),
  ];
}

UserAsset _guess(String path, String label) {
  final asset = classifyAsset(path);
  final named = label.trim();
  if (named.isEmpty) return asset;
  asset.note = named;
  asset.pinned = true;
  return asset;
}

UserAsset _named(String path, String role, String label) {
  final named = label.trim();
  final who = named.isEmpty ? '' : ' named $named';
  final note = switch (role) {
    'character' => 'Character$who. The same face on every generated shot.',
    'background' => 'Set$who. The place the film returns to, not one pasted card.',
    'product' => 'Object$who. Keep it recognizable whenever it is in frame.',
    'footage' => named.isEmpty ? 'Footage. Cut in as picture.' : 'Footage named $named. Cut in as picture.',
    'reference' => named.isEmpty
        ? 'Reference picture. Use only the look it shows.'
        : 'Reference named $named. Use only the look it shows.',
    _ => named,
  };
  return UserAsset(path: path, role: role, note: note, pinned: true);
}

void applyClassified(FilmDraft draft, Map<String, dynamic> json) {
  final list = json['assets'];
  if (list is! List) return;
  for (final raw in list) {
    if (raw is! Map) continue;
    final path = (raw['path'] ?? '').toString();
    final role = (raw['role'] ?? '').toString();
    final note = (raw['note'] ?? '').toString();
    final match = draft.assets.where((a) => a.path == path);
    if (match.isEmpty) continue;
    const allowed = {'character', 'background', 'product', 'footage', 'reference'};
    if (match.first.pinned) continue;
    if (allowed.contains(role)) match.first.role = role;
    if (note.trim().isNotEmpty) match.first.note = note.trim();
  }
}

const lookRoles = {
  'narrated_story': ['character', 'background'],
  'what_if_diary': ['character', 'background'],
  'creature_eye': ['character', 'background'],
  'explainer': ['background'],
  'podcast': ['background'],
  'time_travel_pov': ['background'],
  'body': ['background'],
  'fpv': ['background'],
  'countdown': ['background'],
};

void ensureLookAnchors(FilmDraft draft) {
  if (draft.workflowId == 'cut_my_clips') return;
  final roles = lookRoles[draft.workflowId] ?? const ['background'];
  final assets = [...draft.assets];
  var changed = false;
  for (final role in roles) {
    final exists = assets.any((a) => a.role == role && a.path.isNotEmpty);
    if (exists) continue;
    changed = true;
    assets.add(UserAsset(
      path: 'look:$role',
      role: role,
      note: role == 'character' ? 'Made for this film and used on every generated shot.' : 'Made for this film and used as the set.',
      prompt: _anchorPrompt(draft, role),
    ));
  }
  if (changed) draft.assets = assets;
}

String _anchorPrompt(FilmDraft draft, String role) {
  final look = [draft.lock.trim(), draft.topic.trim()].where((s) => s.isNotEmpty).join('. ');
  if (role == 'character' && draft.workflowId == 'creature_eye') {
    return 'Creature sheet for $look. Front, side, and full body on a plain background. The same animal in every view. No human face. No text.';
  }
  if (role == 'character') {
    return 'Character sheet for $look. Front, three-quarter, and full body on a plain background. The same face in every view. No scene. No text.';
  }
  if (draft.workflowId == 'fpv') {
    return 'Empty aerial plate for $look. One camera height, one weather, wide view. No people, no face, no text.';
  }
  if (draft.workflowId == 'body') {
    return 'Documentary plate of the body region in $look. No face, no text.';
  }
  return 'Empty set for $look. Wide view of the place the film returns to. No people, no text.';
}

void bindAssets(FilmDraft draft) {
  for (final shot in draft.shots.where((s) => !s.dropped && s.kind != 'user')) {
    final guides = guideAssets(draft, shot);
    if (guides.isEmpty) {
      shot.referencePath = null;
      shot.referenceRole = null;
      continue;
    }
    final match = guides.first;
    shot.referencePath = match.path;
    shot.referenceRole = match.role;
    final key = (match.r2Key ?? '').trim();
    if (key.isNotEmpty) shot.referenceR2Key = key;
  }
  for (final clip in draft.assets.where((a) => a.role == 'footage')) {
    final used = draft.shots.any((s) => s.localPath == clip.path || s.userFileId == clip.path);
    if (used) continue;
    draft.shots.insert(
      0,
      ShotCard(
        id: 'file_${clip.path.hashCode.abs()}',
        chapter: draft.shots.isEmpty ? 'Hook' : draft.shots.first.chapter,
        action: clip.note,
        durationSeconds: 5,
        kind: 'user',
        kindSetByUser: true,
        localPath: clip.path,
        userFileId: clip.path,
      ),
    );
  }
}

const _nameSkip = {
  'character',
  'sheet',
  'portrait',
  'face',
  'background',
  'set',
  'plate',
  'image',
  'look',
  'png',
  'jpg',
  'jpeg',
  'webp',
};

List<UserAsset> guideAssets(FilmDraft draft, ShotCard shot) {
  final pictures = draft.assets.where((a) => a.role != 'footage').toList();
  final hay = '${shot.action} ${shot.line} ${shot.onScreen} ${shot.chapter}'.toLowerCase();
  final people = pictures.where((a) => a.role == 'character' || a.role == 'reference').toList();
  final sets = pictures.where((a) => a.role == 'background').toList();
  final products = pictures.where((a) => a.role == 'product').toList();
  final chosen = <UserAsset>[];
  void add(UserAsset? asset) {
    if (asset == null || chosen.length >= 4) return;
    if (chosen.any((a) => a.path == asset.path)) return;
    chosen.add(asset);
  }

  for (final asset in people.where((a) => _assetMentioned(a, hay))) {
    if (chosen.length >= (sets.isEmpty ? 4 : 3)) break;
    add(asset);
  }
  if (chosen.isEmpty && people.isNotEmpty) add(people.first);
  final namedSet = sets.where((a) => _assetMentioned(a, hay)).toList();
  add(namedSet.isNotEmpty ? namedSet.first : (sets.isNotEmpty ? sets.first : null));
  for (final asset in products.where((a) => _showsProduct(shot, a))) {
    add(asset);
  }
  return chosen;
}

bool _assetMentioned(UserAsset asset, String hay) {
  final stem = asset.path.split(RegExp(r'[/\\]')).last.split('.').first.toLowerCase();
  final tokens = stem.split(RegExp(r'[_\-:\s]+')).where((t) => t.length > 2 && !_nameSkip.contains(t));
  if (tokens.any(hay.contains)) return true;
  final note = asset.note.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.length > 2 && !_nameSkip.contains(w));
  return note.any(hay.contains);
}

bool _showsProduct(ShotCard shot, UserAsset product) {
  final file = product.path.split(RegExp(r'[/\\]')).last.toLowerCase();
  final stem = file.split('.').first;
  final hay = '${shot.action} ${shot.line}'.toLowerCase();
  return hay.contains('product') || hay.contains(stem);
}

String _ordinal(int index) {
  const names = ['first', 'second', 'third', 'fourth'];
  return names[index];
}

String _guideLabel(FilmDraft draft, UserAsset asset) {
  if (asset.role == 'background') return 'set';
  if (asset.role == 'product') return 'object';
  if (draft.workflowId == 'creature_eye') return 'creature';
  return 'character';
}

String assetPrompt(FilmDraft draft, ShotCard shot) {
  final pictures = draft.assets.where((a) => a.role != 'footage').toList();
  final guides = guideAssets(draft, shot);
  final lines = <String>[];
  if (guides.length >= 2) {
    final named = [
      for (var i = 0; i < guides.length; i++) 'The ${_ordinal(i)} image is the ${_guideLabel(draft, guides[i])}',
    ];
    lines.add('${named.join('. ')}. Keep each one recognizable.');
  }
  for (final asset in pictures) {
    final owned = asset.isMade ? '' : 'uploaded ';
    if (asset.path == shot.referencePath && asset.path.isNotEmpty) {
      final name = asset.role == 'background' ? 'set' : asset.role;
      lines.add('Match the $owned$name. Keep it recognizable in this shot.');
    } else if (asset.role == 'background') {
      lines.add(asset.isMade ? 'Place the action in the set.' : 'Place the action in the uploaded set.');
    } else if (asset.role == 'product') {
      lines.add('Keep the ${owned}product recognizable when it is in frame.');
    }
  }
  return lines.join(' ');
}

String chooseVideoModel(FilmDraft draft, ShotCard shot, WorkflowSpec spec) {
  if (draft.videoEngine == 'ltx25_int8_t2v') return 'ltx25_int8_t2v';
  if (draft.videoEngine == 'minimax_h3') return 'minimax_h3';
  if (spec.chainEndFrames || spec.id == 'fpv' || spec.id == 'body') return 'ltx25_int8_t2v';
  if (shot.durationSeconds > 15) return 'ltx25_int8_t2v';
  final text = '${shot.action} ${shot.onScreen} ${shot.chapter} ${shot.line}'.toLowerCase();
  final named = draft.assets
      .where((a) => a.role == 'character')
      .where((a) => _assetMentioned(a, text))
      .length;
  final onScreen = shot.kind == 'video' && shot.line.trim().isNotEmpty && !isNarrationLine(shot);
  final camera = RegExp(
    r'\b(wide|aerial|forest|river|palace|city|army|crowd|landscape|sky|sea|ocean|bridge|road|valley|temple|fly|flies|glides|camera|crosses|crossing)\b',
  ).hasMatch(text);
  if (spec.id == 'podcast' || onScreen || named >= 2) return 'minimax_h3';
  if (spec.id == 'song_video' && named >= 1) return 'minimax_h3';
  if (camera || spec.id == 'countdown' || spec.id == 'explainer' || spec.id == 'creature_eye' || spec.id == 'song_video') {
    return 'ltx25_int8_t2v';
  }
  return 'minimax_h3';
}

void applyPicturePolicy(List<ShotCard> shots, String workflowId) {
  final live = shots.where((s) => !s.dropped && s.kind != 'user' && !s.kindSetByUser).toList();
  if (live.isEmpty) return;
  if (workflowId == 'narrated_story' ||
      workflowId == 'explainer' ||
      workflowId == 'countdown' ||
      workflowId == 'body') {
    for (final shot in live) {
      shot.kind = 'video';
    }
  } else if (workflowId == 'podcast') {
    for (var i = 0; i < live.length; i++) {
      live[i].kind = (i == 0 || i == live.length - 1) ? 'video' : 'image';
    }
  } else if (workflowId == 'countdown' || workflowId == 'body') {
    for (var i = 0; i < live.length; i++) {
      live[i].kind = i == live.length - 1 ? 'video' : 'image';
    }
  } else if (workflowId == 'fpv' ||
      workflowId == 'what_if_diary' ||
      workflowId == 'time_travel_pov' ||
      workflowId == 'creature_eye' ||
      workflowId == 'song_video') {
    for (final shot in live) {
      shot.kind = 'video';
    }
  }
}

String soundFor(String workflowId, {required bool clipAudioIsMain, required bool lastShot}) {
  switch (workflowId) {
    case 'narrated_story':
      return 'the place in this shot: wind, room, water, or weather';
    case 'explainer':
      return 'a quiet room';
    case 'podcast':
      return 'a quiet treated room';
    case 'what_if_diary':
      return 'the place of that day';
    case 'time_travel_pov':
      return 'the era around the camera';
    case 'body':
      return 'body sounds: breath, pulse, and impact';
    case 'fpv':
      return 'wind and motor';
    case 'creature_eye':
      return 'that animal\'s place: wind, water, or leaves';
    case 'countdown':
      return lastShot ? 'the place of the winning rank' : 'a quiet room';
    default:
      return clipAudioIsMain ? 'wind and motor' : 'the sound of this place';
  }
}

String musicStyle(String workflowId) {
  switch (workflowId) {
    case 'narrated_story':
    case 'what_if_diary':
    case 'time_travel_pov':
      return 'cinematic instrumental, sparse, no vocals';
    case 'explainer':
    case 'podcast':
      return 'quiet instrumental bed, no vocals';
    case 'body':
      return 'spare documentary instrumental, no vocals';
    case 'fpv':
      return 'driving instrumental, no vocals';
    case 'creature_eye':
      return 'naturalistic instrumental, no vocals';
    case 'countdown':
      return 'tense instrumental that lifts at the end, no vocals';
    case 'song_video':
      return 'a sung song with a clear lead vocal';
    default:
      return 'cinematic instrumental, no vocals';
  }
}

String sfxPrompt(String workflowId) {
  if (workflowId == 'countdown') {
    return 'One short hit as the winning rank appears. No voice. No music.';
  }
  return 'One short hit. No voice. No music.';
}

String voiceDescription(FilmDraft draft) {
  final voice = draft.voiceLock.trim();
  if (voice.isNotEmpty) return voice;
  return 'One narrator, the same age and accent in every chapter.';
}

const _voiceDefaults = {
  'narrated_story': 'One narrator, unhurried, the same age and accent in every chapter.',
  'explainer': 'One clear narrator, the same voice in every chapter.',
  'podcast': 'Each speaker keeps one voice. Do not change age or accent between chapters.',
  'what_if_diary': 'One second-person narrator, close and steady.',
  'time_travel_pov': 'One narrator, plus a second speaker only for the stranger.',
  'body': 'One documentary narrator, calm and precise.',
  'countdown': 'One host, the same voice for every rank.',
  'creature_eye': 'One quiet narrator, used only when narration is on.',
};

void ensureVoiceLock(FilmDraft draft) {
  if (draft.voiceLock.trim().isNotEmpty) return;
  draft.voiceLock = _voiceDefaults[draft.workflowId] ?? voiceDescription(draft);
}

List<String> checkProduct(FilmDraft draft) {
  final live = draft.shots.where((s) => !s.dropped).toList();
  final reasons = <String>[];
  switch (draft.workflowId) {
    case 'narrated_story':
      final chapters = live.map((s) => s.chapter.toLowerCase()).join(' ');
      if (live.length > 2 && !chapters.contains('turn')) {
        reasons.add('The story needs a turn.');
      }
      if (live.length > 2 && !chapters.contains('last')) {
        reasons.add('The story needs a last image.');
      }
      if (live.isNotEmpty) {
        final words = live.first.line.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        if (words > 12) reasons.add('The hook has to be sayable in the first three seconds.');
      }
      for (final shot in live.where((s) => s.kind == 'video')) {
        if ((shot.videoPrompt ?? '').toLowerCase().contains('soft room tone')) {
          reasons.add('Name the sound of the place.');
        }
      }
      break;
    case 'explainer':
      for (final shot in live) {
        final screen = shot.onScreen.trim();
        if (screen.isNotEmpty && screen == shot.line.trim()) {
          reasons.add('On-screen text repeats the sentence.');
        }
      }
      break;
    case 'podcast':
      final speakers = live.map((s) => s.speaker.trim()).where((s) => s.isNotEmpty).toSet();
      if (live.any((s) => s.line.trim().isNotEmpty) && speakers.length < 2) {
        reasons.add('A podcast needs at least two speakers.');
      }
      break;
    case 'fpv':
      for (final shot in live) {
        final text = '${shot.action} ${shot.line}'.toLowerCase();
        if (RegExp(r'\b(face|portrait|close-up of a person)\b').hasMatch(text)) {
          reasons.add('An FPV shot cannot cut to a face.');
        }
        if (shot.kind == 'video' && !shot.model.startsWith('ltx') && draft.videoEngine != 'minimax_h3') {
          reasons.add('FPV shots have to chain.');
        }
      }
      break;
    case 'countdown':
      final nums = <int>[];
      for (final shot in live) {
        final match = RegExp(r'\d+').firstMatch(shot.chapter);
        if (match != null) nums.add(int.parse(match.group(0)!));
      }
      if (nums.length >= 3 && nums.last > nums.first) {
        reasons.add('The best item has to be last.');
      }
      if (live.isNotEmpty && live.last.kind != 'video' && live.last.kind != 'user') {
        reasons.add('The last rank is a moving shot.');
      }
      break;
    case 'cut_my_clips':
      if (live.any((s) => s.kind != 'user' || ((s.videoPrompt ?? '').trim().isNotEmpty))) {
        reasons.add('Use only the files that were attached.');
      }
      break;
    case 'what_if_diary':
      final videos = live.where((s) => s.kind == 'video').length;
      final images = live.where((s) => s.kind == 'image').length;
      if (images > videos) reasons.add('This diary is told in moving shots.');
      break;
    case 'creature_eye':
      for (final shot in live) {
        if (shot.action.toLowerCase().contains('human face')) {
          reasons.add('The camera stays at the animal\'s eye height, with no human face.');
        }
      }
      break;
  }
  if (draft.voiceLock.trim().isNotEmpty && draft.voiceLock.trim() == draft.lock.trim()) {
    reasons.add('The narrator\'s voice has to be separate from the picture lock.');
  }
  return reasons;
}

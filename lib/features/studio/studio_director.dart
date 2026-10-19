import 'workflow_models.dart';

class CastNeed {
  final String name;
  final String role;
  final String prompt;

  const CastNeed({required this.name, required this.role, required this.prompt});
}

const _castRoles = {'character', 'background', 'product'};

List<CastNeed> readCast(Map<String, dynamic> json) {
  final raw = json['assets'];
  if (raw is! List) return const [];
  final needs = <CastNeed>[];
  final seen = <String>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final name = (item['name'] ?? '').toString().trim();
    final role = (item['role'] ?? '').toString().trim();
    if (name.isEmpty || !_castRoles.contains(role)) continue;
    final key = '${role.toLowerCase()}:${name.toLowerCase()}';
    if (!seen.add(key)) continue;
    if (needs.length == 6) break;
    needs.add(CastNeed(
      name: name,
      role: role,
      prompt: (item['prompt'] ?? '').toString().trim(),
    ));
  }
  return needs;
}

bool assetCovers(UserAsset asset, String role, String name) {
  if (asset.role != role || asset.isMade) return false;
  final needle = name.toLowerCase();
  final hay = '${asset.note} ${asset.path}'.toLowerCase();
  return hay.contains(needle);
}

/// Adds the sheets and sets the story needs. A file the user already
/// brought for that name is left alone.
void installCast(FilmDraft draft, Map<String, dynamic> json) {
  final needs = readCast(json);
  if (needs.isEmpty) return;
  final assets = [...draft.assets];
  for (final need in needs) {
    if (assets.any((asset) => assetCovers(asset, need.role, need.name))) continue;
    assets.removeWhere((asset) => asset.isMade && asset.path == 'look:${need.role}');
    final slug = need.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    if (slug.isEmpty) continue;
    final path = 'look:${need.role}:$slug';
    if (assets.any((asset) => asset.path == path)) continue;
    final prompt = need.prompt.isEmpty ? _sheetPrompt(draft, need) : need.prompt;
    assets.add(UserAsset(
      path: path,
      role: need.role,
      note: '${need.name}. ${_sheetNote(need.role)}',
      prompt: prompt,
    ));
  }
  draft.assets = assets;
}

String _sheetNote(String role) {
  switch (role) {
    case 'background':
      return 'The place the film returns to.';
    case 'product':
      return 'Keep it recognizable whenever it is in frame.';
    default:
      return 'The same face on every generated shot.';
  }
}

String _sheetPrompt(FilmDraft draft, CastNeed need) {
  final story = [draft.lock.trim(), draft.topic.trim()].where((s) => s.isNotEmpty).join('. ');
  switch (need.role) {
    case 'background':
      return 'Empty set of ${need.name} for $story. One wide view, one light, no people, no text.';
    case 'product':
      return 'Object sheet of ${need.name} for $story. Three views on a plain background. No scene. No text.';
    default:
      return 'Character sheet of ${need.name} for $story. Front, three-quarter, and full body on a plain background. The same face in every view. No scene. No text.';
  }
}

String castInstruction(FilmDraft draft) {
  final shots = draft.shots
      .where((shot) => !shot.dropped)
      .map((shot) => '${shot.id}: ${shot.action} ${shot.line}'.trim())
      .join('\n');
  final owned = draft.assets
      .where((asset) => !asset.isMade)
      .map((asset) => '${asset.role}: ${asset.note}')
      .join('; ');
  return 'You are the creative director. Topic: ${draft.topic}. Lock: ${draft.lock}.\n'
      'Shots:\n$shots\n'
      'Already uploaded: ${owned.isEmpty ? 'none' : owned}.\n'
      'Return {"assets":[{"name":"Rama","role":"character|background|product","prompt":"..."}]}.\n'
      'List only people, places, and objects that must look the same in more than one shot. At most six, and at most four in any one shot. '
      'Do not list a person, place, or object the upload already covers. '
      'A character prompt is a sheet on a plain background, front and full body, no scene, no text. '
      'A set prompt is an empty place, no people, no text. '
      'An object prompt is three views on a plain background, no scene, no text.';
}

/// What the picture models can actually hold, told to the writer.
String craftBrief(String workflowId) {
  switch (workflowId) {
    case 'narrated_story':
      return 'Every shot is video, 6 to 10 seconds, and the durations add up to the length. '
          'A face or a line said on screen names the acting. A journey, crowd, or landscape names the camera move and has no close face. '
          'Do not plan a still.';
    case 'explainer':
      return 'Every shot is video, 6 to 8 seconds. The opening claim moves. '
          'On-screen text is one term, never the spoken sentence. A host face is used only when the lock names a host.';
    case 'podcast':
      return 'Only the first shot and the last shot are video. The middle shots are stills. '
          'Do not write mouth movement. At least two speakers, each with one voice.';
    case 'fpv':
      return 'Every shot is video, 6 to 12 seconds, one camera height, one lens, one weather. '
          'No face. Each shot starts on its frame and lands on the next shot\'s frame. The sound is wind and motor.';
    case 'body':
      return 'Every beat is video, 6 to 10 seconds, one camera inside the body. '
          'Each shot lands on the next beat. Name breath, pulse, or impact. No face.';
    case 'time_travel_pov':
      return 'Every shot is video. The same person walks. One modern object stays recognizable. '
          'A walk starts on one frame and lands on the next.';
    case 'creature_eye':
      return 'Every shot is video from the animal\'s eye height. One real behavior per shot. No human face.';
    case 'countdown':
      return 'Every rank is a moving shot of 5 to 8 seconds. The best rank is last. One sourced fact per rank.';
    case 'song_video':
      return 'Scenes are 4 to 10 seconds and sit on the song lines. The picture follows the song. '
          'A face in the lock is the same person in every scene that shows them.';
    case 'what_if_diary':
      return 'Every shot is video. Chapters are Day 1, Day 2, Day 3, and the bill. One locked person.';
    case 'cut_my_clips':
      return 'Use only the attached files. Do not invent a shot.';
    default:
      return 'Shots are 6 to 10 seconds of video. A face is held. A camera move names the camera.';
  }
}

String composeKeyframePrompt({
  required String action,
  required String lock,
  required List<UserAsset> guides,
}) {
  final labels = <String>[];
  for (var i = 0; i < guides.length; i++) {
    final name = _shortName(guides[i]);
    labels.add('Image ${i + 1} is the $name.');
  }
  final keep = labels.isEmpty
      ? ''
      : '${labels.join(' ')} Keep each one recognizable. Do not redesign a face, a place, or an object. One frame, no text, no collage.';
  return [lock.trim(), keep, action.trim()].where((line) => line.isNotEmpty).join('\n');
}

String _shortName(UserAsset asset) {
  final note = asset.note.split('.').first.trim();
  if (note.isNotEmpty && !note.startsWith('Made for')) return note;
  switch (asset.role) {
    case 'background':
      return 'set';
    case 'product':
      return 'object';
    default:
      return 'character';
  }
}

/// On-screen speech stays in the clip. Voiceover stays out, for the narrator track.
String performedClipPrompt({
  required ShotCard shot,
  required String sound,
  required String reference,
  required bool arriveOnEnd,
}) {
  final ltx = shot.model.startsWith('ltx');
  final spoken = shot.line.trim();
  final speaker = shot.speaker.trim().isEmpty ? 'The person on screen' : shot.speaker.trim();
  final lines = <String>[
    shot.lock.trim(),
    reference.trim(),
    if (ltx) 'Camera: ${shot.action.trim()}' else shot.action.trim(),
    'Hold the face, clothes, and place from the opening frame.',
    if (spoken.isNotEmpty) '$speaker says, "$spoken". The mouth moves with those words. No other voice.',
    if (arriveOnEnd) 'Arrive on the closing frame.',
    'Sound: ${sound.trim()}. No music.',
  ];
  return lines.where((line) => line.isNotEmpty).join('\n');
}

bool sharesSet(FilmDraft draft, ShotCard a, ShotCard b) {
  String? setOf(ShotCard shot) {
    for (final asset in draft.assets) {
      if (asset.role != 'background') continue;
      final hay = '${shot.action} ${shot.line} ${shot.chapter}'.toLowerCase();
      final name = asset.note.split('.').first.trim().toLowerCase();
      if (name.isNotEmpty && hay.contains(name)) return asset.path;
    }
    final sets = draft.assets.where((asset) => asset.role == 'background').toList();
    if (sets.length == 1) return sets.first.path;
    return null;
  }

  final left = setOf(a);
  final right = setOf(b);
  return left != null && left == right;
}

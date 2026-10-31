/// Suno V6 job types. Matches docs/suno_v6_frontend.md.
library;

const String kSunoV6ModelId = 'suno_v6';

const List<String> kSunoV6SoundKeys = [
  'Any',
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
  'Cm',
  'C#m',
  'Dm',
  'D#m',
  'Em',
  'Fm',
  'F#m',
  'Gm',
  'G#m',
  'Am',
  'A#m',
  'Bm',
];

const List<String> kSunoV6StemNames = [
  'Lead Vocal',
  'Drum Kit',
  'Kick',
  'Snare',
  'Risers',
  'Bass',
  'Backing Vocals',
  'Piano',
  'Electric Guitar',
  'Percussion',
  'String Section',
  'Synth',
  'Acoustic Guitar',
  'Sound Effects',
  'Synth Pad',
  'Synth Bass',
  'Guitar',
  'Brass Section',
  'Organ',
  'Electronic Drum Kit',
  'Lead Electric Guitar',
  'Synth Keys',
  'Rhythm Electric Guitar',
  'Electric Piano',
  'Upright Bass',
  'Keyboards',
  'Distorted Electric Guitar',
  'Synth Strings',
  'Synth Lead',
  'Woodwinds',
  'Rhythm Acoustic Guitar',
  'Flute',
  'Harp',
  'Tambourine',
  'Trumpet',
  'Arpeggiator',
  'Accordion',
  'Fiddle',
  'Pedal Steel Guitar',
  'Synth Voice',
  'Violin',
  'Digital Piano',
  'Synth Brass',
  'Mandolin',
  'Choir',
  'Banjo',
  'Bells',
  'Clarinet',
  'Tenor Saxophone',
  'Trombone',
  'Shaker',
  'French Horn',
  'Glockenspiel',
  'Electric Bass',
  'Cello',
  'Timpani',
  'Harmonica',
  'Marimba',
  'Vibraphone',
  'Lap Steel Guitar',
  'Saxophone',
  'Orchestra',
  'Horns',
  'Cymbals',
  'Hand Clap',
  'Oboe',
  'Celesta',
  'Congas',
  'Drone',
  'Alto Saxophone',
  'Double Bass',
  'Ukulele',
  'Harpsichord',
  'Baritone Saxophone',
  'Xylophone',
  'Tuba',
  'Bass Guitar',
  'Whistle',
  'Lead Guitar',
  'Rhodes',
  '808',
  'Bongos',
  'Bassoon',
  'Cowbell',
  'Viola',
  'Sitar',
  'Steel Drums',
  'Piccolo',
  'Theremin',
  'Bagpipes',
  'Hi-Hat',
  'Music Box',
  'Melodica',
  'Tabla',
  'Koto',
  'Djembe',
  'Taiko',
  'Didgeridoo',
];

int sunoV6CreditCost({required String action, String? stemType}) {
  switch (action) {
    case 'lyrics':
      return 20;
    case 'covers':
      return 40;
    case 'video':
      return 80;
    case 'persona':
      return 40;
    case 'voice':
      return 8;
    case 'stems':
      if (stemType == 'split_stem') return 160;
      if (stemType == 'split_stem_advanced') return 120;
      return 80;
    case 'sounds':
      return 15;
    case 'extend':
    case 'upload_extend':
    case 'mashup':
    case 'replace':
    case 'song':
    default:
      return 65;
  }
}

String sunoV6PhaseLabel(String? phase, {String? fallback}) {
  switch (phase) {
    case 'writing_lyrics':
      return 'Writing lyrics';
    case 'composing':
      return 'Composing';
    case 'first_track':
      return 'First version ready';
    case 'cover_art':
      return 'Painting covers';
    case 'separating':
      return 'Separating stems';
    case 'rendering_video':
      return 'Rendering video';
    case 'replacing':
      return 'Replacing a section';
    case 'complete':
      return 'Ready';
    default:
      return fallback ?? 'Working';
  }
}

int sunoV6PhaseRank(String? phase) {
  const order = {
    'writing_lyrics': 1,
    'composing': 2,
    'first_track': 3,
    'cover_art': 4,
    'separating': 3,
    'rendering_video': 3,
    'replacing': 3,
    'complete': 5,
  };
  return order[phase] ?? 0;
}

Map<String, dynamic>? musicMapFromStatus(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

Map<String, dynamic>? preferRicherMusic(
  Map<String, dynamic>? current,
  Map<String, dynamic>? incoming,
) {
  if (incoming == null) return current;
  if (current == null) return incoming;
  return MusicResult.fromJson(current)
      .absorb(MusicResult.fromJson(incoming))
      .toJson();
}

String? fullerLyrics(MusicTrack track, List<MusicLyricSheet> sheets) {
  var best = track.lyrics?.trim() ?? '';
  for (final sheet in sheets) {
    final text = sheet.text.trim();
    if (text.length <= best.length) continue;
    // Easy mode writes a lyric sheet, then the model sings its own words.
    // Those words come back on the clip. A different sheet must not replace them.
    if (best.isEmpty || _sameLyric(best, text)) best = text;
  }
  return best.isEmpty ? null : best;
}

bool _sameLyric(String current, String next) {
  final a = current.trim().toLowerCase();
  final b = next.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return false;
  if (b.startsWith(a) || a.startsWith(b)) return true;
  final aLine = a.split('\n').first.trim();
  final bLine = b.split('\n').first.trim();
  if (aLine.length < 8 || bLine.length < 8) return false;
  return b.contains(aLine) || a.contains(bLine);
}

String? _lyricsFromTrack(Map<String, dynamic> json) {
  final lyrics = _stringOrNull(json['lyrics']);
  final prompt = _stringOrNull(json['prompt']);
  final promptIsLyrics = prompt != null &&
      (prompt.contains('[') || prompt.contains('\n')) &&
      prompt.length >= 12;
  if (lyrics == null) return promptIsLyrics ? prompt : null;
  if (promptIsLyrics && prompt.length > lyrics.length + 24) return prompt;
  return lyrics;
}

class MusicLyricSheet {
  final String title;
  final String text;

  const MusicLyricSheet({required this.title, required this.text});

  factory MusicLyricSheet.fromJson(Map<String, dynamic> json) {
    return MusicLyricSheet(
      title: (json['title'] ?? '').toString(),
      text: (json['text'] ?? json['lyrics'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {'title': title, 'text': text};
}

class MusicStem {
  final String name;
  final String? url;
  final String? downloadUrl;

  const MusicStem({required this.name, this.url, this.downloadUrl});

  factory MusicStem.fromJson(Map<String, dynamic> json) {
    return MusicStem(
      name: (json['name'] ?? 'Stem').toString(),
      url: _stringOrNull(json['url']),
      downloadUrl: _stringOrNull(json['download_url']),
    );
  }

  String? get playUrl => downloadUrl ?? url;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (url != null) 'url': url,
        if (downloadUrl != null) 'download_url': downloadUrl,
      };
}

class MusicPersona {
  final String id;
  final String? name;
  final String? model;

  const MusicPersona({required this.id, this.name, this.model});

  factory MusicPersona.fromJson(Map<String, dynamic> json) {
    return MusicPersona(
      id: (json['id'] ?? '').toString(),
      name: _stringOrNull(json['name']),
      model: _stringOrNull(json['model']) ?? 'style_persona',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (model != null) 'model': model,
      };
}

class MusicTrack {
  final String id;
  final String title;
  final String? lyrics;
  final String? tags;
  final double? duration;
  final String? audioUrl;
  final String? streamUrl;
  final String? coverUrl;
  final String? downloadUrl;

  const MusicTrack({
    required this.id,
    required this.title,
    this.lyrics,
    this.tags,
    this.duration,
    this.audioUrl,
    this.streamUrl,
    this.coverUrl,
    this.downloadUrl,
  });

  factory MusicTrack.fromJson(Map<String, dynamic> json) {
    return MusicTrack(
      id: (json['id'] ?? json['audio_id'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      lyrics: _lyricsFromTrack(json),
      tags: _stringOrNull(json['tags']),
      duration: json['duration'] is num
          ? (json['duration'] as num).toDouble()
          : double.tryParse('${json['duration'] ?? ''}'),
      audioUrl: _stringOrNull(json['audio_url']),
      streamUrl: _stringOrNull(json['stream_url']) ??
          _stringOrNull(json['stream_audio_url']),
      coverUrl: _stringOrNull(json['cover_url']) ??
          _stringOrNull(json['coverUrl']) ??
          _stringOrNull(json['image_url']) ??
          _stringOrNull(json['imageUrl']) ??
          _urlFrom(json['cover']) ??
          _urlFrom(json['image']),
      downloadUrl: _stringOrNull(json['download_url']),
    );
  }

  /// The finished file. A stream can start earlier and has no stable length.
  /// The minted download link is the one the player can actually open.
  String? get fileUrl {
    if (_isFinishedFile(downloadUrl)) return downloadUrl;
    if (_isFinishedFile(audioUrl)) return audioUrl;
    return null;
  }

  bool _isFinishedFile(String? url) {
    if (url == null || url.isEmpty) return false;
    if (streamUrl != null && url == streamUrl) return false;
    return true;
  }

  /// Play the stream while the song is still arriving, even if a file URL is
  /// already attached. That early file is not the finished download.
  bool streamsDuring(String phase) {
    final stream = streamUrl;
    if (stream == null || stream.isEmpty) return false;
    return phase == 'first_track' || phase == 'composing';
  }

  String? urlDuring(String phase) {
    if (streamsDuring(phase)) return streamUrl;
    return fileUrl ?? streamUrl;
  }

  /// Play the finished file once it exists. Until then, play the stream.
  String? get playUrl => fileUrl ?? streamUrl;

  bool get isStreaming => fileUrl == null && streamUrl != null;

  bool get isPlayable => playUrl != null;

  Duration? get knownDuration {
    final seconds = duration;
    if (seconds == null || seconds <= 0) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  MusicTrack absorb(MusicTrack next) {
    final incomingWords = next.lyrics?.trim() ?? '';
    final keptWords = lyrics?.trim() ?? '';
    final words = incomingWords.isEmpty
        ? lyrics
        : keptWords.isEmpty || !_sameLyric(keptWords, incomingWords)
            ? next.lyrics
            : _longerText(lyrics, next.lyrics);
    final seconds = duration == null
        ? next.duration
        : next.duration == null
            ? duration
            : (duration! > next.duration! ? duration : next.duration);
    return MusicTrack(
      id: id.isNotEmpty ? id : next.id,
      title: title != 'Untitled' && title.trim().isNotEmpty ? title : next.title,
      lyrics: words,
      tags: _longerText(tags, next.tags),
      duration: seconds,
      audioUrl: next.audioUrl ?? audioUrl,
      streamUrl: streamUrl ?? next.streamUrl,
      coverUrl: next.coverUrl ?? coverUrl,
      downloadUrl: next.downloadUrl ?? downloadUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (lyrics != null) 'lyrics': lyrics,
        if (tags != null) 'tags': tags,
        if (duration != null) 'duration': duration,
        if (audioUrl != null) 'audio_url': audioUrl,
        if (streamUrl != null) 'stream_url': streamUrl,
        if (coverUrl != null) 'cover_url': coverUrl,
        if (downloadUrl != null) 'download_url': downloadUrl,
      };
}

class MusicResult {
  final String action;
  final String phase;
  final String? label;
  final String? variant;
  final bool easy;
  final bool instrumental;
  final bool commercialRights;
  final String? taskId;
  final String? sourceTaskId;
  final String? audioId;
  final List<MusicTrack> tracks;
  final List<MusicLyricSheet> lyrics;
  final int lyricsUsed;
  final List<String> covers;
  final List<MusicStem> stems;
  final String? videoUrl;
  final MusicPersona? persona;
  final String? voiceId;
  final String? note;

  const MusicResult({
    this.action = 'song',
    this.phase = '',
    this.label,
    this.variant,
    this.easy = true,
    this.instrumental = false,
    this.commercialRights = false,
    this.taskId,
    this.sourceTaskId,
    this.audioId,
    this.tracks = const [],
    this.lyrics = const [],
    this.lyricsUsed = 0,
    this.covers = const [],
    this.stems = const [],
    this.videoUrl,
    this.persona,
    this.voiceId,
    this.note,
  });

  factory MusicResult.fromJson(Map<String, dynamic> json) {
    return MusicResult(
      action: (json['action'] ?? 'song').toString(),
      phase: (json['phase'] ?? '').toString(),
      label: _stringOrNull(json['label']),
      variant: _stringOrNull(json['variant']),
      easy: json['easy'] != false,
      instrumental: json['instrumental'] == true,
      commercialRights: json['commercial_rights'] == true,
      taskId: _stringOrNull(json['task_id']),
      sourceTaskId: _stringOrNull(json['source_task_id']),
      audioId: _stringOrNull(json['audio_id']),
      tracks: _mapList(json['tracks'], MusicTrack.fromJson),
      lyrics: _mapList(json['lyrics'], MusicLyricSheet.fromJson),
      lyricsUsed: json['lyrics_used'] is num
          ? (json['lyrics_used'] as num).toInt()
          : 0,
      covers: _coverUrls(json),
      stems: _mapList(json['stems'], MusicStem.fromJson),
      videoUrl: _stringOrNull(json['video_url']),
      persona: json['persona'] is Map
          ? MusicPersona.fromJson(Map<String, dynamic>.from(json['persona'] as Map))
          : null,
      voiceId: _stringOrNull(json['voice_id']),
      note: _stringOrNull(json['note']),
    );
  }

  String get statusLine =>
      (label != null && label!.trim().isNotEmpty)
          ? label!.trim()
          : sunoV6PhaseLabel(phase);

  bool get hasPlayableTrack => tracks.any((t) => t.isPlayable);

  bool get isComplete => phase == 'complete';

  bool get canFollowUp =>
      isComplete && taskId != null && taskId!.isNotEmpty && tracks.isNotEmpty;

  bool get anyStreaming =>
      tracks.any((track) => track.streamsDuring(phase) || track.isStreaming);

  MusicResult absorb(MusicResult next) {
    final nextRank = sunoV6PhaseRank(next.phase);
    final keepNextPhase = next.phase.isNotEmpty && nextRank >= sunoV6PhaseRank(phase);
    return MusicResult(
      action: next.action.isNotEmpty ? next.action : action,
      phase: keepNextPhase ? next.phase : phase,
      label: keepNextPhase ? (next.label ?? label) : (label ?? next.label),
      variant: next.variant ?? variant,
      easy: easy,
      instrumental: instrumental || next.instrumental,
      commercialRights: commercialRights || next.commercialRights,
      taskId: next.taskId ?? taskId,
      sourceTaskId: next.sourceTaskId ?? sourceTaskId,
      audioId: next.audioId ?? audioId,
      tracks: _mergeTracks(tracks, next.tracks),
      lyrics: _mergeSheets(lyrics, next.lyrics),
      lyricsUsed: lyricsUsed,
      covers: _union(covers, next.covers),
      stems: next.stems.isNotEmpty ? next.stems : stems,
      videoUrl: next.videoUrl ?? videoUrl,
      persona: next.persona ?? persona,
      voiceId: next.voiceId ?? voiceId,
      note: next.note ?? note,
    );
  }

  MusicResult mergeFollowUp(MusicResult next) {
    final replaceSong = next.action == 'replace' || next.action == 'song';
    return MusicResult(
      action: replaceSong ? next.action : action,
      phase: next.isComplete ? 'complete' : (next.phase.isNotEmpty ? next.phase : phase),
      label: next.label ?? label,
      variant: next.variant ?? variant,
      easy: easy,
      instrumental: instrumental,
      commercialRights: commercialRights || next.commercialRights,
      taskId: replaceSong && next.taskId != null ? next.taskId : taskId,
      sourceTaskId: next.sourceTaskId ?? sourceTaskId,
      audioId: audioId,
      tracks: next.tracks.isNotEmpty ? next.tracks : tracks,
      lyrics: next.lyrics.isNotEmpty ? next.lyrics : lyrics,
      lyricsUsed: lyricsUsed,
      covers: next.covers.isNotEmpty ? next.covers : covers,
      stems: next.stems.isNotEmpty ? next.stems : stems,
      videoUrl: next.videoUrl ?? videoUrl,
      persona: next.persona ?? persona,
      voiceId: next.voiceId ?? voiceId,
      note: next.note ?? note,
    );
  }

  int get richness {
    var score = sunoV6PhaseRank(phase) * 20;
    score += tracks.where((t) => t.isPlayable).length * 12;
    score += lyrics.length * 2;
    score += covers.length;
    if (videoUrl != null) score += 6;
    if (stems.isNotEmpty) score += stems.length;
    if (persona != null) score += 4;
    if (commercialRights) score += 1;
    return score;
  }

  Map<String, dynamic> toJson() => {
        'action': action,
        'phase': phase,
        if (label != null) 'label': label,
        if (variant != null) 'variant': variant,
        'easy': easy,
        'instrumental': instrumental,
        'commercial_rights': commercialRights,
        if (taskId != null) 'task_id': taskId,
        if (sourceTaskId != null) 'source_task_id': sourceTaskId,
        if (audioId != null) 'audio_id': audioId,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'lyrics': lyrics.map((s) => s.toJson()).toList(),
        'lyrics_used': lyricsUsed,
        'covers': covers,
        'stems': stems.map((s) => s.toJson()).toList(),
        if (videoUrl != null) 'video_url': videoUrl,
        if (persona != null) 'persona': persona!.toJson(),
        if (voiceId != null) 'voice_id': voiceId,
        if (note != null) 'note': note,
      };
}

List<String> _coverUrls(Map<String, dynamic> json) {
  final found = <String>[];
  void add(dynamic raw) {
    final url = _urlFrom(raw);
    if (url != null && !found.contains(url)) found.add(url);
  }

  for (final key in ['covers', 'cover_urls', 'images']) {
    final raw = json[key];
    if (raw is List) {
      for (final item in raw) {
        add(item);
      }
    } else {
      add(raw);
    }
  }
  add(json['cover_url']);
  add(json['image_url']);
  return found;
}

String? _urlFrom(dynamic raw) {
  if (raw is String) {
    final text = raw.trim();
    return text.isEmpty ? null : text;
  }
  if (raw is Map) {
    return _stringOrNull(raw['url']) ??
        _stringOrNull(raw['cover_url']) ??
        _stringOrNull(raw['image_url']) ??
        _stringOrNull(raw['src']);
  }
  return null;
}

List<T> _mapList<T>(
  dynamic raw,
  T Function(Map<String, dynamic> json) parse,
) {
  if (raw is! List) return <T>[];
  final out = <T>[];
  for (final item in raw) {
    if (item is Map) {
      out.add(parse(Map<String, dynamic>.from(item)));
    }
  }
  return out;
}

List<MusicTrack> _mergeTracks(List<MusicTrack> current, List<MusicTrack> incoming) {
  final out = List<MusicTrack>.from(current);
  final untitledIncoming =
      incoming.where((track) => _trackKey(track).isEmpty).length;
  for (final next in incoming) {
    var index = -1;
    final key = _trackKey(next);
    if (key.isNotEmpty) {
      for (var i = 0; i < out.length; i++) {
        if (_trackKey(out[i]) == key) {
          index = i;
          break;
        }
      }
    } else if (untitledIncoming == 1) {
      // A title match is only safe for a single update that has no id and no
      // url. Two HitMaker versions often share a name.
      final title = next.title.trim().toLowerCase();
      if (title.isNotEmpty && title != 'untitled') {
        final matches = <int>[];
        for (var i = 0; i < out.length; i++) {
          if (out[i].title.trim().toLowerCase() == title) matches.add(i);
        }
        if (matches.length == 1) index = matches.first;
      }
    }
    if (index < 0) {
      out.add(next);
    } else {
      out[index] = out[index].absorb(next);
    }
  }
  return out;
}

String _trackKey(MusicTrack track) {
  if (track.id.isNotEmpty) return 'id:${track.id}';
  final url = track.audioUrl ?? track.streamUrl ?? track.downloadUrl ?? '';
  if (url.isNotEmpty) return 'url:$url';
  return '';
}

List<MusicLyricSheet> _mergeSheets(
  List<MusicLyricSheet> current,
  List<MusicLyricSheet> incoming,
) {
  final out = List<MusicLyricSheet>.from(current);
  for (final next in incoming) {
    var index = -1;
    final title = next.title.trim().toLowerCase();
    if (title.isNotEmpty) {
      for (var i = 0; i < out.length; i++) {
        if (out[i].title.trim().toLowerCase() == title) {
          index = i;
          break;
        }
      }
    }
    if (index < 0) {
      out.add(next);
      continue;
    }
    final kept = out[index];
    if (next.text.trim().length > kept.text.trim().length) out[index] = next;
  }
  return out;
}

List<String> _union(List<String> current, List<String> incoming) {
  final out = List<String>.from(current);
  for (final item in incoming) {
    if (item.isEmpty || out.contains(item)) continue;
    out.add(item);
  }
  return out;
}

String? _longerText(String? current, String? next) {
  final a = current?.trim() ?? '';
  final b = next?.trim() ?? '';
  if (a.isEmpty) return b.isEmpty ? null : b;
  if (b.isEmpty) return a;
  return b.length > a.length ? b : a;
}

String? _stringOrNull(dynamic raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}

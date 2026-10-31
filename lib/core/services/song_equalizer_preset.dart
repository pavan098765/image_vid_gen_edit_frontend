/// Picks a baked EQ curve from the song title, style, tags, and lyrics
/// when the preset service does not answer.
String? presetForSongText({
  required String title,
  required String style,
  required String tags,
  required String lyrics,
}) {
  final text = ' ${[title, style, tags, lyrics].join(' ').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()} ';
  if (text.trim().isEmpty) return null;
  const phrases = <(String, String)>[
    ('soft rock', 'softrock'),
    ('hip hop', 'fullbass'),
    ('lo fi', 'soft'),
    ('drum and bass', 'techno'),
    ('dubstep', 'techno'),
    ('bhangra', 'party'),
    ('punjabi', 'party'),
    ('bollywood', 'pop'),
    ('reggaeton', 'dance'),
    ('classical', 'classical'),
    ('orchestra', 'classical'),
    ('acoustic', 'live'),
    ('ambient', 'soft'),
    ('country', 'softrock'),
    ('hiphop', 'fullbass'),
    ('techno', 'techno'),
    ('house', 'techno'),
    ('trap', 'fullbass'),
    ('drill', 'fullbass'),
    ('reggae', 'reggae'),
    ('jazz', 'classical'),
    ('folk', 'live'),
    ('indie', 'softrock'),
    ('metal', 'rock'),
    ('rock', 'rock'),
    ('latin', 'dance'),
    ('salsa', 'dance'),
    ('dance', 'dance'),
    ('club', 'club'),
    ('party', 'party'),
    ('ballad', 'soft'),
    ('lofi', 'soft'),
    ('rnb', 'soft'),
    ('edm', 'techno'),
    ('pop', 'pop'),
    ('ska', 'ska'),
  ];
  for (final phrase in phrases) {
    if (text.contains(' ${phrase.$1} ')) return phrase.$2;
  }
  return null;
}

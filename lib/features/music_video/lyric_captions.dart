import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';

enum LyricSync { word, line, hidden }

final RegExp _sectionTag = RegExp(r'\[[^\]]*\]');

String stripSectionTags(String raw) {
  return raw.replaceAll(_sectionTag, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

LyricSync lyricSyncFor({
  required List<AlignedWord> words,
  double? confidence,
}) {
  if (words.isEmpty) return LyricSync.hidden;
  final usable = words.where((word) => word.success && stripSectionTags(word.word).isNotEmpty);
  if (usable.length < 2) return LyricSync.hidden;
  if (usable.length / words.length < 0.5) return LyricSync.hidden;
  if (confidence != null && confidence < 0.2) return LyricSync.line;
  return LyricSync.word;
}

class LyricSyllable {
  final String text;
  final double startS;
  final double endS;

  const LyricSyllable({
    required this.text,
    required this.startS,
    required this.endS,
  });
}

class LyricLine {
  final double startS;
  final double endS;
  final List<LyricSyllable> syllables;

  const LyricLine({
    required this.startS,
    required this.endS,
    required this.syllables,
  });

  String get text => syllables.map((syllable) => syllable.text).join(' ');
}

List<LyricLine> lyricLinesFromWords(List<AlignedWord> words) {
  final lines = <LyricLine>[];
  var syllables = <LyricSyllable>[];
  var length = 0;

  void flush() {
    if (syllables.isEmpty) return;
    lines.add(LyricLine(
      startS: syllables.first.startS,
      endS: syllables.last.endS,
      syllables: List<LyricSyllable>.from(syllables),
    ));
    syllables = [];
    length = 0;
  }

  for (final word in words) {
    if (!word.success) continue;
    final parts = word.word.split('\n');
    for (var i = 0; i < parts.length; i++) {
      final text = stripSectionTags(parts[i]);
      if (text.isNotEmpty) {
        if (syllables.isNotEmpty && length + text.length > 36) flush();
        syllables.add(LyricSyllable(
          text: text,
          startS: word.startS,
          endS: word.endS < word.startS ? word.startS : word.endS,
        ));
        length += text.length + 1;
      }
      if (i < parts.length - 1) flush();
    }
  }
  flush();
  return lines;
}

String? activeLyricLine(List<AlignedWord> words, double timeSeconds) {
  final lines = lyricLinesFromWords(words);
  for (final line in lines) {
    if (timeSeconds >= line.startS && timeSeconds <= line.endS + 0.15) {
      return line.text;
    }
  }
  return null;
}

/// ASS karaoke. Word highlight uses `\k`. A weak alignment is one line at a time.
String? buildAssSubtitles({
  required List<AlignedWord> words,
  required double? confidence,
  required int playResX,
  required int playResY,
}) {
  final sync = lyricSyncFor(words: words, confidence: confidence);
  if (sync == LyricSync.hidden) return null;
  final lines = lyricLinesFromWords(words);
  if (lines.isEmpty) return null;
  final events = StringBuffer();
  for (final line in lines) {
    final start = _assTime(line.startS);
    final end = _assTime(line.endS <= line.startS ? line.startS + 0.4 : line.endS);
    final text = sync == LyricSync.word ? _karaoke(line) : _escapeAss(line.text);
    events.writeln(
      'Dialogue: 0,$start,$end,Karaoke,,0,0,0,,$text',
    );
  }
  return '''
[Script Info]
ScriptType: v4.00+
PlayResX: $playResX
PlayResY: $playResY
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Karaoke,Roboto,${_fontSize(playResY)},&H00FFFFFF,&H00B0B0B0,&H00000000,&H64000000,-1,0,0,0,100,100,0,0,1,3,1,2,48,48,56,1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
${events.toString().trim()}
''';
}

int _fontSize(int height) => height >= 1000 ? 54 : 42;

String _karaoke(LyricLine line) {
  final buffer = StringBuffer();
  for (final syllable in line.syllables) {
    final centiseconds = ((syllable.endS - syllable.startS) * 100).round().clamp(1, 10000);
    buffer.write('{\\k$centiseconds}${_escapeAss(syllable.text)} ');
  }
  return buffer.toString().trim();
}

String _escapeAss(String text) {
  return text.replaceAll(r'\', r'\\').replaceAll('{', r'\{').replaceAll('}', r'\}');
}

String _assTime(double seconds) {
  final safe = seconds < 0 ? 0.0 : seconds;
  final totalCs = (safe * 100).round();
  final cs = totalCs % 100;
  final totalSeconds = totalCs ~/ 100;
  final s = totalSeconds % 60;
  final m = (totalSeconds ~/ 60) % 60;
  final h = totalSeconds ~/ 3600;
  return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}.${cs.toString().padLeft(2, '0')}';
}

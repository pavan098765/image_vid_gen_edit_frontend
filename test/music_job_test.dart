import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/job_model.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';

void main() {
  final sample = {
    'action': 'song',
    'phase': 'first_track',
    'label': 'First version ready',
    'variant': 'V6',
    'easy': true,
    'instrumental': false,
    'commercial_rights': true,
    'task_id': 'song-task-id',
    'tracks': [
      {
        'id': 'audio-1',
        'title': 'Starry Night Dreams',
        'lyrics': '[Verse]\nhello',
        'tags': 'nostalgic, acoustic',
        'duration': 198.44,
        'audio_url': 'https://example.com/song.mp3',
        'stream_url': 'https://example.com/stream',
        'cover_url': 'https://example.com/cover.jpg',
      }
    ],
    'lyrics': [
      {'title': 'Starry Night Dreams', 'text': '[Verse]\nhello'}
    ],
    'lyrics_used': 0,
    'covers': <String>[],
  };

  test('parses music payload and plays the finished file before the stream', () {
    final music = MusicResult.fromJson(sample);
    expect(music.phase, 'first_track');
    expect(music.commercialRights, isTrue);
    expect(music.tracks, hasLength(1));
    expect(music.tracks.first.playUrl, 'https://example.com/song.mp3');
    expect(music.tracks.first.isStreaming, isFalse);
    expect(music.lyrics.first.title, 'Starry Night Dreams');
    expect(music.statusLine, 'First version ready');
  });

  test('play url uses the stream until the full file arrives', () {
    final streaming = MusicTrack.fromJson({
      'id': 'a',
      'title': 'T',
      'stream_audio_url': 'https://stream',
      'image_url': 'https://cover',
      'prompt': '[Verse]\nline one\nline two',
      'duration': 12,
    });
    expect(streaming.playUrl, 'https://stream');
    expect(streaming.isStreaming, isTrue);
    expect(streaming.coverUrl, 'https://cover');
    expect(streaming.lyrics, contains('[Verse]'));

    final ready = streaming.absorb(MusicTrack.fromJson({
      'id': 'a',
      'title': 'T',
      'audio_url': 'https://audio',
      'lyrics': '[Verse]\nline one',
    }));
    expect(ready.playUrl, 'https://audio');
    expect(ready.isStreaming, isFalse);
    expect(ready.lyrics, contains('line two'));
  });

  test('credit table matches the studio spec', () {
    expect(sunoV6CreditCost(action: 'song'), 65);
    expect(sunoV6CreditCost(action: 'sounds'), 15);
    expect(sunoV6CreditCost(action: 'replace'), 65);
    expect(sunoV6CreditCost(action: 'lyrics'), 20);
    expect(sunoV6CreditCost(action: 'covers'), 40);
    expect(sunoV6CreditCost(action: 'video'), 80);
    expect(sunoV6CreditCost(action: 'persona'), 40);
    expect(sunoV6CreditCost(action: 'stems'), 80);
    expect(sunoV6CreditCost(action: 'stems', stemType: 'split_stem'), 160);
    expect(
      sunoV6CreditCost(action: 'stems', stemType: 'split_stem_advanced'),
      120,
    );
  });

  test('prefer richer music keeps the later phase with tracks', () {
    final thin = {
      'phase': 'writing_lyrics',
      'lyrics': [
        {'title': 'A', 'text': 'hi'}
      ],
    };
    final rich = preferRicherMusic(thin, sample);
    expect(rich?['phase'], 'first_track');
    expect((rich?['tracks'] as List).length, 1);
  });

  test('job round-trip keeps music', () {
    final job = JobModel(
      jobId: 'job-suno',
      title: 'Starry Night Dreams',
      model: kSunoV6ModelId,
      outputType: 'audio',
      capabilityId: 'create_music',
      music: sample,
    );
    final restored = JobModel.fromJson(job.toJson());
    expect(restored.model, kSunoV6ModelId);
    expect(restored.usesKieCloud, isTrue);
    expect(MusicResult.fromJson(restored.music!).tracks.first.id, 'audio-1');
  });

  test('follow-up merge keeps song tracks and adds covers', () {
    final song = MusicResult.fromJson(sample);
    final covers = MusicResult.fromJson({
      'action': 'covers',
      'phase': 'complete',
      'covers': ['https://example.com/c1.png', 'https://example.com/c2.png'],
    });
    final merged = song.mergeFollowUp(covers);
    expect(merged.tracks, hasLength(1));
    expect(merged.covers, hasLength(2));
    expect(merged.taskId, 'song-task-id');
  });

  test('a later poll keeps the longer lyrics and adds the file', () {
    final early = {
      'phase': 'first_track',
      'tracks': [
        {
          'id': 'audio-1',
          'title': 'Starry Night Dreams',
          'stream_url': 'https://example.com/stream',
          'lyrics': '[Verse]\nhello\n[Chorus]\nstay',
        }
      ],
    };
    final later = {
      'phase': 'complete',
      'tracks': [
        {
          'id': 'audio-1',
          'title': 'Starry Night Dreams',
          'audio_url': 'https://example.com/song.mp3',
          'lyrics': '[Verse]\nhello',
        },
        {
          'id': 'audio-2',
          'title': 'Starry Night Dreams 2',
          'audio_url': 'https://example.com/song-b.mp3',
        }
      ],
    };
    final merged = MusicResult.fromJson(preferRicherMusic(early, later)!);
    expect(merged.phase, 'complete');
    expect(merged.tracks, hasLength(2));
    expect(merged.tracks.first.playUrl, 'https://example.com/song.mp3');
    expect(merged.tracks.first.isStreaming, isFalse);
    expect(merged.tracks.first.lyrics, contains('[Chorus]'));
  });

  test('two versions that share a title stay separate', () {
    final current = MusicResult.fromJson({
      'action': 'song',
      'tracks': [
        {'id': 'audio-a', 'title': 'Same Song', 'audio_url': 'https://example.com/a.mp3'},
        {'id': 'audio-b', 'title': 'Same Song', 'stream_audio_url': 'https://example.com/b-stream'},
      ],
    });
    final incoming = MusicResult.fromJson({
      'action': 'song',
      'tracks': [
        {'id': 'audio-a', 'title': 'Same Song', 'audio_url': 'https://example.com/a-final.mp3'},
        {'id': 'audio-b', 'title': 'Same Song', 'audio_url': 'https://example.com/b-final.mp3'},
      ],
    });

    final merged = current.absorb(incoming);

    expect(merged.tracks, hasLength(2));
    expect(merged.tracks[0].id, 'audio-a');
    expect(merged.tracks[0].playUrl, 'https://example.com/a-final.mp3');
    expect(merged.tracks[1].id, 'audio-b');
    expect(merged.tracks[1].playUrl, 'https://example.com/b-final.mp3');
    expect(merged.tracks[1].isStreaming, isFalse);
  });

  test('a track with no id merges only when its title is unique', () {
    final current = MusicResult.fromJson({
      'tracks': [
        {'id': 'audio-a', 'title': 'Only Song', 'audio_url': 'https://example.com/a.mp3'},
      ],
    });
    final incoming = MusicResult.fromJson({
      'tracks': [
        {'title': 'Only Song', 'lyrics': '[Verse]\nkept'},
      ],
    });

    final merged = current.absorb(incoming);

    expect(merged.tracks, hasLength(1));
    expect(merged.tracks.single.id, 'audio-a');
    expect(merged.tracks.single.lyrics, contains('kept'));
  });

  test('a later file replaces an earlier audio url and reads the cover', () {
    final early = MusicTrack.fromJson({
      'id': 'audio-1',
      'audio_url': 'https://example.com/partial.mp3',
      'stream_audio_url': 'https://example.com/stream',
      'duration': 12,
    });
    final ready = early.absorb(MusicTrack.fromJson({
      'id': 'audio-1',
      'audio_url': 'https://example.com/song.mp3',
      'stream_audio_url': 'https://example.com/stream',
      'image_url': 'https://example.com/cover.jpeg',
      'duration': 198.44,
    }));
    expect(ready.playUrl, 'https://example.com/song.mp3');
    expect(ready.isStreaming, isFalse);
    expect(ready.coverUrl, 'https://example.com/cover.jpeg');
    expect(ready.knownDuration, const Duration(milliseconds: 198440));

    final music = MusicResult.fromJson({
      'action': 'song',
      'covers': [
        {'url': 'https://example.com/extra.png'},
      ],
    });
    expect(music.covers, ['https://example.com/extra.png']);
  });
}

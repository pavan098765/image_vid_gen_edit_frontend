import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/song_equalizer_preset.dart';

void main() {
  test('a genre phrase picks a known curve', () {
    expect(
      presetForSongText(title: 'Night', style: 'soft rock ballad', tags: '', lyrics: ''),
      'softrock',
    );
    expect(
      presetForSongText(title: 'Mumbai', style: '', tags: 'punjabi bhangra', lyrics: ''),
      'party',
    );
    expect(
      presetForSongText(title: 'Fill That Box With Joy', style: '', tags: '', lyrics: ''),
      isNull,
    );
  });
}

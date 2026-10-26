import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/safe_video_view.dart';
import 'package:video_player/video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a missing player is not a ready frame', () {
    expect(videoFrameIsReady(null), isFalse);
    expect(videoNeedsRestart(null), isFalse);
  });

  testWidgets('a zero-size video shows the fallback and does not throw', (
    tester,
  ) async {
    final controller = VideoPlayerController.file(
      File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}kala_missing_preview.mp4',
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeVideoView(
            controller: controller,
            fallback: const Text('preview unavailable'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('preview unavailable'), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(tester.takeException(), isNull);
    expect(videoFrameIsReady(controller), isFalse);
  });
}

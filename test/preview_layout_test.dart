import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/backlit_glass.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/result_manager/before_after_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('still backlight builds without a drifting clock', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: BacklitWash(forceDark: true, drift: false)),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(BacklitWash), findsOneWidget);
  });

  testWidgets(
    'image result preview keeps a finite layout and its app bar',
    (tester) async {
      final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}kala_preview_layout.png',
      );
      file.writeAsBytesSync(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        ),
      );
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: BeforeAfterPreviewPage(resultFile: file, originalFile: file),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Result'), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

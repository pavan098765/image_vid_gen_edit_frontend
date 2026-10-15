import 'dart:io';

/// Native compositor (Media3 / AVFoundation) is Android, iOS, and macOS.
/// Windows and Linux keep the FFmpeg export path.
class NativeCompositor {
  NativeCompositor._();

  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
}

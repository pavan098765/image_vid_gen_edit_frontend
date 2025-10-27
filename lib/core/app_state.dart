// lib/core/app_state.dart
import 'package:flutter/foundation.dart';

/// Global app-level selected index for the bottom navigation.
/// Any page can set this to switch the active tab.
final ValueNotifier<int> selectedIndexNotifier = ValueNotifier<int>(0);

/// Helpful constants for default tab indices.
/// Adjust if you reorder the tabs in main.dart.
class AppTabs {
  static const int editor = 0;
  static const int aiTools = 1;
  static const int video = 2;
  static const int credits = 3;
  static const int settings = 4;
}

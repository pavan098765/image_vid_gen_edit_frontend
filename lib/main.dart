// lib/main.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_vid_gen_edit_frontend/core/services/polling_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme/app_theme.dart';
import 'core/app_state.dart';
import 'core/services/notification_service.dart';

import 'features/editor/editor_page.dart';
import 'features/ai_tools/ai_tools_page.dart';
import 'features/ai_tools/generic_tool_page.dart';
import 'features/video_gen/video_gen_page.dart';
import 'features/credits/credits_page.dart';
import 'features/settings/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ Initialize the NotificationService
  // ✅ Initialize the NotificationService
  await NotificationService.initialize(onTap: (response) async {
    if (response.payload != null && response.payload!.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();

      // 🧠 Restore last used tool config
      final lastModel = prefs.getString("last_model");
      final lastParamsStr = prefs.getString("last_model_params");
      final lastInputsStr = prefs.getString("last_model_inputs");
      final lastTitle = prefs.getString("last_model_title") ?? "AI Tool";

      GenericToolConfig? config;
      if (lastModel != null) {
        config = GenericToolConfig(
          title: lastTitle,
          model: lastModel,
          params: lastParamsStr != null ? jsonDecode(lastParamsStr) : const {},
          inputs: lastInputsStr != null
              ? List<Map<String, dynamic>>.from(jsonDecode(lastInputsStr))
              : const [],
          outputType: "image",
        );
      }

      // ✅ 1️⃣ Check if PollingService already cached result
      final cached = prefs.getString("cached_result_bytes");
      if (cached != null && cached.isNotEmpty && config != null) {
        debugPrint("✅ Found cached result — opening instantly");
        runApp(
          AICreativeStudio(
            initialJobId: response.payload!,
            restoredConfig: config,
          ),
        );
        return;
      }

      // ✅ 2️⃣ If cached not found, fallback to pending URL
      final pendingUrl = prefs.getString("pending_download_url");
      if (pendingUrl != null && pendingUrl.isNotEmpty && config != null) {
        debugPrint("ℹ️ Using pending download URL from prefs");
        runApp(
          AICreativeStudio(
            initialJobId: response.payload!,
            restoredConfig: config,
          ),
        );
        return;
      }

      // ✅ 3️⃣ If nothing found, load normally
      runApp(const AICreativeStudio());
    } else {
      runApp(const AICreativeStudio());
    }
  });

  PollingService.instance.start();
  runApp(const AICreativeStudio());
}

class AICreativeStudio extends StatelessWidget {
  final String? initialJobId;
  final GenericToolConfig? restoredConfig;

  const AICreativeStudio({
    super.key,
    this.initialJobId,
    this.restoredConfig,
  });

  /// Main app pages
  final List<Widget> _pages = const [
    EditorPage(),
    VideoGenPage(),
    AiToolsPage(),
    CreditsPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    // ✅ Case 1: Opened from notification (restore job)
    if (initialJobId != null &&
        initialJobId!.isNotEmpty &&
        restoredConfig != null) {
      return MaterialApp(
        title: 'AI Creative Studio',
        theme: AppTheme.darkTheme,
        debugShowCheckedModeBanner: false,
        home: GenericToolPage(
          config: restoredConfig!,
          restoreJobId: initialJobId,
        ),
      );
    }

    // ✅ Case 2: Normal app launch
    return MaterialApp(
      title: 'AI Creative Studio',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder<int>(
            valueListenable: selectedIndexNotifier,
            builder: (_, currentIndex, __) {
              return IndexedStack(
                index: currentIndex,
                children: _pages,
              );
            },
          ),
        ),
        bottomNavigationBar: ValueListenableBuilder<int>(
          valueListenable: selectedIndexNotifier,
          builder: (_, currentIndex, __) {
            return NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (i) => selectedIndexNotifier.value = i,
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.photo_library), label: "Photo"),
                NavigationDestination(icon: Icon(Icons.movie), label: "Video"),
                NavigationDestination(
                    icon: Icon(Icons.auto_awesome), label: "AI Tools"),
                NavigationDestination(
                    icon: Icon(Icons.monetization_on), label: "Credits"),
                NavigationDestination(
                    icon: Icon(Icons.settings), label: "Settings"),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/exit_app_dialog.dart';

import 'studio_screens.dart';
import 'studio_session.dart';
import 'workflow_models.dart';

class StudioPage extends StatefulWidget {
  final String? initialExploreJobId;
  final String? initialAssetKey;
  final String? initialLocalPath;
  final int? initialSceneIndex;

  const StudioPage({
    super.key,
    this.initialExploreJobId,
    this.initialAssetKey,
    this.initialLocalPath,
    this.initialSceneIndex,
  });

  @override
  State<StudioPage> createState() => _StudioPageState();
}

class _StudioPageState extends State<StudioPage> {
  final _session = StudioSession();
  final _navKey = GlobalKey<NavigatorState>();
  List<WorkflowSpec> _workflows = const [];

  @override
  void initState() {
    super.initState();
    final path = widget.initialLocalPath;
    if (path != null && path.isNotEmpty) {
      _session.pendingFiles = [path];
    }
    loadWorkflows().then((value) {
      if (!mounted) return;
      setState(() => _workflows = value);
      final clip = widget.initialLocalPath;
      if (clip != null && clip.isNotEmpty) {
        final cut = value.where((w) => w.id == 'cut_my_clips');
        if (cut.isNotEmpty) {
          _session.open(cut.first);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navKey.currentState?.push(
              MaterialPageRoute(builder: (_) => const StudioSetupPage()),
            );
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (popShellOverlay(context)) return;
        if (selectedIndexNotifier.value != AppTabs.studio) return;
        final nav = _navKey.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
          return;
        }
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => const ConfirmExitAppDialog(),
        );
        if (leave == true) SystemNavigator.pop();
      },
      child: StudioScope(
        session: _session,
        child: Navigator(
          key: _navKey,
          onGenerateRoute: (settings) {
            return MaterialPageRoute(
              builder: (_) => StudioShelf(workflows: _workflows),
            );
          },
        ),
      ),
    );
  }
}

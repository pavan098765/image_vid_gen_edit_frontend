import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/ad_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/media_source_picker_sheet.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/themed_native_ad.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/image_editor/image_encode.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/image_editor/image_history_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/image_editor/image_layer_list_sheet.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/image_editor/image_text_style_store.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/image_editor/kala_image_editor_configs.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/media_editor/editor_tab_launch.dart';
import 'package:kala_ai_create_images_videos_with_ai/features/video_editor/video_editor_page.dart';

enum ImageEditorInitialTool { none, text, crop, sticker }

class EditorPage extends StatefulWidget {
  /// Whether to show the AppBar. Set to false when nested in MediaEditorPage.
  final bool showAppBar;
  final File? initialImage;
  final File? stickerImage;
  final ImageEditorInitialTool initialTool;
  final String? historyId;

  /// When false, this page is the hidden side of the photo/video toggle and
  /// must not answer the system back button.
  final bool handlesSystemBack;

  const EditorPage({
    super.key,
    this.showAppBar = true,
    this.initialImage,
    this.stickerImage,
    this.initialTool = ImageEditorInitialTool.none,
    this.historyId,
    this.handlesSystemBack = true,
  });

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage>
    with SingleTickerProviderStateMixin {
  Uint8List? _exportedImage;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  final AdService _adService = AdService();

  DateTime? _lastEditCompleteAt;
  bool _isSaving = false;

  /// GlobalKey to access ProImageEditor state for undo/redo/done.
  /// Replaced on every open so a previous photo cannot stay on screen.
  GlobalKey<ProImageEditorState> _editorKey = GlobalKey<ProImageEditorState>();

  ImportStateHistory? _importHistory;
  bool _openedInitialTool = false;
  bool _placedSticker = false;
  late String _historyId;
  Uint8List? _originalBytes;
  bool _holdingBeforeAfter = false;
  bool _allowRoutePop = false;
  bool _historyReady = false;
  bool _returnToResultManager = false;
  int _restoreTabIndex = 0;
  int _seenLaunchId = 0;
  int _openGeneration = 0;
  bool _replacingImage = false;
  bool _exitPromptOpen = false;
  String _frameGuide = 'off';
  ImageSaveFormat _saveFormat = ImageSaveFormat.jpeg;
  int _maxEdge = 0;
  mui.TextStyle? _savedTextStyle;
  Timer? _holdTimer;
  late final AnimationController _exportGlow;

  late final ProImageEditorCallbacks _callbacks = ProImageEditorCallbacks(
    onImageEditingComplete: (bytes) async {
      debugPrint("✅ Image editing completed");
    },
    onCloseEditor: (_) {}, // ✅ keep minimal
  );

  @override
  void initState() {
    super.initState();
    _exportGlow = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    // Listen for ad-free status changes to hide/show native ads
    isAdFreeNotifier.addListener(_onAdFreeStatusChanged);
    editorTabLaunchNotifier.addListener(_onEditorTabLaunch);
    _historyId = widget.historyId ??
        ImageHistoryStore.historyIdFor(image: widget.initialImage);
    _historyReady = widget.initialImage == null;
    ImageTextStyleStore.load().then((style) {
      if (!mounted) return;
      setState(() {
        _savedTextStyle = mui.TextStyle(
          fontFamily: style.family,
          fontSize: style.size,
          color: mui.Color(style.color.toARGB32()),
        );
      });
    });
    final initial = widget.initialImage;
    if (initial != null && initial.existsSync()) {
      _selectedImage = initial;
      _originalBytes = initial.readAsBytesSync();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _importHistory = await ImageHistoryStore.load(
          _historyId,
          widgetLoader: ImageHistoryStore.widgetLoader,
        );
        if (mounted) {
          setState(() => _historyReady = true);
          _openRequestedToolOnce();
        }
      });
    }
  }

  Future<void> _persistHistory() async {
    final state = _editorKey.currentState;
    if (state == null) return;
    try {
      final hist = await state.exportStateHistory();
      final json = await hist.toJson();
      await ImageHistoryStore.save(_historyId, json);
    } catch (e) {
      debugPrint('Image editor history save failed: $e');
    }
  }

  void _openRequestedToolOnce() {
    if (_openedInitialTool) return;
    _openedInitialTool = true;
    final state = _editorKey.currentState;
    if (state == null) return;
    switch (widget.initialTool) {
      case ImageEditorInitialTool.text:
        state.openTextEditor();
        break;
      case ImageEditorInitialTool.crop:
        state.openCropRotateEditor();
        break;
      case ImageEditorInitialTool.sticker:
        state.openStickerEditor();
        break;
      case ImageEditorInitialTool.none:
        break;
    }
    _placeStickerIfNeeded();
  }

  void _placeStickerIfNeeded() {
    if (_placedSticker) return;
    final sticker = widget.stickerImage;
    final state = _editorKey.currentState;
    if (sticker == null || !sticker.existsSync() || state == null) return;
    _placedSticker = true;
    state.addLayer(
      WidgetLayer(
        widget: Image.file(sticker, fit: BoxFit.contain),
        exportConfigs: WidgetLayerExportConfigs(id: sticker.path),
      ),
    );
  }

  void _onEditorTabLaunch() {
    final launch = editorTabLaunchNotifier.value;
    if (launch == null || launch.id == _seenLaunchId) return;
    _seenLaunchId = launch.id;
    final image = launch.image;
    if (image == null || !image.existsSync()) {
      _returnToResultManager = false;
      return;
    }
    _replacingImage = true;
    _returnToResultManager = launch.returnToResultManager;
    _restoreTabIndex = launch.restoreTabIndex;
    _historyId = launch.historyId ?? ImageHistoryStore.historyIdFor(image: image);
    _stopExportGlow();
    setState(() {
      _editorKey = GlobalKey<ProImageEditorState>();
      _selectedImage = image;
      _exportedImage = null;
      _lastEditCompleteAt = null;
      _openedInitialTool = false;
      _placedSticker = false;
      _historyReady = false;
      _originalBytes = null;
      _importHistory = null;
    });
    _loadOpenedImage(image);
  }

  Future<void> _loadOpenedImage(File image) async {
    final generation = ++_openGeneration;
    Uint8List? bytes;
    ImportStateHistory? history;
    try {
      bytes = await image.readAsBytes();
      history = await ImageHistoryStore.load(
        _historyId,
        widgetLoader: ImageHistoryStore.widgetLoader,
      );
    } catch (e) {
      debugPrint('Image editor open failed: $e');
    }
    if (!mounted || generation != _openGeneration) return;
    setState(() {
      _originalBytes = bytes;
      _importHistory = history;
      _historyReady = true;
      _replacingImage = false;
    });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _exportGlow.dispose();
    editorTabLaunchNotifier.removeListener(_onEditorTabLaunch);
    isAdFreeNotifier.removeListener(_onAdFreeStatusChanged);
    super.dispose();
  }

  void _startExportGlow() {
    if (!_exportGlow.isAnimating) {
      _exportGlow.repeat(reverse: true);
    }
  }

  void _stopExportGlow() {
    _exportGlow.stop();
    _exportGlow.value = 0;
  }

  Widget _highlightExport(Widget child) {
    if (_exportedImage == null) return child;
    final glow = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _exportGlow,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_exportGlow.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.28 + 0.55 * t),
                blurRadius: 8 + 16 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: child,
    );
  }

  Future<bool?> _pickSaveOptions() async {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) {
        var format = _saveFormat;
        var edge = _maxEdge;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Save format',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in ImageSaveFormat.values)
                        ChoiceChip(
                          label: Text(f.name.toUpperCase()),
                          selected: format == f,
                          onSelected: (_) => setLocal(() => format = f),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('Max edge'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in const [0, 1080, 1440, 2048])
                        ChoiceChip(
                          label: Text(e == 0 ? 'Original' : '$e'),
                          selected: edge == e,
                          onSelected: (_) => setLocal(() => edge = e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _saveFormat = format;
                          _maxEdge = edge;
                        });
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  void _onAdFreeStatusChanged() {
    // Rebuild to hide/show native ads when ad-free status changes
    if (mounted) setState(() {});
  }

  Future<void> _pickImage() async {
    try {
      final source = await _showSourcePickerSheet();
      if (source == null) return;

      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdk = androidInfo.version.sdkInt;
        if (sdk <= 32) {
          final status = await Permission.storage.request();
          if (!status.isGranted) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Storage permission denied')),
              );
            }
            return;
          }
        } else {
          final photos = await Permission.photos.request();
          if (!photos.isGranted) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Photo access permission denied')),
              );
            }
            return;
          }
        }
      }

      File? safeFile;

      if (source == ImageSource.camera) {
        final XFile? cameraFile = await _picker.pickImage(
            source: ImageSource.camera, imageQuality: 100);
        if (cameraFile == null) return;

        final tempDir = await getTemporaryDirectory();
        final safePath = '${tempDir.path}/${cameraFile.name}';
        safeFile = await File(cameraFile.path).copy(safePath);
      } else {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: true,
        );

        if (result == null || result.files.isEmpty) return;
        final file = result.files.single;

        final tempDir = await getTemporaryDirectory();
        final safePath = '${tempDir.path}/${file.name}';
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        safeFile = await File(safePath).writeAsBytes(bytes, flush: true);
      }

      try {
        await decodeImageFromList(await safeFile.readAsBytes());
      } catch (_) {
        debugPrint('⚠️ Failed to decode picked image, file may be corrupted');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Could not open image — file corrupt.')),
          );
        }
        return;
      }

      if (!mounted) return;
      _historyId = ImageHistoryStore.historyIdFor(image: safeFile);
      _originalBytes = await safeFile.readAsBytes();
      _importHistory = await ImageHistoryStore.load(
        _historyId,
        widgetLoader: ImageHistoryStore.widgetLoader,
      );
      if (!mounted) return;
      _stopExportGlow();
      setState(() {
        _selectedImage = safeFile;
        _exportedImage = null;
        _lastEditCompleteAt = null;
        _openedInitialTool = false;
        _placedSticker = false;
        _historyReady = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openRequestedToolOnce();
      });

      debugPrint('✅ Image selected safely: ${safeFile.path}');
    } catch (e, st) {
      debugPrint('❌ Error picking image: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<ImageSource?> _showSourcePickerSheet() {
    return showMediaSourcePickerBottomSheet(
      context,
      title: 'Add a photo',
    );
  }

  Future<bool> _confirmExitEditing() async {
    if (_exitPromptOpen) return false;
    _exitPromptOpen = true;
    try {
      return (await showDialog<bool>(
            context: context,
            builder: (_) => const _ConfirmExitDialog(),
          )) ??
          false;
    } finally {
      _exitPromptOpen = false;
    }
  }

  /// Tool pages share [onCloseEditor] with the main editor. Their back button
  /// must pop that page. [includeRootRoute] is only for that button: system
  /// back must not pop the editor route itself.
  bool _closeOpenTool({bool includeRootRoute = false}) {
    final editorContext = _editorKey.currentContext;
    if (editorContext == null || !editorContext.mounted) return false;

    NavigatorState? nested;
    void visit(Element element) {
      if (element is StatefulElement && element.state is NavigatorState) {
        final navigator = element.state as NavigatorState;
        if (navigator.canPop()) nested = navigator;
      }
      element.visitChildren(visit);
    }

    editorContext.visitChildElements(visit);
    if (nested != null) {
      nested!.pop();
      return true;
    }
    if (!includeRootRoute) return false;

    final root = Navigator.of(editorContext);
    if (!root.canPop()) return false;
    root.pop();
    return true;
  }

  void _clearOpenImage() {
    if (!mounted) return;
    _openGeneration++;
    _replacingImage = false;
    _stopExportGlow();
    setState(() {
      _selectedImage = null;
      _exportedImage = null;
      _lastEditCompleteAt = null;
      _historyReady = true;
      _originalBytes = null;
      _importHistory = null;
    });
  }

  Future<void> _leaveEditor() async {
    if (!mounted || _replacingImage) return;
    _stopExportGlow();
    if (_returnToResultManager) {
      final tab = _restoreTabIndex;
      final generation = _openGeneration;
      _returnToResultManager = false;
      returnEditorSessionToResultManager(
        restoreTabIndex: tab,
        onCovered: () {
          if (generation != _openGeneration) return;
          _clearOpenImage();
        },
      );
      return;
    }
    if (Navigator.of(context).canPop()) {
      _allowRoutePop = true;
      Navigator.of(context).pop();
      return;
    }
    _clearOpenImage();
  }

  Future<bool> _handleSystemBack() async {
    if (popShellOverlay(context)) return false;
    if (!widget.handlesSystemBack) return false;
    if (_allowRoutePop) return true;
    if (selectedIndexNotifier.value != AppTabs.editor) {
      final current = ModalRoute.of(context)?.isCurrent ?? false;
      if (current && Navigator.of(context).canPop()) return true;
      return false;
    }
    if (_selectedImage != null && _closeOpenTool()) return false;
    if (selectedIndexNotifier.value == AppTabs.editor &&
        _returnToResultManager &&
        _selectedImage != null) {
      if (_exportedImage == null) {
        final ok = await _confirmExitEditing();
        if (!ok) return false;
      }
      await _leaveEditor();
      return false;
    }
    if (Navigator.of(context).canPop()) {
      if (_selectedImage != null && _exportedImage == null) {
        final ok = await _confirmExitEditing();
        if (!ok) return false;
      }
      _stopExportGlow();
      _allowRoutePop = true;
      return true;
    }
    final ok = await _confirmExitApp();
    if (ok) {
      SystemNavigator.pop();
    }
    return false;
  }

  Future<bool> _confirmExitApp() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmExitAppDialog(),
        )) ??
        false;
  }

  Future<void> _onExportPressed() async {
    if (_exportedImage == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No exported image available. Please finish editing.'),
        ),
      );
      return;
    }

    if (_isSaving) return;

    final options = await _pickSaveOptions();
    if (options == null) return;

    setState(() => _isSaving = true);

    try {
      // Show rewarded ad before allowing export
      final adCompleted = await _showExportAd();

      if (!adCompleted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(LucideIcons.alertCircle, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                      child: Text('Please watch the ad to save your image')),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }

      // Ad completed - proceed with save
      final encoded = encodeEditedImage(
        _exportedImage!,
        format: _saveFormat,
        maxEdge: _maxEdge,
      );
      final savedPath = await FileService.saveFile(
        context,
        encoded,
        extension: extensionFor(_saveFormat),
      );
      if (savedPath != null) {
        await ImageHistoryStore.copyTo(
          _historyId,
          ImageHistoryStore.historyIdFor(image: File(savedPath)),
        );
      }
      if (savedPath != null) {
        debugPrint('✅ Image saved at: $savedPath');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveAsClip() async {
    final bytes = _exportedImage;
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final png = File('${dir.path}/still_${DateTime.now().millisecondsSinceEpoch}.png');
    await png.writeAsBytes(encodeEditedImage(bytes, format: ImageSaveFormat.png));
    final out = '${dir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final session = await FFmpegKit.execute(
      '-y -loop 1 -t 4 -i "${png.path}" -vf scale=trunc(iw/2)*2:trunc(ih/2)*2 -c:v libx264 -pix_fmt yuv420p "$out"',
    );
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code) || !File(out).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not make a clip from this photo.')),
        );
      }
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoEditorPage(initialVideoPath: out),
      ),
    );
  }

  /// Shows a rewarded ad for export gate
  /// Returns true if ad was completed (or skipped for ad-free users), false otherwise
  Future<bool> _showExportAd() async {
    if (!shouldRequireHeavyTierRewardedAd()) {
      debugPrint('✅ User is not on heavy ad tier, skipping export ad');
      return true;
    }

    // Pre-load ad if not ready
    if (!_adService.isAdReadyNotifier.value) {
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
                SizedBox(width: 12),
                Text('Loading ad...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      await _adService.loadRewardedAd();

      // Wait for ad to load (with timeout)
      for (int i = 0; i < 10; i++) {
        if (_adService.isAdReadyNotifier.value) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Clear the loading snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
      }

      if (!_adService.isAdReadyNotifier.value) {
        // Ad failed to load - allow export anyway (better UX)
        debugPrint('⚠️ Ad failed to load, allowing export anyway');
        return true;
      }
    }

    // Show the ad
    return await _adService.showAdForFeatureGate();
  }

  PreferredSizeWidget _buildEditorAppBar() {
    final cs = Theme.of(context).colorScheme;
    final actions = <Widget>[
      if (_selectedImage != null)
        PopupMenuButton<String>(
          tooltip: 'Frame',
          icon: const Icon(Icons.crop_free),
          onSelected: (id) => setState(() => _frameGuide = id),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'off', child: Text('No frame')),
            PopupMenuItem(value: '9:16', child: Text('Story 9:16')),
            PopupMenuItem(value: '4:5', child: Text('4:5')),
            PopupMenuItem(value: '1:1', child: Text('Square 1:1')),
          ],
        ),
      if (_selectedImage != null)
        IconButton(
          icon: const Icon(Icons.layers_outlined),
          tooltip: 'Layers',
          onPressed: () => showImageLayerListSheet(context, _editorKey),
        ),
      if (_selectedImage != null)
        IconButton(
          icon: const Icon(Icons.blur_on),
          tooltip: 'Hide',
          onPressed: () => _editorKey.currentState?.openPaintEditor(),
        ),
      if (_selectedImage != null)
        IconButton(
          icon: const Icon(Icons.photo_library_outlined),
          tooltip: 'Select Image',
          onPressed: _pickImage,
        ),
      if (_exportedImage != null)
        _isSaving
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _highlightExport(
                IconButton(
                  icon: const Icon(Icons.save_alt),
                  tooltip: 'Save Image',
                  onPressed: _onExportPressed,
                ),
              ),
    ];

    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Material(
        color: cs.surface,
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: kToolbarHeight,
            child: Row(
              children: [
                const BackButton(),
                const Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: KalaLogoWithIcon(logoHeight: 26, fontSize: 18),
                    ),
                  ),
                ),
                if (actions.isNotEmpty)
                  Flexible(
                    flex: 2,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: actions,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        appBar: widget.showAppBar ? _buildEditorAppBar() : null,
        body: Stack(
          children: [
            if (_selectedImage == null)
              _buildEmptyStateWithAd(context)
            else if (!_historyReady)
              const Center(child: CircularProgressIndicator())
            else
              Listener(
                onPointerDown: (_) {
                  _holdTimer?.cancel();
                  _holdTimer = Timer(const Duration(milliseconds: 420), () {
                    if (mounted) {
                      setState(() => _holdingBeforeAfter = true);
                    }
                  });
                },
                onPointerUp: (_) {
                  _holdTimer?.cancel();
                  setState(() => _holdingBeforeAfter = false);
                },
                onPointerCancel: (_) {
                  _holdTimer?.cancel();
                  setState(() => _holdingBeforeAfter = false);
                },
                child: Stack(
                  children: [
                    ProImageEditor.file(
                _selectedImage!,
                key: _editorKey,
                configs: kalaImageEditorConfigs(
                  context,
                  stickerSeed: widget.stickerImage,
                  initStateHistory: _importHistory,
                  frameGuides: kalaFrameGuides(_frameGuide),
                  textStyle: _savedTextStyle,
                ),
                callbacks: _callbacks.copyWith(
                  // inside the callbacks.copyWith(...)
                  onImageEditingComplete: (bytes) async {
                    if (!mounted) return;
                    await _persistHistory();
                    _lastEditCompleteAt = DateTime.now();

                    // Keep the timestamp for a short debounce window; then clear it so future closes behave normally.
                    Timer(const Duration(milliseconds: 900), () {
                      if (mounted) _lastEditCompleteAt = null;
                    });

                    setState(() => _exportedImage = bytes);
                    _startExportGlow();
                    await ImageTextStyleStore.save(
                      family: 'Inter',
                      size: 24,
                      color: Colors.white,
                      background: Colors.transparent,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Editing complete. Tap the glowing Save button to export.',
                        ),
                        action: SnackBarAction(
                          label: 'Save',
                          onPressed: _onExportPressed,
                        ),
                      ),
                    );
                  },

                  onCloseEditor: (mode) async {
                    if (_replacingImage) return;
                    if (mode != EditorMode.main) {
                      _closeOpenTool(includeRootRoute: true);
                      return;
                    }
                    final now = DateTime.now();

                    // If editing was just completed recently, treat this as the editor's internal close event and ignore it.
                    if (_lastEditCompleteAt != null) {
                      final diff = now.difference(_lastEditCompleteAt!);
                      if (diff.inMilliseconds < 900) {
                        debugPrint(
                            'pro_image_editor: onCloseEditor ignored — happened $diff after edit complete (internal).');
                        return;
                      }
                    }

                    // If editing is complete (_exportedImage exists), ProImageEditor already showed its
                    // internal close dialog. Just close without showing another dialog.
                    if (_exportedImage != null) {
                      debugPrint(
                          'pro_image_editor: onCloseEditor after editing complete — closing without extra dialog.');
                      await _leaveEditor();
                      return;
                    }

                    debugPrint(
                        'pro_image_editor: onCloseEditor triggered by user — showing confirm dialog.');
                    final ok = await _confirmExitEditing();
                    if (ok) {
                      await _leaveEditor();
                    } else {
                      debugPrint('❌ User cancelled exit from editor.');
                    }
                  },
                ),
              ),
                    if (_holdingBeforeAfter && _originalBytes != null)
                      Positioned.fill(
                        child: Image.memory(_originalBytes!, fit: BoxFit.contain),
                      ),
                  ],
                ),
              ),
            if (_exportedImage != null)
              Positioned(
                right: 16,
                bottom: 100,
                child: GradientButton(
                  icon: Icons.preview,
                  label: "Preview",
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            _ResultPreviewPage(imageBytes: _exportedImage!),
                      ),
                    );
                  },
                  variant: ButtonVariant.secondary,
                  size: ButtonSize.medium,
                ),
              ),
            // Action buttons when AppBar is hidden (nested in MediaEditorPage)
            if (!widget.showAppBar && _selectedImage != null)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Undo button
                    _buildActionButton(
                      icon: Icons.undo,
                      tooltip: 'Undo',
                      onPressed: () => _editorKey.currentState?.undoAction(),
                    ),
                    const SizedBox(width: 8),
                    // Redo button
                    _buildActionButton(
                      icon: Icons.redo,
                      tooltip: 'Redo',
                      onPressed: () => _editorKey.currentState?.redoAction(),
                    ),
                    const SizedBox(width: 8),
                    // Select another image button
                    _buildActionButton(
                      icon: Icons.photo_library_outlined,
                      tooltip: 'Select Image',
                      onPressed: _pickImage,
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.layers_outlined,
                      tooltip: 'Layers',
                      onPressed: () =>
                          showImageLayerListSheet(context, _editorKey),
                    ),
                    const SizedBox(width: 8),
                    _buildActionButton(
                      icon: Icons.blur_on,
                      tooltip: 'Hide',
                      onPressed: () =>
                          _editorKey.currentState?.openPaintEditor(),
                    ),
                    const SizedBox(width: 8),
                    // Tick/Done button before editing complete, Save button after
                    if (_exportedImage == null)
                      // Tick/Done button - triggers editing complete
                      _buildActionButton(
                        icon: Icons.check,
                        tooltip: 'Done Editing',
                        onPressed: () => _editorKey.currentState?.doneEditing(),
                        isPrimary: true,
                      )
                    else
                      // Save button after editing complete
                      _isSaving
                          ? Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surface
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            )
                          : Row(
                              children: [
                                _buildActionButton(
                                  icon: Icons.movie_creation_outlined,
                                  tooltip: 'Save as clip',
                                  onPressed: _saveAsClip,
                                ),
                                const SizedBox(width: 8),
                                _highlightExport(
                                  _buildActionButton(
                                    icon: Icons.save_alt,
                                    tooltip: 'Save Image',
                                    onPressed: _onExportPressed,
                                    isPrimary: true,
                                  ),
                                ),
                              ],
                            ),
                  ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: _selectedImage == null
            ? GradientButton(
                icon: Icons.add_photo_alternate_outlined,
                label: "Choose a photo",
                onPressed: _pickImage,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  /// Builds a compact action button for when AppBar is hidden
  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isPrimary ? cs.primary : cs.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(10),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 22,
            color: isPrimary ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateWithAd(BuildContext context) {
    final showAds = shouldShowNativeBannerAds();

    return Column(
      children: [
        // Native ad at top (only if not ad-free)
        if (showAds)
          const ThemedNativeAd(
            height: 260,
            useSmallTemplate: false,
          ),
        // Placeholder in remaining space - with bottom padding for FAB
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 80), // Space for FAB
            child: _buildNoImagePlaceholder(context),
          ),
        ),
      ],
    );
  }

  Widget _buildNoImagePlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [cs.surface.withValues(alpha: 0.70), cs.surface.withValues(alpha: 0.55)]
                : [cs.surface.withValues(alpha: 0.85), cs.surface.withValues(alpha: 0.70)],
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : Colors.black54).withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                size: 56, color: cs.onSurface.withValues(alpha: 0.38)),
            const SizedBox(height: 12),
            Text(
              'Choose a photo to start.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.70),
                    fontSize: 14,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// Confirm Exit Dialog (for editing session)
class _ConfirmExitDialog extends StatelessWidget {
  const _ConfirmExitDialog();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Exit editing?',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      content: Text(
        'Your unsaved changes will be lost. Exit editor?',
        style: t.bodyMedium,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        GradientButton(
          label: "Exit",
          onPressed: () => Navigator.pop(context, true),
          variant: ButtonVariant.danger,
          size: ButtonSize.small,
        ),
      ],
    );
  }
}

// Confirm Exit App Dialog (for base pages)
class _ConfirmExitAppDialog extends StatelessWidget {
  const _ConfirmExitAppDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(
              LucideIcons.logOut,
              size: 40,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Exit App?',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Are you sure you want to exit?',
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GradientButton(
                label: 'Exit',
                icon: LucideIcons.logOut,
                onPressed: () => Navigator.pop(context, true),
                variant: ButtonVariant.danger,
                size: ButtonSize.medium,
                expanded: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultPreviewPage extends StatelessWidget {
  final Uint8List imageBytes;
  const _ResultPreviewPage({Key? key, required this.imageBytes})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Preview Result')),
      backgroundColor: cs.surface,
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.memory(imageBytes),
        ),
      ),
    );
  }
}

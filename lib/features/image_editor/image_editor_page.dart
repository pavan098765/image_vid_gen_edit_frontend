import 'dart:async';
import 'dart:typed_data';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/ad_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/file_service.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/theme/app_theme.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/gradient_button.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/widgets/themed_native_ad.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:path_provider/path_provider.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  Uint8List? _exportedImage;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  final AdService _adService = AdService();

  DateTime? _lastEditCompleteAt;
  bool _isSaving = false;

  late final ProImageEditorConfigs _configs = const ProImageEditorConfigs();

  late final ProImageEditorCallbacks _callbacks = ProImageEditorCallbacks(
    onImageEditingComplete: (bytes) async {
      debugPrint("✅ Image editing completed");
    },
    onCloseEditor: (_) {}, // ✅ keep minimal
  );
  
  @override
  void initState() {
    super.initState();
    // Listen for ad-free status changes to hide/show native ads
    isAdFreeNotifier.addListener(_onAdFreeStatusChanged);
  }
  
  @override
  void dispose() {
    isAdFreeNotifier.removeListener(_onAdFreeStatusChanged);
    super.dispose();
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
      setState(() {
        _selectedImage = safeFile;
        _exportedImage = null;
        _lastEditCompleteAt = null;
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

  Future<ImageSource?> _showSourcePickerSheet() async {
    final cs = Theme.of(context).colorScheme;

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          LucideIcons.imagePlus,
                          color: cs.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        'Choose Image Source',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Options
                  Row(
                    children: [
                      // Gallery option
                      Expanded(
                        child: _buildPickerOption(
                          icon: LucideIcons.image,
                          label: 'Gallery',
                          sublabel: 'Choose from photos',
                          color: cs.primary,
                          onTap: () => Navigator.pop(context, ImageSource.gallery),
                        ),
                      ),
                      const SizedBox(width: 12),
                      
                      // Camera option
                      Expanded(
                        child: _buildPickerOption(
                          icon: LucideIcons.camera,
                          label: 'Camera',
                          sublabel: 'Take a new photo',
                          color: cs.secondary,
                          onTap: () => Navigator.pop(context, ImageSource.camera),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Picker option card for bottom sheet
  Widget _buildPickerOption({
    required IconData icon,
    required String label,
    required String sublabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: cs.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sublabel,
                style: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmExitEditing() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmExitDialog(),
        )) ??
        false;
  }

  Future<bool> _handleSystemBack() async {
    if (_selectedImage != null) {
      final ok = await _confirmExitEditing();
      if (ok) {
        setState(() {
          _selectedImage = null;
          _exportedImage = null;
          _lastEditCompleteAt = null;
        });
      }
      return false;
    }
    return true;
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
                  Expanded(child: Text('Please watch the ad to save your image')),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }

      // Ad completed - proceed with save
      final savedPath = await FileService.saveFile(context, _exportedImage!);
      if (savedPath != null) {
        debugPrint('✅ Image saved at: $savedPath');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  
  /// Shows a rewarded ad for export gate
  /// Returns true if ad was completed, false otherwise
  Future<bool> _showExportAd() async {
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
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        appBar: AppBar(
          title: const KalaLogoWithIcon(logoHeight: 30, fontSize: 22),
          actions: [
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
                  : IconButton(
                      icon: const Icon(Icons.save_alt),
                      tooltip: 'Save Image',
                      onPressed: _onExportPressed,
                    ),
          ],
        ),
        body: Stack(
          children: [
            if (_selectedImage == null)
              _buildEmptyStateWithAd(context)
            else
              ProImageEditor.file(
                _selectedImage!,
                key: ValueKey(_selectedImage!.path),
                configs: _configs,
                callbacks: _callbacks.copyWith(
                  // inside the callbacks.copyWith(...)
                  onImageEditingComplete: (bytes) async {
                    if (!mounted) return;
                    _lastEditCompleteAt = DateTime.now();

                    // Keep the timestamp for a short debounce window; then clear it so future closes behave normally.
                    Timer(const Duration(milliseconds: 900), () {
                      if (mounted) _lastEditCompleteAt = null;
                    });

                    setState(() => _exportedImage = bytes);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Image editing complete')),
                    );
                  },

                  onCloseEditor: (_) async {
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

                    // Otherwise it's likely a user-initiated close (❌). Show your confirm dialog.
                    debugPrint(
                        'pro_image_editor: onCloseEditor triggered by user — showing confirm dialog.');
                    final ok = await _confirmExitEditing();
                    if (ok) {
                      if (mounted) {
                        setState(() {
                          _selectedImage = null;
                          _exportedImage = null;
                          _lastEditCompleteAt = null;
                        });
                      }
                    } else {
                      debugPrint('❌ User cancelled exit from editor.');
                    }
                  },
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
          ],
        ),
        floatingActionButton: _selectedImage == null
            ? GradientButton(
                icon: Icons.add_photo_alternate_outlined,
                label: "Pick Image",
                onPressed: _pickImage,
                variant: ButtonVariant.primary,
                size: ButtonSize.large,
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }

  Widget _buildEmptyStateWithAd(BuildContext context) {
    final showAds = shouldShowAds();
    
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
                ? [cs.surface.withOpacity(0.70), cs.surface.withOpacity(0.55)]
                : [cs.surface.withOpacity(0.85), cs.surface.withOpacity(0.70)],
          ),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : Colors.black54).withOpacity(0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined,
                size: 56, color: cs.onSurface.withOpacity(0.38)),
            const SizedBox(height: 12),
            Text(
              'No image selected.\nTap the button below to choose one to start editing.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
                    fontSize: 14,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// Confirm Exit Dialog
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

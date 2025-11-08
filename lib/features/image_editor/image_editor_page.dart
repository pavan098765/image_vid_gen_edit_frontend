import 'dart:typed_data';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
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

  DateTime? _lastEditCompleteAt;

  late final ProImageEditorConfigs _configs = const ProImageEditorConfigs();

  late final ProImageEditorCallbacks _callbacks = ProImageEditorCallbacks(
    onImageEditingComplete: (bytes) async {
      debugPrint("✅ Image editing completed");
    },
    onCloseEditor: (_) {},
  );

  // Pick image from gallery or camera (robust across Android versions)
  Future<void> _pickImage() async {
    try {
      final source = await _showSourcePickerSheet();
      if (source == null) return;

      // ✅ Request appropriate permissions for Android 13 and below
      if (Platform.isAndroid) {
        final androidVersion = int.tryParse(
              (await DeviceInfoPlugin().androidInfo).version.release ?? '0',
            ) ??
            0;

        if (androidVersion <= 12) {
          // Android 13 and below may still need storage permission
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
          // Android 13+ uses scoped storage; request photo permission
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

      // ✅ Let user pick image
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 100,
      );
      if (pickedFile == null) return;

      // ✅ Ensure file is accessible locally (handles scoped URIs)
      File safeFile;
      if (await File(pickedFile.path).exists()) {
        // Copy to app temp directory for guaranteed access
        final tempDir = await getTemporaryDirectory();
        final fileName = pickedFile.name;
        final safePath = '${tempDir.path}/$fileName';
        safeFile = await File(pickedFile.path).copy(safePath);
      } else {
        // Fallback: read bytes (some devices return content:// URI)
        final bytes = await pickedFile.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        final fileName = pickedFile.name;
        final safePath = '${tempDir.path}/$fileName';
        safeFile = await File(safePath).writeAsBytes(bytes, flush: true);
      }

      // ✅ Optional: verify image decodes successfully before using
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

  // // Pick image from gallery or camera
  // Future<void> _pickImage() async {
  //   try {
  //     final source = await _showSourcePickerSheet();
  //     if (source == null) return;

  //     final XFile? pickedFile = await _picker.pickImage(source: source);
  //     if (pickedFile != null) {
  //       final bytes = await pickedFile.readAsBytes();
  //       final tempFile =
  //           await FileService.writeTempFile(bytes, pickedFile.name);

  //       if (!mounted) return;
  //       setState(() {
  //         _selectedImage = tempFile;
  //         _exportedImage = null;
  //         _lastEditCompleteAt = null;
  //       });
  //     }
  //   } catch (e) {
  //     debugPrint('❌ Error picking image: $e');
  //     if (context.mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Error picking image: $e')),
  //       );
  //     }
  //   }
  // }

  Future<ImageSource?> _showSourcePickerSheet() async {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        cs.surface.withOpacity(0.98),
                        cs.surface.withOpacity(0.92),
                      ]
                    : [
                        cs.surface.withOpacity(0.98),
                        cs.surface.withOpacity(0.96),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: (isDark ? Colors.black : Colors.black54)
                      .withOpacity(0.12),
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Select Image Source',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _SheetTile(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                  _SheetTile(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Show confirm exit dialog (video editor style)
  Future<bool> _confirmExitEditing() async {
    return (await showDialog<bool>(
          context: context,
          builder: (_) => const _ConfirmExitDialog(),
        )) ??
        false;
  }

  // Handle system/device back press
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

  // Manual save button
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

    final savedPath = await FileService.saveFile(context, _exportedImage!);

    if (savedPath != null) {
      debugPrint('✅ Image saved at: $savedPath');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: _handleSystemBack,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Image Editor'),
          actions: [
            if (_selectedImage != null)
              IconButton(
                icon: const Icon(Icons.photo_library_outlined),
                tooltip: 'Select Image',
                onPressed: _pickImage,
              ),
            if (_exportedImage != null)
              IconButton(
                icon: const Icon(Icons.save_alt),
                tooltip: 'Save Image',
                onPressed: _onExportPressed,
              ),
          ],
        ),
        body: Stack(
          children: [
            if (_selectedImage == null)
              _buildNoImagePlaceholder(context)
            else
              ProImageEditor.file(
                _selectedImage!,
                key: ValueKey(_selectedImage!.path),
                configs: _configs,
                callbacks: _callbacks.copyWith(
                  onImageEditingComplete: (bytes) async {
                    if (mounted) {
                      _lastEditCompleteAt = DateTime.now();
                      setState(() => _exportedImage = bytes);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('✅ Image editing complete')),
                      );
                    }
                  },
                  onCloseEditor: (_) async {
                    final ok = await _confirmExitEditing();
                    if (ok) {
                      setState(() {
                        _selectedImage = null;
                        _exportedImage = null;
                        _lastEditCompleteAt = null;
                      });
                    } else {
                      debugPrint('❌ User cancelled exit from image editor.');
                    }
                  },
                ),
              ),
            if (_exportedImage != null)
              Positioned(
                right: 16,
                bottom: 100,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withOpacity(0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: FloatingActionButton.small(
                    backgroundColor: Colors.transparent,
                    foregroundColor: cs.onPrimary,
                    elevation: 0,
                    tooltip: 'Preview Image',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              _ResultPreviewPage(imageBytes: _exportedImage!),
                        ),
                      );
                    },
                    child: const Icon(Icons.preview),
                  ),
                ),
              ),
          ],
        ),
        floatingActionButton: _selectedImage == null
            ? _PrimaryFAB(
                label: 'Pick Image',
                icon: Icons.add_photo_alternate_outlined,
                onPressed: _pickImage,
              )
            : null,
      ),
    );
  }

  Widget _buildNoImagePlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
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
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(
            color: cs.outlineVariant.withOpacity(0.25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_outlined,
              size: 80,
              color: cs.onSurface.withOpacity(0.38),
            ),
            const SizedBox(height: 16),
            Text(
              'No image selected.\nTap the button below to choose one.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withOpacity(0.70),
                    fontSize: 16,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// Confirm Exit dialog (same as video editor)
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
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Exit'),
        ),
      ],
    );
  }
}

class _PrimaryFAB extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _PrimaryFAB({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: cs.primary.withOpacity(0.35),
            blurRadius: 28,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        label: Text(label),
        icon: Icon(icon),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
    );
  }
}

class _SheetTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
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

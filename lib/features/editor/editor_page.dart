import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_vid_gen_edit_frontend/core/services/file_service.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  Uint8List? _exportedImage;
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  // track last time editing completed — used to avoid immediately showing close dialog
  DateTime? _lastEditCompleteAt;

  // Editor configuration
  late final ProImageEditorConfigs _configs = const ProImageEditorConfigs();

  // Default callbacks (base)
  late final ProImageEditorCallbacks _callbacks = ProImageEditorCallbacks(
    onImageEditingComplete: (bytes) async {
      debugPrint("✅ Image editing completed");
    },
    // leave onCloseEditor empty / noop so we don't interfere with internal navigation
    onCloseEditor: (_) {},
  );

  /// Pick image from gallery or camera
  Future<void> _pickImage() async {
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        backgroundColor: Colors.grey[900],
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Text(
                    'Select Image Source',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.photo_library, color: Colors.white70),
                  title: const Text('Gallery',
                      style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: Colors.white70),
                  title: const Text('Camera',
                      style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );

      if (source == null) return;

      final XFile? pickedFile = await _picker.pickImage(source: source);
      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        final tempFile =
            await FileService.writeTempFile(bytes, pickedFile.name);

        setState(() {
          _selectedImage = tempFile;
          _exportedImage = null;
          _lastEditCompleteAt = null;
        });
      }
    } catch (e) {
      debugPrint('❌ Error picking image: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  /// Confirm close (triggered when user tries to exit the editor)
  /// Returns true if we closed the editor (i.e., cleared selected image), false otherwise.
  Future<bool> _confirmClose() async {
    final result = await showDialog<_EditorCloseAction>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Exit the editor?'),
        content: const Text('Do you want to save your work before closing?'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_EditorCloseAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_EditorCloseAction.discard),
            child: const Text('Discard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_EditorCloseAction.save),
            child: const Text('Save & Exit'),
          ),
        ],
      ),
    );

    if (result == null || result == _EditorCloseAction.cancel) return false;

    if (result == _EditorCloseAction.save) {
      await _onExportPressed();
    }

    // Clear selection and exported bytes — this returns the UI to the image picker.
    if (mounted) {
      setState(() {
        _selectedImage = null;
        _exportedImage = null;
        _lastEditCompleteAt = null;
      });
    }

    return true;
  }

  /// Manual save button
  Future<void> _onExportPressed() async {
    if (_exportedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No exported image available. Please finish editing.'),
        ),
      );
      return;
    }

    final savedPath = await FileService.saveFile(
      context,
      _exportedImage!,
      prefix: 'edit',
    );

    if (savedPath != null) {
      debugPrint('✅ Image saved at: $savedPath');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Intercept system / app back navigation while an image is loaded.
    return WillPopScope(
      onWillPop: () async {
        // If we have an image open in editor, ask the user before leaving.
        if (_selectedImage != null) {
          // show confirm dialog; if user discards or saves, we clear selection.
          await _confirmClose();
          // Prevent popping the route — we only changed local state to return to picker.
          return false;
        }
        // No image open — allow default back navigation.
        return true;
      },
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
              _buildNoImagePlaceholder()
            else
              // ProImageEditor: don't implement custom 'onCloseEditor' behavior that clears state.
              // Let sub-editors handle their own back/check behavior internally.
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

                  // keep onCloseEditor minimal *and* no state-clearing here.
                  // If the package signals a top-level close, it will also likely trigger a route pop
                  // or the user will press system back — both will be handled by WillPopScope above.
                  onCloseEditor: (_) {
                    // intentionally left minimal to avoid interfering with sub-tool navigation.
                    debugPrint(
                        'pro_image_editor: onCloseEditor called (ignored here).');
                  },
                ),
              ),

            // Floating preview button (optional)
            if (_exportedImage != null)
              Positioned(
                right: 16,
                bottom: 100,
                child: FloatingActionButton.small(
                  backgroundColor: Colors.white24,
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
                  child: const Icon(Icons.preview, color: Colors.white),
                ),
              ),
          ],
        ),
        floatingActionButton: _selectedImage == null
            ? FloatingActionButton.extended(
                onPressed: _pickImage,
                label: const Text('Pick Image'),
                icon: const Icon(Icons.add_photo_alternate_outlined),
              )
            : null,
      ),
    );
  }

  Widget _buildNoImagePlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_outlined, size: 80, color: Colors.white38),
          SizedBox(height: 16),
          Text(
            'No image selected.\nTap the button below to choose one.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

enum _EditorCloseAction { cancel, discard, save }

class _ResultPreviewPage extends StatelessWidget {
  final Uint8List imageBytes;
  const _ResultPreviewPage({Key? key, required this.imageBytes})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preview Result')),
      backgroundColor: Colors.black,
      body: Center(child: Image.memory(imageBytes)),
    );
  }
}

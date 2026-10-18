import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class BeforeAfterPreviewPage extends StatefulWidget {
  final File resultFile;
  final File originalFile;

  const BeforeAfterPreviewPage({
    super.key,
    required this.resultFile,
    required this.originalFile,
  });

  @override
  State<BeforeAfterPreviewPage> createState() => _BeforeAfterPreviewPageState();
}

class _BeforeAfterPreviewPageState extends State<BeforeAfterPreviewPage> {
  bool _showOriginal = false;
  int? _heldPointer;

  void _press(PointerDownEvent event) {
    _heldPointer = event.pointer;
    if (_showOriginal) return;
    setState(() => _showOriginal = true);
  }

  void _release(PointerEvent event) {
    if (event.pointer != _heldPointer) return;
    _heldPointer = null;
    if (!_showOriginal) return;
    setState(() => _showOriginal = false);
  }

  @override
  Widget build(BuildContext context) {
    final file = _showOriginal ? widget.originalFile : widget.resultFile;
    final label = _showOriginal ? 'Original photo' : 'Edited result';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_showOriginal ? 'Original' : 'Result'),
        actions: [
          Tooltip(
            message: 'Hold to see original',
            child: Semantics(
              button: true,
              label: 'Hold to see the original photo',
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _press,
                onPointerUp: _release,
                onPointerCancel: _release,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(LucideIcons.eye, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Semantics(
            image: true,
            label: label,
            child: Image.file(
              file,
              key: ValueKey<String>(file.path + label),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        ),
      ),
    );
  }
}

void openBeforeAfterPreview(
  BuildContext context, {
  required File resultFile,
  required File originalFile,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => BeforeAfterPreviewPage(
        resultFile: resultFile,
        originalFile: originalFile,
      ),
    ),
  );
}

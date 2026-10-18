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
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Stack(
                  children: [
                    Positioned.fill(
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
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Tooltip(
                        message: 'Hold to see original',
                        child: Semantics(
                          button: true,
                          label: 'Hold to see the original photo',
                          child: GestureDetector(
                            onTapDown: (_) => setState(() => _showOriginal = true),
                            onTapUp: (_) => setState(() => _showOriginal = false),
                            onTapCancel: () => setState(() => _showOriginal = false),
                            child: Material(
                              color: _showOriginal
                                  ? Colors.white
                                  : const Color(0xCC1A1A1A),
                              shape: const CircleBorder(),
                              elevation: 2,
                              child: SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(
                                  LucideIcons.eye,
                                  color: _showOriginal ? Colors.black : Colors.white,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
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

// lib/features/video_editor/widgets/toolbar/panels/text_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../models/effect_model.dart';
import '../../../models/project_model.dart';
import '../../../state/editor_providers.dart';

/// Panel for adding and editing text overlays.
/// When a TextClip is selected on the timeline, it switches to Edit mode.
class TextPanel extends ConsumerStatefulWidget {
  const TextPanel({super.key});

  @override
  ConsumerState<TextPanel> createState() => _TextPanelState();
}

class _TextPanelState extends ConsumerState<TextPanel> {
  final _textController = TextEditingController(text: 'Your Text');
  double _fontSize = 28;
  Color _textColor = Colors.white;
  bool _isBold = true;
  bool _isItalic = false;
  TextAnimation _animation = TextAnimation.none;
  String _fontFamily = 'Inter';
  String? _editingClipId;

  final _fontOptions = [
    'Inter',
    'Roboto',
    'Poppins',
    'Montserrat',
    'Oswald',
    'Playfair Display',
    'Lobster',
    'Pacifico',
    'Dancing Script',
    'Bebas Neue',
  ];

  final _colorOptions = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.cyan,
    Colors.blue,
    Colors.purple,
    Colors.pink,
    const Color(0xFF7B5EFF),
    const Color(0xFF00D4FF),
  ];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _syncFromClip(TextClip clip) {
    _editingClipId = clip.id;
    _textController.text = clip.text;
    _fontSize = clip.fontSize;
    _textColor = clip.color;
    _isBold = clip.isBold;
    _isItalic = clip.isItalic;
    _animation = clip.animation;
    _fontFamily = clip.fontFamily;
  }

  void _resetToDefaults() {
    _editingClipId = null;
    _textController.text = 'Your Text';
    _fontSize = 28;
    _textColor = Colors.white;
    _isBold = true;
    _isItalic = false;
    _animation = TextAnimation.none;
    _fontFamily = 'Inter';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);
    final isEditing = selectedClip is TextClip;

    // Sync from selected clip when it changes
    if (isEditing && selectedClip.id != _editingClipId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _syncFromClip(selectedClip));
      });
    } else if (!isEditing && _editingClipId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _resetToDefaults());
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(LucideIcons.type, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                isEditing ? 'Edit Text' : 'Add Text',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (isEditing) ...[
                // Delete button
                IconButton(
                  onPressed: () => _deleteClip(selectedClip.id),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.redAccent,
                  tooltip: 'Delete Text',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const SizedBox(width: 4),
              ],
              FilledButton.icon(
                onPressed: isEditing ? null : _addTextClip,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add New', style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Text input
          TextField(
            controller: _textController,
            style: TextStyle(color: cs.onSurface),
            onChanged: isEditing ? (_) => _updateClip() : null,
            decoration: InputDecoration(
              hintText: 'Enter text...',
              hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.4)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.15)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.onSurface.withValues(alpha: 0.15)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Font picker
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _fontOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final font = _fontOptions[i];
                final selected = font == _fontFamily;
                return InkWell(
                  onTap: () {
                    setState(() => _fontFamily = font);
                    if (isEditing) _updateClip();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary.withValues(alpha: 0.15)
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: selected
                          ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      font,
                      style: TextStyle(
                        fontFamily: font,
                        fontSize: 12,
                        color: selected
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.7),
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Size slider + Bold/Italic
          Row(
            children: [
              Text('Size',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 12,
                  max: 72,
                  onChanged: (v) {
                    setState(() => _fontSize = v);
                    if (isEditing) _updateClip();
                  },
                ),
              ),
              Text(
                _fontSize.round().toString(),
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(width: 8),
              _toggleChip('B', _isBold, () {
                setState(() => _isBold = !_isBold);
                if (isEditing) _updateClip();
              }),
              const SizedBox(width: 4),
              _toggleChip('I', _isItalic, () {
                setState(() => _isItalic = !_isItalic);
                if (isEditing) _updateClip();
              }),
            ],
          ),

          // Color picker
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _colorOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final c = _colorOptions[i];
                final selected = c.toARGB32() == _textColor.toARGB32();
                return GestureDetector(
                  onTap: () {
                    setState(() => _textColor = c);
                    if (isEditing) _updateClip();
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.white24,
                        width: selected ? 2.5 : 1,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color: c.withValues(alpha: 0.4), blurRadius: 6)
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Animation picker
          Text('Animation',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: TextAnimation.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final anim = TextAnimation.values[i];
                final selected = anim == _animation;
                return InkWell(
                  onTap: () {
                    setState(() => _animation = anim);
                    if (isEditing) _updateClip();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary.withValues(alpha: 0.15)
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                      border: selected
                          ? Border.all(color: cs.primary.withValues(alpha: 0.4))
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      anim.label,
                      style: TextStyle(
                        fontSize: 11,
                        color: selected
                            ? cs.primary
                            : cs.onSurface.withValues(alpha: 0.6),
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Animation plays in preview. The export uses still text.',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleChip(String label, bool active, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              active ? cs.primary.withValues(alpha: 0.15) : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
          border:
              active ? Border.all(color: cs.primary.withValues(alpha: 0.4)) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            fontStyle: label == 'I' ? FontStyle.italic : FontStyle.normal,
            color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  void _updateClip() {
    if (_editingClipId == null) return;
    ref.read(projectProvider.notifier).updateClip(
          _editingClipId!,
          (c) => (c as TextClip).copyWith(
            text: _textController.text,
            fontFamily: _fontFamily,
            fontSize: _fontSize,
            color: _textColor,
            isBold: _isBold,
            isItalic: _isItalic,
            animation: _animation,
          ),
        );
  }

  void _deleteClip(String clipId) {
    ref.read(projectProvider.notifier).removeClip(clipId);
    ref.read(timelineProvider.notifier).clearSelection();
    setState(() => _resetToDefaults());
    Navigator.of(context).pop(); // close the bottom sheet
  }

  void _addTextClip() {
    final project = ref.read(projectProvider);
    if (project == null) return;

    final playback = ref.read(playbackProvider);

    // Find or create a text track
    var textTrack =
        project.tracks.where((t) => t.type == TrackType.text).firstOrNull;

    if (textTrack == null) {
      final trackId =
          '${project.id}_text_${DateTime.now().microsecondsSinceEpoch}';
      textTrack = Track(
        id: trackId,
        type: TrackType.text,
        name: 'Text 1',
      );
      ref.read(projectProvider.notifier).addTrack(textTrack);
    }

    final clipId =
        '${project.id}_textclip_${DateTime.now().microsecondsSinceEpoch}';
    final clip = TextClip(
      id: clipId,
      startTime: playback.position,
      duration: const Duration(seconds: 3),
      text: _textController.text,
      fontFamily: _fontFamily,
      fontSize: _fontSize,
      color: _textColor,
      isBold: _isBold,
      isItalic: _isItalic,
      animation: _animation,
    );

    ref.read(projectProvider.notifier).addClipToTrack(textTrack.id, clip);
    ref
        .read(timelineProvider.notifier)
        .selectClip(clipId, trackId: textTrack.id);
  }
}

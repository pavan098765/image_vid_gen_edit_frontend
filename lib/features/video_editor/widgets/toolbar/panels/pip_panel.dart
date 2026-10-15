// lib/features/video_editor/widgets/toolbar/panels/pip_panel.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pro_video_editor/pro_video_editor.dart';

import '../../../models/clip_model.dart';
import '../../../models/project_model.dart';
import '../../../state/editor_providers.dart';

/// Panel for Picture-in-Picture overlay controls.
class PipPanel extends ConsumerStatefulWidget {
  const PipPanel({super.key});

  @override
  ConsumerState<PipPanel> createState() => _PipPanelState();
}

class _PipPanelState extends ConsumerState<PipPanel> {
  double _scale = 0.3;
  double _opacity = 1.0;
  double _posX = 0.75;
  double _posY = 0.75;
  double _borderRadius = 8;
  double _volume = 0.0;
  String? _lastClipId;

  void _syncFromClip(PipClip clip) {
    _scale = clip.scale;
    _opacity = clip.opacity;
    _posX = clip.position.dx;
    _posY = clip.position.dy;
    _borderRadius = clip.borderRadius;
    _volume = clip.volume;
    _lastClipId = clip.id;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);

    if (selectedClip is PipClip && selectedClip.id != _lastClipId) {
      _syncFromClip(selectedClip);
    } else if (selectedClip == null || selectedClip is! PipClip) {
      _lastClipId = null;
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
              Icon(LucideIcons.pictureInPicture2, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                selectedClip is PipClip ? 'Edit PiP' : 'Picture in Picture',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (selectedClip is PipClip)
                IconButton(
                  onPressed: () => _deleteClip(selectedClip.id),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.redAccent,
                  tooltip: 'Delete PiP',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _importPipVideo,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Import', style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (selectedClip is PipClip) ...[
            // Position presets
            Text('Position', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _posPreset('TL', 0.15, 0.15),
                _posPreset('TC', 0.5, 0.15),
                _posPreset('TR', 0.85, 0.15),
                _posPreset('BL', 0.15, 0.85),
                _posPreset('BC', 0.5, 0.85),
                _posPreset('BR', 0.85, 0.85),
              ],
            ),
            const SizedBox(height: 12),

            _sliderRow('Scale', _scale, 0.1, 0.8, (v) {
              setState(() => _scale = v);
              _updatePip();
            }),
            _sliderRow('Opacity', _opacity, 0, 1, (v) {
              setState(() => _opacity = v);
              _updatePip();
            }),
            _sliderRow('Radius', _borderRadius, 0, 40, (v) {
              setState(() => _borderRadius = v);
              _updatePip();
            }),
            _sliderRow('Volume', _volume, 0, 1, (v) {
              setState(() => _volume = v);
              _updatePip();
            }),
          ] else
            Center(
              child: Text(
                'Import a video to add PiP overlay',
                style: TextStyle(
                  color: cs.onSurface.withOpacity(0.4),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _posPreset(String label, double x, double y) {
    final cs = Theme.of(context).colorScheme;
    final selected = (_posX - x).abs() < 0.05 && (_posY - y).abs() < 0.05;
    return GestureDetector(
      onTap: () {
        setState(() {
          _posX = x;
          _posY = y;
        });
        _updatePip();
      },
      child: Container(
        width: 36,
        height: 28,
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(0.15) : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? cs.primary : cs.onSurface.withOpacity(0.1),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? cs.primary : cs.onSurface.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.toStringAsFixed(1),
            style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7)),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  void _deleteClip(String clipId) {
    ref.read(projectProvider.notifier).removeClip(clipId);
    ref.read(timelineProvider.notifier).clearSelection();
    Navigator.of(context).pop();
  }

  void _updatePip() {
    final selectedClip = ref.read(selectedClipProvider);
    if (selectedClip == null || selectedClip is! PipClip) return;

    ref.read(projectProvider.notifier).updateClip(
          selectedClip.id,
          (c) => (c as PipClip).copyWith(
            position: Offset(_posX, _posY),
            scale: _scale,
            opacity: _opacity,
            borderRadius: _borderRadius,
            volume: _volume,
          ),
        );
  }

  Future<void> _importPipVideo() async {
    final picked = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (picked == null) return;

    final project = ref.read(projectProvider);
    if (project == null) return;
    final playback = ref.read(playbackProvider);

    // Find or create PiP track
    var pipTrack = project.tracks
        .where((t) => t.type == TrackType.pip)
        .firstOrNull;

    if (pipTrack == null) {
      final trackId = '${project.id}_pip_${DateTime.now().microsecondsSinceEpoch}';
      pipTrack = Track(
        id: trackId,
        type: TrackType.pip,
        name: 'PiP 1',
      );
      ref.read(projectProvider.notifier).addTrack(pipTrack);
    }

    final clipDuration = project.totalDuration > Duration.zero
        ? project.totalDuration
        : const Duration(seconds: 10);

    final clipId = '${project.id}_pipclip_${DateTime.now().microsecondsSinceEpoch}';
    final clip = PipClip(
      id: clipId,
      startTime: playback.position,
      duration: clipDuration,
      sourcePath: picked.path,
      trimStart: Duration.zero,
      trimEnd: clipDuration,
      originalDuration: clipDuration,
    );

    ref.read(projectProvider.notifier).addClipToTrack(pipTrack.id, clip);
    ref.read(timelineProvider.notifier).selectClip(clipId, trackId: pipTrack.id);

    // Generate thumbnail asynchronously for the PiP clip
    _generatePipThumbnail(File(picked.path), clipId);
  }

  Future<void> _generatePipThumbnail(File file, String clipId) async {
    try {
      final video = EditorVideo.file(file);
      final thumbs = await ProVideoEditor.instance.getKeyFrames(
        KeyFramesConfigs(
          video: video,
          outputSize: const Size.square(48),
          boxFit: ThumbnailBoxFit.cover,
          maxOutputFrames: 5,
          outputFormat: ThumbnailFormat.jpeg,
        ),
      );
      if (thumbs.isNotEmpty && mounted) {
        ref.read(projectProvider.notifier).updateClip(
              clipId,
              (c) => (c as PipClip).copyWith(thumbnails: thumbs),
            );
      }
    } catch (e) {
      debugPrint('PiP thumbnail generation failed: $e');
    }
  }
}

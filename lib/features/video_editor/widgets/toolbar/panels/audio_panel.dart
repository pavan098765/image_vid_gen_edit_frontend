// lib/features/video_editor/widgets/toolbar/panels/audio_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../models/effect_model.dart';
import '../../../models/project_model.dart';
import '../../../state/editor_providers.dart';
import '../../../services/waveform_service.dart';

/// Panel for adding/managing audio tracks.
class AudioPanel extends ConsumerStatefulWidget {
  const AudioPanel({super.key});

  @override
  ConsumerState<AudioPanel> createState() => _AudioPanelState();
}

class _AudioPanelState extends ConsumerState<AudioPanel> {
  double _volume = 1.0;
  double _fadeInSec = 0;
  double _fadeOutSec = 0;
  String? _lastClipId;

  void _syncFromClip(AudioClip clip) {
    _volume = clip.volume;
    _fadeInSec = clip.fadeIn.inMilliseconds / 1000.0;
    _fadeOutSec = clip.fadeOut.inMilliseconds / 1000.0;
    _lastClipId = clip.id;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);
    final isAudioSelected = selectedClip is AudioClip;

    if (selectedClip is AudioClip && selectedClip.id != _lastClipId) {
      _syncFromClip(selectedClip);
    } else if (selectedClip == null || selectedClip is! AudioClip) {
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
              Icon(LucideIcons.music, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                isAudioSelected ? 'Edit Audio' : 'Audio',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (isAudioSelected)
                IconButton(
                  onPressed: () => _deleteClip(selectedClip.id),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.redAccent,
                  tooltip: 'Delete Audio',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: _importAudio,
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
          const SizedBox(height: 16),

          // Volume
          _sliderRow(
            label: 'Volume',
            value: _volume,
            min: 0,
            max: 1,
            divisions: 20,
            displayValue: '${(_volume * 100).round()}%',
            onChanged: (v) {
              setState(() => _volume = v);
              if (isAudioSelected) {
                ref.read(projectProvider.notifier).updateClip(
                      selectedClip.id,
                      (c) => (c as AudioClip).copyWith(volume: v),
                    );
              }
            },
          ),

          // Fade In
          _sliderRow(
            label: 'Fade In',
            value: _fadeInSec,
            min: 0,
            max: 5,
            divisions: 50,
            displayValue: '${_fadeInSec.toStringAsFixed(1)}s',
            onChanged: (v) {
              setState(() => _fadeInSec = v);
              if (isAudioSelected) {
                ref.read(projectProvider.notifier).updateClip(
                      selectedClip.id,
                      (c) => (c as AudioClip).copyWith(
                        fadeIn: Duration(milliseconds: (v * 1000).round()),
                      ),
                    );
              }
            },
          ),

          // Fade Out
          _sliderRow(
            label: 'Fade Out',
            value: _fadeOutSec,
            min: 0,
            max: 5,
            divisions: 50,
            displayValue: '${_fadeOutSec.toStringAsFixed(1)}s',
            onChanged: (v) {
              setState(() => _fadeOutSec = v);
              if (isAudioSelected) {
                ref.read(projectProvider.notifier).updateClip(
                      selectedClip.id,
                      (c) => (c as AudioClip).copyWith(
                        fadeOut: Duration(milliseconds: (v * 1000).round()),
                      ),
                    );
              }
            },
          ),
          if (isAudioSelected) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final eq in VoiceEq.values)
                  ChoiceChip(
                    label: Text(eq.label),
                    selected: selectedClip.voiceEq == eq,
                    onSelected: (_) {
                      ref.read(projectProvider.notifier).updateClip(
                            selectedClip.id,
                            (c) => (c as AudioClip).copyWith(voiceEq: eq),
                          );
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            displayValue,
            style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.7)),
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

  Future<void> _importAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.path == null) return;

    final project = ref.read(projectProvider);
    if (project == null) return;
    final playback = ref.read(playbackProvider);

    // Find or create audio track
    var audioTrack = project.tracks
        .where((t) => t.type == TrackType.audio)
        .firstOrNull;

    if (audioTrack == null) {
      final trackId = '${project.id}_audio_${DateTime.now().microsecondsSinceEpoch}';
      audioTrack = Track(
        id: trackId,
        type: TrackType.audio,
        name: 'Audio 1',
      );
      ref.read(projectProvider.notifier).addTrack(audioTrack);
    }

    final clipId = '${project.id}_audioclip_${DateTime.now().microsecondsSinceEpoch}';
    // Default to 30 seconds or project duration
    final clipDuration = project.totalDuration > Duration.zero
        ? project.totalDuration
        : const Duration(seconds: 30);

    final waveformSamples =
        await WaveformService.samplesForPath(file.path!, count: 80);

    final clip = AudioClip(
      id: clipId,
      startTime: playback.position,
      duration: clipDuration,
      sourcePath: file.path!,
      trimStart: Duration.zero,
      trimEnd: clipDuration,
      originalDuration: clipDuration,
      name: file.name,
      waveform: waveformSamples,
    );

    ref.read(projectProvider.notifier).addClipToTrack(audioTrack.id, clip);
    ref.read(timelineProvider.notifier).selectClip(clipId, trackId: audioTrack.id);
  }
}

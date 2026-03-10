// lib/features/video_editor/widgets/toolbar/panels/speed_panel.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../models/clip_model.dart';
import '../../../models/effect_model.dart';
import '../../../state/editor_providers.dart';
import '../../../utils/editor_constants.dart';

/// Panel for speed adjustment and speed ramping.
class SpeedPanel extends ConsumerStatefulWidget {
  const SpeedPanel({super.key});

  @override
  ConsumerState<SpeedPanel> createState() => _SpeedPanelState();
}

class _SpeedPanelState extends ConsumerState<SpeedPanel> {
  SpeedMode _mode = SpeedMode.constant;
  double _speed = 1.0;
  double _rampStart = 1.0;
  double _rampEnd = 1.0;
  String? _lastClipId;

  // Presets
  static const _presets = [
    (label: '0.25x', value: 0.25),
    (label: '0.5x', value: 0.5),
    (label: '0.75x', value: 0.75),
    (label: '1x', value: 1.0),
    (label: '1.5x', value: 1.5),
    (label: '2x', value: 2.0),
    (label: '3x', value: 3.0),
    (label: '5x', value: 5.0),
  ];

  void _syncFromClip(VideoClip clip) {
    _mode = clip.speedEffect.mode;
    _speed = clip.speedEffect.speed;
    _rampStart = clip.speedEffect.rampStart;
    _rampEnd = clip.speedEffect.rampEnd;
    _lastClipId = clip.id;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selectedClip = ref.watch(selectedClipProvider);

    if (selectedClip is VideoClip && selectedClip.id != _lastClipId) {
      _syncFromClip(selectedClip);
    } else if (selectedClip == null || selectedClip is! VideoClip) {
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
              Icon(LucideIcons.gauge, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                'Speed',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Mode toggle
          Row(
            children: [
              _modeChip('Constant', SpeedMode.constant),
              const SizedBox(width: 8),
              _modeChip('Ramp', SpeedMode.ramp),
            ],
          ),
          const SizedBox(height: 12),

          if (_mode == SpeedMode.constant) ...[
            // Preset buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _presets.map((p) {
                final selected = (_speed - p.value).abs() < 0.01;
                return GestureDetector(
                  onTap: () => _setConstantSpeed(p.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? cs.primary.withOpacity(0.15)
                          : cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? cs.primary : cs.onSurface.withOpacity(0.1),
                      ),
                    ),
                    child: Text(
                      p.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        color: selected ? cs.primary : cs.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),

            // Custom slider
            Row(
              children: [
                Text('Custom', style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
                Expanded(
                  child: Slider(
                    value: _speed.clamp(EditorConstants.minSpeed, EditorConstants.maxSpeed),
                    min: EditorConstants.minSpeed,
                    max: EditorConstants.maxSpeed,
                    divisions: 99,
                    onChanged: (v) => _setConstantSpeed(v),
                  ),
                ),
                Text(
                  '${_speed.toStringAsFixed(2)}x',
                  style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7)),
                ),
              ],
            ),
          ] else ...[
            // Ramp mode
            _sliderRow('Start Speed', _rampStart, 0.1, 5.0, (v) {
              setState(() => _rampStart = v);
              _applySpeed();
            }),
            _sliderRow('End Speed', _rampEnd, 0.1, 5.0, (v) {
              setState(() => _rampEnd = v);
              _applySpeed();
            }),

            // Visual curve preview
            const SizedBox(height: 8),
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(
                painter: _SpeedCurvePainter(
                  startSpeed: _rampStart,
                  endSpeed: _rampEnd,
                  color: cs.primary,
                ),
                size: const Size(double.infinity, 60),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeChip(String label, SpeedMode mode) {
    final cs = Theme.of(context).colorScheme;
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _mode = mode);
        _applySpeed();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withOpacity(0.15) : cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primary : cs.onSurface.withOpacity(0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? cs.primary : cs.onSurface.withOpacity(0.7),
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
          width: 80,
          child: Text(label, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: 49,
            onChanged: onChanged,
          ),
        ),
        Text(
          '${value.toStringAsFixed(1)}x',
          style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.7)),
        ),
      ],
    );
  }

  void _setConstantSpeed(double v) {
    setState(() {
      _speed = v;
      _mode = SpeedMode.constant;
    });
    _applySpeed();
  }

  void _applySpeed() {
    final selectedClip = ref.read(selectedClipProvider);
    if (selectedClip == null || selectedClip is! VideoClip) {
      _showNoClipWarning();
      return;
    }

    ref.read(projectProvider.notifier).updateClip(
          selectedClip.id,
          (c) => (c as VideoClip).copyWith(
            speedEffect: SpeedEffect(
              mode: _mode,
              speed: _speed,
              rampStart: _rampStart,
              rampEnd: _rampEnd,
            ),
          ),
        );
    _showAppliedFeedback('Speed set to ${_speed.toStringAsFixed(1)}x');
  }

  void _showAppliedFeedback(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }

  void _showNoClipWarning() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Select a video clip first'),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Colors.orange.shade700,
      ),
    );
  }
}

class _SpeedCurvePainter extends CustomPainter {
  final double startSpeed;
  final double endSpeed;
  final Color color;

  _SpeedCurvePainter({
    required this.startSpeed,
    required this.endSpeed,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const maxSpeed = 5.0;
    final path = Path();
    for (int i = 0; i <= 100; i++) {
      final t = i / 100.0;
      final speed = startSpeed + (endSpeed - startSpeed) * t;
      final x = t * size.width;
      final y = size.height - (speed / maxSpeed * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    // 1x reference line
    final refY = size.height - (1.0 / maxSpeed * size.height);
    final refPaint = Paint()
      ..color = color.withOpacity(0.2)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, refY), Offset(size.width, refY), refPaint);
  }

  @override
  bool shouldRepaint(_SpeedCurvePainter old) =>
      old.startSpeed != startSpeed || old.endSpeed != endSpeed;
}

import 'dart:async';

import 'package:flutter/material.dart';

/// Typewriter-style cycling hints for an empty composer (replaces static placeholder).
class StreamingComposerHint extends StatefulWidget {
  final List<String> examples;
  final TextStyle textStyle;
  final bool active;

  const StreamingComposerHint({
    super.key,
    required this.examples,
    required this.textStyle,
    required this.active,
  });

  @override
  State<StreamingComposerHint> createState() => _StreamingComposerHintState();
}

class _StreamingComposerHintState extends State<StreamingComposerHint> {
  Timer? _tick;
  int _exampleIndex = 0;
  int _visibleChars = 0;

  List<String> get _examples =>
      widget.examples.where((s) => s.trim().isNotEmpty).toList();

  void _cancel() {
    _tick?.cancel();
    _tick = null;
  }

  void _arm() {
    _cancel();
    if (!widget.active || _examples.isEmpty) return;
    _tick = Timer.periodic(const Duration(milliseconds: 26), (_) {
      if (!mounted || !widget.active) {
        _cancel();
        return;
      }
      final full = _examples[_exampleIndex % _examples.length];
      if (_visibleChars < full.length) {
        setState(() => _visibleChars++);
      } else {
        _cancel();
        Future<void>.delayed(const Duration(milliseconds: 2500), () {
          if (!mounted || !widget.active) return;
          setState(() {
            _visibleChars = 0;
            _exampleIndex = (_exampleIndex + 1) % _examples.length;
          });
          _arm();
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.active) _arm();
  }

  @override
  void didUpdateWidget(StreamingComposerHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        setState(() {
          _visibleChars = 0;
          _exampleIndex = 0;
        });
        _arm();
      } else {
        _cancel();
      }
    }
    if (widget.examples != oldWidget.examples) {
      setState(() {
        _visibleChars = 0;
        _exampleIndex = 0;
      });
      if (widget.active) {
        _cancel();
        _arm();
      }
    }
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _examples.isEmpty) {
      return const SizedBox.shrink();
    }
    final full = _examples[_exampleIndex % _examples.length];
    final end = _visibleChars.clamp(0, full.length);
    final slice = full.substring(0, end);
    return Text(
      slice,
      maxLines: 12,
      style: widget.textStyle,
    );
  }
}

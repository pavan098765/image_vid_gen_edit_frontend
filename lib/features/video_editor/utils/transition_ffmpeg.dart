// lib/features/video_editor/utils/transition_ffmpeg.dart

import 'package:flutter/foundation.dart';

import '../models/effect_model.dart';

final Set<String> _loggedTransitionFallback = {};

void logTransitionFallback(TransitionType type, Object? err) {
  final key = type.name;
  if (_loggedTransitionFallback.add(key)) {
    debugPrint('FFmpeg transition fallback for $key: $err');
  }
}

/// FFmpeg video-filter fragment for transition-in at the **start** of a segment.
/// [t] is seconds from the start of the current clip file.
/// Returns `null` for [TransitionType.none].
String? transitionInVideoFilter(ClipTransition tr) {
  if (tr.type == TransitionType.none) return null;
  final d = (tr.duration.inMilliseconds / 1000.0).clamp(0.05, 10.0);
  final ds = d.toStringAsFixed(4);

  switch (tr.type) {
    case TransitionType.none:
      return null;
    case TransitionType.fade:
    case TransitionType.dissolve:
      return 'fade=t=in:st=0:d=$ds';
    case TransitionType.slideLeft:
      return 'pad=2*iw:ih:iw:0:black,'
          'crop=iw:ih:x=\'iw*if(lt(t\\,$ds)\\,t/$ds\\,1)\':y=0';
    case TransitionType.slideRight:
      return 'pad=2*iw:ih:0:0:black,'
          'crop=iw:ih:x=\'iw*if(lt(t\\,$ds)\\,1-t/$ds\\,0)\':y=0';
    case TransitionType.slideUp:
      return 'pad=iw:2*ih:0:ih:black,'
          'crop=iw:ih:x=0:y=\'ih*if(lt(t\\,$ds)\\,t/$ds\\,1)\'';
    case TransitionType.slideDown:
      return 'pad=iw:2*ih:0:0:black,'
          'crop=iw:ih:x=0:y=\'ih*if(lt(t\\,$ds)\\,1-t/$ds\\,0)\'';
    case TransitionType.zoomIn:
      return 'format=rgba,'
          'scale=w=\'iw*(0.3+0.7*if(lt(t\\,$ds)\\,t/$ds\\,1))\':h=-2,'
          'colorchannelmixer=aa=\'if(lt(t\\,$ds)\\,t/$ds\\,1)\'';
    case TransitionType.zoomOut:
      return 'format=rgba,'
          'scale=w=\'iw*(1.5-0.5*if(lt(t\\,$ds)\\,t/$ds\\,1))\':h=-2,'
          'colorchannelmixer=aa=\'if(lt(t\\,$ds)\\,t/$ds\\,1)\'';
    case TransitionType.wipeLeft:
      return 'crop=iw*if(lt(t\\,$ds)\\,t/$ds\\,1):ih:'
          'iw*if(lt(t\\,$ds)\\,1-t/$ds\\,0):0';
    case TransitionType.wipeRight:
      return 'crop=iw*if(lt(t\\,$ds)\\,t/$ds\\,1):ih:0:0';
    case TransitionType.wipeUp:
      return 'crop=iw:ih*if(lt(t\\,$ds)\\,t/$ds\\,1):'
          '0:ih*if(lt(t\\,$ds)\\,1-t/$ds\\,0)';
    case TransitionType.wipeDown:
      return 'crop=iw:ih*if(lt(t\\,$ds)\\,t/$ds\\,1):0:0';
  }
}

/// If a transition filter fails at runtime, caller can substitute a simple fade-in.
String fadeInFallback(ClipTransition tr) {
  final d = (tr.duration.inMilliseconds / 1000.0).clamp(0.05, 10.0);
  return 'fade=t=in:st=0:d=${d.toStringAsFixed(4)}';
}

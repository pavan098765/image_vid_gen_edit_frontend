import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kala_ai_create_images_videos_with_ai/core/app_state.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/music_job.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/services/auth_service.dart';
import 'package:path_provider/path_provider.dart';

const String _controllerUrl = 'https://genedit.mooo.com';

const List<int> _bandsHz = <int>[
  60,
  170,
  310,
  600,
  1000,
  3000,
  6000,
  12000,
  14000,
  16000,
];

/// The 18 VLC curves. Flat is absent because it does not change the file.
const Map<String, List<double>> _curves = <String, List<double>>{
  'classical': <double>[0, 0, 0, 0, 0, 0, -7.2, -7.2, -7.2, -9.6],
  'club': <double>[0, 0, 8, 5.6, 5.6, 5.6, 3.2, 0, 0, 0],
  'dance': <double>[9.6, 7.2, 2.4, 0, 0, -5.6, -7.2, -7.2, 0, 0],
  'fullbass': <double>[-8, 9.6, 9.6, 5.6, 1.6, -4, -8, -10.4, -11.2, -11.2],
  'fullbasstreble': <double>[7.2, 5.6, 0, -7.2, -4.8, 1.6, 8, 11.2, 12, 12],
  'fulltreble': <double>[-9.6, -9.6, -9.6, -4, 2.4, 11.2, 16, 16, 16, 16.8],
  'headphones': <double>[4.8, 11.2, 5.6, -3.2, -2.4, 1.6, 4.8, 9.6, 12.8, 14.4],
  'largehall': <double>[10.4, 10.4, 5.6, 5.6, 0, -4.8, -4.8, -4.8, 0, 0],
  'live': <double>[-4.8, 0, 4, 5.6, 5.6, 5.6, 4, 2.4, 2.4, 2.4],
  'party': <double>[7.2, 7.2, 0, 0, 0, 0, 0, 0, 7.2, 7.2],
  'pop': <double>[-1.6, 4.8, 7.2, 8, 5.6, 0, -2.4, -2.4, -1.6, -1.6],
  'reggae': <double>[0, 0, 0, -5.6, 0, 6.4, 6.4, 0, 0, 0],
  'rock': <double>[8, 4.8, -5.6, -8, -3.2, 4, 8.8, 11.2, 11.2, 11.2],
  'ska': <double>[-2.4, -4.8, -4, 0, 4, 5.6, 8.8, 9.6, 11.2, 9.6],
  'soft': <double>[4.8, 1.6, 0, -2.4, 0, 4, 8, 9.6, 11.2, 12],
  'softrock': <double>[4, 4, 2.4, 0, -4, -5.6, -3.2, 0, 2.4, 8.8],
  'techno': <double>[8, 5.6, 0, -5.6, -4.8, 0, 8, 9.6, 9.6, 8.8],
};

const Map<String, String> _aliases = <String, String>{
  'hiphop': 'fullbass',
  'trap': 'fullbass',
  'edm': 'techno',
  'ballad': 'soft',
  'rnb': 'soft',
  'metal': 'rock',
  'jazz': 'classical',
  'acoustic': 'live',
  'lofi': 'soft',
  'ambient': 'soft',
  'latin': 'dance',
  'punjabi': 'party',
  'bhangra': 'party',
  'bollywood': 'pop',
  'indie': 'softrock',
  'country': 'softrock',
};

const Set<String> _equalizedActions = <String>{
  'song',
  'extend',
  'upload_extend',
  'mashup',
};

/// Bake the style-chosen VLC curve into a HitMaker song before it is saved.
///
/// Speech, stems, sounds, and video are left as downloaded. A failed lookup or
/// ffmpeg run returns the original bytes.
Future<Uint8List> equalizeHitMakerDownload({
  required Uint8List bytes,
  required String extension,
  String? jobId,
}) async {
  if (bytes.isEmpty || extension.toLowerCase() != 'mp3') {
    debugPrint('EQ: skip, not an mp3 ($extension, ${bytes.length} bytes)');
    return bytes;
  }
  if (jobId == null || jobId.isEmpty) {
    debugPrint('EQ: skip, download has no job id');
    return bytes;
  }
  final job = _job(jobId);
  if (job == null || !_shouldEqualize(job)) {
    debugPrint('EQ: skip, job $jobId is not a HitMaker song');
    return bytes;
  }

  final sourceHash = sha1.convert(bytes).toString();
  final applied = _storedHashes(job.settingsSnapshot?['eqAppliedHashes']);
  if (applied.contains(sourceHash)) {
    debugPrint('EQ: skip, this file was already equalized ($sourceHash)');
    return bytes;
  }

  final stored = job.settingsSnapshot?['eqPreset'];
  final String preset;
  if (stored is String && stored.trim().isNotEmpty) {
    preset = stored.trim().toLowerCase();
    debugPrint('EQ: reusing preset $preset for job $jobId');
  } else {
    final song = _songText(job);
    debugPrint(
      'EQ: asking for a preset title="${song.title}" style="${song.style}"',
    );
    final chosen = await _requestPreset(
      title: song.title,
      style: song.style,
      tags: song.tags,
      lyrics: song.lyrics,
    );
    if (chosen == null) {
      debugPrint('EQ: preset lookup failed, saving the original');
      return bytes;
    }
    preset = chosen;
    debugPrint('EQ: preset is $preset');
  }

  final filter = _filterFor(preset);
  var output = bytes;
  if (filter == null) {
    debugPrint('EQ: preset $preset is flat, file unchanged');
  } else {
    debugPrint('EQ: ffmpeg $filter');
    final baked = await _bake(bytes, filter);
    if (baked == null) {
      debugPrint('EQ: ffmpeg failed, saving the original');
      return bytes;
    }
    output = baked;
    debugPrint('EQ: equalized ${bytes.length} bytes to ${output.length}');
  }

  final hashes = <String>[...applied, sourceHash];
  final outputHash = sha1.convert(output).toString();
  if (outputHash != sourceHash) hashes.add(outputHash);
  await _remember(jobId, preset, hashes.length > 8 ? hashes.sublist(hashes.length - 8) : hashes);
  return output;
}

String? _filterFor(String presetId) {
  final canonical = _aliases[presetId] ?? presetId;
  final gains = _curves[canonical];
  if (gains == null || gains.length != _bandsHz.length) return null;
  var peak = 0.0;
  for (final gain in gains) {
    if (gain > peak) peak = gain;
  }
  final parts = <String>[];
  if (peak > 0) parts.add('volume=-${_db(peak)}dB');
  for (var i = 0; i < _bandsHz.length; i++) {
    parts.add('equalizer=f=${_bandsHz[i]}:t=q:w=1:g=${_db(gains[i])}');
  }
  parts.add('alimiter=limit=0.95');
  return parts.join(',');
}

String _db(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

JobModel? _job(String jobId) {
  for (final job in jobListNotifier.value) {
    if (job.jobId == jobId) return job;
  }
  return null;
}

bool _shouldEqualize(JobModel job) {
  final snapModel = job.settingsSnapshot?['modelId'];
  final isHitMaker = job.model == kSunoV6ModelId || snapModel == kSunoV6ModelId;
  if (!isHitMaker || job.outputType == 'video') return false;
  return _equalizedActions.contains(_action(job));
}

String _action(JobModel job) {
  final music = job.music;
  if (music != null) {
    final action = music['action'];
    if (action is String && action.isNotEmpty) return action;
  }
  final snap = job.settingsSnapshot?['musicAction'];
  if (snap is String && snap.isNotEmpty) return snap;
  return 'song';
}

({String title, String style, String tags, String lyrics}) _songText(JobModel job) {
  final snap = job.settingsSnapshot ?? const <String, dynamic>{};
  final music = job.music == null ? null : MusicResult.fromJson(job.music!);
  final titles = <String>[];
  final tags = <String>[];
  final lyrics = <String>[];
  for (final track in music?.tracks ?? const <MusicTrack>[]) {
    if (track.title.trim().isNotEmpty) titles.add(track.title.trim());
    final trackTags = track.tags?.trim() ?? '';
    if (trackTags.isNotEmpty) tags.add(trackTags);
    final words = track.lyrics?.trim() ?? '';
    if (words.isNotEmpty) lyrics.add(words);
  }
  final snapTitle = snap['sunoTitle']?.toString().trim() ?? '';
  final snapLyrics = snap['lyrics']?.toString().trim() ?? '';
  return (
    title: _clip(
      snapTitle.isNotEmpty
          ? snapTitle
          : (titles.isEmpty ? job.title : titles.first),
      200,
    ),
    style: _clip(snap['style']?.toString(), 1000),
    tags: _clip(tags.join(', '), 500),
    lyrics: _clip(
      snapLyrics.isNotEmpty ? snapLyrics : (lyrics.isEmpty ? '' : lyrics.first),
      500,
    ),
  );
}

String _clip(String? value, int max) {
  final text = value?.trim() ?? '';
  if (text.length <= max) return text;
  return text.substring(0, max);
}

List<String> _storedHashes(Object? raw) {
  if (raw is! List) return const <String>[];
  return <String>[
    for (final item in raw)
      if (item is String && item.isNotEmpty) item,
  ];
}

Future<String?> _requestPreset({
  required String title,
  required String style,
  required String tags,
  required String lyrics,
}) async {
  try {
    final token = await AuthService().getIdToken();
    if (token == null || token.isEmpty) return null;
    final response = await http
        .post(
          Uri.parse('$_controllerUrl/eq_preset'),
          headers: <String, String>{
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, String>{
            'title': title,
            'style': style,
            'tags': tags,
            'lyrics': lyrics,
          }),
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final preset = decoded['preset'];
    if (preset is! String || preset.trim().isEmpty) return null;
    return preset.trim().toLowerCase();
  } catch (error) {
    debugPrint('EQ preset lookup failed: $error');
    return null;
  }
}

Future<Uint8List?> _bake(Uint8List source, String filter) async {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final dir = await getTemporaryDirectory();
  final input = File('${dir.path}/eq_in_$stamp.mp3');
  final output = File('${dir.path}/eq_out_$stamp.mp3');
  try {
    await input.writeAsBytes(source, flush: true);
    final session = await FFmpegKit.executeWithArguments(<String>[
      '-y',
      '-i',
      input.path,
      '-af',
      filter,
      '-c:a',
      'libmp3lame',
      '-q:a',
      '2',
      output.path,
    ]);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code) || !output.existsSync()) return null;
    final baked = await output.readAsBytes();
    if (baked.isEmpty) return null;
    return baked;
  } catch (error) {
    debugPrint('EQ bake failed: $error');
    return null;
  } finally {
    try {
      if (input.existsSync()) await input.delete();
    } catch (_) {}
    try {
      if (output.existsSync()) await output.delete();
    } catch (_) {}
  }
}

Future<void> _remember(String jobId, String preset, List<String> hashes) async {
  final current = _job(jobId);
  if (current == null) return;
  final snap = Map<String, dynamic>.from(current.settingsSnapshot ?? const <String, dynamic>{});
  snap['eqPreset'] = preset;
  snap['eqAppliedHashes'] = hashes;
  await addOrUpdateJob(current.copyWith(settingsSnapshot: snap));
}

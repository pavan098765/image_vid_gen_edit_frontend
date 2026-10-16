import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'workflow_models.dart';

class StudioDraftStore {
  StudioDraftStore({this.saveOverride, this.loadOverride});

  final Future<void> Function(FilmDraft draft)? saveOverride;
  final Future<FilmDraft?> Function(String workflowId)? loadOverride;

  Future<void> save(FilmDraft draft) async {
    if (saveOverride != null) {
      await saveOverride!(draft);
      return;
    }
    try {
      final folder = await _folder();
      final file = File('${folder.path}/${draft.id}.json');
      await file.writeAsString(jsonEncode(draft.toJson()));
    } catch (_) {}
  }

  Future<FilmDraft?> latestFor(String workflowId) async {
    if (loadOverride != null) return loadOverride!(workflowId);
    try {
      final folder = await _folder();
      if (!folder.existsSync()) return null;
      FilmDraft? newest;
      DateTime? newestStamp;
      for (final entity in folder.listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final draft = FilmDraft.fromJson(jsonDecode(await entity.readAsString()) as Map<String, dynamic>);
        if (draft.workflowId != workflowId) continue;
        final stamp = entity.lastModifiedSync();
        if (newestStamp == null || stamp.isAfter(newestStamp)) {
          newest = draft;
          newestStamp = stamp;
        }
      }
      return newest;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _folder() async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/studio_drafts');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    return folder;
  }
}

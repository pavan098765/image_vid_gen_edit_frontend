import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/job_model.dart';

void main() {
  JobModel sample() => JobModel(
        jobId: 'job-1',
        title: 'Sunset',
        model: 'flux_klein',
        outputType: 'image',
        status: 'processing',
        templateId: 'glow_up_photo',
        templateTitle: 'Glow Up Photo',
        capabilityId: 'edit_image',
        settingsSnapshot: sanitizeSettingsSnapshot({
          'prompt': 'softer light',
          'modelId': 'flux_klein',
          'variations': 1,
          'transparentBackground': true,
          'inputPaths': ['a.jpg', 'b.jpg'],
          'mediaPaths': {
            'init_image': ['a.jpg', 'b.jpg'],
          },
          'secret': 'drop-me',
        }),
        creditsCharged: 18,
        parentJobId: 'job-0',
        batchId: 'batch-9',
      );

  test('round-trip keeps lineage fields', () {
    final json = sample().toJson();
    final restored = JobModel.fromJson(json);
    expect(restored.templateId, 'glow_up_photo');
    expect(restored.templateTitle, 'Glow Up Photo');
    expect(restored.capabilityId, 'edit_image');
    expect(restored.settingsSnapshot?['prompt'], 'softer light');
    expect(restored.settingsSnapshot?['transparentBackground'], isTrue);
    expect(restored.settingsSnapshot?['inputPaths'], ['a.jpg', 'b.jpg']);
    expect(
      (restored.settingsSnapshot?['mediaPaths'] as Map)['init_image'],
      ['a.jpg', 'b.jpg'],
    );
    expect(restored.settingsSnapshot?.containsKey('secret'), isFalse);
    expect(restored.creditsCharged, 18);
    expect(restored.parentJobId, 'job-0');
    expect(restored.batchId, 'batch-9');
  });

  test('missing keys still parse', () {
    final restored = JobModel.fromJson({
      'jobId': 'old',
      'title': 'Old job',
      'model': 'flux_klein',
      'outputType': 'image',
      'status': 'completed',
    });
    expect(restored.templateId, isNull);
    expect(restored.settingsSnapshot, isNull);
    expect(restored.parentJobId, isNull);
    expect(restored.creditsCharged, isNull);
    expect(restored.batchId, isNull);
  });

  test('status merge keeps launch details from either record', () {
    final thin = JobModel(
      jobId: 'job-1',
      title: 'Sunset',
      model: 'flux_klein',
      outputType: 'image',
      status: 'completed',
    );
    final merged = thin.mergePreservingLaunch(sample());
    expect(merged.status, 'completed');
    expect(merged.settingsSnapshot?['prompt'], 'softer light');
    expect(merged.originalPrompt, isNull);
    expect(merged.capabilityId, 'edit_image');
    expect(merged.templateId, 'glow_up_photo');
  });

  test('status merge keeps the app model id over a provider id', () {
    final fromPing = JobModel(
      jobId: 'job-1',
      title: 'Sunset',
      model: 'runware:400@2',
      outputType: 'image',
      status: 'completed',
    );
    final merged = fromPing.mergePreservingLaunch(sample());
    expect(merged.model, 'flux_klein');
  });

  test('copyWith status-only update keeps lineage', () {
    final updated = sample().copyWith(status: 'completed');
    expect(updated.status, 'completed');
    expect(updated.templateId, 'glow_up_photo');
    expect(updated.settingsSnapshot?['prompt'], 'softer light');
    expect(updated.parentJobId, 'job-0');
    expect(updated.creditsCharged, 18);
  });

  test('music snapshot survives json and merge', () {
    final withMusic = sample().copyWith(
      music: {
        'phase': 'complete',
        'task_id': 't1',
        'tracks': [
          {'id': 'a1', 'title': 'Night', 'audio_url': 'https://x'}
        ],
      },
    );
    final restored = JobModel.fromJson(withMusic.toJson());
    expect(restored.music?['task_id'], 't1');
    final thin = JobModel(
      jobId: 'job-1',
      title: 'Sunset',
      model: 'suno_v6',
      outputType: 'audio',
      status: 'completed',
    );
    final merged = thin.mergePreservingLaunch(withMusic);
    expect(merged.music?['task_id'], 't1');
  });
}

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

  test('copyWith status-only update keeps lineage', () {
    final updated = sample().copyWith(status: 'completed');
    expect(updated.status, 'completed');
    expect(updated.templateId, 'glow_up_photo');
    expect(updated.settingsSnapshot?['prompt'], 'softer light');
    expect(updated.parentJobId, 'job-0');
    expect(updated.creditsCharged, 18);
  });
}

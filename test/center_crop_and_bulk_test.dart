import 'package:flutter_test/flutter_test.dart';
import 'package:kala_ai_create_images_videos_with_ai/core/center_crop.dart';

void main() {
  test('wide image center-crops to 9:16', () {
    final rect = centerCropRect(width: 1920, height: 1080, targetRatio: 9 / 16);
    expect(rect.height, closeTo(1080, 0.01));
    expect(rect.width, closeTo(1080 * 9 / 16, 0.01));
    expect(rect.left, closeTo((1920 - rect.width) / 2, 0.01));
    expect(rect.top, 0);
  });

  test('tall image center-crops to 16:9', () {
    final rect = centerCropRect(width: 1080, height: 1920, targetRatio: 16 / 9);
    expect(rect.width, closeTo(1080, 0.01));
    expect(rect.height, closeTo(1080 / (16 / 9), 0.01));
    expect(rect.top, closeTo((1920 - rect.height) / 2, 0.01));
    expect(rect.left, 0);
  });

  test('near-square is already 1:1 within 2 percent', () {
    expect(
      isAlreadyTargetRatio(width: 1000, height: 990, targetRatio: 1),
      isTrue,
    );
    expect(
      isAlreadyTargetRatio(width: 1920, height: 1080, targetRatio: 1),
      isFalse,
    );
  });

  test('bulk total is unit times count', () {
    expect(bulkPhotoTotal(unitCost: 12, count: 5), 60);
  });

  test('count above the non-VIP cap is rejected', () {
    expect(bulkCountAllowed(count: 5, isVip: false), isTrue);
    expect(bulkCountAllowed(count: 6, isVip: false), isFalse);
    expect(bulkCountAllowed(count: 15, isVip: true), isTrue);
    expect(bulkCountAllowed(count: 16, isVip: true), isFalse);
  });

  test('favorite list drops ids missing from the catalog', () {
    expect(
      favoriteIdsInCatalog(
        storedIds: ['a', 'gone', 'b'],
        knownIds: {'a', 'b'},
      ),
      ['a', 'b'],
    );
  });
}

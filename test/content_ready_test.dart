import 'package:church_portal/core/content_ready.dart';
import 'package:church_portal/domain/daily_verse.dart';
import 'package:church_portal/domain/models.dart';
import 'package:church_portal/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('first content / loading screen (ADR-038)', () {
    final settings = AsyncData<ChurchSettings>(ChurchSettings.fromMap(const {'nameAr': 'x'}));
    const verses = AsyncData<List<Verse>>([]);

    test('waits for settings, the section switches and the hero verses', () {
      expect(firstContentArrived(settings: settings, featuresReady: true, verses: verses), isTrue);
      expect(firstContentArrived(settings: const AsyncLoading(), featuresReady: true, verses: verses), isFalse);
      expect(firstContentArrived(settings: settings, featuresReady: false, verses: verses), isFalse);
      expect(firstContentArrived(settings: settings, featuresReady: true, verses: const AsyncLoading()), isFalse);
    });

    test('a failed input never holds the page', () {
      expect(
          firstContentArrived(
              settings: AsyncError(StateError('x'), StackTrace.empty),
              featuresReady: true,
              verses: AsyncError(StateError('y'), StackTrace.empty)),
          isTrue);
    });

    test('signal is idempotent and releases whenIdle', () async {
      var idle = false;
      ContentReady.whenIdle.then((_) => idle = true);
      expect(ContentReady.signalled, isFalse);
      ContentReady.signal();
      ContentReady.signal();
      expect(ContentReady.signalled, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(idle, isTrue);
    });
  });
}

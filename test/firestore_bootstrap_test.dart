import 'package:church_portal/data/firebase_bootstrap.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('firestoreSettings', () {
    test('web enables multi-tab IndexedDB persistence via WebPersistentMultipleTabManager', () {
      final settings = firestoreSettings(isWeb: true);

      expect(settings.persistenceEnabled, isTrue);
      expect(settings.cacheSizeBytes, 40 * 1024 * 1024);
      expect(settings.webPersistentTabManager, isA<WebPersistentMultipleTabManager>());
    });

    test('native platforms keep existing persistence settings without webPersistentTabManager', () {
      final settings = firestoreSettings(isWeb: false);

      expect(settings.persistenceEnabled, isTrue);
      expect(settings.cacheSizeBytes, 40 * 1024 * 1024);
      expect(settings.webPersistentTabManager, isNull);
    });
  });
}

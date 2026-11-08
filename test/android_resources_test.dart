import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Android Splash & Theme Resources (INV-SPLASH-01)', () {
    test('colors.xml defines splash_cream as #FBF3E4', () {
      final file = File('android/app/src/main/res/values/colors.xml');
      expect(file.existsSync(), isTrue, reason: 'colors.xml exists');
      final content = file.readAsStringSync();
      expect(
        content.contains('<color name="splash_cream">#FBF3E4</color>'),
        isTrue,
        reason: 'splash_cream must be defined as #FBF3E4',
      );
    });

    test('launch_background.xml files use @color/splash_cream and ban white/colorBackground', () {
      final paths = [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ];

      for (final p in paths) {
        final file = File(p);
        expect(file.existsSync(), isTrue, reason: '$p exists');
        final content = file.readAsStringSync();

        expect(
          content.contains('android:drawable="@color/splash_cream"'),
          isTrue,
          reason: '$p must set first item drawable to @color/splash_cream',
        );
        expect(
          content.contains('@android:color/white'),
          isFalse,
          reason: '$p must not contain @android:color/white',
        );
        expect(
          content.contains('?android:colorBackground'),
          isFalse,
          reason: '$p must not contain ?android:colorBackground',
        );
      }
    });

    test('values/styles.xml and values-night/styles.xml use splash_cream and Light parent', () {
      final styles = File('android/app/src/main/res/values/styles.xml');
      expect(styles.existsSync(), isTrue);
      final stylesContent = styles.readAsStringSync();
      expect(stylesContent.contains('<item name="android:windowBackground">@color/splash_cream</item>'), isTrue);
      expect(stylesContent.contains('?android:colorBackground'), isFalse);

      final nightStyles = File('android/app/src/main/res/values-night/styles.xml');
      expect(nightStyles.existsSync(), isTrue);
      final nightContent = nightStyles.readAsStringSync();
      expect(nightContent.contains('<item name="android:windowBackground">@color/splash_cream</item>'), isTrue);
      expect(nightContent.contains('parent="@android:style/Theme.Light.NoTitleBar"'), isTrue);
      expect(nightContent.contains('Theme.Black'), isFalse);
      expect(nightContent.contains('?android:colorBackground'), isFalse);
    });

    test('values-v31 and values-night-v31 define windowSplashScreenBackground in cream', () {
      final v31Paths = [
        'android/app/src/main/res/values-v31/styles.xml',
        'android/app/src/main/res/values-night-v31/styles.xml',
      ];

      for (final p in v31Paths) {
        final file = File(p);
        expect(file.existsSync(), isTrue, reason: '$p must exist for Android 12+');
        final content = file.readAsStringSync();

        expect(
          content.contains('<item name="android:windowSplashScreenBackground">@color/splash_cream</item>'),
          isTrue,
          reason: '$p must set windowSplashScreenBackground to @color/splash_cream',
        );
        expect(
          content.contains('<item name="android:windowBackground">@drawable/launch_background</item>'),
          isTrue,
          reason: '$p LaunchTheme windowBackground',
        );
        expect(
          content.contains('<item name="android:windowBackground">@color/splash_cream</item>'),
          isTrue,
          reason: '$p NormalTheme windowBackground',
        );
      }
    });
  });
}

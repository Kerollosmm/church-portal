// Firebase configuration for project `asafra-church-portal`.
//
// Web and Android values are the real ones registered in the Firebase
// console. iOS has NOT been registered yet: its values are PLACEHOLDERS and
// the app falls back to the bundled seed data on iOS until you run
//   flutterfire configure --project=asafra-church-portal --platforms=ios
// (which regenerates this whole file) or paste the iOS values below.
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const String _placeholderMarker = 'PLACEHOLDER';

  /// Options for the current platform, or null when this platform has no
  /// (real) configuration — the app then runs on bundled seed data.
  static FirebaseOptions? get currentPlatformOrNull {
    final FirebaseOptions? o;
    if (kIsWeb) {
      o = web;
    } else {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          o = android;
        case TargetPlatform.iOS:
          o = ios;
        default:
          o = null;
      }
    }
    if (o == null || !isConfigured(o)) return null;
    return o;
  }

  static bool isConfigured(FirebaseOptions o) =>
      !o.apiKey.contains(_placeholderMarker) && !o.appId.contains(_placeholderMarker);

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBEHiTY84sHSgLeV_cZ8p-kiKX-IWivByU',
    appId: '1:724175543696:web:8c75dcd193c3dc5106a715',
    messagingSenderId: '724175543696',
    projectId: 'asafra-church-portal',
    authDomain: 'asafra-church-portal.firebaseapp.com',
    storageBucket: 'asafra-church-portal.firebasestorage.app',
  );

  // Android app id is real. The API key below is the project's browser key;
  // if Android requests are rejected, replace it with the "current_key" from
  // google-services.json (Firebase console > Project settings > Android app).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBEHiTY84sHSgLeV_cZ8p-kiKX-IWivByU',
    appId: '1:724175543696:android:93a4afeb7a9c7d9806a715',
    messagingSenderId: '724175543696',
    projectId: 'asafra-church-portal',
    storageBucket: 'asafra-church-portal.firebasestorage.app',
  );

  // PLACEHOLDER — iOS app not registered yet.
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'PLACEHOLDER_IOS_API_KEY',
    appId: 'PLACEHOLDER_IOS_APP_ID',
    messagingSenderId: '724175543696',
    projectId: 'asafra-church-portal',
    storageBucket: 'asafra-church-portal.firebasestorage.app',
    iosBundleId: 'com.asafrachurch.churchPortal',
  );
}

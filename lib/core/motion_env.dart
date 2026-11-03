import 'motion_env_stub.dart' if (dart.library.js_interop) 'motion_env_web.dart' as impl;

/// Platform signals for ambient motion and the hero video (ADR-022).
class MotionEnv {
  MotionEnv._();

  /// True under `flutter test`: ambient loops (cloud drift, light rays, Ken
  /// Burns, video) stay still so `pumpAndSettle` settles.
  static bool get isTest => impl.isFlutterTest();

  /// The visitor asked to save data (`navigator.connection.saveData` on web,
  /// Chrome "Lite mode" / Android Data Saver). The hero video never loads then.
  static bool get saveData => impl.saveDataRequested();
}

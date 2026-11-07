import 'push_env_stub.dart'
    if (dart.library.js_interop) 'push_env_web.dart' as impl;

/// Storage key in localStorage for notification preferences.
const pushStorageKey = 'church_portal_push';

/// Abstraction over browser push notification capabilities.
abstract class PushEnv {
  const PushEnv();

  bool get isSupported;
  String get permission;
  Future<String> requestPermission();
}

/// Default platform push environment.
class PlatformPushEnv extends PushEnv {
  const PlatformPushEnv();

  @override
  bool get isSupported => impl.getIsSupported();

  @override
  String get permission => impl.getPermission();

  @override
  Future<String> requestPermission() => impl.requestPermission();
}

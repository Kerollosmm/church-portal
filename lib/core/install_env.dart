import 'install_env_stub.dart'
    if (dart.library.js_interop) 'install_env_web.dart' as impl;

/// Storage key in localStorage for install banner dismiss date.
const installStorageKey = 'church_portal_install';

/// Abstraction over platform/browser APIs for app installation and client storage.
abstract class InstallEnv {
  const InstallEnv();

  String get userAgent;
  String get platform;
  int get maxTouchPoints;
  bool get isStandalone;
  bool get hasDeferredPrompt;
  bool get installedEventReceived;

  void clearInstalledSessionFlag();
  Future<bool> promptInstall();

  Map<String, dynamic>? readJson(String key);
  void writeJson(String key, Map<String, dynamic> data);
  void remove(String key);
}

/// Default platform install environment.
class PlatformInstallEnv extends InstallEnv {
  const PlatformInstallEnv();

  @override
  String get userAgent => impl.getUserAgent();

  @override
  String get platform => impl.getPlatform();

  @override
  int get maxTouchPoints => impl.getMaxTouchPoints();

  @override
  bool get isStandalone => impl.getIsStandalone();

  @override
  bool get hasDeferredPrompt => impl.getHasDeferredPrompt();

  @override
  bool get installedEventReceived => impl.getInstalledEventReceived();

  @override
  void clearInstalledSessionFlag() => impl.clearInstalledSessionFlag();

  @override
  Future<bool> promptInstall() => impl.promptInstall();

  @override
  Map<String, dynamic>? readJson(String key) => impl.readJson(key);

  @override
  void writeJson(String key, Map<String, dynamic> data) => impl.writeJson(key, data);

  @override
  void remove(String key) => impl.removeStorageKey(key);
}

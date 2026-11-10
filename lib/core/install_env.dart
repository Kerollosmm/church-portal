import 'install_env_stub.dart'
    if (dart.library.js_interop) 'install_env_web.dart'
    if (dart.library.io) 'install_env_io.dart' as impl;

/// Preloads device storage on Android (SharedPreferences) so [InstallEnv.readJson] can stay
/// synchronous; a no-op on the web (`localStorage` is synchronous already).
Future<void> initInstallStore() => impl.initInstallStore();

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
  /// Throws when device storage refuses the write.
  void writeJson(String key, Map<String, dynamic> data);
  void remove(String key);

  /// Calls [onChange] when the browser reports an install change after the
  /// banner rendered (`beforeinstallprompt`, `appinstalled`). Returns the
  /// unsubscribe function.
  void Function() listenInstallChanges(void Function() onChange);
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

  @override
  void Function() listenInstallChanges(void Function() onChange) => impl.listenInstallChanges(onChange);
}

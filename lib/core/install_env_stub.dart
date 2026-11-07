// Stub implementation for non-web environments (Android APK / desktop).

String getUserAgent() => '';
String getPlatform() => '';
int getMaxTouchPoints() => 0;
bool getIsStandalone() => false;
bool getHasDeferredPrompt() => false;
bool getInstalledEventReceived() => false;
void clearInstalledSessionFlag() {}
Future<bool> promptInstall() => Future.value(false);
Map<String, dynamic>? readJson(String key) => null;
void writeJson(String key, Map<String, dynamic> data) {}
void removeStorageKey(String key) {}

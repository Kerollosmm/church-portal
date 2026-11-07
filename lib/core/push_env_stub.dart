// Stub implementation for non-web environments (Android APK / desktop).

bool getIsSupported() => false;
String getPermission() => 'denied';
Future<String> requestPermission() => Future.value('denied');

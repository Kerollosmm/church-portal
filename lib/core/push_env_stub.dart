// Stub implementation for non-web environments (Android APK / desktop).

bool getIsSupported() => false;
String getPermission() => 'denied';
Future<String> requestPermission() => Future.value('denied');
Future<bool> showLocalNotification(String title, String body, {String? icon, String? link}) => Future.value(false);


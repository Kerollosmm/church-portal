import 'dart:io' show Platform;

bool isFlutterTest() {
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

bool saveDataRequested() => false;

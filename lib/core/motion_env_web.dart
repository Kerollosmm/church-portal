import 'dart:js_interop';
import 'dart:js_interop_unsafe';

bool isFlutterTest() => false;

bool saveDataRequested() {
  try {
    final nav = globalContext['navigator'] as JSObject?;
    final conn = nav?['connection'] as JSObject?;
    final save = conn?['saveData'];
    return save != null && save.isA<JSBoolean>() && (save as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}

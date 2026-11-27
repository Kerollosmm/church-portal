import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

VoidCallback addWindowFocusListener(VoidCallback onFocus) {
  final focusListener = ((web.Event _) => onFocus()).toJS;
  final visListener = ((web.Event _) {
    if (web.document.visibilityState == 'visible') {
      onFocus();
    }
  }).toJS;
  web.window.addEventListener('focus', focusListener);
  web.document.addEventListener('visibilitychange', visListener);
  return () {
    web.window.removeEventListener('focus', focusListener);
    web.document.removeEventListener('visibilitychange', visListener);
  };
}

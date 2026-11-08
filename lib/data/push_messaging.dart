// FCM push messaging wrapper and platform dispatcher (ADR-059 / PR C).

export 'push_messaging_stub.dart'
    if (dart.library.io) 'push_messaging_io.dart';

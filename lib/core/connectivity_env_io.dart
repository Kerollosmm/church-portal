// Native (Android / iOS / desktop IO) connectivity hint via connectivity_plus.
// Never imported on web (guarded by conditional imports in connectivity_env.dart).

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Pure check: true whenever at least one real network interface is present;
/// false only when there is no network at all ([ConnectivityResult.none] only).
@visibleForTesting
bool isConnectivityOnline(List<ConnectivityResult> results) =>
    results.any((r) => r != ConnectivityResult.none);

bool _isOnline = true;
bool _initialized = false;
Connectivity? _connectivity;
StreamSubscription<List<ConnectivityResult>>? _sub;
final StreamController<bool> _changes = StreamController<bool>.broadcast();

bool get isOnline => _isOnline;

Connectivity _client() => _connectivity ??= Connectivity();

void _update(bool next) {
  if (_isOnline == next) return;
  _isOnline = next;
  if (!_changes.isClosed) {
    _changes.add(next);
  }
}

Future<void> initConnectivityEnv({Connectivity? connectivity}) async {
  _initialized = true;
  if (connectivity != null) {
    _connectivity = connectivity;
  }
  await _sub?.cancel();
  _sub = null;

  try {
    final results = await _client().checkConnectivity().timeout(const Duration(seconds: 2));
    _isOnline = isConnectivityOnline(results);
  } catch (_) {
    // Plugin unavailable (e.g. headless widget tests): keep optimistic default.
  }

  try {
    _sub = _client().onConnectivityChanged.listen(
      (results) => _update(isConnectivityOnline(results)),
      onError: (Object _) {},
    );
  } catch (_) {}
}

Future<bool> checkOnline() async {
  // In headless widget tests where initConnectivityEnv() never ran, avoid
  // spawning a platform-channel / DBus check and 2 s timeout Timer inside FakeAsync.
  if (!_initialized) return _isOnline;
  try {
    final results = await _client().checkConnectivity().timeout(const Duration(seconds: 2));
    final next = isConnectivityOnline(results);
    _update(next);
    return next;
  } catch (_) {
    return _isOnline;
  }
}

Stream<bool> getOnOnlineChanged() => _changes.stream.distinct();

@visibleForTesting
Future<void> resetConnectivityEnvForTest({bool online = true, Connectivity? connectivity}) async {
  await _sub?.cancel();
  _sub = null;
  _connectivity = connectivity;
  _initialized = connectivity != null;
  _isOnline = online;
}

import 'connectivity_env_stub.dart'
    if (dart.library.js_interop) 'connectivity_env_web.dart'
    if (dart.library.io) 'connectivity_env_io.dart' as impl;

/// Initializes platform connectivity monitoring before the first frame.
Future<void> initConnectivityEnv() => impl.initConnectivityEnv();

/// Abstraction over platform connectivity hints (`connectivity_plus` on native
/// IO; `window.navigator.onLine` on web).
///
/// Note: connectivity signals are hints only (lie-fi reports online); real
/// write safety still relies on Firestore server-ack timeouts.
abstract class ConnectivityEnv {
  const ConnectivityEnv();

  /// Latest known connectivity hint (true when at least one network interface
  /// is active or before the first check completes).
  bool get isOnline;

  /// Probes the current connectivity state and updates [isOnline].
  Future<bool> checkOnline();

  /// Emits connectivity changes whenever the platform signal changes.
  Stream<bool> get onOnlineChanged;
}

/// Default platform [ConnectivityEnv] backed by conditional imports.
class PlatformConnectivityEnv extends ConnectivityEnv {
  const PlatformConnectivityEnv();

  @override
  bool get isOnline => impl.isOnline;

  @override
  Future<bool> checkOnline() => impl.checkOnline();

  @override
  Stream<bool> get onOnlineChanged => impl.getOnOnlineChanged();
}

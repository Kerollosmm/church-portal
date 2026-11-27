// Stub implementation of ConnectivityEnv for unsupported platforms.

bool get isOnline => true;

Future<void> initConnectivityEnv() async {}

Future<bool> checkOnline() async => true;

Stream<bool> getOnOnlineChanged() => const Stream<bool>.empty();

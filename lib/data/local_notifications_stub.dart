// Web / no-op stub for local notifications (ADR-058 / PR B).

import '../domain/notify_plan.dart';
import 'local_notifications.dart';

/// Creates the web stub notifier.
LocalNotifier createLocalNotifier({dynamic plugin}) => const LocalNotifierStub();

/// A no-op implementation of [LocalNotifier] for web and unsupported platforms.
class LocalNotifierStub implements LocalNotifier {
  const LocalNotifierStub();

  @override
  Future<void> initialize({void Function(String? payload)? onSelectNotification}) async {}

  @override
  Future<bool> requestPermissions() async => false;

  @override
  Future<bool> canScheduleExactAlarms() async => false;

  @override
  Future<void> schedulePlan(List<PlannedNotification> plan, {String? lang}) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> showInstant(
    int id,
    String title,
    String body, {
    String? channelId,
    String? payload,
  }) async {}

  @override
  Future<int> pendingCount() async => 0;
}

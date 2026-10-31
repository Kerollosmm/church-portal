import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/admin_repository.dart';
import '../data/content_repository.dart';
import '../data/firebase_bootstrap.dart';
import '../domain/models.dart';

/// Overridden in main() after bootstrapping.
final firebaseStatusProvider = Provider<FirebaseStatus>((ref) => FirebaseStatus.unavailable);
final repositoryProvider = Provider<ContentRepository>((ref) => throw UnimplementedError('override in main'));
final adminRepositoryProvider = Provider<AdminRepository?>((ref) => null);

final settingsProvider = StreamProvider<ChurchSettings>((ref) => ref.watch(repositoryProvider).settings());
final alertsProvider = StreamProvider<List<Alert>>((ref) => ref.watch(repositoryProvider).alerts());
final seasonsProvider = StreamProvider<List<Season>>((ref) => ref.watch(repositoryProvider).seasons());
final liturgiesProvider = StreamProvider<List<Liturgy>>((ref) => ref.watch(repositoryProvider).liturgies());
final meetingsProvider = StreamProvider<List<Meeting>>((ref) => ref.watch(repositoryProvider).meetings());
final activitiesProvider = StreamProvider<List<Activity>>((ref) => ref.watch(repositoryProvider).activities());
final clinicsProvider = StreamProvider<List<Clinic>>((ref) => ref.watch(repositoryProvider).clinics());
final facilitiesProvider = StreamProvider<List<Facility>>((ref) => ref.watch(repositoryProvider).facilities());
final priestsProvider = StreamProvider<List<Priest>>((ref) => ref.watch(repositoryProvider).priests());
final milestonesProvider = StreamProvider<List<Milestone>>((ref) => ref.watch(repositoryProvider).milestones());
final saintsProvider = StreamProvider<List<Saint>>((ref) => ref.watch(repositoryProvider).saints());

/// Ticks every 30 s so time-based UI (next mass, "available today") stays fresh.
final nowProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// Whether the assistant entry points should be shown.
final assistantVisibleProvider = Provider<bool>((ref) {
  final fb = ref.watch(firebaseStatusProvider);
  final s = ref.watch(settingsProvider).value;
  // Firebase AI Logic is App Check-enforced: without an active App Check
  // provider (e.g. no reCAPTCHA site key) requests would fail, so hide it.
  return fb.available && fb.appCheckActive && (s?.assistantEnabled ?? false);
});

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() {
    // Shareable English links: ?lang=en
    final q = Uri.base.queryParameters['lang'];
    return q == 'en' ? const Locale('en') : const Locale('ar');
  }
  void toggle() => state = state.languageCode == 'ar' ? const Locale('en') : const Locale('ar');
  void set(Locale l) => state = l;
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);

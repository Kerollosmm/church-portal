import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/reminder_store.dart';
import '../../domain/reminders.dart';
import '../../state/providers.dart';
// The sheet and «تذكيراتي» ship in their own web chunk, fetched on the first
// tap (ADR-057 size budget).
import 'reminder_sheet.dart' deferred as sheet;

/// Button that lets visitors set a custom reminder for an event or liturgy (ADR-057).
class RemindMeButton extends ConsumerWidget {
  final String eventKey;
  final String? occurrence;
  final Map<String, String> title;
  final DateTime startsAt;
  final bool recurring;

  const RemindMeButton({
    super.key,
    required this.eventKey,
    this.occurrence,
    required this.title,
    required this.startsAt,
    this.recurring = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pushSettings = ref.watch(pushSettingsProvider);
    // `push` on, `reminders` offered and the event's source in reminderSources.
    if (!pushSettings.remindsFor(eventKey)) return const SizedBox.shrink();

    // Do not show for past events
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    if (startsAt.isBefore(now)) return const SizedBox.shrink();

    // Exact occurrence (strict: null matches only null), or a recurring
    // «كل مرة» reminder for this event.
    final activeReminder =
        ReminderStore.findIn(ref.watch(userRemindersProvider), eventKey, occurrence: occurrence, startsAt: startsAt);

    final isSet = activeReminder != null;
    final pal = context.pal;
    final titleText = context.pick(title['ar'] ?? '', title['en'] ?? '');

    return Semantics(
      button: true,
      label: context.tr('remindMeSemantic', {'title': titleText}),
      child: isSet
          ? OutlinedButton.icon(
              icon: Icon(Icons.notifications_active, size: 18, color: pal.goldText),
              label: Text(
                context.tr('remindMeSet', {'lead': leadLabel(activeReminder.lead, context.isAr ? 'ar' : 'en')}),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: pal.goldText),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(48, 48),
                side: BorderSide(color: pal.goldText),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () => _open(
                context,
                eventKey: eventKey,
                occurrence: occurrence,
                title: title,
                startsAt: startsAt,
                recurring: recurring,
                existing: activeReminder,
              ),
            )
          : TextButton.icon(
              icon: Icon(Icons.notifications_none_outlined, size: 18, color: pal.primary),
              label: Text(
                context.tr('remindMe'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              onPressed: () => _open(
                context,
                eventKey: eventKey,
                occurrence: occurrence,
                title: title,
                startsAt: startsAt,
                recurring: recurring,
                existing: activeReminder,
              ),
            ),
    );
  }


  Future<void> _open(
    BuildContext context, {
    required String eventKey,
    String? occurrence,
    required Map<String, String> title,
    required DateTime startsAt,
    bool recurring = false,
    Reminder? existing,
  }) async {
    try {
      await sheet.loadLibrary();
    } catch (_) {
      return; // offline: the button simply does nothing this time
    }
    if (!context.mounted) return;
    await sheet.showReminderSheet(
      context,
      eventKey: eventKey,
      occurrence: occurrence,
      title: title,
      startsAt: startsAt,
      recurring: recurring,
      existing: existing,
    );
  }
}

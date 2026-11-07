import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/push.dart';
import '../../domain/reminders.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';

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
    if (!pushSettings.enabled || !pushSettings.offered.contains(NotifyType.reminders)) {
      return const SizedBox.shrink();
    }

    // Do not show for past events
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    if (startsAt.isBefore(now)) return const SizedBox.shrink();

    final reminders = ref.watch(userRemindersProvider);
    Reminder? activeReminder;
    for (final r in reminders) {
      if (r.eventKey == eventKey && (occurrence == null || r.occurrence == occurrence)) {
        activeReminder = r;
        break;
      }
    }

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
              onPressed: () => showReminderSheet(
                context,
                ref: ref,
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
              onPressed: () => showReminderSheet(
                context,
                ref: ref,
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
}

/// Displays the bottom sheet allowing the visitor to configure and save a reminder.
Future<void> showReminderSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String eventKey,
  String? occurrence,
  required Map<String, String> title,
  required DateTime startsAt,
  bool recurring = false,
  Reminder? existing,
}) {
  final pal = context.pal;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _ReminderConfigSheet(
      ref: ref,
      eventKey: eventKey,
      occurrence: occurrence,
      title: title,
      startsAt: startsAt,
      recurring: recurring,
      existing: existing,
    ),
  );
}

class _ReminderConfigSheet extends StatefulWidget {
  final WidgetRef ref;
  final String eventKey;
  final String? occurrence;
  final Map<String, String> title;
  final DateTime startsAt;
  final bool recurring;
  final Reminder? existing;

  const _ReminderConfigSheet({
    required this.ref,
    required this.eventKey,
    this.occurrence,
    required this.title,
    required this.startsAt,
    this.recurring = false,
    this.existing,
  });

  @override
  State<_ReminderConfigSheet> createState() => _ReminderConfigSheetState();
}

class _ReminderConfigSheetState extends State<_ReminderConfigSheet> {
  late int _selectedLead;
  late bool _every;

  @override
  void initState() {
    super.initState();
    final pushSettings = widget.ref.read(pushSettingsProvider);
    _selectedLead = widget.existing?.lead ?? pushSettings.defaultLead;
    _every = widget.existing?.every ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final pushSettings = widget.ref.watch(pushSettingsProvider);
    final leads = pushSettings.reminderLeads;
    final now = widget.ref.watch(nowProvider).value ?? DateTime.now();

    final titleText = context.pick(widget.title['ar'] ?? '', widget.title['en'] ?? '');
    final dateStr = formatDate(widget.startsAt, arabic: context.isAr);
    final hm = '${widget.startsAt.hour.toString().padLeft(2, '0')}:${widget.startsAt.minute.toString().padLeft(2, '0')}';
    final timeStr = context.isAr ? formatTimeArabic(hm) : formatTimeLatin(hm);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: pal.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Header
                  Text(
                    context.tr('remindSheetTitle'),
                    style: AppFonts.heading(size: 19, color: pal.primaryDeep),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    titleText,
                    style: TextStyle(
                      fontFamily: AppFonts.body,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: pal.ink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$dateStr • $timeStr',
                    style: TextStyle(fontSize: 13, color: pal.muted),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  Text(
                    context.tr('remindLeadPrompt'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: pal.ink),
                  ),
                  const SizedBox(height: 8),

                  // Leads list
                  Column(
                    children: [
                      for (final lead in leads)
                        // ignore: deprecated_member_use
                        RadioListTile<int>(
                          value: lead,
                          // ignore: deprecated_member_use
                          groupValue: _selectedLead,
                          title: Row(
                            children: [
                              Text(leadLabel(lead, context.isAr ? 'ar' : 'en'), style: TextStyle(color: widget.startsAt.subtract(Duration(minutes: lead)).isBefore(now) ? pal.muted : pal.ink)),
                              if (widget.startsAt.subtract(Duration(minutes: lead)).isBefore(now)) ...[
                                const SizedBox(width: 8),
                                Text(
                                  context.tr('remindLeadPast'),
                                  style: TextStyle(fontSize: 12, color: pal.muted.withValues(alpha: 0.8)),
                                ),
                              ],
                            ],
                          ),
                          activeColor: pal.primary,
                          // ignore: deprecated_member_use
                          onChanged: widget.startsAt.subtract(Duration(minutes: lead)).isBefore(now) ? null : (v) => setState(() => _selectedLead = v!),
                        ),
                    ],
                  ),

                  // Recurring choice
                  if (widget.recurring) ...[
                    const SizedBox(height: 10),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(context.tr('remindOccurrenceSingle')),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(context.tr('remindOccurrenceEvery')),
                        ),
                      ],
                      selected: {_every},
                      onSelectionChanged: (val) => setState(() => _every = val.first),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Web delay notice & add to calendar
                  if (kIsWeb)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: pal.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: pal.hairline),
                      ),
                      child: Text(
                        context.tr('remindWebDelayNotice'),
                        style: TextStyle(fontSize: 12, color: pal.muted, height: 1.5),
                      ),
                    ),

                  const SizedBox(height: 18),

                  // Buttons
                  Row(
                    children: [
                      if (widget.existing != null) ...[
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            foregroundColor: pal.alert,
                            side: BorderSide(color: pal.alert),
                          ),
                          onPressed: () {
                            widget.ref
                                .read(userRemindersProvider.notifier)
                                .remove(widget.eventKey, occurrence: widget.occurrence);
                            Navigator.of(context).pop();
                          },
                          child: Text(context.tr('remindCancelButton')),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: () {
                            final reminder = Reminder(
                              eventKey: widget.eventKey,
                              occurrence: widget.occurrence,
                              lead: _selectedLead,
                              every: _every,
                              title: widget.title,
                              startsAt: widget.startsAt,
                              createdAt: DateTime.now().toUtc(),
                            );
                            final success = widget.ref.read(userRemindersProvider.notifier).put(reminder);
                            Navigator.of(context).pop();

                            if (!success) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(context.tr('myRemindersMaxReached'))),
                              );
                            }
                          },
                          child: Text(context.tr('remindSaveButton')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The «تذكيراتي» list widget embedded into /notifications (ADR-057).
class MyRemindersSection extends ConsumerWidget {
  const MyRemindersSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reminders = ref.watch(userRemindersProvider);
    final pal = context.pal;
    final now = ref.watch(nowProvider).value ?? DateTime.now();

    if (reminders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: pal.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: pal.hairline),
        ),
        child: Center(
          child: Text(
            context.tr('myRemindersEmpty'),
            style: TextStyle(color: pal.muted, fontSize: 14),
          ),
        ),
      );
    }

    final hasExpired = reminders.any((r) => r.isExpired(now));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.tr('myRemindersTitle'),
              style: AppFonts.heading(size: 18, color: pal.primaryDeep),
            ),
            if (hasExpired)
              TextButton(
                onPressed: () => ref.read(userRemindersProvider.notifier).clearExpired(now),
                child: Text(context.tr('myRemindersClearExpired'), style: TextStyle(color: pal.primary)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reminders.length,
          separatorBuilder: (ctx, i) => const SizedBox(height: 8),
          itemBuilder: (ctx, i) {
            final r = reminders[i];
            final expired = r.isExpired(now);
            final title = context.pick(r.title['ar'] ?? '', r.title['en'] ?? '');
            final lead = leadLabel(r.lead, context.isAr ? 'ar' : 'en');
            final dateStr = formatDate(r.startsAt, arabic: context.isAr);
            final hm = '${r.startsAt.hour.toString().padLeft(2, '0')}:${r.startsAt.minute.toString().padLeft(2, '0')}';
            final timeStr = context.isAr ? formatTimeArabic(hm) : formatTimeLatin(hm);

            return Dismissible(
              key: Key(r.id),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: pal.alert,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.delete_outline, color: pal.onPrimary),
              ),
              onDismissed: (_) {
                ref.read(userRemindersProvider.notifier).remove(r.eventKey, occurrence: r.occurrence);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: pal.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: pal.hairline),
                ),
                child: Row(
                  children: [
                    Icon(
                      expired ? Icons.event_busy : Icons.alarm,
                      color: expired ? pal.muted : pal.goldText,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title.isNotEmpty ? title : r.eventKey,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: expired ? pal.muted : pal.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$dateStr • $timeStr (${context.tr('remindMeSet', {'lead': lead})})',
                            style: TextStyle(fontSize: 12.5, color: pal.muted),
                          ),
                          if (r.every)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                context.tr('remindOccurrenceEvery'),
                                style: TextStyle(fontSize: 11, color: pal.goldText, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: pal.muted,
                      tooltip: context.tr('remindCancelButton'),
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      onPressed: () {
                        ref.read(userRemindersProvider.notifier).remove(r.eventKey, occurrence: r.occurrence);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

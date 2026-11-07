import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/reminder_store.dart';
import '../../domain/cairo_time.dart';
import '../../domain/push.dart';
import '../../domain/reminders.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';

/// Strings only this deferred chunk uses (registered before it builds).
const Map<String, List<String>> reminderSheetStrings = {
  'remindSheetTitle': ['تذكير بموعد', 'Event reminder'],
  'remindLeadPrompt': ['متى تحب أن نذكّرك؟', 'When would you like to be reminded?'],
  'remindLeadPast': ['(فات موعد التنبيه)', '(Reminder time has passed)'],
  'remindOccurrenceSingle': ['هذه المرة فقط', 'This time only'],
  'remindOccurrenceEvery': ['كل مرة (تكرار)', 'Every time (recurring)'],
  'remindWebDelayNotice': ['يصل التذكير عبر الإنترنت وقد يتأخر حتى ٣٠ دقيقة تقريبًا — للتنبيه في الموعد بالضبط يمكنك استخدام «أضف إلى التقويم»', 'Online reminders may arrive up to ~30 minutes late. For exact-time alerts, you can also use "Add to calendar"'],
  'remindSaveButton': ['حفظ التذكير', 'Save reminder'],
  'remindCancelButton': ['إلغاء التذكير', 'Cancel reminder'],
  'myRemindersTitle': ['تذكيراتي', 'My reminders'],
  'myRemindersEmpty': ['لا توجد تذكيرات مجدولة حاليًا.', 'No scheduled reminders currently.'],
  'myRemindersMaxReached': ['وصلت للحد الأقصى للتذكيرات (٣٠ تذكيرًا). ألغِ بعض التذكيرات لإضافة غيرها.', 'Maximum limit of 30 reminders reached. Remove some reminders to add more.'],
  'myRemindersClearExpired': ['مسح التذكيرات المنتهية', 'Clear expired reminders'],
  'remindStorageError': ['تعذّر حفظ التذكير على هذا الجهاز — قد يكون التخزين ممتلئًا أو مقفولًا في وضع التصفح الخاص.', 'Could not save the reminder on this device — storage may be full or blocked in private browsing.'],
  'remindNoLeadLeft': ['فاتت كل مواعيد التنبيه لهذه المرة.', 'All reminder times for this occurrence have passed.'],
};

/// Displays the bottom sheet allowing the visitor to configure and save a reminder.
Future<void> showReminderSheet(
  BuildContext context, {
  required String eventKey,
  String? occurrence,
  required Map<String, String> title,
  required DateTime startsAt,
  bool recurring = false,
  Reminder? existing,
}) {
  registerStrings(reminderSheetStrings);
  final pal = context.pal;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: pal.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _ReminderConfigSheet(
      eventKey: eventKey,
      occurrence: occurrence,
      title: title,
      startsAt: startsAt,
      recurring: recurring,
      existing: existing,
    ),
  );
}

/// Its own [ConsumerStatefulWidget] so the clock and the admin settings
/// rebuild it while it is open (a lead whose time passes gets disabled).
class _ReminderConfigSheet extends ConsumerStatefulWidget {
  final String eventKey;
  final String? occurrence;
  final Map<String, String> title;
  final DateTime startsAt;
  final bool recurring;
  final Reminder? existing;

  const _ReminderConfigSheet({
    required this.eventKey,
    this.occurrence,
    required this.title,
    required this.startsAt,
    this.recurring = false,
    this.existing,
  });

  @override
  ConsumerState<_ReminderConfigSheet> createState() => _ReminderConfigSheetState();
}

/// The lead to pre-select in the reminder sheet: [preferred] (the existing
/// reminder's lead, else the admin default) while its fire time is still
/// ahead of [now], else the longest lead that is still ahead (the earliest
/// still-valid reminder), else `null` when every lead has passed (save is
/// disabled then).
@visibleForTesting
int? initialReminderLead({
  required int preferred,
  required List<int> leads,
  required DateTime startsAt,
  required DateTime now,
}) {
  bool ok(int lead) => !startsAt.subtract(Duration(minutes: lead)).isBefore(now);
  if (leads.contains(preferred) && ok(preferred)) return preferred;
  final valid = leads.where(ok).toList()..sort();
  return valid.isEmpty ? null : valid.last;
}

class _ReminderConfigSheetState extends ConsumerState<_ReminderConfigSheet> {
  int? _selectedLead;
  late bool _every;
  bool _storageError = false;

  @override
  void initState() {
    super.initState();
    final pushSettings = ref.read(pushSettingsProvider);
    final now = ref.read(nowProvider).value ?? DateTime.now();
    _selectedLead = initialReminderLead(
      preferred: widget.existing?.lead ?? pushSettings.defaultLead,
      leads: pushSettings.reminderLeads,
      startsAt: widget.startsAt,
      now: now,
    );
    _every = widget.existing?.every ?? false;
  }

  bool _leadPast(int lead, DateTime now) => widget.startsAt.subtract(Duration(minutes: lead)).isBefore(now);

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final pushSettings = ref.watch(pushSettingsProvider);
    final leads = pushSettings.reminderLeads;
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    // Saveable only with an offered lead whose fire time is still ahead.
    final lead = _selectedLead;
    final canSave = lead != null && leads.contains(lead) && !_leadPast(lead, now);

    final titleText = context.pick(widget.title['ar'] ?? '', widget.title['en'] ?? '');
    final cairoStartsAt = CairoTime.fromInstant(widget.startsAt);
    final dateStr = formatDate(cairoStartsAt, arabic: context.isAr);
    final hm = '${cairoStartsAt.hour.toString().padLeft(2, '0')}:${cairoStartsAt.minute.toString().padLeft(2, '0')}';
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
                              Flexible(
                                child: Text(leadLabel(lead, context.isAr ? 'ar' : 'en'),
                                    style: TextStyle(color: _leadPast(lead, now) ? pal.muted : pal.ink)),
                              ),
                              if (_leadPast(lead, now)) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    context.tr('remindLeadPast'),
                                    style: TextStyle(fontSize: 12, color: pal.muted),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          activeColor: pal.primary,
                          // ignore: deprecated_member_use
                          onChanged: _leadPast(lead, now) ? null : (v) => setState(() => _selectedLead = v),
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

                  // Platform delivery line (web: may arrive ~30 min late) —
                  // shown once a delivery path exists (PR B / PR D).
                  if (kIsWeb && kPushDeliveryShipped)
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

                  if (_storageError || leads.every((l) => _leadPast(l, now))) ...[
                    const SizedBox(height: 10),
                    Text(
                      context.tr(_storageError ? 'remindStorageError' : 'remindNoLeadLeft'),
                      key: const Key('remindSheetError'),
                      style: TextStyle(fontSize: 13, color: pal.alert, height: 1.5),
                    ),
                  ],

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
                            ref
                                .read(userRemindersProvider.notifier)
                                .remove(widget.eventKey, occurrence: widget.existing!.occurrence);
                            Navigator.of(context).pop();
                          },
                          child: Text(context.tr('remindCancelButton')),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                          onPressed: !canSave
                              ? null
                              : () {
                                  // «كل مرة» covers every occurrence: stored without one.
                                  final reminder = Reminder(
                                    eventKey: widget.eventKey,
                                    occurrence: _every ? null : widget.occurrence,
                                    lead: _selectedLead!,
                                    every: _every,
                                    title: widget.title,
                                    startsAt: widget.startsAt,
                                    createdAt: DateTime.now().toUtc(),
                                  );
                                  final result = ref
                                      .read(userRemindersProvider.notifier)
                                      .put(reminder, replacing: widget.existing);
                                  switch (result) {
                                    case ReminderPutResult.ok:
                                      Navigator.of(context).pop();
                                    case ReminderPutResult.storageError:
                                      setState(() => _storageError = true);
                                    case ReminderPutResult.full:
                                      final messenger = ScaffoldMessenger.of(context);
                                      final msg = context.tr('myRemindersMaxReached');
                                      Navigator.of(context).pop();
                                      messenger.showSnackBar(SnackBar(content: Text(msg)));
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
    registerStrings(reminderSheetStrings);
    final pal = context.pal;
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    // Sorted by next fire time (a recurring reminder by its next occurrence).
    final reminders = List<Reminder>.of(ref.watch(userRemindersProvider))
      ..sort((a, b) => a.nextFireTime(now).compareTo(b.nextFireTime(now)));

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
            // Cairo wall time of the next occurrence (a recurring reminder
            // rolls forward weekly; the stored instant is UTC).
            final cairoStartsAt = CairoTime.fromInstant(r.nextStartsAt(now));
            final dateStr = formatDate(cairoStartsAt, arabic: context.isAr);
            final hm = '${cairoStartsAt.hour.toString().padLeft(2, '0')}:${cairoStartsAt.minute.toString().padLeft(2, '0')}';
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

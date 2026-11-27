import 'dart:async';

import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/content_repository.dart';
import '../../data/error_reporting.dart';
import '../../domain/cairo_time.dart';
import '../../domain/error_privacy.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/map_embed.dart';
import 'home_page.dart' show PhoneRow;

/// Shared across visits to the page within a session.
var _rateLimiter = ContactRateLimiter();

@visibleForTesting
void resetContactRateLimiterForTest({
  Duration minInterval = const Duration(seconds: 60),
  int maxPerWindow = 3,
}) =>
    _rateLimiter = ContactRateLimiter(minInterval: minInterval, maxPerWindow: maxPerWindow);

class ContactPage extends ConsumerWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final f = ref.watch(featuresProvider);
    final showInfo = f.enabled(Sections.contactInfo);
    final showSocial = f.enabled(Sections.socials);
    final showForm = f.enabled(Sections.contactForm);
    return PageBody(
      header: CustomizablePageHeader(
          pageKey: CustomizablePages.contact,
          title: context.tr('contact'), subtitle: context.tr('dir_contact'), icon: Icons.call_rounded),
      children: [
        const PageIntro(pageKey: CustomizablePages.contact),
        AsyncSection<ChurchSettings>(
          provider: settingsProvider,
          retry: settingsProvider,
          loading: const SkeletonList(count: 2, itemHeight: 220),
          builder: (context, s) {
            final hasInfo = showInfo || showSocial;
            final info = _InfoColumn(s: s, showInfo: showInfo, showSocial: showSocial);
            const form = ContactForm();
            final Widget top;
            if (hasInfo && showForm) {
              top = wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: info),
                      const SizedBox(width: 16),
                      const Expanded(child: form),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 16), form]);
            } else {
              top = hasInfo ? info : (showForm ? form : const SizedBox.shrink());
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              top,
              if (showInfo) ...[
                SectionTitle(context.tr('location'), icon: Icons.location_on_rounded),
                ChurchMap(settings: s, height: 380),
              ],
            ]);
          },
        ),
      ],
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final ChurchSettings s;
  final bool showInfo, showSocial;
  const _InfoColumn({required this.s, this.showInfo = true, this.showSocial = true});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (showInfo) ...[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('phones'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: context.pal.primary)),
            const SizedBox(height: 6),
            for (final p in s.phones) PhoneRow(phone: p),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      ],
      if (showSocial) ...[
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('social'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: context.pal.primary)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (s.whatsappChannel.isNotEmpty)
                ActionChipButton(
                    icon: Icons.campaign_rounded,
                    label: context.tr('whatsappChannel'),
                    color: whatsappGreen,
                    onTap: () => openUrl(s.whatsappChannel)),
              if (s.whatsapp.isNotEmpty)
                ActionChipButton(
                    icon: Icons.chat_rounded,
                    label: context.tr('whatsapp'),
                    color: whatsappGreen,
                    onTap: () => openWhatsApp(s.whatsapp)),
              if (s.facebook.isNotEmpty)
                ActionChipButton(
                    icon: Icons.facebook, label: context.tr('facebook'), color: facebookBlue, onTap: () => openUrl(s.facebook)),
              if (s.youtube.isNotEmpty)
                ActionChipButton(
                    icon: Icons.live_tv_rounded,
                    label: context.tr('youtube'),
                    color: youtubeRed,
                    onTap: () => openUrl(s.youtube)),
              if (s.instagram.isNotEmpty)
                ActionChipButton(
                    icon: Icons.photo_camera_rounded,
                    label: context.tr('instagram'),
                    color: instagramPink,
                    onTap: () => openUrl(s.instagram)),
            ]),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      ],
      if (showInfo)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.tr('address'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: context.pal.primary)),
            const SizedBox(height: 6),
            IconLine(Icons.location_on_outlined, context.pick(s.addressAr, s.addressEn),
                style: const TextStyle(fontWeight: FontWeight.w700, height: 1.5)),
            const SizedBox(height: 10),
            Text(context.tr('transport'), style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            IconLine(Icons.directions_bus_outlined, context.pick(s.transportAr, s.transportEn)),
          ]),
        ),
      ),
    ]);
  }
}

/// Public contact form (no login). Validated client-side with the same
/// limits enforced by firestore.rules, plus a client-side rate limit.
class ContactForm extends ConsumerStatefulWidget {
  const ContactForm({super.key});

  @override
  ConsumerState<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<ContactForm> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();
  final _honeypot = TextEditingController();
  final _date = TextEditingController();
  Map<ContactField, ContactError> _errors = const {};

  /// Chosen category slot (ADR-028); null = the first visible one.
  String? _slot;
  int _resetCount = 0;
  bool _anonymous = false;
  String _bookingType = '';
  bool _sending = false;
  bool _consented = false;
  String? _status;
  _ContactStatusTone _statusTone = _ContactStatusTone.error;
  ContactDraft? _queuedDraftBaseline;
  int _formRevision = 0;
  int? _queuedRevision;
  bool _suppressRevisionBump = false;

  void _bumpRevision() {
    if (!_suppressRevisionBump) {
      _formRevision++;
    }
  }

  void _runWithoutRevisionBump(void Function() fn) {
    final prev = _suppressRevisionBump;
    _suppressRevisionBump = true;
    try {
      fn();
    } finally {
      _suppressRevisionBump = prev;
    }
  }

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _email, _message, _date]) {
      c.addListener(_bumpRevision);
    }
    final queue = ref.read(contactQueueProvider);
    if (queue.draft != null) {
      _runWithoutRevisionBump(() => _restoreDraft(queue.draft!));
      _queuedDraftBaseline = queue.draft;
      _queuedRevision = _formRevision;
    }
  }

  void _restoreDraft(ContactDraft draft) {
    final base = _queuedDraftBaseline;
    bool canRestoreText(String current, String baseVal) =>
        base != null ? current == baseVal : current.isEmpty;

    if (canRestoreText(_name.text, base?.name ?? '')) _name.text = draft.name;
    if (canRestoreText(_phone.text, base?.phone ?? '')) _phone.text = draft.phone;
    if (canRestoreText(_email.text, base?.email ?? '')) _email.text = draft.email;
    if (canRestoreText(_message.text, base?.message ?? '')) _message.text = draft.message;
    if (canRestoreText(_date.text, base?.preferredDate ?? '')) _date.text = draft.preferredDate;

    var slotChanged = false;
    if (base != null ? _slot == base.slot : _slot == null) {
      if (_slot != draft.slot) {
        _slot = draft.slot;
        slotChanged = true;
      }
    }
    if (base != null ? _bookingType == base.bookingType : _bookingType.isEmpty) {
      _bookingType = draft.bookingType;
    }
    if (base != null ? _anonymous == base.anonymous : !_anonymous) {
      _anonymous = draft.anonymous;
    }
    if (base != null ? _consented == base.consented : !_consented) {
      _consented = draft.consented;
    }
    if (slotChanged || base == null) {
      _resetCount++;
    }
  }

  ContactDraft _collectDraft() => ContactDraft(
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        message: _message.text,
        preferredDate: _date.text,
        slot: _slot,
        bookingType: _bookingType,
        anonymous: _anonymous,
        consented: _consented,
      );

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _message, _date]) {
      c.removeListener(_bumpRevision);
    }
    for (final c in [_name, _phone, _email, _message, _honeypot, _date]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _err(ContactField f) {
    final e = _errors[f];
    if (e == null) return null;
    return context.tr(switch (e) {
      ContactError.nameLength => 'errNameLength',
      ContactError.phoneInvalid => 'errPhone',
      ContactError.emailInvalid => 'errEmail',
      ContactError.phoneOrEmailRequired => 'errPhoneOrEmail',
      ContactError.messageLength => 'errMessage',
      ContactError.consentRequired => 'errConsent',
      ContactError.phoneRequired => 'errPhoneRequired',
      ContactError.subtypeRequired => 'errSubtype',
      ContactError.dateInvalid => 'errDate',
    });
  }

  /// The contact types, without the wedding booking choice while the season
  /// preset hides it (ADR-042).
  static ContactSettings _contactSettings(ContactSettings? stored, bool weddingOff) {
    final cfg = stored ?? ContactSettings.defaults;
    return weddingOff ? cfg.withoutWedding() : cfg;
  }

  Future<void> _submit() async {
    if (_sending || ref.read(contactQueueProvider).hasPendingWrites) return; // a submission is already in flight or queued
    FocusScope.of(context).unfocus();
    final cat = _category(
        _contactSettings(ref.read(contactSettingsProvider).value, ref.read(featuresProvider).weddingBookingOff));
    final v = validateContactForm(ContactFormInput(
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      message: _message.text,
      consented: _consented,
      category: cat,
      anonymous: _anonymous,
      bookingType: _bookingType,
      preferredDate: _date.text,
      today: _cairoToday(),
    ));
    setState(() {
      _errors = v.errors;
      _status = null;
    });
    if (!v.isValid) return;
    // Bots fill hidden fields: pretend success, send nothing.
    if (_honeypot.text.isNotEmpty) {
      _done(context.tr('sent'), _ContactStatusTone.success);
      return;
    }
    final now = DateTime.now();
    final wait = _rateLimiter.waitTime(now);
    if (wait > Duration.zero) {
      setState(() {
        _status = context.tr('rateLimited', {'t': localDigits(context, '${wait.inSeconds + 1}')});
        _statusTone = _ContactStatusTone.error;
      });
      return;
    }
    final lang = context.isAr ? 'ar' : 'en';
    final msgs = (
      sent: context.tr('sent'),
      queuedOffline: context.tr('contactQueuedOffline'),
      timeoutRetry: context.tr('sendTimeoutRetry'),
      unavailable: context.tr('contactUnavailable'),
      failed: context.tr('sendFailed'),
    );
    ref.read(contactQueueProvider.notifier).clearNotice();
    final draft = _collectDraft();
    final submittedRevision = _formRevision;
    setState(() => _sending = true);
    try {
      final result = await ref.read(contactQueueProvider.notifier).submit(
            payload: v.payload!,
            lang: lang,
            draft: draft,
            onSynced: () => _rateLimiter.recordSubmission(DateTime.now()),
            onRejected: () => _rateLimiter.recordSubmission(DateTime.now()),
          );
      if (result.isQueuedOffline) {
        _queuedDraftBaseline = draft;
        _queuedRevision = submittedRevision;
        _done(msgs.queuedOffline, _ContactStatusTone.queued);
      } else {
        _done(msgs.sent, _ContactStatusTone.success, clearForm: _formRevision == submittedRevision);
      }
    } on TimeoutException {
      // Not confirmed in time. Firestore may still deliver the queued batch
      // (a resend would duplicate it) or the server throttle may reject it,
      // so never promise delivery and never invite a resend: keep the
      // visitor's text in the form so it is not lost, point them to the
      // church office, and throttle an immediate resend.
      _rateLimiter.recordSubmission(now);
      _done(msgs.timeoutRetry, _ContactStatusTone.error);
    } on ContactUnavailableException {
      _done(msgs.unavailable, _ContactStatusTone.error);
    } catch (e, st) {
      // The error only (never the form's text, ADR-034). A permission-denied
      // write is usually the server-side throttle, but also any rules
      // rejection (schema drift): reported, tagged so it can be filtered.
      ErrorReporting.capture(ContactSubmitFailure(e.runtimeType.toString(), scrubText('$e')), st,
          section: 'contact', source: '$e'.contains('permission-denied') ? 'permission-denied' : null);
      _done(msgs.failed, _ContactStatusTone.error);
    }
  }

  void _done(String msg, _ContactStatusTone tone, {bool clearForm = true}) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _status = msg;
      _statusTone = tone;
      if (tone == _ContactStatusTone.success && clearForm) {
        _clearFormFields();
      }
    });
  }

  void _clearFormFields() {
    _runWithoutRevisionBump(() {
      _queuedDraftBaseline = null;
      _queuedRevision = null;
      _name.clear();
      _phone.clear();
      _email.clear();
      _message.clear();
      _date.clear();
      _bookingType = '';
      _slot = null;
      _resetCount++;
      _anonymous = false;
      _consented = false; // each message needs its own consent
      TextInput.finishAutofillContext(shouldSave: true);
    });
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  DateTime _cairoTodayDate() {
    final c = CairoTime.fromInstant(ref.read(nowProvider).value ?? DateTime.now());
    return DateTime(c.year, c.month, c.day);
  }

  String _cairoToday() {
    final c = _cairoTodayDate();
    return '${c.year}-${_two(c.month)}-${_two(c.day)}';
  }

  /// The selected category (the first visible one by default), or null when
  /// none is configured (legacy message without a category).
  ContactCategory? _category(ContactSettings cfg) {
    final list = cfg.visible;
    for (final c in list) {
      if (c.slot == _slot) return c;
    }
    return list.isEmpty ? null : list.first;
  }

  Future<void> _pickDate() async {
    final today = _cairoTodayDate();
    final lastDate = DateTime(today.year + 2, 12, 31);
    final parsed = DateTime.tryParse(_date.text);
    final initial = parsed == null || parsed.isBefore(today) || parsed.isAfter(lastDate) ? today : parsed;
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      currentDate: today,
      lastDate: lastDate,
      initialDate: initial,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date.text = '${picked.year}-${_two(picked.month)}-${_two(picked.day)}';
      _errors = Map.of(_errors)..remove(ContactField.date);
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ContactQueueState>(contactQueueProvider, (prev, next) {
      if (!mounted) return;
      if (prev?.phase == ContactQueuePhase.pending && next.phase == ContactQueuePhase.sent) {
        setState(() {
          _sending = false;
          _status = context.tr('sent');
          _statusTone = _ContactStatusTone.success;
          if (_queuedRevision == null || _formRevision == _queuedRevision) {
            _clearFormFields();
          } else {
            _queuedDraftBaseline = null;
            _queuedRevision = null;
          }
        });
      } else if (prev?.phase != ContactQueuePhase.failed && next.phase == ContactQueuePhase.failed) {
        setState(() {
          _sending = false;
          if (next.draft != null && (_queuedRevision == null || _formRevision == _queuedRevision)) {
            _runWithoutRevisionBump(() => _restoreDraft(next.draft!));
          }
          _queuedDraftBaseline = null;
          _queuedRevision = null;
          _status = context.tr('contactQueuedFailed');
          _statusTone = _ContactStatusTone.error;
        });
      }
    });

    final queue = ref.watch(contactQueueProvider);
    final hasPendingWrites = queue.hasPendingWrites;
    final String? visibleStatus;
    final _ContactStatusTone visibleTone;
    if (hasPendingWrites) {
      visibleStatus = context.tr('contactQueuedOffline');
      visibleTone = _ContactStatusTone.queued;
    } else if (_status == null && queue.phase == ContactQueuePhase.failed) {
      visibleStatus = context.tr('contactQueuedFailed');
      visibleTone = _ContactStatusTone.error;
    } else {
      visibleStatus = _status;
      visibleTone = _statusTone;
    }

    final contactErr = _err(ContactField.contact);
    final cfg = _contactSettings(ref.watch(contactSettingsProvider).value,
        ref.watch(featuresProvider.select((f) => f.weddingBookingOff)));
    final cats = cfg.visible;
    final cat = _category(cfg);
    final anonymous = _anonymous && (cat?.allowsAnonymous ?? false);
    final booking = cat?.isBooking ?? false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.tr('contactForm'),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: context.pal.primary)),
            if (queue.hasUnverifiedPrevious) ...[
              const SizedBox(height: 10),
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const Key('contactUnverifiedNotice'),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: context.pal.notice,
                    border: Border.all(color: context.pal.noticeEdge),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(Icons.info_outline_rounded, color: context.pal.noticeInk),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr('contactUnverifiedPrevious'),
                          style: TextStyle(color: context.pal.noticeInk, fontWeight: FontWeight.w600, height: 1.45),
                        ),
                      ),
                      IconButton(
                        key: const Key('dismissUnverifiedContactButton'),
                        tooltip: context.tr('close'),
                        onPressed: () => ref.read(contactQueueProvider.notifier).dismissUnverifiedNotice(),
                        icon: Icon(Icons.close_rounded, color: context.pal.noticeInk),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (cats.length > 1) ...[
              // Rebuilt when the admin-managed list (settings/contact,
              // ADR-028) arrives or changes: a form field keeps its first
              // value, so a default type must not stay selected (PR #23).
              KeyedSubtree(
                key: ValueKey('contactCats-$_resetCount-${[for (final c in cats) c.slot].join(',')}'),
                child: DropdownButtonFormField<String>(
                  key: const Key('contactCategory'),
                  isExpanded: true,
                  initialValue: cat?.slot,
                  decoration: InputDecoration(labelText: context.tr('contactCategory'), prefixIcon: const Icon(Icons.forum_outlined)),
                  items: [
                    for (final c in cats) DropdownMenuItem(value: c.slot, child: Text(context.pick(c.labelAr, c.labelEn))),
                  ],
                  onChanged: (v) => setState(() {
                    _formRevision++;
                    _slot = v;
                    _bookingType = '';
                    _errors = const {};
                  }),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (cat?.allowsAnonymous ?? false) ...[
              SwitchListTile(
                key: const Key('anonSwitch'),
                contentPadding: EdgeInsets.zero,
                title: Text(context.tr('sendAnonymously'), style: const TextStyle(fontWeight: FontWeight.w700)),
                value: _anonymous,
                onChanged: (v) => setState(() {
                  _formRevision++;
                  _anonymous = v;
                  _errors = const {};
                }),
              ),
              if (anonymous)
                Container(
                  key: const Key('anonHint'),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.pal.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.pal.hairline),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.privacy_tip_outlined, color: context.pal.goldText),
                    const SizedBox(width: 8),
                    Expanded(child: Text(context.tr('anonymousHint'), style: TextStyle(height: 1.6, color: context.pal.ink))),
                  ]),
                ),
            ],
            if (booking && cat!.subtypes.isNotEmpty) ...[
              Text(context.tr('bookingType'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 6, children: [
                for (final s in cat.subtypes)
                  ChoiceChip(
                    key: ValueKey('subtype-${s.key}'),
                    label: Text(context.pick(s.labelAr, s.labelEn)),
                    selected: _bookingType == s.key,
                    onSelected: (_) => setState(() {
                      _formRevision++;
                      _bookingType = s.key;
                      _errors = Map.of(_errors)..remove(ContactField.subtype);
                    }),
                  ),
              ]),
              if (_err(ContactField.subtype) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_err(ContactField.subtype)!,
                      style: TextStyle(color: context.pal.alert, fontSize: 12.5)),
                ),
              const SizedBox(height: 10),
            ],
            if (booking) ...[
              TextField(
                key: const Key('preferredDate'),
                controller: _date,
                readOnly: true,
                onTap: _pickDate,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: '${context.tr('preferredDate')} *',
                  hintText: 'YYYY-MM-DD',
                  errorText: _err(ContactField.date),
                  prefixIcon: const Icon(Icons.event_rounded),
                  suffixIcon: IconButton(
                      tooltip: context.tr('pickDate'), icon: const Icon(Icons.calendar_month), onPressed: _pickDate),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (!anonymous) ...[
            TextField(
              controller: _name,
              maxLength: contactNameMax,
              autofillHints: const [AutofillHints.name],
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                  labelText: context.tr('name'), errorText: _err(ContactField.name), prefixIcon: const Icon(Icons.person)),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              textInputAction: TextInputAction.next,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: booking ? '${context.tr('phone')} *' : context.tr('phone'),
                hintText: '01XXXXXXXXX',
                errorText: _err(ContactField.phone) ?? contactErr,
                prefixIcon: const Icon(Icons.phone_iphone),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.next,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: context.tr('email'),
                errorText: _err(ContactField.email),
                prefixIcon: const Icon(Icons.alternate_email),
              ),
            ),
            const SizedBox(height: 12),
            ],
            TextField(
              controller: _message,
              minLines: 4,
              maxLines: 8,
              maxLength: contactMessageMax,
              decoration: InputDecoration(
                labelText: context.tr('message'),
                alignLabelWithHint: true,
                errorText: _err(ContactField.message),
              ),
            ),
            // Honeypot (invisible to humans).
            Offstage(child: TextField(controller: _honeypot)),
            // Egyptian PDPL privacy notice + explicit consent (FR-CT-06).
            // Anonymous messages store no identity: the notice says so (ADR-028).
            Text(context.tr(anonymous ? 'privacyNoticeAnon' : 'privacyNotice'),
                key: const Key('privacyNotice'), style: Theme.of(context).textTheme.bodySmall),
            CheckboxListTile(
              value: _consented,
              onChanged: (v) => setState(() {
                _formRevision++;
                _consented = v ?? false;
                if (_consented && _errors.containsKey(ContactField.consent)) {
                  _errors = Map.of(_errors)..remove(ContactField.consent);
                }
              }),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(context.tr(anonymous ? 'consentLabelAnon' : 'consentLabel')),
              subtitle: _err(ContactField.consent) == null
                  ? null
                  : Text(_err(ContactField.consent)!, style: TextStyle(color: context.pal.alert)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('contactSendButton'),
              onPressed: (_sending || hasPendingWrites) ? null : _submit,
              icon: _sending
                  ? SizedBox.square(
                      dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.onBar))
                  : Icon(hasPendingWrites ? Icons.schedule_send_rounded : Icons.send_rounded),
              label: Text(context.tr(_sending ? 'sending' : 'send')),
            ),
            if (visibleStatus != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                // Screen readers announce the send result.
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    key: Key(visibleTone == _ContactStatusTone.queued
                        ? 'contactQueuedStatus'
                        : (visibleTone == _ContactStatusTone.error && queue.phase == ContactQueuePhase.failed
                            ? 'contactQueuedError'
                            : 'contactStatusBanner')),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: switch (visibleTone) {
                        _ContactStatusTone.success => context.pal.success.withValues(alpha: 0.1),
                        _ContactStatusTone.queued => context.pal.notice,
                        _ContactStatusTone.error => context.pal.alert.withValues(alpha: 0.1),
                      },
                      border: visibleTone == _ContactStatusTone.queued
                          ? Border.all(color: context.pal.noticeEdge)
                          : null,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(children: [
                      Icon(
                        switch (visibleTone) {
                          _ContactStatusTone.success => Icons.check_circle,
                          _ContactStatusTone.queued => Icons.schedule_send_rounded,
                          _ContactStatusTone.error => Icons.error_outline,
                        },
                        color: switch (visibleTone) {
                          _ContactStatusTone.success => context.pal.success,
                          _ContactStatusTone.queued => context.pal.noticeInk,
                          _ContactStatusTone.error => context.pal.alert,
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          visibleStatus,
                          style: visibleTone == _ContactStatusTone.queued
                              ? TextStyle(color: context.pal.noticeInk, fontWeight: FontWeight.w600)
                              : null,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

enum _ContactStatusTone { success, queued, error }

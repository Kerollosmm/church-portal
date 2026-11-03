import 'dart:async';

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
final _rateLimiter = ContactRateLimiter();

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
            TitleWithBadge(context.tr('phones'),
                sample: s.sample,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Theme.of(context).colorScheme.primary)),
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
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Theme.of(context).colorScheme.primary)),
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
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Theme.of(context).colorScheme.primary)),
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
  bool _anonymous = false;
  String _bookingType = '';
  bool _sending = false;
  bool _consented = false;
  String? _status;
  bool _statusOk = false;

  @override
  void dispose() {
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

  Future<void> _submit() async {
    if (_sending) return; // a submission is already in flight
    FocusScope.of(context).unfocus();
    final cat = _category(ref.read(contactSettingsProvider).value ?? ContactSettings.defaults);
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
      _done(context.tr('sent'), true);
      return;
    }
    final now = DateTime.now();
    final wait = _rateLimiter.waitTime(now);
    if (wait > Duration.zero) {
      setState(() {
        _status = context.tr('rateLimited', {'t': localDigits(context, '${wait.inSeconds + 1}')});
        _statusOk = false;
      });
      return;
    }
    final lang = context.isAr ? 'ar' : 'en';
    final msgs = (
      sent: context.tr('sent'),
      timeoutRetry: context.tr('sendTimeoutRetry'),
      unavailable: context.tr('contactUnavailable'),
      failed: context.tr('sendFailed'),
    );
    setState(() => _sending = true);
    try {
      await ref.read(repositoryProvider).submitContact(v.payload!, lang: lang);
      _rateLimiter.recordSubmission(now);
      _done(msgs.sent, true);
    } on TimeoutException {
      // Not confirmed in time. Firestore may still deliver the queued batch
      // (a resend would duplicate it) or the server throttle may reject it,
      // so never promise delivery and never invite a resend: keep the
      // visitor's text in the form so it is not lost, point them to the
      // church office, and throttle an immediate resend.
      _rateLimiter.recordSubmission(now);
      _done(msgs.timeoutRetry, false);
    } on ContactUnavailableException {
      _done(msgs.unavailable, false);
    } catch (e, st) {
      // The error only (never the form's text, ADR-034). A permission-denied
      // write is the server-side rate limit doing its job: not reported.
      if (!'$e'.contains('permission-denied')) {
        ErrorReporting.capture(ContactSubmitFailure(e.runtimeType.toString(), scrubText('$e')), st, section: 'contact');
      }
      _done(msgs.failed, false);
    }
  }

  void _done(String msg, bool ok) {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _status = msg;
      _statusOk = ok;
      if (ok) {
        _name.clear();
        _phone.clear();
        _email.clear();
        _message.clear();
        _date.clear();
        _bookingType = '';
        _anonymous = false;
        _consented = false; // each message needs its own consent
      }
    });
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String _cairoToday() {
    final c = CairoTime.fromInstant(DateTime.now());
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      firstDate: today,
      lastDate: DateTime(today.year + 2, 12, 31),
      initialDate: DateTime.tryParse(_date.text) ?? today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date.text = '${picked.year}-${_two(picked.month)}-${_two(picked.day)}';
      _errors = Map.of(_errors)..remove(ContactField.date);
    });
  }

  @override
  Widget build(BuildContext context) {
    final contactErr = _err(ContactField.contact);
    final cfg = ref.watch(contactSettingsProvider).value ?? ContactSettings.defaults;
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
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 12),
            if (cats.length > 1) ...[
              // Rebuilt when the admin-managed list (settings/contact,
              // ADR-028) arrives or changes: a form field keeps its first
              // value, so a default type must not stay selected (PR #23).
              KeyedSubtree(
                key: ValueKey('contactCats-${[for (final c in cats) c.slot].join(',')}'),
                child: DropdownButtonFormField<String>(
                  key: const Key('contactCategory'),
                  isExpanded: true,
                  initialValue: cat?.slot,
                  decoration: InputDecoration(labelText: context.tr('contactCategory'), prefixIcon: const Icon(Icons.forum_outlined)),
                  items: [
                    for (final c in cats) DropdownMenuItem(value: c.slot, child: Text(context.pick(c.labelAr, c.labelEn))),
                  ],
                  onChanged: (v) => setState(() {
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
                      _bookingType = s.key;
                      _errors = Map.of(_errors)..remove(ContactField.subtype);
                    }),
                  ),
              ]),
              if (_err(ContactField.subtype) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_err(ContactField.subtype)!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12.5)),
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
                  : Text(_err(ContactField.consent)!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? SizedBox.square(
                      dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: context.pal.onPrimary))
                  : const Icon(Icons.send_rounded),
              label: Text(context.tr(_sending ? 'sending' : 'send')),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                // Screen readers announce the send result.
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_statusOk ? AppColors.success : AppColors.alert).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(children: [
                      Icon(_statusOk ? Icons.check_circle : Icons.error_outline,
                          color: _statusOk ? AppColors.success : AppColors.alert),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_status!)),
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

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../data/content_repository.dart';
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
      header: PageHeader(title: context.tr('contact'), subtitle: context.tr('dir_contact'), icon: Icons.call_rounded),
      children: [
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
            Row(children: [
              Text(context.tr('phones'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.burgundy)),
              const Spacer(),
              if (s.sample) const SampleBadge(),
            ]),
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.burgundy)),
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
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.burgundy)),
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
  Map<ContactField, ContactError> _errors = const {};
  bool _sending = false;
  String? _status;
  bool _statusOk = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _message, _honeypot]) {
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
    });
  }

  Future<void> _submit() async {
    if (_sending) return; // a submission is already in flight
    FocusScope.of(context).unfocus();
    final v = validateContactForm(ContactFormInput(
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      message: _message.text,
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
      queued: context.tr('queued'),
      unavailable: context.tr('contactUnavailable'),
      failed: context.tr('sendFailed'),
    );
    setState(() => _sending = true);
    try {
      await ref.read(repositoryProvider).submitContact(v.payload!, lang: lang);
      _rateLimiter.recordSubmission(now);
      _done(msgs.sent, true);
    } on TimeoutException {
      // Firestore queued the write offline; it syncs when back online.
      _rateLimiter.recordSubmission(now);
      _done(msgs.queued, true);
    } on ContactUnavailableException {
      _done(msgs.unavailable, false);
    } catch (_) {
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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final contactErr = _err(ContactField.contact);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.tr('contactForm'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.burgundy)),
            const SizedBox(height: 12),
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
                labelText: context.tr('phone'),
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
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
              label: Text(context.tr(_sending ? 'sending' : 'send')),
            ),
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_statusOk ? AppColors.success : AppColors.alert).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(_statusOk ? Icons.check_circle : Icons.error_outline,
                        color: _statusOk ? AppColors.success : AppColors.alert),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_status!)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

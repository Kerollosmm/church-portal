import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/document_lang.dart';
import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/item_detail.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import '../widgets/app_shell.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';
import '../widgets/feature_gate.dart';
import '../widgets/item_image.dart';
import 'activities_page.dart' show activityIcon;
import 'clinics_page.dart' show ClinicCard;
import 'education_page.dart' show stageLabels;
import 'public_services_page.dart' show facilityIcon;

/// Public detail page of one item (`/clinics/<id>`, `/about/priests/<id>`…,
/// ADR-020). Resolves the item from the collection stream the list page
/// already uses (no extra Firestore read); only the inline gallery images
/// (`media/{id}`) are fetched, lazily, when this page mounts.
class ItemDetailPage extends ConsumerWidget {
  final DetailKind kind;
  final String id;
  const ItemDetailPage({super.key, required this.kind, required this.id});

  StreamProvider<List<Object>> get _provider => switch (kind) {
        DetailKind.meeting => meetingsProvider,
        DetailKind.activity => activitiesProvider,
        DetailKind.clinic => clinicsProvider,
        DetailKind.facility => facilitiesProvider,
        DetailKind.priest => priestsProvider,
        DetailKind.saint => saintsProvider,
        DetailKind.milestone => milestonesProvider,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = _provider;
    final items = ref.watch(provider);
    final features = ref.watch(featuresProvider);
    final path = detailPathFor(kind, id);
    final parent = kind.parentPath;
    return items.when(
      skipLoadingOnReload: true,
      loading: () => const PageBody(children: [
        SkeletonBox(height: 28, width: 220),
        SizedBox(height: 12),
        SkeletonBox(height: 160, radius: 16),
      ]),
      error: (_, _) => PageBody(children: [ErrorState(onRetry: () => ref.invalidate(provider))]),
      data: (list) {
        Object? item;
        for (final o in list) {
          if (_idOf(o) == id) {
            item = o;
            break;
          }
        }
        final state = detailStateFor(
          item == null ? null : _detailsOf(item),
          features: features,
          visible: item != null && _publiclyListed(item),
          priestDeparted: item is Priest ? item.departed : null,
        );
        setDocumentRouteMeta(path: path, indexable: state == DetailState.available);
        return switch (state) {
          DetailState.sectionOff => const SectionUnavailable(),
          DetailState.unavailable => _Unavailable(parent: parent),
          DetailState.available => _DetailView(entry: _Entry.of(context, ref, item!), parent: parent),
        };
      },
    );
  }
}

String _idOf(Object o) => switch (o) {
      Meeting m => m.id,
      Activity a => a.id,
      Clinic c => c.id,
      Facility f => f.id,
      Priest p => p.id,
      Saint s => s.id,
      Milestone m => m.id,
      _ => '',
    };

ItemDetails _detailsOf(Object o) => switch (o) {
      Meeting m => m.details,
      Activity a => a.details,
      Clinic c => c.details,
      Facility f => f.details,
      Priest p => p.details,
      Saint s => s.details,
      Milestone m => m.details,
      _ => ItemDetails.none,
    };

/// Shown on its list page: visible (and, for clinics, active).
bool _publiclyListed(Object o) => switch (o) {
      Clinic c => c.visible && c.active,
      Hideable h => h.visible,
      _ => false,
    };

/// Everything the detail layout needs, read from one item.
class _Entry {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool sample;
  final MediaImage? cover;
  final ItemDetails details;
  final List<Widget> pills;
  final List<Widget> facts;
  final String summary;

  /// Clinics: the church office phone when the clinic has no phone/WhatsApp.
  final bool officeFallback;

  /// Activities (like their card): a mobile contact phone is also WhatsApp.
  final bool whatsappFromPhone;

  /// Pre-filled WhatsApp message (clinics: booking request).
  final String? whatsappText;

  const _Entry({
    required this.title,
    required this.icon,
    required this.details,
    this.subtitle = '',
    this.sample = false,
    this.cover,
    this.pills = const [],
    this.facts = const [],
    this.summary = '',
    this.officeFallback = false,
    this.whatsappFromPhone = false,
    this.whatsappText,
  });

  static _Entry of(BuildContext context, WidgetRef ref, Object item) {
    final primary = Theme.of(context).colorScheme.primary;
    String date(String s) => formatLooseDate(s, arabic: context.isAr);
    switch (item) {
      case Meeting m:
        final stage = stageLabels[m.stage];
        return _Entry(
          title: context.pick(m.nameAr, m.nameEn),
          icon: Icons.school_rounded,
          details: m.details,
          sample: m.sample,
          cover: m.image,
          pills: [if (stage != null) Pill(context.pick(stage[0], stage[1]), color: primary)],
          facts: [
            if (m.weekday != null)
              Text(weekdayLabel(context, m.weekday),
                  style: const TextStyle(color: AppColors.goldText, fontWeight: FontWeight.w800)),
            if (m.start.isNotEmpty) TimeRangeText(m.start, m.end),
            IconLine(Icons.meeting_room_outlined, context.pick(m.hallAr, m.hallEn)),
            IconLine(Icons.info_outline, m.notes),
          ],
        );
      case Activity a:
        final schedule = context.pick(a.scheduleAr, a.scheduleEn);
        return _Entry(
          title: context.pick(a.titleAr, a.titleEn),
          icon: activityIcon(a.category),
          details: a.details,
          sample: a.sample,
          cover: a.image,
          facts: [
            IconLine(Icons.schedule_rounded, schedule.isEmpty ? '' : '${context.tr('schedule')}: $schedule'),
            IconLine(Icons.cake_outlined,
                a.ageRange.isEmpty ? '' : '${context.tr('ages')}: ${localDigits(context, a.ageRange)}'),
          ],
          summary: context.pick(a.descAr, a.descEn),
          whatsappFromPhone: true,
        );
      case Clinic c:
        final now = ref.watch(nowProvider).value ?? DateTime.now();
        final doctor = !context.isAr && ClinicCard.isPlaceholderDoctor(c)
            ? context.tr('doctorTba', {'s': c.specialtyEn.isNotEmpty ? c.specialtyEn : c.specialtyAr})
            : c.doctorName;
        final days = c.days.map((d) => weekdayLabel(context, d)).join(context.isAr ? '، ' : ', ');
        return _Entry(
          title: context.pick(c.specialtyAr, c.specialtyEn),
          subtitle: doctor,
          icon: Icons.local_hospital_rounded,
          details: c.details,
          sample: c.sample,
          cover: c.image,
          pills: [if (isClinicAvailableToday(c, now)) Pill(context.tr('availableToday'), icon: Icons.check_circle)],
          facts: [
            Text(doctor, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            if (context.pick(c.degreeAr, c.degreeEn).isNotEmpty)
              Text(context.pick(c.degreeAr, c.degreeEn), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            IconLine(Icons.calendar_today_outlined, days),
            if (c.start.isNotEmpty) TimeRangeText(c.start, c.end),
          ],
          officeFallback: true,
          whatsappText: context.isAr
              ? 'أرغب في حجز موعد بعيادة ${c.specialtyAr} (${c.doctorName})'
              : 'I would like to book an appointment at the ${c.specialtyEn} clinic ($doctor)',
        );
      case Facility f:
        return _Entry(
          title: context.pick(f.nameAr, f.nameEn),
          icon: facilityIcon(f.type),
          details: f.details,
          sample: f.sample,
          cover: f.image,
          facts: [IconLine(Icons.schedule_rounded, context.pick(f.hoursAr, f.hoursEn))],
          summary: context.pick(f.descAr, f.descEn),
        );
      case Priest p:
        final rank = context.tr(p.rank == 'hegumen' ? 'hegumen' : 'priest');
        return _Entry(
          title: context.isAr ? p.name : (p.nameEn.isNotEmpty ? p.nameEn : p.name),
          subtitle: rank,
          icon: p.departed ? Icons.local_florist_rounded : Icons.person_rounded,
          details: p.details,
          sample: p.sample,
          cover: p.displayImage,
          pills: [
            Pill(rank, color: AppColors.goldText),
            if (p.departed) Pill(context.tr('opt_departed'), color: AppColors.muted, icon: Icons.local_florist_outlined),
          ],
          facts: [
            if (p.ordinationDate.isNotEmpty)
              IconLine(Icons.event_outlined, '${context.tr('ordained')}: ${date(p.ordinationDate)}'),
            if (p.hegumenDate.isNotEmpty)
              IconLine(Icons.workspace_premium_outlined, '${context.tr('hegumenSince')}: ${date(p.hegumenDate)}'),
            if (p.departed && p.departedDate.isNotEmpty)
              IconLine(Icons.local_florist_outlined, '${context.tr('departedOn')}: ${date(p.departedDate)}'),
          ],
          summary: context.pick(p.bioAr, p.bioEn),
        );
      case Saint s:
        final feast = context.pick(s.feastCopticAr, s.feastCopticEn);
        return _Entry(
          title: context.pick(s.nameAr, s.nameEn),
          icon: Icons.auto_awesome_rounded,
          details: s.details,
          cover: s.image,
          pills: [
            if (feast.isNotEmpty) Pill('${context.tr('feast')}: $feast', color: primary, icon: Icons.event),
            if (context.pick(s.feastGregorianAr, s.feastGregorian).isNotEmpty)
              Pill(context.pick(s.feastGregorianAr, s.feastGregorian), color: AppColors.muted),
          ],
          summary: context.pick(s.bioAr, s.bioEn),
        );
      case Milestone m:
        return _Entry(
          title: context.pick(m.titleAr, m.titleEn),
          icon: Icons.history_edu_rounded,
          details: m.details,
          cover: m.image,
          pills: [if (m.year != null) Pill(localDigits(context, '${m.year}'), color: AppColors.goldText)],
          summary: context.pick(m.descAr, m.descEn),
        );
    }
    return _Entry(title: '', icon: Icons.info_outline, details: _detailsOf(item));
  }
}

/// "Back to …" link at the top of the page body.
class _BackLink extends StatelessWidget {
  final String parent;
  const _BackLink({required this.parent});

  @override
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const Key('detailBackLink'),
          onPressed: () => context.go(parent),
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
          label: Text(backToLabel(context, parent)),
        ),
      );
}

class _Unavailable extends StatelessWidget {
  final String parent;
  const _Unavailable({required this.parent});

  @override
  Widget build(BuildContext context) => PageBody(key: const Key('itemUnavailable'), children: [
        const SizedBox(height: 40),
        const Icon(Icons.visibility_off_rounded, size: 64, color: AppColors.muted),
        const SizedBox(height: 12),
        Text(context.tr('itemUnavailable'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(context.tr('itemUnavailableHint'),
            textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(
            key: const Key('unavailableBack'),
            onPressed: () => context.go(parent),
            child: Text(backToLabel(context, parent)),
          ),
        ),
      ]);
}

class _DetailView extends ConsumerWidget {
  final _Entry entry;
  final String parent;
  const _DetailView({required this.entry, required this.parent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final d = e.details;
    final f = ref.watch(featuresProvider);
    final primary = Theme.of(context).colorScheme.primary;
    final showImages = f.showImages && d.showDetailImages;
    final cover = showImages ? e.cover : null;
    final gallery = showImages ? d.gallery : const <MediaImage>[];
    final longText = context.pick(d.detailsAr, d.detailsEn).trim();
    final facts = e.facts.where((w) => !(w is IconLine && w.text.isEmpty)).toList();
    final contacts = d.showContacts ? _contactButtons(context, ref, e) : const <Widget>[];
    final note = d.showContacts ? context.pick(d.contactNoteAr, d.contactNoteEn).trim() : '';
    final links = itemSocialsShown(d, f) ? _linkButtons(context, e) : const <Widget>[];

    return PageBody(
      key: const Key('itemDetailPage'),
      header: PageHeader(title: e.title, subtitle: e.subtitle, icon: e.icon),
      children: [
        _BackLink(parent: parent),
        const SizedBox(height: 4),
        if (e.sample) const PendingConfirmationNote(),
        if (e.pills.isNotEmpty || e.sample)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ...e.pills,
              if (e.sample) const SampleBadge(),
            ]),
          ),
        if (cover != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: ItemImage(
                key: const Key('detailCover'),
                image: cover,
                size: 168,
                circle: false,
                radius: 16,
                label: e.title,
                placeholder: const SizedBox.shrink(),
              ),
            ),
          ),
        if (facts.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final w in facts) Padding(padding: const EdgeInsets.only(bottom: 4), child: w),
              ]),
            ),
          ),
        if (e.summary.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(e.summary, style: const TextStyle(height: 1.8, fontSize: 15)),
          ),
        if (longText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: SelectableText(longText,
                key: const Key('detailText'), style: const TextStyle(height: 1.8, fontSize: 15, color: AppColors.ink)),
          ),
        if (d.extraFields.isNotEmpty) ...[
          SectionTitle(context.tr('moreInfo'), icon: Icons.list_alt_rounded),
          ResponsiveGrid(minItemWidth: 260, children: [for (final c in d.extraFields) _FieldCard(field: c)]),
        ],
        if (gallery.isNotEmpty) ...[
          SectionTitle(context.tr('photos'), icon: Icons.photo_library_outlined),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < gallery.length; i++)
              ItemImage(
                key: ValueKey('galleryThumb-$i'),
                image: gallery[i],
                size: 104,
                circle: false,
                label: context.tr('photoOf', {'n': localDigits(context, '${i + 1}'), 's': e.title}),
                placeholder: Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.image_outlined, color: primary),
                ),
              ),
          ]),
        ],
        if (contacts.isNotEmpty || note.isNotEmpty) ...[
          SectionTitle(context.tr('contactRegister'), icon: Icons.call_rounded),
          if (contacts.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: contacts),
          if (note.isNotEmpty)
            Container(
              key: const Key('detailContactNote'),
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.goldText),
                const SizedBox(width: 10),
                Expanded(child: Text(note, style: const TextStyle(height: 1.6, color: AppColors.ink))),
              ]),
            ),
        ],
        if (links.isNotEmpty) ...[
          SectionTitle(context.tr('itemLinks'), icon: Icons.link_rounded),
          Wrap(spacing: 8, runSpacing: 8, children: links),
        ],
      ],
    );
  }

  List<Widget> _contactButtons(BuildContext context, WidgetRef ref, _Entry e) {
    final d = e.details;
    final phone = d.contactPhone.trim();
    final wa = d.whatsapp.trim().isNotEmpty
        ? d.whatsapp.trim()
        : (e.whatsappFromPhone && isEgyptianMobile(phone) ? phone : '');
    String? office;
    if (e.officeFallback && phone.isEmpty && wa.isEmpty && ref.watch(featuresProvider).enabled(Sections.contactInfo)) {
      office = ref.watch(settingsProvider).value?.phones.where((p) => p.number.isNotEmpty).firstOrNull?.number;
    }
    final primary = Theme.of(context).colorScheme.primary;
    return [
      if (phone.isNotEmpty)
        ActionChipButton(
          key: const Key('detailCall'),
          icon: Icons.call,
          label: '${context.tr('call')} $phone',
          semanticLabel: actionSemanticLabel('${context.tr('call')} $phone', e.title),
          color: primary,
          onTap: () => callPhone(phone),
        ),
      if (wa.isNotEmpty)
        ActionChipButton(
          key: const Key('detailWhatsapp'),
          icon: Icons.chat_rounded,
          label: context.tr('whatsapp'),
          semanticLabel: actionSemanticLabel(context.tr('whatsapp'), e.title),
          color: whatsappGreen,
          onTap: () => openWhatsApp(wa, text: e.whatsappText),
        ),
      if (office != null)
        ActionChipButton(
          key: const Key('detailCallOffice'),
          icon: Icons.call,
          label: context.tr('callChurchOffice'),
          semanticLabel: actionSemanticLabel(context.tr('callChurchOffice'), e.title),
          color: primary,
          onTap: () => callPhone(office!),
        ),
    ];
  }

  List<Widget> _linkButtons(BuildContext context, _Entry e) {
    final d = e.details;
    Widget link(String key, IconData icon, String label, Color color, String url) => ActionChipButton(
          key: Key(key),
          icon: icon,
          label: label,
          semanticLabel: actionSemanticLabel(label, e.title),
          color: color,
          onTap: () => openUrl(url),
        );
    final external = d.externalUrl.trim();
    final externalLabel = context.pick(d.externalLabelAr.trim(), d.externalLabelEn.trim());
    return [
      if (d.whatsappUrl.trim().isNotEmpty)
        link('detailWhatsappGroup', Icons.groups_rounded, context.tr('whatsappGroup'), whatsappGreen, d.whatsappUrl.trim()),
      if (d.facebookUrl.trim().isNotEmpty)
        link('detailFacebook', Icons.facebook, context.tr('facebook'), facebookBlue, d.facebookUrl.trim()),
      if (d.youtubeUrl.trim().isNotEmpty)
        link('detailYoutube', Icons.smart_display_rounded, context.tr('youtubeLink'), youtubeRed, d.youtubeUrl.trim()),
      if (d.instagramUrl.trim().isNotEmpty)
        link('detailInstagram', Icons.photo_camera_rounded, context.tr('instagram'), instagramPink, d.instagramUrl.trim()),
      if (external.isNotEmpty)
        link('detailExternal', Icons.open_in_new_rounded, externalLabel.isEmpty ? context.tr('openPage') : externalLabel,
            Theme.of(context).colorScheme.primary, external),
    ];
  }
}

/// One admin-defined "title: value" row.
class _FieldCard extends StatelessWidget {
  final CustomField field;
  const _FieldCard({required this.field});

  @override
  Widget build(BuildContext context) {
    final title = context.pick(field.titleAr, field.titleEn).trim();
    final value = context.pick(field.valueAr, field.valueEn).trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title.isNotEmpty)
          Text(title,
              style: TextStyle(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary, height: 1.4)),
        if (title.isNotEmpty && value.isNotEmpty) const SizedBox(height: 4),
        if (value.isNotEmpty) Text(value, style: const TextStyle(height: 1.6, color: AppColors.ink)),
      ]),
    );
  }
}

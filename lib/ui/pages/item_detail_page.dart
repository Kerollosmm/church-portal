import 'package:flutter/services.dart';
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
import 'education_page.dart' show meetingGroupOf, stageLabels;
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
      error: (_, _) {
        // Nothing to show: never let an error page be indexed under the item's URL.
        setDocumentRouteMeta(path: path, indexable: false);
        return PageBody(children: [ErrorState(onRetry: () => ref.invalidate(provider))]);
      },
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
          DetailState.available => _DetailView(
              entry: _Entry.of(context, ref, item!),
              parent: parent,
              kind: kind,
              id: id,
              related: _relatedTo(item, list, features),
            ),
        };
      },
    );
  }
}

/// Up to 3 other items of the same section whose own detail page is
/// available (same gating as this page: listed, not switched off, priests'
/// status section on), same group first. Read from the list already loaded:
/// no extra Firestore read.
List<Object> _relatedTo(Object self, List<Object> list, FeatureSettings features) {
  final group = _groupOf(self);
  bool opens(Object o) =>
      detailStateFor(_detailsOf(o),
          features: features, visible: _publiclyListed(o), priestDeparted: o is Priest ? o.departed : null) ==
      DetailState.available;
  return pickRelated([for (final o in list) if (o == self || opens(o)) o], self,
      sameGroup: group == null ? null : (o) => _groupOf(o) == group);
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

/// One labelled row of the "Key information" card (label above value, so
/// long Arabic values wrap cleanly at 320 px / 200% text).
class _Fact {
  final IconData icon;
  final String label;
  final String text;

  /// Rich value (e.g. the bilingual time range) instead of [text].
  final Widget? child;
  const _Fact(this.icon, this.label, this.text) : child = null;
  const _Fact.widget(this.icon, this.label, Widget this.child) : text = '';

  bool get isEmpty => child == null && text.trim().isEmpty;
}

/// Everything the detail layout needs, read from one item.
class _Entry {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool sample;
  final MediaImage? cover;
  final ItemDetails details;
  final List<Widget> pills;
  final List<_Fact> facts;
  final String summary;

  /// Weekly schedule for "Add to calendar" (ISO weekdays + "HH:mm" times);
  /// empty = no calendar button.
  final List<int> calendarDays;
  final String start, end;

  /// Happens at the church (meetings, activities, clinics, services): the
  /// page offers directions to the church.
  final bool onSite;

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
    this.calendarDays = const [],
    this.start = '',
    this.end = '',
    this.onSite = false,
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
            if (m.weekday != null) _Fact(Icons.calendar_today_outlined, context.tr('factDay'), weekdayLabel(context, m.weekday)),
            if (m.start.isNotEmpty) _Fact.widget(Icons.schedule_rounded, context.tr('factTime'), TimeRangeText(m.start, m.end)),
            _Fact(Icons.meeting_room_outlined, context.tr('place'), context.pick(m.hallAr, m.hallEn)),
            _Fact(Icons.info_outline, context.tr('factNotes'), m.notes),
          ],
          calendarDays: [if (m.weekday != null) m.weekday!],
          start: m.start,
          end: m.end,
          onSite: true,
        );
      case Activity a:
        return _Entry(
          title: context.pick(a.titleAr, a.titleEn),
          icon: activityIcon(a.category),
          details: a.details,
          sample: a.sample,
          cover: a.image,
          facts: [
            _Fact(Icons.schedule_rounded, context.tr('schedule'), context.pick(a.scheduleAr, a.scheduleEn)),
            _Fact(Icons.cake_outlined, context.tr('ages'), a.ageRange.isEmpty ? '' : localDigits(context, a.ageRange)),
          ],
          summary: context.pick(a.descAr, a.descEn),
          onSite: true,
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
            _Fact(Icons.medical_services_outlined, context.tr('factDoctor'), doctor),
            _Fact(Icons.workspace_premium_outlined, context.tr('factQualification'), context.pick(c.degreeAr, c.degreeEn)),
            _Fact(Icons.calendar_today_outlined, context.tr('factDays'), days),
            if (c.start.isNotEmpty) _Fact.widget(Icons.schedule_rounded, context.tr('factTime'), TimeRangeText(c.start, c.end)),
          ],
          calendarDays: c.days,
          start: c.start,
          end: c.end,
          onSite: true,
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
          facts: [_Fact(Icons.schedule_rounded, context.tr('factHours'), context.pick(f.hoursAr, f.hoursEn))],
          summary: context.pick(f.descAr, f.descEn),
          onSite: true,
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
            if (p.ordinationDate.isNotEmpty) _Fact(Icons.event_outlined, context.tr('ordained'), date(p.ordinationDate)),
            if (p.hegumenDate.isNotEmpty)
              _Fact(Icons.workspace_premium_outlined, context.tr('hegumenSince'), date(p.hegumenDate)),
            if (p.departed && p.departedDate.isNotEmpty)
              _Fact(Icons.local_florist_outlined, context.tr('departedOn'), date(p.departedDate)),
          ],
          summary: context.pick(p.bioAr, p.bioEn),
        );
      case Saint s:
        return _Entry(
          title: context.pick(s.nameAr, s.nameEn),
          icon: Icons.auto_awesome_rounded,
          details: s.details,
          cover: s.image,
          facts: [
            _Fact(Icons.event, context.tr('feast'), context.pick(s.feastCopticAr, s.feastCopticEn)),
            _Fact(Icons.event_note_outlined, context.tr('factGregorian'), context.pick(s.feastGregorianAr, s.feastGregorian)),
          ],
          summary: context.pick(s.bioAr, s.bioEn),
        );
      case Milestone m:
        return _Entry(
          title: context.pick(m.titleAr, m.titleEn),
          icon: Icons.history_edu_rounded,
          details: m.details,
          cover: m.image,
          facts: [if (m.year != null) _Fact(Icons.history_edu_outlined, context.tr('factYear'), localDigits(context, '${m.year}'))],
          summary: context.pick(m.descAr, m.descEn),
        );
    }
    return _Entry(title: '', icon: Icons.info_outline, details: _detailsOf(item));
  }
}

/// Card title of a related item (same wording as its detail page title).
String _titleOf(BuildContext context, Object o) => switch (o) {
      Meeting m => context.pick(m.nameAr, m.nameEn),
      Activity a => context.pick(a.titleAr, a.titleEn),
      Clinic c => context.pick(c.specialtyAr, c.specialtyEn),
      Facility f => context.pick(f.nameAr, f.nameEn),
      Priest p => context.isAr ? p.name : (p.nameEn.isNotEmpty ? p.nameEn : p.name),
      Saint s => context.pick(s.nameAr, s.nameEn),
      Milestone m => context.pick(m.titleAr, m.titleEn),
      _ => '',
    };

/// Grouping used to suggest related items first: meetings by stage group,
/// activities by category, priests by serving / departed. Null = no grouping.
Object? _groupOf(Object o) => switch (o) {
      Meeting m => meetingGroupOf(m.stage),
      Activity a => a.category,
      Priest p => p.departed,
      _ => null,
    };

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
  final DetailKind kind;
  final String id;

  /// Other items of the same section ("More in this section").
  final List<Object> related;
  const _DetailView(
      {required this.entry, required this.parent, required this.kind, required this.id, this.related = const []});

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
    final facts = e.facts.where((x) => !x.isEmpty).toList();
    final contacts = d.showContacts ? _contactButtons(context, ref, e) : const <Widget>[];
    final note = d.showContacts ? context.pick(d.contactNoteAr, d.contactNoteEn).trim() : '';
    final links = itemSocialsShown(d, f) ? _linkButtons(context, e) : const <Widget>[];
    final actions = _quickActions(context, ref, e);

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
            child: LayoutBuilder(
              builder: (context, c) => Align(
                alignment: AlignmentDirectional.centerStart,
                child: ItemImage(
                  key: const Key('detailCover'),
                  image: cover,
                  // Hero picture: as wide as the column allows, up to 320 px.
                  size: c.maxWidth.isFinite ? c.maxWidth.clamp(120.0, 320.0) : 240,
                  circle: false,
                  radius: 16,
                  label: e.title,
                  placeholder: const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        if (facts.isNotEmpty)
          Semantics(
            container: true,
            label: context.tr('keyFacts'),
            child: Card(
              key: const Key('detailFacts'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final x in facts) _FactRow(fact: x),
                ]),
              ),
            ),
          ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(key: const Key('detailActions'), spacing: 8, runSpacing: 8, children: actions),
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
                  decoration: BoxDecoration(color: AppColors.parchment, borderRadius: BorderRadius.circular(4)),
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
                borderRadius: BorderRadius.circular(4),
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
        if (related.isNotEmpty) ...[
          SectionTitle(context.tr('relatedItems'), icon: Icons.grid_view_rounded),
          Column(key: const Key('detailRelated'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final o in related) _RelatedLink(kind: kind, id: _idOf(o), title: _titleOf(context, o), icon: e.icon),
          ]),
        ],
      ],
    );
  }

  /// Add to calendar (weekly items), directions to the church (on-site
  /// items, while the contact-info section is on) and share (every page).
  List<Widget> _quickActions(BuildContext context, WidgetRef ref, _Entry e) {
    final primary = Theme.of(context).colorScheme.primary;
    final features = ref.watch(featuresProvider);
    final settings = features.enabled(Sections.contactInfo) ? ref.watch(settingsProvider).value : null;
    final english = !context.isAr;
    final url = absoluteDetailUrl(kCanonicalOrigin, kind, id, english: english);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final calendar = e.calendarDays.isEmpty
        ? null
        : weeklyCalendarUrl(
            title: e.title,
            weekdays: e.calendarDays,
            start: e.start,
            end: e.end,
            details: url,
            location: settings == null
                ? ''
                : [context.pick(settings.nameAr, settings.nameEn), context.pick(settings.addressAr, settings.addressEn)]
                    .where((x) => x.trim().isNotEmpty)
                    .join(english ? ', ' : '، '),
            now: now,
          );
    return [
      if (calendar != null)
        ActionChipButton(
          key: const Key('detailAddToCalendar'),
          icon: Icons.event_available_rounded,
          label: context.tr('addToCalendar'),
          semanticLabel: actionSemanticLabel(context.tr('addToCalendar'), e.title),
          color: primary,
          onTap: () => openUrl(calendar),
        ),
      if (e.onSite && settings != null && _hasDestination(settings))
        ActionChipButton(
          key: const Key('detailDirections'),
          icon: Icons.directions_rounded,
          label: context.tr('directions'),
          semanticLabel: actionSemanticLabel(context.tr('directions'), e.title),
          color: AppColors.goldText,
          onTap: () => openUrl(mapsDirectionsUrl(settings)),
        ),
      ActionChipButton(
        key: const Key('detailShare'),
        icon: Icons.share_rounded,
        label: context.tr('shareLink'),
        semanticLabel: actionSemanticLabel(context.tr('shareLink'), e.title),
        color: AppColors.muted,
        onTap: () async {
          final messenger = ScaffoldMessenger.maybeOf(context);
          final copied = context.tr('linkCopied');
          final failed = context.tr('linkCopyFailed', {'u': url});
          try {
            await Clipboard.setData(ClipboardData(text: url));
            messenger?.showSnackBar(SnackBar(content: Text(copied)));
          } catch (_) {
            // Clipboard refused (browser permission): show the link so it can still be copied by hand.
            messenger?.showSnackBar(SnackBar(content: SelectableText(failed), duration: const Duration(seconds: 8)));
          }
        },
      ),
    ];
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
        borderRadius: BorderRadius.circular(4),
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

/// Whether [mapsDirectionsUrl] has a destination (maps query, coordinates or
/// an address); otherwise the directions action is hidden.
bool _hasDestination(ChurchSettings s) =>
    s.mapsQuery.trim().isNotEmpty || (s.lat != null && s.lng != null) || s.addressAr.trim().isNotEmpty;

/// One labelled "Key information" row: icon, small label, value below.
class _FactRow extends StatelessWidget {
  final _Fact fact;
  const _FactRow({required this.fact});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(fact.icon, size: 20, color: primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fact.label, style: const TextStyle(fontSize: 12, color: AppColors.muted, height: 1.4)),
            fact.child ??
                Text(fact.text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, height: 1.5)),
          ]),
        ),
      ]),
    );
  }
}

/// A "More in this section" row: the whole row opens the item's page.
class _RelatedLink extends StatelessWidget {
  final DetailKind kind;
  final String id;
  final String title;
  final IconData icon;
  const _RelatedLink({required this.kind, required this.id, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    void open() => context.go(detailPathFor(kind, id));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        container: true,
        button: true,
        link: true,
        label: actionSemanticLabel(context.tr('details'), title),
        onTap: open,
        excludeSemantics: true,
        child: InkWell(
          key: ValueKey('relatedLink-$id'),
          borderRadius: BorderRadius.circular(4),
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Icon(icon, color: primary),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4))),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: primary),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import 'common.dart';

/// Venue / audience labels of a programme (ADR-041): the admin lists in
/// settings/features (defaults when none). An unknown key shows nothing.
String venueLabel(BuildContext context, ProgramOptions o, String key) {
  final v = o.venue(key);
  return v == null ? '' : context.pick(v.labelAr, v.labelEn);
}

String audienceLabel(BuildContext context, ProgramOptions o, String key) {
  final v = o.audience(key);
  return v == null ? '' : context.pick(v.labelAr, v.labelEn);
}

/// Where a service is held, for one-line summaries: its free-text place, else
/// its venue's label ('' when neither; ADR-043, Holy Week sim B2).
String servicePlace(BuildContext context, ProgramOptions o, Liturgy l) {
  final place = context.pick(l.placeAr, l.placeEn).trim();
  return place.isNotEmpty ? place : venueLabel(context, o, l.program.venue);
}

/// "Name — place", or just the name when there is no place (no dangling dash).
String serviceWithPlace(BuildContext context, ProgramOptions o, Liturgy l) {
  final name = context.pick(l.nameAr, l.nameEn);
  final place = servicePlace(context, o, l);
  return place.isEmpty ? name : '$name — $place';
}

/// Speaker, topic, choir, venue, audience and the PDF / Drive link of a
/// liturgy, meeting or season (ADR-041). Renders nothing for an item
/// without programme details, so existing cards look exactly as before.
class ProgramDetails extends ConsumerWidget {
  final ProgramInfo program;

  /// Hide the venue (the card already shows it as its place line).
  final bool showVenue;

  /// "At the same time: …" line for services held in parallel elsewhere.
  final String parallelText;

  /// «وبعدها ٠٧:٠٠ ص: …» lines for parallel services that start later, while
  /// this one runs (ADR-053), already worded ([parallelThenLine]).
  final List<String> parallelThen;
  const ProgramDetails(this.program,
      {super.key, this.showVenue = true, this.parallelText = '', this.parallelThen = const []});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = program;
    if (p.isEmpty && parallelText.isEmpty && parallelThen.isEmpty) return const SizedBox.shrink();
    final opts = ref.watch(featuresProvider.select((f) => f.programOptions));
    final speaker = context.pick(p.speakerAr, p.speakerEn);
    final topic = context.pick(p.topicAr, p.topicEn);
    final choir = context.pick(p.choirAr, p.choirEn);
    final venue = showVenue ? venueLabel(context, opts, p.venue) : '';
    final audience = audienceLabel(context, opts, p.audience);
    final label = context.pick(p.attachmentLabelAr, p.attachmentLabelEn);
    final primary = context.pal.primary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (venue.isNotEmpty || audience.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 2),
          child: Wrap(spacing: 6, runSpacing: 4, children: [
            if (venue.isNotEmpty) Pill(venue, icon: Icons.place_outlined, color: primary),
            if (audience.isNotEmpty) Pill(audience, icon: Icons.groups_outlined, color: context.pal.goldText),
          ]),
        ),
      if (speaker.isNotEmpty)
        IconLine(Icons.record_voice_over_outlined, '${context.tr('speakerLabel')}: $speaker'),
      if (topic.isNotEmpty) IconLine(Icons.menu_book_outlined, '${context.tr('topicLabel')}: $topic'),
      if (choir.isNotEmpty) IconLine(Icons.music_note_outlined, '${context.tr('choirLabel')}: $choir'),
      if (parallelText.isNotEmpty) IconLine(Icons.call_split_rounded, context.tr('parallelAt', {'v': parallelText})),
      for (final (i, t) in parallelThen.indexed) IconLine(Icons.call_split_rounded, t, key: Key('parallelThen$i')),
      if (p.hasAttachment)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: OutlinedButton.icon(
            key: const Key('programPdf'),
            onPressed: () => openUrl(p.attachmentUrl),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(label.isNotEmpty ? label : context.tr('programPdf')),
          ),
        ),
    ]);
  }
}

/// «وبعدها ٠٧:٠٠ ص: القداس الإلهي (صباح الأحد) — الكنيسة الكبرى (عام)»: a
/// parallel service that starts later than the one shown, named with its own
/// start time [time] (already formatted), so the card does not call it «في
/// نفس الوقت» (ADR-053, sims r2 P2 O-a).
String parallelThenLine(BuildContext context, ProgramOptions opts, Liturgy o, String time) {
  final audience = audienceLabel(context, opts, o.program.audience);
  final v = [serviceWithPlace(context, opts, o), if (audience.isNotEmpty) '($audience)'].join(' ');
  return context.tr('parallelThen', {'t': time, 'v': v});
}

/// "Lower hall (Youth) 19:00" for each parallel service (ADR-041), joined
/// with the Arabic list comma «، » (", " in English). Kept on purpose
/// (ADR-050, issue 20): «،» is the correct Arabic list separator; «•»
/// already separates the day and the time in the pills.
String parallelSummary(BuildContext context, ProgramOptions opts, List<Liturgy> others) => [
      for (final o in others)
        [
          // An unknown venue key falls back to the free-text place (CodeRabbit).
          if (o.program.venue.isNotEmpty ? venueLabel(context, opts, o.program.venue) : '' case final v when v.isNotEmpty)
            v
          else
            context.pick(o.placeAr, o.placeEn),
          if (audienceLabel(context, opts, o.program.audience) case final a when a.isNotEmpty) '($a)',
        ].where((s) => s.isNotEmpty).join(' '),
    ].where((s) => s.isNotEmpty).join(context.isAr ? '، ' : ', ');

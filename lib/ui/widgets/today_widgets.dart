import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/today.dart';
import '../../state/providers.dart';
import 'common.dart';
import 'program_details.dart';

/// Top utility bar above the app bar (ADR-044): the Coptic date of the
/// liturgical day (ADR-039) at the start and, while the church is streaming
/// (ADR-040), a compact live badge at the end. Every colour comes from the
/// occasion palette (ADR-043): the title-band roles ([OccasionColors.bar],
/// [OccasionColors.onBar]) and the live roles, so Holy Week turns it charcoal
/// with a crimson badge like the rest of the site.
/// Shown on every page or on Home only (settings/features.copticStrip); the
/// badge follows the live switch (settings/features.live*), except on Home
/// where the red [LiveStreamBanner] already carries «شاهد البث»: there it
/// hides while the banner shows (settings/features.liveBadgeHideOnHome,
/// default on). The badge opens the stream like the banner's button.
class TopUtilityBar extends ConsumerWidget {
  final String location;
  const TopUtilityBar({super.key, required this.location});

  static bool shownOn(String mode, String location) =>
      mode == CopticStripModes.all || (mode == CopticStripModes.home && location == '/');

  /// Text in the bar is capped at this scale; the bar grows with it (never
  /// clips), so 200 % text stays readable without pushing the page down twice.
  static const maxTextScale = 1.6;

  /// The bar's height for the visitor's text size: 32 px at 100 %.
  static double heightFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: maxTextScale).scale(13) / 13;
    return (32.0 + 20.0 * (scale - 1)).clamp(32.0, 32.0 + 20.0 * (maxTextScale - 1)).roundToDouble();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(featuresReadyProvider)) return const SizedBox.shrink();
    final t = ref.watch(todaySettingsProvider);
    final showDate = shownOn(t.copticStrip, location);
    final liveActive = ref.watch(nowProvider.select((n) => t.liveBadgeOn(n.value ?? DateTime.now(), location)));
    if (!showDate && !liveActive) return const SizedBox.shrink();

    final day = ref.watch(liturgicalDayProvider);
    final label = day.label(arabic: context.isAr);
    final pal = context.pal;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: maxTextScale,
      child: Container(
        key: const Key('copticDateStrip'),
        width: double.infinity,
        height: heightFor(context),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: pal.barGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter),
          border: Border(bottom: BorderSide(color: pal.barEdge ?? pal.ornamentLine)),
        ),
        child: Row(
          children: [
            // The date takes the free width; the badge keeps its own (≤ 150 px).
            Expanded(
              child: showDate
                  ? Semantics(
                      container: true,
                      label: '${context.tr('copticDate')}: $label',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_note_rounded, size: 14, color: pal.onBarAccent),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              key: const Key('copticDateLabel'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pal.onBar),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (liveActive) ...[
              const SizedBox(width: 8),
              _LiveBadge(settings: t),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compatibility alias so existing code and tests referring to CopticDateStrip continue working.
typedef CopticDateStrip = TopUtilityBar;

/// The live badge in [TopUtilityBar]: the admin's live label (or «مباشر»),
/// ≤ 150 px with an ellipsis, in the theme's live colours.
class _LiveBadge extends StatelessWidget {
  final TodaySettings settings;
  const _LiveBadge({required this.settings});

  @override
  Widget build(BuildContext context) {
    final custom = context.pick(settings.liveLabelAr, settings.liveLabelEn).trim();
    final label = custom.isEmpty ? context.tr('liveBadge') : custom;
    final red = context.pal.live, onRed = context.pal.onLive;
    void open() => openUrl(settings.liveUrl);
    return Semantics(
      button: true,
      label: '$label — ${context.tr('watchLive')}',
      onTap: open,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('topBarLiveBadge'),
          onTap: open,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: red,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: onRed.withValues(alpha: 0.4), width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _PulseDot(size: 7),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: onRed, fontWeight: FontWeight.w700, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «بث مباشر الآن من الكنيسة» (ADR-040): shown at the top of every page
/// while the admin's live switch is on (and before its optional switch-off
/// time); one tap opens the stream.
class LiveStreamBanner extends ConsumerWidget {
  const LiveStreamBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(todaySettingsProvider);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    if (!t.liveOn(now)) return const SizedBox.shrink();
    final custom = context.pick(t.liveLabelAr, t.liveLabelEn).trim();
    final label = custom.isEmpty ? context.tr('liveNow') : custom;
    // The theme's live colours (red; deep crimson on Holy Week — ADR-043).
    final red = context.pal.live, onRed = context.pal.onLive;
    void open() => openUrl(t.liveUrl);
    return Semantics(
      button: true,
      label: '$label — ${context.tr('watchLive')}',
      // The InkWell below is excluded from the semantics tree: expose its tap.
      onTap: open,
      excludeSemantics: true,
      child: Material(
        key: const Key('liveStreamBanner'),
        color: red,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _PulseDot(),
              const SizedBox(width: 10),
              Flexible(
                child: Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: onRed, fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: onRed, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.play_arrow_rounded, size: 18, color: red),
                  Text(context.tr('watchLive'),
                      style: TextStyle(color: red, fontWeight: FontWeight.w800, fontSize: 13)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The pulsing "on air" dot (static when the visitor asked for less motion).
class _PulseDot extends StatefulWidget {
  final double size;
  const _PulseDot({this.size = 12});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 1;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(color: context.pal.onLive, shape: BoxShape.circle),
        ),
      );
}

/// The top event of the day on Home (ADR-040): the admin's church event,
/// else today's / tonight's programme service of an active season (speaker,
/// topic, choir and its PDF button; ADR-045), else the day's feast /
/// commemoration (Katameros, else the computed list).
class TopEventCard extends ConsumerWidget {
  const TopEventCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(topEventProvider);
    if (e == null) return const SizedBox.shrink();
    final title = context.pick(e.titleAr, e.titleEn).trim();
    if (title.isEmpty) return const SizedBox.shrink();
    final primary = context.pal.primary;
    final kicker = switch (e.kind) {
      TopEventKind.church => context.tr('todayEvent'),
      TopEventKind.service => context.tr(e.tonight ? 'tonightProgramme' : 'todayProgramme'),
      TopEventKind.feast => context.tr('todayFeast'),
      TopEventKind.commemoration => context.tr('todayCommemoration'),
    };
    final ev = e.event;
    final lines = context.isAr || e.linesEn.isEmpty ? e.linesAr : e.linesEn;
    final rawLink = ev?.link ?? '';
    final internal = rawLink.startsWith('/') && !rawLink.startsWith('//');
    // An in-app link to a section the admin switched off is not offered.
    final link = internal && !ref.watch(featuresProvider).routeEnabled(rawLink) ? '' : rawLink;
    final children = <Widget>[
      Text(kicker, style: TextStyle(color: context.pal.goldText, fontWeight: FontWeight.w800, fontSize: 13)),
      const SizedBox(height: 4),
      Text(title,
          key: const Key('topEventTitle'),
          style: displayStyle(context, size: 22, color: primary, height: 1.4)),
    ];
    if (ev != null) {
      final speaker = context.pick(ev.speakerAr, ev.speakerEn).trim();
      final topic = context.pick(ev.topicAr, ev.topicEn).trim();
      final note = context.pick(ev.noteAr, ev.noteEn).trim();
      if (ev.start.isNotEmpty) {
        children.add(Padding(padding: const EdgeInsets.only(top: 6), child: TimeRangeText(ev.start, ev.end)));
      }
      if (speaker.isNotEmpty) {
        children.add(IconLine(Icons.record_voice_over_outlined, '${context.tr('speakerLabel')}: $speaker'));
      }
      if (topic.isNotEmpty) children.add(IconLine(Icons.menu_book_outlined, '${context.tr('topicLabel')}: $topic'));
      if (note.isNotEmpty) {
        children.add(Padding(padding: const EdgeInsets.only(top: 4), child: Text(note, style: const TextStyle(height: 1.6))));
      }
      // The event's programme / PDF with its own labelled button (ADR-045).
      if (ev.attachmentUrl.isNotEmpty) {
        final label = context.pick(ev.attachmentLabelAr, ev.attachmentLabelEn).trim();
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: OutlinedButton.icon(
            key: const Key('topEventPdf'),
            onPressed: () => openUrl(ev.attachmentUrl),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: Text(label.isNotEmpty ? label : context.tr('programPdf')),
          ),
        ));
      }
      if (link.isNotEmpty) {
        children.add(Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => internal ? context.go(link) : openUrl(link),
            child: Text(context.tr('learnMore')),
          ),
        ));
      }
    } else if (e.service case final o?) {
      // Today's / tonight's programme service (ADR-045): its time, then the
      // programme (speaker, topic, choir, venue, audience, PDF button).
      children.add(Padding(
          padding: const EdgeInsets.only(top: 6), child: TimeRangeText(o.liturgy.start, o.liturgy.end)));
      children.add(KeyedSubtree(key: const Key('topEventProgramme'), child: ProgramDetails(o.liturgy.program)));
      // A sample (unconfirmed) service carries the same note as on the
      // next-service card (CodeRabbit review on PR #38).
      if (o.liturgy.sample) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(context.tr('timesPending'),
              key: const Key('topEventTimesPending'),
              style: TextStyle(color: context.pal.goldText, fontWeight: FontWeight.w700, fontSize: 12)),
        ));
      }
    } else {
      for (final l in lines.where((l) => l.trim().isNotEmpty && l.trim() != title)) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('• $l', style: TextStyle(color: context.pal.ink, height: 1.5)),
        ));
      }
      if (e.fromKatameros) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(context.tr('katamerosCredit'), style: TextStyle(fontSize: 11.5, color: context.pal.muted)),
        ));
      }
    }
    return Container(
      key: const Key('topEventCard'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: context.pal.panel,
        borderRadius: BorderRadius.circular(kPanelRadius),
        border: Border.all(color: context.pal.ornamentLine),
        boxShadow: context.pal.panelShadow,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(
            switch (e.kind) {
              TopEventKind.church => Icons.campaign_rounded,
              TopEventKind.service => Icons.event_note_rounded,
              _ => Icons.auto_awesome_rounded,
            },
            color: primary),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
      ]),
    );
  }
}

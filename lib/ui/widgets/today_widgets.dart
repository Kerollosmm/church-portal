import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/today.dart';
import '../../state/providers.dart';
import 'common.dart';

/// Top utility bar with the Coptic date of the liturgical day (ADR-039)
/// and optional pulsing live-stream badge when active (ADR-040).
/// Height: 32px, liturgical burgundy background `#3B0A0A`, gold hairline bottom border.
class TopUtilityBar extends ConsumerWidget {
  final String location;
  const TopUtilityBar({super.key, required this.location});

  static bool shownOn(String mode, String location) =>
      mode == CopticStripModes.all || (mode == CopticStripModes.home && location == '/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(featuresReadyProvider)) return const SizedBox.shrink();
    final t = ref.watch(todaySettingsProvider);
    final mode = t.copticStrip;
    final showDate = shownOn(mode, location);
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    final liveActive = t.liveOn(now);
    if (!showDate && !liveActive) return const SizedBox.shrink();

    final day = ref.watch(liturgicalDayProvider);
    final label = day.label(arabic: context.isAr);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Container(
        key: const Key('copticDateStrip'),
        width: double.infinity,
        height: 32.0,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: Color(0xFF3B0A0A),
          border: Border(bottom: BorderSide(color: Color(0x33C9963F), width: 1)),
        ),
        child: Row(
          children: [
            if (showDate)
              Expanded(
                child: Semantics(
                  container: true,
                  label: '${context.tr('copticDate')}: $label',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.event_note_rounded, size: 14, color: Color(0xFFC9963F)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'IBM Plex Sans Arabic',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF6E7C8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              const Spacer(),
            if (liveActive) ...[
              const SizedBox(width: 8),
              Flexible(child: _LiveBadge(settings: t)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compatibility alias so existing code and tests referring to CopticDateStrip continue working.
typedef CopticDateStrip = TopUtilityBar;

class _LiveBadge extends StatelessWidget {
  final TodaySettings settings;
  const _LiveBadge({required this.settings});

  @override
  Widget build(BuildContext context) {
    final custom = context.pick(settings.liveLabelAr, settings.liveLabelEn).trim();
    final label = custom.isEmpty ? context.tr('liveBadge') : custom;
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
              color: const Color(0xFFB3261E),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x66F6E7C8), width: 0.8),
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
                    style: const TextStyle(
                      fontFamily: 'IBM Plex Sans Arabic',
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
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
    const red = Color(0xFFB3261E);
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
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_arrow_rounded, size: 18, color: red),
                  Text(context.tr('watchLive'),
                      style: const TextStyle(color: red, fontWeight: FontWeight.w800, fontSize: 13)),
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
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
      );
}

/// The top event of the day on Home (ADR-040): the admin's church event, or
/// the day's feast / commemoration (Katameros, else the computed list).
class TopEventCard extends ConsumerWidget {
  const TopEventCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = ref.watch(topEventProvider);
    if (e == null) return const SizedBox.shrink();
    final title = context.pick(e.titleAr, e.titleEn).trim();
    if (title.isEmpty) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;
    final kicker = switch (e.kind) {
      TopEventKind.church => context.tr('todayEvent'),
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
      if (link.isNotEmpty) {
        children.add(Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: () => internal ? context.go(link) : openUrl(link),
            child: Text(context.tr('learnMore')),
          ),
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
        border: Border.all(color: const Color(0x61C9963F)),
        boxShadow: kPanelShadow,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(e.kind == TopEventKind.church ? Icons.campaign_rounded : Icons.auto_awesome_rounded, color: primary),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
      ]),
    );
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/app_config.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/assistant_model.dart';
import '../../data/assistant_usage_store.dart';
import '../../domain/assistant_context.dart';
import '../../domain/assistant_conversation.dart';
import '../../domain/assistant_quota.dart';
import '../../domain/assistant_settings.dart';
import '../../domain/contact_categories.dart';
import '../../domain/custom_content.dart';
import '../../domain/cairo_time.dart';
import '../../domain/features.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';
import '../widgets/safe_markdown.dart';

class _Msg {
  final bool user;
  final String text;
  final bool error;
  const _Msg(this.user, this.text, {this.error = false});
}

/// The model behind the assistant (Firebase AI Logic). Overridden in tests
/// with a fake. Declared here, in the deferred /ask chunk, so `firebase_ai`
/// stays out of the main bundle.
final assistantModelProvider = Provider<AssistantModel>((ref) => const FirebaseAssistantModel());

/// This device's daily question counter (ADR-031): shared_preferences
/// (localStorage on web). Overridden in tests with a [MemoryUsageStore].
final assistantUsageStoreProvider = FutureProvider<AssistantUsageStore>((ref) => PrefsUsageStore.load());

/// "Ask the church" assistant — Gemini via Firebase AI Logic (ADR-014,
/// ADR-029), grounded on the live portal content through the system
/// instruction, limited to church topics (out-of-scope questions get the
/// admin's refusal message) and rate-limited per visit.
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  late final AssistantConversation _conversation =
      AssistantConversation(ref.read(assistantModelProvider), defaultModel: AppConfig.geminiModel);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(assistantUsageStoreProvider.future).then(
          (u) => _conversation.limiter.usage ??= u,
          onError: (Object _) => _conversation.limiter.usage ??= MemoryUsageStore(),
        );
    // Mint the App Check token while the visitor reads the welcome, so the
    // first question does not race it (the model also retries once).
    if (ref.read(firebaseStatusProvider).appCheckActive) {
      ref.read(assistantModelProvider).warmUp();
    }
  }

  /// Keeps every provider the instruction is built from subscribed while the
  /// page is open. Riverpod 3 pauses a provider nobody listens to, so a
  /// stream the page only `read` (liturgies, meetings, priests…) never
  /// delivered on a direct visit to /ask: `_awaitContent` timed out and the
  /// first prompt had empty sections ("no mass schedule data"). Watching them
  /// also starts loading them as soon as the page opens. Contact types and
  /// custom sections / pages only while their section is on.
  void _watchGrounding() {
    final f = ref.watch(featuresProvider);
    ref
      ..watch(featuresStreamProvider)
      ..watch(liturgiesProvider)
      ..watch(seasonsProvider)
      ..watch(clinicsProvider)
      ..watch(meetingsProvider)
      ..watch(activitiesProvider)
      ..watch(facilitiesProvider)
      ..watch(alertsProvider)
      ..watch(priestsProvider)
      ..watch(saintsProvider);
    if (f.enabled(Sections.milestones)) ref.watch(milestonesProvider);
    if (f.enabled(Sections.contactForm)) ref.watch(contactSettingsProvider);
    if (f.enabled(Sections.customSections)) {
      ref
        ..watch(categoriesProvider)
        ..watch(entriesProvider);
    }
    if (f.enabled(Sections.customPages)) ref.watch(customPagesProvider);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Waits (briefly) for every content stream the instruction is built from,
  /// so the first question is not answered from a partial context. Sections
  /// switched on while waiting are picked up: the section flags are re-read
  /// after each round until they stop changing (within the 10 s budget).
  Future<void> _awaitContent() async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    final done = <String>{};
    try {
      await Future.wait<Object?>([
        ref.read(settingsProvider.future),
        ref.read(featuresStreamProvider.future),
        ref.read(assistantSettingsProvider.future),
        ref.read(liturgiesProvider.future),
        ref.read(seasonsProvider.future),
        ref.read(clinicsProvider.future),
        ref.read(meetingsProvider.future),
        ref.read(activitiesProvider.future),
        ref.read(facilitiesProvider.future),
        ref.read(alertsProvider.future),
        ref.read(priestsProvider.future),
        ref.read(saintsProvider.future),
      ]).timeout(deadline.difference(DateTime.now()));
      while (true) {
        final f = ref.read(featuresProvider);
        // Grounded only while their section is on.
        final pending = {
          if (f.enabled(Sections.milestones)) Sections.milestones,
          if (f.enabled(Sections.contactForm)) Sections.contactForm,
          if (f.enabled(Sections.customSections)) Sections.customSections,
          if (f.enabled(Sections.customPages)) Sections.customPages,
        }.difference(done);
        if (pending.isEmpty) break;
        final left = deadline.difference(DateTime.now());
        if (left <= Duration.zero) break;
        await Future.wait<Object?>([
          if (pending.contains(Sections.milestones)) ref.read(milestonesProvider.future),
          if (pending.contains(Sections.contactForm)) ref.read(contactSettingsProvider.future),
          if (pending.contains(Sections.customSections)) ref.read(categoriesProvider.future),
          if (pending.contains(Sections.customSections)) ref.read(entriesProvider.future),
          if (pending.contains(Sections.customPages)) ref.read(customPagesProvider.future),
        ]).timeout(left);
        done.addAll(pending);
      }
    } catch (e) {
      debugPrint('Assistant: content not fully loaded: $e');
    }
  }

  AssistantSettings get _settings => ref.read(assistantSettingsProvider).value ?? AssistantSettings.defaults;

  /// Contact types / custom sections / custom pages, read only while their
  /// section is on (a switched-off section's provider is never subscribed).
  ({ContactSettings contact, List<CustomCategory> categories, List<CategoryEntry> entries, List<CustomPage> pages})
      _customInputs(FeatureSettings f) => (
            contact: f.enabled(Sections.contactForm)
                ? (ref.read(contactSettingsProvider).value ?? ContactSettings.defaults)
                : ContactSettings.defaults,
            categories: f.enabled(Sections.customSections) ? (ref.read(categoriesProvider).value ?? const []) : const [],
            entries: f.enabled(Sections.customSections) ? (ref.read(entriesProvider).value ?? const []) : const [],
            pages: f.enabled(Sections.customPages) ? (ref.read(customPagesProvider).value ?? const []) : const [],
          );

  String _buildInstruction() {
    final f = ref.read(featuresProvider);
    final c = _customInputs(f);
    return buildAssistantInstruction(
      settings: ref.read(settingsProvider).requireValue,
      liturgies: ref.read(liturgiesProvider).value ?? const [],
      seasons: ref.read(seasonsProvider).value ?? const [],
      clinics: ref.read(clinicsProvider).value ?? const [],
      meetings: ref.read(meetingsProvider).value ?? const [],
      activities: ref.read(activitiesProvider).value ?? const [],
      facilities: ref.read(facilitiesProvider).value ?? const [],
      now: CairoTime.now(),
      features: f,
      alerts: ref.read(alertsProvider).value ?? const [],
      priests: ref.read(priestsProvider).value ?? const [],
      saints: ref.read(saintsProvider).value ?? const [],
      milestones: ref.read(milestonesProvider).value ?? const [],
      assistant: _settings,
      categories: c.categories,
      entries: c.entries,
      pages: c.pages,
      contact: c.contact,
    );
  }

  /// Enabled sections + detail grounding + contact types / custom sections /
  /// pages grounding: when any of them changes, earlier turns (possibly
  /// quoting content an admin withdrew) are not replayed.
  String _historyKey() {
    final f = ref.read(featuresProvider);
    final sections = [for (final s in Sections.all) if (f.enabled(s)) s].join(',');
    final details = assistantDetailSignature(
      features: f,
      clinics: ref.read(clinicsProvider).value ?? const [],
      meetings: ref.read(meetingsProvider).value ?? const [],
      activities: ref.read(activitiesProvider).value ?? const [],
      facilities: ref.read(facilitiesProvider).value ?? const [],
      priests: ref.read(priestsProvider).value ?? const [],
      saints: ref.read(saintsProvider).value ?? const [],
      milestones: ref.read(milestonesProvider).value ?? const [],
    );
    final c = _customInputs(f);
    final custom = assistantCustomSignature(
        features: f, contact: c.contact, categories: c.categories, entries: c.entries, pages: c.pages);
    // The allowed topics too: answers about a topic an admin removed are not
    // replayed.
    final topics = _settings.effectiveTopics.join('\n');
    return '$sections\u0000$details\u0000$custom\u0000$topics';
  }

  static String _cairoStamp() {
    final n = CairoTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)} (${weekdayNamesEn[n.weekday]})';
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _input.text).trim();
    if (q.isEmpty || _busy) return;
    final s = _settings;
    // The device's daily counter (preloaded in initState; memory-only if
    // storage fails).
    if (_conversation.limiter.usage == null) {
      try {
        _conversation.limiter.usage ??= await ref.read(assistantUsageStoreProvider.future);
      } catch (_) {
        _conversation.limiter.usage ??= MemoryUsageStore();
      }
      if (!mounted) return;
    }
    // Checked before anything is shown or sent (length, per-minute and
    // per-device daily limits).
    final blocked = _conversation.precheck(q, s, DateTime.now());
    if (blocked != null) {
      setState(() => _messages.add(_Msg(false, _blockedText(blocked, s), error: true)));
      _scrollDown();
      return;
    }
    final errorText = context.tr('askError');
    setState(() {
      _messages.add(_Msg(true, q));
      _busy = true;
      _input.clear();
    });
    _scrollDown();
    try {
      await _awaitContent();
      if (!mounted) return;
      final r = await _conversation.ask(
        q,
        settings: _settings,
        instruction: _buildInstruction(),
        historyKey: _historyKey(),
        now: DateTime.now(),
        stamp: '[Current Cairo time: ${_cairoStamp()}]',
      );
      if (!mounted) return;
      setState(() => _messages.add(switch (r.outcome) {
            AssistantOutcome.answer || AssistantOutcome.refused => _Msg(false, r.text),
            AssistantOutcome.sourceSearch => _Msg(false, _sourceSearchText(q, s)),
            AssistantOutcome.error => _Msg(false, errorText, error: true),
            final o => _Msg(false, _blockedText(o, s), error: true),
          }));
    } catch (e) {
      debugPrint('Assistant error: $e');
      if (!mounted) return;
      setState(() => _messages.add(_Msg(false, errorText, error: true)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollDown();
      }
    }
  }

  String _blockedText(AssistantOutcome o, AssistantSettings s) => switch (o) {
        AssistantOutcome.rateLimitedMinute => context.tr('askSlowDown'),
        AssistantOutcome.rateLimitedDay => context.tr('askDayLimit', {'n': '${s.perDay}'}),
        AssistantOutcome.invalid => context.tr('askTooLong', {'n': '${s.maxChars}'}),
        _ => context.tr('askError'),
      };

  /// Faith / church question not in the data (ADR-031): the admin's faith
  /// reply, a search restricted to the source domains, and the contact page.
  String _sourceSearchText(String question, AssistantSettings s) {
    final ar = looksArabic(question);
    final domains = s.effectiveSourceDomains;
    final searchLabel = ar ? 'ابحث في ${domains.join('، ')}' : 'Search ${domains.join(', ')}';
    final contactLabel = ar ? 'صفحة تواصل معنا' : 'Contact page';
    return '${s.faithReply(ar)}\n'
        '- [$searchLabel](${sourceSearchUrl(domains, question)})\n'
        '- [$contactLabel](/contact)';
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(assistantVisibleProvider);
    final settings = ref.watch(settingsProvider);
    if (visible) _watchGrounding();
    if (settings.isLoading) return const Center(child: CircularProgressIndicator());
    if (!visible) {
      return PageBody(
        header: CustomizablePageHeader(
            pageKey: CustomizablePages.ask, title: context.tr('askTitle'), icon: Icons.auto_awesome_rounded),
        children: [const PageIntro(pageKey: CustomizablePages.ask), EmptyState(message: context.tr('askUnavailable'), icon: Icons.smart_toy_outlined)],
      );
    }
    final cfg = ref.watch(assistantSettingsProvider).value ?? AssistantSettings.defaults;
    // No chips unless the admin turned "Show suggested questions" on; no
    // built-in fallbacks.
    final suggestions = cfg.visibleSuggestions(context.isAr);
    final welcome = cfg.welcome(context.isAr);
    return Column(children: [
      CustomizablePageHeader(
          pageKey: CustomizablePages.ask,
          title: context.tr('askTitle'),
          subtitle: context.tr('askDisclaimer'),
          icon: Icons.auto_awesome_rounded),
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
              const PageIntro(pageKey: CustomizablePages.ask),
              _bubble(_Msg(false, welcome.isNotEmpty ? welcome : context.tr('askIntro'))),
              if (_messages.isEmpty && suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in suggestions)
                      ActionChip(
                        label: Text(s),
                        avatar: Icon(Icons.lightbulb_outline, size: 18, color: context.pal.goldText),
                        onPressed: () => _send(s),
                      ),
                  ]),
                ),
              for (final m in _messages) _bubble(m),
              if (_busy)
                // Announced by screen readers while the answer is on its way.
                Semantics(
                  liveRegion: true,
                  label: context.tr('sending'),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: context.pal.surface,
            border: Border(top: BorderSide(color: AppColors.gold.withValues(alpha: 0.4))),
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    key: const Key('askInput'),
                    maxLength: cfg.maxChars,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(hintText: context.tr('askHint'), counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: context.tr('send'),
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _bubble(_Msg m) {
    return Align(
      alignment: m.user ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: m.user
              ? Theme.of(context).colorScheme.primary
              : m.error
                  ? const Color(0xFFFDECEA)
                  : context.pal.surface,
          borderRadius: BorderRadius.circular(4),
          border: m.user ? null : Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        ),
        child: m.user
            ? SelectableText(m.text, style: TextStyle(color: context.pal.onPrimary, height: 1.6))
            // Replies and notices are Markdown: render the safe subset (ADR-030).
            : SafeMarkdown(m.text,
                style: TextStyle(color: m.error ? AppColors.ink : context.pal.ink, height: 1.6)),
      ),
    );
  }
}

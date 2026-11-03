import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/app_config.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/assistant_model.dart';
import '../../domain/assistant_context.dart';
import '../../domain/assistant_conversation.dart';
import '../../domain/assistant_settings.dart';
import '../../domain/contact_categories.dart';
import '../../domain/cairo_time.dart';
import '../../domain/features.dart';
import '../../domain/time_format.dart';
import '../../state/providers.dart';
import '../widgets/common.dart';

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
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Waits (briefly) for every content stream the instruction is built from,
  /// so the first question is not answered from a partial context.
  Future<void> _awaitContent() async {
    final f = ref.read(featuresProvider);
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
        // Grounded only while their section is on.
        if (f.enabled(Sections.milestones)) ref.read(milestonesProvider.future),
        if (f.enabled(Sections.contactForm)) ref.read(contactSettingsProvider.future),
        if (f.enabled(Sections.customSections)) ref.read(categoriesProvider.future),
        if (f.enabled(Sections.customSections)) ref.read(entriesProvider.future),
        if (f.enabled(Sections.customPages)) ref.read(customPagesProvider.future),
      ]).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Assistant: content not fully loaded: $e');
    }
  }

  AssistantSettings get _settings => ref.read(assistantSettingsProvider).value ?? AssistantSettings.defaults;

  String _buildInstruction() => buildAssistantInstruction(
        settings: ref.read(settingsProvider).requireValue,
        liturgies: ref.read(liturgiesProvider).value ?? const [],
        seasons: ref.read(seasonsProvider).value ?? const [],
        clinics: ref.read(clinicsProvider).value ?? const [],
        meetings: ref.read(meetingsProvider).value ?? const [],
        activities: ref.read(activitiesProvider).value ?? const [],
        facilities: ref.read(facilitiesProvider).value ?? const [],
        now: CairoTime.now(),
        features: ref.read(featuresProvider),
        alerts: ref.read(alertsProvider).value ?? const [],
        priests: ref.read(priestsProvider).value ?? const [],
        saints: ref.read(saintsProvider).value ?? const [],
        milestones: ref.read(milestonesProvider).value ?? const [],
        assistant: _settings,
        categories: ref.read(categoriesProvider).value ?? const [],
        entries: ref.read(entriesProvider).value ?? const [],
        pages: ref.read(customPagesProvider).value ?? const [],
        contact: ref.read(contactSettingsProvider).value ?? ContactSettings.defaults,
      );

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
    final custom = assistantCustomSignature(
      features: f,
      contact: ref.read(contactSettingsProvider).value ?? ContactSettings.defaults,
      categories: ref.read(categoriesProvider).value ?? const [],
      entries: ref.read(entriesProvider).value ?? const [],
      pages: ref.read(customPagesProvider).value ?? const [],
    );
    return '$sections\u0000$details\u0000$custom';
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
    // Checked before anything is shown or sent (length, per-minute and
    // per-visit limits).
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
        AssistantOutcome.rateLimitedSession => context.tr('askSessionLimit'),
        AssistantOutcome.invalid => context.tr('askTooLong', {'n': '${s.maxChars}'}),
        _ => context.tr('askError'),
      };

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
    if (settings.isLoading) return const Center(child: CircularProgressIndicator());
    if (!visible) {
      return PageBody(
        header: CustomizablePageHeader(
            pageKey: CustomizablePages.ask, title: context.tr('askTitle'), icon: Icons.auto_awesome_rounded),
        children: [const PageIntro(pageKey: CustomizablePages.ask), EmptyState(message: context.tr('askUnavailable'), icon: Icons.smart_toy_outlined)],
      );
    }
    final cfg = ref.watch(assistantSettingsProvider).value ?? AssistantSettings.defaults;
    final custom = cfg.suggestions(context.isAr);
    final suggestions =
        custom.isNotEmpty ? custom : [context.tr('askSuggest1'), context.tr('askSuggest2'), context.tr('askSuggest3')];
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
              if (_messages.isEmpty)
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
        child: SelectableText(m.text, style: TextStyle(
                color: m.user ? context.pal.onPrimary : (m.error ? AppColors.ink : context.pal.ink), height: 1.6)),
      ),
    );
  }
}

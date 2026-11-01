import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/app_config.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../domain/assistant_context.dart';
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

/// "Ask the church" assistant — Gemini via Firebase AI Logic, grounded on
/// the portal content (schedule, clinics, meetings, contacts) through the
/// system instruction. Hidden when settings/church.assistantEnabled=false.
class AssistantPage extends ConsumerStatefulWidget {
  const AssistantPage({super.key});

  @override
  ConsumerState<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends ConsumerState<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [];
  ChatSession? _chat;
  String? _chatInstruction;

  /// Enabled sections the history was built under: when they change, earlier
  /// turns (possibly about a section now switched off) are not replayed.
  String? _historySections;
  bool _busy = false;

  /// Successful turns (user + model), replayed when the session is rebuilt
  /// after a failure or a content/date change. Capped so request size and
  /// cost stay bounded; the oldest turns drop off first.
  final List<Content> _history = [];
  static const _maxHistoryContents = 20; // 10 question/answer turns

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Waits (briefly) for every content stream the instruction is built from,
  /// so the first question is not answered from a partial context.
  Future<void> _awaitContent() async {
    try {
      await Future.wait<Object?>([
        ref.read(settingsProvider.future),
        ref.read(featuresStreamProvider.future),
        ref.read(liturgiesProvider.future),
        ref.read(seasonsProvider.future),
        ref.read(clinicsProvider.future),
        ref.read(meetingsProvider.future),
        ref.read(activitiesProvider.future),
        ref.read(facilitiesProvider.future),
        ref.read(alertsProvider.future),
        ref.read(priestsProvider.future),
        ref.read(saintsProvider.future),
      ]).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Assistant: content not fully loaded: $e');
    }
  }

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
      );

  /// Reuses the chat while the grounding (church data + Cairo date) is
  /// unchanged; otherwise starts a new one that carries the earlier turns.
  ChatSession _session() {
    final instruction = _buildInstruction();
    if (_chat != null && instruction == _chatInstruction) return _chat!;
    final f = ref.read(featuresProvider);
    final sections = [for (final s in Sections.all) if (f.enabled(s)) s].join(',');
    if (_historySections != null && _historySections != sections) _history.clear();
    _historySections = sections;
    final model = FirebaseAI.googleAI().generativeModel(
      model: AppConfig.geminiModel,
      systemInstruction: Content.system(instruction),
      generationConfig: GenerationConfig(temperature: 0.2, maxOutputTokens: 800),
    );
    _chatInstruction = instruction;
    return _chat = model.startChat(history: List.of(_history));
  }

  static String _cairoStamp() {
    final n = CairoTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)} (${weekdayNamesEn[n.weekday]})';
  }

  Future<void> _send([String? preset]) async {
    final q = (preset ?? _input.text).trim();
    if (q.isEmpty || _busy) return;
    if (q.length > 500) return;
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
      final prompt = Content.text('[Current Cairo time: ${_cairoStamp()}]\n$q');
      final r = await _session().sendMessage(prompt).timeout(const Duration(seconds: 45));
      final text = r.text?.trim();
      final ok = text != null && text.isNotEmpty;
      if (ok) {
        _history
          ..add(prompt)
          ..add(Content.model([TextPart(text)]));
        if (_history.length > _maxHistoryContents) {
          _history.removeRange(0, _history.length - _maxHistoryContents);
          _chat = null; // rebuild with the trimmed history on the next question
        }
      }
      if (!mounted) return;
      setState(() => _messages.add(_Msg(false, ok ? text : errorText, error: !ok)));
    } catch (e) {
      debugPrint('Assistant error: $e');
      _chat = null; // rebuild the session (with the kept history) on next try
      if (!mounted) return;
      setState(() => _messages.add(_Msg(false, errorText, error: true)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollDown();
      }
    }
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
    if (settings.isLoading) return const Center(child: CircularProgressIndicator());
    if (!visible) {
      return PageBody(
        header: PageHeader(title: context.tr('askTitle'), icon: Icons.auto_awesome_rounded),
        children: [EmptyState(message: context.tr('askUnavailable'), icon: Icons.smart_toy_outlined)],
      );
    }
    final suggestions = [context.tr('askSuggest1'), context.tr('askSuggest2'), context.tr('askSuggest3')];
    return Column(children: [
      PageHeader(title: context.tr('askTitle'), subtitle: context.tr('askDisclaimer'), icon: Icons.auto_awesome_rounded),
      Expanded(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
              _bubble(_Msg(false, context.tr('askIntro'))),
              if (_messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final s in suggestions)
                      ActionChip(
                        label: Text(s),
                        avatar: const Icon(Icons.lightbulb_outline, size: 18, color: AppColors.gold),
                        onPressed: () => _send(s),
                      ),
                  ]),
                ),
              for (final m in _messages) _bubble(m),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4)),
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
            color: Colors.white,
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
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(hintText: context.tr('askHint'), counterText: ''),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
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
              ? AppColors.burgundy
              : m.error
                  ? const Color(0xFFFDECEA)
                  : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: m.user ? null : Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
        ),
        child: SelectableText(m.text, style: TextStyle(color: m.user ? Colors.white : AppColors.ink, height: 1.6)),
      ),
    );
  }
}

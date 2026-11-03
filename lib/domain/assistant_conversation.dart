// The assistant's conversation logic (ADR-029), kept free of Firebase so it
// is unit-tested with a fake model: message length and rate limits, the
// replayed history (capped, cleared when the grounding's sections / detail
// signature change), the out-of-scope refusal swap and the model fallback.

import 'assistant_settings.dart';

/// One past turn sent back to the model.
class AssistantTurn {
  final bool user;
  final String text;
  const AssistantTurn(this.user, this.text);
}

/// The generative model behind the assistant. The app uses Firebase AI
/// Logic (`lib/data/assistant_model.dart`); tests use a fake.
abstract class AssistantModel {
  /// Sends [prompt] after [history] under [instruction]; returns the reply
  /// text (null / empty = no answer). Throws on transport / model errors.
  Future<String?> generate({
    required String model,
    required String instruction,
    required List<AssistantTurn> history,
    required String prompt,
  });
}

enum AssistantOutcome {
  /// The model answered (on topic).
  answer,

  /// The model flagged the question as out of scope: [AssistantReply.text]
  /// is the admin's refusal message.
  refused,

  /// Blank or too long; nothing was sent.
  invalid,

  /// Too many questions this minute; nothing was sent.
  rateLimitedMinute,

  /// The per-visit question limit is used up; nothing was sent.
  rateLimitedSession,

  /// The model call failed or returned nothing.
  error,
}

class AssistantReply {
  final AssistantOutcome outcome;
  final String text;
  const AssistantReply(this.outcome, [this.text = '']);
  bool get ok => outcome == AssistantOutcome.answer || outcome == AssistantOutcome.refused;
}

/// Arabic letters anywhere in the question → reply in Arabic. Letters only:
/// Arabic-Indic digits, tatweel and combining marks do not count.
final _arabicLetter = RegExp('[\u0621-\u063A\u0641-\u064A\u0671-\u06D3\u06D5\u06EE\u06EF\u06FA-\u06FC\u06FF'
    '\u0750-\u077F\u08A0-\u08C9]');
bool looksArabic(String s) => _arabicLetter.hasMatch(s);

/// Client-side limits per page session: [perMinute] questions in any rolling
/// 60 s and [perSession] in total. Only questions actually sent count.
class AssistantRateLimiter {
  final List<DateTime> _sent = [];
  int _total = 0;

  int get total => _total;

  AssistantOutcome? check(DateTime now, AssistantSettings s) {
    if (_total >= s.perSession) return AssistantOutcome.rateLimitedSession;
    _sent.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    if (_sent.length >= s.perMinute) return AssistantOutcome.rateLimitedMinute;
    return null;
  }

  void record(DateTime now) {
    _sent.add(now);
    _total++;
  }
}

/// Whether [e] says that [model] does not exist / is not available (then
/// the default model is tried once instead). The error must name the model
/// (or "model") AND say it is missing / unsupported, so an unrelated 404 does
/// not switch models.
bool isModelUnavailableError(Object e, String model) {
  final t = e.toString().toLowerCase();
  final aboutModel = t.contains(model.toLowerCase()) || t.contains('model');
  final unavailable = t.contains('not found') ||
      t.contains('not_found') ||
      t.contains('404') ||
      t.contains('is not supported') ||
      t.contains('unsupported') ||
      t.contains('no longer available') ||
      t.contains('deprecated');
  return aboutModel && unavailable;
}

class AssistantConversation {
  final AssistantModel backend;

  /// Build-time default model (AppConfig.geminiModel).
  final String defaultModel;

  /// Max contents replayed (user + model), oldest dropped first.
  final int maxHistory;

  AssistantConversation(this.backend, {required this.defaultModel, this.maxHistory = 20});

  final List<AssistantTurn> _history = [];
  final AssistantRateLimiter limiter = AssistantRateLimiter();
  String? _historyKey;

  /// Models that failed as unavailable this session (not retried).
  final Set<String> _badModels = {};

  List<AssistantTurn> get history => List.unmodifiable(_history);

  /// Checks [question] without sending it.
  AssistantOutcome? precheck(String question, AssistantSettings s, DateTime now) {
    final q = question.trim();
    if (q.isEmpty || q.length > s.maxChars) return AssistantOutcome.invalid;
    return limiter.check(now, s);
  }

  /// Asks [question] under the grounding [instruction]. [historyKey]
  /// (enabled sections + detail signature) clears the replayed history when
  /// it changes, so answers about content an admin withdrew are not sent
  /// again. [stamp] prefixes the question (current Cairo time).
  Future<AssistantReply> ask(
    String question, {
    required AssistantSettings settings,
    required String instruction,
    required String historyKey,
    required DateTime now,
    String stamp = '',
  }) async {
    final q = question.trim();
    final blocked = precheck(q, settings, now);
    if (blocked != null) return AssistantReply(blocked);
    if (_historyKey != null && _historyKey != historyKey) _history.clear();
    _historyKey = historyKey;
    limiter.record(now);
    final prompt = stamp.isEmpty ? q : '$stamp\n$q';
    final arabic = looksArabic(q);
    String? raw;
    try {
      raw = await _generate(settings, instruction, prompt);
    } catch (_) {
      return const AssistantReply(AssistantOutcome.error);
    }
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return const AssistantReply(AssistantOutcome.error);
    if (isOutOfScopeReply(text)) {
      // Refusals are not replayed: they add nothing for later questions.
      return AssistantReply(AssistantOutcome.refused, settings.refusal(arabic));
    }
    _history
      ..add(AssistantTurn(true, prompt))
      ..add(AssistantTurn(false, text));
    if (_history.length > maxHistory) _history.removeRange(0, _history.length - maxHistory);
    return AssistantReply(AssistantOutcome.answer, text);
  }

  Future<String?> _generate(AssistantSettings s, String instruction, String prompt) async {
    final chosen = s.effectiveModel(defaultModel);
    final model = _badModels.contains(chosen) ? defaultModel : chosen;
    try {
      return await backend.generate(model: model, instruction: instruction, history: history, prompt: prompt);
    } catch (e) {
      if (model == defaultModel || !isModelUnavailableError(e, model)) rethrow;
      // The admin's model is unknown / retired: fall back to the default.
      _badModels.add(model);
      return backend.generate(model: defaultModel, instruction: instruction, history: history, prompt: prompt);
    }
  }
}

/// The model marked the question out of scope: the token anywhere in the
/// reply (never shown raw; the admin's refusal replaces the whole reply).
bool isOutOfScopeReply(String text) => text.contains(outOfScopeToken);

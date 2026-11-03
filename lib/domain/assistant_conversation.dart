// The assistant's conversation logic (ADR-029), kept free of Firebase so it
// is unit-tested with a fake model: message length and rate limits, the
// replayed history (capped, cleared when the grounding's sections / detail
// signature change), the out-of-scope refusal swap and the model fallback.

import 'assistant_quota.dart';
import 'error_privacy.dart';
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

  /// Called when the assistant page opens: fetches the App Check token
  /// ahead of the first question. Never throws.
  Future<void> warmUp();
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

  /// This device used up today's questions (Cairo day); nothing was sent.
  rateLimitedDay,

  /// The model flagged a faith / church question the data does not answer
  /// ([sourceSearchToken]): the app shows the faith reply + search links.
  sourceSearch,

  /// The model call failed or returned nothing.
  error,
}

class AssistantReply {
  final AssistantOutcome outcome;
  final String text;
  const AssistantReply(this.outcome, [this.text = '']);
  bool get ok =>
      outcome == AssistantOutcome.answer ||
      outcome == AssistantOutcome.refused ||
      outcome == AssistantOutcome.sourceSearch;
}

/// Arabic letters anywhere in the question → reply in Arabic. Letters only:
/// Arabic-Indic digits, tatweel and combining marks do not count.
final _arabicLetter = RegExp('[\u0621-\u063A\u0641-\u064A\u0671-\u06D3\u06D5\u06EE\u06EF\u06FA-\u06FC\u06FF'
    '\u0750-\u077F\u08A0-\u08C9]');
bool looksArabic(String s) => _arabicLetter.hasMatch(s);

/// Client-side limits: [perMinute] questions in any rolling 60 s (this page
/// session) and [perDay] per device per Cairo day (when a [usage] store is
/// set — ADR-031). Only questions actually sent count.
class AssistantRateLimiter {
  final List<DateTime> _sent = [];
  int _total = 0;

  /// The device's daily counter (null = no daily limit, e.g. before the
  /// store has loaded in tests).
  AssistantUsageStore? usage;

  int get total => _total;

  AssistantOutcome? check(DateTime now, AssistantSettings s) {
    final u = usage;
    if (u != null && u.read().reached(cairoDayKey(now), s.perDay)) return AssistantOutcome.rateLimitedDay;
    _sent.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    if (_sent.length >= s.perMinute) return AssistantOutcome.rateLimitedMinute;
    return null;
  }

  void record(DateTime now) {
    _sent.add(now);
    _total++;
    final u = usage;
    if (u != null) u.write(u.read().recorded(cairoDayKey(now)));
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

/// Whether one more identical call may succeed: App Check (token still
/// minting on the first call), network, timeout and server errors are; quota /
/// rate limits, invalid requests and safety blocks are not (a repeat gets the
/// same rejection). Model-unavailable errors are handled by the fallback.
bool isRetryableAssistantError(Object e) {
  final t = e.toString().toLowerCase();
  const permanent = [
    '429',
    'quota',
    'resource_exhausted',
    'resource exhausted',
    'rate limit',
    'too many requests',
    'invalid_argument',
    'invalid argument',
    '400',
    'safety',
    'blocked',
    'billing',
  ];
  return !permanent.any(t.contains);
}

/// An assistant failure as it may be reported (ADR-034): the error's type
/// and its message with the visitor's question removed ([redact]).
class AssistantFailure implements Exception {
  final String type;
  final String message;
  const AssistantFailure(this.type, this.message);

  /// [error] with every [secrets] (question, prompt) redacted.
  factory AssistantFailure.from(Object error, Iterable<String> secrets) =>
      AssistantFailure(error.runtimeType.toString(), redact(error.toString(), secrets));

  @override
  String toString() => 'AssistantFailure($type): $message';
}

class AssistantConversation {
  final AssistantModel backend;

  /// Receives failures worth reporting (ADR-034): never quota / rate-limit /
  /// billing / safety rejections (the visitor sees those as a message), and
  /// always as an [AssistantFailure] without the visitor's question.
  final void Function(AssistantFailure failure, StackTrace stack)? onError;

  /// Build-time default model (AppConfig.geminiModel).
  final String defaultModel;

  /// Max contents replayed (user + model), oldest dropped first.
  final int maxHistory;

  /// Pause before the one automatic retry of a failed / empty call.
  final Duration retryDelay;

  AssistantConversation(this.backend,
      {required this.defaultModel,
      this.maxHistory = 20,
      this.retryDelay = const Duration(milliseconds: 700),
      this.onError});

  void _report(Object e, StackTrace st, List<String> secrets) {
    if (isUserFacingAssistantError(e)) return;
    onError?.call(AssistantFailure.from(e, secrets), st);
  }

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
    // One automatic retry: the first call of a visit can fail while the App
    // Check token (reCAPTCHA Enterprise / Play Integrity) is still being
    // minted, or the model can return nothing once. Counted as one question.
    // Quota / rate-limit / bad-request errors are not retried (CodeRabbit).
    var text = '';
    (Object, StackTrace)? lastError;
    for (var attempt = 0; attempt < 2 && text.isEmpty; attempt++) {
      if (attempt > 0) await Future<void>.delayed(retryDelay);
      try {
        text = (await _generate(settings, instruction, prompt))?.trim() ?? '';
        lastError = null;
      } catch (e, st) {
        if (!isRetryableAssistantError(e)) {
          _report(e, st, [q, prompt]);
          return const AssistantReply(AssistantOutcome.error);
        }
        lastError = (e, st);
        text = '';
      }
    }
    if (text.isEmpty) {
      // Both attempts failed with a (retryable) error: worth reporting.
      if (lastError != null) _report(lastError.$1, lastError.$2, [q, prompt]);
      return const AssistantReply(AssistantOutcome.error);
    }
    if (text.contains(sourceSearchToken)) {
      // Not replayed either; the page builds the reply (search + contact).
      return const AssistantReply(AssistantOutcome.sourceSearch);
    }
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

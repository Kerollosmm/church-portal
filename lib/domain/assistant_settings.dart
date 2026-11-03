// "Ask the church" assistant settings (ADR-029): `settings/assistant`,
// edited in /admin → Assistant. A missing doc or a blank field means the code
// default below, so nothing has to be seeded. firestore.rules validAssistant
// mirrors the limits. Pure Dart.

String _s(Object? v) => v is String ? v.trim() : '';
int? _i(Object? v) => v is int ? v : (v is num && v == v.roundToDouble() ? v.toInt() : null);

/// Limits shared with firestore.rules (validAssistant) and the admin form.
class AssistantLimits {
  AssistantLimits._();
  static const modelMax = 60;
  static const instructionsMax = 4000;
  static const topicsMax = 2000;
  static const textMax = 500; // refusal / welcome per language
  static const suggestionsMax = 300; // per language, one suggestion per line
  static const maxSuggestions = 3;

  /// Message length bounds (characters).
  static const maxCharsMin = 50, maxCharsMax = 1000, maxCharsDefault = 500;

  /// Questions per rolling minute.
  static const perMinuteMin = 1, perMinuteMax = 20, perMinuteDefault = 4;

  /// Questions per visit (page session).
  static const perSessionMin = 1, perSessionMax = 200, perSessionDefault = 30;
}

/// Model names the admin may enter: a Gemini model id (lower-case letters,
/// digits, dots and hyphens). Anything else falls back to the default.
final modelNameRe = RegExp(r'^gemini-[a-z0-9][a-z0-9.\-]{0,52}$');

/// Retired families that would only fail (Gemini 1.x / 2.x).
final _retiredModelRe = RegExp(r'^gemini-(1|2)(\.|-)');

bool isUsableModelName(String m) => modelNameRe.hasMatch(m) && !_retiredModelRe.hasMatch(m);

/// The reply the model gives for an out-of-scope question; the app swaps it
/// for the admin's refusal message in the visitor's language.
const outOfScopeToken = '[[OUT_OF_SCOPE]]';

class AssistantSettings {
  /// Admin-chosen model ('' = [defaultModel]).
  final String model;

  /// Persona / tone instructions ('' = [defaultInstructions]). The scope and
  /// grounding guardrails are always added by the app and cannot be removed.
  final String instructions;

  /// Allowed topics, one per line ('' = [defaultTopics]).
  final String topics;

  final String refusalAr, refusalEn;
  final String welcomeAr, welcomeEn;

  /// Suggested questions, one per line ('' = built-in suggestions).
  final String suggestionsAr, suggestionsEn;

  /// Stored limits (null = default); read the clamped [maxChars],
  /// [perMinute] and [perSession].
  final int? rawMaxChars, rawPerMinute, rawPerSession;

  const AssistantSettings({
    this.model = '',
    this.instructions = '',
    this.topics = '',
    this.refusalAr = '',
    this.refusalEn = '',
    this.welcomeAr = '',
    this.welcomeEn = '',
    this.suggestionsAr = '',
    this.suggestionsEn = '',
    this.rawMaxChars,
    this.rawPerMinute,
    this.rawPerSession,
  });

  static const defaults = AssistantSettings();

  factory AssistantSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    return AssistantSettings(
      model: _s(m['model']),
      instructions: _s(m['instructions']),
      topics: _s(m['topics']),
      refusalAr: _s(m['refusalAr']),
      refusalEn: _s(m['refusalEn']),
      welcomeAr: _s(m['welcomeAr']),
      welcomeEn: _s(m['welcomeEn']),
      suggestionsAr: _s(m['suggestionsAr']),
      suggestionsEn: _s(m['suggestionsEn']),
      rawMaxChars: _i(m['maxChars']),
      rawPerMinute: _i(m['perMinute']),
      rawPerSession: _i(m['perSession']),
    );
  }

  /// The model actually requested: the admin's choice when it is a usable
  /// Gemini id, else [defaultModel].
  String effectiveModel(String defaultModel) => isUsableModelName(model) ? model : defaultModel;

  String get effectiveInstructions => instructions.isNotEmpty ? instructions : defaultInstructions;

  /// Allowed topics (non-empty lines, bullets stripped).
  List<String> get effectiveTopics {
    final lines = [
      for (final l in (topics.isNotEmpty ? topics : defaultTopics).split('\n'))
        if (l.replaceFirst(RegExp(r'^\s*[-*•]\s*'), '').trim().isNotEmpty) l.replaceFirst(RegExp(r'^\s*[-*•]\s*'), '').trim(),
    ];
    return lines.isEmpty ? defaultTopics.split('\n') : lines;
  }

  String refusal(bool arabic) => arabic
      ? (refusalAr.isNotEmpty ? refusalAr : defaultRefusalAr)
      : (refusalEn.isNotEmpty ? refusalEn : defaultRefusalEn);

  /// '' = the app's built-in welcome text.
  String welcome(bool arabic) => arabic ? welcomeAr : welcomeEn;

  /// Up to three suggested questions for [arabic] (empty = built-ins).
  List<String> suggestions(bool arabic) => [
        for (final l in (arabic ? suggestionsAr : suggestionsEn).split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ].take(AssistantLimits.maxSuggestions).toList();

  int get maxChars => _clamp(rawMaxChars, AssistantLimits.maxCharsMin, AssistantLimits.maxCharsMax,
      AssistantLimits.maxCharsDefault);
  int get perMinute => _clamp(rawPerMinute, AssistantLimits.perMinuteMin, AssistantLimits.perMinuteMax,
      AssistantLimits.perMinuteDefault);
  int get perSession => _clamp(rawPerSession, AssistantLimits.perSessionMin, AssistantLimits.perSessionMax,
      AssistantLimits.perSessionDefault);

  static int _clamp(int? v, int lo, int hi, int def) => v == null ? def : (v < lo ? lo : (v > hi ? hi : v));

  static const defaultInstructions =
      'You are the friendly information desk of the church. Be warm, polite and brief (at most about 6 lines). '
      'Use bullet points for lists and give times like 06:30 AM. '
      'Do not give medical, legal or spiritual-direction advice beyond pointing to the right clinic, meeting or priest. '
      'Do not ask for or collect personal data.';

  static const defaultTopics = 'Liturgy / mass, vespers and praise times, and holy seasons\n'
      'Sunday school and meetings\n'
      'Clinics and their times\n'
      'Activities and public services\n'
      'Priests, departed fathers and patron saints\n'
      'Church history and milestones\n'
      'Announcements\n'
      'Contact details, location and directions\n'
      'Hall bookings and the contact form\n'
      'Donations page\n'
      'The custom sections and pages of this website';

  static const defaultRefusalAr =
      'عذرًا، أنا مساعد الكنيسة وأجيب فقط عن أسئلة الكنيسة وخدماتها: مواعيد القداسات والاجتماعات والعيادات والأنشطة والآباء الكهنة والقديسين والتواصل والعنوان والحجوزات والتبرعات. كيف أساعدك في شيء من ذلك؟';
  static const defaultRefusalEn =
      "Sorry, I'm the church's assistant and can only help with questions about this church and its services: "
      'mass and meeting times, clinics, activities, priests, saints, contact, location, bookings and donations. '
      'How can I help with one of those?';
}

// "Ask the church" assistant settings (ADR-029): `settings/assistant`,
// edited in /admin → Assistant. A missing doc or a blank field means the code
// default below, so nothing has to be seeded. firestore.rules validAssistant
// mirrors the limits. Pure Dart.

import 'assistant_quota.dart' show parseSourceDomains;

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
  static const faithReplyMax = 300; // reply for faith questions not in the data, per language
  static const sourceDomainsMax = 300;
  static const maxSuggestions = 3;

  /// Message length bounds (characters).
  static const maxCharsMin = 50, maxCharsMax = 1000, maxCharsDefault = 500;

  /// Questions per rolling minute.
  static const perMinuteMin = 1, perMinuteMax = 20, perMinuteDefault = 4;

  /// Questions per device per Cairo day (ADR-031; replaced the per-visit
  /// limit — a legacy `perSession` value is ignored).
  static const perDayMin = 1, perDayMax = 100, perDayDefault = 3;

  /// Questions per device per Cairo day while an exceptional season is
  /// active (ADR-042: Holy Week, Pascha, Nativity, revivals — not summer).
  static const perDaySeasonDefault = 6;
}

/// Season keys that raise the daily limit to [AssistantSettings.perDaySeason]
/// while active (ADR-042). The summer season is a long, ordinary period.
const exceptionalSeasonKeys = ['holy_week', 'pascha', 'nativity', 'revival_maximus', 'revival_moses'];

/// Which public sections an allowed-topic line needs (ADR-042): a line that
/// mentions one of the words is dropped when none of its sections is on, so
/// the assistant never offers clinics, meetings… that the admin switched off.
/// Applies to the admin's own topic lines as well as the defaults.
const topicSectionWords = <List<String>, List<String>>{
  ['clinic', 'عياد', 'عيادة']: ['clinics'],
  ['meeting', 'sunday school', 'اجتماع', 'مدارس الأحد', 'التربية الكنسية']: ['meetings'],
  ['activit', 'choir', 'نشاط', 'أنشطة', 'كورال']: ['activities'],
  ['public service', 'nursery', 'library', 'employment', 'خدمات عامة', 'الخدمات العامة', 'حضانة', 'مكتبة', 'توظيف']: ['services'],
  ['priest', 'father', 'كاهن', 'كهنة', 'الآباء', 'متنيح']: ['priests', 'departedPriests'],
  ['saint', 'قديس', 'شفيع', 'شفعاء']: ['saints'],
  // Separate groups: «history and milestones» needs both sections (Codex review on PR #33).
  ['history', 'تاريخ']: ['history'],
  ['milestone', 'محطات']: ['milestones'],
  ['announcement', 'notice', 'تنويه', 'إعلان']: ['alerts'],
  ['liturgy', 'mass', 'vespers', 'praise', 'season', 'قداس', 'عشية', 'تسبحة', 'موسم', 'مواسم']: ['schedule'],
  ['booking', 'contact form', 'حجز', 'نموذج المراسلة']: ['contactForm'],
  ['contact', 'location', 'direction', 'تواصل', 'العنوان']: ['contactInfo', 'contactForm'],
  ['donation', 'custom section', 'custom page', 'تبرع', 'أقسام مخصصة', 'صفحات مخصصة']: ['customSections', 'customPages'],
};

/// The section groups an allowed-topic [line] mentions: the line is kept
/// when every group has at least one section on; empty = always kept.
List<List<String>> topicSections(String line) {
  final l = line.toLowerCase();
  return [
    for (final e in topicSectionWords.entries)
      if (e.key.any(l.contains)) e.value,
  ];
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

/// The reply the model gives for a faith / church question the church data
/// does not answer (ADR-031): the app swaps it for the admin's faith reply
/// plus a search link restricted to the source domains and the contact page.
const sourceSearchToken = '[[SOURCE_SEARCH]]';

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

  /// Suggested questions, one per line. Shown only when [showSuggestions]
  /// is on; there are no built-in fallbacks.
  final String suggestionsAr, suggestionsEn;

  /// "Show suggested questions" (default off).
  final bool showSuggestions;

  /// Shown (before the search and contact links) for faith / church questions
  /// the church data does not answer — '' = [defaultFaithReplyAr] / [defaultFaithReplyEn].
  final String faithReplyAr, faithReplyEn;

  /// The only sources for faith questions outside the church data (comma or
  /// newline separated; '' = [defaultSourceDomains]).
  final String sourceDomains;

  /// "Mention unconfirmed flags" (default off): when off, the `sample` items
  /// reach the model without the [UNCONFIRMED] marker and it never adds an
  /// "unconfirmed" disclaimer; when on, it may say so once, briefly, only
  /// when asked about that specific flagged item.
  final bool mentionUnconfirmed;

  /// Stored limits (null = default); read the clamped [maxChars],
  /// [perMinute] and [perDay].
  final int? rawMaxChars, rawPerMinute, rawPerDay;

  /// Stored daily limit during an exceptional season (null = default 6);
  /// read the clamped [perDaySeason].
  final int? rawPerDaySeason;

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
    this.showSuggestions = false,
    this.faithReplyAr = '',
    this.faithReplyEn = '',
    this.sourceDomains = '',
    this.mentionUnconfirmed = false,
    this.rawMaxChars,
    this.rawPerMinute,
    this.rawPerDay,
    this.rawPerDaySeason,
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
      showSuggestions: m['showSuggestions'] == true,
      faithReplyAr: _s(m['faithReplyAr']),
      faithReplyEn: _s(m['faithReplyEn']),
      sourceDomains: _s(m['sourceDomains']),
      mentionUnconfirmed: m['mentionUnconfirmed'] == true,
      rawMaxChars: _i(m['maxChars']),
      rawPerMinute: _i(m['perMinute']),
      rawPerDay: _i(m['perDay']),
      rawPerDaySeason: _i(m['perDaySeason']),
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

  /// [effectiveTopics] without the lines whose sections are all switched
  /// off ([topicSections], ADR-042).
  List<String> topicsFor(bool Function(String section) enabled) => [
        for (final t in effectiveTopics)
          if (topicSections(t).every((group) => group.any(enabled))) t,
      ];

  String refusal(bool arabic) => arabic
      ? (refusalAr.isNotEmpty ? refusalAr : defaultRefusalAr)
      : (refusalEn.isNotEmpty ? refusalEn : defaultRefusalEn);

  /// The faith-question reply in each language (admin text or default).
  String faithReply(bool arabic) => arabic
      ? (faithReplyAr.isNotEmpty ? faithReplyAr : defaultFaithReplyAr)
      : (faithReplyEn.isNotEmpty ? faithReplyEn : defaultFaithReplyEn);

  /// Allowed source domains (validated; default st-takla.org).
  List<String> get effectiveSourceDomains =>
      parseSourceDomains(sourceDomains, fallback: const [defaultSourceDomains]);

  /// '' = the app's built-in welcome text.
  String welcome(bool arabic) => arabic ? welcomeAr : welcomeEn;

  /// The chips the page shows: none unless [showSuggestions] is on.
  List<String> visibleSuggestions(bool arabic) => showSuggestions ? suggestions(arabic) : const [];

  /// Up to three suggested questions for [arabic] (admin text only).
  List<String> suggestions(bool arabic) => [
        for (final l in (arabic ? suggestionsAr : suggestionsEn).split('\n'))
          if (l.trim().isNotEmpty) l.trim(),
      ].take(AssistantLimits.maxSuggestions).toList();

  int get maxChars => _clamp(rawMaxChars, AssistantLimits.maxCharsMin, AssistantLimits.maxCharsMax,
      AssistantLimits.maxCharsDefault);
  int get perMinute => _clamp(rawPerMinute, AssistantLimits.perMinuteMin, AssistantLimits.perMinuteMax,
      AssistantLimits.perMinuteDefault);
  int get perDay =>
      _clamp(rawPerDay, AssistantLimits.perDayMin, AssistantLimits.perDayMax, AssistantLimits.perDayDefault);

  /// Daily limit while an exceptional season is active (ADR-042, default 6).
  int get perDaySeason => _clamp(rawPerDaySeason, AssistantLimits.perDayMin, AssistantLimits.perDayMax,
      AssistantLimits.perDaySeasonDefault);

  /// The daily limit that applies now: [perDaySeason] while one of
  /// [activeSeasonKeys] is in [exceptionalSeasonKeys], else [perDay].
  int perDayFor(Iterable<String> activeSeasonKeys) =>
      activeSeasonKeys.any(exceptionalSeasonKeys.contains) ? perDaySeason : perDay;

  /// These settings with [perDay] = [perDayFor] the active seasons, so the
  /// limiter and the "daily limit reached" text both use the season limit.
  AssistantSettings withSeasonLimit(Iterable<String> activeSeasonKeys) => AssistantSettings(
        model: model,
        instructions: instructions,
        topics: topics,
        refusalAr: refusalAr,
        refusalEn: refusalEn,
        welcomeAr: welcomeAr,
        welcomeEn: welcomeEn,
        suggestionsAr: suggestionsAr,
        suggestionsEn: suggestionsEn,
        showSuggestions: showSuggestions,
        faithReplyAr: faithReplyAr,
        faithReplyEn: faithReplyEn,
        sourceDomains: sourceDomains,
        mentionUnconfirmed: mentionUnconfirmed,
        rawMaxChars: rawMaxChars,
        rawPerMinute: rawPerMinute,
        rawPerDay: perDayFor(activeSeasonKeys),
        rawPerDaySeason: rawPerDaySeason,
      );

  static int _clamp(int? v, int lo, int hi, int def) => v == null ? def : (v < lo ? lo : (v > hi ? hi : v));

  static const defaultInstructions =
      'You are the friendly information desk of the church. Be warm, polite and brief (at most about 6 lines). '
      'Use bullet points for lists and give times like 06:30 AM. '
      'Do not give medical, legal or spiritual-direction advice beyond pointing to the right clinic, meeting or priest. '
      'Do not ask for or collect personal data.';

  static const defaultTopics = 'Liturgy / mass, vespers and praise times, and holy seasons\n'
      'Sunday school and meetings\n'
      'Clinics and their times\n'
      'Activities and choirs\n'
      'Public services\n'
      'Priests and departed fathers\n'
      'Patron saints\n'
      'Church history and milestones\n'
      'Announcements\n'
      'Contact details, location and directions\n'
      'Hall bookings and the contact form\n'
      'Donations page\n'
      'The custom sections and pages of this website';

  static const defaultSourceDomains = 'st-takla.org';
  static const defaultFaithReplyAr =
      'لم أجد إجابة هذا السؤال في بيانات موقع الكنيسة. يمكنك البحث في موقع الأنبا تكلا هيمانوت أو التواصل معنا:';
  static const defaultFaithReplyEn =
      "I couldn't find this in the church's website data. You can search St-Takla.org or contact us:";

  static const defaultRefusalAr =
      'عذرًا، أنا مساعد الكنيسة وأجيب فقط عن أسئلة الكنيسة وخدماتها: مواعيد القداسات والاجتماعات والعيادات والأنشطة والآباء الكهنة والقديسين والتواصل والعنوان والحجوزات والتبرعات. كيف أساعدك في شيء من ذلك؟';
  static const defaultRefusalEn =
      "Sorry, I'm the church's assistant and can only help with questions about this church and its services: "
      'mass and meeting times, clinics, activities, priests, saints, contact, location, bookings and donations. '
      'How can I help with one of those?';
}

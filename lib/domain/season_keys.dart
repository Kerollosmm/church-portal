// Church-season keys (ADR-042 … ADR-051): the one list every reader shares —
// `seasons/{id}.key`, a liturgy's `seasonKey`, the season verses, the
// season → theme map, the season preset and the assistant's exceptional
// daily limit. firestore.rules `seasonKeyList()` mirrors [SeasonKeys.all]
// (a test checks it). Pure Dart.

class SeasonKeys {
  SeasonKeys._();

  static const holyWeek = 'holy_week';
  static const pascha = 'pascha';
  static const nativity = 'nativity';
  static const epiphany = 'epiphany';
  static const marian = 'marian';

  /// Any fast (kept for older documents and fasts without a key of their
  /// own, e.g. the Nativity fast before Kiahk, Nineveh / Jonah).
  static const fast = 'fast';
  static const revivalMaximus = 'revival_maximus';
  static const revivalMoses = 'revival_moses';
  static const summer = 'summer';

  /// ADR-051: the Apostles' fast (صوم الرسل).
  static const apostles = 'apostles';

  /// ADR-051: El-Nayrouz, the Coptic New Year, through the Feast of the
  /// Cross (1–17 Tout): one festive key, no separate `cross` key.
  static const nayrouz = 'nayrouz';

  /// ADR-051: the month of Kiahk (Kiahk praises, the end of the Nativity fast).
  static const kiahk = 'kiahk';

  /// ADR-051: Great Lent (الصوم الكبير), Preparation week included.
  static const greatLent = 'great_lent';

  /// Every key, in the admin's order (older keys first, so stored
  /// documents keep their place in the lists).
  static const all = [
    holyWeek, pascha, nativity, epiphany, marian, fast, revivalMaximus, revivalMoses, summer, //
    apostles, nayrouz, kiahk, greatLent,
  ];

  /// The fasting seasons (ADR-051): weddings are not held, so the season
  /// preset unticks wedding bookings by default; their verses fall back to
  /// the `fast` set when they have none of their own.
  static const fastFamily = [fast, greatLent, apostles, kiahk];

  static bool isFast(String key) => fastFamily.contains(key);
}

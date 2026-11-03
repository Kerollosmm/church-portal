// Contact-form categories (ADR-028): `settings/contact.categories`, slots
// c1…c12, each with a behaviour [ContactKinds]. Each slot is stored as ONE
// string (see [ContactCategory.encode]) so a full first save of 12 types
// with 8 occasions each stays within the 1,000 rule expressions of a write. Missing doc = [ContactSettings.defaults]
// (code defaults; firestore.rules mirrors them in defaultContactCats()).
// Pure Dart.

String _s(Object? v) => v is String ? v : '';
bool _b(Object? v, bool def) => v is bool ? v : def;

/// What a category does on the form and in the inbox.
class ContactKinds {
  ContactKinds._();
  static const general = 'general';

  /// Hall booking: subtype (wedding / condolence…), preferred date, phone required.
  static const booking = 'booking';
  static const complaint = 'complaint';
  static const suggestion = 'suggestion';
  static const all = [general, booking, complaint, suggestion];

  /// Kinds that may be sent anonymously (when the category allows it).
  static const anonymousCapable = [complaint, suggestion];
}

/// Inbox status values. Booking requests use the booking ones; every other
/// message keeps the original new / handled pair.
class MessageStatus {
  MessageStatus._();
  static const newMsg = 'new';
  static const handled = 'handled';
  static const contacted = 'contacted';
  static const confirmed = 'confirmed';
  static const declined = 'declined';
  static const all = [newMsg, handled, contacted, confirmed, declined];
  static const booking = [newMsg, contacted, confirmed, declined];
  static const plain = [newMsg, handled];
}

/// Category slots (one map per slot; rules validate them one by one).
const contactSlots = ['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9', 'c10', 'c11', 'c12'];
const contactMaxSubtypes = 8;
const contactLabelMax = 80, subtypeLabelMax = 60, adminNotesMax = 2000;
const _fieldSep = '\u001f', _subSep = '\u001e';

/// Separators are never part of a label.
String _clean(String s) => s.replaceAll(RegExp('[|\u001e\u001f]'), '/');
final _subKeyRe = RegExp(r'^[a-z0-9_-]{1,30}$');

/// A booking subtype (فرح / عزاء…), stored as 'key|labelAr|labelEn'.
class ContactSubtype {
  final String key, labelAr, labelEn;
  const ContactSubtype(this.key, this.labelAr, this.labelEn);

  static ContactSubtype? parse(Object? v) {
    if (v is! String) return null;
    final p = v.split('|');
    if (p.length != 3 || !_subKeyRe.hasMatch(p[0]) || p[1].trim().isEmpty) return null;
    return ContactSubtype(p[0], p[1], p[2]);
  }

  String encode() => '$key|${_clean(labelAr)}|${_clean(labelEn)}';

  @override
  bool operator ==(Object other) =>
      other is ContactSubtype && other.key == key && other.labelAr == labelAr && other.labelEn == labelEn;
  @override
  int get hashCode => Object.hash(key, labelAr, labelEn);
}

class ContactCategory {
  final String slot, labelAr, labelEn, kind;
  final bool on, anonymous;
  final int order;
  final List<ContactSubtype> subtypes;

  const ContactCategory({
    required this.slot,
    required this.labelAr,
    this.labelEn = '',
    this.kind = ContactKinds.general,
    this.on = true,
    this.anonymous = false,
    this.order = 0,
    this.subtypes = const [],
  });

  bool get isBooking => kind == ContactKinds.booking;

  /// Anonymous sending is offered (only complaint / suggestion kinds).
  bool get allowsAnonymous => anonymous && ContactKinds.anonymousCapable.contains(kind);

  /// Stored form (firestore.rules validContactCat):
  /// `kind␟on␟anon␟order␟labelAr␟labelEn␟subtypes` with on / anon as 1 / 0
  /// and the subtypes ('key|labelAr|labelEn') joined by U+001E.
  String encode() => [
        kind,
        on ? '1' : '0',
        allowsAnonymous ? '1' : '0',
        '$order',
        _clean(labelAr),
        _clean(labelEn),
        [for (final s in subtypes) s.encode()].join(_subSep),
      ].join(_fieldSep);

  /// The stored string (or, tolerantly, a map); null when unusable.
  static ContactCategory? fromStored(String slot, Object? v) {
    if (v is String) {
      final p = v.split(_fieldSep);
      if (p.length != 7) return null;
      return fromMap(slot, {
        'kind': p[0],
        'on': p[1] == '1',
        'anon': p[2] == '1',
        'order': int.tryParse(p[3]) ?? 0,
        'labelAr': p[4],
        'labelEn': p[5],
        'subtypes': p[6].isEmpty ? const <String>[] : p[6].split(_subSep),
      });
    }
    return fromMap(slot, v);
  }

  static ContactCategory? fromMap(String slot, Object? v) {
    if (v is! Map || !contactSlots.contains(slot)) return null;
    final kind = _s(v['kind']);
    final subs = v['subtypes'];
    return ContactCategory(
      slot: slot,
      labelAr: _s(v['labelAr']),
      labelEn: _s(v['labelEn']),
      kind: ContactKinds.all.contains(kind) ? kind : ContactKinds.general,
      on: _b(v['on'], true),
      anonymous: _b(v['anon'], false),
      order: v['order'] is int ? v['order'] as int : 0,
      subtypes: subs is List ? [for (final s in subs) ?ContactSubtype.parse(s)] : const [],
    );
  }

  /// Exactly the keys firestore.rules validContactCat accepts.
  Map<String, dynamic> toMap() => {
        'labelAr': labelAr,
        'labelEn': labelEn,
        'kind': kind,
        'on': on,
        'anon': allowsAnonymous,
        'order': order,
        'subtypes': [for (final s in subtypes) s.encode()],
      };

  ContactCategory copyWith({
    String? labelAr,
    String? labelEn,
    String? kind,
    bool? on,
    bool? anonymous,
    int? order,
    List<ContactSubtype>? subtypes,
  }) =>
      ContactCategory(
        slot: slot,
        labelAr: labelAr ?? this.labelAr,
        labelEn: labelEn ?? this.labelEn,
        kind: kind ?? this.kind,
        on: on ?? this.on,
        anonymous: anonymous ?? this.anonymous,
        order: order ?? this.order,
        subtypes: subtypes ?? this.subtypes,
      );

  ContactSubtype? subtype(String key) {
    for (final s in subtypes) {
      if (s.key == key) return s;
    }
    return null;
  }
}

/// `settings/contact`.
class ContactSettings {
  /// All configured slots (hidden ones included), sorted by order then slot.
  final List<ContactCategory> categories;
  const ContactSettings(this.categories);

  /// Code defaults (used while `settings/contact` does not exist). Mirrored
  /// by defaultContactCats() in firestore.rules.
  static const defaults = ContactSettings([
    ContactCategory(slot: 'c1', labelAr: 'استفسار عام', labelEn: 'General inquiry', order: 10),
    ContactCategory(
      slot: 'c2',
      labelAr: 'حجز قاعة',
      labelEn: 'Hall booking',
      kind: ContactKinds.booking,
      order: 20,
      subtypes: [ContactSubtype('wedding', 'فرح', 'Wedding'), ContactSubtype('condolence', 'عزاء', 'Condolence')],
    ),
    ContactCategory(
        slot: 'c3', labelAr: 'شكوى', labelEn: 'Complaint', kind: ContactKinds.complaint, anonymous: true, order: 30),
    ContactCategory(
        slot: 'c4', labelAr: 'اقتراح', labelEn: 'Suggestion', kind: ContactKinds.suggestion, anonymous: true, order: 40),
  ]);

  factory ContactSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null || m['categories'] is! Map) return defaults;
    final raw = m['categories'] as Map;
    final list = <ContactCategory>[
      for (final slot in contactSlots) ?ContactCategory.fromStored(slot, raw[slot]),
    ];
    return ContactSettings(sortCategories(list));
  }

  /// The visitor's choices (switched-on categories with a label).
  List<ContactCategory> get visible =>
      [for (final c in categories) if (c.on && (c.labelAr.trim().isNotEmpty || c.labelEn.trim().isNotEmpty)) c];

  ContactCategory? bySlot(String? slot) {
    for (final c in categories) {
      if (c.slot == slot) return c;
    }
    return null;
  }

  /// The next free slot (null when all 12 are used).
  String? get nextSlot {
    final used = {for (final c in categories) c.slot};
    for (final s in contactSlots) {
      if (!used.contains(s)) return s;
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'categories': {for (final c in categories) c.slot: c.encode()},
      };
}

List<ContactCategory> sortCategories(List<ContactCategory> list) {
  final out = [...list]..sort((a, b) {
      final o = a.order.compareTo(b.order);
      return o != 0 ? o : contactSlots.indexOf(a.slot).compareTo(contactSlots.indexOf(b.slot));
    });
  return out;
}

/// The inbox box a message belongs to: 'anonymous' for anonymous messages,
/// else its category slot ('c1' for legacy messages without one).
String inboxBoxOf(Map<String, dynamic> m) {
  if (m['anonymous'] == true) return 'anonymous';
  final c = m['category'];
  return c is String && c.isNotEmpty ? c : 'c1';
}

/// Whether a message counts as still open (new) in the inbox.
bool messageIsOpen(Map<String, dynamic> m) => (m['status'] ?? MessageStatus.newMsg) == MessageStatus.newMsg;

/// A fresh subtype key for a row the admin adds (unique within [taken]).
String newSubtypeKey(Iterable<String> taken) {
  final t = taken.toSet();
  for (var i = 1;; i++) {
    final k = 'type$i';
    if (!t.contains(k)) return k;
  }
}

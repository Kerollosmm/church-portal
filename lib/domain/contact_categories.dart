import 'dart:math';

// Contact-form categories (ADR-028): `settings/contact.categories`, keyed by
// a stable id that is never reused (PR #19: the defaults keep c1…c4, every
// added category gets a fresh random id — [newContactCategoryId]), at most
// [contactMaxCategories], each with a behaviour [ContactKinds]. Each slot is stored as ONE
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

/// The ids of the original slots (the code defaults use c1…c4; messages
/// sent before PR #19 may name any of them).
const contactSlots = ['c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9', 'c10', 'c11', 'c12'];

/// At most this many categories (firestore.rules validContactSettings).
const contactMaxCategories = 12;

/// A category id: 'c' + 1…15 lower-case letters / digits (firestore.rules
/// contactIdOk). Covers the legacy slots and the random ids.
final contactIdRe = RegExp(r'^c[0-9a-z]{1,15}$');
bool isContactId(Object? v) => v is String && contactIdRe.hasMatch(v);

const _idChars = 'abcdefghijklmnopqrstuvwxyz0123456789';

/// A fresh, stable id for a category an admin adds: 'c' + 10 random
/// letters / digits, never one of [taken] and never a legacy slot id
/// (`c` + digits only), so a deleted category's id — and with it the label
/// of its old messages — is never handed to a new one.
String newContactCategoryId(Iterable<String> taken, {Random? random}) {
  final r = random ?? Random.secure();
  final t = taken.toSet();
  while (true) {
    final id = 'c${List.generate(10, (_) => _idChars[r.nextInt(_idChars.length)]).join()}';
    if (!t.contains(id) && !RegExp(r'^c[0-9]+$').hasMatch(id)) return id;
  }
}
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
    if (v is! Map || !isContactId(slot)) return null;
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
      for (final e in raw.entries)
        if (e.key is String) ?ContactCategory.fromStored(e.key as String, e.value),
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

  /// A fresh id for a new category (null when [contactMaxCategories] are
  /// used). [retired] = ids that must never come back (e.g. categories
  /// deleted in the editor before saving); random ids make a clash with
  /// any earlier id practically impossible anyway.
  String? newId({Iterable<String> retired = const [], Random? random}) {
    if (categories.length >= contactMaxCategories) return null;
    return newContactCategoryId([for (final c in categories) c.slot, ...retired], random: random);
  }

  Map<String, dynamic> toMap() => {
        'categories': {for (final c in categories) c.slot: c.encode()},
      };
}

List<ContactCategory> sortCategories(List<ContactCategory> list) {
  final out = [...list]..sort((a, b) {
      final o = a.order.compareTo(b.order);
      return o != 0 ? o : _slotRank(a.slot).compareTo(_slotRank(b.slot));
    });
  return out;
}

/// Legacy slots in their numeric order, then other ids alphabetically.
String _slotRank(String id) {
  final i = contactSlots.indexOf(id);
  return i >= 0 ? '0${i.toString().padLeft(2, '0')}' : '1$id';
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

import 'cairo_time.dart';
import 'models.dart';

// ---------------------------------------------------------------- Alerts

bool isAlertVisible(Alert a, DateTime now) {
  if (!a.active) return false;
  if (a.startsAt != null && now.isBefore(a.startsAt!)) return false;
  if (a.endsAt != null && now.isAfter(a.endsAt!)) return false;
  return true;
}

/// Alerts to show in the urgent banner: active, within window, highest
/// priority first (ties: the one that started most recently first).
List<Alert> visibleAlerts(Iterable<Alert> alerts, DateTime now) {
  final list = alerts.where((a) => isAlertVisible(a, now)).toList();
  list.sort((a, b) {
    final p = b.priority.compareTo(a.priority);
    if (p != 0) return p;
    return (b.startsAt ?? DateTime(1970)).compareTo(a.startsAt ?? DateTime(1970));
  });
  return list;
}

// ---------------------------------------------------------------- Clinics

/// ISO weekday (1=Mon..7=Sun) of [now] in Cairo.
int cairoWeekday(DateTime now) => CairoTime.fromInstant(now).weekday;

bool isClinicAvailableToday(Clinic c, DateTime now) => c.active && c.days.contains(cairoWeekday(now));

/// Active clinics filtered by [specialty] (null/empty = all). Clinics open
/// today come first, then by specialty and doctor name.
List<Clinic> filterClinics(Iterable<Clinic> clinics, {String? specialty, required DateTime now}) {
  final wd = cairoWeekday(now);
  final list = clinics
      .where((c) => c.active && (specialty == null || specialty.isEmpty || c.specialty == specialty))
      .toList();
  list.sort((a, b) {
    final ta = a.days.contains(wd) ? 0 : 1;
    final tb = b.days.contains(wd) ? 0 : 1;
    if (ta != tb) return ta.compareTo(tb);
    final s = a.specialty.compareTo(b.specialty);
    return s != 0 ? s : a.doctorName.compareTo(b.doctorName);
  });
  return list;
}

/// Distinct specialties (key -> [ar, en]) in first-seen order.
Map<String, List<String>> clinicSpecialties(Iterable<Clinic> clinics) {
  final map = <String, List<String>>{};
  for (final c in clinics.where((c) => c.active)) {
    map.putIfAbsent(c.specialty, () => [c.specialtyAr, c.specialtyEn]);
  }
  return map;
}

// ---------------------------------------------------------------- Digits & phone

const _arabicIndic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
const _persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

/// Converts Arabic-Indic / Persian digits to ASCII digits.
String normalizeDigits(String input) {
  var s = input;
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(_arabicIndic[i], '$i').replaceAll(_persian[i], '$i');
  }
  return s;
}

/// Converts ASCII digits to Arabic-Indic digits.
String toArabicDigits(String input) => input.replaceAllMapped(RegExp(r'\d'), (m) => _arabicIndic[int.parse(m[0]!)]);

/// Normalises an Egyptian phone to the local form (e.g. 01012345678 /
/// 035551234). Returns null when it is not a valid Egyptian number.
String? normalizeEgyptianPhone(String raw) {
  var s = normalizeDigits(raw).replaceAll(RegExp(r'[\s\-().]'), '');
  if (s.startsWith('+20')) {
    s = '0${s.substring(3)}';
  } else if (s.startsWith('0020')) {
    s = '0${s.substring(4)}';
  } else if (s.startsWith('20') && s.length >= 10 && s.length <= 12) {
    // Bare country code without '+': 20 + mobile (12) / Cairo landline (11) /
    // Alexandria & other landlines (10-11).
    s = '0${s.substring(2)}';
  }
  if (RegExp(r'^01[0125]\d{8}$').hasMatch(s)) return s; // mobile
  if (RegExp(r'^02\d{8}$').hasMatch(s)) return s; // Cairo landline
  if (RegExp(r'^03\d{7}$').hasMatch(s)) return s; // Alexandria landline
  if (RegExp(r'^0[4-9]\d{7,8}$').hasMatch(s)) return s; // other governorates
  if (RegExp(r'^1\d{4}$').hasMatch(s)) return s; // 5-digit hotlines
  return null;
}

bool isValidEgyptianPhone(String raw) => normalizeEgyptianPhone(raw) != null;

/// True for Egyptian mobile numbers (the only ones that can have WhatsApp).
bool isEgyptianMobile(String raw) {
  final n = normalizeEgyptianPhone(raw);
  return n != null && RegExp(r'^01[0125]\d{8}$').hasMatch(n);
}

/// International digits for wa.me / tel links (Egypt default +20).
String toInternationalDigits(String raw) {
  var s = normalizeDigits(raw).replaceAll(RegExp(r'[^\d+]'), '');
  if (s.startsWith('+')) return s.substring(1);
  if (s.startsWith('00')) return s.substring(2);
  if (s.startsWith('0')) return '20${s.substring(1)}';
  return s;
}

String whatsappLink(String raw, {String? text}) {
  final base = 'https://wa.me/${toInternationalDigits(raw)}';
  if (text == null || text.isEmpty) return base;
  return '$base?text=${Uri.encodeComponent(text)}';
}

String telLink(String raw) {
  final s = normalizeDigits(raw).replaceAll(RegExp(r'[^\d+]'), '');
  return 'tel:$s';
}

// ---------------------------------------------------------------- Contact form

final _emailRe = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$");

bool isValidEmail(String s) => s.length <= 254 && _emailRe.hasMatch(s.trim());

enum ContactField { name, phone, email, contact, message }

/// Error codes (localised by the UI).
enum ContactError { nameLength, phoneInvalid, emailInvalid, phoneOrEmailRequired, messageLength }

class ContactFormInput {
  final String name, phone, email, message;
  const ContactFormInput({required this.name, this.phone = '', this.email = '', required this.message});
}

class ContactValidation {
  final Map<ContactField, ContactError> errors;
  final Map<String, dynamic>? payload;
  const ContactValidation(this.errors, this.payload);
  bool get isValid => errors.isEmpty;
}

const contactNameMin = 2, contactNameMax = 80, contactMessageMin = 5, contactMessageMax = 1000;

/// Validates the contact form. On success returns the sanitised payload
/// (without createdAt/status, which the data layer adds) matching the
/// Firestore rule in firestore.rules.
ContactValidation validateContactForm(ContactFormInput input) {
  final errors = <ContactField, ContactError>{};
  final name = input.name.trim().replaceAll(RegExp(r'\s+'), ' ');
  final phoneRaw = input.phone.trim();
  final email = input.email.trim();
  final message = input.message.trim();

  if (name.length < contactNameMin || name.length > contactNameMax) {
    errors[ContactField.name] = ContactError.nameLength;
  }
  String? phone;
  if (phoneRaw.isNotEmpty) {
    phone = normalizeEgyptianPhone(phoneRaw);
    if (phone == null) errors[ContactField.phone] = ContactError.phoneInvalid;
  }
  if (email.isNotEmpty && !isValidEmail(email)) {
    errors[ContactField.email] = ContactError.emailInvalid;
  }
  if (phoneRaw.isEmpty && email.isEmpty) {
    errors[ContactField.contact] = ContactError.phoneOrEmailRequired;
  }
  if (message.length < contactMessageMin || message.length > contactMessageMax) {
    errors[ContactField.message] = ContactError.messageLength;
  }
  if (errors.isNotEmpty) return ContactValidation(errors, null);
  return ContactValidation(const {}, {
    'name': name,
    'phone': phone ?? '',
    'email': email,
    'message': message,
  });
}

/// Client-side rate limiter: at most [maxPerWindow] submissions per
/// [window] and at least [minInterval] between two submissions.
class ContactRateLimiter {
  final Duration minInterval;
  final Duration window;
  final int maxPerWindow;
  final List<DateTime> _sent = [];
  ContactRateLimiter({
    this.minInterval = const Duration(seconds: 60),
    this.window = const Duration(hours: 1),
    this.maxPerWindow = 3,
  });

  /// Remaining wait before the next submission is allowed (zero = allowed).
  Duration waitTime(DateTime now) {
    _sent.removeWhere((t) => now.difference(t) >= window);
    var wait = Duration.zero;
    if (_sent.isNotEmpty) {
      final sinceLast = now.difference(_sent.last);
      if (sinceLast < minInterval) wait = minInterval - sinceLast;
    }
    if (_sent.length >= maxPerWindow) {
      final w = window - now.difference(_sent.first);
      if (w > wait) wait = w;
    }
    return wait;
  }

  bool canSubmit(DateTime now) => waitTime(now) == Duration.zero;
  void recordSubmission(DateTime now) => _sent.add(now);
}

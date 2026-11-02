// Public item detail pages (ADR-020, PR #13). Pure Dart: routes, parent
// sections and the gating rules of `ItemDetailPage`, unit-tested.

import 'cairo_time.dart';
import 'features.dart';
import 'models.dart';

/// The 7 collections whose items can have a public detail page.
enum DetailKind { meeting, activity, clinic, facility, priest, saint, milestone }

extension DetailKindX on DetailKind {
  /// Route prefix of the item's detail page (`<basePath>/<id>`).
  String get basePath => switch (this) {
        DetailKind.meeting => '/church-education',
        DetailKind.activity => '/church-activities',
        DetailKind.clinic => '/clinics',
        DetailKind.facility => '/public-services',
        DetailKind.priest => '/about/priests',
        DetailKind.saint => '/about/saints',
        DetailKind.milestone => '/about/milestones',
      };

  /// Public page listing the item (where "Back" goes). Milestones are listed
  /// on Home ("Our story"), not on /about.
  String get parentPath => switch (this) {
        DetailKind.priest || DetailKind.saint => '/about',
        DetailKind.milestone => '/',
        _ => basePath,
      };

  /// Firestore collection holding the items.
  String get collection => switch (this) {
        DetailKind.meeting => 'meetings',
        DetailKind.activity => 'activities',
        DetailKind.clinic => 'clinics',
        DetailKind.facility => 'facilities',
        DetailKind.priest => 'priests',
        DetailKind.saint => 'saints',
        DetailKind.milestone => 'milestones',
      };
}

/// Detail kind of a Firestore [collection], or null when it has no detail pages.
DetailKind? detailKindForCollection(String collection) {
  for (final k in DetailKind.values) {
    if (k.collection == collection) return k;
  }
  return null;
}

/// Shareable path of an item's detail page (the id is URL-encoded).
String detailPathFor(DetailKind kind, String id) => '${kind.basePath}/${Uri.encodeComponent(id)}';

/// The detail kind and item id behind [location], or null when it is not a
/// detail route. Trailing `/`, query and fragment are ignored.
(DetailKind, String)? parseDetailPath(String location) {
  var p = location;
  final cut = p.indexOf(RegExp('[?#]'));
  if (cut >= 0) p = p.substring(0, cut);
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  for (final k in DetailKind.values) {
    final prefix = '${k.basePath}/';
    if (!p.startsWith(prefix)) continue;
    final rest = p.substring(prefix.length);
    if (rest.isEmpty || rest.contains('/')) continue;
    String id;
    try {
      id = Uri.decodeComponent(rest);
    } catch (_) {
      id = rest; // malformed %-escape in a hand-typed URL: keep it raw, never throw
    }
    return (k, id);
  }
  return null;
}

/// What a detail page shows.
enum DetailState {
  /// The item, with its details.
  available,

  /// "Not available": no such item, hidden by an admin, or its detail page
  /// is switched off (an explicit `detailsEnabled: false`; a missing field
  /// means on, PR #14). Not indexable.
  unavailable,

  /// The section the item belongs to is off (a departed father while
  /// `departedPriests` is off, or a serving one while `priests` is off).
  sectionOff,
}

/// Gating of a detail page (plan PR #13, Task 3.2). [details] null = item not
/// found. [priestDeparted] is set for priests only: their page needs the
/// section matching their status, not just "any priests section" (which is
/// all the route itself checks).
DetailState detailStateFor(
  ItemDetails? details, {
  required FeatureSettings features,
  bool visible = true,
  bool? priestDeparted,
}) {
  if (details == null || !visible || !details.detailsEnabled) return DetailState.unavailable;
  if (priestDeparted != null) {
    final allowed =
        priestDeparted ? features.enabled(Sections.departedPriests) : features.enabled(Sections.priests);
    if (!allowed) return DetailState.sectionOff;
  }
  return DetailState.available;
}

/// Whether an item's social / external links are shown (its own switch and
/// the site-wide `socials` section).
bool itemSocialsShown(ItemDetails d, FeatureSettings f) => d.showSocials && f.enabled(Sections.socials);

/// Absolute, shareable URL of an item's detail page on [origin]
/// (`?lang=en` when shared from the English site).
String absoluteDetailUrl(String origin, DetailKind kind, String id, {bool english = false}) =>
    '$origin${detailPathFor(kind, id)}${english ? '?lang=en' : ''}';

const _rruleDays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

String _calStamp(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}${two(d.month)}${two(d.day)}T${two(d.hour)}${two(d.minute)}00';
}

/// Google Calendar "add event" link for an item that repeats every week on
/// ISO [weekdays] (1 = Monday … 7 = Sunday) from [start] to [end] ("HH:mm",
/// Cairo wall time). The first event is the next occurrence after [now]
/// (later today counts); a missing / invalid [end] means one hour, an [end]
/// before [start] rolls to the next day. Null when there is no usable day or
/// start time. Times are sent as Cairo local time with `ctz=Africa/Cairo`, so
/// the visitor's calendar converts them correctly wherever they are.
String? weeklyCalendarUrl({
  required String title,
  required List<int> weekdays,
  required String start,
  String end = '',
  String details = '',
  String location = '',
  required DateTime now,
}) {
  final days = weekdays.where((d) => d >= 1 && d <= 7).toSet().toList()..sort();
  final startMin = parseHm(start);
  if (days.isEmpty || startMin == null) return null;
  var endMin = parseHm(end) ?? startMin + 60;
  if (endMin <= startMin) endMin += 24 * 60;
  final c = CairoTime.fromInstant(now);
  final nowMin = c.hour * 60 + c.minute;
  var offset = 0;
  while (offset < 8) {
    final day = CairoTime.at(c.year, c.month, c.day + offset);
    if (days.contains(day.weekday) && (offset > 0 || startMin > nowMin)) break;
    offset++;
  }
  final from = CairoTime.at(c.year, c.month, c.day + offset, startMin);
  final to = CairoTime.at(c.year, c.month, c.day + offset, endMin);
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': '${_calStamp(from)}/${_calStamp(to)}',
    'ctz': 'Africa/Cairo',
    'recur': 'RRULE:FREQ=WEEKLY;BYDAY=${days.map((d) => _rruleDays[d - 1]).join(',')}',
    if (details.isNotEmpty) 'details': details,
    if (location.isNotEmpty) 'location': location,
  }).toString();
}

/// Up to [max] other items from [items] for a "More in this section" list:
/// [self] excluded, items in the same group ([sameGroup]) first, list order
/// kept otherwise.
List<T> pickRelated<T>(List<T> items, T self, {bool Function(T)? sameGroup, int max = 3}) {
  final others = [for (final i in items) if (i != self) i];
  final g = sameGroup;
  final ordered = g == null ? others : [...others.where(g), ...others.where((i) => !g(i))];
  return ordered.take(max).toList();
}

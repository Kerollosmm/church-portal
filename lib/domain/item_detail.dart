// Public item detail pages (ADR-020, PR #13). Pure Dart: routes, parent
// sections and the gating rules of `ItemDetailPage`, unit-tested.

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
    return (k, Uri.decodeComponent(rest));
  }
  return null;
}

/// What a detail page shows.
enum DetailState {
  /// The item, with its details.
  available,

  /// "Not available": no such item, hidden by an admin, or its detail page
  /// is switched off (`detailsEnabled` false). Not indexable.
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

import 'package:church_portal/data/content_repository.dart';
import 'package:church_portal/data/seed_data.dart';
import 'package:church_portal/domain/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Milestone ms(String id, int? year, {int order = 0}) => Milestone(
        id: id,
        titleAr: id,
        titleEn: id,
        year: year,
        order: order,
      );

  group('compareMilestonesByYear', () {
    test('sorts ascending by year, nulls last, ties broken stably by order', () {
      final list = [
        ms('y2025', 2025, order: 1),
        ms('y1980', 1980, order: 4),
        ms('y2022b', 2022, order: 3),
        ms('y2022a', 2022, order: 2),
        ms('null1', null, order: 0),
        ms('null2', null, order: 5),
      ]..sort(compareMilestonesByYear);

      expect(
        list.map((m) => m.id).toList(),
        ['y1980', 'y2022a', 'y2022b', 'y2025', 'null1', 'null2'],
      );
    });
  });

  group('SeedRepository.milestones()', () {
    test('returns milestones sorted by year with nulls last and order tie-breaker', () async {
      final seed = SeedData({
        'milestones': {
          'a': {'titleAr': '2025', 'titleEn': '2025', 'year': 2025, 'order': 1},
          'b': {'titleAr': 'null', 'titleEn': 'null', 'order': 0},
          'c': {'titleAr': '2022-3', 'titleEn': '2022-3', 'year': 2022, 'order': 3},
          'd': {'titleAr': '1980', 'titleEn': '1980', 'year': 1980, 'order': 9},
          'e': {'titleAr': '2022-2', 'titleEn': '2022-2', 'year': 2022, 'order': 2},
        },
      });
      final repo = SeedRepository(seed);
      final sorted = await repo.milestones().first;
      expect(sorted.map((m) => m.id).toList(), ['d', 'e', 'c', 'a', 'b']);
    });
  });
}

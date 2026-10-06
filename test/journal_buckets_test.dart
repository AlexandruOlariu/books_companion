import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/history/domain/journal_buckets.dart';
import 'package:reading_library/features/library/domain/models.dart';

Completion done(String id, DatePrecision p, String? value) => Completion(
  id: id,
  userBookId: id,
  finish: PartialDate(p, value),
  source: 'entered_past',
);

void main() {
  final all = [
    done('a', DatePrecision.day, '2024-06-30'),
    done('b', DatePrecision.day, '2024-06-02'),
    done('c', DatePrecision.month, '2024-06'),
    done('d', DatePrecision.year, '2024'),
    done('e', DatePrecision.year, '2023'),
    done('f', DatePrecision.month, '2023-12'),
    done('g', DatePrecision.unknown, null),
  ];

  test('months hold only finishes whose month is remembered, in order', () {
    final months = JournalBuckets.months(all, 2024);
    expect(months, hasLength(12));
    // Known days in order, then the one remembered only as "June".
    expect(months[5].map((c) => c.id), ['b', 'a', 'c']);
    expect(months.expand((m) => m).map((c) => c.id), isNot(contains('d')));
    expect(months[11], isEmpty);
    expect(JournalBuckets.months(all, 2023)[11].single.id, 'f');
  });

  test('a year-only finish is never placed in a month', () {
    expect(JournalBuckets.yearOnly(all, 2024).single.id, 'd');
    expect(JournalBuckets.yearOnly(all, 2023).single.id, 'e');
    expect(JournalBuckets.yearOnly(all, 2022), isEmpty);
    for (var m = 0; m < 12; m++) {
      expect(
        JournalBuckets.months(all, 2023)[m].map((c) => c.id),
        isNot(contains('e')),
      );
    }
  });

  test('years list every dated year newest first; unknown is separate', () {
    final years = JournalBuckets.years(all);
    expect(years.map((y) => y.$1), [2024, 2023]);
    expect(
      years.first.$2.map((c) => c.id),
      unorderedEquals(['a', 'b', 'c', 'd']),
    );
    expect(JournalBuckets.undated(all).single.id, 'g');
  });

  test('every finish is counted exactly once across the buckets', () {
    var seen = 0;
    for (final (y, _) in JournalBuckets.years(all)) {
      seen += JournalBuckets.months(all, y).expand((m) => m).length;
      seen += JournalBuckets.yearOnly(all, y).length;
    }
    seen += JournalBuckets.undated(all).length;
    expect(seen, all.length);
  });
}

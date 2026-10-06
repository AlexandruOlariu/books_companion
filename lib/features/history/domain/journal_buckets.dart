import '../../library/domain/models.dart';

/// Groups remembered finishes for the Journal without inventing precision: a
/// book appears under a month only if the reader remembers the month.
class JournalBuckets {
  /// The twelve months of [year], in order. A finish belongs to a month when
  /// its precision is `month` or `day`; within a month, books with a known day
  /// come first in day order, then those remembered only as the month.
  static List<List<Completion>> months(List<Completion> all, int year) {
    final byMonth = List.generate(12, (_) => <Completion>[]);
    for (final c in all) {
      final m = c.finish.month;
      if (c.finish.year == year && m != null) byMonth[m - 1].add(c);
    }
    for (final list in byMonth) {
      String key(Completion c) => c.finish.precision == DatePrecision.day
          ? c.finish.value!
          : '${c.finish.value}-99';
      list.sort((a, b) => key(a).compareTo(key(b)));
    }
    return byMonth;
  }

  /// Finishes remembered only as a year, kept apart from the months.
  static List<Completion> yearOnly(List<Completion> all, int year) => [
    for (final c in all)
      if (c.finish.precision == DatePrecision.year && c.finish.year == year) c,
  ];

  /// Years that have at least one finish, newest first, with their finishes.
  static List<(int, List<Completion>)> years(List<Completion> all) {
    final byYear = <int, List<Completion>>{};
    for (final c in all) {
      final y = c.finish.year;
      if (y != null) (byYear[y] ??= []).add(c);
    }
    return [
      for (final y in byYear.keys.toList()..sort((a, b) => b - a))
        (y, byYear[y]!),
    ];
  }

  /// Finishes the reader knows happened but cannot date at all.
  static List<Completion> undated(List<Completion> all) => [
    for (final c in all)
      if (c.finish.year == null) c,
  ];
}

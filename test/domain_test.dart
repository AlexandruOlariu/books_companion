import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/library/domain/models.dart';

void main() {
  test('partial dates preserve only information the reader knows', () {
    final year = PartialDate(DatePrecision.year, '2019');
    expect(year.value, '2019');
    expect(year.month, isNull);
    final month = PartialDate(DatePrecision.month, '2024-02');
    expect(month.value, '2024-02');
    expect(month.month, 2);
    expect(const PartialDate.unknown().year, isNull);
    expect(
      () => PartialDate(DatePrecision.year, '2019-01-01'),
      throwsFormatException,
    );
    expect(
      () => PartialDate(DatePrecision.unknown, '2019'),
      throwsFormatException,
    );
    expect(
      () => PartialDate(DatePrecision.day, '2023-02-29'),
      throwsFormatException,
    );
    expect(() => PartialDate(DatePrecision.day, '2024-02-29'), returnsNormally);
    expect(
      () => PartialDate(DatePrecision.month, '2024-13'),
      throwsFormatException,
    );
  });
  test('retroactive completion counts never become activity', () {
    final data = LibrarySnapshot(
      completions: [
        Completion(
          id: '1',
          userBookId: 'a',
          finish: PartialDate(DatePrecision.year, '2019'),
          source: 'entered_past',
        ),
        const Completion(
          id: '2',
          userBookId: 'b',
          finish: PartialDate.unknown(),
          source: 'entered_past',
        ),
      ],
    );
    expect(data.finishesIn(null), hasLength(2));
    expect(data.finishesIn(2019), hasLength(1));
    expect(data.finishesIn(2026), isEmpty);
    expect(data.pagesLogged(null), 0);
    expect(data.secondsLogged(null), 0);
  });
  test('sessions require coherent page ranges or known time', () {
    expect(() => validateSession(10, 30, null, 100), returnsNormally);
    expect(() => validateSession(null, null, 600, null), returnsNormally);
    expect(() => validateSession(30, 10, 600, 100), throwsFormatException);
    expect(() => validateSession(10, null, 600, 100), throwsFormatException);
    expect(() => validateSession(10, 101, null, 100), throwsFormatException);
    expect(
      () => validateSession(null, null, null, null),
      throwsFormatException,
    );
    expect(() => validatePage(-1, null), throwsFormatException);
  });
}

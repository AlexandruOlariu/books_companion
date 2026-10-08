import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/library/domain/library_title.dart';

void main() {
  test('a first name makes the library theirs', () {
    expect(libraryTitle('Alex'), 'Alex’s Library');
    expect(libraryTitle('  Ana '), 'Ana’s Library');
  });

  test('without a name the title stays generic', () {
    expect(libraryTitle(null), 'My Library');
    expect(libraryTitle(''), 'My Library');
    expect(libraryTitle('   '), 'My Library');
  });
}

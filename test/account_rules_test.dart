import 'package:flutter_test/flutter_test.dart';
import 'package:reading_library/features/friends/domain/account_rules.dart';

void main() {
  group('names', () {
    test('a name is needed and has a limit', () {
      expect(checkName('Ana', 'First name'), isNull);
      expect(checkName('  ', 'First name'), 'First name cannot be empty.');
      expect(checkName('a' * 60, 'Last name'), isNull);
      expect(checkName('a' * 61, 'Last name'), contains('at most 60'));
    });
  });

  group('username', () {
    test('3 to 30 letters, digits, underscore or dot', () {
      expect(checkUsername('ana'), isNull);
      expect(checkUsername('ana.pop_9'), isNull);
      expect(checkUsername('ab'), isNotNull);
      expect(checkUsername('a' * 31), isNotNull);
      expect(checkUsername('ana pop'), isNotNull);
      expect(checkUsername('ană'), isNotNull);
    });
    test(
      'capitals and spaces around it are fine: the server lower-cases it',
      () {
        expect(checkUsername('  Ana '), isNull);
      },
    );
  });

  group('new password', () {
    test('needs 10 characters and a matching repeat', () {
      expect(
        checkNewPassword('long enough!', confirmation: 'long enough!'),
        isNull,
      );
      expect(
        checkNewPassword('short', confirmation: 'short'),
        contains('at least 10'),
      );
      expect(
        checkNewPassword('long enough!', confirmation: 'long enough?'),
        contains('not the same'),
      );
      expect(
        checkNewPassword('a' * 129, confirmation: 'a' * 129),
        contains('at most 128'),
      );
    });
  });
}

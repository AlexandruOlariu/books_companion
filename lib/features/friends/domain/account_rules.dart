// Checks for the account details the reader can change, in plain Dart so they
// can be tested. They mirror the server's limits (docs/backend.md); the server
// still has the last word. Each returns a message to show, or null when fine.

const maxNameLength = 60;
const minPasswordLength = 10;
const maxPasswordLength = 128;

final _usernamePattern = RegExp(r'^[a-z0-9_.]{3,30}$');

String? checkName(String value, String label) {
  final name = value.trim();
  if (name.isEmpty) return '$label cannot be empty.';
  if (name.length > maxNameLength) {
    return '$label can have at most $maxNameLength characters.';
  }
  return null;
}

/// The server lower-cases usernames, so capitals typed here are fine.
String? checkUsername(String value) =>
    _usernamePattern.hasMatch(value.trim().toLowerCase())
    ? null
    : 'Username: 3 to 30 letters, digits, "_" or ".".';

String? checkNewPassword(String value, {required String confirmation}) {
  if (value.length < minPasswordLength) {
    return 'The new password needs at least $minPasswordLength characters.';
  }
  if (value.length > maxPasswordLength) {
    return 'The new password can have at most $maxPasswordLength characters.';
  }
  if (value != confirmation) return 'The two new passwords are not the same.';
  return null;
}

/// The heading of the Library tab: "Alex’s Library" for a signed-in reader,
/// "My Library" when there is no account or no first name to show.
String libraryTitle(String? firstName) {
  final name = firstName?.trim() ?? '';
  return name.isEmpty ? 'My Library' : '$name’s Library';
}

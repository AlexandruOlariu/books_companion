import 'package:flutter_contacts/flutter_contacts.dart';

/// The phone numbers in the reader's address book, or nothing if they said no.
class ContactNumbers {
  final bool granted;
  final List<String> numbers;
  const ContactNumbers({required this.granted, this.numbers = const []});
}

abstract class ContactsSource {
  /// Asks for permission (only now, when the reader chose to find friends) and
  /// returns the distinct phone numbers. Names, emails, and photos are never
  /// read.
  Future<ContactNumbers> readNumbers();
}

class DeviceContactsSource implements ContactsSource {
  @override
  Future<ContactNumbers> readNumbers() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    if (status != PermissionStatus.granted &&
        status != PermissionStatus.limited) {
      return const ContactNumbers(granted: false);
    }
    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.phone},
    );
    final numbers = <String>{
      for (final contact in contacts)
        for (final phone in contact.phones)
          if (phone.number.trim().isNotEmpty) phone.number.trim(),
    };
    return ContactNumbers(granted: true, numbers: numbers.toList());
  }
}

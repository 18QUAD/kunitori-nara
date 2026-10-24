import 'package:flutter_test/flutter_test.dart';
import 'package:kunitori/attack_contacts.dart';

void main() {
  test('a new primary touch recovers missing release and cancellation', () {
    final contacts = AttackContacts();
    expect(contacts.begin(1, 'touch', primary: true), isTrue);
    // Neither release nor cancel arrives for pointer 1.
    expect(contacts.begin(7, 'touch', primary: true), isTrue);
    expect(contacts.length, 1);
    contacts.end(7);
    expect(contacts.length, 0);
    expect(contacts.begin(7, 'touch', primary: true), isTrue);
    // Pointer IDs may be reused for later contact sequences.
    expect(contacts.begin(7, 'touch', primary: true), isTrue);
  });

  test('overlapping and alternating fingers remain one group', () {
    final contacts = AttackContacts();
    expect(contacts.begin(1, 'touch', primary: true), isTrue);
    expect(contacts.begin(2, 'touch', primary: false), isFalse);
    contacts.end(1);
    // A new finger is non-primary until every touch has left the surface.
    expect(contacts.begin(3, 'touch', primary: false), isFalse);
    contacts.end(2);
    expect(contacts.begin(4, 'touch', primary: false), isFalse);
    contacts.end(3);
    contacts.end(4);
    expect(contacts.begin(5, 'touch', primary: true), isTrue);
  });

  test('primary recovery preserves held contacts of other pointer types', () {
    final contacts = AttackContacts();
    expect(contacts.begin(1, 'mouse', primary: true), isTrue);
    expect(contacts.begin(2, 'touch', primary: true), isFalse);
    expect(contacts.begin(3, 'touch', primary: true), isFalse);
    contacts.end(1);
    expect(contacts.begin(4, 'touch', primary: false), isFalse);
    contacts.end(3);
    contacts.end(4);
    expect(contacts.begin(5, 'mouse', primary: true), isTrue);
    contacts.clear();
    expect(contacts.length, 0);
  });
  test(
    'a primary sequence starting outside the button permits its secondary contact',
    () {
      final contacts = AttackContacts();
      expect(contacts.begin(1, 'touch', primary: true), isTrue);
      // Lost release, then the next primary contact begins elsewhere in the page.
      contacts.startSequence('touch');
      expect(contacts.begin(3, 'touch', primary: false), isTrue);
      expect(contacts.begin(4, 'touch', primary: false), isFalse);
      contacts.end(3);
      contacts.end(4);
      expect(contacts.length, 0);
    },
  );
}

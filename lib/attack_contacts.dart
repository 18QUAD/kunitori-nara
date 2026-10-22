/// Counts a contact group once, until every contact has ended.
///
/// A primary pointerdown begins a new contact sequence for that pointer type.
/// It is independent evidence that an earlier sequence ended, even if its
/// pointerup/pointercancel was lost (for example while a button was disabled).
class AttackContacts {
  final Map<int, String> _active = {};

  int get length => _active.length;

  bool begin(int pointer, String type, {required bool primary}) {
    if (primary) _active.removeWhere((_, value) => value == type);
    final first = _active.isEmpty;
    final added = !_active.containsKey(pointer);
    _active[pointer] = type;
    return first && added;
  }

  bool end(int pointer) => _active.remove(pointer) != null;
  void clear() => _active.clear();
}

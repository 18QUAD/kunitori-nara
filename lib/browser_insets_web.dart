import 'dart:js_interop';
import 'package:flutter/widgets.dart';

@JS('kunitoriViewport.top')
external JSNumber _topInset();
@JS('kunitoriViewport.bottom')
external JSNumber _bottomInset();
@JS('window.addEventListener')
external void _listen(String name, JSFunction listener);

final browserInsets = _createBrowserInsets();
ValueNotifier<EdgeInsets> _createBrowserInsets() {
  EdgeInsets read() => EdgeInsets.only(
    top: _topInset().toDartDouble,
    bottom: _bottomInset().toDartDouble,
  );
  final notifier = ValueNotifier(read());
  _listen(
    'kunitori-viewport',
    ((JSAny? event) {
      notifier.value = read();
    }).toJS,
  );
  return notifier;
}

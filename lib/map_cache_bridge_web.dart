import 'dart:js_interop';

@JS('window.kunitoriMapMemory.get')
external JSPromise<JSNumber> _get();
@JS('window.kunitoriMapMemory.set')
external JSPromise<JSNumber> _set(JSNumber value);

Future<int> readMapCacheMegabytes() async => (await _get().toDart).toDartInt;
Future<void> saveMapCacheMegabytes(int value) async {
  await _set(value.toJS).toDart;
}

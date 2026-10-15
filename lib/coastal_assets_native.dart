import 'package:flutter/services.dart';

Future<String> loadCoastalAsset(String key) =>
    rootBundle.loadString(key, cache: false);

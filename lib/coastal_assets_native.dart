import 'package:flutter/services.dart';

Future<String> loadCoastalAsset(String key, {String version = '20261015-v1'}) =>
    rootBundle.loadString(key, cache: false);

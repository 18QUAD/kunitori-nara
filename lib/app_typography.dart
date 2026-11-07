import 'package:flutter/foundation.dart';

// The source variable font has a default wght of 100. Native platforms get
// explicitly registered static weights so normal text cannot select that thin
// default. The browser continues using its existing variable font.
const appFontFamily = kIsWeb ? 'NotoSansJP' : 'KunitoriNotoJP';

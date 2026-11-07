import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// Match the compact portrait buttons shown in the mobile browser, instead of
// stretching them into the space freed by the browser's address/navigation bars.
const nativePortraitAttackHeight = 90.0;
const nativePortraitAttackGap = 8.0;

// Mobile browsers use the normal text size even when iOS's preferred text size
// is smaller. Keep that baseline on native too, while retaining larger sizes
// (including non-linear accessibility scaling).
TextScaler displayTextScaler(TextScaler system, {bool isWeb = kIsWeb}) =>
    isWeb ? system : system.clamp(minScaleFactor: 1);

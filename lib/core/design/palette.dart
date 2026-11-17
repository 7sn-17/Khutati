import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Resolves the token palette for the current brightness.
///
/// Lives in `core` so design widgets never depend on `app/theme`.
KhutatiPalette paletteOf(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark ? KColors.dark : KColors.light;
}

extension KhutatiPaletteContext on BuildContext {
  KhutatiPalette get palette => paletteOf(this);
}

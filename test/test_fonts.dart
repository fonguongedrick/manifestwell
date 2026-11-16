import 'dart:io';

import 'package:flutter/services.dart';

/// flutter_test renders with a placeholder font unless told otherwise. Load
/// the real bundled typefaces so layout in tests matches a device.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File('assets/fonts/$f').readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  await load('Cinzel', ['Cinzel.ttf']);
  await load('NunitoSans', ['NunitoSans.ttf']);
}

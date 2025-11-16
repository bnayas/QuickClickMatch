import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

Future<void> ensureDefaultDecksExist() async {
  final appDir = await getApplicationDocumentsDirectory();
  final deckDir = Directory('${appDir.path}/deck_assets');
  if (!deckDir.existsSync()) {
    deckDir.createSync(recursive: true);
  }
  await _seedMissingDefaultDeckAssets(deckDir.path);
}

Future<void> _seedMissingDefaultDeckAssets(String destPath) async {
  final manifestContent = await rootBundle.loadString('AssetManifest.json');
  final Map<String, dynamic> manifestMap = json.decode(manifestContent);
  const prefix = 'assets/deck_assets/';

  final assetList = manifestMap.keys.where((key) => key.startsWith(prefix));

  for (final asset in assetList) {
    final relativePath = asset.substring(prefix.length);
    if (relativePath.isEmpty || _isHiddenAsset(relativePath)) continue;

    final file = File('$destPath/$relativePath');
    if (file.existsSync()) {
      continue; // file already seeded
    }

    final data = await rootBundle.load(asset);
    file.createSync(recursive: true);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }
}

bool _isHiddenAsset(String relativePath) {
  return relativePath.startsWith('.') ||
      relativePath.contains('/.') ||
      relativePath.contains('__MACOSX') ||
      relativePath.endsWith('.DS_Store');
}

import 'package:quick_click_match/infra/platform/file_manager.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class AndroidFileManager implements FileManager {
  AndroidFileManager._();
  static final AndroidFileManager instance = AndroidFileManager._();
  factory AndroidFileManager() => instance;
  @override
  Future<List<int>> readImage(String path) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/deck_assets/$path');
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    throw Exception('File not found: ${file.path}');
  }

  @override
  Future<String?> readJSON(String path) async {
    final directory = await getApplicationDocumentsDirectory();

    File? file;
    final normalizedPath = path.trim();
    if (normalizedPath.isNotEmpty) {
      file = File('${directory.path}/deck_assets/$normalizedPath.json');
    } else {
      // pick from Downloads or anywhere user wants
      final result = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null || result.files.single.path == null) return null;
      file = File(result.files.single.path!);
    }
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    return content;
  }

  @override
  Future<List<String>> getSubfolders(String path) async {
    final directory = await getApplicationDocumentsDirectory();
    final dir = Directory('${directory.path}/$path');
    final List<String> folders = [];
    await for (var entity in dir.list(followLinks: false)) {
      if (entity is Directory) {
        final folderName =
            entity.path.substring(directory.path.length + path.length);
        // Skip macOS metadata directories
        if (!folderName.contains('__MACOSX') &&
            !folderName.contains('.DS_Store') &&
            !folderName.startsWith('._')) {
          folders.add(folderName);
        }
      }
    }
    return folders;
  }

  @override
  Future<void> writeImage(String path, List<int> bytes) async {
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> writeJSON(String path, String json) async {
    final file = File(path);
    await file.create(recursive: true);
    await file.writeAsString(json);
  }

  @override
  Future<void> deleteDeck(String deckKey) async {
    final normalized = deckKey
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^deck_assets/'), '')
        .trim();
    if (normalized.isEmpty) {
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final deckAssetsPath = '${directory.path}/deck_assets';

    final segments =
        normalized.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.isEmpty) {
      return;
    }

    final possibleDirs = <Directory>{
      Directory('$deckAssetsPath/$normalized'),
      Directory('$deckAssetsPath/${segments.first}'),
    };

    final possibleJsonFiles = <File>{
      File('$deckAssetsPath/$normalized.json'),
      File('$deckAssetsPath/${segments.first}.json'),
    };

    for (final dir in possibleDirs) {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }

    for (final file in possibleJsonFiles) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }
}

FileManager createFileManager() => AndroidFileManager();

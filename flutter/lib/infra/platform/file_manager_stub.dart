import 'file_manager.dart';

class StubFileManager implements FileManager {
  @override
  Future<List<int>> readImage(String path) async =>
      throw UnsupportedError('Not supported');
  @override
  Future<String?> readJSON(String path) async =>
      throw UnsupportedError('Not supported');
  @override
  Future<List<String>> getSubfolders(String path) async =>
      throw UnsupportedError('Not supported');
  @override
  Future<void> writeImage(String path, List<int> bytes) async =>
      throw UnsupportedError('Not supported');
  @override
  Future<void> writeJSON(String path, String json) async =>
      throw UnsupportedError('Not supported');
  @override
  Future<void> deleteDeck(String deckKey) async =>
      throw UnsupportedError('Not supported');
}

FileManager createFileManager() => StubFileManager();

/// Abstract interface for platform-specific file management.
abstract class FileManager {
  FileManager._();

  /// Reads an image file as bytes from the given [path].
  Future<List<int>> readImage(String path);

  /// Reads a JSON file as a string from the given [path].
  Future<String?> readJSON(String path);

  /// Returns a list of subfolder names in the given [path].
  Future<List<String>> getSubfolders(String path);

  /// Writes an image file as bytes to the given [path].
  Future<void> writeImage(String path, List<int> bytes);

  /// Writes a JSON file as a string to the given [path].
  Future<void> writeJSON(String path, String json);

  /// Deletes a deck and its related assets from persistent storage.
  Future<void> deleteDeck(String deckKey);
}

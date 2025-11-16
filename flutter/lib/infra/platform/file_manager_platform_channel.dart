import 'package:flutter/services.dart';
import 'file_manager.dart';

/// Platform channel implementation of [FileManager] for mobile and desktop.
/// Communicates with native code using MethodChannel.
class PlatformChannelFileManager implements FileManager {
  static const MethodChannel _channel = MethodChannel('file_manager');

  @override
  Future<List<int>> readImage(String path) async {
    // Calls native code to read image as bytes
    final List<dynamic> result =
        await _channel.invokeMethod('readImage', {'path': path});
    return result.cast<int>();
  }

  @override
  Future<String?> readJSON(String path) async {
    // Calls native code to read JSON as string
    final String result =
        await _channel.invokeMethod('readJSON', {'path': path});
    return result;
  }

  @override
  Future<List<int>> writeImage(String path, List<int> bytes) async {
    // Calls native code to read image as bytes
    final List<dynamic> result =
        await _channel.invokeMethod('writeImage', {'path': path});
    return result.cast<int>();
  }

  @override
  Future<String> writeJSON(String path, String json) async {
    // Calls native code to read JSON as string
    final String result =
        await _channel.invokeMethod('writeJSON', {'path': path});
    return result;
  }

  @override
  Future<List<String>> getSubfolders(String path) async {
    // Calls native code to list subfolders
    final List<dynamic> result =
        await _channel.invokeMethod('getSubfolders', {'path': path});
    return result.cast<String>();
  }

  @override
  Future<void> deleteDeck(String deckKey) async {
    await _channel.invokeMethod('deleteDeck', {'deckKey': deckKey});
  }
}

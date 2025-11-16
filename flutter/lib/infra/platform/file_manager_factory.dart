import 'file_manager.dart'; // interface
import 'file_manager_stub.dart'
    if (dart.library.io) 'android/file_manager_android.dart';

class FileManagerFactory {
  static FileManager create() {
    return createFileManager();
  }
}

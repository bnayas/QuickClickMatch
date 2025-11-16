import 'dart:developer' as developer;

const bool _isReleaseMode = bool.fromEnvironment('dart.vm.product');

void appLog(
  String message, {
  String name = 'QuickClickMatch',
  Object? error,
  StackTrace? stackTrace,
}) {
  if (_isReleaseMode) return;
  developer.log(
    message,
    name: name,
    error: error,
    stackTrace: stackTrace,
  );
}

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provides a single place to read/write auth related identifiers.
/// Stores data in encrypted storage on Android and falls back to
/// SharedPreferences for other platforms (including web).
class SecureCredentialsStorage {
  static const _userIdKey = 'user_id';
  static const _userNameKey = 'user_name';
  static const _awsLoggedInKey = 'aws_logged_in';

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const AndroidOptions _androidOptions =
      AndroidOptions(encryptedSharedPreferences: true);

  static bool get _useSecureStorage =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> saveUserId(String? value) =>
      _writeString(_userIdKey, value);

  static Future<String?> getUserId() => _readString(_userIdKey);

  static Future<void> saveUserName(String? value) =>
      _writeString(_userNameKey, value);

  static Future<String?> getUserName() => _readString(_userNameKey);

  static Future<void> setAwsLoggedIn(bool value) =>
      _writeBool(_awsLoggedInKey, value);

  static Future<bool> isAwsLoggedIn() async =>
      (await _readBool(_awsLoggedInKey)) ?? false;

  static Future<void> clearUserCredentials() async {
    await Future.wait([
      _delete(_userIdKey),
      _delete(_userNameKey),
      _delete(_awsLoggedInKey),
    ]);
  }

  static Future<void> _writeString(String key, String? value) async {
    if (_useSecureStorage) {
      if (value == null) {
        await _secureStorage.delete(key: key, aOptions: _androidOptions);
      } else {
        await _secureStorage.write(
          key: key,
          value: value,
          aOptions: _androidOptions,
        );
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  static Future<String?> _readString(String key) async {
    if (_useSecureStorage) {
      return _secureStorage.read(key: key, aOptions: _androidOptions);
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(key);
  }

  static Future<void> _writeBool(String key, bool value) async {
    if (_useSecureStorage) {
      await _secureStorage.write(
        key: key,
        value: value.toString(),
        aOptions: _androidOptions,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  static Future<bool?> _readBool(String key) async {
    if (_useSecureStorage) {
      final storedValue =
          await _secureStorage.read(key: key, aOptions: _androidOptions);
      if (storedValue == null) return null;
      return storedValue.toLowerCase() == 'true';
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(key);
  }

  static Future<void> _delete(String key) async {
    if (_useSecureStorage) {
      await _secureStorage.delete(key: key, aOptions: _androidOptions);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}

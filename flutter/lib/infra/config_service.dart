import 'package:shared_preferences/shared_preferences.dart';

class ConfigService {
  static const _ipKey = 'server_ip';

  Future<void> setServerIP(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipKey, ip);
  }

  Future<String?> getServerIP() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ipKey);
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/infra/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigService configService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    configService = ConfigService();
  });

  test('setServerIP stores and retrieves the same value', () async {
    const address = 'https://api.example.com/ws';
    await configService.setServerIP(address);

    final stored = await configService.getServerIP();
    expect(stored, address);
  });

  test('setServerIP overwrites previous value', () async {
    await configService.setServerIP('wss://old.example.com/ws');
    await configService.setServerIP('wss://new.example.com/ws');

    final stored = await configService.getServerIP();
    expect(stored, 'wss://new.example.com/ws');
  });
}

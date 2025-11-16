import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/infra/config_service.dart';
import 'package:quick_click_match/infra/websocket_service.dart';

class _FakeConfigService extends ConfigService {
  _FakeConfigService(this._ip);

  final String? _ip;

  @override
  Future<String?> getServerIP() async => _ip;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getUrl prefers stored server IP and enforces secure scheme', () async {
    final service = WebSocketService(
      configService: _FakeConfigService('http://example.com/ws'),
    );

    final url = await service.getUrl();
    expect(url, 'wss://example.com/ws');
  });
}

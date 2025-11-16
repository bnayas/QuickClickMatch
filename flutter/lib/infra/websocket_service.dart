// lib/infra/websocket_service.dart - REACTIVE VERSION
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:quick_click_match/infra/config_service.dart';
import 'package:flutter/foundation.dart';
import 'package:quick_click_match/utils/debug_logger.dart';

class WebSocketService {
  static WebSocketService? _instance;
  static const String _envBackendAddress =
      String.fromEnvironment('BACKEND_ADDRESS', defaultValue: '');
  static const String _devFallbackBackend = 'ws://localhost:8080/ws';

  factory WebSocketService({ConfigService? configService}) {
    _instance ??= WebSocketService._internal(configService);
    return _instance!;
  }

  WebSocketService._internal(ConfigService? configService) {
    _configService = configService ?? ConfigService();
  }

  late ConfigService _configService;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  String? _registeredAsUserId;

  // Message stream (existing)
  final StreamController<Map<String, dynamic>> _messagesController =
      StreamController<Map<String, dynamic>>.broadcast();

  // NEW: Connection state stream
  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();
  Completer<bool>? _connectionCompleter;

  Stream<Map<String, dynamic>> get messages => _messagesController.stream;

  // NEW: Expose connection state as a stream
  Stream<bool> get connectionState => _connectionStateController.stream;

  bool get isConnected => getIsConnected();
  bool get isConnecting =>
      _connectionCompleter != null && !_connectionCompleter!.isCompleted;
  String? get registeredAsUserId => _registeredAsUserId;

  void updateRegisteredUserId(String? userId) {
    _registeredAsUserId = userId;
  }

  // NEW: Helper to emit connection state changes
  /// Use this function to change the connection state and emit it.
  /// Always call this instead of assigning `_isConnected` directly.
  void _setConnectionState(bool connected) {
    debugLog(
        '[WS] _setConnectionState called: $connected (current: $_isConnected)');

    // update internal flag only here
    if (_isConnected == connected) {
      debugLog('[WS] Connection state unchanged, not emitting');
      return;
    }

    _isConnected = connected;

    if (_connectionStateController.isClosed) {
      debugLog('[WS] WARNING: Connection state controller is closed!');
      return;
    }

    if (!_connectionStateController.hasListener) {
      debugLog('[WS] WARNING: No listeners on connection state stream!');
    }

    _connectionStateController.add(connected);
    debugLog('[WS] Connection state emitted: $connected');
  }

  Future<String?> getUrl() async {
    final ip = (await _configService.getServerIP())?.trim() ?? '';
    final envAddress = _envBackendAddress.trim();

    String address = '';
    if (ip.isNotEmpty) {
      address = ip;
    } else if (envAddress.isNotEmpty) {
      address = envAddress;
    } else if (!kReleaseMode) {
      address = _devFallbackBackend;
    }

    if (address.isEmpty) {
      throw StateError(
        'BACKEND_ADDRESS not configured. Provide --dart-define BACKEND_ADDRESS=... '
        'or set a server IP in Settings before starting the app.',
      );
    }

    final lower = address.toLowerCase();
    Uri parsed;

    if (lower.startsWith('ws://') || lower.startsWith('wss://')) {
      parsed = Uri.parse(address);
      if (parsed.scheme == 'ws') {
        parsed = parsed.replace(scheme: 'wss');
      }
    } else if (lower.startsWith('http://') || lower.startsWith('https://')) {
      parsed = Uri.parse(address);
      parsed = parsed.replace(scheme: 'wss');
    } else {
      parsed = Uri.parse('//$address');
    }

    if (parsed.host.isEmpty) {
      throw StateError('Invalid server address: $address');
    }

    final bool allowInsecureWs = !kReleaseMode;

    if (_looksLikeIpAddress(parsed.host) && kReleaseMode) {
      throw StateError(
          'Insecure host detected. Configure a domain that supports TLS.');
    }

    if (parsed.scheme != 'ws' && parsed.scheme != 'wss') {
      parsed = parsed.replace(scheme: 'wss');
    }

    if (parsed.scheme == 'ws' && !allowInsecureWs) {
      parsed = parsed.replace(scheme: 'wss');
    }

    return parsed.replace(scheme: 'wss').toString();
  }

  bool _looksLikeIpAddress(String host) {
    final normalized = host.trim();
    final ipv4Pattern = RegExp(
        r'^((25[0-5]|2[0-4]\d|1?\d{1,2})\.){3}(25[0-5]|2[0-4]\d|1?\d{1,2})$');
    final ipv6Pattern = RegExp(r'^\[?[0-9a-fA-F:]+\]?$');
    return ipv4Pattern.hasMatch(normalized) ||
        ipv6Pattern.hasMatch(normalized) ||
        normalized == 'localhost';
  }

  void _handleWebSocketMessage(dynamic data) {
    if (!_isConnected || isConnecting) {
      if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
        _connectionCompleter!.complete(true);
        _setConnectionState(true);
      }
    }
    try {
      if (data is String) {
        final decoded = json.decode(data) as Map<String, dynamic>;
        debugLog('[WS] Received: ${decoded['type']}');
        if (!_messagesController.isClosed) {
          _messagesController.add(decoded);
        }
      }
    } catch (e) {
      debugLog('[WS] Decode error: $e');
    }
  }

  Future<bool> _connectPreconditions() async {
    debugLog(
        '[WS] connectionPreconditions() - connected: $_isConnected, connecting: $isConnecting');
    if (isConnecting) {
      debugLog('[WS] Already connecting...');
      return _connectionCompleter!.future;
    }
    if (_isConnected) {
      if (getIsConnected()) {
        debugLog('[WS] Already connected and verified working');
        return false;
      } else {
        debugLog(
            '[WS] Was marked connected but connection is dead, reconnecting...');
        await _cleanup();
      }
    }
    return true;
  }

  Future<WebSocketChannel> wsConnectWithTimeout(Uri uri,
      {Duration timeout = const Duration(seconds: 5)}) async {
    return await Future<WebSocketChannel>.delayed(Duration.zero, () {
      return WebSocketChannel.connect(uri);
    }).timeout(timeout);
  }

  Future<void> connect() async {
    bool shouldConnect = await _connectPreconditions();
    if (!shouldConnect) return;
    String? url = await getUrl();
    if (url == null) {
      throw StateError('Server IP not configured');
    }

    _connectionCompleter = Completer<bool>();
    debugLog('[WS] Connecting to: $url');
    try {
      _channel = await wsConnectWithTimeout(Uri.parse(url));
      _setConnectionState(true);
      debugLog('[WS] Init WebSocket successfully');
    } catch (e) {
      debugLog('[WS] Failed to create WebSocket channel: $e');
      _setConnectionState(false);
      _connectionCompleter = null;
      throw Exception('Cannot connect to server: $e');
    }

    _subscription = _channel!.stream.listen(
      (dynamic data) {
        _handleWebSocketMessage(data);
      },
      onDone: () {
        debugLog('[WS] Connection closed by server');
        _setConnectionState(false); // EMIT STATE CHANGE
        if (_connectionCompleter != null &&
            !_connectionCompleter!.isCompleted) {
          _connectionCompleter!.complete(false);
        }
      },
      onError: (error) {
        debugLog('[WS] Connection error: $error');
        _setConnectionState(false); // EMIT STATE CHANGE
        if (_connectionCompleter != null &&
            !_connectionCompleter!.isCompleted) {
          _connectionCompleter!.complete(false);
        }
      },
      cancelOnError: true, // Important: cancel stream on error
    );

    try {
      final connected = await _connectionCompleter!.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugLog('[WS] Connection timeout - no response from server');
          _setConnectionState(false); // EMIT on timeout
          return false;
        },
      );

      if (!connected) {
        _setConnectionState(false); // EMIT before throwing
        final errorMessage = _isConnected
            ? 'Connection timeout'
            : 'Failed to establish connection - server not responding';
        _connectionCompleter = null;
        throw Exception(errorMessage);
      }

      debugLog('[WS] Connection verified and ready');
    } catch (e) {
      debugLog('[WS] Connection verification failed: $e');
      _setConnectionState(false); // EMIT on error
      _connectionCompleter = null;
      rethrow;
    }
    _connectionCompleter = null;
  }

  bool getIsConnected() {
    if (!_isConnected) return false;
    if (_channel == null) {
      _setConnectionState(false); // EMIT STATE CHANGE
      return false;
    }

    try {
      if (_channel!.closeCode != null) {
        _setConnectionState(false); // EMIT STATE CHANGE
        return false;
      }
      return true;
    } catch (e) {
      debugLog('[WS] Error checking connection: $e');
      _setConnectionState(false); // EMIT STATE CHANGE
      return false;
    }
  }

  void register(String? userId, {String? userName}) {
    debugLog('[WS] Register: $userId as $userName');
    try {
      _send({
        'type': 'register',
        'userId': userId,
        'userName': userName ?? userId,
      });
      _registeredAsUserId = userId;
    } catch (e) {
      debugLog('[WS] Error registering user ($userId): $e');
    }
  }

  // ... rest of your methods unchanged ...

  void _send(Map<String, dynamic> data) {
    if (!getIsConnected()) {
      debugLog('[WS] Cannot send - not connected');
      return;
    }

    try {
      final jsonString = json.encode(data);
      debugLog('[WS] Sending: ${data['type']}');
      _channel!.sink.add(jsonString);
    } catch (e) {
      debugLog('[WS] Send error: $e');
      _setConnectionState(false); // EMIT STATE CHANGE
    }
  }

  Future<void> _cleanup() async {
    debugLog('[WS] Cleanup...');
    _registeredAsUserId = null;
    _setConnectionState(false);
    await _subscription?.cancel();
    _subscription = null;
    _connectionCompleter = null;
    if (_channel != null) {
      try {
        await _channel!.sink.close(ws_status.normalClosure);
      } catch (e) {
        debugLog('[WS] Close error: $e');
      }
      _channel = null;
    }
  }

  Future<void> disconnect() async {
    debugLog('[WS] Disconnecting...');
    _registeredAsUserId = null;

    await _cleanup();
    debugLog('[WS] Disconnected');
  }

  static Future<void> resetSingleton() async {
    if (_instance != null) {
      await _instance!.disconnect();
      try {
        await _instance!._messagesController.close();
        await _instance!._connectionStateController.close();
      } catch (e) {
        debugLog('[WS] Error closing controllers: $e');
      }
      _instance = null;
      debugLog('[WS] Singleton reset complete');
    }
  }

  void sendInvite({
    required String? fromUserId,
    required String fromUserName,
    required String? toUserId,
    required String toUserName,
    required String deckJsonKey,
    int? deckCardCount,
  }) {
    _send({
      'type': 'send_invite',
      'fromUserId': fromUserId,
      'fromUserName': fromUserName,
      'toUserId': toUserId,
      'toUserName': toUserName,
      'deckJsonKey': deckJsonKey,
      'deckCardCount': deckCardCount ?? 55,
    });
  }

  void migrateIdentity({required String oldUserId, required String newUserId}) {
    _send({
      'type': 'migrate_identity',
      'oldUserId': oldUserId,
      'newUserId': newUserId,
    });
  }

  void searchUser(String query) {
    _send({
      'type': 'search_user',
      'username': query,
      'userId': query,
      'searchQuery': query,
    });
  }

  void respondToInvite({required String inviteId, required bool accept}) {
    _send({
      'type': 'respond_invite',
      'inviteId': inviteId,
      'response': accept ? 'accepted' : 'declined',
    });
  }

  void blockUser(String blockUserId) {
    _send({'type': 'block_user', 'blockUserId': blockUserId});
  }

  void unblockUser(String unblockUserId) {
    _send({'type': 'unblock_user', 'unblockUserId': unblockUserId});
  }

  void sendClick(int symbolId, int timestamp) {
    _send({'type': 'click', 'symbolId': symbolId, 'timestamp': timestamp});
  }

  void sendAckClick(bool wasFirst) {
    _send({'type': 'ack_click', 'value': wasFirst});
  }

  void sendGameEvent(int? symbolId, int? timestamp) {
    timestamp ??= DateTime.now().millisecondsSinceEpoch;
    sendClick(symbolId!, timestamp);
  }

  void sendReadyToDraw() {
    _send({'type': 'ready_to_draw'});
  }

  void endGame() {
    _send({'type': 'game_ended'});
  }

  void leavingGame() {
    _send({'type': 'peer_left'});
  }

  void send(Map<String, dynamic> data) {
    _send(data);
  }
}

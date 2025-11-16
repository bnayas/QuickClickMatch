import 'dart:async';
import 'package:quick_click_match/infra/websocket_service.dart';
import 'package:quick_click_match/utils/debug_logger.dart';

class GameService {
  static final GameService _instance = GameService._internal();
  factory GameService() => _instance;
  GameService._internal();

  WebSocketService? _webSocketService;
  StreamSubscription? _internalMessageSubscription;
  List<Map<String, dynamic>> _currentInvites = [];

  // --- Stream controllers ---
  final StreamController<List<Map<String, dynamic>>> _pendingInvitesController =
      StreamController<List<Map<String, dynamic>>>.broadcast();

  final StreamController<Map<String, dynamic>> _newInviteController =
      StreamController<Map<String, dynamic>>.broadcast();

  final StreamController<Map<String, dynamic>> _inviteResponseController =
      StreamController<Map<String, dynamic>>.broadcast();

  // NEW: Stream controller for registration state
  final StreamController<bool> _registrationController =
      StreamController<bool>.broadcast();

  // NEW: Stream controller for display name update events
  final StreamController<Map<String, dynamic>> _displayNameUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();

  // NEW: Stream controller for authentication errors
  final StreamController<Map<String, dynamic>> _authErrorController =
      StreamController<Map<String, dynamic>>.broadcast();

  int _referenceCount = 0;
  String? _currentUserId;
  String? _currentUserName;
  bool _isRegistered =
      false; // This is now a private cache, driven by server messages

  WebSocketService _ensureWebSocketService() {
    _webSocketService ??= WebSocketService();
    return _webSocketService!;
  }

  // Expose connection state stream (socket open/closed)
  Stream<bool> get connectionState => _ensureWebSocketService().connectionState;

  // Expose message stream
  Stream<Map<String, dynamic>> get messages =>
      _ensureWebSocketService().messages;

  // NEW: Expose registration state stream (joined server)
  // ** THIS IS THE FIX FOR YOUR BUG. Use this in LobbyScreen for _isConnected **
  Stream<bool> get registrationState async* {
    yield _isRegistered;
    yield* _registrationController.stream;
  }

  // NEW: Stream for display name update results
  Stream<Map<String, dynamic>> get displayNameUpdateEvents =>
      _displayNameUpdateController.stream;

  // NEW: Stream for auth errors
  Stream<Map<String, dynamic>> get authErrorEvents =>
      _authErrorController.stream;

  // Check if socket is currently connected
  bool get isSocketConnected =>
      _webSocketService != null && _webSocketService!.getIsConnected();

  // Check if registered (user is authenticated)
  bool get isRegistered => _isRegistered;

  // Get current user info
  String? get currentUserId => _currentUserId;
  String? get currentUserName => _currentUserName;

  // Get the underlying WebSocket service (for advanced use cases)
  WebSocketService get webSocketService => _ensureWebSocketService();

  Stream<List<Map<String, dynamic>>> get pendingInvites async* {
    yield _currentInvites; // Emit current value first
    yield* _pendingInvitesController.stream; // Then emit new updates
  }

  // Getter for single new invites (for pop-ups)
  Stream<Map<String, dynamic>> get newInvite => _newInviteController.stream;

  // Getter for invite responses
  Stream<Map<String, dynamic>> get inviteResponse =>
      _inviteResponseController.stream;

  /// Get or create the WebSocket service instance without connecting
  Future<WebSocketService> getMultiplayerService() async {
    debugLog('[GameService] getMultiplayerService called');

    _webSocketService ??= WebSocketService();
    _referenceCount++;

    debugLog('[GameService] Reference count: $_referenceCount');
    return _webSocketService!;
  }

  /// Initialize and connect to multiplayer with user credentials
  Future<void> connectAndRegister({
    required String userId,
    required String userName,
    String? oldUserId,
    bool forceReconnect = false,
  }) async {
    debugLog('[GameService] connectAndRegister called for $userId');

    try {
      // Get or create WebSocket service
      _webSocketService ??= WebSocketService();
      _referenceCount++;

      // Store credentials for reconnection
      _currentUserId = userId;
      _currentUserName = userName;

      // Check if socket is open and we are *already registered*
      if (isSocketConnected &&
          _isRegistered &&
          _webSocketService!.registeredAsUserId == userId &&
          !forceReconnect) {
        debugLog('[GameService] Already connected and registered as $userId');
        _registrationController.add(true); // Re-notify listeners
        return;
      }

      // Disconnect if force reconnect or different user
      if (forceReconnect ||
          (_isRegistered && _webSocketService!.registeredAsUserId != userId)) {
        debugLog('[GameService] Disconnecting for reconnect...');
        await _webSocketService!.disconnect();
        // State will be cleaned up by the listener's onDone
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Connect socket if not connected
      if (!isSocketConnected) {
        debugLog('[GameService] Connecting to WebSocket...');
        await _webSocketService!.connect();
      }

      _setupInternalMessageListener();

      // Register user
      final registrationId = oldUserId ?? userId;
      debugLog(
          '[GameService] Registering as $registrationId (force: $forceReconnect)');

      // We no longer set _isRegistered = true here.
      // We wait for the 'joined' message from the server.

      if (forceReconnect) {
        _webSocketService!.send({
          'type': 'force_register',
          'userId': registrationId,
          'userName': userName,
        });
        _webSocketService!.updateRegisteredUserId(registrationId);
      } else {
        _webSocketService!.register(registrationId, userName: userName);
      }

      // Handle identity migration if needed
      if (oldUserId != null && oldUserId != userId) {
        debugLog('[GameService] Migrating identity: $oldUserId -> $userId');
        _webSocketService!.migrateIdentity(
          oldUserId: oldUserId,
          newUserId: userId,
        );
        // We wait for 'identity_migrated' message
      }

      debugLog('[GameService] Connection and registration messages sent.');
    } catch (e) {
      debugLog('[GameService] Connection/registration failed: $e');
      _isRegistered = false;
      _registrationController.add(false);
      rethrow;
    }
  }

  /// Reconnect with stored credentials
  Future<void> reconnect() async {
    if (_currentUserId == null || _currentUserName == null) {
      throw StateError('No stored credentials for reconnection');
    }

    debugLog('[GameService] Reconnecting...');
    await connectAndRegister(
      userId: _currentUserId!,
      userName: _currentUserName!,
    );
  }

  /// Sets up the internal listener to cache state from WebSocket messages.
  void _setupInternalMessageListener() {
    // Prevent setting up multiple listeners
    if (_internalMessageSubscription != null) return;

    final ws = _webSocketService;
    if (ws == null) return;

    debugLog('[GameService] Setting up internal message listener');
    _internalMessageSubscription = ws.messages.listen(
      _handleInternalMessage,
      onError: (e) {
        debugLog('[GameService] Internal message listener error: $e');
        _isRegistered = false;
        _registrationController.add(false);
        _internalMessageSubscription?.cancel();
        _internalMessageSubscription = null;
      },
      onDone: () {
        debugLog('[GameService] Internal message listener done (disconnected)');
        _isRegistered = false;
        _registrationController.add(false);
        _internalMessageSubscription = null;
      },
    );
  }

  /// Handles messages for internal state caching (e.g., invites).
  void _handleInternalMessage(Map<String, dynamic> msg) {
    final type = msg['type'];
    debugLog('[GameService] _handleInternalMessage called with type: $type');

    switch (type) {
      case 'joined':
        _isRegistered = true;
        _currentUserId = msg['userId'];
        _currentUserName = msg['displayName'];
        _webSocketService?.updateRegisteredUserId(_currentUserId);
        _registrationController.add(true);
        debugLog(
            '[GameService] Successfully registered as ${msg['displayName']}');
        break;

      case 'identity_migrated':
        _isRegistered = true;
        _currentUserId = msg['newUserId'];
        _currentUserName = msg['displayName']; // Server now sends this
        _webSocketService?.updateRegisteredUserId(_currentUserId);
        _registrationController.add(true);
        debugLog('[GameService] Successfully migrated to ${msg['newUserId']}');
        break;

      case 'register_error':
        _isRegistered = false;
        _webSocketService?.updateRegisteredUserId(null);
        _registrationController.add(false);
        debugLog('[GameService] Registration failed: ${msg['message']}');
        // Note: LobbyScreen will catch this via its raw message listener
        break;

      case 'display_name_updated':
        _currentUserName = msg['newDisplayName'];
        _displayNameUpdateController.add(msg);
        debugLog('[GameService] Display name updated to $_currentUserName');
        break;

      case 'update_error':
        _displayNameUpdateController.add(msg);
        debugLog('[GameService] Display name update failed: ${msg['message']}');
        break;

      case 'auth_required':
        _authErrorController.add(msg);
        debugLog('[GameService] Server requires authentication.');
        break;

      case 'pending_invites':
        final invites = (msg['invites'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        _currentInvites = invites;
        _pendingInvitesController.add(_currentInvites);
        debugLog('[GameService] Cached ${invites.length} pending invites');
        break;

      case 'new_invite':
        final invite = msg['invite'] as Map<String, dynamic>;
        // Add to list (avoid duplicates just in case)
        _currentInvites.removeWhere((i) => i['id'] == invite['id']);
        _currentInvites.add(invite);

        _pendingInvitesController
            .add(List.from(_currentInvites)); // Update list stream
        _newInviteController.add(invite); // Fire new invite stream (for dialog)
        debugLog('[GameService] Cached new invite ${invite['id']}');
        break;

      case 'invite_response':
        debugLog('[GameService] 🎯 Processing invite_response');
        try {
          final inviteId = msg['inviteId'];
          if (inviteId is String) {
            final initialLength = _currentInvites.length;
            _currentInvites.removeWhere((invite) => invite['id'] == inviteId);
            if (_currentInvites.length != initialLength) {
              _pendingInvitesController
                  .add(List.from(_currentInvites)); // sync listeners
            }
          }
          _inviteResponseController.add(msg);
          debugLog('✅ Successfully added to inviteResponseController');
        } catch (e) {
          debugLog('❌ ERROR adding to controller: $e');
        }
        break;

      default:
        debugLog(
            '[GameService] Unhandled message type in _handleInternalMessage: $type');
    }
  }

  /// NEW: Update display name live on the server
  Future<void> updateDisplayName(String newDisplayName) async {
    if (!isSocketConnected) {
      throw Exception('Not connected to server');
    }
    if (!isRegistered) {
      throw Exception('Not registered with server. Please wait or reconnect.');
    }

    _webSocketService!.send({
      'type': 'update_display_name',
      'newDisplayName': newDisplayName,
    });
    debugLog('[GameService] Sent display name update request');
    // Listen to 'displayNameUpdateEvents' stream for the result
  }

  /// DEPRECATED: Use updateDisplayName instead
  @Deprecated('Use updateDisplayName for live updates without reconnecting')
  Future<void> updateUserName(String newUserName) async {
    if (_currentUserId == null) {
      throw StateError('No user ID set');
    }

    _currentUserName = newUserName;

    // Reconnect with new name
    if (_webSocketService != null) {
      await _webSocketService!.disconnect();
      // State will be cleaned up by onDone listener
      await connectAndRegister(
        userId: _currentUserId!,
        userName: newUserName,
      );
    }
  }

  /// Release reference but keep connection alive
  Future<void> releaseMultiplayerService() async {
    if (_referenceCount > 0) {
      _referenceCount--;
      debugLog(
          '[GameService] Reference count decremented to: $_referenceCount');
    }
    debugLog('[GameService] WebSocket connection kept alive for reuse');
  }

  /// Fully disconnect (app closing, user logs out)
  Future<void> disconnectMultiplayer() async {
    debugLog('[GameService] disconnectMultiplayer called');

    if (_webSocketService != null) {
      await _webSocketService!.disconnect();
      _referenceCount = 0;
      _currentUserId = null;
      _currentUserName = null;
      _isRegistered = false; // Manually set, though onDone should also fire

      // Cleanup listener and cache
      await _internalMessageSubscription?.cancel();
      _internalMessageSubscription = null;
      _currentInvites = [];

      // Emit empty/false states
      _registrationController.add(false);
      _pendingInvitesController.add(_currentInvites); // Emit empty list

      debugLog('[GameService] WebSocket disconnected and cleaned up');
    }
  }

  /// Throws an exception if the user is not registered.
  void _checkRegistration() {
    if (!isSocketConnected) {
      throw Exception('Not connected to server');
    }
    if (!isRegistered) {
      throw Exception('Not registered with server. Please wait or reconnect.');
    }
  }

  /// Search for a user ID first and fall back to display name.
  Future<void> searchUser(String query) async {
    _checkRegistration(); // NEW: Check if registered
    _webSocketService!.searchUser(query);
  }

  /// Send game invite
  Future<void> sendInvite({
    required String? fromUserId,
    required String fromUserName,
    required String? toUserId,
    required String toUserName,
    required String deckJsonKey,
    int? deckCardCount,
  }) async {
    // NOTE: We don't call _checkRegistration() here because the server
    // supports implicit registration via 'send_invite'.
    if (!isSocketConnected) {
      throw Exception('Not connected to server');
    }

    _webSocketService!.sendInvite(
      fromUserId: fromUserId,
      fromUserName: fromUserName,
      toUserId: toUserId,
      toUserName: toUserName,
      deckJsonKey: deckJsonKey,
      deckCardCount: deckCardCount,
    );
    debugLog('[GameService] Invite sent from $fromUserId to $toUserId');
  }

  /// Respond to invite
  Future<void> respondToInvite({
    required String inviteId,
    required bool accept,
  }) async {
    debugLog('[GameService] - response to invite: $inviteId, accept: $accept');
    try {
      _checkRegistration(); // NEW: Check if registered
    } catch (e) {
      if (_currentUserId == null || _currentUserName == null) {
        debugLog(
            'Missing regisration details: $_currentUserName, $_currentUserId');
        return;
      }
      connectAndRegister(userId: _currentUserId!, userName: _currentUserName!);
      debugLog("Registration problem $e");
      try {
        _checkRegistration(); // NEW: Check if registered
      } catch (e) {
        return;
      }
    }
    debugLog('[GameService] - call WebSocketService response to invite');
    _webSocketService!.respondToInvite(inviteId: inviteId, accept: accept);
    final int initialLength = _currentInvites.length;
    _currentInvites.removeWhere((i) => i['id'] == inviteId);
    final wasRemoved = _currentInvites.length < initialLength;
    if (wasRemoved) {
      debugLog('[GameService] Invite was removed $inviteId: $accept');
      _pendingInvitesController.add(List.from(_currentInvites));
    } else {
      debugLog('[GameService] Invite was not removed $inviteId: $accept');
    }
    debugLog('[GameService] Responded to invite $inviteId: $accept');
  }

  /// Block user
  Future<void> blockUser(String blockUserId) async {
    _checkRegistration(); // NEW: Check if registered
    _webSocketService!.blockUser(blockUserId);
    debugLog('[GameService] Blocked user $blockUserId');
  }

  /// Unblock user
  Future<void> unblockUser(String unblockUserId) async {
    _checkRegistration(); // NEW: Check if registered
    _webSocketService!.unblockUser(unblockUserId);
    debugLog('[GameService] Unblocked user $unblockUserId');
  }

  /// Send custom message (for backwards compatibility)
  void send(Map<String, dynamic> data) {
    if (!isSocketConnected) {
      debugLog('[GameService] Cannot send, socket is not connected.');
      return;
    }
    if (!_isRegistered &&
        data['type'] != 'register' &&
        data['type'] != 'force_register') {
      debugLog(
          '[GameService] Cannot send, user not registered. Message: ${data['type']}');
      // Allow auth messages to pass
      // We also allow 'send_invite' and 'migrate_identity' to pass
      // This logic is handled by the server now, so we just send.
    }
    _webSocketService!.send(data);
  }

  // Game-related methods
  void sendClick(int symbolId, int timestamp) {
    if (!isRegistered) return; // Silently fail for game moves
    _webSocketService?.sendClick(symbolId, timestamp);
  }

  void sendAckClick(bool wasFirst) {
    if (!isRegistered) return;
    _webSocketService?.sendAckClick(wasFirst);
  }

  void sendGameEvent(int? symbolId, int? timestamp) {
    if (!isRegistered) return;
    _webSocketService?.sendGameEvent(symbolId, timestamp);
  }

  void sendReadyToDraw() {
    if (!isRegistered) return;
    _webSocketService?.sendReadyToDraw();
  }

  void endGame() {
    if (!isRegistered) return;
    _webSocketService?.endGame();
  }

  void leavingGame() {
    if (!isRegistered) return;
    _webSocketService?.leavingGame();
  }
}

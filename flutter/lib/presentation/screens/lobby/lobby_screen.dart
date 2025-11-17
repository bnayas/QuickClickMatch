// lib/presentation/screens/lobby_screen.dart - SIMPLIFIED VERSION
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:quick_click_match/services/game_service.dart';
import 'package:quick_click_match/services/friends_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import '../../../infra/platform/file_manager_factory.dart';
import 'package:quick_click_match/services/localization_service.dart';
import 'package:quick_click_match/services/secure_credentials_storage.dart';
import 'package:quick_click_match/utils/debug_logger.dart';
import 'package:quick_click_match/services/auth_service.dart';
import 'package:quick_click_match/utils/user_identity.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  final GameService _gameService = GameService();
  late final LocalizationService _l10n;
  final TextEditingController _findFriendController = TextEditingController();

  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectionSubscription;
  StreamSubscription? _inviteListSubscription;
  StreamSubscription? _inviteResponseSubscription;
  StreamSubscription? _newInviteSubscription;
  StreamSubscription? _registrationSubscription;

  String? _webSocketUserId;
  String? _oldWebSocketUserId;
  String? _displayName;
  List<Map<String, dynamic>> _pendingInvites = [];
  FriendsCacheService? _friendsService;
  List<Friend> _friends = [];
  late final AuthStateNotifier _authNotifier;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isSocketConnected = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  String? _deckJson;
  String? _deckJsonKey;
  Set<String> _availableDecks = {};
  late SharedPreferences _prefs;
  bool _pendingConnectionSnack = false;
  bool _isLoadingUserData = false;
  bool _pendingUserDataReload = false;

  @override
  void initState() {
    super.initState();
    _l10n = LocalizationService.instance;
    _l10n.addListener(_handleLocalizationChanged);
    _authNotifier = AuthStateNotifier.instance;
    _authNotifier.addListener(_handleAuthStateChanged);
    _loadAvailableDecks();
    _loadUserData();
    _setupGameServiceListeners();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handleRouteArguments();
  }

  @override
  void dispose() {
    _connectionSubscription?.cancel();
    _messageSubscription?.cancel();
    _inviteListSubscription?.cancel();
    _newInviteSubscription?.cancel();
    _inviteResponseSubscription?.cancel();
    _registrationSubscription?.cancel();
    _l10n.removeListener(_handleLocalizationChanged);
    _authNotifier.removeListener(_handleAuthStateChanged);
    _findFriendController.dispose();
    super.dispose();
  }

  void _handleLocalizationChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key) => _l10n.t(key);
  String _f(String key, Map<String, String> params) =>
      _l10n.format(key, params);
  String _playerName(String? name) => name ?? _t('lobby.player.unknown');

  Future<void> _connectToServer({
    bool showSuccessMessage = true,
    bool forceReconnect = false,
  }) async {
    if (_isConnecting || _webSocketUserId == null || _displayName == null) {
      return;
    }

    setState(() {
      _isConnecting = true;
      _isConnected = false;
      if (showSuccessMessage) {
        _pendingConnectionSnack = true;
      }
    });

    try {
      await _gameService.connectAndRegister(
        userId: _webSocketUserId!,
        userName: _displayName!,
        oldUserId: _oldWebSocketUserId,
        forceReconnect: forceReconnect,
      );

      setState(() {
        _isConnecting = false;
      });

      // IMPORTANT: Verify listeners are active after connection
      debugLog('[LobbyScreen] Connection complete, verifying listeners...');
      debugLog(
          '[LobbyScreen] Has invite response listener: ${_inviteResponseSubscription != null}');
    } catch (e) {
      debugLog('Connection failed: $e');

      setState(() {
        _isConnecting = false;
        _isConnected = false;
      });

      if (showSuccessMessage) {
        _pendingConnectionSnack = false;
      }

      if (mounted && _reconnectAttempts == 1 && showSuccessMessage) {
        _showSnackBar(_t('lobby.error.cannotConnect'), Colors.red);
      }
    }
  }

  void _setupGameServiceListeners() {
    _connectionSubscription?.cancel();
    _messageSubscription?.cancel();
    _inviteListSubscription?.cancel();
    _newInviteSubscription?.cancel();
    _inviteResponseSubscription?.cancel();

    debugLog('[LobbyScreen] Setting up GameService listeners');

    // Listen to connection state
    _connectionSubscription = _gameService.connectionState.listen(
      (bool connected) {
        if (!mounted) return;

        debugLog('[LobbyScreen] Connection state changed: $connected');

        final wasSocketConnected = _isSocketConnected;

        setState(() {
          _isSocketConnected = connected;
          if (!connected) {
            _isConnecting = false;
            _isConnected = false;
          }
        });

        if (connected) {
          // Reset reconnect attempts once the transport is back
          _reconnectAttempts = 0;
        }

        // Only try to reconnect if:
        // 1. We lost connection (were connected, now not)
        // 2. Not currently connecting
        // 3. Haven't exceeded max reconnect attempts
        if (!connected &&
            wasSocketConnected &&
            !_isConnecting &&
            _reconnectAttempts < _maxReconnectAttempts) {
          _handleConnectionLost();
        }
      },
    );

    // Listen to registration/authentication state
    _registrationSubscription = _gameService.registrationState.listen(
      (bool registered) {
        if (!mounted) return;

        debugLog('[LobbyScreen] Registration state changed: $registered');

        final wasRegistered = _isConnected;

        setState(() {
          _isConnected = registered;
          if (registered) {
            _isConnecting = false;
            _reconnectAttempts = 0;
            if (_oldWebSocketUserId != null) {
              _oldWebSocketUserId = null;
            }
          }
        });

        if (registered && _pendingConnectionSnack) {
          _pendingConnectionSnack = false;
          _showSnackBar(_t('lobby.snackbar.connected'), Colors.green);
        }

        if (!registered && wasRegistered) {
          _pendingConnectionSnack = false;
        }
      },
    );

    _inviteListSubscription = _gameService.pendingInvites.listen(
      (invites) {
        if (!mounted) return;
        debugLog('[LobbyScreen] Received ${invites.length} pending invites');
        setState(() {
          _pendingInvites = invites;
        });
      },
    );

    _newInviteSubscription = _gameService.newInvite.listen(
      (invite) {
        if (!mounted) return;
        debugLog('[LobbyScreen] Received new invite: ${invite['id']}');
        _showInviteDialog(invite);
      },
    );

    // CRITICAL: Subscribe to invite responses
    _inviteResponseSubscription = _gameService.inviteResponse.listen(
      (response) {
        debugLog(
            '[LobbyScreen] ✅ INVITE RESPONSE RECEIVED: ${response['status']} from ${response['responder']}');
        if (!mounted) return;
        _handleInviteResponse(response);
      },
      onError: (error) {
        debugLog('[LobbyScreen] ❌ Error in invite response stream: $error');
      },
      onDone: () {
        debugLog('[LobbyScreen] ⚠️  Invite response stream closed');
      },
      cancelOnError: false,
    );

    _messageSubscription = _gameService.messages.listen(
      (msg) {
        if (!mounted) return;
        debugLog('[LobbyScreen] Raw message type: ${msg['type']}');
        unawaited(_handleMessage(msg));
      },
    );

    debugLog('[LobbyScreen] ✅ All listeners set up successfully');
    debugLog(
        '[LobbyScreen] Invite response subscription active: ${_inviteResponseSubscription != null}');
  }

  Future<void> _handleMessage(Map<String, dynamic> msg) async {
    switch (msg['type']) {
      case 'force_disconnected':
        _handleForceDisconnected(msg);
        break;
      case 'identity_migrated':
        _handleIdentityMigrated(msg);
        break;
      case 'register_error':
        _handleRegisterError(msg);
        break;
      case 'ready':
        await _handleGameReady(msg);
        break;
      case 'user_search_result':
        _handleUserSearchResult(msg);
        break;
    }
  }

  void _handleConnectionLost() {
    if (_isConnecting) return;

    _reconnectAttempts++;
    debugLog(
        '[LobbyScreen] Connection lost, attempting reconnect $_reconnectAttempts/$_maxReconnectAttempts');

    if (_reconnectAttempts > _maxReconnectAttempts) {
      debugLog('[LobbyScreen] Max reconnect attempts reached, giving up');
      if (mounted) {
        _showSnackBar(
          _t('lobby.snackbar.connectionLost'),
          Colors.orange,
        );
      }
      return;
    }

    // Exponential backoff: 2s, 4s, 8s
    final delay = Duration(seconds: pow(2, _reconnectAttempts).toInt());
    debugLog('[LobbyScreen] Reconnecting in ${delay.inSeconds}s...');

    Future.delayed(delay, () {
      if (mounted && !_isSocketConnected && !_isConnecting) {
        _connectToServer(showSuccessMessage: false);
      }
    });
  }

  void _handleRouteArguments() {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _deckJson = args['deckJson'] as String?;
      _deckJsonKey = args['deckJsonKey'] as String?;
    }
  }

  Future<void> _loadAvailableDecks() async {
    try {
      final fileManager = FileManagerFactory.create();
      final deckKeys = await fileManager.getSubfolders('deck_assets/');
      setState(() {
        _availableDecks = {..._availableDecks, ..._collectDeckTokens(deckKeys)};
      });
    } catch (e) {
      debugLog('Error loading available decks: $e');
    }
  }

  Future<void> _initializeServices() async {
    if (_displayName == null) return;

    _friendsService = FriendsCacheService();
    await _friendsService!.initialize(_displayName!);
    _loadFriends();
  }

  Future<bool> _selectDeck(String deckKey) async {
    try {
      final fileManager = FileManagerFactory.create();
      final jsonString = await fileManager.readJSON(deckKey);
      if (jsonString == null) {
        debugLog('Deck $deckKey not found on device.');
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_deck_key', deckKey);
      _prefs = prefs;

      final tokens = _deckKeyTokens(deckKey);
      if (!mounted) {
        _deckJsonKey = deckKey;
        _deckJson = jsonString;
        _availableDecks = {..._availableDecks, ...tokens};
        return true;
      }

      setState(() {
        _deckJsonKey = deckKey;
        _deckJson = jsonString;
        _availableDecks = {..._availableDecks, ...tokens};
      });

      return true;
    } catch (e) {
      debugLog('Error selecting deck $deckKey: $e');
      return false;
    }
  }

  Future<void> _refreshDeckSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final deckKey = prefs.getString('selected_deck_key');

    if (deckKey == null || deckKey.isEmpty) {
      if (!mounted) {
        _deckJsonKey = null;
        _deckJson = null;
        return;
      }
      setState(() {
        _deckJsonKey = null;
        _deckJson = null;
      });
      return;
    }

    await _selectDeck(deckKey);
  }

  Future<void> _loadFriends() async {
    if (_friendsService != null) {
      final friends = _friendsService!.activeFriends;
      setState(() {
        _friends = friends;
      });
    }
  }

  void _handleAuthStateChanged() {
    if (!mounted) return;
    _loadUserData(forceReconnect: true);
  }

  Future<void> _loadUserData({bool forceReconnect = false}) async {
    if (_isLoadingUserData) {
      _pendingUserDataReload = _pendingUserDataReload || forceReconnect;
      return;
    }
    _isLoadingUserData = true;

    debugLog('Loading User data...');
    try {
      _prefs = await SharedPreferences.getInstance();

      String? awsUserId = await SecureCredentialsStorage.getUserId();
      bool awsLoggedIn = await SecureCredentialsStorage.isAwsLoggedIn();
      String? guestUserId = _prefs.getString('guest_websocket_id');

      if (guestUserId == null || guestUserId.isEmpty) {
        final random = Random().nextInt(999999).toString().padLeft(6, '0');
        guestUserId = 'guest_${DateTime.now().millisecondsSinceEpoch}_$random';
        await _prefs.setString('guest_websocket_id', guestUserId);
        debugLog('Generated persistent guest ID: $guestUserId');
      }

      String? webSocketUserId;
      String? oldWebSocketUserId;

      if (awsLoggedIn && awsUserId != null && awsUserId.isNotEmpty) {
        webSocketUserId = awsUserId;
        String? lastUsedId = _prefs.getString('last_websocket_id');
        if (lastUsedId != null && lastUsedId != awsUserId) {
          oldWebSocketUserId = lastUsedId;
          debugLog('Will migrate from $oldWebSocketUserId to $awsUserId');
        }
      } else {
        webSocketUserId = guestUserId;
        String? lastUsedId = _prefs.getString('last_websocket_id');
        if (lastUsedId != null &&
            lastUsedId != guestUserId &&
            lastUsedId.startsWith('guest_')) {
          oldWebSocketUserId = lastUsedId;
        }
      }

      await _prefs.setString('last_websocket_id', webSocketUserId);

      String? displayName = _prefs.getString('display_name');
      if (displayName == null || displayName.isEmpty) {
        displayName = await _promptForDisplayName();
        if (displayName != null && displayName.isNotEmpty) {
          await _prefs.setString('display_name', displayName);
        }
      }

      String? deckJsonKey = _prefs.getString('selected_deck_key');
      String? deckJson;
      if (deckJsonKey != null && deckJsonKey.isNotEmpty) {
        try {
          final fileManager = FileManagerFactory.create();
          deckJson = await fileManager.readJSON(deckJsonKey);
        } catch (e) {
          debugLog('Failed to load deck "$deckJsonKey": $e');
        }
      }

      final previousUserId = _webSocketUserId;

      setState(() {
        _webSocketUserId = webSocketUserId;
        _oldWebSocketUserId = oldWebSocketUserId;
        _displayName = displayName;
        _deckJsonKey = deckJsonKey;
        _deckJson = deckJson;
        if (deckJsonKey != null && deckJsonKey.isNotEmpty) {
          _availableDecks = {
            ..._availableDecks,
            ..._deckKeyTokens(deckJsonKey),
          };
        }
      });

      final shouldForceReconnect = forceReconnect ||
          (previousUserId != null && previousUserId != webSocketUserId);

      if (_webSocketUserId != null && _displayName != null) {
        await _initializeServices();
        await _connectToServer(
          showSuccessMessage: false,
          forceReconnect: shouldForceReconnect,
        );
      }
    } finally {
      _isLoadingUserData = false;
      if (_pendingUserDataReload) {
        _pendingUserDataReload = false;
        unawaited(_loadUserData(forceReconnect: true));
      }
    }
  }

  void _handleRegisterError(Map<String, dynamic> msg) {
    final errorMessage = msg['message'] as String?;

    if (errorMessage != null && errorMessage.contains('already connected')) {
      _showUserIdConflictDialog();
    } else {
      _showSnackBar(
          errorMessage ?? _t('lobby.error.registrationFailed'), Colors.red);
      setState(() {
        _isConnecting = false;
        _isConnected = false;
      });
      _changeDisplayName(
        isError: true,
        errorMessage: errorMessage ?? _t('lobby.error.nameInUse'),
      );
    }
  }

  void _showUserIdConflictDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_t('lobby.dialog.conflict.title')),
        content: Text(_t('lobby.dialog.conflict.message')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _isConnecting = false;
                _isConnected = false;
              });
            },
            child: Text(_t('action.cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _forceReconnect();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(_t('lobby.dialog.conflict.force')),
          ),
        ],
      ),
    );
  }

  Future<void> _forceReconnect() async {
    debugLog('Forcing reconnect');
    await _gameService.disconnectMultiplayer();

    setState(() {
      _isConnecting = false;
      _isConnected = false;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    await _connectToServer(showSuccessMessage: true, forceReconnect: true);
  }

  Future<String?> _promptForDisplayName() async {
    final controller = TextEditingController();

    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_t('lobby.dialog.displayName.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_t('lobby.dialog.displayName.description'),
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: _t('lobby.labels.displayName'),
                hintText: _t('lobby.dialog.displayName.hint'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person),
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: 20,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: Text(_t('action.continue')),
          ),
        ],
      ),
    );
  }

  Set<String> _deckKeyTokens(String? rawKey) {
    if (rawKey == null) return {};

    final tokens = <String>{};
    void addVariant(String? value) {
      if (value == null) return;
      final cleaned = value.trim();
      if (cleaned.isEmpty) return;
      tokens.add(cleaned.toLowerCase());
    }

    final original = rawKey.replaceAll('\\', '/');
    addVariant(original);

    var base = original
        .replaceFirst(RegExp(r'^assets/'), '')
        .replaceFirst(RegExp(r'^deck_assets/'), '')
        .replaceFirst(RegExp(r'^/+'), '')
        .replaceFirst(RegExp(r'/+$'), '')
        .trim();
    addVariant(base);

    if (base.isEmpty) {
      return tokens;
    }

    final withoutJson = base.replaceAll(
      RegExp(r'\.json$', caseSensitive: false),
      '',
    );
    addVariant(withoutJson);
    addVariant('$withoutJson.json');
    addVariant('deck_assets/$withoutJson');
    addVariant('deck_assets/$withoutJson.json');
    addVariant('assets/deck_assets/$withoutJson');
    addVariant('assets/deck_assets/$withoutJson.json');

    final segments =
        withoutJson.split('/').where((segment) => segment.isNotEmpty).toList();
    if (segments.isNotEmpty) {
      for (final segment in segments) {
        addVariant(segment);
      }
      if (segments.length >= 2) {
        addVariant('${segments.first}/${segments.last}');
      }
    }

    return tokens;
  }

  Set<String> _collectDeckTokens(Iterable<String> keys) {
    final tokens = <String>{};
    for (final key in keys) {
      tokens.addAll(_deckKeyTokens(key));
    }
    return tokens;
  }

  bool _hasDeck(String? deckJsonKey) {
    if (deckJsonKey == null) return true;
    final candidates = _deckKeyTokens(deckJsonKey);
    if (candidates.isEmpty) return false;
    return candidates.any(_availableDecks.contains);
  }

  String _getDeckDisplayName(String? deckJsonKey) {
    if (deckJsonKey == null) return _t('lobby.deck.unknown');
    final parts = deckJsonKey.split('/');
    final deckName = parts.isNotEmpty ? parts.last : deckJsonKey;
    return deckName
        .split('_')
        .map((word) => word.isNotEmpty
            ? word[0].toUpperCase() + word.substring(1).toLowerCase()
            : '')
        .join(' ');
  }

  void _handleIdentityMigrated(Map<String, dynamic> msg) {
    final oldId = msg['oldUserId'] as String?;
    final newId = msg['newUserId'] as String?;
    debugLog('Identity migrated: $oldId -> $newId');
    _showSnackBar(_t('lobby.snackbar.accountLinked'), Colors.green);
    _initializeServices();
  }

  void _handleForceDisconnected(Map<String, dynamic> msg) {
    final message = msg['message'] as String?;

    setState(() {
      _isConnecting = false;
      _isConnected = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_t('lobby.dialog.sessionDisconnected.title')),
        content:
            Text(message ?? _t('lobby.dialog.sessionDisconnected.message')),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('action.ok')),
          ),
        ],
      ),
    );
  }

  void _handleInviteResponse(Map<String, dynamic> msg) {
    debugLog('[LobbyScreen] 🎯 _handleInviteResponse called');
    debugLog(
      '[LobbyScreen] Invite response - status: ${msg['status']}, responder: ${msg['responder']}, inviteId: ${msg['inviteId']}',
    );
    final status = msg['status'] as String;
    final responder = msg['responder'] as String?;
    final inviteId = msg['inviteId'];

    if (inviteId is String) {
      setState(() {
        _pendingInvites.removeWhere((invite) => invite['id'] == inviteId);
      });
    }

    if (status == 'accepted') {
      _showSnackBar(
          _f('lobby.snackbar.inviteAccepted', {'name': _playerName(responder)}),
          Colors.green);
    } else {
      _showSnackBar(
          _f('lobby.snackbar.inviteDeclined', {'name': _playerName(responder)}),
          Colors.orange);
    }
  }

  Future<void> _handleGameReady(Map<String, dynamic> msg) async {
    final seed = msg['seed'] as int?;
    final deckJsonKey = msg['deckJsonKey'] as String?;
    final playerPosition = msg['playerPosition'] as String?;
    final opponentId = msg['opponentId'] as String?;
    final opponentName = msg['opponentName'] as String?;

    unawaited(_maybeUpdateFriendName(opponentId, opponentName));

    if (deckJsonKey != null && deckJsonKey.isNotEmpty) {
      final hasDeck = _hasDeck(deckJsonKey);
      if (hasDeck && deckJsonKey != _deckJsonKey) {
        final selected = await _selectDeck(deckJsonKey);
        if (!selected) {
          _showSnackBar(
              _f('lobby.snackbar.deckLoadFailed', {'deck': deckJsonKey}),
              Colors.red);
          return;
        }
      } else if (!hasDeck) {
        _showSnackBar(_f('lobby.snackbar.deckMissing', {'deck': deckJsonKey}),
            Colors.orange);
        return;
      }
    }

    await Navigator.pushNamed(
      context,
      AppRoutes.game,
      arguments: {
        'gameMode': 'friend',
        'seed': seed,
        'playerPosition': playerPosition,
        'opponentId': opponentId,
        'player1Name': _displayName,
        'player2Name': msg['opponentName'],
        'jsonKey': deckJsonKey ?? _deckJsonKey,
        'deckJson': _deckJson,
      },
    );
  }

  void _handleUserSearchResult(Map<String, dynamic> msg) {
    final found = msg['found'] as bool? ?? false;
    final userId = msg['userId'] as String?;
    final userName = msg['userName'] as String?;
    final searchQuery = msg['searchQuery'] as String?;
    final canSaveFriend =
        msg['isRegisteredUser'] as bool? ?? _canSaveFriend(userId);

    if (found && userId != null && userName != null) {
      _showAddFriendDialog(userId, userName, canSaveFriend: canSaveFriend);
    } else {
      _showSnackBar(
          _f('lobby.snackbar.userNotFound',
              {'query': searchQuery ?? _t('lobby.player.unknown')}),
          Colors.orange);
    }
  }

  void _showInviteDialog(Map<String, dynamic> invite) {
    final deckJsonKey = invite['deckJsonKey'] as String?;
    final hasDeck = _hasDeck(deckJsonKey);
    final deckName = _getDeckDisplayName(deckJsonKey);
    final fromName = _playerName(invite['fromUserName'] as String?);
    final cardCount = invite['deckCardCount']?.toString() ?? '-';
    final willAutoSwitch = hasDeck &&
        deckJsonKey != null &&
        deckJsonKey.isNotEmpty &&
        deckJsonKey != _deckJsonKey;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_t('lobby.dialog.invite.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _f('lobby.dialog.invite.summary', {'name': fromName}),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  hasDeck ? Icons.check_circle : Icons.warning,
                  color: hasDeck ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _f('lobby.dialog.invite.deck', {'deck': deckName}),
                    style: TextStyle(
                      fontSize: 14,
                      color: hasDeck ? Colors.black87 : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            if (willAutoSwitch) ...[
              const SizedBox(height: 8),
              Text(
                _t('lobby.dialog.invite.autoSwitch'),
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
            if (!hasDeck) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  await Navigator.pushNamed(context, AppRoutes.deck_choice);
                  await _refreshDeckSelection();
                },
                icon: const Icon(Icons.download, size: 16),
                label: Text(_t('lobby.dialog.invite.getDeck')),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.orange,
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _f('lobby.dialog.invite.cards', {'count': cardCount}),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _respondToInvite(invite['id'], false);
            },
            child: Text(_t('action.decline')),
          ),
          ElevatedButton(
            onPressed: hasDeck
                ? () async {
                    Navigator.pop(context);
                    await _respondToInvite(invite['id'], true);
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: hasDeck ? Colors.green : Colors.grey,
            ),
            child: Text(_t('action.accept')),
          ),
        ],
      ),
    );
  }

  Future<void> _maybeUpdateFriendName(
      String? userId, String? updatedName) async {
    if (_friendsService == null ||
        userId == null ||
        updatedName == null ||
        updatedName.isEmpty) {
      return;
    }

    final current = _friendsService!.getFriend(userId);
    if (current != null && current.userName != updatedName) {
      final success =
          await _friendsService!.updateFriendName(userId, updatedName);
      if (success) {
        await _loadFriends();
      }
    }
  }

  Future<bool> _syncDeckWithInvite(Map<String, dynamic> invite) async {
    final deckJsonKey = invite['deckJsonKey'] as String?;
    if (deckJsonKey == null || deckJsonKey.isEmpty) {
      return true;
    }

    if (!_hasDeck(deckJsonKey)) {
      _showSnackBar(
        _f('lobby.snackbar.deckMissing',
            {'deck': _getDeckDisplayName(deckJsonKey)}),
        Colors.orange,
      );
      return false;
    }

    if (_deckJsonKey == deckJsonKey) {
      return true;
    }

    final selected = await _selectDeck(deckJsonKey);
    if (!selected) {
      _showSnackBar(
        _f('lobby.snackbar.deckLoadFailed',
            {'deck': _getDeckDisplayName(deckJsonKey)}),
        Colors.red,
      );
    }
    return selected;
  }

  Future<void> _respondToInvite(String inviteId, bool accept) async {
    debugLog("[Lobby Screen] - _respondToInvite $inviteId");
    final invite = _pendingInvites.firstWhere(
      (inv) => inv['id'] == inviteId,
      orElse: () => {},
    );
    debugLog('[Lobby Screen] - Invite: ${invite.isNotEmpty}');
    if (accept && invite.isNotEmpty) {
      final synced = await _syncDeckWithInvite(invite);
      if (!synced) {
        debugLog('[Lobby Screen] - Deck sync failed, aborting accept');
        return;
      }
      final fromUserId = invite['fromUserId'] as String?;
      final fromUserName = invite['fromUserName'] as String?;
      final fromRegistered =
          invite['fromUserIsRegistered'] as bool? ?? _canSaveFriend(fromUserId);
      debugLog(
          '[Lobby Screen] - fromUserId: $fromUserId}, fromUserName, $fromUserName');

      if (fromUserId != null &&
          fromUserName != null &&
          _friendsService != null &&
          fromRegistered) {
        final added =
            await _friendsService!.addFriend(fromUserId, fromUserName);
        if (added) {
          await _loadFriends();
        }
      }
    }
    debugLog('call game service to respond to invite');
    try {
      await _gameService.respondToInvite(inviteId: inviteId, accept: accept);
    } catch (e) {
      _showSnackBar(_t('lobby.snackbar.respondFailed'), Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _copyDisplayNameToClipboard() {
    if (_displayName != null) {
      Clipboard.setData(ClipboardData(text: _displayName!));
      _showSnackBar(_f('lobby.snackbar.displayCopied', {'name': _displayName!}),
          Colors.green);
    }
  }

  void _showFindFriendDialog() {
    final searchController = _findFriendController;
    searchController.clear();
    void submitSearch(BuildContext dialogContext) {
      final displayName = searchController.text.trim();
      if (displayName.isNotEmpty) {
        Navigator.of(dialogContext).pop();
        _searchForUser(displayName);
      }
    }

    showDialog(
      context: context,
      builder: (dialogContext) {
        final mediaQuery = MediaQuery.of(dialogContext);
        final bottomInset = mediaQuery.viewInsets.bottom;
        return MediaQuery(
          data: mediaQuery.removeViewInsets(removeBottom: true),
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: AlertDialog(
              scrollable: true,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              title: Text(_t('lobby.findFriend.title')),
              content: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _t('lobby.findFriend.description'),
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        labelText: _t('lobby.labels.displayName'),
                        hintText: _t('lobby.findFriend.hint'),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      textCapitalization: TextCapitalization.words,
                      autocorrect: false,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => submitSearch(dialogContext),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t('lobby.findFriend.note'),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(_t('action.cancel')),
                ),
                ElevatedButton(
                  onPressed: () => submitSearch(dialogContext),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_t('action.search')),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _searchForUser(String displayName) {
    if (!_isConnected) {
      _showSnackBar(_t('lobby.snackbar.requiresConnection'), Colors.red);
      return;
    }

    try {
      _gameService.searchUser(displayName);
      _showSnackBar(
          _f('lobby.snackbar.searching', {'name': displayName}), Colors.blue);
    } catch (e) {
      _showSnackBar(_t('lobby.snackbar.searchFailed'), Colors.red);
    }
  }

  bool _canSaveFriend(String? userId) {
    return UserIdentityUtils.isRegisteredUserId(userId);
  }

  void _showAddFriendDialog(String userId, String userName,
      {bool canSaveFriend = true}) {
    if (_friendsService != null && _friendsService!.hasFriend(userId)) {
      _showSnackBar(
          _f('lobby.snackbar.friendExists', {'name': userName}), Colors.orange);
      _sendGameInvite(userId, userName);
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_t('lobby.friendFound.title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_f('lobby.friendFound.message', {'name': userName})),
            if (!canSaveFriend) ...[
              const SizedBox(height: 12),
              Text(
                _t('lobby.friendFound.temporaryNotice'),
                style: const TextStyle(fontSize: 13, color: Colors.orange),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('action.cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              if (_friendsService != null && canSaveFriend) {
                final added =
                    await _friendsService!.addFriend(userId, userName);
                if (added) {
                  await _loadFriends();
                  _showSnackBar(
                      _f('lobby.snackbar.friendAdded', {'name': userName}),
                      Colors.green);
                }
              } else if (!canSaveFriend) {
                _showSnackBar(
                    _t('lobby.snackbar.friendRegisteredOnly'), Colors.orange);
              }

              await _sendGameInvite(userId, userName);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(canSaveFriend
                ? _t('lobby.friendFound.addInvite')
                : _t('lobby.friendFound.inviteOnly')),
          ),
        ],
      ),
    );
  }

  Future<void> _sendGameInvite(String? friendUserId, String friendName) async {
    if (!_isConnected) {
      _showSnackBar(_t('lobby.snackbar.requiresConnection'), Colors.red);
      return;
    }

    if (_deckJsonKey == null) {
      await _refreshDeckSelection();
    }

    if (_deckJsonKey == null) {
      _showSnackBar(_t('lobby.snackbar.deckRequired'), Colors.orange);
      await Navigator.pushNamed(context, AppRoutes.deck_choice);
      await _refreshDeckSelection();
      if (_deckJsonKey == null) {
        return;
      }
    }

    if (_displayName != null && _webSocketUserId != null) {
      try {
        int? deckCardCount;
        if (_deckJson != null) {
          try {
            final decoded = json.decode(_deckJson!);
            final cards = decoded['cards'] as List<dynamic>?;
            deckCardCount = cards?.length;
          } catch (e) {
            debugLog('Failed to parse deck card count: $e');
          }
        }

        await _gameService.sendInvite(
          fromUserId: _webSocketUserId,
          fromUserName: _displayName!,
          toUserId: friendUserId,
          toUserName: friendName,
          deckJsonKey: _deckJsonKey!,
          deckCardCount: deckCardCount,
        );
        _showSnackBar(
            _f('lobby.snackbar.inviteSent', {'name': friendName}), Colors.blue);
      } catch (e) {
        _showSnackBar(_t('lobby.snackbar.inviteFailed'), Colors.red);
      }
    }
  }

  Future<void> _changeDisplayName(
      {bool isError = false, String? errorMessage}) async {
    final controller = TextEditingController(text: _displayName);

    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: !isError,
      builder: (context) => AlertDialog(
        title: Text(isError ? 'Display Name Taken' : 'Change Display Name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (errorMessage != null) ...[
              Text(errorMessage, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              maxLength: 20,
            ),
          ],
        ),
        actions: [
          if (!isError)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_t('action.cancel')),
            ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: Text(isError
                ? _t('lobby.dialog.displayName.setNew')
                : _t('action.save')),
          ),
        ],
      ),
    );

    if (newName != null && newName != _displayName) {
      await _prefs.setString('display_name', newName);

      setState(() {
        _displayName = newName;
      });

      // Update GameService registration without disconnecting
      try {
        await _gameService.updateDisplayName(newName);
        _showSnackBar(_f('lobby.snackbar.displayUpdated', {'name': newName}),
            Colors.green);
      } catch (e) {
        _showSnackBar(_t('lobby.snackbar.displayUpdateFailed'), Colors.red);
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 1) {
      return _t('lobby.date.today');
    } else if (difference.inDays < 7) {
      return _f('lobby.date.daysAgo', {'days': difference.inDays.toString()});
    } else {
      return _f('lobby.date.long', {
        'day': date.day.toString(),
        'month': date.month.toString(),
        'year': date.year.toString(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileName = _displayName ?? _t('lobby.profile.notSet');
    final profileLabel = _f('lobby.profile.displayName', {'name': profileName});
    final connectionLabel = _isConnected
        ? _t('lobby.connection.connected')
        : _isConnecting
            ? _t('lobby.connection.connecting')
            : _t('lobby.connection.disconnected');
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('lobby.header.title')),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Display Name Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          profileLabel,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      if (_displayName != null)
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: _t('lobby.profile.copyTooltip'),
                          onPressed: _copyDisplayNameToClipboard,
                        ),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: _t('lobby.profile.changeTooltip'),
                        onPressed: () => _changeDisplayName(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Connection Status Card
              Card(
                color: _isConnected ? Colors.green.shade50 : Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isConnected ? Icons.wifi : Icons.wifi_off,
                            color: _isConnected ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              connectionLabel,
                              style: TextStyle(
                                color: _isConnected
                                    ? Colors.green.shade900
                                    : Colors.red.shade900,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!_isConnected && !_isConnecting) ...[
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _connectToServer(),
                          icon: const Icon(Icons.refresh),
                          label: Text(_t('lobby.connection.connectButton')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                      if (_isConnecting) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Text(_t('lobby.connection.connectingLabel')),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              if (_isConnected) ...[
                const SizedBox(height: 16),

                // Find Friend Button
                ElevatedButton.icon(
                  onPressed: _showFindFriendDialog,
                  icon: const Icon(Icons.person_search),
                  label: Text(_t('lobby.findFriend.button')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 16, horizontal: 24),
                  ),
                ),

                const SizedBox(height: 8),

                // Help text
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _t('lobby.findFriend.helper'),
                          style: TextStyle(
                              fontSize: 13, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Friends List Section
                if (_friends.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_t('lobby.friends.title'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _friends.length,
                            itemBuilder: (context, index) {
                              final friend = _friends[index];
                              return Card(
                                child: ListTile(
                                  leading: const CircleAvatar(
                                      child: Icon(Icons.person)),
                                  title: Text(friend.userName),
                                  subtitle: Text(_f('lobby.friends.added',
                                      {'date': _formatDate(friend.addedAt)})),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: () async => _sendGameInvite(
                                            friend.userId, friend.userName),
                                        icon: const Icon(Icons.games, size: 16),
                                        label: Text(_t('lobby.friends.play')),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      PopupMenuButton(
                                        itemBuilder: (context) => [
                                          PopupMenuItem(
                                            child: Row(
                                              children: [
                                                const Icon(Icons.block,
                                                    size: 16,
                                                    color: Colors.orange),
                                                const SizedBox(width: 8),
                                                Text(_t('lobby.friends.block')),
                                              ],
                                            ),
                                            onTap: () async {
                                              await _friendsService!
                                                  .blockFriend(friend.userId);
                                              await _loadFriends();
                                              _showSnackBar(
                                                  _t('lobby.snackbar.friendBlocked'),
                                                  Colors.orange);
                                            },
                                          ),
                                          PopupMenuItem(
                                            child: Row(
                                              children: [
                                                const Icon(Icons.delete,
                                                    size: 16,
                                                    color: Colors.red),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _t('lobby.friends.remove'),
                                                  style: const TextStyle(
                                                      color: Colors.red),
                                                ),
                                              ],
                                            ),
                                            onTap: () async {
                                              await _friendsService!
                                                  .removeFriend(friend.userId);
                                              await _loadFriends();
                                              _showSnackBar(
                                                  _t('lobby.snackbar.friendRemoved'),
                                                  Colors.red);
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(Icons.people_outline,
                              size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          Text(
                            _t('lobby.friends.emptyTitle'),
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _t('lobby.friends.emptySubtitle'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // Pending Invites
                if (_pendingInvites.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_t('lobby.pendingInvites.title'),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _pendingInvites.length,
                            itemBuilder: (context, index) {
                              final invite = _pendingInvites[index];
                              final deckJsonKey =
                                  invite['deckJsonKey'] as String?;
                              final hasDeck = _hasDeck(deckJsonKey);
                              final deckName = _getDeckDisplayName(deckJsonKey);

                              return Card(
                                color: hasDeck ? null : Colors.orange.shade50,
                                child: ListTile(
                                  leading: Icon(
                                    hasDeck ? Icons.mail : Icons.warning,
                                    color:
                                        hasDeck ? Colors.blue : Colors.orange,
                                  ),
                                  title: Text(_f('lobby.pendingInvites.from', {
                                    'name': _playerName(
                                        invite['fromUserName'] as String?)
                                  })),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            hasDeck
                                                ? Icons.check_circle
                                                : Icons.error,
                                            size: 16,
                                            color: hasDeck
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              _f('lobby.pendingInvites.deck',
                                                  {'deck': deckName}),
                                              style: TextStyle(
                                                color: hasDeck
                                                    ? null
                                                    : Colors.orange.shade900,
                                                fontWeight: hasDeck
                                                    ? null
                                                    : FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (!hasDeck)
                                        GestureDetector(
                                          onTap: () {
                                            Navigator.pushNamed(
                                              context,
                                              AppRoutes.deck_choice,
                                            ).then(
                                                (_) => _refreshDeckSelection());
                                          },
                                          child: Text(
                                            _t('lobby.pendingInvites.getDeck'),
                                            style: TextStyle(
                                              color: Colors.orange.shade700,
                                              decoration:
                                                  TextDecoration.underline,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextButton(
                                        onPressed: () => _respondToInvite(
                                            invite['id'], false),
                                        child: Text(_t('action.decline')),
                                      ),
                                      ElevatedButton(
                                        onPressed: hasDeck
                                            ? () => _respondToInvite(
                                                invite['id'], true)
                                            : null,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: hasDeck
                                              ? Colors.green
                                              : Colors.grey,
                                        ),
                                        child: Text(_t('action.accept')),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

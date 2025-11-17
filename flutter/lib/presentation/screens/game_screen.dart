import 'package:flutter/material.dart' hide Card;
import 'package:quick_click_match/domain/entities/card.dart';
import 'dart:math';
import 'dart:typed_data';

import '../../domain/entities/player_deck.dart';
import '../../domain/entities/deck.dart';
import 'dart:async';
import 'dart:convert';
import 'screens_factory.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../utils/deck_config.dart';
import 'package:quick_click_match/infra/platform/file_manager_factory.dart';
import 'package:quick_click_match/presentation/widgets/image_data.dart';
import 'package:quick_click_match/services/game_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:quick_click_match/constants/app_routes.dart';
import 'package:quick_click_match/services/localization_service.dart';
import 'package:quick_click_match/utils/debug_logger.dart';
import 'package:quick_click_match/services/sound_service.dart';
import 'package:quick_click_match/utils/app_logger.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => ScreenFactory.createGameScreenState();
}

abstract class GameScreenState extends State<GameScreen> {
  late Deck _deck;
  String? _deckJsonKey;
  String? _deckJson;
  late DeckConfig deckConfig;
  PlayerDeck? player1Deck; // Bottom card (or player's deck)
  PlayerDeck? player2Deck; // Top card (or opponent's deck)
  int? correctSymbolId;
  String gameMode = 'train';
  String player1Name = LocalizationService.instance.t('game.player.you');
  String player2Name = LocalizationService.instance.t('game.player.computer');
  Timer? _computerTimer;
  final Random _random = Random();
  bool isDeckLoaded = false;
  bool _hasInitialized = false;

  // Friend mode variables - now using GameService instead of WebSocket directly
  final GameService _gameService = GameService();
  StreamSubscription? _messageSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<bool>? _registrationSubscription;
  int? _seedOverride;
  String? _playerPosition; // 'A' or 'B'
  String? _opponentId;

  // Click tracking - unified for all modes
  int? clickedSymbolId;
  int? _clickedTimestamp;
  bool isPlayer1Card = true; // Which card was clicked
  bool isCorrectClick = false;
  bool _waitingForPeerAdmit = false; // Friend mode: waiting for peer
  int? _peerClickSymbolId;

  // Ready state management (used by friend mode, always true for others)
  bool isPlayer1Ready = true;
  bool isPlayer2Ready = true;
  bool showCards = true;

  // Disposal tracking
  bool _isDisposed = false;
  bool nextCardsAreReady = false;

  // Image loading tracking
  final Set<String> _loadedImagePaths = {};
  final Set<String> _loadingImagePaths = {};

  // Result display state
  bool showingResult = false;
  bool wasWinner = false;
  bool isLeavingGame = false;
  bool _connectionLossHandled = false;

  // Computer reaction tracking
  String computerLevel = 'rookie';
  int _computerReactionTotalMs = 0;
  int _computerReactionRounds = 0;
  int? _lastComputerReactionMs;
  int? _pendingComputerTimerMs;

  @override
  void initState() {
    super.initState();
    _loadAndInitialize();
  }

  Future<void> _loadAndInitialize() async {
    await _loadDeck();
    await _initializeGame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_hasInitialized) return;
    _hasInitialized = true;

    final args = ModalRoute.of(context)?.settings.arguments;

    if (args == null) {
      gameMode = 'train';
      return;
    }

    if (args is String) {
      gameMode = args;
      if (gameMode == 'computer') {
        _startComputerTimer();
      }
      return;
    }

    if (args is Map) {
      final argKeys = args.keys
          .map((dynamic key) => key.toString())
          .toList(growable: false);
      debugLog('[GameScreen] Route arguments keys: $argKeys');
      _handleMapArguments(args);
    }
  }

  void _handleMapArguments(Map args) {
    gameMode = args['gameMode'] ?? 'train';
    debugLog('[GameScreen] Setting gameMode to: $gameMode');

    // Extract player names if provided
    player1Name = args['player1Name'] ??
        LocalizationService.instance.t('game.player.you');
    player2Name = args['player2Name'] ??
        LocalizationService.instance.t('game.player.computer');

    if (gameMode == 'computer') {
      final levelArg = args['computerLevel'];
      if (levelArg is String && levelArg.isNotEmpty) {
        computerLevel = levelArg;
      } else {
        computerLevel = 'rookie';
      }
    }

    if (gameMode == 'friend') {
      _seedOverride = args['seed'] as int?;
      _playerPosition = args['playerPosition'] as String?;
      _opponentId = args['opponentId'] as String?;

      debugLog(
          '[GameScreen] Friend mode data - seed: $_seedOverride, position: $_playerPosition, opponent: $_opponentId');

      _setupFriendMode();
    } else if (gameMode == 'computer') {
      _startComputerTimer();
    }
  }

  void _setupFriendMode() {
    debugLog('[GameScreen] Setting up friend mode listeners');
    _monitorFriendConnection();
    _verifyFriendConnection();
    _setupMultiplayerListeners();
  }

  void _monitorFriendConnection() {
    _connectionSubscription?.cancel();
    _connectionSubscription =
        _gameService.connectionState.listen((bool connected) {
      if (!connected) {
        debugLog('[GameScreen] Connection lost during game');
        _handleGameConnectionLost();
      }
    });

    _registrationSubscription?.cancel();
    _registrationSubscription =
        _gameService.registrationState.listen((bool registered) {
      if (!registered) {
        debugLog('[GameScreen] Registration lost during game');
        _handleGameConnectionLost();
      }
    });
  }

  void _verifyFriendConnection() {
    if (!_gameService.isSocketConnected || !_gameService.isRegistered) {
      debugLog('[GameScreen] Friend mode started without active connection');
      _handleGameConnectionLost();
    }
  }

  void _setupMultiplayerListeners() {
    _messageSubscription?.cancel();

    debugLog('[GameScreen] Setting up GameService message listeners');
    _messageSubscription = _gameService.messages.listen((msg) {
      if (_isDisposed || !mounted) return;

      debugLog(
          '[GameScreen] Received message: ${msg['type']} - I am ready $isPlayer1Ready, opponent ready: $isPlayer2Ready');

      switch (msg['type']) {
        case 'click':
          _handlePeerClick(msg);
          break;
        case 'ack_click':
          _handleAckClickMsg(msg);
          break;
        case 'peer_ready_to_draw':
          _handlePeerReadyToDraw();
          break;
        case 'peer_left':
        case 'game_ended':
          _showPeerLeftDialog();
          break;
      }
    });
  }

  void _handleGameConnectionLost() {
    if (_connectionLossHandled || _isDisposed) return;
    _connectionLossHandled = true;
    _safeSetState(() {
      isLeavingGame = true;
    });

    if (gameMode == 'friend') {
      _gameService.leavingGame();
    }

    if (!mounted) {
      return;
    }

    final l10n = LocalizationService.instance;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.t('game.connectionLost.title')),
        content: Text(l10n.t('game.connectionLost.message')),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Text(l10n.t('action.ok')),
          ),
        ],
      ),
    );
  }

  void _safeSetState(VoidCallback callback) {
    if (!_isDisposed && mounted) {
      setState(callback);
    }
  }

  Future<void> _loadDeck() async {
    debugLog('[GameScreen] _loadDeck called');
    if (_isDisposed) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _deckJsonKey = prefs.getString('selected_deck_key');
      debugLog('_deckJsonKey: $_deckJsonKey');
      if (_deckJsonKey == null || _deckJsonKey!.isEmpty) {
        throw StateError(
            'No deck selected. Please select a deck before starting a game.');
      }

      final fileManager = FileManagerFactory.create();
      _deckJson = await fileManager.readJSON(_deckJsonKey!);

      if (_deckJson == null) {
        throw StateError(
            'Could not load the selected deck. Please download it again.');
      }

      final Map<String, dynamic> jsonData = json.decode(_deckJson!);
      deckConfig = DeckConfig.fromJson(jsonData);
      _deck = Deck.fromJson(jsonData);

      if (_isDisposed) return;

      _safeSetState(() {
        isDeckLoaded = true;
      });

      debugLog(
          '[GameScreen] Deck structure loaded, ready to load images on demand');
    } catch (e, stack) {
      debugLog('[GameScreen] Error in _loadDeck: $e - $stack');
      if (!_isDisposed) {
        if (e is StateError && e.message.contains('No deck selected')) {
          _showErrorDialog(
            'You need to choose a deck before starting a game.',
            actionLabel: 'Choose Deck',
            onAction: () {
              Navigator.of(context).pushReplacementNamed(AppRoutes.deck_choice);
            },
          );
        } else if (e is StateError &&
            e.message.contains('Could not load the selected deck')) {
          _showErrorDialog(
            'We could not load your selected deck. Please download it again.',
            actionLabel: 'Choose Deck',
            onAction: () {
              Navigator.of(context).pushReplacementNamed(AppRoutes.deck_choice);
            },
          );
        } else {
          _showErrorDialog('Failed to load deck: $e');
        }
      }
    }
  }

  Future<void> _loadVisibleCardImages() async {
    if (_isDisposed || player1Deck == null || player2Deck == null) return;

    debugLog('[GameScreen] Loading visible card images...');

    final cardsToLoad = <Card>[
      player1Deck!.topCard,
      player2Deck!.topCard,
    ];

    await Future.wait(
      cardsToLoad.map((card) => _loadCardImage(card)),
    );

    debugLog('[GameScreen] Visible card images loaded');
  }

  Future<void> _loadCardImage(Card card) async {
    if (_isDisposed) return;

    final cardImageData = deckConfig.cardImages[card.cardId];
    if (cardImageData == null) {
      debugLog('[GameScreen] No image data for card ${card.cardId}');
      return;
    }

    await _loadSingleImage(cardImageData);

    await Future.wait(
      card.symbolIds.map((symbolId) async {
        final symbolImageData = deckConfig.cardImages[symbolId.toString()];
        if (symbolImageData != null) {
          await _loadSingleImage(symbolImageData);
        }
      }),
    );

    debugLog('[GameScreen] Completed loading card ${card.cardId}');
  }

  Future<void> _loadSingleImage(ImageData imageData) async {
    if (_isDisposed) return;

    if (_loadedImagePaths.contains(imageData.src)) {
      return;
    }

    if (_loadingImagePaths.contains(imageData.src)) {
      return;
    }

    if (imageData.bytes != null) {
      _loadedImagePaths.add(imageData.src);
      return;
    }

    _loadingImagePaths.add(imageData.src);
    debugLog('[GameScreen] Starting to load image: ${imageData.src}');

    try {
      Uint8List bytes;
      final fileManager = FileManagerFactory.create();

      if (deckConfig.inAssets) {
        final String path = imageData.src.startsWith('/')
            ? imageData.src.substring(1)
            : imageData.src;
        final ByteData byteData = await rootBundle.load(path);
        bytes = byteData.buffer.asUint8List();
      } else {
        final logMessage =
            '[GameScreen] Storage deck image load via FileManager: "${imageData.src}"';
        debugLog(logMessage);
        // ignore: avoid_print
        debugLog(logMessage);
        final rawData = await fileManager.readImage(imageData.src);
        bytes = Uint8List.fromList(rawData);
      }

      imageData.bytes = bytes;
      _loadedImagePaths.add(imageData.src);
      _loadingImagePaths.remove(imageData.src);

      debugLog('[GameScreen] Successfully loaded image: ${imageData.src}');

      if (mounted && !_isDisposed) {
        setState(() {});
      }
    } catch (e) {
      debugLog('[GameScreen] Error loading image ${imageData.src}: $e');
      _loadingImagePaths.remove(imageData.src);
    }
  }

  void _preloadUpcomingCards() {
    if (_isDisposed || player1Deck == null || player2Deck == null) return;

    final upcomingCards = <Card>[];

    if (player1Deck!.cards.length > 1) {
      upcomingCards.add(player1Deck!.cards[1]);
      if (player1Deck!.cards.length > 2) {
        upcomingCards.add(player1Deck!.cards[2]);
      }
    }

    if (player2Deck!.cards.length > 1) {
      upcomingCards.add(player2Deck!.cards[1]);
      if (player2Deck!.cards.length > 2) {
        upcomingCards.add(player2Deck!.cards[2]);
      }
    }

    for (final card in upcomingCards) {
      _loadCardImage(card);
    }
    setState(() => nextCardsAreReady = true);
  }

  Future<void> _initializeGame() async {
    debugLog('[GameScreen] _initializeGame called for gameMode $gameMode');

    if (_isDisposed || !isDeckLoaded) {
      debugLog('[GameScreen] Cannot initialize - disposed or deck not loaded');
      return;
    }

    final cards = List<Card>.from(_deck.cards);
    debugLog('[GameScreen] Initializing with ${cards.length} cards');

    if (gameMode == 'computer') {
      _computerReactionTotalMs = 0;
      _computerReactionRounds = 0;
      _lastComputerReactionMs = null;
      _pendingComputerTimerMs = null;
    }

    if (gameMode == 'friend') {
      if (_seedOverride == null || _playerPosition == null) {
        debugLog(
            '[GameScreen] ERROR: Missing seed or position for friend mode!');
        return;
      }

      final Random seededRandom = Random(_seedOverride!);
      cards.shuffle(seededRandom);

      debugLog(
          '[GameScreen] Using seed $_seedOverride for deterministic shuffle');

      final firstHalf = cards.sublist(0, cards.length ~/ 2);
      final secondHalf = cards.sublist(cards.length ~/ 2);

      if (_playerPosition == 'A') {
        player1Deck = PlayerDeck(firstHalf);
        player2Deck = PlayerDeck(secondHalf);
      } else {
        player1Deck = PlayerDeck(secondHalf);
        player2Deck = PlayerDeck(firstHalf);
      }

      debugLog(
          '[GameScreen] My deck first card: ${player1Deck!.topCard.cardId}');
      debugLog(
          '[GameScreen] Opponent deck first card: ${player2Deck!.topCard.cardId}');

      // Friend mode uses ready mechanism
      isPlayer1Ready = false;
      isPlayer2Ready = false;
      showCards = false;
    } else {
      cards.shuffle(_random);
      player1Deck = PlayerDeck(cards.sublist(0, cards.length ~/ 2));
      player2Deck = PlayerDeck(cards.sublist(cards.length ~/ 2));

      // Computer/train/hotseat always ready
      isPlayer1Ready = true;
      isPlayer2Ready = true;
      showCards = true;

      debugLog('I am ready $isPlayer1Ready, opponent ready: $isPlayer2Ready');
    }

    // Reset click state
    clickedSymbolId = null;
    _clickedTimestamp = null;
    isPlayer1Card = true;
    isCorrectClick = false;
    _waitingForPeerAdmit = false;
    _peerClickSymbolId = null;
    showingResult = false;
    wasWinner = false;

    _setCorrectSymbolId();
    _loadVisibleCardImages();
    _preloadUpcomingCards();

    debugLog('[GameScreen] _initializeGame completed successfully');
  }

  void _startComputerTimer() {
    if (_isDisposed) return;

    _computerTimer?.cancel();

    final range = _computerReactionRange();
    final rangeSpan = (range.max - range.min).clamp(1, 10000).toInt();
    final randomTime = range.min + _random.nextInt(rangeSpan + 1);
    debugLog(
        '[GameScreen] Computer timer set for ${randomTime / 1000} seconds at level $computerLevel');

    _lastComputerReactionMs = randomTime;
    _pendingComputerTimerMs = randomTime;

    _computerTimer = Timer(Duration(milliseconds: randomTime), () {
      if (!_isDisposed && mounted && !showingResult) {
        _handleComputerWin();
      }
    });
  }

  void _handleComputerWin() {
    if (_isDisposed || showingResult) return;

    debugLog('[GameScreen] Computer found the answer');

    if (_pendingComputerTimerMs != null) {
      _computerReactionTotalMs += _pendingComputerTimerMs!;
      _computerReactionRounds += 1;
      _pendingComputerTimerMs = null;
    }

    // Computer clicked correct symbol on their card
    _safeSetState(() {
      clickedSymbolId = correctSymbolId;
      _clickedTimestamp = DateTime.now().millisecondsSinceEpoch;
      isPlayer1Card = false; // Computer is player 2
      isCorrectClick = true;
    });

    _handleRoundResult(winnerIsPlayer1: false);
  }

  _ReactionRange _computerReactionRange() {
    switch (computerLevel) {
      case 'legend':
        return const _ReactionRange(6000, 10800);
      case 'ace':
        return const _ReactionRange(10200, 15600);
      case 'rookie':
      default:
        return const _ReactionRange(15600, 23400);
    }
  }

  String get computerLevelDisplay {
    final l10n = LocalizationService.instance;
    switch (computerLevel) {
      case 'legend':
        return l10n.t('game.computer.level.legend');
      case 'ace':
        return l10n.t('game.computer.level.ace');
      default:
        return l10n.t('game.computer.level.rookie');
    }
  }

  double get computerAverageReactionSeconds {
    if (_computerReactionRounds == 0) return 0;
    return _computerReactionTotalMs / (_computerReactionRounds * 1000.0);
  }

  int get computerReactionRounds => _computerReactionRounds;

  double? get lastComputerReactionSeconds => _lastComputerReactionMs != null
      ? _lastComputerReactionMs! / 1000.0
      : null;

  void _setCorrectSymbolId() {
    if (_isDisposed || player1Deck == null || player2Deck == null) return;

    try {
      final card1 = player1Deck!.topCard;
      final card2 = player2Deck!.topCard;
      final ids1 = card1.symbolIds.toSet();
      final ids2 = card2.symbolIds.toSet();
      final intersection = ids1.intersection(ids2);
      correctSymbolId = intersection.isNotEmpty ? intersection.first : null;
      debugLog('[GameScreen] Correct symbol id is $correctSymbolId');
    } catch (e, stack) {
      debugLog('[GameScreen] Error in _setCorrectSymbolId: $e - $stack');
    }
  }

  // UNIFIED CLICK HANDLER
  void onSymbolClick(int symbolId, {bool isPlayer1Click = true}) {
    debugLog(
        '[GameScreen] onSymbolClick: symbolId=$symbolId, isPlayer1Click=$isPlayer1Click, gameMode=$gameMode');

    if (_isDisposed || showingResult) {
      debugLog('[GameScreen] Ignoring click - showing result or disposed');
      return;
    }

    SoundService.instance.playCardFlip();

    // Store click information
    _safeSetState(() {
      clickedSymbolId = symbolId;
      _clickedTimestamp = DateTime.now().millisecondsSinceEpoch;
      isPlayer1Card = isPlayer1Click;
      isCorrectClick = (symbolId == correctSymbolId);
    });

    debugLog(
        '[GameScreen] Click stored - correct: $isCorrectClick, correctSymbol: $correctSymbolId');

    // Route to appropriate handler
    switch (gameMode) {
      case 'computer':
      case 'train':
        _handleComputerClick();
        break;
      case 'friend':
        _handleFriendClick();
        break;
      case 'hotseat':
        _handleHotSeatClick();
        break;
    }
  }

  void _handleComputerClick() {
    debugLog('[GameScreen] handleComputerClick - isCorrect: $isCorrectClick');

    // Cancel computer timer if running
    _computerTimer?.cancel();
    _pendingComputerTimerMs = null;

    // Determine winner based on correctness
    _handleRoundResult(winnerIsPlayer1: isCorrectClick);
  }

  void _handleFriendClick() {
    debugLog(
        '[GameScreen] handleFriendClick - isCorrect: $isCorrectClick - I am ready $isPlayer1Ready, opponent ready: $isPlayer2Ready');

    // Send click to peer via GameService
    _gameService.sendClick(clickedSymbolId!, _clickedTimestamp!);

    _safeSetState(() {
      isPlayer1Ready = false;
      isPlayer2Ready = false;
      _waitingForPeerAdmit = true;
    });
  }

  void _handleHotSeatClick() {
    debugLog(
        '[GameScreen] handleHotSeatClick - player${isPlayer1Card ? "1" : "2"} clicked');

    // In hot-seat, whoever clicks their card wins
    _handleRoundResult(
        winnerIsPlayer1: (isPlayer1Card & isCorrectClick) |
            (!isPlayer1Card & !isCorrectClick));
  }

  void _handleAckClickMsg(Map<String, dynamic> msg) {
    if (msg['value']) {
      _handleRoundResult(winnerIsPlayer1: clickedSymbolId == correctSymbolId);
    } else {
      if (_peerClickSymbolId != null) {
        _handleRoundResult(
            winnerIsPlayer1: _peerClickSymbolId != correctSymbolId);
      }
    }
  }

  void _handlePeerClick(Map<String, dynamic> msg) {
    final peerSymbolId = msg['symbolId'] as int?;
    final peerTimestamp = msg['timestamp'] as int?;

    _safeSetState(() {
      isPlayer1Ready = false;
      isPlayer2Ready = false;
    });

    if (!_gameService.isSocketConnected) {
      debugLog('[GameScreen] ERROR - Not connected to server');
      return;
    }

    debugLog(
        '[GameScreen] Peer clicked: symbol=$peerSymbolId, timestamp=$_clickedTimestamp, peerTimestamp:$peerTimestamp, _waitingForPeerAdmit: $_waitingForPeerAdmit');

    if (_waitingForPeerAdmit & (_clickedTimestamp != null)) {
      if ((peerTimestamp == null) | (peerTimestamp! > _clickedTimestamp!)) {
        debugLog('[GameScreen] Player clicked first');
        _gameService.sendAckClick(false);
        _handleRoundResult(winnerIsPlayer1: clickedSymbolId == correctSymbolId);
      } else {
        _safeSetState(() {
          _peerClickSymbolId = peerSymbolId;
        });
        _gameService.sendAckClick(true);
        _handleRoundResult(winnerIsPlayer1: peerSymbolId != correctSymbolId);
      }
    } else {
      debugLog('[GameScreen] Peer clicked, no player action pending');
      _safeSetState(() {
        _peerClickSymbolId = peerSymbolId;
      });
      _gameService.sendAckClick(true);
      _handleRoundResult(winnerIsPlayer1: peerSymbolId != correctSymbolId);
    }

    _safeSetState(() {
      _waitingForPeerAdmit = false;
    });
  }

  // UNIFIED RESULT HANDLER
  void _handleRoundResult({required bool winnerIsPlayer1}) {
    if (showingResult) return;

    debugLog(
        '[GameScreen] handleRoundResult - winner: ${winnerIsPlayer1 ? "Player1" : "Player2"} - I am ready $isPlayer1Ready, opponent ready: $isPlayer2Ready');

    _safeSetState(() {
      showingResult = true;
      wasWinner = winnerIsPlayer1;
    });

    if (winnerIsPlayer1) {
      SoundService.instance.playSuccess();
    } else {
      SoundService.instance.playMismatch();
    }

    // Show UI - override in subclass
    showRoundResult(
      winnerName: winnerIsPlayer1 ? player1Name : player2Name,
      isPlayer1Winner: winnerIsPlayer1,
      clickedSymbol: clickedSymbolId ?? correctSymbolId!,
      correctSymbol: correctSymbolId!,
    );
  }

  // Override in subclasses to show result UI
  void showRoundResult({
    required String winnerName,
    required bool isPlayer1Winner,
    required int clickedSymbol,
    required int correctSymbol,
  }) {
    // Override in subclass
  }

  // Called when player acknowledges result (taps screen)
  void acknowledgeResult() {
    if (!showingResult) return;

    debugLog('[GameScreen] acknowledgeResult called');

    _safeSetState(() {
      showingResult = false;
    });

    // Move cards
    if (wasWinner) {
      player1Deck!.winOverPlayer(player2Deck!);
    } else {
      player2Deck!.winOverPlayer(player1Deck!);
    }

    _prepareNextRound();
  }

  void _prepareNextRound() {
    debugLog('[GameScreen] Preparing next round...');

    // Reset click state
    clickedSymbolId = null;
    _clickedTimestamp = null;
    isPlayer1Card = true;
    isCorrectClick = false;
    _waitingForPeerAdmit = false;
    _peerClickSymbolId = null;

    // Check if game ended
    if (player1Deck!.isEmpty || player2Deck!.isEmpty) {
      _checkForGameEnd();
      return;
    }

    // Set correct symbol for the new top cards
    _setCorrectSymbolId();
    _loadVisibleCardImages();
    _preloadUpcomingCards();

    if (gameMode == 'friend') {
      _safeSetState(() {
        showCards = false;
      });
      debugLog(
          '[GameScreen] Cards hidden, waiting for both players to be ready - I am ready $isPlayer1Ready, opponent ready: $isPlayer2Ready');
    } else {
      _safeSetState(() {
        showCards = true;
      });
      if (gameMode == 'computer') {
        _startComputerTimer();
      }
    }
  }

  void handleReadyToDraw() {
    if (_isDisposed || isPlayer1Ready) return;

    debugLog('[GameScreen] I am ready - isPlayer2Ready: $isPlayer2Ready');

    _safeSetState(() {
      isPlayer1Ready = true;
    });

    _gameService.sendReadyToDraw();
    _checkBothPlayersReady();
  }

  void _handlePeerReadyToDraw() {
    if (_isDisposed) return;

    debugLog('[GameScreen] Peer ready received');

    _safeSetState(() {
      isPlayer2Ready = true;
    });

    _checkBothPlayersReady();
  }

  void _checkBothPlayersReady() {
    if (_isDisposed) return;

    debugLog(
        '[GameScreen] Check ready state - Player1: $isPlayer1Ready, Player2: $isPlayer2Ready');

    if (isPlayer1Ready && isPlayer2Ready) {
      _safeSetState(() {
        showCards = true;
      });
      debugLog('[GameScreen] Both players ready, showing cards');
    }
  }

  void _checkForGameEnd() {
    if (_isDisposed || player1Deck == null || player2Deck == null) return;

    if (player2Deck!.isEmpty) {
      Future.delayed(Duration.zero, () {
        if (!_isDisposed && mounted) {
          _showEndDialog(
            title: '$player1Name Wins!',
            content: 'Congratulations! ${player1Name} has won the game.',
          );
        }
      });
    } else if (player1Deck!.isEmpty) {
      Future.delayed(Duration.zero, () {
        if (!_isDisposed && mounted) {
          _showEndDialog(
            title: '$player2Name Wins!',
            content: '${player2Name} has won the game.',
          );
        }
      });
    }
  }

  void _showEndDialog({required String title, required String content}) {
    if (_isDisposed || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String message,
      {String? actionLabel, VoidCallback? onAction}) {
    if (_isDisposed || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
            if (actionLabel != null)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onAction?.call();
                },
                child: Text(actionLabel),
              ),
          ],
        );
      },
    );
  }

  void _showPeerLeftDialog() {
    appLog('_showPeerLeftDialog called');
    if (_isDisposed || !mounted) return;
    _connectionLossHandled = true;
    setState(() {
      isLeavingGame = true;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Game Ended'),
          content: const Text('Your opponent has left the game.'),
          actions: [
            TextButton(
              onPressed: () {
                appLog('Peer left dialog dismissed, navigating back');
                Navigator.of(context).pop();
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    debugLog('[GameScreen] Disposing...');
    _isDisposed = true;

    _computerTimer?.cancel();
    _messageSubscription?.cancel();
    _connectionSubscription?.cancel();
    _registrationSubscription?.cancel();

    if (gameMode == 'friend') {
      _gameService.endGame();
      _gameService.releaseMultiplayerService();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold();
  }
}

class _ReactionRange {
  const _ReactionRange(this.min, this.max);

  final int min;
  final int max;
}

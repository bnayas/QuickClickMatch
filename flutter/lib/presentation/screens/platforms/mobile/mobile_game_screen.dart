import 'package:flutter/material.dart' hide Card;
import 'package:quick_click_match/presentation/screens/game_screen.dart';
import 'package:quick_click_match/presentation/widgets/card_widget.dart';
import 'package:quick_click_match/presentation/widgets/card_shape_utils.dart';
import 'package:quick_click_match/services/game_service.dart';
import 'package:confetti/confetti.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:quick_click_match/services/localization_service.dart';
import 'package:quick_click_match/utils/debug_logger.dart';

class _MobileGameScreenState extends GameScreenState {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState(); // VERY important
    _confettiController =
        ConfettiController(duration: const Duration(milliseconds: 900));
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  void showRoundResult({
    required String winnerName,
    required bool isPlayer1Winner,
    required int clickedSymbol,
    required int correctSymbol,
  }) {
    // Just set state - UI will automatically show result overlay
    setState(() {
      // State is already set in parent - just trigger UI update
    });
    if (isPlayer1Winner) {
      _confettiController.play();
    }
  }

  void _handleScreenTap() {
    if (showingResult) {
      debugLog('stop confetti!');
      _confettiController.stop();
      acknowledgeResult();
    }
  }

  Future<bool> _onWillPop() async {
    // Don't show dialog if already disposed or not in an active game
    if (isLeavingGame) {
      return true;
    }

    // Only show confirmation for friend mode (or add other modes as needed)
    if (gameMode != 'friend') {
      return true; // Allow leaving without confirmation
    }

    // Don't show confirmation if game already ended
    if ((player1Deck?.isEmpty ?? true) || (player2Deck?.isEmpty ?? true)) {
      return true;
    }

    final shouldLeave = await _showForfeitDialog();

    if (shouldLeave == true) {
      isLeavingGame = true;
      // Send end game message via GameService
      if (gameMode == 'friend') {
        GameService().leavingGame();
        GameService().releaseMultiplayerService();
      }
      return true;
    }

    return false;
  }

  // Add this method to show the forfeit confirmation dialog
  Future<bool?> _showForfeitDialog() async {
    if (!mounted) return true;
    final l10n = LocalizationService.instance;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(l10n.t('game.leaveDialog.title')),
          content: Text(l10n.t('game.leaveDialog.message')),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // Don't leave
              },
              child: Text(l10n.t('game.leaveDialog.stay')),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true); // Leave and forfeit
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: Text(l10n.t('game.leaveDialog.forfeit')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!isDeckLoaded ||
        !nextCardsAreReady ||
        player1Deck == null ||
        player2Deck == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final l10n = LocalizationService.instance;
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final bool isTabletLayout = mediaQuery.size.shortestSide >= 600;
    final double feedbackIconSize = isTabletLayout ? 32.0 : 24.0;

    // Prevent error if either deck is empty (end dialog will be shown)
    if (player1Deck!.isEmpty || player2Deck!.isEmpty) {
      return const Scaffold();
    }

    final card1 = player1Deck!.topCard;
    final card2 = player2Deck!.topCard;

    // Determine title based on game mode
    String appBarTitle;
    if (gameMode == 'train') {
      appBarTitle = l10n.t('game.appbar.train');
    } else if (gameMode == 'hotseat') {
      appBarTitle = l10n.format('game.appbar.hotseat', {
        'player1': player1Name,
        'player2': player2Name,
      });
    } else if (gameMode == 'friend') {
      appBarTitle = l10n.format('game.appbar.friend', {
        'player1': player1Name,
        'player2': player2Name,
      });
    } else {
      appBarTitle = l10n.format('game.appbar.vs', {'name': player2Name});
    }

    final opponentLabel = gameMode == 'computer'
        ? l10n
            .format('game.score.computerName', {'level': computerLevelDisplay})
        : player2Name;
    final player2CardsLabel = l10n.format('game.score.cardsLabel', {
      'name': opponentLabel,
      'count': player2Deck!.length.toString(),
    });
    final player1CardsLabel = l10n.format('game.score.cardsLabel', {
      'name': player1Name,
      'count': player1Deck!.length.toString(),
    });

    return PopScope(
        canPop: isLeavingGame,
        onPopInvokedWithResult: (bool didPop, dynamic result) async {
          if (didPop) return;

          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(appBarTitle),
          ),
          body: GestureDetector(
            onTap: showingResult ? _handleScreenTap : null,
            behavior: HitTestBehavior.translucent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/game_background.png',
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.55),
                          Colors.black.withValues(alpha: 0.38),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                ),
                // Top: Player 2 deck size badge
                Positioned(
                  top: 12,
                  left: 16,
                  child: _ScoreBadge.multi(
                    lines: [
                      player2CardsLabel,
                    ],
                  ),
                ),

                // Main content: two cards or waiting area
                showCards
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompactHeight = constraints.maxHeight < 720;
                          final isTablet = constraints.maxWidth >= 600;
                          final cardSpacing = isCompactHeight ? 24.0 : 32.0;
                          final verticalGuard = isCompactHeight ? 96.0 : 120.0;
                          final double maxCardSize = isTablet ? 520.0 : 400.0;
                          final double minCardSize = isTablet ? 220.0 : 170.0;
                          final availableHeight = (constraints.maxHeight -
                                  verticalGuard -
                                  cardSpacing)
                              .clamp(minCardSize * 2, constraints.maxHeight);
                          final heightBasedSize = (availableHeight / 2)
                              .clamp(minCardSize, maxCardSize);
                          final widthFactor = isTablet
                              ? 0.5
                              : (constraints.maxWidth < 380 ? 0.9 : 0.8);
                          final widthBasedSize =
                              (constraints.maxWidth * widthFactor)
                                  .clamp(minCardSize, maxCardSize);
                          final cardSize = min(heightBasedSize, widthBasedSize);

                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _buildCard(
                                  cardId: card2.cardId,
                                  isPlayer1Card: false,
                                  cardSize: cardSize,
                                ),
                                SizedBox(height: cardSpacing),
                                _buildCard(
                                  cardId: card1.cardId,
                                  isPlayer1Card: true,
                                  cardSize: cardSize,
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : _buildWaitingArea(),

                // Bottom: Player 1 deck size
                Positioned(
                  bottom: 12,
                  right: 16,
                  child: _ScoreBadge.multi(
                    lines: [
                      player1CardsLabel,
                    ],
                  ),
                ),

                // Result overlay
                if (showingResult)
                  Positioned(
                    top: 60,
                    left: 0,
                    right: 0,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: (wasWinner
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error)
                            .withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 1,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                wasWinner ? Icons.check_circle : Icons.close,
                                color: wasWinner
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onError,
                                size: feedbackIconSize,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                wasWinner
                                    ? l10n.format('game.victory.playerWins',
                                        {'player': player1Name})
                                    : l10n.format('game.victory.playerWins',
                                        {'player': player2Name}),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: wasWinner
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onError,
                                  fontWeight: FontWeight.w700,
                                  fontSize: isTabletLayout ? 20 : 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.t('game.tapToContinue'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: (wasWinner
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.onError)
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.center,
                  child: ConfettiWidget(
                    confettiController: _confettiController,
                    blastDirectionality: BlastDirectionality.explosive,
                    maxBlastForce: 80,
                    minBlastForce: 30,
                    emissionFrequency: 0.08,
                    numberOfParticles: 30,
                    gravity: 0.25,
                    shouldLoop: false,
                    colors: const [
                      Colors.red,
                      Colors.blue,
                      Colors.yellow,
                      Colors.green,
                      Colors.purple,
                    ],
                  ),
                )
              ],
            ),
          ),
        ));
  }

  Widget _buildCard({
    required int cardId,
    required bool isPlayer1Card,
    required double cardSize,
  }) {
    final double glowStroke = (cardSize / 120).clamp(3.0, 6.0);
    final double glowBlur = (cardSize / 18).clamp(12.0, 22.0);
    final double glowSpread = (cardSize / 80).clamp(1.0, 4.0);
    // If not showing result, return simple interactive card
    if (!showingResult) {
      return CardWidget(
        card_id: cardId,
        config: deckConfig,
        size: cardSize,
        onSymbolClick: (symbolId) =>
            onSymbolClick(symbolId, isPlayer1Click: isPlayer1Card),
      );
    }

    // --- SHOWING RESULT: Determine highlights ---

    int? goldSymbolId;
    int? blueSymbolId;
    int? redSymbolId;
    Color? cardGlowColor;

    if (gameMode == 'hotseat') {
      // HOT-SEAT MODE: Click must be on correct symbol on their card

      if (isCorrectClick) {
        // Clicked the matching symbol correctly - they win
        goldSymbolId = correctSymbolId; // Show gold symbol on both cards

        if (isPlayer1Card) {
          // Rendering Player 1's card
          if (wasWinner) {
            // Player 1 won
            cardGlowColor = Colors.amber; // Winner: gold glow
          } else {
            // Player 1 lost
            cardGlowColor = Colors.red; // Loser: red glow
          }
        } else {
          // Rendering Player 2's card
          if (!wasWinner) {
            // Player 2 won
            cardGlowColor = Colors.amber; // Winner: gold glow
          } else {
            // Player 2 lost
            cardGlowColor = Colors.red; // Loser: red glow
          }
        }
      } else {
        // Clicked wrong symbol on their card - they lose
        blueSymbolId =
            correctSymbolId; // Show correct symbol in blue on both cards

        if (isPlayer1Card) {
          debugLog(
              'isPlayer1Card: $isPlayer1Card, wasWinner: $wasWinner, this.isPlayer1Card: ${this.isPlayer1Card}');
          // Rendering Player 1's card
          if (!wasWinner) {
            // Player 1 lost (clicked wrong)
            cardGlowColor = Colors.red; // Loser: red glow
            redSymbolId = clickedSymbolId; // Show wrong symbol in red
          } else {
            // Player 1 won (player 2 clicked wrong)
            cardGlowColor = Colors.amber; // Winner: gold glow
          }
        } else {
          debugLog(
              'isPlayer1Card: $isPlayer1Card, wasWinner: $wasWinner, this.isPlayer1Card: ${this.isPlayer1Card}');

          // Rendering Player 2's card
          if (wasWinner) {
            // Player 2 lost (clicked wrong)
            cardGlowColor = Colors.red; // Loser: red glow
            redSymbolId = clickedSymbolId; // Show wrong symbol in red
            debugLog('redSymbolId: $redSymbolId');
          } else {
            // Player 2 won (player 1 clicked wrong)
            cardGlowColor = Colors.amber; // Winner: gold glow
          }
        }
      }
    } else {
      // COMPUTER / TRAIN / FRIEND MODE: Correct symbol matters
      // Both cards show same highlights (can click either card)

      if (wasWinner) {
        // Player 1 won (clicked correct symbol on either card)
        goldSymbolId = correctSymbolId;
        cardGlowColor = Colors.amber; // Both cards glow gold
      } else {
        // Player 1 lost (clicked wrong or opponent won)
        blueSymbolId =
            correctSymbolId; // Show correct symbol in blue on both cards
        cardGlowColor = Colors.red; // Both cards glow red

        // Show red on wrong symbol only on the card that contains it
        if (clickedSymbolId != null && !isCorrectClick) {
          // isPlayer1Card parameter = which card we're rendering (true=bottom, false=top)
          // this.isPlayer1Card = which card was clicked
          if (isPlayer1Card == this.isPlayer1Card) {
            redSymbolId = clickedSymbolId;
            debugLog('redSymbolId: $redSymbolId');
          }
        }
      }
    }
    debugLog('redSymbolId: $redSymbolId');
    final Color? glowColor = cardGlowColor;
    final Decoration? glowDecoration;
    if (glowColor != null) {
      glowDecoration = ShapeDecoration(
        shape: buildCardShapeBorder(
          deckConfig.cardShape,
          side: BorderSide(color: glowColor, width: glowStroke),
        ),
        shadows: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.32),
            blurRadius: glowBlur,
            spreadRadius: glowSpread,
          ),
        ],
      );
    } else {
      glowDecoration = null;
    }

    return Container(
      width: cardSize,
      height: cardSize,
      decoration: glowDecoration,
      child: CardWidget(
        card_id: cardId,
        config: deckConfig,
        size: cardSize,
        onSymbolClick: null, // Disable clicks when showing result
        highlightGoldSymbolId: goldSymbolId,
        highlightBlueSymbolId: blueSymbolId,
        highlightWrongSymbolId: redSymbolId,
      ),
    );
  }

  Widget _buildWaitingArea() {
    final l10n = LocalizationService.instance;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            l10n.t('game.roundComplete.title'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Text(
            isPlayer1Ready
                ? l10n.t('game.roundComplete.waiting')
                : l10n.t('game.roundComplete.readyQuestion'),
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 20),
          if (!isPlayer1Ready)
            ElevatedButton(
              onPressed: handleReadyToDraw,
              child: Text(l10n.t('action.ready')),
            ),
          if (isPlayer1Ready) const CircularProgressIndicator(),
        ],
      ),
    );
  }
}

_MobileGameScreenState createMobileGameScreenState() =>
    _MobileGameScreenState();

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge._(this._lines);

  factory _ScoreBadge.multi({required List<String> lines}) {
    final filtered =
        lines.where((line) => line.trim().isNotEmpty).toList(growable: false);
    return _ScoreBadge._(filtered.isEmpty ? const [''] : filtered);
  }

  final List<String> _lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < _lines.length; i++)
                  Padding(
                    padding:
                        EdgeInsets.only(bottom: i == _lines.length - 1 ? 0 : 2),
                    child: Text(
                      _lines[i],
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: Offset(0, 1),
                            blurRadius: 2,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'card.dart';
import 'package:quick_click_match/utils/app_logger.dart';

class PlayerDeck {
  final List<Card> _cards;
  PlayerDeck(List<Card> cards) : _cards = List.from(cards);

  Card get topCard => _cards.first;
  void winOverPlayer(PlayerDeck other_player_deck) {
    appLog('winOverPlayer ${_cards.length}');
    addCardToEnd(other_player_deck.topCard);
    other_player_deck.removeTopCard();
    moveTopCardToEnd();
  }

  void moveTopCardToEnd() {
    if (_cards.isNotEmpty) {
      _cards.add(_cards.removeAt(0));
    }
  }

  void addCardToEnd(Card card) {
    _cards.add(card);
  }

  void removeTopCard() {
    if (_cards.isNotEmpty) {
      _cards.removeAt(0);
    }
  }

  List<Card> get cards => List.unmodifiable(_cards);
  bool get isEmpty => _cards.isEmpty;
  int get length => _cards.length;
  @override
  String toString() => _cards.map((c) => c.cardId.toString()).join('\n');
}

void printPlayerDecks(PlayerDeck player, PlayerDeck computer) {
  appLog('Player deck (${player.length} cards):\n$player');
  appLog('Computer deck (${computer.length} cards):\n$computer');
}

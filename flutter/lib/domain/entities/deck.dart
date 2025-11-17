import 'card.dart';

class Deck {
  final List<Card> cards;
  Deck({required this.cards});

  static Deck fromJson(Map<String, dynamic> json) {
    List<Card> cards = [];
    for (final card in json['cards']) {
      final card_id = card['card_id'];
      final List<int> symbols = [];
      for (final symbol in card['images']) {
        final id = int.parse(symbol['id'].replaceAll(RegExp(r'[^0-9]'), ''));
        symbols.add(id);
      }
      cards.add(Card(cardId: card_id, symbolIds: symbols));
    }
    return Deck(cards: cards);
  }
}

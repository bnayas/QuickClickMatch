import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/domain/services/card_generator.dart';

void main() {
  test('CardGenerator generates two cards with one shared number', () {
    final generator = CardGenerator(iconsPerCard: 8, iconPoolSize: 30);
    final cards = generator.generateCardPair();
    final card1 = cards[0];
    final card2 = cards[1];
    // Both cards should have the correct length
    expect(card1.length, 8);
    expect(card2.length, 8);
    // There should be exactly one shared number
    final shared = card1.toSet().intersection(card2.toSet());
    expect(shared.length, 1);
    // All numbers in each card should be unique
    expect(card1.toSet().length, 8);
    expect(card2.toSet().length, 8);
    // All numbers should be in the valid range
    expect(card1.every((n) => n >= 1 && n <= 30), isTrue);
    expect(card2.every((n) => n >= 1 && n <= 30), isTrue);
  });
}

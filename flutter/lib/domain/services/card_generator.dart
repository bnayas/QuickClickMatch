import 'dart:math';
import '../entities/point.dart';
import '../entities/line.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/utils/app_logger.dart';

class CardGenerator {
  final int iconsPerCard;
  final int iconPoolSize;
  final Random _random;

  CardGenerator({this.iconsPerCard = 8, this.iconPoolSize = 30, Random? random})
      : _random = random ?? Random();

  /// Generates two cards, each with [iconsPerCard] numbers, sharing exactly one number.
  /// The numbers are in the range [1, iconPoolSize].
  List<List<int>> generateCardPair() {
    assert(iconPoolSize >= iconsPerCard * 2 - 1);
    // Pick the shared number
    final shared = _random.nextInt(iconPoolSize) + 1;
    // Pick unique numbers for each card
    final pool = List<int>.generate(iconPoolSize, (i) => i + 1)..remove(shared);
    pool.shuffle(_random);
    final card1 = [shared, ...pool.take(iconsPerCard - 1)];
    final card2 = [
      shared,
      ...pool.skip(iconsPerCard - 1).take(iconsPerCard - 1)
    ];
    card1.shuffle(_random);
    card2.shuffle(_random);
    return [card1, card2];
  }
}

Set<Point> generateProjectivePoints(int q) {
  final points = <Point>{};

  // Generate points in normalized form: (x, y, 1), (x, 1, 0), (1, 0, 0)

  // Points with z=1: (x, y, 1) for all x, y in F_q
  for (int x = 0; x < q; x++) {
    for (int y = 0; y < q; y++) {
      points.add(Point(x, y, 1));
    }
  }

  // Points with z=0, y=1: (x, 1, 0) for all x in F_q
  for (int x = 0; x < q; x++) {
    points.add(Point(x, 1, 0));
  }

  // Point at infinity: (1, 0, 0)
  points.add(Point(1, 0, 0));

  return points;
}

Set<Line> generateProjectiveLines(int q) {
  final lines = <Line>{};

  // Generate lines in normalized form

  // Lines with c=1: ax + by + z = 0 for all a, b in F_q
  for (int a = 0; a < q; a++) {
    for (int b = 0; b < q; b++) {
      lines.add(Line(a, b, 1));
    }
  }

  // Lines with c=0, b=1: ax + y = 0 for all a in F_q
  for (int a = 0; a < q; a++) {
    lines.add(Line(a, 1, 0));
  }

  // Line at infinity: x = 0
  lines.add(Line(1, 0, 0));

  return lines;
}

List<List<int>> generateCardsMatchingGameDeck(int q) {
  final points = generateProjectivePoints(q).toList();
  final pointIndices = {for (var i = 0; i < points.length; i++) points[i]: i};
  final random = Random();

  final lines = generateProjectiveLines(q);
  final deck = <List<int>>[];

  for (var line in lines) {
    final symbols = <int>[];
    for (var point in points) {
      if (line.contains(point, q)) {
        symbols.add(pointIndices[point]!);
      }
    }
    symbols.shuffle(random);
    deck.add(symbols);
  }

  return deck;
}

void main() {
  test('generateProjectiveLines returns correct number of unique lines for q=3',
      () {
    final lines = generateProjectiveLines(3);
    expect(lines.length, 13); // For q=3, should be 13 unique lines
  });

  test('every card pair has exactly one item in common for q=7', () {
    final deck = generateCardsMatchingGameDeck(7);

    // Check every pair of cards
    for (int i = 0; i < deck.length; i++) {
      for (int j = i + 1; j < deck.length; j++) {
        final card1 = deck[i];
        final card2 = deck[j];

        // Find common items
        final commonItems =
            card1.where((item) => card2.contains(item)).toList();

        // Verify exactly one item in common
        expect(commonItems.length, 1,
            reason:
                'Cards $i and $j should have exactly one item in common, but found ${commonItems.length}');

        appLog('Cards $i and $j share item: ${commonItems[0]}');
      }
    }

    appLog('Total cards in deck: ${deck.length}');
    appLog('Total card pairs checked: ${deck.length * (deck.length - 1) ~/ 2}');
  });
}

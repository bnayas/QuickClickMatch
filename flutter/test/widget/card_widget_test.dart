import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quick_click_match/presentation/widgets/card_data.dart';
import 'package:quick_click_match/presentation/widgets/card_widget.dart';
import 'package:quick_click_match/presentation/widgets/image_data.dart';
import 'package:quick_click_match/utils/deck_config.dart';

DeckConfig _buildDeckConfig() {
  final cardData = CardData(
    id: 0,
    src: 'card0.png',
    symbols: [
      SymbolData(
        id: 1,
        rotation: 0,
        scale: 1,
        centerX: 0.0,
        centerY: 0.0,
        contour: const [
          [0.0, 0.0],
          [0.4, 0.0],
          [0.4, 0.4],
        ],
      ),
      SymbolData(
        id: 2,
        rotation: 0,
        scale: 1,
        centerX: -0.2,
        centerY: 0.2,
        contour: const [
          [-0.3, -0.3],
          [-0.1, -0.3],
          [-0.1, -0.1],
        ],
      ),
    ],
  );

  final cardImages = {
    0: ImageData(
      id: '0',
      src: 'card0.png',
      contour: <PointData>[],
      image: img.Image(1, 1),
    ),
  };

  return DeckConfig(
    deckFolderName: 'test_deck',
    imagePrefix: 'card_',
    extension: 'png',
    cardImages: cardImages,
    cardsDataMap: {0: cardData},
    layoutRadius: 1.0,
  );
}

void main() {
  testWidgets('CardWidget renders when data is available',
      (WidgetTester tester) async {
    final config = _buildDeckConfig();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardWidget(
            card_id: 0,
            config: config,
          ),
        ),
      ),
    );

    expect(find.byType(CardWidget), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

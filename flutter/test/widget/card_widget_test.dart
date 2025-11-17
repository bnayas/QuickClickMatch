import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/presentation/widgets/card_data.dart';
import 'package:quick_click_match/presentation/widgets/card_widget.dart';
import 'package:quick_click_match/presentation/widgets/image_data.dart';
import 'package:quick_click_match/utils/deck_config.dart';
import 'dart:typed_data';

DeckConfig _buildDeckConfig() {
  final transparentImage = Uint8List.fromList(const <int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0A,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0x00,
    0x01,
    0x00,
    0x00,
    0x05,
    0x00,
    0x01,
    0x0D,
    0x0A,
    0x2D,
    0xB4,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);
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
      bytes: transparentImage,
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

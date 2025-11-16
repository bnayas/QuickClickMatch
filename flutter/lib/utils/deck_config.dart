import '../presentation/widgets/image_data.dart';
import '../presentation/widgets/card_data.dart';
import 'package:quick_click_match/utils/debug_logger.dart';

enum CardShape { circle, square, hexagon }

CardShape parseCardShape(String? value) {
  switch (value?.toLowerCase()) {
    case 'square':
      return CardShape.square;
    case 'hexagon':
      return CardShape.hexagon;
    default:
      return CardShape.circle;
  }
}

class DeckConfig {
  final String deckFolderName;
  final String imagePrefix;
  final String extension;
  final Map<int, ImageData>
      cardImages; // Changed from symbolImages to cardImages
  final Map<int, CardData> cardsDataMap;
  final bool inAssets;
  final double layoutRadius; // Add this field
  final CardShape cardShape;
  DeckConfig(
      {required this.deckFolderName,
      required this.imagePrefix,
      required this.extension,
      required this.cardImages, // Changed from symbolImages to cardImages
      required this.cardsDataMap,
      this.inAssets = false,
      required this.layoutRadius, // Add this to constructor
      this.cardShape = CardShape.circle});

  factory DeckConfig.fromJson(Map<String, dynamic> json) {
    // Build cardImages map from cards array (using card_image_url)
    final Map<int, ImageData> cardImages = {};
    final Map<int, CardData> cardsData = {};

    // Process cards data and create card images from card_image_url
    if (json['cards'] != null) {
      for (final card in json['cards']) {
        // Get card_id using image_prefix to peel off the prefix of card['id']
        int card_id;
        if (card.containsKey('id')) {
          final String imagePrefix = json['image_prefix'] as String;
          final dynamic idValue = card['id'];
          if (idValue is String && idValue.startsWith(imagePrefix)) {
            card_id = int.parse(idValue.substring(imagePrefix.length));
          } else if (idValue is int) {
            card_id = idValue;
          } else if (idValue is String) {
            card_id = int.tryParse(idValue) ?? 0;
          } else {
            card_id = 0;
          }
        } else if (card.containsKey('card_id')) {
          card_id = card['card_id'] as int;
        } else {
          card_id = 0;
        }

        final card_image_url = card['src'] as String?;

        // Create ImageData for card image if it exists
        if (card_image_url != null) {
          cardImages[card_id] = ImageData(
            id: '$card_id',
            src: card_image_url,
            contour: [], // Card images don't have contours
          );
        }

        try {
          cardsData[card_id] = CardData.fromJson(card);
        } catch (e) {
          debugLog('Error while creating CardData from JSON: $e');
        }
      }
    }

    return DeckConfig(
      deckFolderName: json['deck_folder_name'] as String,
      imagePrefix: json['image_prefix'] as String,
      extension: json['extension'] as String,
      cardImages: cardImages, // Use cardImages instead of symbolImages
      cardsDataMap: cardsData,
      layoutRadius: json['layout_radius'] != null
          ? (json['layout_radius'] as num).toDouble()
          : 1.0, // Parse layout_radius
      cardShape: parseCardShape(json['card_shape'] as String?),
    );
  }

  static int extractSymbolId(String imageId, String prefix) {
    if (imageId.startsWith(prefix)) {
      return int.parse(imageId.substring(prefix.length));
    }
    throw FormatException(
        'Image id $imageId does not start with prefix $prefix');
  }
}

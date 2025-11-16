import 'package:quick_click_match/utils/debug_logger.dart';

// image_data.dart
class SymbolData {
  final int id;
  final double? rotation;
  final double? scale;
  final double? left;
  final double? top;
  final double? centerX; // normalized, -1 to 1
  final double? centerY; // normalized, -1 to 1
  final double? size; // normalized, 0 to 1
  final double? angle;
  final double? radialDistance;
  final List<List<double>>? contour;
  SymbolData(
      {required this.id,
      required this.rotation,
      required this.scale,
      this.left,
      this.top,
      this.centerX,
      this.centerY,
      this.size,
      this.angle,
      this.radialDistance,
      this.contour});
}

class CardData {
  final int id;
  List<SymbolData>? symbols;
  String? src; // New field for the pre-rendered card image
  CardData({
    required this.id,
    this.symbols,
    this.src,
  });

  factory CardData.fromJson(Map<String, dynamic> json) {
    List<SymbolData> symbols = [];
    for (final symbol in json['images']) {
      var symbolData;

      try {
        // Parse symbol ID from string format "id{number}"
        int symbolId;
        if (symbol['id'] is String) {
          String idStr = symbol['id'] as String;
          if (idStr.startsWith('id')) {
            symbolId = int.parse(idStr.substring(2));
          } else {
            symbolId = int.parse(idStr);
          }
        } else {
          symbolId = symbol['id'] as int;
        }

        // Parse contour as List<Map<String, double>> (PointData format)
        List<List<double>> contourList = [];
        final rawContour = symbol['contour'];
        if (rawContour is List) {
          for (var point in rawContour) {
            if (point is Map &&
                point.containsKey('x') &&
                point.containsKey('y')) {
              final x = (point['x'] as num?)?.toDouble();
              final y = (point['y'] as num?)?.toDouble();
              if (x != null && y != null) {
                contourList.add([x, y]);
              }
            }
          }
        }

        symbolData = SymbolData(
          id: symbolId,
          rotation: symbol['rotation'] != null
              ? (symbol['rotation'] as num).toDouble()
              : null,
          scale: symbol['scale'] != null
              ? (symbol['scale'] as num).toDouble()
              : null,
          left: symbol['left'] as double?,
          top: symbol['top'] as double?,
          centerX: symbol['centerX'] != null
              ? (symbol['centerX'] as num).toDouble()
              : null,
          centerY: symbol['centerY'] != null
              ? (symbol['centerY'] as num).toDouble()
              : null,
          angle: symbol['angle'] != null
              ? (symbol['angle'] as num).toDouble()
              : null,
          size: symbol['size'] != null
              ? (symbol['size'] as num).toDouble()
              : null,
          radialDistance:
              symbol['r'] != null ? (symbol['r'] as num).toDouble() : null,
          contour: contourList,
        );
      } catch (e) {
        debugLog('Error parsing symbol data: $e');
        // Fallback with default values
        symbolData = SymbolData(
          id: 0,
          rotation: 0.0,
          scale: 1.0,
          left: null,
          top: null,
          centerX: null,
          centerY: null,
          angle: null,
          size: null,
          radialDistance: null,
          contour: [],
        );
      }

      symbols.add(symbolData);
    }
    CardData cardData;
    try {
      cardData = CardData(
        id: json['card_id'],
        symbols: symbols,
        src: json['src'] as String?,
      );
    } catch (e) {
      debugLog(e);
      cardData = CardData(id: 0, symbols: [], src: '');
    }
    return cardData;
  }
}

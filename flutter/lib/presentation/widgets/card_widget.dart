import 'package:quick_click_match/presentation/widgets/card_data.dart';
import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:quick_click_match/presentation/widgets/card_shape_utils.dart';
import '../../utils/deck_config.dart';
import 'dart:typed_data';
import 'package:quick_click_match/utils/debug_logger.dart';

class CardWidget extends StatelessWidget {
  final int card_id;
  final DeckConfig config;
  final double size;
  final Function(int)? onSymbolClick;
  final bool showContours;
  final int? highlightSymbolId;
  final int? highlightWrongSymbolId;
  final int? highlightGoldSymbolId;
  final int? highlightBlueSymbolId;

  const CardWidget({
    super.key,
    required this.card_id,
    required this.config,
    this.size = 300,
    this.onSymbolClick,
    this.showContours = false,
    this.highlightSymbolId,
    this.highlightGoldSymbolId,
    this.highlightBlueSymbolId,
    this.highlightWrongSymbolId,
  });

  @override
  Widget build(BuildContext context) {
    final cardData = config.cardsDataMap[card_id];
    final cardImageData = config.cardImages[card_id];
    final int? n = cardData?.symbols?.length;
    final shapeBorder = buildCardShapeBorder(config.cardShape);
    final shapeClipper = ShapeBorderClipper(shape: shapeBorder);
    final Widget Function(Widget child) clipCardChild = (child) => ClipPath(
          clipper: shapeClipper,
          child: child,
        );

    if (cardData == null) {
      debugLog('cardData is null');
      return const SizedBox();
    }
    if (cardData.symbols == null) {
      debugLog('cardData.symbols is null');
      return const SizedBox();
    }
    if (n == null) {
      debugLog('n is null');
      return const SizedBox();
    }
    if (cardData.symbols!.length < n) {
      debugLog('cardData.symbols!.length is ${cardData.symbols!.length}');
      return const SizedBox();
    }

    // Check if card image is loaded
    final Uint8List? cardBytes = cardImageData?.bytes;
    final bool isImageLoaded = cardBytes != null;
    debugLog('CardWidget: highlightWrongSymbolId:$highlightWrongSymbolId');
    if (highlightWrongSymbolId != null)
      for (final symbol in cardData.symbols!) {
        debugLog(
            'symbol.id: ${symbol.id} ${symbol.id == highlightWrongSymbolId}');
        if (symbol.id == highlightWrongSymbolId &&
            symbol.contour != null &&
            symbol.contour!.isNotEmpty)
          debugLog('CardWidget: highlightWrongSymbolId found');
      }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Only show card background if image is loaded
          if (isImageLoaded) ...[
            Container(
              width: size,
              height: size,
              decoration: ShapeDecoration(
                shape: shapeBorder,
                color: Colors.transparent,
                shadows: [
                  BoxShadow(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.25),
                    blurRadius: 18,
                    spreadRadius: 4,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 26,
                    spreadRadius: 8,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
            ),
            // Card background
            Container(
              width: size,
              height: size,
              decoration: ShapeDecoration(
                shape: buildCardShapeBorder(
                  config.cardShape,
                  side: const BorderSide(
                    color: Colors.white,
                    width: 5.5,
                  ),
                ),
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFFE6DEFF),
                    Color(0xFFFDFBFF),
                    Color(0xFFFFFFFF),
                  ],
                  radius: 0.85,
                  center: Alignment(-0.2, -0.25),
                ),
                shadows: [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.45),
                    blurRadius: 12,
                    spreadRadius: -6,
                    offset: const Offset(-4, -6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 18,
                    spreadRadius: 4,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.18),
                    blurRadius: 8,
                    spreadRadius: -1,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
            ),

            if (cardData.src != null) ...[
              Positioned.fill(
                child: clipCardChild(
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _CardBevelPainter(
                        cardShape: config.cardShape,
                        shape: shapeBorder,
                      ),
                    ),
                  ),
                ),
              ),
              // Display the pre-rendered card image
              Positioned.fill(
                child: clipCardChild(
                  Image.memory(
                    cardBytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),

              Positioned.fill(
                child: clipCardChild(
                  IgnorePointer(
                    child: Image.asset(
                      'assets/textures/paper_noise.png',
                      fit: BoxFit.cover,
                      color: Colors.grey.shade600.withValues(alpha: 0.22),
                      colorBlendMode: BlendMode.overlay,
                    ),
                  ),
                ),
              ),

              // Paper texture overlay
              Positioned.fill(
                child: clipCardChild(
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _PaperTexturePainter(seed: card_id),
                    ),
                  ),
                ),
              ),

              Positioned.fill(
                child: clipCardChild(
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: 0.35),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.18),
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Gesture detector layer for symbol detection
              Positioned.fill(
                child: clipCardChild(
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final Size paintSize =
                          Size(constraints.maxWidth, constraints.maxHeight);
                      final Map<int, List<Offset>> contourCache = {
                        for (final symbol in cardData.symbols!)
                          if (symbol.contour != null &&
                              symbol.contour!.isNotEmpty)
                            symbol.id: _transformContour(symbol, paintSize),
                      };

                      return Stack(
                        children: [
                          // Main gesture detector
                          GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTapDown: onSymbolClick == null
                                ? null
                                : (details) => _handleTap(
                                    details.localPosition, contourCache),
                            child: SizedBox(
                              width: paintSize.width,
                              height: paintSize.height,
                            ),
                          ),

                          // Highlight symbol in GOLD (winning symbol)
                          if (highlightGoldSymbolId != null)
                            for (final symbol in cardData.symbols!)
                              if (symbol.id == highlightGoldSymbolId &&
                                  contourCache.containsKey(symbol.id))
                                CustomPaint(
                                  size: paintSize,
                                  painter: ContourPainter(
                                    contourCache[symbol.id]!,
                                    const Color(0xFFFFD700)
                                        .withValues(alpha: 0.8), // Gold
                                    strokeWidth: 5.0,
                                  ),
                                ),

                          // Highlight symbol in BLUE (correct symbol when lost)
                          if (highlightBlueSymbolId != null)
                            for (final symbol in cardData.symbols!)
                              if (symbol.id == highlightBlueSymbolId &&
                                  contourCache.containsKey(symbol.id))
                                CustomPaint(
                                  size: paintSize,
                                  painter: ContourPainter(
                                    contourCache[symbol.id]!,
                                    const Color(0xFF1976D2)
                                        .withValues(alpha: 0.7), // Deep Blue
                                    strokeWidth: 4.0,
                                  ),
                                ),

                          // Highlight wrong symbol in RED (player chose wrong)
                          if (highlightWrongSymbolId != null)
                            for (final symbol in cardData.symbols!)
                              if (symbol.id == highlightWrongSymbolId &&
                                  contourCache.containsKey(symbol.id))
                                CustomPaint(
                                  size: paintSize,
                                  painter: ContourPainter(
                                    contourCache[symbol.id]!,
                                    Colors.red.withValues(alpha: 0.7),
                                    strokeWidth: 4.0,
                                  ),
                                ),

                          // Highlight opponent's symbol in red (opponent won)
                          if (highlightSymbolId != null)
                            for (final symbol in cardData.symbols!)
                              if (symbol.id == highlightSymbolId &&
                                  contourCache.containsKey(symbol.id))
                                CustomPaint(
                                  size: paintSize,
                                  painter: ContourPainter(
                                    contourCache[symbol.id]!,
                                    Colors.red.withValues(alpha: 0.6),
                                    strokeWidth: 4.0,
                                  ),
                                ),
                          if (showContours)
                            for (final symbol in cardData.symbols!)
                              if (contourCache.containsKey(symbol.id))
                                CustomPaint(
                                  size: paintSize,
                                  painter: ContourPainter(
                                    contourCache[symbol.id]!,
                                    Colors.red.withValues(alpha: 0.3),
                                    strokeWidth: 2.0,
                                  ),
                                ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ] else ...[
            // Show loading indicator if image not loaded
            clipCardChild(
              Container(
                width: size,
                height: size,
                decoration: ShapeDecoration(
                  shape: shapeBorder,
                  color: Colors.grey[200],
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.deepPurple,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Handle tap and determine which symbol was clicked
  void _handleTap(
      Offset tapPosition, Map<int, List<Offset>> transformedContours) {
    debugLog('Tap at: $tapPosition');

    for (final entry in transformedContours.entries) {
      if (_isPointInPolygon(tapPosition, entry.value)) {
        debugLog('Hit symbol ${entry.key}');
        onSymbolClick?.call(entry.key);
        return;
      }
    }

    debugLog('No symbol hit');
  }

  /// Transform contour coordinates from normalized space to widget coordinates
  List<Offset> _transformContour(SymbolData symbol, Size paintSize) {
    if (symbol.contour == null || symbol.contour!.isEmpty) {
      return [];
    }

    final double centerX = paintSize.width / 2;
    final double centerY = paintSize.height / 2;
    final double layoutRadius = config.layoutRadius == 0
        ? 1.0
        : config.layoutRadius; // Guard against divide-by-zero
    final double scale = (paintSize.shortestSide / 2) / layoutRadius;

    return symbol.contour!.map((point) {
      double x = point[0];
      double y = -point[1];

      double screenX = centerX + (x * scale);
      double screenY = centerY + (y * scale);

      return Offset(screenX, screenY);
    }).toList();
  }

  /// Point-in-polygon test using ray casting algorithm
  bool _isPointInPolygon(Offset point, List<Offset> polygon) {
    if (polygon.length < 3) return false;

    int intersections = 0;

    for (int i = 0; i < polygon.length; i++) {
      Offset p1 = polygon[i];
      Offset p2 = polygon[(i + 1) % polygon.length];

      if ((p1.dy <= point.dy && point.dy < p2.dy) ||
          (p2.dy <= point.dy && point.dy < p1.dy)) {
        double intersectionX =
            (p2.dx - p1.dx) * (point.dy - p1.dy) / (p2.dy - p1.dy) + p1.dx;

        if (point.dx < intersectionX) {
          intersections++;
        }
      }
    }

    return intersections % 2 == 1;
  }
}

class _CardBevelPainter extends CustomPainter {
  const _CardBevelPainter({required this.cardShape, required this.shape});

  final CardShape cardShape;
  final ShapeBorder shape;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final strokeWidth = size.width * 0.055;

    if (cardShape == CardShape.circle) {
      final radius = size.width / 2 - strokeWidth / 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = ui.Gradient.sweep(
          rect.center,
          [
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.25),
            Colors.black.withValues(alpha: 0.28),
            Colors.white.withValues(alpha: 0.75),
          ],
          const [0.0, 0.35, 0.78, 1.0],
          TileMode.clamp,
          -pi / 2,
          2 * pi - pi / 2,
        );

      canvas.drawCircle(rect.center, radius, paint);
      return;
    }

    final Path path = shape.getOuterPath(rect.deflate(strokeWidth / 2));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = ui.Gradient.linear(
        rect.topLeft,
        rect.bottomRight,
        [
          Colors.white.withValues(alpha: 0.8),
          Colors.white.withValues(alpha: 0.3),
          Colors.black.withValues(alpha: 0.28),
          Colors.white.withValues(alpha: 0.6),
        ],
        [0.0, 0.35, 0.78, 1.0],
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CardBevelPainter oldDelegate) {
    return oldDelegate.cardShape != cardShape || oldDelegate.shape != shape;
  }
}

class _PaperTexturePainter extends CustomPainter {
  _PaperTexturePainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);

    final lightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final darkPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.09)
      ..style = PaintingStyle.fill;

    // Scatter tiny speckles
    for (int i = 0; i < 220; i++) {
      final offset = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = 1.1 + random.nextDouble() * 1.8;
      canvas.drawCircle(offset, radius, i.isEven ? lightPaint : darkPaint);
    }

    // Draw faint fibers
    final fiberPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 30; i++) {
      final start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final angle = random.nextDouble() * pi * 2;
      final length = 16 + random.nextDouble() * 32;
      final end = Offset(
        start.dx + cos(angle) * length,
        start.dy + sin(angle) * length,
      );
      canvas.drawLine(start, end, fiberPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperTexturePainter oldDelegate) {
    return oldDelegate.seed != seed;
  }
}

/// Custom painter for contour visualization overlays.
class ContourPainter extends CustomPainter {
  final List<Offset> contour;
  final Color color;
  final double strokeWidth;

  ContourPainter(this.contour, this.color, {this.strokeWidth = 2.0});

  @override
  void paint(Canvas canvas, Size size) {
    if (contour.isEmpty) return;

    final Paint fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final Paint strokePaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final Path path = Path();
    path.moveTo(contour.first.dx, contour.first.dy);

    for (int i = 1; i < contour.length; i++) {
      path.lineTo(contour[i].dx, contour[i].dy);
    }
    path.close();

    // Draw filled polygon
    canvas.drawPath(path, fillPaint);

    // Draw outline
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is! ContourPainter ||
        oldDelegate.contour != contour ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

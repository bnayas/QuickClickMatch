import 'dart:math';

import 'package:flutter/material.dart';

import 'package:quick_click_match/utils/deck_config.dart';

ShapeBorder buildCardShapeBorder(CardShape shape,
    {BorderSide side = BorderSide.none}) {
  switch (shape) {
    case CardShape.square:
      return RoundedRectangleBorder(
        side: side,
        borderRadius: BorderRadius.circular(24),
      );
    case CardShape.hexagon:
      return HexagonShapeBorder(side: side);
    case CardShape.circle:
      return CircleBorder(side: side);
  }
}

class HexagonShapeBorder extends ShapeBorder {
  const HexagonShapeBorder({this.side = BorderSide.none});

  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  ShapeBorder scale(double t) => HexagonShapeBorder(side: side.scale(t));

  Path _buildHexPath(Rect rect) {
    final double radius = min(rect.width, rect.height) / 2;
    final Offset center = rect.center;
    final Path path = Path();

    for (int i = 0; i < 6; i++) {
      final double angle = (pi / 3) * i - pi / 2;
      final Offset point = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    return path..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _buildHexPath(rect.deflate(side.width));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _buildHexPath(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final Paint paint = side.toPaint();
    final Path path = _buildHexPath(rect.deflate(side.width / 2));
    canvas.drawPath(path, paint);
  }

  @override
  int get hashCode => side.hashCode;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HexagonShapeBorder && other.side == side;
  }
}

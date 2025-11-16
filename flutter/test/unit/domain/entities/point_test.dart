import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/domain/entities/point.dart';

void main() {
  test('Point equality and hashCode', () {
    final p1 = Point(1, 2, 3);
    final p2 = Point(1, 2, 3);
    expect(p1, equals(p2));
    expect(p1.hashCode, equals(p2.hashCode));
  });
} 

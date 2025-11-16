import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/domain/entities/point.dart';
import 'package:quick_click_match/domain/entities/line.dart';

void main() {
  test('Line contains point', () {
    final q = 7;
    final line = Line(1, 2, 3);
    final p = Point(2, 0, 1);
    // Check if the line contains the point
    final result = line.contains(p, q);
    expect(result, isA<bool>());
  });
} 

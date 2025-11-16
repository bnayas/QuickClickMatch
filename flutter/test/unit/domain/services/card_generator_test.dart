import 'package:flutter_test/flutter_test.dart';
import 'package:quick_click_match/domain/services/card_generator.dart';

void main() {
  test('generateProjectiveLines returns correct number of unique lines for q=3', () {
    final lines = generateProjectiveLines(3);
    expect(lines.length, 13); // For q=3, should be 13 unique lines
    // Optionally, print lines for debugging
    for (final line in lines) {
      print(line);
    }
  });
}
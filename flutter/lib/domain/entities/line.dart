import '../../utils/math_utils.dart';
import 'point.dart';

class Line {
  final int a, b, c;
  Line(this.a, this.b, this.c);

  Line normalize(int q) {
    // Find the first non-zero coefficient
    if (c != 0 && _hasModularInverse(c, q)) {
      int inv = modInv(c, q);
      return Line(mod(a * inv, q), mod(b * inv, q), 1);
    } else if (b != 0 && _hasModularInverse(b, q)) {
      int inv = modInv(b, q);
      return Line(mod(a * inv, q), 1, mod(c * inv, q));
    } else if (a != 0 && _hasModularInverse(a, q)) {
      int inv = modInv(a, q);
      return Line(1, mod(b * inv, q), mod(c * inv, q));
    } else {
      // If no coefficient has a modular inverse, return the line as-is
      // This can happen when q is not prime
      return this;
    }
  }

  bool _hasModularInverse(int a, int q) {
    // A number has a modular inverse modulo q if and only if gcd(a, q) = 1
    return _gcd(a, q) == 1;
  }

  int _gcd(int a, int b) {
    while (b != 0) {
      int temp = b;
      b = a % b;
      a = temp;
    }
    return a;
  }

  bool contains(Point p, int q) {
    return mod(a * p.x + b * p.y + c * p.z, q) == 0;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Line && other.a == a && other.b == b && other.c == c;
  }

  @override
  int get hashCode => Object.hash(a, b, c);

  @override
  String toString() => '[$a,$b,$c]';
}

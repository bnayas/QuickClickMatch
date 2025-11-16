class Point {
  final int x, y, z;
  Point(this.x, this.y, this.z);

  @override
  bool operator ==(Object other) =>
      other is Point && x == other.x && y == other.y && z == other.z;

  @override
  int get hashCode => x.hashCode ^ y.hashCode ^ z.hashCode;

  @override
  String toString() => '([1m$x,$y,$z[0m)';
} 

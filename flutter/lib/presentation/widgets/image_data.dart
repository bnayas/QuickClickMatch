// image_data.dart
import 'dart:typed_data';

class ImageData {
  final String id;
  final String src;
  final List<PointData> contour;
  Uint8List? bytes;
  ImageData(
      {required this.id, required this.src, required this.contour, this.bytes});

  // Add a copyWith method for partial updates
  ImageData copyWith(
      {String? id,
      String? src,
      List<PointData>? contour,
      Uint8List? bytes}) {
    return ImageData(
        id: id ?? this.id,
        src: src ?? this.src,
        contour: contour ?? this.contour,
        bytes: bytes ?? this.bytes);
  }

  factory ImageData.fromJson(Map<String, dynamic> json) {
    return ImageData(
      id: json['id'],
      src: json['src'],
      contour: (json['contour'] as List)
          .map((pt) => PointData.fromJson(pt))
          .toList(),
    );
  }
}

class PointData {
  final double x;
  final double y;
  PointData({required this.x, required this.y});

  factory PointData.fromJson(Map<String, dynamic> json) {
    return PointData(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
    );
  }
}

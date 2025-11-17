// image_data.dart
import 'package:image/image.dart' as img;

class ImageData {
  final String id;
  final String src;
  final List<PointData> contour;
  img.Image? image;
  ImageData(
      {required this.id, required this.src, required this.contour, this.image});

  // Add a copyWith method for partial updates
  ImageData copyWith(
      {String? id,
      String? src,
      List<PointData>? contour,
      img.Image? imageBytes}) {
    return ImageData(
        id: id ?? this.id,
        src: src ?? this.src,
        contour: contour ?? this.contour,
        image: image ?? this.image);
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

import 'package:latlong2/latlong.dart';

/// One imported boundary feature (조사지 경계 등), always stored in WGS84.
class GeoShape {
  final String name;
  final bool polygon; // true = closed area, false = open line
  final List<LatLng> points;
  const GeoShape({required this.name, required this.polygon, required this.points});

  Map<String, dynamic> toJson() => {
        'name': name,
        'polygon': polygon,
        // [lat, lon] pairs, rounded to ~1 cm to keep the file small
        'pts': [
          for (final p in points)
            [
              double.parse(p.latitude.toStringAsFixed(7)),
              double.parse(p.longitude.toStringAsFixed(7))
            ]
        ],
      };

  factory GeoShape.fromJson(Map<String, dynamic> j) => GeoShape(
        name: j['name'] as String? ?? '',
        polygon: j['polygon'] as bool? ?? true,
        points: [
          for (final e in (j['pts'] as List? ?? []))
            LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble())
        ],
      );
}

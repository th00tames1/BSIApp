import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'package:xml/xml.dart';

import '../l10n.dart';
import '../models/geo_shape.dart';

/// Thrown when a shapefile's CRS can't be determined (missing/unknown .prj)
/// and its coordinates are clearly projected — the caller must ask the user.
class NeedsCrsException implements Exception {
  final double sampleX, sampleY;
  NeedsCrsException(this.sampleX, this.sampleY);
  @override
  String toString() => 'CRS unknown (x=$sampleX, y=$sampleY)';
}

/// Imports survey-boundary geometry from KML/KMZ, GeoJSON, or ESRI Shapefile
/// and returns it in WGS84 for drawing on the map.
class GeoImport {
  /// Proj4 definitions for the CRSs Korean forestry data actually ships in.
  static const Map<String, String> crsDefs = {
    'EPSG:5179':
        '+proj=tmerc +lat_0=38 +lon_0=127.5 +k=0.9996 +x_0=1000000 +y_0=2000000 +ellps=GRS80 +units=m +no_defs',
    'EPSG:5186':
        '+proj=tmerc +lat_0=38 +lon_0=127 +k=1 +x_0=200000 +y_0=600000 +ellps=GRS80 +units=m +no_defs',
    'EPSG:5185':
        '+proj=tmerc +lat_0=38 +lon_0=125 +k=1 +x_0=200000 +y_0=600000 +ellps=GRS80 +units=m +no_defs',
    'EPSG:5187':
        '+proj=tmerc +lat_0=38 +lon_0=129 +k=1 +x_0=200000 +y_0=600000 +ellps=GRS80 +units=m +no_defs',
    'EPSG:5188':
        '+proj=tmerc +lat_0=38 +lon_0=131 +k=1 +x_0=200000 +y_0=600000 +ellps=GRS80 +units=m +no_defs',
    'EPSG:5174':
        '+proj=tmerc +lat_0=38 +lon_0=127.0028902777778 +k=1 +x_0=200000 +y_0=500000 +ellps=bessel +units=m +no_defs +towgs84=-115.8,474.99,674.11,1.16,-2.31,-1.63,6.43',
    'EPSG:32651': '+proj=utm +zone=51 +datum=WGS84 +units=m +no_defs',
    'EPSG:32652': '+proj=utm +zone=52 +datum=WGS84 +units=m +no_defs',
  };

  /// Human labels for the CRS picker (앱 언어에 따라 표기).
  static Map<String, String> get crsLabels => {
        'EPSG:5186': tr('Korea 2000 중부원점 (EPSG:5186)',
            'Korea 2000 Central Belt (EPSG:5186)'),
        'EPSG:5185':
            tr('Korea 2000 서부원점 (EPSG:5185)', 'Korea 2000 West Belt (EPSG:5185)'),
        'EPSG:5187':
            tr('Korea 2000 동부원점 (EPSG:5187)', 'Korea 2000 East Belt (EPSG:5187)'),
        'EPSG:5188': tr('Korea 2000 동해원점 (EPSG:5188)',
            'Korea 2000 East Sea Belt (EPSG:5188)'),
        'EPSG:5179': 'Korea 2000 UTM-K (EPSG:5179)',
        'EPSG:5174': tr('보정 중부원점 / Bessel (EPSG:5174)',
            'Modified Central Belt / Bessel (EPSG:5174)'),
        'EPSG:32652': 'WGS84 UTM 52N (EPSG:32652)',
        'EPSG:32651': 'WGS84 UTM 51N (EPSG:32651)',
      };

  static proj4.Projection _proj(String epsg) {
    final existing = proj4.Projection.get(epsg);
    if (existing != null) return existing;
    return proj4.Projection.add(epsg, crsDefs[epsg]!);
  }

  /// Load every recognised file in [paths] (a mixed selection is fine:
  /// .shp + .prj, a .zip bundle, .kml/.kmz, .geojson).
  /// [crsOverride] forces the shapefile CRS when the .prj is missing/unknown.
  static Future<List<GeoShape>> load(List<String> paths, {String? crsOverride}) async {
    final shapes = <GeoShape>[];
    // Group by extension so a .prj can be matched to its .shp.
    final byExt = <String, List<String>>{};
    for (final path in paths) {
      final ext = path.toLowerCase().split('.').last;
      (byExt[ext] ??= []).add(path);
    }

    for (final path in byExt['kml'] ?? const []) {
      shapes.addAll(parseKml(await File(path).readAsString()));
    }
    for (final path in byExt['kmz'] ?? const []) {
      shapes.addAll(_fromKmz(await File(path).readAsBytes()));
    }
    for (final path in [...?byExt['geojson'], ...?byExt['json']]) {
      shapes.addAll(parseGeoJson(await File(path).readAsString()));
    }
    for (final path in byExt['zip'] ?? const []) {
      shapes.addAll(await _fromZip(await File(path).readAsBytes(), crsOverride));
    }
    for (final path in byExt['shp'] ?? const []) {
      // Find a sibling .prj (same base name) among the selection.
      final base = path.substring(0, path.length - 4);
      String? prj;
      for (final c in byExt['prj'] ?? const []) {
        if (c.substring(0, c.length - 4) == base) prj = c;
      }
      prj ??= (byExt['prj'] ?? const []).cast<String?>().firstWhere((_) => true, orElse: () => null);
      final prjText = prj == null ? null : await File(prj).readAsString();
      shapes.addAll(parseShp(
        await File(path).readAsBytes(),
        epsg: crsOverride ?? (prjText == null ? null : detectCrs(prjText)),
      ));
    }
    return shapes;
  }

  static List<GeoShape> _fromKmz(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final out = <GeoShape>[];
    for (final f in archive.files) {
      if (f.isFile && f.name.toLowerCase().endsWith('.kml')) {
        out.addAll(parseKml(utf8.decode(f.content as List<int>, allowMalformed: true)));
      }
    }
    return out;
  }

  /// A zipped shapefile bundle (or a zip holding kml/geojson).
  static Future<List<GeoShape>> _fromZip(Uint8List bytes, String? crsOverride) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final out = <GeoShape>[];
    Uint8List? shp;
    String? prjText;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final n = f.name.toLowerCase();
      final data = f.content as List<int>;
      if (n.endsWith('.shp')) {
        shp = Uint8List.fromList(data);
      } else if (n.endsWith('.prj')) {
        prjText = utf8.decode(data, allowMalformed: true);
      } else if (n.endsWith('.kml')) {
        out.addAll(parseKml(utf8.decode(data, allowMalformed: true)));
      } else if (n.endsWith('.geojson') || n.endsWith('.json')) {
        out.addAll(parseGeoJson(utf8.decode(data, allowMalformed: true)));
      }
    }
    if (shp != null) {
      out.addAll(parseShp(shp,
          epsg: crsOverride ?? (prjText == null ? null : detectCrs(prjText))));
    }
    return out;
  }

  // ── KML ────────────────────────────────────────────────────────────
  static List<GeoShape> parseKml(String kml) {
    final doc = XmlDocument.parse(kml);
    final out = <GeoShape>[];
    // Match on local names so namespaced KML (kml22, gx) still parses.
    Iterable<XmlElement> local(XmlElement e, String name) =>
        e.descendants.whereType<XmlElement>().where((x) => x.name.local == name);

    for (final pm in doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'Placemark')) {
      final name = local(pm, 'name').isEmpty ? '' : local(pm, 'name').first.innerText.trim();
      for (final poly in local(pm, 'Polygon')) {
        // outer ring only (holes are rare in survey boundaries)
        final outer = poly.descendants
            .whereType<XmlElement>()
            .where((x) => x.name.local == 'outerBoundaryIs');
        final rings = outer.isNotEmpty ? outer : [poly];
        for (final r in rings) {
          for (final c in r.descendants
              .whereType<XmlElement>()
              .where((x) => x.name.local == 'coordinates')) {
            final pts = _kmlCoords(c.innerText);
            if (pts.length >= 3) out.add(GeoShape(name: name, polygon: true, points: pts));
          }
        }
      }
      for (final ls in local(pm, 'LineString')) {
        for (final c in ls.descendants
            .whereType<XmlElement>()
            .where((x) => x.name.local == 'coordinates')) {
          final pts = _kmlCoords(c.innerText);
          if (pts.length >= 2) out.add(GeoShape(name: name, polygon: false, points: pts));
        }
      }
    }
    return out;
  }

  static List<LatLng> _kmlCoords(String text) {
    final out = <LatLng>[];
    for (final tok in text.trim().split(RegExp(r'\s+'))) {
      final parts = tok.split(',');
      if (parts.length < 2) continue;
      final lon = double.tryParse(parts[0]);
      final lat = double.tryParse(parts[1]);
      if (lon == null || lat == null) continue;
      out.add(LatLng(lat, lon));
    }
    return out;
  }

  // ── GeoJSON ────────────────────────────────────────────────────────
  static List<GeoShape> parseGeoJson(String text) {
    final root = jsonDecode(text);
    final out = <GeoShape>[];
    void geometry(Map<String, dynamic> g, String name) {
      final type = g['type'] as String?;
      final c = g['coordinates'];
      switch (type) {
        case 'Polygon':
          for (final ring in (c as List)) {
            final pts = _gjRing(ring as List);
            if (pts.length >= 3) out.add(GeoShape(name: name, polygon: true, points: pts));
            break; // outer ring only
          }
        case 'MultiPolygon':
          for (final poly in (c as List)) {
            for (final ring in (poly as List)) {
              final pts = _gjRing(ring as List);
              if (pts.length >= 3) out.add(GeoShape(name: name, polygon: true, points: pts));
              break;
            }
          }
        case 'LineString':
          final pts = _gjRing(c as List);
          if (pts.length >= 2) out.add(GeoShape(name: name, polygon: false, points: pts));
        case 'MultiLineString':
          for (final line in (c as List)) {
            final pts = _gjRing(line as List);
            if (pts.length >= 2) out.add(GeoShape(name: name, polygon: false, points: pts));
          }
        case 'GeometryCollection':
          for (final sub in (g['geometries'] as List? ?? [])) {
            geometry(sub as Map<String, dynamic>, name);
          }
      }
    }

    if (root is Map<String, dynamic>) {
      if (root['type'] == 'FeatureCollection') {
        for (final f in (root['features'] as List? ?? [])) {
          final feat = f as Map<String, dynamic>;
          final props = feat['properties'] as Map<String, dynamic>? ?? {};
          final name = (props['name'] ?? props['NAME'] ?? props['이름'] ?? '').toString();
          final g = feat['geometry'];
          if (g is Map<String, dynamic>) geometry(g, name);
        }
      } else if (root['type'] == 'Feature') {
        final g = root['geometry'];
        if (g is Map<String, dynamic>) geometry(g, '');
      } else {
        geometry(root, '');
      }
    }
    return out;
  }

  static List<LatLng> _gjRing(List ring) {
    final out = <LatLng>[];
    for (final pt in ring) {
      if (pt is List && pt.length >= 2) {
        out.add(LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble()));
      }
    }
    return out;
  }

  // ── Shapefile ──────────────────────────────────────────────────────
  /// Identify a .prj WKT as one of [crsDefs]; null when unrecognised.
  static String? detectCrs(String prj) {
    final t = prj.toUpperCase();
    if (!t.contains('PROJCS')) return 'EPSG:4326'; // geographic → already lon/lat
    double? param(String key) {
      final m = RegExp('PARAMETER\\s*\\[\\s*"$key"\\s*,\\s*(-?[0-9.]+)', caseSensitive: false)
          .firstMatch(prj);
      return m == null ? null : double.tryParse(m.group(1)!);
    }

    final cm = param('central_meridian') ?? param('longitude_of_center');
    final fn = param('false_northing');
    final fe = param('false_easting');
    final bessel = t.contains('BESSEL');

    if (t.contains('UTM') || (fe == 500000 && fn == 0)) {
      if (t.contains('ZONE_52') || t.contains('ZONE 52') || cm == 129) return 'EPSG:32652';
      if (t.contains('ZONE_51') || t.contains('ZONE 51') || cm == 123) return 'EPSG:32651';
    }
    if (cm == 127.5 || fe == 1000000) return 'EPSG:5179';
    if (bessel && cm != null && (cm - 127.0028902777778).abs() < 0.01) return 'EPSG:5174';
    if (cm != null && fn == 600000) {
      if ((cm - 125).abs() < 0.01) return 'EPSG:5185';
      if ((cm - 127).abs() < 0.01) return 'EPSG:5186';
      if ((cm - 129).abs() < 0.01) return 'EPSG:5187';
      if ((cm - 131).abs() < 0.01) return 'EPSG:5188';
    }
    if (cm != null && fn == 500000 && (cm - 127).abs() < 0.01) return 'EPSG:5174';
    return null;
  }

  /// Parse the geometry (.shp) file. [epsg] is the source CRS; when null the
  /// coordinates must already look like lon/lat or [NeedsCrsException] is thrown.
  static List<GeoShape> parseShp(Uint8List bytes, {String? epsg}) {
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 100 || bd.getInt32(0, Endian.big) != 9994) {
      throw FormatException(
          tr('올바른 .shp 파일이 아닙니다', 'Not a valid .shp file'));
    }
    // Decide the transform up front from the file's bounding box.
    final xMin = bd.getFloat64(36, Endian.little);
    final yMin = bd.getFloat64(44, Endian.little);
    final looksLonLat = xMin.abs() <= 180 && yMin.abs() <= 90;
    String? code = epsg;
    if (code == null) {
      if (looksLonLat) {
        code = 'EPSG:4326';
      } else {
        throw NeedsCrsException(xMin, yMin);
      }
    }
    proj4.Projection? src;
    if (code != 'EPSG:4326') {
      src = _proj(code);
    }
    final dst = proj4.Projection.get('EPSG:4326')!;

    LatLng toLatLng(double x, double y) {
      if (src == null) return LatLng(y, x); // already lon/lat
      final p = src.transform(dst, proj4.Point(x: x, y: y));
      return LatLng(p.y, p.x);
    }

    final out = <GeoShape>[];
    int offset = 100;
    while (offset + 8 <= bytes.length) {
      final contentWords = bd.getInt32(offset + 4, Endian.big);
      final content = offset + 8;
      final contentBytes = contentWords * 2;
      if (contentBytes <= 0 || content + contentBytes > bytes.length) break;
      final type = bd.getInt32(content, Endian.little);

      if (type == 1 || type == 11 || type == 21) {
        // Point — skipped: a boundary overlay of single points isn't useful.
      } else if (type == 3 || type == 5 || type == 13 || type == 15 || type == 23 || type == 25) {
        final isPolygon = type == 5 || type == 15 || type == 25;
        int o = content + 4 + 32; // shape type + bbox
        final numParts = bd.getInt32(o, Endian.little);
        final numPoints = bd.getInt32(o + 4, Endian.little);
        o += 8;
        final parts = <int>[for (int i = 0; i < numParts; i++) bd.getInt32(o + i * 4, Endian.little)];
        o += numParts * 4;
        final ptsBase = o;
        for (int part = 0; part < numParts; part++) {
          final start = parts[part];
          final end = part + 1 < numParts ? parts[part + 1] : numPoints;
          final ring = <LatLng>[];
          for (int i = start; i < end; i++) {
            final px = ptsBase + i * 16;
            if (px + 16 > bytes.length) break;
            ring.add(toLatLng(
                bd.getFloat64(px, Endian.little), bd.getFloat64(px + 8, Endian.little)));
          }
          if (ring.length >= (isPolygon ? 3 : 2)) {
            out.add(GeoShape(name: '', polygon: isPolygon, points: ring));
          }
        }
      }
      offset = content + contentBytes;
    }
    return out;
  }
}

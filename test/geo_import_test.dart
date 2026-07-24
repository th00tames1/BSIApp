import 'dart:typed_data';

import 'package:bsi_field/src/services/geo_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a minimal one-polygon shapefile (.shp) from projected/geographic XY.
Uint8List buildShp(List<List<double>> pts) {
  const headerLen = 100;
  final contentBytes = 4 + 32 + 4 + 4 + 4 + pts.length * 16;
  final total = headerLen + 8 + contentBytes;
  final b = ByteData(total);

  final xs = pts.map((p) => p[0]).toList()..sort();
  final ys = pts.map((p) => p[1]).toList()..sort();

  b.setInt32(0, 9994, Endian.big); // file code
  b.setInt32(24, total ~/ 2, Endian.big); // length in 16-bit words
  b.setInt32(28, 1000, Endian.little); // version
  b.setInt32(32, 5, Endian.little); // polygon
  b.setFloat64(36, xs.first, Endian.little);
  b.setFloat64(44, ys.first, Endian.little);
  b.setFloat64(52, xs.last, Endian.little);
  b.setFloat64(60, ys.last, Endian.little);

  b.setInt32(100, 1, Endian.big); // record number
  b.setInt32(104, contentBytes ~/ 2, Endian.big); // content length (words)
  var o = 108;
  b.setInt32(o, 5, Endian.little); // shape type
  o += 4;
  b.setFloat64(o, xs.first, Endian.little);
  b.setFloat64(o + 8, ys.first, Endian.little);
  b.setFloat64(o + 16, xs.last, Endian.little);
  b.setFloat64(o + 24, ys.last, Endian.little);
  o += 32;
  b.setInt32(o, 1, Endian.little); // numParts
  b.setInt32(o + 4, pts.length, Endian.little); // numPoints
  o += 8;
  b.setInt32(o, 0, Endian.little); // parts[0]
  o += 4;
  for (final p in pts) {
    b.setFloat64(o, p[0], Endian.little);
    b.setFloat64(o + 8, p[1], Endian.little);
    o += 16;
  }
  return b.buffer.asUint8List();
}

void main() {
  group('shapefile', () {
    test('EPSG:5186 false origin maps to exactly lon 127 / lat 38', () {
      // Korea 2000 Central Belt 2010: x_0=200000, y_0=600000 at lat_0=38, lon_0=127.
      final shp = buildShp([
        [200000, 600000],
        [200100, 600000],
        [200100, 600100],
        [200000, 600100],
      ]);
      final shapes = GeoImport.parseShp(shp, epsg: 'EPSG:5186');
      expect(shapes, hasLength(1));
      expect(shapes.first.polygon, isTrue);
      final p0 = shapes.first.points.first;
      expect(p0.longitude, closeTo(127.0, 1e-6));
      expect(p0.latitude, closeTo(38.0, 1e-6));
      // 100 m east/north stays ~100 m away (sanity on scale).
      final p1 = shapes.first.points[1];
      expect(p1.longitude, greaterThan(p0.longitude));
      expect((p1.longitude - p0.longitude), closeTo(0.00114, 3e-4));
    });

    test('lon/lat shapefile without .prj is read as WGS84', () {
      final shp = buildShp([
        [129.4, 36.99],
        [129.41, 36.99],
        [129.41, 37.0],
      ]);
      final shapes = GeoImport.parseShp(shp); // no epsg
      expect(shapes, hasLength(1));
      expect(shapes.first.points.first.latitude, closeTo(36.99, 1e-9));
      expect(shapes.first.points.first.longitude, closeTo(129.4, 1e-9));
    });

    test('projected shapefile without CRS asks the user', () {
      final shp = buildShp([
        [200000, 600000],
        [200100, 600000],
        [200100, 600100],
      ]);
      expect(() => GeoImport.parseShp(shp), throwsA(isA<NeedsCrsException>()));
    });

    test('rejects a non-shapefile', () {
      expect(() => GeoImport.parseShp(Uint8List(120)), throwsA(isA<FormatException>()));
    });
  });

  group('prj detection', () {
    test('Korea 2000 Central Belt 2010', () {
      const prj =
          'PROJCS["Korea_2000_Korea_Central_Belt_2010",GEOGCS["GCS_Korea_2000",DATUM["D_Korea_2000",SPHEROID["GRS_1980",6378137.0,298.257222101]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]],PROJECTION["Transverse_Mercator"],PARAMETER["False_Easting",200000.0],PARAMETER["False_Northing",600000.0],PARAMETER["Central_Meridian",127.0],PARAMETER["Scale_Factor",1.0],PARAMETER["Latitude_Of_Origin",38.0],UNIT["Meter",1.0]]';
      expect(GeoImport.detectCrs(prj), 'EPSG:5186');
    });

    test('UTM-K (EPSG:5179)', () {
      const prj =
          'PROJCS["Korea_2000_Unified_Coordinate_System",GEOGCS["GCS_Korea_2000",DATUM["D_Korea_2000",SPHEROID["GRS_1980",6378137.0,298.257222101]]],PROJECTION["Transverse_Mercator"],PARAMETER["False_Easting",1000000.0],PARAMETER["False_Northing",2000000.0],PARAMETER["Central_Meridian",127.5],PARAMETER["Scale_Factor",0.9996],PARAMETER["Latitude_Of_Origin",38.0],UNIT["Meter",1.0]]';
      expect(GeoImport.detectCrs(prj), 'EPSG:5179');
    });

    test('geographic .prj is treated as lon/lat', () {
      const prj =
          'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]';
      expect(GeoImport.detectCrs(prj), 'EPSG:4326');
    });

    test('unknown projection returns null so the user is asked', () {
      const prj =
          'PROJCS["Weird",PROJECTION["Lambert_Conformal_Conic"],PARAMETER["False_Easting",4000000.0],PARAMETER["Central_Meridian",10.0],UNIT["Meter",1.0]]';
      expect(GeoImport.detectCrs(prj), isNull);
    });
  });

  group('kml / geojson', () {
    test('KML polygon + linestring, namespaced', () {
      const kml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
 <Document>
  <Placemark><name>임반 3-2</name>
   <Polygon><outerBoundaryIs><LinearRing><coordinates>
     129.40,36.99,0 129.41,36.99,0 129.41,37.00,0 129.40,36.99,0
   </coordinates></LinearRing></outerBoundaryIs></Polygon>
  </Placemark>
  <Placemark><name>조사선</name>
   <LineString><coordinates>129.40,36.99 129.42,37.01</coordinates></LineString>
  </Placemark>
 </Document>
</kml>''';
      final shapes = GeoImport.parseKml(kml);
      expect(shapes, hasLength(2));
      final poly = shapes.firstWhere((s) => s.polygon);
      expect(poly.name, '임반 3-2');
      expect(poly.points, hasLength(4));
      expect(poly.points.first.latitude, closeTo(36.99, 1e-9));
      expect(poly.points.first.longitude, closeTo(129.40, 1e-9));
      final line = shapes.firstWhere((s) => !s.polygon);
      expect(line.points, hasLength(2));
    });

    test('GeoJSON FeatureCollection with Polygon and MultiLineString', () {
      const gj = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","properties":{"name":"경계"},
  "geometry":{"type":"Polygon","coordinates":[[[129.4,36.99],[129.41,36.99],[129.41,37.0],[129.4,36.99]]]}},
 {"type":"Feature","properties":{},
  "geometry":{"type":"MultiLineString","coordinates":[[[129.4,36.99],[129.42,37.01]]]}}
]}''';
      final shapes = GeoImport.parseGeoJson(gj);
      expect(shapes, hasLength(2));
      final poly = shapes.firstWhere((s) => s.polygon);
      expect(poly.name, '경계');
      expect(poly.points.first.latitude, closeTo(36.99, 1e-9));
      expect(poly.points.first.longitude, closeTo(129.4, 1e-9));
      expect(shapes.firstWhere((s) => !s.polygon).points, hasLength(2));
    });
  });
}

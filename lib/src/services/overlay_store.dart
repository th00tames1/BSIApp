import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/geo_shape.dart';

/// Per-project boundary overlays (조사지 경계), stored as JSON on disk so a
/// large imported shapefile doesn't bloat SharedPreferences.
class OverlayStore {
  static Future<File> _file(String site) async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(dir.path, 'overlays'));
    if (!d.existsSync()) d.createSync(recursive: true);
    final safe = site.replaceAll(RegExp(r'[^0-9A-Za-z가-힣 _\-]'), '_');
    return File(p.join(d.path, '$safe.json'));
  }

  static Future<List<GeoShape>> load(String site) async {
    try {
      final f = await _file(site);
      if (!f.existsSync()) return [];
      final list = jsonDecode(await f.readAsString()) as List;
      return [for (final e in list) GeoShape.fromJson(e as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(String site, List<GeoShape> shapes) async {
    final f = await _file(site);
    await f.writeAsString(jsonEncode([for (final s in shapes) s.toJson()]), flush: true);
  }

  static Future<void> clear(String site) async {
    final f = await _file(site);
    if (f.existsSync()) await f.delete();
  }
}

import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/survey.dart';

class CsvExport {
  static const _header = [
    'tree_id', 'site', 'address', 'lat', 'lon', 'species', 'dbh_cm', 'model',
    'pole_len_m', 'bsi', 'mortality_prob', 'verdict',
    'face_azimuth', 'soot_height_m', 'soot_proportion', 'soot_proportion_whole',
    'soot_width_m', 'visible_stem_m', 'dbh_est_m', 'px_per_m', 'created_at',
  ];

  static List<List<Object?>> _rows(List<SurveyRecord> recs) {
    final rows = <List<Object?>>[_header];
    for (final r in recs) {
      final base = [
        r.treeId, r.site, r.address, r.lat, r.lon, r.species, r.dbhCm,
        r.modelName, r.poleLengthM, r.bsi, r.mortalityProb, r.verdict,
      ];
      if (r.faces.isEmpty) {
        rows.add([...base, '', '', '', '', '', '', '', '', r.createdAt.toIso8601String()]);
      }
      for (final f in r.faces) {
        rows.add([
          ...base, f.azimuth, f.sootHeightM, f.sootProportion, f.sootProportionWhole,
          f.sootWidthM, f.visibleStemHeightM, f.dbhEstM, f.pxPerMetre,
          r.createdAt.toIso8601String(),
        ]);
      }
    }
    return rows;
  }

  static Future<File> write(List<SurveyRecord> recs, {String name = 'bsi_export.csv'}) async {
    final csv = const ListToCsvConverter().convert(_rows(recs));
    final dir = await getApplicationDocumentsDirectory();
    final f = File(p.join(dir.path, name));
    await f.writeAsString(csv, flush: true);
    return f;
  }

  static Future<void> share(List<SurveyRecord> recs) async {
    final f = await write(recs);
    await SharePlus.instance.share(
      ShareParams(text: 'BSI survey export', files: [XFile(f.path)]),
    );
  }
}

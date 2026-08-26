import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_prefs.dart';
import '../models/survey.dart';
import 'raw_archive.dart';

class CsvExport {
  static const _header = [
    'tree_id', 'site', 'address', 'lat', 'lon', 'species', 'dbh_cm',
    'height_m', 'soot_max_m', 'model',
    'pole_len_m', 'pole_gap_m', 'bsi', 'mortality_prob', 'verdict',
    'face_azimuth', 'face_source', 'soot_height_m', 'soot_proportion',
    'soot_proportion_whole',
    'soot_width_m', 'visible_stem_m', 'dbh_est_m', 'px_per_m', 'scale_source',
    'created_at',
  ];

  /// NaN은 CSV에서 빈 칸으로 낸다.
  static Object? _v(double v) => v.isNaN ? null : v;

  /// 헤더와 각 행의 칸 수가 어긋나면 열이 통째로 밀린다. 테스트가 이걸 잡는다.
  @visibleForTesting
  static List<List<Object?>> rowsForTest(List<SurveyRecord> recs) => _rows(recs);

  static List<List<Object?>> _rows(List<SurveyRecord> recs) {
    final rows = <List<Object?>>[_header];
    for (final r in recs) {
      // 수고·그을음 높이는 상세 화면과 같은 유효값(수정값 우선, 없으면 계측 최대).
      final base = [
        r.treeId, r.site, r.address, r.lat, r.lon, r.species, r.dbhCm,
        _v(r.effectiveHeightM), _v(r.effectiveSootMaxM),
        r.modelName, r.poleLengthM, r.poleGapM,
        _v(r.bsi), _v(r.mortalityProb), r.verdict,
      ];
      if (r.faces.isEmpty) {
        rows.add([
          ...base, '', '', '', '', '', '', '', '', '', '',
          r.createdAt.toIso8601String()
        ]); // face 칸 10개 + created_at — 헤더 칸 수와 맞아야 한다(테스트가 검증)
      }
      for (final f in r.faces) {
        rows.add([
          ...base, f.azimuth,
          // 분석값인지 조사자가 직접 넣은 값인지 구분할 수 있어야 한다.
          f.manual
              ? 'manual' // 사진 없이 야장 값으로 채운 면
              : (f.manualEdited ? 'edited' : 'analysed'), // 분석 후 손으로 고친 면
          _v(f.sootHeightM), _v(f.sootProportion), _v(f.sootProportionWhole),
          _v(f.sootWidthM), _v(f.visibleStemHeightM), _v(f.dbhEstM), _v(f.pxPerMetre),
          f.scaleSource, // 'pole' | 'dbh'(흉고직경 추정, 정밀도 낮음) | 'manual' | ''
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

  /// 내보내기. 개발자 모드에서는 CSV에 더해 각 기록의 원시 번들(원본 사진·
  /// 촬영 메타·분석 산출물·마스크·record.json)과 사진·오버레이를 ZIP으로 묶는다.
  /// 일반 사용자는 CSV만 받는다.
  static Future<void> share(List<SurveyRecord> recs) async {
    final f = await write(recs);
    if (devMode.value) {
      final zip = await RawArchive.exportZip(recs, f);
      await SharePlus.instance.share(
        ShareParams(text: 'BSI survey export (raw bundle)', files: [XFile(zip.path)]),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(text: 'BSI survey export', files: [XFile(f.path)]),
    );
  }
}

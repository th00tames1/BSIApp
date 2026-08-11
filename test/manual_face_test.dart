import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:bsi_field/src/services/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// 촬영하지 못한 방위를 야장 값으로 채우면 그 면이 BSI 합에 들어가야 하고,
/// 재분석·저장을 거쳐도 "직접 입력"이라는 사실이 남아 있어야 한다.
void main() {
  final svc = AnalysisService.instance;

  AzimuthResult shot(String az, double h, double r) => AzimuthResult(
        azimuth: az,
        imagePath: '/p/$az.jpg',
        sootHeightM: h,
        sootProportion: r,
        analysed: true,
      );

  AzimuthResult manual(String az, double h, double r) => AzimuthResult(
        azimuth: az,
        sootHeightM: h,
        sootProportion: r,
        analysed: true,
        manual: true,
      );

  group('직접 입력 방위', () {
    test('BSI 합에 포함된다', () {
      final only2 = svc.integrate([shot('N', 2, .5), shot('S', 2, .5)], 30);
      final with4 = svc.integrate([
        shot('N', 2, .5),
        shot('S', 2, .5),
        manual('E', 2, .5),
        manual('W', 2, .5),
      ], 30);
      expect(only2.facesUsed, 2);
      expect(with4.facesUsed, 4);
      expect(with4.isPartial, isFalse);
      expect(with4.bsi, closeTo(4.0, 1e-9));
    });

    test('직접 입력 값이 다르면 BSI도 달라진다', () {
      final a = svc.integrate([shot('N', 2, .5), manual('S', 1, .5)], 30).bsi;
      final b = svc.integrate([shot('N', 2, .5), manual('S', 3, .5)], 30).bsi;
      expect(b, greaterThan(a));
    });

    test('manual 플래그가 JSON 왕복에서 살아남는다', () {
      final m = manual('E', 2.4, .61);
      final back = AzimuthResult.fromJson(m.toJson());
      expect(back.manual, isTrue);
      expect(back.sootHeightM, 2.4);
      expect(back.sootProportion, closeTo(.61, 1e-9));
      expect(back.imagePath, isNull);
    });

    test('기존 기록(manual 키 없음)은 분석값으로 읽힌다', () {
      final legacy = AzimuthResult.fromJson({
        'azimuth': 'N',
        'sootHeightM': 2.0,
        'sootProportion': 0.5,
        'analysed': true,
      });
      expect(legacy.manual, isFalse);
    });

    test('레코드 왕복(sqflite Map)에서도 유지된다', () {
      final rec = SurveyRecord(
        treeId: 'T1',
        site: 'S',
        address: '',
        species: '소나무',
        dbhCm: 30,
        modelName: 'YOLO26s@640',
        faces: [shot('N', 2, .5), manual('E', 2, .5)],
        createdAt: DateTime(2026, 8, 10),
      );
      final back = SurveyRecord.fromMap(rec.toMap());
      expect(back.faces.map((f) => f.manual).toList(), [false, true]);
    });

    test('재분석 대상 선별: 직접 입력은 제외되고 보존된다', () {
      final faces = [shot('N', 2, .5), manual('E', 2, .5), shot('S', 2, .5)];
      // saved_screen._reanalyse 와 같은 규칙
      final toReanalyse =
          faces.where((f) => !f.manual && f.imagePath != null).toList();
      final preserved = faces.where((f) => f.manual).toList();
      expect(toReanalyse.map((f) => f.azimuth), ['N', 'S']);
      expect(preserved.map((f) => f.azimuth), ['E']);
      expect(toReanalyse.length + preserved.length, faces.length);
    });
  });

  _csvTests();
  _prefillTests();
}

/// CSV는 헤더와 행의 칸 수가 어긋나면 열이 통째로 밀려 조용히 잘못된 표가 된다.
void _csvTests() {
  SurveyRecord rec(List<AzimuthResult> faces) => SurveyRecord(
        treeId: 'T1',
        site: 'S',
        address: '',
        species: '소나무',
        dbhCm: 30,
        modelName: 'YOLO26s@640',
        faces: faces,
        createdAt: DateTime(2026, 8, 10),
      );

  group('CSV 열 정합', () {
    test('모든 행이 헤더와 같은 칸 수를 갖는다', () {
      final rows = CsvExport.rowsForTest([
        rec([]), // 면 없음 분기
        rec([
          const AzimuthResult(
              azimuth: 'N', imagePath: '/p/n.jpg', sootHeightM: 2, analysed: true),
          const AzimuthResult(
              azimuth: 'E', sootHeightM: 2, analysed: true, manual: true),
        ]),
      ]);
      final width = rows.first.length;
      for (final r in rows) {
        expect(r.length, width);
      }
    });

    test('면의 출처가 analysed / manual 로 구분된다', () {
      final rows = CsvExport.rowsForTest([
        rec([
          const AzimuthResult(azimuth: 'N', imagePath: '/p/n.jpg', analysed: true),
          const AzimuthResult(azimuth: 'E', analysed: true, manual: true),
        ])
      ]);
      final i = rows.first.indexOf('face_source');
      expect(i, greaterThan(0));
      expect(rows[1][i], 'analysed');
      expect(rows[2][i], 'manual');
    });

    test('NaN은 빈 칸으로 나간다(문자열 NaN 금지)', () {
      final rows = CsvExport.rowsForTest([
        rec([const AzimuthResult(azimuth: 'N', imagePath: '/p/n.jpg', analysed: true)])
      ]);
      expect(rows[1].any((c) => c.toString().toLowerCase().contains('nan')), isFalse);
    });
  });
}

/// 프리필이 저장값보다 짧으면 값을 고치지 않고 저장만 눌러도 기록이 바뀐다.
/// manual_face_sheet 의 _fmt 와 같은 규칙을 여기서 고정한다.
String fmtPrefill(double? v) {
  if (v == null || v.isNaN) return '';
  final s = v.toStringAsFixed(2);
  return s.contains('.')
      ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : s;
}

void _prefillTests() {
  group('직접 입력 프리필', () {
    test('다시 열어 그대로 저장해도 값이 변하지 않는다', () {
      for (final pct in [12.5, 33.3, 5.4, 90.0, 0.0, 7.25]) {
        final stored = pct / 100;
        final reparsed = double.parse(fmtPrefill(stored * 100)) / 100;
        expect(reparsed, closeTo(stored, 1e-9), reason: '$pct %');
      }
    });

    test('군더더기 0이 붙지 않는다', () {
      expect(fmtPrefill(90), '90');
      expect(fmtPrefill(12.5), '12.5');
      expect(fmtPrefill(2.40), '2.4');
    });

    test('NaN·null은 빈 칸', () {
      expect(fmtPrefill(double.nan), '');
      expect(fmtPrefill(null), '');
    });
  });
}

import 'dart:math' as math;

import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/services/bsi_table.dart';
import 'package:bsi_field/src/services/csv_export.dart';
import 'package:bsi_field/src/services/mortality.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('판정표 데이터 무결성', () {
    test('격자 크기: BSI 1~25 × DBH 20~58(2cm 간격)', () {
      expect(BsiTable.percent, hasLength(25));
      expect(BsiTable.dbhCm, hasLength(20));
      expect(BsiTable.dbhCm.first, 20);
      expect(BsiTable.dbhCm.last, 58);
      for (final row in BsiTable.percent) {
        expect(row, hasLength(20));
        for (final v in row) {
          expect(v, inInclusiveRange(0, 100));
        }
      }
    });

    test('원본에서 뽑은 표본 값이 일치', () {
      int at(int bsi, int dbh) =>
          BsiTable.percent[bsi - 1][BsiTable.dbhCm.indexOf(dbh)];
      expect(at(1, 20), 10);
      expect(at(1, 58), 1);
      expect(at(6, 20), 30);
      expect(at(13, 20), 74);
      expect(at(16, 58), 27);
      expect(at(25, 20), 99);
      expect(at(25, 58), 81);
    });

    test('BSI가 오를수록·DBH가 굵을수록 단조', () {
      for (var j = 0; j < BsiTable.dbhCm.length; j++) {
        for (var i = 1; i < BsiTable.percent.length; i++) {
          expect(
            BsiTable.percent[i][j],
            greaterThanOrEqualTo(BsiTable.percent[i - 1][j]),
            reason: 'BSI ${i + 1}, DBH ${BsiTable.dbhCm[j]}',
          );
        }
      }
      for (final row in BsiTable.percent) {
        for (var j = 1; j < row.length; j++) {
          expect(row[j], lessThanOrEqualTo(row[j - 1]));
        }
      }
    });

    test('로지스틱 적합과 정수 반올림 오차(±0.51%p) 내에서 일치', () {
      // 원본 표를 만든 모형: logit = -0.9887 + 0.2720*BSI - 0.07528*DBH
      var maxDev = 0.0;
      for (var i = 0; i < BsiTable.percent.length; i++) {
        for (var j = 0; j < BsiTable.dbhCm.length; j++) {
          final z = -0.9887 + 0.2720 * (i + 1) - 0.07528 * BsiTable.dbhCm[j];
          final pred = 100 / (1 + math.exp(-z));
          final dev = (pred - BsiTable.percent[i][j]).abs();
          if (dev > maxDev) maxDev = dev;
        }
      }
      expect(maxDev, lessThan(0.6));
    });
  });

  group('조회', () {
    test('가장 가까운 칸을 찾는다', () {
      expect(BsiTable.lookup(1, 20), 10);
      expect(BsiTable.lookup(1.4, 20.9), 10); // 반올림 → BSI 1, DBH 20
      expect(BsiTable.lookup(6, 21), 30); // DBH 21 → 20이 더 가깝지 않음(동률)이 아니라 20
      expect(BsiTable.lookup(13, 20), 74);
    });

    test('표 범위를 벗어나면 null', () {
      expect(BsiTable.lookup(0.4, 30), isNull);
      expect(BsiTable.lookup(26, 30), isNull);
      expect(BsiTable.lookup(10, 5), isNull);
      expect(BsiTable.lookup(10, 100), isNull);
      expect(BsiTable.lookup(double.nan, 30), isNull);
    });

    test('벌채 기준은 30%', () {
      expect(BsiTable.isCut(29), isFalse);
      expect(BsiTable.isCut(30), isTrue);
      // 경계 칸: BSI 6·DBH 20 = 30%(벌채), BSI 6·DBH 22 = 27%(존치)
      expect(BsiTable.isCut(BsiTable.lookup(6, 20)!), isTrue);
      expect(BsiTable.isCut(BsiTable.lookup(6, 22)!), isFalse);
    });
  });

  group('앱 판정이 표와 일치', () {
    test('BSI만 정수 반올림하고 DBH 35 cm는 그대로 사용한다', () {
      expect(Mortality.bsiForDecision(14.49), 14);
      expect(Mortality.percent(14.49, 35), 54.5);
      expect((Mortality.probability(14.49, 35) * 100).round(), 55);
      expect(Mortality.verdict(14.49, 35), '벌채');
      expect(Mortality.percent(14.49, 34), 56);
      expect(Mortality.percent(14.49, 36), 53);
    });

    test('BSI 0.5 경계에서 올림하며 DBH 소수 실측값도 보존한다', () {
      expect(Mortality.bsiForDecision(14.49999), 14);
      expect(Mortality.bsiForDecision(14.5), 15);
      expect(Mortality.percent(14.5, 35), 61);
      expect(Mortality.percent(14.49, 35.25), 54.125);
    });

    test('확률 표시의 이진 소수 오차를 보정하고 실제 판정 기준은 유지한다', () {
      expect(Mortality.probabilityLabel(0.285), '29%');
      expect(Mortality.probabilityLabel(0.2849), '28%');
      expect(Mortality.probabilityLabel(0.545), '55%');
      expect(Mortality.probabilityLabel(double.nan), '–');
      expect(Mortality.verdict(10, 35), '존치');
    });

    test('30% 판정 경계도 반올림한 BSI로 결정한다', () {
      expect(Mortality.percent(5.49, 20), 24);
      expect(Mortality.verdict(5.49, 20), '존치');
      expect(Mortality.percent(5.5, 20), 30);
      expect(Mortality.verdict(5.5, 20), '벌채');
      expect(Mortality.percent(6, 21), 28.5);
      expect(Mortality.verdict(6, 21), '존치');
    });

    test('유효하지 않은 값은 반올림하거나 판정하지 않는다', () {
      expect(Mortality.bsiForDecision(double.nan).isNaN, isTrue);
      expect(Mortality.bsiForDecision(double.infinity).isNaN, isTrue);
      expect(Mortality.percent(double.infinity, 35).isNaN, isTrue);
      expect(Mortality.percent(14, double.infinity).isNaN, isTrue);
    });

    test('500칸 전부에서 확률·판정이 표와 동일', () {
      for (var i = 0; i < BsiTable.percent.length; i++) {
        final bsi = (i + BsiTable.minBsi).toDouble();
        for (var j = 0; j < BsiTable.dbhCm.length; j++) {
          final dbh = BsiTable.dbhCm[j].toDouble();
          final cell = BsiTable.percent[i][j];
          expect(
            Mortality.percent(bsi, dbh),
            closeTo(cell, 1e-9),
            reason: 'BSI $bsi, DBH $dbh',
          );
          expect(
            (Mortality.probability(bsi, dbh) * 100).round(),
            cell,
            reason: '화면 표시값 BSI $bsi, DBH $dbh',
          );
          expect(
            Mortality.verdict(bsi, dbh),
            BsiTable.isCut(cell) ? '벌채' : '존치',
            reason: 'BSI $bsi, DBH $dbh',
          );
        }
      }
    });

    test('격자 사이 값은 이웃 칸 사이로 보간된다', () {
      // BSI 10, DBH 26=44% / 28=41% → 27cm는 그 사이
      final v = Mortality.percent(10, 27);
      expect(v, greaterThan(41));
      expect(v, lessThan(44));
    });

    test('흉고직경이 없으면 판정하지 않는다', () {
      expect(Mortality.probability(10, 0).isNaN, isTrue);
      expect(Mortality.verdict(10, 0), '');
      expect(Mortality.verdict(double.nan, 30), '');
    });

    test('표 밖의 값은 가장자리로 고정', () {
      expect(Mortality.percent(30, 20), BsiTable.percent.last.first.toDouble());
      expect(
        Mortality.percent(0.2, 20),
        BsiTable.percent.first.first.toDouble(),
      );
      expect(Mortality.percent(10, 200), BsiTable.percent[9].last.toDouble());
    });
  });

  group('기존 기록과 원자료 보존', () {
    SurveyRecord oldRecord(List<AzimuthResult> faces) => SurveyRecord(
      treeId: '001',
      site: 'test',
      address: '',
      species: '소나무',
      dbhCm: 35,
      modelName: 'test',
      faces: faces,
      bsi: 14.49,
      mortalityProb: 0.58,
      verdict: '벌채',
      createdAt: DateTime.utc(2026, 10, 15),
    );

    test('기존 판정은 새 기준으로 계산하되 원본 BSI·DBH와 레코드는 그대로 둔다', () {
      final original = oldRecord([]);
      final current = Mortality.applyToRecord(original);
      expect(current.bsi, 14.49);
      expect(current.dbhCm, 35);
      expect(current.mortalityProb, 0.545);
      expect(original.mortalityProb, 0.58);
      final restored = SurveyRecord.fromMap(current.toMap());
      expect(restored.bsi, 14.49);
      expect(restored.dbhCm, 35);
    });

    test('CSV는 방위 유무와 관계없이 원본 BSI와 판정용 BSI를 함께 남긴다', () {
      final rows = CsvExport.rowsForTest([
        oldRecord([]),
        oldRecord([const AzimuthResult(azimuth: 'E')]),
      ]);
      final header = rows.first;
      for (final row in rows.skip(1)) {
        expect(row.length, header.length);
        expect(row[header.indexOf('bsi')], 14.49);
        expect(row[header.indexOf('bsi_for_decision')], 14);
        expect(row[header.indexOf('dbh_cm')], 35);
        expect(row[header.indexOf('mortality_prob')], 0.545);
      }
    });
  });
}

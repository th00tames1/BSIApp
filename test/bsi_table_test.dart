import 'dart:math' as math;

import 'package:bsi_field/src/services/bsi_table.dart';
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
          expect(BsiTable.percent[i][j],
              greaterThanOrEqualTo(BsiTable.percent[i - 1][j]),
              reason: 'BSI ${i + 1}, DBH ${BsiTable.dbhCm[j]}');
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
    test('500칸 전부에서 확률·판정이 표와 동일', () {
      for (var i = 0; i < BsiTable.percent.length; i++) {
        final bsi = (i + BsiTable.minBsi).toDouble();
        for (var j = 0; j < BsiTable.dbhCm.length; j++) {
          final dbh = BsiTable.dbhCm[j].toDouble();
          final cell = BsiTable.percent[i][j];
          expect(Mortality.percent(bsi, dbh), closeTo(cell, 1e-9),
              reason: 'BSI $bsi, DBH $dbh');
          expect((Mortality.probability(bsi, dbh) * 100).round(), cell,
              reason: '화면 표시값 BSI $bsi, DBH $dbh');
          expect(Mortality.verdict(bsi, dbh), BsiTable.isCut(cell) ? '벌채' : '존치',
              reason: 'BSI $bsi, DBH $dbh');
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
      expect(Mortality.percent(0.2, 20), BsiTable.percent.first.first.toDouble());
      expect(Mortality.percent(10, 200),
          BsiTable.percent[9].last.toDouble());
    });
  });
}

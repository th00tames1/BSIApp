import 'dart:math' as math;

import 'bsi_table.dart';

/// 산불피해목 고사 확률·존치/벌채 판정.
///
/// **발주처 판정표([BsiTable], 착수보고 v6 p.20)가 유일한 기준이다.** 앱이 보여주는
/// 값은 표에서 읽은 값과 반드시 일치해야 하므로, 표의 격자점(BSI 정수 1‥25,
/// DBH 20‥58 cm 2 cm 간격)에서는 표 값을 그대로 쓰고 그 사이만 이중선형 보간한다.
/// (근사 로지스틱으로 대체하면 경계 칸에서 판정이 뒤집힌다.)
///
/// 표는 DBH를 요구한다. 흉고직경이 없으면 판정 자체가 정의되지 않으므로
/// NaN·빈 문자열을 돌려주고, 화면이 "흉고직경을 입력하세요"로 안내한다.
class Mortality {
  Mortality._();

  /// 이 값 이상이면 벌채(표의 초록 경계와 동일).
  static const int cutThresholdPercent = BsiTable.cutThresholdPercent;

  /// 표와 같은 단위(%)의 고사 확률. 격자점에서는 표 값과 정확히 일치.
  static double percent(double bsi, double dbhCm) {
    if (bsi.isNaN || dbhCm.isNaN || dbhCm <= 0) return double.nan;
    final cols = BsiTable.dbhCm;

    // BSI 축 (표 밖은 가장자리 행으로 고정)
    final b = bsi.clamp(BsiTable.minBsi.toDouble(), BsiTable.maxBsi.toDouble());
    final b0 = b.floor().clamp(BsiTable.minBsi, BsiTable.maxBsi);
    final b1 = math.min(b0 + 1, BsiTable.maxBsi);
    final tb = b - b0;

    // DBH 축 (표 밖은 가장자리 열로 고정)
    final d = dbhCm.clamp(cols.first.toDouble(), cols.last.toDouble());
    var j0 = 0;
    while (j0 + 2 < cols.length && cols[j0 + 1] <= d) {
      j0++;
    }
    final j1 = math.min(j0 + 1, cols.length - 1);
    final span = cols[j1] - cols[j0];
    final td = span == 0 ? 0.0 : (d - cols[j0]) / span;

    double at(int bsiRow, int col) =>
        BsiTable.percent[bsiRow - BsiTable.minBsi][col].toDouble();
    final lo = at(b0, j0) + (at(b0, j1) - at(b0, j0)) * td;
    final hi = at(b1, j0) + (at(b1, j1) - at(b1, j0)) * td;
    return lo + (hi - lo) * tb;
  }

  /// 고사 확률 [0,1]. 판정 불가(흉고직경 미입력 등)이면 NaN.
  static double probability(double bsi, double dbhCm) {
    final p = percent(bsi, dbhCm);
    return p.isNaN ? double.nan : p / 100.0;
  }

  /// '존치' | '벌채' — 판정 불가이면 빈 문자열.
  static String verdict(double bsi, double dbhCm) {
    final p = percent(bsi, dbhCm);
    if (p.isNaN) return '';
    return p < cutThresholdPercent ? '존치' : '벌채';
  }
}

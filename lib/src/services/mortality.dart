import 'dart:math' as math;

import '../models/survey.dart';
import 'bsi_table.dart';

/// 산불피해목 고사 확률·존치/벌채 판정.
///
/// **발주처 판정표([BsiTable], 착수보고 v6 p.20)가 유일한 기준이다.** 앱이 보여주는
/// BSI는 정수로 반올림하고 DBH는 실측값을 유지한다. 원본 표의 DBH 열 사이에서는
/// 선형 보간한다. 표의 500개 격자점에서는 원본 값을 그대로 쓴다.
/// 원래 소수 BSI는 기록·분석 자료에 보존하고 판정용 값만 반올림한다.
///
/// 표는 DBH를 요구한다. 흉고직경이 없으면 판정 자체가 정의되지 않으므로
/// NaN·빈 문자열을 돌려주고, 화면이 "흉고직경을 입력하세요"로 안내한다.
class Mortality {
  Mortality._();

  /// 이 값 이상이면 벌채(표의 초록 경계와 동일).
  static const int cutThresholdPercent = BsiTable.cutThresholdPercent;

  /// 판정과 화면 표시가 함께 쓰는 BSI. 0.5는 올림하며 원본 값은 변경하지 않는다.
  static double bsiForDecision(double bsi) =>
      bsi.isFinite ? bsi.roundToDouble() : double.nan;

  /// 28.5%가 이진 소수 오차로 28.499999...가 되는 경우에도 같은 반올림을 쓴다.
  static int percentForDisplay(double probability) =>
      (probability * 100 + 1e-9).round();

  static String probabilityLabel(double probability) =>
      probability.isFinite ? '${percentForDisplay(probability)}%' : '–';

  /// 이전 판정 방식으로 저장된 기록도 원측정값을 보존하며 같은 기준으로 조회한다.
  static SurveyRecord applyToRecord(SurveyRecord record) => record.copyWith(
    mortalityProb: probability(record.bsi, record.dbhCm),
    verdict: verdict(record.bsi, record.dbhCm),
  );

  /// 표와 같은 단위(%)의 고사 확률. 격자점에서는 표 값과 정확히 일치.
  static double percent(double bsi, double dbhCm) {
    if (!bsi.isFinite || !dbhCm.isFinite || dbhCm <= 0) return double.nan;
    final cols = BsiTable.dbhCm;

    // 반올림한 정수 BSI 행을 쓰며 표 밖은 가장자리 행으로 고정한다.
    final b = bsiForDecision(
      bsi,
    ).clamp(BsiTable.minBsi.toDouble(), BsiTable.maxBsi.toDouble()).toInt();

    // DBH 축 (표 밖은 가장자리 열로 고정)
    final d = dbhCm.clamp(cols.first.toDouble(), cols.last.toDouble());
    var j0 = 0;
    while (j0 + 2 < cols.length && cols[j0 + 1] <= d) {
      j0++;
    }
    final j1 = math.min(j0 + 1, cols.length - 1);
    final span = cols[j1] - cols[j0];
    final td = span == 0 ? 0.0 : (d - cols[j0]) / span;

    double at(int col) => BsiTable.percent[b - BsiTable.minBsi][col].toDouble();
    return at(j0) + (at(j1) - at(j0)) * td;
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

import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// 재분석이 "재현 가능"하려면 같은 방위별 계측값에서 항상 같은 BSI가 나와야 하고,
/// 그을음 높이가 달라지면 BSI도 따라 달라져야 한다. 그 계약을 고정한다.
AzimuthResult face(String az, double heightM, double ratio) => AzimuthResult(
      azimuth: az,
      imagePath: '/tmp/$az.jpg',
      sootHeightM: heightM,
      sootProportion: ratio,
      analysed: true,
    );

void main() {
  final svc = AnalysisService.instance;

  group('통합 BSI', () {
    test('같은 입력이면 항상 같은 값이 나온다', () {
      List<AzimuthResult> faces() => [
            face('N', 2.0, 0.90),
            face('E', 2.5, 0.92),
            face('S', 2.2, 0.88),
            face('W', 2.4, 0.94),
          ];
      final a = svc.integrate(faces(), 30);
      final b = svc.integrate(faces(), 30);
      expect(a.bsi, b.bsi);
      expect(a.mortality, b.mortality);
      expect(a.verdict, b.verdict);
    });

    test('Σ(그을음 높이 × 면적비) — 4방위가 다 있으면 단순 합', () {
      final r = svc.integrate([
        face('N', 2.0, 0.5),
        face('E', 2.0, 0.5),
        face('S', 2.0, 0.5),
        face('W', 2.0, 0.5),
      ], 30);
      expect(r.bsi, closeTo(4.0, 1e-9)); // 1.0 × 4면
      expect(r.facesUsed, 4);
    });

    test('그을음 높이가 오르면 BSI도 오른다', () {
      final low = svc.integrate([face('N', 2.0, 0.9)], 30).bsi;
      final high = svc.integrate([face('N', 3.0, 0.9)], 30).bsi;
      expect(high, greaterThan(low));
      // 한 방위만 계측돼도 4방위로 환산한다.
      expect(low, closeTo(2.0 * 0.9 * 4, 1e-9));
    });

    test('계측된 방위 수로 환산해 부분 촬영도 4방위 규모로 맞춘다', () {
      final two = svc.integrate([face('N', 2.0, 0.5), face('S', 2.0, 0.5)], 30);
      final four = svc.integrate([
        face('N', 2.0, 0.5),
        face('E', 2.0, 0.5),
        face('S', 2.0, 0.5),
        face('W', 2.0, 0.5),
      ], 30);
      expect(two.bsi, closeTo(four.bsi, 1e-9));
      expect(two.facesUsed, 2);
      expect(two.isPartial, isTrue);
      expect(four.isPartial, isFalse);
    });

    test('계측 실패 면(NaN)은 합에서 빠진다', () {
      final r = svc.integrate([
        face('N', 2.0, 0.5),
        face('E', double.nan, 0.5), // 수고봉 미검출
        const AzimuthResult(azimuth: 'S'), // 분석 안 됨
      ], 30);
      expect(r.facesUsed, 1);
      expect(r.bsi, closeTo(4.0, 1e-9));
    });

    test('계측된 면이 하나도 없으면 BSI는 NaN', () {
      final r = svc.integrate([const AzimuthResult(azimuth: 'N')], 30);
      expect(r.bsi.isNaN, isTrue);
    });

    test('흉고직경은 BSI를 바꾸지 않고 판정만 바꾼다', () {
      List<AzimuthResult> f() => [face('N', 3.0, 0.9)];
      final thin = svc.integrate(f(), 22);
      final thick = svc.integrate(f(), 56);
      expect(thin.bsi, thick.bsi);
      expect(thin.mortality, greaterThan(thick.mortality));
    });
  });
}

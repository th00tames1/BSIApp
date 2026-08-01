import 'dart:convert';
import 'dart:io';

import 'package:bsi_field/src/services/pole_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 앱(Dart)의 스케일 계산이 **검증된 파이썬 기준 구현과 같은 답**을 내는지 확인한다.
///
/// fixture는 val 65장에 모델을 돌려 얻은 실제 검출점과, `4_code/pole/pole_scale.py`가
/// 그 점들로 계산한 px/m이다. 앱 정확도는 이 이식의 일치에 달려 있으므로, 규칙이
/// 한쪽만 바뀌면 여기서 깨져야 한다.
void main() {
  final f = File('test/fixtures/pole_scale_cases.json');

  test('fixture가 존재한다', () {
    expect(f.existsSync(), isTrue,
        reason: '4_code/pole 에서 fixture를 다시 생성해야 합니다');
  });

  test('49개 실제 사례에서 파이썬 기준과 px/m이 일치', () {
    final cases = (jsonDecode(f.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(cases, isNotEmpty);

    final mismatches = <String>[];
    for (final c in cases) {
      final pts = [
        for (final p in (c['points'] as List))
          PoleBoundary((p[0] as num).toDouble(), (p[1] as num).toDouble(), 0.9)
      ];
      final sol = PoleDetector.solve(pts, (c['width'] as num).toInt());
      final want = (c['px_per_m'] as num).toDouble();
      if (sol == null) {
        mismatches.add('${c['image']}: Dart는 해를 못 냄 (기준 $want)');
        continue;
      }
      final rel = (sol.pxPerMetre - want).abs() / want;
      if (rel > 0.001) {
        mismatches.add(
            '${c['image']}: Dart ${sol.pxPerMetre.toStringAsFixed(2)} vs 기준 '
            '${want.toStringAsFixed(2)} (${(rel * 100).toStringAsFixed(2)}%)');
      }
      expect(sol.boundaryCount, c['n_boundaries'],
          reason: '${c['image']} 봉 군집 결과가 다름');
      expect(sol.perspectiveCorrected, c['perspective'],
          reason: '${c['image']} 원근 보정 적용 여부가 다름');
    }
    expect(mismatches, isEmpty,
        reason: '파이썬 기준과 어긋남:\n${mismatches.join('\n')}');
  });
}

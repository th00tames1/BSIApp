import 'dart:typed_data';

import 'package:bsi_field/src/services/pole_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// 세로로 늘어선 경계점을 만든다(간격 목록으로 지정).
List<PoleBoundary> column(double x, double y0, List<double> gaps) {
  final pts = [PoleBoundary(x, y0, 0.9)];
  var y = y0;
  for (final g in gaps) {
    y += g;
    pts.add(PoleBoundary(x, y, 0.9));
  }
  return pts;
}

void main() {
  group('px/m 산출', () {
    test('간격이 고르면 그 값이 곧 1 m', () {
      final s = PoleDetector.solve(column(400, 100, [220, 218, 222]), 960)!;
      expect(s.pxPerMetre, closeTo(220, 3));
      expect(s.boundaryCount, 4);
    });

    test('경계 간격 설정: 0.5 m 봉이면 px/m이 2배가 된다', () {
      final one = PoleDetector.solve(column(400, 100, [220, 218, 222]), 960)!;
      final half = PoleDetector.solve(column(400, 100, [220, 218, 222]), 960,
          gapMetres: 0.5)!;
      expect(half.pxPerMetre, closeTo(one.pxPerMetre * 2, 1e-6));
      // 국소 배율(원근 보정 경로)도 같은 배율로 환산돼야 한다.
      expect(half.pxPerMetreAt(400, 300),
          closeTo(one.pxPerMetreAt(400, 300) * 2, 1e-6));
    });

    test('경계 간격 설정: 2 m 봉이면 px/m이 절반이 된다', () {
      final s = PoleDetector.solve(column(400, 100, [220, 218, 222]), 960,
          gapMetres: 2.0)!;
      expect(s.pxPerMetre, closeTo(110, 2));
    });

    test('가려져 건너뛴 경계(2 m 간격)를 정수배로 되돌린다', () {
      final s = PoleDetector.solve(column(400, 100, [200, 400, 200]), 960)!;
      expect(s.pxPerMetre, closeTo(200, 5));
    });

    test('2 m 간격이 섞이고 간격이 짝수여도 2배로 틀어지지 않는다', () {
      // 회귀 테스트: 중앙값을 그대로 쓰면 548.8을 1 m로 골라 스케일이 2배가 된다
      final s = PoleDetector.solve(column(400, 100, [231.2, 548.8]), 960)!;
      expect(s.pxPerMetre, closeTo(274, 12));
      expect(s.pxPerMetre, lessThan(400));
    });

    test('한 경계에 중복 검출이 있어도 무너지지 않는다', () {
      final pts = column(400, 100, [220, 220, 220]);
      pts.add(PoleBoundary(401, 321, 0.8)); // 두 번째 경계 바로 옆 중복
      final s = PoleDetector.solve(pts, 960)!;
      expect(s.pxPerMetre, closeTo(220, 8));
    });

    test('경계가 하나뿐이면 스케일을 만들지 않는다', () {
      expect(PoleDetector.solve([const PoleBoundary(400, 100, 0.9)], 960), isNull);
    });
  });

  group('봉이 둘일 때', () {
    test('경계가 더 많은 봉을 고르고 두 봉을 섞지 않는다', () {
      final near = column(300, 100, [300, 300, 300]); // 가까운 봉(4점)
      final far = column(800, 200, [120, 120]); // 먼 봉(3점)
      final s = PoleDetector.solve([...near, ...far], 960)!;
      expect(s.boundaryCount, 4);
      expect(s.pxPerMetre, closeTo(300, 10)); // 먼 봉의 120이 섞이면 실패
    });
  });

  group('원근 보정', () {
    test('간격이 일정하면 국소 배율도 거의 일정', () {
      final s = PoleDetector.solve(column(400, 100, [220, 220, 220]), 960)!;
      final a = s.pxPerMetreAt(400, 150);
      final b = s.pxPerMetreAt(400, 700);
      expect((a - b).abs() / a, lessThan(0.05));
    });

    test('간격이 위로 갈수록 줄면 국소 배율도 그 방향으로 변한다', () {
      // 봉이 카메라에서 멀어지며 위로 갈수록 1 m가 짧아지는 상황
      final s = PoleDetector.solve(column(400, 800, [-260, -230, -205]), 960)!;
      expect(s.perspectiveCorrected, isTrue);
      final low = s.pxPerMetreAt(400, 780); // 아래(가까움) → 큰 배율
      final high = s.pxPerMetreAt(400, 120); // 위(멂) → 작은 배율
      expect(low, greaterThan(high));
      // 관측 범위 안에서는 대표값의 0.5~2배를 벗어나지 않아야 한다
      for (final v in [low, high]) {
        expect(v, greaterThan(0.5 * s.pxPerMetre));
        expect(v, lessThan(2.0 * s.pxPerMetre));
      }
    });

    test('점이 3개뿐이면 사영 적합을 쓰지 않는다(노이즈 증폭 방지)', () {
      final s = PoleDetector.solve(column(400, 100, [220, 215]), 960)!;
      expect(s.perspectiveCorrected, isFalse);
      expect(s.pxPerMetreAt(400, 500), s.pxPerMetre);
    });

    test('봉 범위 밖으로 외삽하지 않는다', () {
      final s = PoleDetector.solve(column(400, 100, [-250, -230, -210]), 960)!;
      final far = s.pxPerMetreAt(400, -5000);
      expect(far.isFinite, isTrue);
      expect(far, greaterThan(0));
    });
  });

  group('검출 디코딩', () {
    test('dense 출력에서 점수 임계값과 중복 병합이 동작', () {
      const n = 6, ch = 5;
      final out = List<double>.filled(ch * n, 0.0);
      void put(int i, double cx, double cy, double sc) {
        out[i] = cx;
        out[n + i] = cy;
        out[2 * n + i] = 20;
        out[3 * n + i] = 20;
        out[4 * n + i] = sc;
      }
      put(0, 100, 100, 0.9);
      put(1, 103, 102, 0.8); // 중복 — 병합돼야 함
      put(2, 100, 300, 0.7);
      put(3, 100, 500, 0.6);
      put(4, 100, 700, 0.1); // 임계값 미만
      put(5, 100, 900, 0.05); // 임계값 미만
      final pts = PoleDetector.decode(_f32(out), [1, ch, n], 640);
      expect(pts.length, 3);
      expect(pts.first.score, closeTo(0.9, 1e-6));
    });

    test('end-to-end 출력(x1,y1,x2,y2,score,cls)에서도 중심점을 뽑는다', () {
      // YOLO26 내보내기 형식: [1, n, 6]. NMS가 이미 적용돼 나온다.
      const n = 8;
      final out = List<double>.filled(n * 6, 0.0);
      void put(int i, double cx, double cy, double sc) {
        out[i * 6 + 0] = cx - 10;
        out[i * 6 + 1] = cy - 10;
        out[i * 6 + 2] = cx + 10;
        out[i * 6 + 3] = cy + 10;
        out[i * 6 + 4] = sc;
      }
      put(0, 100, 100, 0.9);
      put(1, 100, 300, 0.7);
      put(2, 100, 500, 0.6);
      put(3, 100, 700, 0.1); // 임계값 미만
      // 남은 칸은 점수 0이라 걸러진다
      final pts = PoleDetector.decode(_f32(out), [1, n, 6], 640);
      expect(pts.length, 3);
      expect(pts.first.x, closeTo(100, 1e-6));
      expect(pts.first.y, closeTo(100, 1e-6));
      expect(pts.first.score, closeTo(0.9, 1e-6));
    });
  });

  group('기기 독립성', () {
    // 스케일은 같은 사진 안의 수고봉에서 나오므로 초점거리·센서·해상도가 상쇄된다.
    // 같은 장면을 배율만 바꿔 넣으면 px/m은 배율만큼 변하고 실제 치수는 그대로여야 한다.
    test('해상도가 달라도 환산한 실제 길이는 같다', () {
      double spanMetres(double k) {
        final size = (640 * k).round();
        final pts = [
          for (var i = 0; i < 4; i++)
            PoleBoundary(0.5 * size, (100 + 120.0 * i) * k, 0.9)
        ];
        final sol = PoleDetector.solve(pts, size);
        expect(sol, isNotNull, reason: '배율 $k에서 스케일을 못 세움');
        final topY = 100.0 * k, botY = (100 + 120.0 * 3) * k;
        return (botY - topY) / sol!.pxPerMetre;
      }

      final base = spanMetres(1.0);
      expect(base, closeTo(3.0, 1e-6)); // 경계 4개 = 1 m 간격 3구간
      for (final k in [0.5, 0.75, 1.5, 2.0]) {
        expect(spanMetres(k), closeTo(base, 1e-6),
            reason: '배율 $k에서 실제 길이가 달라짐');
      }
    });

    test('px/m 자체는 해상도에 비례한다', () {
      double pxPerM(double k) {
        final size = (640 * k).round();
        final pts = [
          for (var i = 0; i < 4; i++)
            PoleBoundary(0.5 * size, (100 + 120.0 * i) * k, 0.9)
        ];
        return PoleDetector.solve(pts, size)!.pxPerMetre;
      }

      expect(pxPerM(2.0) / pxPerM(1.0), closeTo(2.0, 1e-6));
      expect(pxPerM(0.5) / pxPerM(1.0), closeTo(0.5, 1e-6));
    });
  });
}

/// double 리스트 → Float32List
Float32List _f32(List<double> v) {
  final f = Float32List(v.length);
  for (var i = 0; i < v.length; i++) {
    f[i] = v[i];
  }
  return f;
}

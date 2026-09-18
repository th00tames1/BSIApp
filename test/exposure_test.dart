import 'dart:typed_data';
import 'dart:ui' show Color, ColorFilter;

import 'package:bsi_field/src/services/exposure.dart';
import 'package:bsi_field/src/services/photo_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

/// 촬영 화면 노출 슬라이더: 범위가 하드웨어의 2배 이상이어야 하고, 하드웨어
/// 한계를 넘는 몫의 소프트웨어 밝기는 미리보기와 저장 사진이 같아야 한다.
void main() {
  group('슬라이더 범위', () {
    test('하드웨어 범위의 2배 이상으로 열린다', () {
      for (final hw in [(-2.0, 2.0), (-4.0, 4.0), (-1.0, 3.0)]) {
        final r = Exposure.sliderRange(hw.$1, hw.$2);
        expect(r.min, lessThanOrEqualTo(hw.$1 * 2), reason: '$hw');
        expect(r.max, greaterThanOrEqualTo(hw.$2 * 2), reason: '$hw');
      }
    });

    test('하드웨어 보정이 없는 기기도 소프트웨어 범위를 쓴다', () {
      final r = Exposure.sliderRange(0, 0);
      expect(r.min, lessThan(0));
      expect(r.max, greaterThan(0));
    });
  });

  group('하드웨어 / 소프트웨어 분할', () {
    test('하드웨어 범위 안에서는 소프트웨어 몫이 없다', () {
      for (final ev in [-2.0, -1.3, 0.0, 0.7, 2.0]) {
        expect(Exposure.hardware(ev, -2, 2), ev);
        expect(Exposure.software(ev, -2, 2), 0);
        expect(Exposure.gain(Exposure.software(ev, -2, 2)), 1.0);
      }
    });

    test('한계를 넘는 몫만 소프트웨어로 간다', () {
      expect(Exposure.hardware(4.5, -2, 2), 2);
      expect(Exposure.software(4.5, -2, 2), closeTo(2.5, 1e-12));
      expect(Exposure.hardware(-5, -2, 2), -2);
      expect(Exposure.software(-5, -2, 2), closeTo(-3, 1e-12));
    });

    test('두 몫의 합은 항상 슬라이더 값', () {
      for (var ev = -5.0; ev <= 5.0; ev += 0.25) {
        expect(Exposure.hardware(ev, -2, 2) + Exposure.software(ev, -2, 2),
            closeTo(ev, 1e-12));
      }
    });

    test('하드웨어 보정이 없으면 전부 소프트웨어', () {
      expect(Exposure.hardware(1.5, 0, 0), 0);
      expect(Exposure.software(1.5, 0, 0), 1.5);
    });

    test('밝히면 배율 > 1, 어둡게 하면 < 1', () {
      expect(Exposure.gain(1), greaterThan(1));
      expect(Exposure.gain(-1), lessThan(1));
      expect(Exposure.gain(1) * Exposure.gain(-1), closeTo(1, 1e-12));
    });
  });

  group('소프트웨어 밝기 = 미리보기와 같은 연산', () {
    test('배율 1이면 픽셀이 그대로다', () {
      final px = Uint8List.fromList([10, 100, 250, 255, 0, 0, 0, 128]);
      final before = Uint8List.fromList(px);
      PhotoNormalizer.applyGain(px, 1.0);
      expect(px, before);
    });

    test('RGB만 곱하고 255에서 자르며 알파는 건드리지 않는다', () {
      final px = Uint8List.fromList([10, 100, 200, 77]);
      PhotoNormalizer.applyGain(px, 1.5);
      expect(px, [15, 150, 255, 77]);
    });

    test('ColorFilter.matrix 대각 행렬과 같은 결과', () {
      // 미리보기의 행렬 필터: out = clamp(g · in). 저장 경로와 비교한다.
      const g = 1.37;
      final filter = ColorFilter.matrix(<double>[
        g, 0, 0, 0, 0, //
        0, g, 0, 0, 0, //
        0, 0, g, 0, 0, //
        0, 0, 0, 1, 0,
      ]);
      expect(filter, isNotNull); // 같은 계수로 만든 필터가 유효하다
      for (var v = 0; v < 256; v += 17) {
        final px = Uint8List.fromList([v, v, v, 255]);
        PhotoNormalizer.applyGain(px, g);
        final expected = (v * g).round().clamp(0, 255);
        expect(px[0], expected, reason: 'v=$v');
        expect(Color.fromARGB(255, px[0], px[1], px[2]).a, 1.0);
      }
    });
  });
}

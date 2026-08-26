import 'dart:io';

import 'package:bsi_field/src/services/auto_tone.dart';
import 'package:bsi_field/src/services/image_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image _flat(int v, {int w = 320, int h = 420}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(v, v, v));
  return im;
}

void main() {
  group('역광 자동 보정 발동 기준', () {
    test('검증용 예시 사진 4장에는 발동하지 않는다(기준값 보존)', () {
      for (final az in ['N', 'E', 'S', 'W']) {
        final f = File('assets/sample/demo_$az.jpg');
        expect(f.existsSync(), isTrue);
        final src = ImageOps.normalizeResolution(
            img.decodeImage(f.readAsBytesSync())!);
        final lb = ImageOps.letterbox(src, 640); // 기본 = 자동 판단
        expect(lb.toneApplied, isFalse, reason: 'demo_$az');
      }
    });

    test('어둡게 깔린 사진에는 발동한다', () {
      // 아래 2/3는 어둡고 위는 하늘처럼 밝은, 역광에 가까운 그림
      final im = img.Image(width: 480, height: 640);
      for (var y = 0; y < 640; y++) {
        for (var x = 0; x < 480; x++) {
          final v = y < 200 ? 235 : 28 + (x % 7);
          im.setPixelRgb(x, y, v, v, v);
        }
      }
      final stats = AutoTone.measure(im);
      expect(stats.needsTone, isTrue);
      final lb = ImageOps.letterbox(im, 320);
      expect(lb.toneApplied, isTrue);
    });

    test('끄면 밝기 통계와 무관하게 그대로 둔다', () {
      final lb = ImageOps.letterbox(_flat(20), 320, autoTone: false);
      expect(lb.toneApplied, isFalse);
    });
  });

  group('CLAHE', () {
    test('어두운 영역의 대비가 살아난다(평탄한 면은 값이 유지)', () {
      // 어두운 배경에 조금 더 밝은 줄기 — 대비가 벌어져야 한다.
      final im = img.Image(width: 256, height: 256);
      for (var y = 0; y < 256; y++) {
        for (var x = 0; x < 256; x++) {
          final v = (x > 110 && x < 146) ? 46 : 30;
          im.setPixelRgb(x, y, v, v, v);
        }
      }
      final out = AutoTone.applyClahe(im);
      final stem = out.getPixel(128, 128).r.toInt();
      final bg = out.getPixel(20, 128).r.toInt();
      expect(stem - bg, greaterThan(46 - 30)); // 대비 확대
      expect(stem, greaterThan(46)); // 어두운 쪽이 밝아졌다
    });

    test('색 비율은 유지된다(수간·그을음 색 관계 보존)', () {
      final im = img.Image(width: 128, height: 128);
      for (var y = 0; y < 128; y++) {
        for (var x = 0; x < 128; x++) {
          final k = y < 64 ? 1.0 : 2.0; // 위/아래 밝기만 다른 같은 색조
          im.setPixelRgb(x, y, (20 * k).round(), (40 * k).round(), (60 * k).round());
        }
      }
      final out = AutoTone.applyClahe(im);
      final p = out.getPixel(64, 100);
      expect(p.g / p.r, closeTo(2.0, 0.35));
      expect(p.b / p.r, closeTo(3.0, 0.5));
    });

    test('출력이 0~255를 벗어나지 않는다', () {
      final out = AutoTone.applyClahe(_flat(250, w: 128, h: 128));
      for (final px in out) {
        expect(px.r, inInclusiveRange(0, 255));
        expect(px.g, inInclusiveRange(0, 255));
        expect(px.b, inInclusiveRange(0, 255));
      }
    });
  });
}

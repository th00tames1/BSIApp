import 'dart:io';

import 'package:bsi_field/src/services/image_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  group('해상도 정규화 (카메라 원본 = 예시 사진 경로)', () {
    test('예시 사진 크기(960×1280)는 손대지 않는다 — 검증 기준값 유지', () {
      final src = img.Image(width: 960, height: 1280);
      final out = ImageOps.normalizeResolution(src);
      expect(identical(out, src), isTrue);
    });

    test('카메라 원본(4080×3060)은 긴 변 1280으로 줄어 예시 사진과 같은 크기가 된다', () {
      final src = img.Image(width: 3060, height: 4080); // 세로(EXIF 적용 후)
      final out = ImageOps.normalizeResolution(src);
      expect(out.width, 960);
      expect(out.height, 1280);
    });

    test('가로 사진도 긴 변 기준으로 맞춘다', () {
      final out = ImageOps.normalizeResolution(img.Image(width: 4000, height: 3000));
      expect(out.width, 1280);
      expect(out.height, 960);
    });

    test('정규화 후 letterbox 결과는 예시 사진과 같은 기하(480×640 콘텐츠, 좌우 80 패딩)', () {
      final big = img.Image(width: 3060, height: 4080);
      final lb = ImageOps.letterbox(ImageOps.normalizeResolution(big), 640);
      expect(lb.padX, 80);
      expect(lb.padY, 0);
      expect(lb.scale, closeTo(0.5, 1e-9));
    });

    test('면적 평균 축소는 밝기 평균을 보존한다(bilinear 점 표본과 달리)', () {
      // 1픽셀 간격 흑백 줄무늬 → 6배 축소 시 평균 회색(~127)이어야 한다.
      final src = img.Image(width: 3072, height: 3072);
      for (var y = 0; y < src.height; y++) {
        for (var x = 0; x < src.width; x++) {
          final v = (x % 2 == 0) ? 255 : 0;
          src.setPixelRgb(x, y, v, v, v);
        }
      }
      final out = ImageOps.normalizeResolution(src);
      final p = out.getPixel(out.width ~/ 2, out.height ~/ 2);
      expect(p.r, inInclusiveRange(100, 155));
    });

    test('실제 예시 사진을 카메라 해상도(2배)로 키운 뒤 정규화하면 픽셀 단위로 원본과 같다', () {
      final f = File('assets/sample/demo_N.jpg');
      expect(f.existsSync(), isTrue);
      final orig = img.decodeImage(f.readAsBytesSync())!;
      expect(orig.width, 960);
      expect(orig.height, 1280);
      final big = img.copyResize(orig,
          width: orig.width * 2,
          height: orig.height * 2,
          interpolation: img.Interpolation.nearest);
      final norm = ImageOps.normalizeResolution(big);
      expect(norm.width, orig.width);
      expect(norm.height, orig.height);
      var diff = 0;
      for (var y = 0; y < orig.height; y += 7) {
        for (var x = 0; x < orig.width; x += 5) {
          final a = orig.getPixel(x, y), b = norm.getPixel(x, y);
          if (a.r != b.r || a.g != b.g || a.b != b.b) diff++;
        }
      }
      expect(diff, 0);
    });
  });
}

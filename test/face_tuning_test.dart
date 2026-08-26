import 'dart:typed_data';

import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/models/tuning.dart';
import 'package:bsi_field/src/services/image_ops.dart';
import 'package:bsi_field/src/services/seg_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// end-to-end 출력([1, n, 6+nm])을 흉내 낸 검출 텐서.
/// 상자마다 마스크 계수는 자기 프로토타입 하나만 1로 둔다.
({Float32List det, List<int> shape, Float32List proto, List<int> protoShape})
    fakeModel({
  required int size,
  required int mh,
  required List<({double x1, double y1, double x2, double y2, int cls})> boxes,
}) {
  final nm = boxes.length;
  final feat = 6 + nm;
  final det = Float32List(boxes.length * feat);
  for (var i = 0; i < boxes.length; i++) {
    final b = boxes[i];
    final o = i * feat;
    det[o] = b.x1;
    det[o + 1] = b.y1;
    det[o + 2] = b.x2;
    det[o + 3] = b.y2;
    det[o + 4] = 0.9; // conf
    det[o + 5] = b.cls.toDouble();
    det[o + 6 + i] = 20.0; // 자기 proto만 크게(sigmoid≈1)
  }
  // proto[i]는 상자 i 영역만 1인 평면.
  final proto = Float32List(nm * mh * mh);
  final f = mh / size;
  for (var i = 0; i < nm; i++) {
    final b = boxes[i];
    for (var y = (b.y1 * f).floor(); y < (b.y2 * f).ceil(); y++) {
      for (var x = (b.x1 * f).floor(); x < (b.x2 * f).ceil(); x++) {
        if (y < 0 || y >= mh || x < 0 || x >= mh) continue;
        proto[i * mh * mh + y * mh + x] = 1.0;
      }
    }
  }
  return (
    det: det,
    shape: [1, boxes.length, feat],
    proto: proto,
    protoShape: [1, nm, mh, mh],
  );
}

void main() {
  const size = 640, mh = 160;

  group('대상목 선택 (옆·뒤 나무 오검출)', () {
    // 중앙의 조사목(폭 좁음)과, 화면 가장자리의 더 큰 옆 나무.
    final boxes = [
      (x1: 290.0, y1: 120.0, x2: 350.0, y2: 620.0, cls: kTree), // 중앙 대상목
      (x1: 430.0, y1: 40.0, x2: 620.0, y2: 600.0, cls: kTree), // 옆 큰 나무
    ];

    test('면적이 더 커도 화면 중앙의 나무를 고른다', () {
      final m = fakeModel(size: size, mh: mh, boxes: boxes);
      final fa = SegDecoder.analyze(
          m.det, m.shape, m.proto, m.protoShape, size);
      // 중앙 상자(약 60px 폭)만 잡혔는지 — 가로 범위로 확인
      final s = fa.treeSpanAtRow(fa.treeBottom - 5)!;
      expect(s.lo * (size / mh), lessThan(360));
      expect(s.hi * (size / mh), lessThan(360));
    });

    test('수고봉이 옆 나무 쪽에 있으면 그 나무를 고른다', () {
      final m = fakeModel(size: size, mh: mh, boxes: boxes);
      final fa = SegDecoder.analyze(
          m.det, m.shape, m.proto, m.protoShape, size,
          poleHintX: 560);
      final s = fa.treeSpanAtRow(fa.treeBottom - 5)!;
      expect(s.hi * (size / mh), greaterThan(400));
    });

    test('조사자가 줄기를 찍으면 그 나무가 최우선', () {
      final m = fakeModel(size: size, mh: mh, boxes: boxes);
      final fa = SegDecoder.analyze(
          m.det, m.shape, m.proto, m.protoShape, size,
          targetHintX: 520, targetHintY: 300, hintIsTap: true,
          poleHintX: 320); // 봉이 중앙을 가리켜도 지정이 이긴다
      final s = fa.treeSpanAtRow(fa.treeBottom - 5)!;
      expect(s.hi * (size / mh), greaterThan(400));
    });
  });

  group('뒷나무 겹침', () {
    test('대상 상자 안에 들어온 뒤 나무 덩어리는 마스크에서 빠진다', () {
      // 상자 하나가 두 줄기를 함께 물게 만든다: 중앙 줄기 + 오른쪽에 떨어진 줄기.
      const nm = 1;
      const feat = 6 + nm;
      final det = Float32List(feat);
      det[0] = 260; det[1] = 100; det[2] = 470; det[3] = 620;
      det[4] = 0.9; det[5] = kTree.toDouble(); det[6] = 20.0;
      final proto = Float32List(nm * mh * mh);
      void band(int x1, int x2) {
        for (var y = 30; y < 150; y++) {
          for (var x = x1; x < x2; x++) {
            proto[y * mh + x] = 1.0;
          }
        }
      }
      band(70, 82); // 대상 줄기(상자 중심 ≈ (260+470)/2*0.25 = 91)
      band(100, 116); // 뒤에 겹친 다른 줄기(같은 상자 안, 떨어져 있음)
      final fa = SegDecoder.analyze(
          det, [1, 1, feat], proto, [1, nm, mh, mh], size);
      // 남은 마스크가 한 덩어리인지 — 한 행의 좌우 끝 폭이 한 줄기 폭이어야 한다.
      final span = fa.treeSpanAtRow(80)!;
      expect(span.hi - span.lo + 1, lessThan(20));
    });
  });

  group('지표면 지정', () {
    test('지정한 선 아래의 줄기·그을음은 계측에서 빠진다', () {
      final m = fakeModel(size: size, mh: mh, boxes: [
        (x1: 290.0, y1: 100.0, x2: 350.0, y2: 620.0, cls: kTree),
      ]);
      final base =
          SegDecoder.analyze(m.det, m.shape, m.proto, m.protoShape, size);
      final cut = SegDecoder.analyze(
          m.det, m.shape, m.proto, m.protoShape, size,
          groundNorm: 0.5); // 절반 높이를 밑동으로 지정
      expect(base.treeBottom, greaterThan(cut.treeBottom));
      expect(cut.treeBottom, lessThanOrEqualTo((0.5 * mh).round()));
      expect(cut.treePx, lessThan(base.treePx));
    });
  });

  group('밝기·대비 보정', () {
    test('밝기를 올리면 픽셀이 밝아지고, 대비를 올리면 어두운 쪽이 더 어두워진다', () {
      final src = img.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          src.setPixelRgb(x, y, 60, 60, 60); // 역광 그늘처럼 어두운 면
        }
      }
      final plain = ImageOps.letterbox(src, 64);
      final bright =
          ImageOps.letterbox(src, 64, brightness: 0.2);
      final contrast = ImageOps.letterbox(src, 64, contrast: 1.6);
      final c = 32 * 64 + 32; // 가운데 픽셀(패딩 아님)
      expect(bright.chw[c], greaterThan(plain.chw[c]));
      expect(contrast.chw[c], lessThan(plain.chw[c])); // 128보다 어두우면 더 내려간다
    });

    test('보정 없으면 원본 그대로(기존 결과 불변)', () {
      final src = img.Image(width: 32, height: 32);
      img.fill(src, color: img.ColorRgb8(90, 120, 150));
      final a = ImageOps.letterbox(src, 32);
      final b = ImageOps.letterbox(src, 32, brightness: 0, contrast: 1);
      expect(b.chw[500], a.chw[500]);
    });
  });

  group('조정값 보존', () {
    test('FaceTuning은 JSON을 왕복한다', () {
      const t = FaceTuning(
          groundNorm: 0.72, targetX: 0.4, targetY: 0.3, brightness: 0.1, contrast: 1.3);
      final r = FaceTuning.fromJson(t.toJson());
      expect(r.groundNorm, 0.72);
      expect(r.targetX, 0.4);
      expect(r.targetY, 0.3);
      expect(r.brightness, 0.1);
      expect(r.contrast, 1.3);
    });

    test('면 결과에 조정값·직접 입력 표시가 함께 저장된다', () {
      const f = AzimuthResult(
        azimuth: 'N',
        imagePath: '/p/n.jpg',
        analysed: true,
        manualEdited: true,
        tuning: FaceTuning(groundNorm: 0.8),
      );
      final r = AzimuthResult.fromJson(f.toJson());
      expect(r.manualEdited, isTrue);
      expect(r.tuning.groundNorm, 0.8);
      expect(r.manual, isFalse); // 사진이 있는 면은 'manual'이 아니다
    });

    test('구버전 기록(조정값 없음)도 그대로 읽힌다', () {
      final j = const AzimuthResult(azimuth: 'E', analysed: true).toJson()
        ..remove('tuning')
        ..remove('manualEdited');
      final r = AzimuthResult.fromJson(j);
      expect(r.tuning.isDefault, isTrue);
      expect(r.manualEdited, isFalse);
    });
  });
}

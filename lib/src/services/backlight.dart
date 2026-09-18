import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// 역광 **실루엣** 판정.
///
/// 해를 등진 나무를 찍으면 카메라가 밝은 하늘에 노출을 맞춰 줄기가 새까만
/// 실루엣이 된다. 그러면 사진에 수피 정보가 없어 모델은 줄기 전체를 그을음으로
/// 읽는다(현장 001 동: 그을음 0.98). 찍은 뒤 밝게 해도 살아나지 않는다 —
/// 감마·배율을 올려도 그을음 점수는 그대로이고 수간 점수만 무너졌다.
/// 그래서 **찍을 때 잡아야** 하고, 이미 찍힌 실루엣은 BSI에 넣지 않는다.
///
/// 주의: 그을린 줄기도 검다. 줄기에 노출을 맞추면 카메라가 검은 수피를 회색으로
/// 만들어 그을음이 옅어지므로, **실루엣일 때만** 개입해야 한다. 아래 기준은
/// 현장 35면(2026-08-26)에서 잡았다 — 001 동만 걸리고, 가장 가까운 정상 면과도
/// 간격이 넓다(분석: 줄기 중앙 휘도 19 대 37, 어두운 비율 0.86 대 0.38,
/// 주변/줄기 8.1 대 3.7 / 셔터: 주변/줄기 6.7 대 3.2, 줄기 25 대 42).
class Backlight {
  Backlight._();

  // ── 셔터 직후(마스크 없음): 작은 썸네일의 가운데 세로 띠 vs 좌우 ──────────
  /// 주변(좌우) 밝기 ÷ 줄기(가운데 띠의 어두운 절반) 밝기.
  static const double shotRatio = 4.5;

  /// 줄기 휘도(0~255) 상한 — 이보다 밝으면 실루엣이 아니다.
  static const double shotTrunkMax = 35;

  /// 썸네일 긴 변.
  static const int thumbLongSide = 128;

  // ── 분석 뒤(수간 마스크 있음) ─────────────────────────────────────────
  static const double maskMedianMax = 28;
  static const double maskDarkFraction = 0.6;
  static const double maskRatio = 5;
  static const int _dark = 30;

  /// 휘도(ITU-R 601, PIL 'L'과 같은 계수).
  static double luma(num r, num g, num b) => 0.299 * r + 0.587 * g + 0.114 * b;

  /// 셔터 직후 판정. [gray]는 행 우선 휘도(0~255), 똑바로 선 사진.
  ///
  /// 대상목은 화면 가운데 세워 찍으므로 가운데 30 % 세로 띠에 줄기가 있다.
  /// 띠에 하늘이 섞여도 줄기만 보도록 띠의 **어두운 절반**을 줄기로 친다.
  /// 위아래 15 %(하늘·발치)는 뺀다.
  static ShotScore scoreThumb(Uint8List gray, int w, int h) {
    final c0 = (w * 0.35).floor(), c1 = (w * 0.65).floor();
    final y0 = (h * 0.15).floor(), y1 = (h * 0.85).floor();
    final centre = <int>[], sides = <int>[];
    for (var y = y0; y < y1; y++) {
      final row = y * w;
      for (var x = 0; x < w; x++) {
        final v = gray[row + x];
        (x >= c0 && x < c1 ? centre : sides).add(v);
      }
    }
    if (centre.isEmpty || sides.isEmpty) {
      return const ShotScore(trunk: double.nan, surround: double.nan);
    }
    centre.sort();
    final darkHalf = centre.sublist(0, centre.length ~/ 2);
    return ShotScore(trunk: _median(darkHalf), surround: _median(sides..sort()));
  }

  /// 저장 전 카메라 원본을 플랫폼 코덱으로 작게 풀어 판정한다(수십 ms).
  /// 엔진이 EXIF 회전을 적용하므로 세로 사진은 세로로 온다. 실패하면 null.
  static Future<ShotScore?> scoreFile(String path, Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final landscape = desc.width >= desc.height;
      final codec = await desc.instantiateCodec(
          targetWidth: landscape ? thumbLongSide : null,
          targetHeight: landscape ? null : thumbLongSide);
      final frame = await codec.getNextFrame();
      final im = frame.image;
      final w = im.width, h = im.height;
      final rgba = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
      im.dispose();
      codec.dispose();
      desc.dispose();
      buffer.dispose();
      if (rgba == null) return null;
      final px = rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
      final gray = Uint8List(w * h);
      for (var i = 0; i < w * h; i++) {
        gray[i] = luma(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]).round().clamp(0, 255);
      }
      return scoreThumb(gray, w, h);
    } catch (_) {
      return null;
    }
  }

  /// 분석 뒤 판정 — 모델이 잡은 수간 마스크 안이 실루엣인지.
  ///
  /// [square]는 letterbox 캔버스, [treeMask]는 그 위의 proto 격자(mh×mw).
  /// letterbox 여백(회색 114)은 주변 밝기에서 뺀다.
  static MaskScore scoreMask(
      img.Image square, Uint8List treeMask, int mh, int mw) {
    final sx = square.width / mw, sy = square.height / mh;
    final inside = <double>[], outside = <double>[];
    for (var y = 0; y < mh; y++) {
      final py = ((y + 0.5) * sy).floor().clamp(0, square.height - 1);
      for (var x = 0; x < mw; x++) {
        final p = square.getPixel(((x + 0.5) * sx).floor().clamp(0, square.width - 1), py);
        final r = p.r, g = p.g, b = p.b;
        if (treeMask[y * mw + x] == 1) {
          inside.add(luma(r, g, b));
        } else if (!(r == 114 && g == 114 && b == 114)) {
          outside.add(luma(r, g, b));
        }
      }
    }
    if (inside.length < 12 || outside.isEmpty) {
      return const MaskScore(median: double.nan, darkFraction: 0, surround: double.nan);
    }
    final dark = inside.where((v) => v < _dark).length / inside.length;
    return MaskScore(
        median: _median(inside..sort()),
        darkFraction: dark,
        surround: _median(outside..sort()));
  }

  static double _median(List<num> sorted) {
    final n = sorted.length;
    return n.isOdd
        ? sorted[n ~/ 2].toDouble()
        : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }
}

/// 셔터 직후 판정 결과.
class ShotScore {
  final double trunk; // 가운데 띠 어두운 절반의 중앙 휘도
  final double surround; // 좌우의 중앙 휘도
  const ShotScore({required this.trunk, required this.surround});

  double get ratio => surround / (trunk < 1 ? 1 : trunk);

  bool get silhouette =>
      !trunk.isNaN && trunk <= Backlight.shotTrunkMax && ratio >= Backlight.shotRatio;

  Map<String, Object?> toJson() => {
        'trunk': trunk.isNaN ? null : trunk,
        'surround': surround.isNaN ? null : surround,
        'ratio': trunk.isNaN ? null : ratio,
        'silhouette': silhouette,
      };
}

/// 분석 뒤(수간 마스크) 판정 결과.
class MaskScore {
  final double median; // 수간 마스크 안 중앙 휘도
  final double darkFraction; // 그 안에서 휘도 < 30 인 비율
  final double surround; // 마스크 밖(여백 제외) 중앙 휘도
  const MaskScore(
      {required this.median, required this.darkFraction, required this.surround});

  double get ratio => surround / (median < 1 ? 1 : median);

  bool get silhouette =>
      !median.isNaN &&
      median <= Backlight.maskMedianMax &&
      darkFraction >= Backlight.maskDarkFraction &&
      ratio >= Backlight.maskRatio;

  Map<String, Object?> toJson() => {
        'median': median.isNaN ? null : median,
        'darkFraction': darkFraction,
        'surround': surround.isNaN ? null : surround,
        'ratio': median.isNaN ? null : ratio,
        'silhouette': silhouette,
      };
}

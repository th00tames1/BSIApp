import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 사진의 밝기 분포. 역광·짙은 그늘을 자동으로 알아보는 데 쓴다.
class ToneStats {
  final double medianY; // 휘도 중앙값 0~255
  final double darkRatio; // 휘도 60 미만 픽셀 비율
  final double brightRatio; // 휘도 200 초과 비율(하늘 등)
  const ToneStats(this.medianY, this.darkRatio, this.brightRatio);

  /// 피사체가 어둡게 깔린 사진인지.
  ///
  /// 역광에서는 하늘이 날아가고 줄기가 검게 뭉쳐 그을음 경계가 사라진다.
  /// 기준은 검증에 쓰는 예시 사진과 넉넉히 떨어뜨렸다 —
  /// 예시 4장은 어두운 픽셀 21~35 %, 중앙값 85~106이고,
  /// 언더노출 사진은 68 %, 23이었다.
  bool get needsTone => darkRatio >= 0.50 && medianY <= 70;
}

/// 역광·그늘 사진의 어두운 부분을 살리는 자동 보정.
///
/// 널리 쓰이는 **CLAHE**(Contrast Limited Adaptive Histogram Equalization)다.
/// 화면을 타일로 나눠 각 타일의 히스토그램을 평활화하되, 기울기를 제한(clip)해
/// 노이즈가 튀는 것을 막는다. 전역 평활화와 달리 하늘은 그대로 두고 그늘만
/// 끌어올리므로 역광 사진에 적합하다.
///
/// 밝기는 **휘도(Y)에만** 적용하고 색은 비율로 유지한다 — 수간·그을음의
/// 색 관계가 흐트러지면 분할 모델이 흔들린다.
class AutoTone {
  AutoTone._();

  /// 밝기 통계(성능을 위해 격자 표본만 본다).
  static ToneStats measure(img.Image src) {
    final hist = Int32List(256);
    var n = 0;
    final stepX = math.max(1, src.width ~/ 256);
    final stepY = math.max(1, src.height ~/ 256);
    for (var y = 0; y < src.height; y += stepY) {
      for (var x = 0; x < src.width; x += stepX) {
        final p = src.getPixel(x, y);
        final v = _luma(p.r.toInt(), p.g.toInt(), p.b.toInt());
        hist[v]++;
        n++;
      }
    }
    if (n == 0) return const ToneStats(128, 0, 0);
    var dark = 0, bright = 0, acc = 0, median = 128;
    for (var i = 0; i < 60; i++) {
      dark += hist[i];
    }
    for (var i = 201; i < 256; i++) {
      bright += hist[i];
    }
    for (var i = 0; i < 256; i++) {
      acc += hist[i];
      if (acc * 2 >= n) {
        median = i;
        break;
      }
    }
    return ToneStats(median.toDouble(), dark / n, bright / n);
  }

  static int _luma(int r, int g, int b) {
    final v = (0.299 * r + 0.587 * g + 0.114 * b).round();
    return v < 0 ? 0 : (v > 255 ? 255 : v);
  }

  /// CLAHE를 적용한 새 이미지. [tiles]×[tiles] 격자, [clipLimit]는 평균
  /// 히스토그램 높이의 배수(2~3이 통상값).
  static img.Image applyClahe(img.Image src,
      {double clipLimit = 2.5, int tiles = 8}) {
    final w = src.width, h = src.height;
    if (w < tiles * 2 || h < tiles * 2) return src;

    // 1) 휘도 평면
    final y = Uint8List(w * h);
    for (var j = 0; j < h; j++) {
      for (var i = 0; i < w; i++) {
        final p = src.getPixel(i, j);
        y[j * w + i] = _luma(p.r.toInt(), p.g.toInt(), p.b.toInt());
      }
    }

    // 2) 타일마다 클립 히스토그램 → 매핑(CDF)
    final tw = (w / tiles).ceil(), th = (h / tiles).ceil();
    final maps = List.generate(tiles * tiles, (_) => Uint8List(256));
    final hist = Int32List(256);
    for (var ty = 0; ty < tiles; ty++) {
      for (var tx = 0; tx < tiles; tx++) {
        hist.fillRange(0, 256, 0);
        final x0 = tx * tw, y0 = ty * th;
        final x1 = math.min(x0 + tw, w), y1 = math.min(y0 + th, h);
        var count = 0;
        for (var j = y0; j < y1; j++) {
          final base = j * w;
          for (var i = x0; i < x1; i++) {
            hist[y[base + i]]++;
            count++;
          }
        }
        if (count == 0) continue;
        // 클리핑 — 넘친 양은 모든 빈에 고르게 되돌린다.
        final limit = math.max(1, (clipLimit * count / 256).round());
        var excess = 0;
        for (var i = 0; i < 256; i++) {
          if (hist[i] > limit) {
            excess += hist[i] - limit;
            hist[i] = limit;
          }
        }
        final add = excess ~/ 256;
        var rest = excess - add * 256;
        for (var i = 0; i < 256; i++) {
          hist[i] += add;
          if (rest > 0) {
            hist[i]++;
            rest--;
          }
        }
        final map = maps[ty * tiles + tx];
        var cdf = 0;
        for (var i = 0; i < 256; i++) {
          cdf += hist[i];
          map[i] = (cdf * 255 / count).round().clamp(0, 255);
        }
      }
    }

    // 3) 픽셀마다 인접 타일 매핑을 이중선형 보간(타일 경계가 드러나지 않게)
    final out = img.Image.from(src);
    for (var j = 0; j < h; j++) {
      final fy = (j + 0.5) / th - 0.5;
      var ty0 = fy.floor();
      final wy = fy - ty0;
      ty0 = ty0.clamp(0, tiles - 1);
      final ty1 = (ty0 + 1).clamp(0, tiles - 1);
      for (var i = 0; i < w; i++) {
        final fx = (i + 0.5) / tw - 0.5;
        var tx0 = fx.floor();
        final wx = fx - tx0;
        tx0 = tx0.clamp(0, tiles - 1);
        final tx1 = (tx0 + 1).clamp(0, tiles - 1);
        final v = y[j * w + i];
        final a = maps[ty0 * tiles + tx0][v].toDouble();
        final b = maps[ty0 * tiles + tx1][v].toDouble();
        final c = maps[ty1 * tiles + tx0][v].toDouble();
        final d = maps[ty1 * tiles + tx1][v].toDouble();
        final top = a + (b - a) * (wx < 0 ? 0 : wx);
        final bot = c + (d - c) * (wx < 0 ? 0 : wx);
        final ny = (top + (bot - top) * (wy < 0 ? 0 : wy)).round().clamp(0, 255);
        if (ny == v) continue;
        // 색은 비율로 유지 — 휘도만 끌어올린다.
        final p = out.getPixel(i, j);
        final k = v == 0 ? ny.toDouble() : ny / v;
        int ch(num c0) {
          final r = v == 0 ? c0 + ny : c0 * k;
          return r < 0 ? 0 : (r > 255 ? 255 : r.round());
        }

        out.setPixelRgb(i, j, ch(p.r), ch(p.g), ch(p.b));
      }
    }
    return out;
  }
}

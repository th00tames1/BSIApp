import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A photo letterboxed to size×size, plus the CHW tensor and the geometry.
class Letterboxed {
  final img.Image square; // size×size RGB (gray-114 padded)
  final Float32List chw; // [3*size*size] normalized CHW
  final double scale; // resize ratio applied to the original
  final int padX, padY, size;
  Letterboxed(this.square, this.chw, this.scale, this.padX, this.padY, this.size);
}

class ImageOps {
  /// 검증에 쓴 예시 사진의 크기(긴 변). 카메라 원본은 이 크기로 먼저 맞춘다.
  static const int normLongSide = 1280;

  /// Decode a JPEG file, letterbox to size×size (aspect kept, gray 114 pad) and
  /// return the square image + a normalized Float32 CHW tensor (matches the
  /// Android/iOS native apps' preprocessing).
  ///
  /// JPEG의 EXIF 회전은 디코더가 적용하므로(image 4.8) 카메라 원본(가로 픽셀 +
  /// Orientation 태그)도 똑바로 선 채로 들어온다.
  static Letterboxed? letterboxFromFile(String path, int size) {
    final raw = File(path).readAsBytesSync();
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    return letterbox(normalizeResolution(decoded), size);
  }

  /// 입력을 예시 사진과 같은 크기(긴 변 [normLongSide])로 **면적 평균** 축소한다.
  ///
  /// 카메라 원본(12 MP 등)을 640으로 한 번에 6배 넘게 bilinear 축소하면 수고봉
  /// 같은 가는 구조가 예시 사진(2배 축소)과 다르게 뭉개져 계측값이 몇 % 어긋난다
  /// (실기기 검증: 같은 장면이 그을음 높이 4.21 → 4.02 m). 예시 사진과 같은 중간
  /// 해상도를 거치게 해 두 경로가 같은 성능을 내게 한다. 예시 사진(≤1280)에는
  /// 무동작이라 검증 기준값은 그대로다.
  static img.Image normalizeResolution(img.Image src) {
    final long = math.max(src.width, src.height);
    if (long <= normLongSide) return src;
    final r = normLongSide / long;
    return img.copyResize(src,
        width: math.max(1, (src.width * r).round()),
        height: math.max(1, (src.height * r).round()),
        interpolation: img.Interpolation.average);
  }

  static Letterboxed letterbox(img.Image src, int size) {
    final r = math.min(size / src.width, size / src.height);
    final nw = math.max(1, (src.width * r).round());
    final nh = math.max(1, (src.height * r).round());
    final resized = img.copyResize(src,
        width: nw, height: nh, interpolation: img.Interpolation.linear);
    final canvas = img.Image(width: size, height: size, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(114, 114, 114));
    final padX = ((size - nw) / 2).round();
    final padY = ((size - nh) / 2).round();
    img.compositeImage(canvas, resized, dstX: padX, dstY: padY);

    final bytes = canvas.getBytes(order: img.ChannelOrder.rgb);
    final area = size * size;
    final chw = Float32List(3 * area);
    for (int i = 0; i < area; i++) {
      final p = i * 3;
      chw[i] = bytes[p] / 255.0;
      chw[area + i] = bytes[p + 1] / 255.0;
      chw[2 * area + i] = bytes[p + 2] / 255.0;
    }
    return Letterboxed(canvas, chw, r, padX, padY, size);
  }

  /// Nearest-neighbour upsample a proto-grid boolean mask to size×size.
  static Uint8List upsampleMask(Uint8List maskProto, int mh, int mw, int size) {
    final out = Uint8List(size * size);
    for (int y = 0; y < size; y++) {
      final py = (y * mh ~/ size).clamp(0, mh - 1);
      final rowBase = y * size;
      final pRow = py * mw;
      for (int x = 0; x < size; x++) {
        final px = (x * mw ~/ size).clamp(0, mw - 1);
        out[rowBase + x] = maskProto[pRow + px];
      }
    }
    return out;
  }

  /// Render the analysis overlay onto the square image: stem=red, soot=green
  /// (semi-transparent), plus the measuring-pole line in yellow. Returns PNG bytes.
  static Uint8List renderOverlay(
    img.Image square,
    Uint8List treeMask,
    Uint8List sootMask,
    int size, {
    int? poleTopY,
    int? poleBottomY,
    int? poleX,
    List<({double x, double y})> poleBoundaries = const [],
    ({int y, int x1, int x2})? stemBase,
    ({int y, int x1, int x2})? dbhLine,
    ({int y, int x1, int x2})? sootTop,
  }) {
    final out = img.Image.from(square);
    final red = [224, 58, 58];
    final green = [53, 168, 83];
    for (int y = 0; y < size; y++) {
      final row = y * size;
      for (int x = 0; x < size; x++) {
        final idx = row + x;
        final soot = sootMask[idx] == 1;
        final tree = treeMask[idx] == 1;
        if (!soot && !tree) continue;
        final c = soot ? green : red; // soot overrides stem in display
        final px = out.getPixel(x, y);
        // 55% overlay blend
        out.setPixelRgb(
          x,
          y,
          (px.r * 0.45 + c[0] * 0.55).round(),
          (px.g * 0.45 + c[1] * 0.55).round(),
          (px.b * 0.45 + c[2] * 0.55).round(),
        );
      }
    }
    // 실제 계측에 쓰인 세 위치를 가로선으로 그린다(무엇을 쟀는지 보이게).
    void measureLine(({int y, int x1, int x2})? m, img.Color color,
        {bool ticks = true}) {
      if (m == null) return;
      final y = m.y.clamp(0, size - 1);
      final pad = ((m.x2 - m.x1) * 0.12).round().clamp(6, 40);
      img.drawLine(out,
          x1: (m.x1 - pad).clamp(0, size - 1),
          y1: y,
          x2: (m.x2 + pad).clamp(0, size - 1),
          y2: y,
          color: color,
          thickness: 4);
      if (!ticks) return;
      for (final x in [m.x1, m.x2]) {                 // 양끝 눈금
        img.drawLine(out,
            x1: x.clamp(0, size - 1),
            y1: (y - 9).clamp(0, size - 1),
            x2: x.clamp(0, size - 1),
            y2: (y + 9).clamp(0, size - 1),
            color: color,
            thickness: 4);
      }
    }

    // 그을음 최고 높이는 "여기까지"만 알면 되므로 끝 눈금 없이 선만 그린다.
    measureLine(sootTop, img.ColorRgb8(224, 58, 58), ticks: false);
    measureLine(dbhLine, img.ColorRgb8(37, 120, 235));     // 흉고직경
    measureLine(stemBase, img.ColorRgb8(28, 28, 32));      // 나무 밑둥

    // 모델이 찾은 1 m 경계는 짧은 원으로만 표시한다(계측선과 구분).
    if (poleBoundaries.isNotEmpty) {
      final pts = [...poleBoundaries]..sort((a, b) => a.y.compareTo(b.y));
      for (var i = 0; i < pts.length; i++) {
        final x = pts[i].x.round(), y = pts[i].y.round();
        if (i > 0) {
          // 인접 경계를 잇는 얇은 선 = 1 m 구간
          img.drawLine(out,
              x1: pts[i - 1].x.round(),
              y1: pts[i - 1].y.round(),
              x2: x,
              y2: y,
              color: img.ColorRgb8(246, 197, 24),
              thickness: 1);
        }
        img.fillCircle(out,
            x: x, y: y, radius: 7, color: img.ColorRgb8(246, 197, 24));
        img.drawCircle(out,
            x: x, y: y, radius: 7, color: img.ColorRgb8(120, 90, 0));
      }
    } else if (poleTopY != null && poleBottomY != null && poleX != null) {
      img.drawLine(out,
          x1: poleX,
          y1: poleTopY,
          x2: poleX,
          y2: poleBottomY,
          color: img.ColorRgb8(246, 197, 24),
          thickness: 4);
    }
    return Uint8List.fromList(img.encodePng(out));
  }
}

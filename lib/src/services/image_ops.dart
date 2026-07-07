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
  /// Decode a JPEG file, letterbox to size×size (aspect kept, gray 114 pad) and
  /// return the square image + a normalized Float32 CHW tensor (matches the
  /// Android/iOS native apps' preprocessing).
  static Letterboxed? letterboxFromFile(String path, int size) {
    final raw = File(path).readAsBytesSync();
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    return letterbox(decoded, size);
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
    if (poleTopY != null && poleBottomY != null && poleX != null) {
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

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image/image.dart' as img;

/// 촬영·불러온 사진을 **기기와 무관한 표준 형태**로 저장한다.
///
/// 카메라 원본은 기기마다 해상도(12 MP·50 MP·200 MP…)와 저장 방향(가로 픽셀 +
/// EXIF 회전 태그)이 제각각이다. 분석은 예시 사진(960×1280)으로 검증했으므로,
/// 저장 단계에서 **긴 변 [longSide] 이하 · 회전 적용 · EXIF 없음**으로 통일해
/// 이후 파이프라인(분석 정규화 → letterbox 640)이 기기를 타지 않게 한다.
///
/// 축소 디코드는 플랫폼 코덱(dart:ui)이 하므로 50 MP 원본도 Dart 메모리를 크게
/// 쓰지 않는다. 실패하면 원본을 그대로 복사한다 — 분석 쪽 디코더가 EXIF와
/// 해상도를 처리하므로 동작은 계속되고, 표준화만 놓친다.
class PhotoNormalizer {
  PhotoNormalizer._();

  /// 저장 사진의 긴 변. 분석 정규화 크기(1280)의 정확히 2배라 면적 평균 축소가
  /// 2×2 블록 평균이 되어 실기기 검증(2배 해상도 → 동일 결과)과 같은 경로를 탄다.
  static const int longSide = 2560;
  static const int jpegQuality = 90;

  /// [srcPath]의 사진을 정규화해 [destPath]에 JPEG로 쓴다.
  ///
  /// [gain]은 카메라 하드웨어 노출 보정 범위를 넘어선 만큼의 **소프트웨어 밝기**다.
  /// 촬영 화면 미리보기가 같은 값을 `ColorFilter.matrix`로 걸기 때문에 여기서도
  /// 똑같이 sRGB 값에 곱하고 255에서 자른다 — 보이는 것과 저장되는 것이 같다.
  ///
  /// 반환: 실제로 정규화됐으면 true, 원본 복사로 대체됐으면 false
  /// (대체된 경우 [gain]은 적용되지 않는다).
  static Future<bool> save(String srcPath, String destPath,
      {double gain = 1.0}) async =>
      (await saveWithInfo(srcPath, destPath, gain: gain)).normalized;

  /// [save]와 같고, 무엇을 어떻게 바꿨는지(원본·표준 해상도)를 함께 돌려준다 —
  /// 촬영 메타(capture.json)에 변환 이력을 남기기 위해.
  static Future<NormalizeInfo> saveWithInfo(String srcPath, String destPath,
      {double gain = 1.0}) async {
    try {
      final bytes = await File(srcPath).readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      // 엔진이 EXIF 회전을 적용한 크기다(세로 사진은 세로로 온다).
      final w = desc.width, h = desc.height;
      int? tw, th;
      if (w >= h && w > longSide) tw = longSide;
      if (h > w && h > longSide) th = longSide;
      final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final ow = image.width, oh = image.height;
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();
      desc.dispose();
      buffer.dispose();
      if (rgba == null) {
        return NormalizeInfo(await _fallback(srcPath, destPath), w, h, null, null);
      }

      // 안전망: 엔진이 회전을 적용하지 않은 코덱 경로라면 여기서 직접 적용한다.
      // (원본 픽셀 크기와 EXIF 태그로 판정 — 90°/270° 회전은 가로세로가 바뀐다.)
      final orient = _unappliedOrientation(bytes, w, h);
      final jpeg = await Isolate.run(() => _encode(
          rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
          ow, oh, orient, gain));
      await File(destPath).writeAsBytes(jpeg, flush: true);
      final swapped = orient >= 5;
      // 엔진이 회전을 못 했으면(orient ≥ 5) 원본 크기도 돌려서 적는다
      return NormalizeInfo(true, swapped ? h : w, swapped ? w : h,
          swapped ? oh : ow, swapped ? ow : oh);
    } catch (_) {
      return NormalizeInfo(await _fallback(srcPath, destPath), null, null, null, null);
    }
  }

  static Future<bool> _fallback(String src, String dest) async {
    await File(src).copy(dest);
    return false;
  }

  /// 엔진이 EXIF 회전을 적용했으면 1, 아니면 적용해야 할 EXIF orientation 값.
  static int _unappliedOrientation(Uint8List bytes, int decodedW, int decodedH) {
    try {
      final o = img.decodeJpgExif(bytes)?.imageIfd.orientation ?? 1;
      if (o < 2 || o > 8) return 1;
      final info = img.JpegDecoder().startDecode(bytes);
      if (info == null) return 1;
      final swaps = o >= 5; // 5~8: 90°/270° 계열 → 가로세로가 바뀐다
      final expectW = swaps ? info.height : info.width;
      final expectH = swaps ? info.width : info.height;
      final applied = (decodedW >= decodedH) == (expectW >= expectH);
      // 180°(3)·좌우반전(2,4)은 크기로 구분할 수 없어 엔진에 맡긴다.
      return (!applied && swaps) ? o : 1;
    } catch (_) {
      return 1;
    }
  }

  /// RGB에 [gain]을 곱하고 255에서 자른다(알파는 그대로). 미리보기의
  /// `ColorFilter.matrix` 대각 행렬과 같은 연산이다.
  @visibleForTesting
  static void applyGain(Uint8List rgba, double gain) {
    if (gain == 1.0) return;
    final lut = Uint8List(256);
    for (var v = 0; v < 256; v++) {
      final x = (v * gain).round();
      lut[v] = x > 255 ? 255 : (x < 0 ? 0 : x);
    }
    for (var i = 0; i + 3 < rgba.length; i += 4) {
      rgba[i] = lut[rgba[i]];
      rgba[i + 1] = lut[rgba[i + 1]];
      rgba[i + 2] = lut[rgba[i + 2]];
    }
  }

  static Uint8List _encode(
      Uint8List rgba, int w, int h, int orient, double gain) {
    applyGain(rgba, gain);
    var im = img.Image.fromBytes(
        width: w, height: h, bytes: rgba.buffer, bytesOffset: rgba.offsetInBytes,
        numChannels: 4, order: img.ChannelOrder.rgba);
    if (orient != 1) {
      im.exif.imageIfd.orientation = orient;
      im = img.bakeOrientation(im);
    }
    // 저장 파일에는 회전 태그를 남기지 않는다(픽셀이 이미 똑바로 서 있다).
    im.exif.imageIfd.orientation = null;
    return img.encodeJpg(im, quality: jpegQuality);
  }
}

/// 표준화 결과. [normalized]가 false면 원본을 그대로 복사한 것이다(밝기 미적용).
/// 크기는 모두 **회전을 적용한 뒤**의 가로·세로다.
class NormalizeInfo {
  final bool normalized;
  final int? sourceWidth, sourceHeight; // 카메라 원본(엔진 디코드 기준)
  final int? width, height; // 저장한 표준 사진
  const NormalizeInfo(this.normalized, this.sourceWidth, this.sourceHeight,
      this.width, this.height);

  Map<String, dynamic> toJson({required double gain}) => {
        'normalized': normalized,
        'sourceWidth': sourceWidth,
        'sourceHeight': sourceHeight,
        'width': width,
        'height': height,
        if (sourceWidth != null && width != null && sourceWidth! > 0)
          'scale': (sourceWidth! >= sourceHeight! ? width! / sourceWidth! : height! / sourceHeight!),
        'longSide': PhotoNormalizer.longSide,
        'jpegQuality': PhotoNormalizer.jpegQuality,
        'resample': 'platform codec area downscale (dart:ui targetWidth/Height)',
        // 밝기: sRGB 값에 gain을 곱하고 0~255로 자른다(미리보기 ColorFilter와 같은 연산)
        'softwareGain': gain,
        'softwareGainApplied': normalized && gain != 1.0,
        'gainFormula': 'out = clamp(round(v * gain), 0, 255) per R,G,B (sRGB)',
        'exifStripped': normalized,
      };
}

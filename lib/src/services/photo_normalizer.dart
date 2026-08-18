import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
  /// 반환: 실제로 정규화됐으면 true, 원본 복사로 대체됐으면 false.
  static Future<bool> save(String srcPath, String destPath) async {
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
      if (rgba == null) return _fallback(srcPath, destPath);

      // 안전망: 엔진이 회전을 적용하지 않은 코덱 경로라면 여기서 직접 적용한다.
      // (원본 픽셀 크기와 EXIF 태그로 판정 — 90°/270° 회전은 가로세로가 바뀐다.)
      final orient = _unappliedOrientation(bytes, w, h);
      final jpeg = await Isolate.run(() => _encode(
          rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
          ow, oh, orient));
      await File(destPath).writeAsBytes(jpeg, flush: true);
      return true;
    } catch (_) {
      return _fallback(srcPath, destPath);
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

  static Uint8List _encode(Uint8List rgba, int w, int h, int orient) {
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

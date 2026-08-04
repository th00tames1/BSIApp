import 'dart:io';

import '../models/survey.dart';
import 'image_ops.dart';
import 'mortality.dart';
import 'onnx_service.dart';
import 'pole_model.dart';
import 'seg_decoder.dart';

class BsiIntegration {
  final double bsi;
  final double dbhCm;
  final double mortality;
  final String verdict;

  /// BSI 합에 실제로 기여한 방위 수(높이·비율이 모두 나온 면). 4보다 작으면
  /// 4방위 기준으로 환산한 값이므로 화면에 그 사실을 알려야 한다.
  final int facesUsed;

  const BsiIntegration(this.bsi, this.dbhCm, this.mortality, this.verdict,
      {this.facesUsed = 4});

  bool get isPartial => facesUsed > 0 && facesUsed < 4;
}

class AnalysisService {
  AnalysisService._();
  static final AnalysisService instance = AnalysisService._();

  /// Analyse one captured face: segment, scale with the pole, derive metrics,
  /// and (optionally) write an overlay PNG. Returns an [AzimuthResult].
  Future<AzimuthResult> analyzeFace(
    String azimuth,
    String imagePath, {
    required double poleLengthM,
    String? overlayOutPath,
    double? manualPxPerMetre,
  }) async {
    final size = OnnxService.instance.inputSize;
    final lb = ImageOps.letterboxFromFile(imagePath, size);
    if (lb == null) {
      return AzimuthResult(azimuth: azimuth, imagePath: imagePath, analysed: false);
    }
    final raw = await OnnxService.instance.infer(lb.chw, lb.size);
    final fa = SegDecoder.analyze(
        raw.det, raw.detShape, raw.proto, raw.protoShape, lb.size);

    // 스케일 우선순위: 수동 입력 > 수고봉 경계 검출 모델 > (모델 미탑재 시에만)
    // 노란픽셀 휴리스틱.
    //
    // **모델이 탑재됐는데 스케일을 못 냈다면 휴리스틱으로 내려가지 않는다.**
    // 경계가 하나뿐이라 모델이 기권한 경우인데, 휴리스틱은 "가장 긴 노란 구간 =
    // 봉 길이"라는 깨진 가정을 쓰므로 그 자리를 메우면 몇 배 부풀린 높이가 조용히
    // 들어간다(에뮬레이터 검증에서 BSI 4.69 → 8.6). 스케일 없는 면은 높이를
    // 비워 두고, integrate()가 계측된 면으로 4방위를 환산한다.
    PoleScaleSolution? sol;
    var modelUsable = false;
    if (manualPxPerMetre == null && OnnxService.pole.isLoaded) {
      modelUsable = true;
      try {
        final o = await OnnxService.pole.inferDetect(lb.chw, lb.size);
        final pts = PoleDetector.decode(o.data, o.shape, lb.size);
        sol = PoleDetector.solve(pts, lb.size);
      } catch (_) {
        modelUsable = false; // 추론 자체가 실패하면 휴리스틱이라도 쓴다
        sol = null;
      }
    }
    final PoleScale pole = PoleScale.detect(lb.square, lb.size, poleLengthM);
    final double pxPerM = manualPxPerMetre ??
        sol?.pxPerMetre ??
        (modelUsable ? double.nan : pole.pxPerMetre);

    final protoToSize = lb.size / fa.mh; // proto rows/cols -> size px
    double sootHeightM = double.nan,
        sootWidthM = double.nan,
        visStemM = double.nan,
        dbhM = double.nan;
    final haveScale = !pxPerM.isNaN && pxPerM > 0;

    /// 원근 보정: 재려는 구간의 **높이에서의 국소 px/m**을 쓴다. 봉이 기울거나
    /// 가까이 찍히면 1 m의 픽셀 길이가 위아래로 달라지기 때문이다(검증에서
    /// 평균 오차 5.6 %→2.2 %). 보정 정보가 없으면 대표값을 그대로 쓴다.
    double scaleAtRow(int protoRow) {
      if (sol == null) return pxPerM;
      final y = protoRow * protoToSize;
      final x = sol.staff.points.isEmpty ? lb.size / 2 : sol.staff.points.first.x;
      return sol.pxPerMetreAt(x, y);
    }

    if (fa.interPx > 0 && haveScale) {
      final s = scaleAtRow((fa.interTop + fa.interBottom) ~/ 2);
      sootHeightM = (fa.interBottom - fa.interTop) * protoToSize / s;
      sootWidthM = (fa.interRight - fa.interLeft + 1) * protoToSize / s;
    }
    if (fa.hasTree && haveScale) {
      final s = scaleAtRow((fa.treeTop + fa.treeBottom) ~/ 2);
      visStemM = (fa.treeBottom - fa.treeTop) * protoToSize / s;
      dbhM = fa.treeWidthLowerCols() * protoToSize / scaleAtRow(fa.treeBottom);
    }

    String? overlayPath;
    if (overlayOutPath != null) {
      final treeUp = ImageOps.upsampleMask(fa.treeMask, fa.mh, fa.mw, lb.size);
      final sootUp = ImageOps.upsampleMask(fa.sootMask, fa.mh, fa.mw, lb.size);
      final png = ImageOps.renderOverlay(
        lb.square, treeUp, sootUp, lb.size,
        poleTopY: pole.detected ? pole.topY : null,
        poleBottomY: pole.detected ? pole.bottomY : null,
        poleX: pole.detected ? pole.x : null,
        poleBoundaries: [
          for (final p in sol?.staff.points ?? const []) (x: p.x, y: p.y)
        ],
      );
      File(overlayOutPath).writeAsBytesSync(png);
      overlayPath = overlayOutPath;
    }

    return AzimuthResult(
      azimuth: azimuth,
      imagePath: imagePath,
      overlayPath: overlayPath,
      sootProportion: fa.bspBelow,
      sootProportionWhole: fa.bspWhole,
      sootHeightM: sootHeightM,
      sootWidthM: sootWidthM,
      visibleStemHeightM: visStemM,
      pxPerMetre: pxPerM,
      dbhEstM: dbhM,
      sootPx: fa.sootPx,
      treePx: fa.treePx,
      analysed: true,
    );
  }

  /// BSI = Σ over faces of (scorch height[m] × scorch proportion), per Kwon 2021.
  ///
  /// 정의가 **4방위 합**이므로, 어떤 면에서 높이를 못 구하면(수고봉 경계가 하나만
  /// 보여 스케일을 못 세우는 등) 그 면을 빼고 더한 값은 4방위 BSI보다 작아진다.
  /// 그대로 두면 판정이 위험한 방향(과소평가 → 존치)으로 기울므로, 기여한 면의
  /// 평균으로 4방위를 환산하고 [BsiIntegration.facesUsed]로 사실을 알린다.
  BsiIntegration integrate(List<AzimuthResult> faces, double dbhCm) {
    double sum = 0;
    int n = 0;
    for (final f in faces) {
      if (f.analysed && !f.sootHeightM.isNaN && !f.sootProportion.isNaN) {
        sum += f.sootHeightM * f.sootProportion;
        n++;
      }
    }
    final b = n > 0 ? sum * 4 / n : double.nan;
    return BsiIntegration(
      b,
      dbhCm,
      Mortality.probability(b, dbhCm),
      Mortality.verdict(b, dbhCm),
      facesUsed: n,
    );
  }
}

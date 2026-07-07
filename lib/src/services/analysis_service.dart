import 'dart:io';

import '../models/survey.dart';
import 'image_ops.dart';
import 'mortality.dart';
import 'onnx_service.dart';
import 'seg_decoder.dart';

class BsiIntegration {
  final double bsi;
  final double dbhCm;
  final double mortality;
  final String verdict;
  const BsiIntegration(this.bsi, this.dbhCm, this.mortality, this.verdict);
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

    // Pole scale: manual override wins; otherwise heuristic yellow detection.
    PoleScale pole = PoleScale.detect(lb.square, lb.size, poleLengthM);
    double pxPerM = manualPxPerMetre ?? pole.pxPerMetre;

    final protoToSize = lb.size / fa.mh; // proto rows/cols -> size px
    double sootHeightM = double.nan,
        sootWidthM = double.nan,
        visStemM = double.nan,
        dbhM = double.nan;
    final haveScale = !pxPerM.isNaN && pxPerM > 0;
    if (fa.interPx > 0 && haveScale) {
      sootHeightM = (fa.interBottom - fa.interTop) * protoToSize / pxPerM;
      sootWidthM = (fa.interRight - fa.interLeft + 1) * protoToSize / pxPerM;
    }
    if (fa.hasTree && haveScale) {
      visStemM = (fa.treeBottom - fa.treeTop) * protoToSize / pxPerM;
      dbhM = fa.treeWidthLowerCols() * protoToSize / pxPerM;
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
  BsiIntegration integrate(List<AzimuthResult> faces, double dbhCm) {
    double bsi = 0;
    int n = 0;
    for (final f in faces) {
      if (f.analysed && !f.sootHeightM.isNaN && !f.sootProportion.isNaN) {
        bsi += f.sootHeightM * f.sootProportion;
        n++;
      }
    }
    final b = n > 0 ? bsi : double.nan;
    return BsiIntegration(b, dbhCm, Mortality.probability(b, dbhCm), Mortality.verdict(b, dbhCm));
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;

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

  /// 흉고(가슴높이). 흉고직경은 밑둥에서 이 높이의 수간 폭으로 잰다.
  static const double breastHeightM = 1.3;

  /// 방위별 흉고직경 추정값(m)의 중앙값 → cm. 값이 없으면 NaN.
  ///
  /// 방위마다 가려짐·기울기가 달라 폭이 흔들리므로 평균 대신 중앙값을 쓴다.
  static double estimateDbhCm(List<AzimuthResult> faces) {
    final v = [
      for (final f in faces)
        if (f.analysed &&
            f.scaleSource != 'dbh' && // 흉고직경으로 세운 스케일은 순환이라 제외
            !f.dbhEstM.isNaN &&
            f.dbhEstM > 0)
          f.dbhEstM * 100
    ]..sort();
    if (v.isEmpty) return double.nan;
    return v.length.isOdd
        ? v[v.length ~/ 2]
        : (v[v.length ~/ 2 - 1] + v[v.length ~/ 2]) / 2;
  }

  /// Analyse one captured face: segment, scale with the pole, derive metrics,
  /// and (optionally) write an overlay PNG. Returns an [AzimuthResult].
  Future<AzimuthResult> analyzeFace(
    String azimuth,
    String imagePath, {
    required double poleLengthM,
    String? overlayOutPath,
    double? manualPxPerMetre,
    double? dbhCmForScale,
    String? rawOutDir,
  }) async {
    final size = OnnxService.instance.inputSize;
    final lb = ImageOps.letterboxFromFile(imagePath, size);
    if (lb == null) {
      return AzimuthResult(azimuth: azimuth, imagePath: imagePath, analysed: false);
    }
    final analysedAt = DateTime.now();
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
    double pxPerM = manualPxPerMetre ??
        sol?.pxPerMetre ??
        (modelUsable ? double.nan : pole.pxPerMetre);
    String scaleSource = manualPxPerMetre != null
        ? 'manual'
        : sol != null
            ? 'pole'
            : (!modelUsable && !pole.pxPerMetre.isNaN ? 'heuristic' : '');

    final protoToSize = lb.size / fa.mh; // proto rows/cols -> size px

    // 수고봉이 없을 때의 대안: 실측 흉고직경으로 스케일을 세운다(정밀도는 낮다 —
    // 마스크 격자가 4 px라 폭 36 px 기준 ±10 % 안팎). 수고봉·수동 스케일이 있으면
    // 절대 덮어쓰지 않는다.
    var scaleFromDbh = false;
    if (pxPerM.isNaN && dbhCmForScale != null && dbhCmForScale > 0 && fa.hasTree) {
      final s = scaleFromDbhCm(fa, protoToSize, dbhCmForScale);
      if (s != null && s > 0) {
        pxPerM = s;
        scaleSource = 'dbh';
        scaleFromDbh = true;
      }
    }
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
    // 흉고직경 계측 위치(가슴높이 1.3 m)와 그 폭. 오버레이에도 같은 자리를 그린다.
    ({int width, int row, int lo, int hi})? dbhSpan;
    if (fa.hasTree && haveScale) {
      final s = scaleAtRow((fa.treeTop + fa.treeBottom) ~/ 2);
      visStemM = (fa.treeBottom - fa.treeTop) * protoToSize / s;
      // 밑둥에서 1.3 m 위 = 가슴높이. 스케일이 있으니 proto 행으로 환산할 수 있다.
      final rowsUp =
          (breastHeightM * scaleAtRow(fa.treeBottom) / protoToSize).round();
      dbhSpan = fa.treeSpanAtHeight(rowsUp) ??
          fa.treeSpanAtHeight((fa.treeBottom - fa.treeTop) ~/ 3);
      // 스케일을 흉고직경에서 얻었으면 그 폭으로 흉고직경을 "추정"하는 건 순환이다.
      if (dbhSpan != null && !scaleFromDbh) {
        dbhM = dbhSpan.width * protoToSize / scaleAtRow(dbhSpan.row);
      }
    }

    String? overlayPath;
    if (overlayOutPath != null) {
      final treeUp = ImageOps.upsampleMask(fa.treeMask, fa.mh, fa.mw, lb.size);
      final sootUp = ImageOps.upsampleMask(fa.sootMask, fa.mh, fa.mw, lb.size);
      int px(int protoCol) => (protoCol * protoToSize).round();
      final stemSpan = fa.hasTree ? fa.treeSpanAtRow(fa.treeBottom) : null;
      final png = ImageOps.renderOverlay(
        lb.square, treeUp, sootUp, lb.size,
        poleTopY: pole.detected ? pole.topY : null,
        poleBottomY: pole.detected ? pole.bottomY : null,
        poleX: pole.detected ? pole.x : null,
        poleBoundaries: [
          for (final p in sol?.staff.points ?? const []) (x: p.x, y: p.y)
        ],
        stemBase: stemSpan == null
            ? null
            : (y: px(fa.treeBottom), x1: px(stemSpan.lo), x2: px(stemSpan.hi)),
        dbhLine: dbhSpan == null
            ? null
            : (y: px(dbhSpan.row), x1: px(dbhSpan.lo), x2: px(dbhSpan.hi)),
        sootTop: fa.interPx > 0
            ? (y: px(fa.interTop), x1: px(fa.interLeft), x2: px(fa.interRight))
            : null,
      );
      File(overlayOutPath).writeAsBytesSync(png);
      overlayPath = overlayOutPath;
    }

    final result = AzimuthResult(
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
      scaleSource: scaleSource,
    );

    // 연구용 원시 산출물 — 나중에 다른 모델·파이프라인으로 같은 입력을 다시 돌려
    // 비교할 수 있게 모델명·입력 기하·분할 통계·수고봉 경계점·마스크를 남긴다.
    if (rawOutDir != null) {
      _writeRawArtifacts(
        rawOutDir, azimuth, analysedAt, imagePath, lb, fa, sol, pole,
        result, dbhCmForScale, manualPxPerMetre,
      );
    }
    return result;
  }

  static void _writeRawArtifacts(
    String dir,
    String azimuth,
    DateTime analysedAt,
    String imagePath,
    Letterboxed lb,
    FaceAnalysis fa,
    PoleScaleSolution? sol,
    PoleScale pole,
    AzimuthResult r,
    double? dbhCmForScale,
    double? manualPxPerMetre,
  ) {
    try {
      Directory(dir).createSync(recursive: true);
      Object? n(double v) => v.isNaN ? null : v;
      final json = <String, dynamic>{
        'azimuth': azimuth,
        'analysedAt': analysedAt.toIso8601String(),
        'image': imagePath,
        'models': {
          'seg': OnnxService.instance.loadedAsset,
          'pole': OnnxService.pole.loadedAsset,
          'inputSize': lb.size,
        },
        'letterbox': {
          'scale': lb.scale,
          'padX': lb.padX,
          'padY': lb.padY,
          'size': lb.size,
        },
        'seg': {
          'mh': fa.mh,
          'mw': fa.mw,
          'treePx': fa.treePx,
          'sootPx': fa.sootPx,
          'interPx': fa.interPx,
          'nTree': fa.nTree,
          'nSoot': fa.nSoot,
          'bspWhole': n(fa.bspWhole),
          'bspBelow': n(fa.bspBelow),
          'interTop': fa.interTop,
          'interBottom': fa.interBottom,
          'interLeft': fa.interLeft,
          'interRight': fa.interRight,
          'treeTop': fa.treeTop,
          'treeBottom': fa.treeBottom,
        },
        'scale': {
          'source': r.scaleSource,
          'pxPerMetre': n(r.pxPerMetre),
          'manualPxPerMetre': manualPxPerMetre,
          'dbhCmForScale': dbhCmForScale,
          'poleModel': sol == null
              ? null
              : {
                  'pxPerMetre': n(sol.pxPerMetre),
                  'points': [
                    for (final q in sol.staff.points)
                      {'x': q.x, 'y': q.y, 'score': q.score}
                  ],
                },
          'poleHeuristic': {
            'detected': pole.detected,
            'topY': pole.topY,
            'bottomY': pole.bottomY,
            'x': pole.x,
            'pxPerMetre': n(pole.pxPerMetre),
          },
        },
        'metrics': {
          'sootProportion': n(r.sootProportion),
          'sootProportionWhole': n(r.sootProportionWhole),
          'sootHeightM': n(r.sootHeightM),
          'sootWidthM': n(r.sootWidthM),
          'visibleStemHeightM': n(r.visibleStemHeightM),
          'dbhEstM': n(r.dbhEstM),
        },
        'overlay': r.overlayPath,
      };
      File(path.join(dir, '${azimuth}_analysis.json'))
          .writeAsStringSync(_pretty(json), flush: true);
      File(path.join(dir, '${azimuth}_mask_tree.png'))
          .writeAsBytesSync(_maskPng(fa.treeMask, fa.mw, fa.mh), flush: true);
      File(path.join(dir, '${azimuth}_mask_soot.png'))
          .writeAsBytesSync(_maskPng(fa.sootMask, fa.mw, fa.mh), flush: true);
    } catch (_) {
      // 원시 산출물 기록 실패가 분석 결과를 막아서는 안 된다.
    }
  }

  static String _pretty(Map<String, dynamic> j) =>
      const JsonEncoder.withIndent('  ').convert(j);

  /// 0/1 마스크를 0/255 회색 PNG로(모델 proto 해상도 그대로).
  static Uint8List _maskPng(Uint8List mask, int w, int h) {
    final im = img.Image(width: w, height: h, numChannels: 1);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = mask[y * w + x] == 1 ? 255 : 0;
        im.setPixelR(x, y, v);
      }
    }
    return Uint8List.fromList(img.encodePng(im));
  }

  /// 수고봉 없이 **실측 흉고직경**으로 스케일(px/m, letterbox 공간)을 세운다.
  ///
  /// 가슴높이(1.3 m)의 행 위치 자체가 스케일에 달려 있으므로, 줄기 아래 1/3
  /// 지점의 폭으로 초기값을 잡고 "그 스케일로 1.3 m 행을 찾아 폭을 다시 재는"
  /// 과정을 몇 번 반복한다. 수간 폭은 높이에 따라 천천히 변하므로 금방 수렴한다.
  /// 수간이 없거나 폭을 못 재면 null.
  static double? scaleFromDbhCm(FaceAnalysis fa, double protoToSize, double dbhCm) {
    if (!fa.hasTree || dbhCm <= 0) return null;
    final dbhM = dbhCm / 100.0;
    final first = fa.treeSpanAtHeight((fa.treeBottom - fa.treeTop) ~/ 3);
    if (first == null || first.width <= 0) return null;
    var s = first.width * protoToSize / dbhM;
    for (var i = 0; i < 4; i++) {
      final rowsUp = (breastHeightM * s / protoToSize).round();
      final sp = fa.treeSpanAtHeight(rowsUp);
      if (sp == null || sp.width <= 0) break;
      final next = sp.width * protoToSize / dbhM;
      final done = (next - s).abs() < 1e-9;
      s = next;
      if (done) break;
    }
    return s;
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

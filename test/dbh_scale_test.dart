import 'dart:typed_data';

import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:bsi_field/src/services/seg_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// proto 격자(mh×mw)에 수간 마스크를 그린 FaceAnalysis.
/// [widthAt]이 밑둥에서 위로 올라간 행 수(rowsUp)에 따른 폭(열 수)을 준다.
FaceAnalysis _face({
  int mh = 160,
  int mw = 160,
  int treeTop = 20,
  int treeBottom = 150,
  required int Function(int rowsUp) widthAt,
}) {
  final tree = Uint8List(mh * mw);
  for (var y = treeTop; y <= treeBottom; y++) {
    final w = widthAt(treeBottom - y);
    final lo = (mw ~/ 2) - (w ~/ 2);
    for (var x = lo; x < lo + w; x++) {
      tree[y * mw + x] = 1;
    }
  }
  return FaceAnalysis(
    sootMask: Uint8List(mh * mw),
    treeMask: tree,
    mh: mh,
    mw: mw,
    size: 640,
    bspWhole: double.nan,
    bspBelow: double.nan,
    sootPx: 0,
    treePx: 1,
    interPx: 0,
    nTree: 1,
    nSoot: 0,
    interTop: -1,
    interBottom: -1,
    interLeft: -1,
    interRight: -1,
    treeTop: treeTop,
    treeBottom: treeBottom,
  );
}

void main() {
  const protoToSize = 4.0; // 640 / 160

  group('흉고직경 기반 스케일 (수고봉 없을 때)', () {
    test('폭이 일정한 수간: 스케일 = 폭(px) / 흉고직경(m) 정확히', () {
      // 폭 9열 = 36 px, DBH 35 cm → 36 / 0.35 = 102.86 px/m
      final fa = _face(widthAt: (_) => 9);
      final s = AnalysisService.scaleFromDbhCm(fa, protoToSize, 35)!;
      expect(s, closeTo(36 / 0.35, 1e-9));
    });

    test('가늘어지는 수간: 1.3 m 행의 폭으로 수렴한다(밑둥 폭이 아니라)', () {
      // 밑둥 12열, 위로 갈수록 1열씩 좁아져 rowsUp 30(=1.3 m 근처)에서 9열.
      // 참 스케일 103 px/m이면 1.3 m = 133.9 px = 33.5 proto행.
      int width(int up) => (12 - up ~/ 10).clamp(4, 12);
      final fa = _face(widthAt: width);
      final s = AnalysisService.scaleFromDbhCm(fa, protoToSize, 35)!;
      // 수렴 지점에서 rowsUp = 1.3·s/4, 그 행 폭 w → s = 4w/0.35 가 자기일관이어야 한다.
      final rowsUp = (1.3 * s / protoToSize).round();
      final w = fa.treeSpanAtHeight(rowsUp)!.width;
      expect(s, closeTo(w * protoToSize / 0.35, 1e-6));
      // 밑둥 폭(12열=48 px → 137 px/m)으로 계산한 값과는 달라야 한다.
      expect(s, lessThan(48 / 0.35 - 1));
    });

    test('수간이 없으면 null', () {
      final fa = _face(widthAt: (_) => 9);
      final none = FaceAnalysis(
        sootMask: fa.sootMask,
        treeMask: Uint8List(fa.mh * fa.mw),
        mh: fa.mh,
        mw: fa.mw,
        size: 640,
        bspWhole: double.nan,
        bspBelow: double.nan,
        sootPx: 0,
        treePx: 0,
        interPx: 0,
        nTree: 0,
        nSoot: 0,
        interTop: -1,
        interBottom: -1,
        interLeft: -1,
        interRight: -1,
        treeTop: -1,
        treeBottom: -1,
      );
      expect(AnalysisService.scaleFromDbhCm(none, protoToSize, 35), isNull);
      expect(AnalysisService.scaleFromDbhCm(fa, protoToSize, 0), isNull);
    });

    test('흉고직경으로 세운 스케일의 면은 자동 DBH 추정에서 제외된다(순환 방지)', () {
      final faces = [
        const AzimuthResult(
            azimuth: 'N', analysed: true, dbhEstM: 0.35, scaleSource: 'pole'),
        const AzimuthResult(
            azimuth: 'E', analysed: true, dbhEstM: 0.80, scaleSource: 'dbh'),
      ];
      expect(AnalysisService.estimateDbhCm(faces), closeTo(35, 1e-9));
    });

    test('scaleSource는 JSON을 왕복한다', () {
      const r = AzimuthResult(azimuth: 'S', analysed: true, scaleSource: 'dbh');
      expect(AzimuthResult.fromJson(r.toJson()).scaleSource, 'dbh');
      // 구버전 기록(필드 없음)은 빈 문자열로 읽힌다.
      final j = r.toJson()..remove('scaleSource');
      expect(AzimuthResult.fromJson(j).scaleSource, '');
    });
  });
}

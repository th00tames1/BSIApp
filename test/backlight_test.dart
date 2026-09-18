import 'dart:typed_data';

import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:bsi_field/src/services/backlight.dart';
import 'package:bsi_field/src/services/csv_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// 역광 실루엣 판정 — 현장 35면에서 잡은 기준(001 동만 걸림)을 합성 장면으로 고정한다.
///
/// 현장 수치(참고): 셔터 판정 001 동 줄기 25 · 주변/줄기 6.7, 다음으로 높은 정상 면
/// 3.2(줄기 42). 분석 판정 001 동 중앙 19 · 어두운 비율 0.86 · 주변/줄기 8.1,
/// 다음 면 37 · 0.38 · 3.7.
void main() {
  /// 가운데 세로 띠(줄기)와 좌우(배경)를 가진 썸네일. [texture]만큼 줄기 밝기가 흔들린다.
  Uint8List thumb(int trunk, int surround, {int texture = 0, int w = 96, int h = 128}) {
    final g = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final inTrunk = x >= (w * 0.42).floor() && x < (w * 0.58).floor();
        final v = inTrunk ? trunk + ((x + y) % 2 == 0 ? texture : -texture) : surround;
        g[y * w + x] = v.clamp(0, 255);
      }
    }
    return g;
  }

  group('셔터 직후 판정(썸네일)', () {
    test('해를 등진 실루엣은 걸린다', () {
      final s = Backlight.scoreThumb(thumb(20, 170), 96, 128);
      expect(s.silhouette, isTrue, reason: 'trunk ${s.trunk} ratio ${s.ratio}');
    });

    test('정상 노출 줄기는 걸리지 않는다', () {
      expect(Backlight.scoreThumb(thumb(70, 115), 96, 128).silhouette, isFalse);
    });

    test('햇빛 받은 그을린 줄기(검지만 주변과 대비가 약함)는 걸리지 않는다', () {
      expect(Backlight.scoreThumb(thumb(42, 133, texture: 10), 96, 128).silhouette, isFalse);
    });

    test('장면 전체가 어두운 그늘은 실루엣이 아니다(대비가 없다)', () {
      expect(Backlight.scoreThumb(thumb(18, 45), 96, 128).silhouette, isFalse);
    });

    test('가운데 띠에 하늘이 섞여도 줄기(어두운 절반)만 본다', () {
      // 줄기 폭이 띠(30 %)보다 좁아 띠의 절반 이상이 밝은 하늘이어도 판정은 같다.
      final s = Backlight.scoreThumb(thumb(22, 175), 96, 128);
      expect(s.trunk, lessThan(Backlight.shotTrunkMax));
      expect(s.silhouette, isTrue);
    });
  });

  group('분석 뒤 판정(수간 마스크)', () {
    /// 640 letterbox 캔버스(좌우 여백 회색 114) + 160 격자 마스크.
    (img.Image, Uint8List) scene(int trunk, int surround, {int texture = 0}) {
      final im = img.Image(width: 640, height: 640);
      img.fill(im, color: img.ColorRgb8(114, 114, 114)); // letterbox 여백
      for (var y = 0; y < 640; y++) {
        for (var x = 80; x < 560; x++) {
          final inTrunk = x >= 280 && x < 360;
          final v = (inTrunk
                  ? trunk + ((x ~/ 4 + y ~/ 4) % 2 == 0 ? texture : -texture)
                  : surround)
              .clamp(0, 255);
          im.setPixelRgb(x, y, v, v, v);
        }
      }
      final mask = Uint8List(160 * 160);
      for (var y = 0; y < 160; y++) {
        for (var x = 70; x < 90; x++) {
          mask[y * 160 + x] = 1;
        }
      }
      return (im, mask);
    }

    test('실루엣 줄기는 걸린다', () {
      final (im, m) = scene(15, 160);
      final s = Backlight.scoreMask(im, m, 160, 160);
      expect(s.silhouette, isTrue, reason: 'median ${s.median} dark ${s.darkFraction}');
    });

    test('온통 그을렸지만 질감이 살아 있는 줄기는 걸리지 않는다', () {
      final (im, m) = scene(40, 110, texture: 20);
      expect(Backlight.scoreMask(im, m, 160, 160).silhouette, isFalse);
    });

    test('letterbox 여백(회색 114)은 주변 밝기에 넣지 않는다', () {
      final (im, m) = scene(15, 160);
      expect(Backlight.scoreMask(im, m, 160, 160).surround, 160);
    });

    test('마스크가 너무 작으면 판정하지 않는다', () {
      final (im, _) = scene(15, 160);
      final tiny = Uint8List(160 * 160)..[80 * 160 + 80] = 1;
      expect(Backlight.scoreMask(im, tiny, 160, 160).silhouette, isFalse);
    });
  });

  group('실루엣 면의 처리', () {
    AzimuthResult face(String az, {String issue = '', bool edited = false}) =>
        AzimuthResult(
          azimuth: az,
          imagePath: '/p/$az.jpg',
          sootHeightM: 2,
          sootProportion: 0.5,
          analysed: true,
          issue: issue,
          manualEdited: edited,
        );

    test('통합 BSI에서 빠진다', () {
      final r = AnalysisService.instance.integrate(
          [face('N'), face('E', issue: 'backlit'), face('S'), face('W')], 30);
      expect(r.facesUsed, 3);
      expect(r.isPartial, isTrue);
    });

    test('조사자가 값을 고치면 다시 들어간다', () {
      final r = AnalysisService.instance.integrate(
          [face('N'), face('E', issue: 'backlit', edited: true)], 30);
      expect(r.facesUsed, 2);
    });

    test('사유가 저장·복원된다(옛 기록은 사유 없음)', () {
      final back = AzimuthResult.fromJson(face('E', issue: 'backlit').toJson());
      expect(back.issue, 'backlit');
      expect(AzimuthResult.fromJson({'azimuth': 'N'}).issue, '');
    });

    test('CSV에 face_issue 열로 나간다', () {
      final rows = CsvExport.rowsForTest([
        SurveyRecord(
          treeId: 'T',
          site: 'S',
          address: '',
          species: '소나무',
          dbhCm: 30,
          modelName: 'm',
          faces: [face('N'), face('E', issue: 'backlit')],
          createdAt: DateTime(2026, 9, 18),
        )
      ]);
      final i = rows.first.indexOf('face_issue');
      expect(i, greaterThan(0));
      expect(rows[1][i], '');
      expect(rows[2][i], 'backlit');
      for (final r in rows) {
        expect(r.length, rows.first.length);
      }
    });
  });
}

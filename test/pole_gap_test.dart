import 'package:bsi_field/src/models/survey.dart';
import 'package:flutter_test/flutter_test.dart';

/// 수고봉 간격 되잡기.
///
/// 봉은 조사목마다 다를 수 있어서, 잘못 찍힌 간격을 기록에서 고칠 수 있어야
/// 한다. 스케일(px/m)은 간격에 반비례하므로 미터 단위 값은 간격에 **정비례**
/// 한다 — 사진을 다시 분석하지 않아도 산술만으로 정확히 환산된다.
void main() {
  AzimuthResult face(String az,
          {double soot = 2.0,
          double stem = 8.0,
          double pxm = 100.0,
          double ratio = 0.5,
          bool manual = false,
          bool edited = false,
          String? source}) =>
      AzimuthResult(
        azimuth: az,
        analysed: true,
        sootProportion: ratio,
        sootHeightM: soot,
        sootWidthM: 0.4,
        visibleStemHeightM: stem,
        pxPerMetre: pxm,
        dbhEstM: 0.35,
        manual: manual,
        manualEdited: edited,
        scaleSource: source ?? (manual ? 'manual' : 'pole'),
      );

  SurveyRecord rec(List<AzimuthResult> faces,
          {double gap = 1.0, bool dbhAuto = false}) =>
      SurveyRecord(
        dbhAuto: dbhAuto,
        treeId: '001',
        site: '현장검증',
        address: '',
        species: 'pinus_densiflora',
        dbhCm: 35,
        modelName: 'test',
        createdAt: DateTime(2026, 8, 26),
        poleGapM: gap,
        faces: faces,
      );

  group('간격을 바꾸면 미터 값이 정비례한다', () {
    test('0.2 m로 잡힌 기록을 1 m로 고치면 높이가 5배가 된다', () {
      final r = rec([face('E', soot: 2.0, stem: 8.0, pxm: 500)], gap: 0.2);
      final fixed = r.withPoleGap(1.0);
      expect(fixed.poleGapM, 1.0);
      final f = fixed.faces.single;
      expect(f.sootHeightM, closeTo(10.0, 1e-9));
      expect(f.visibleStemHeightM, closeTo(40.0, 1e-9));
      expect(f.dbhEstM, closeTo(1.75, 1e-9));
      // 스케일은 반대로 — 1 m가 100 px가 된다.
      expect(f.pxPerMetre, closeTo(100.0, 1e-9));
      // 비율은 스케일과 무관하므로 그대로여야 한다.
      expect(f.sootProportion, 0.5);
    });

    test('되돌리면 원래 값으로 정확히 돌아온다', () {
      final r = rec([face('E'), face('W', soot: 3.5, stem: 9.0)], gap: 1.0);
      final back = r.withPoleGap(0.25).withPoleGap(1.0);
      for (var i = 0; i < r.faces.length; i++) {
        expect(back.faces[i].sootHeightM, closeTo(r.faces[i].sootHeightM, 1e-9));
        expect(back.faces[i].visibleStemHeightM,
            closeTo(r.faces[i].visibleStemHeightM, 1e-9));
        expect(back.faces[i].pxPerMetre, closeTo(r.faces[i].pxPerMetre, 1e-9));
      }
      expect(back.poleGapM, 1.0);
    });

    test('BSI도 같은 배율로 움직인다', () {
      // BSI = Σ(그을음 높이 × 비율) → 높이가 비례하면 BSI도 비례한다.
      final faces = [face('E'), face('W'), face('S'), face('N')];
      final base = rescaleFacesForGap(faces, 1.0);
      final twice = rescaleFacesForGap(faces, 2.0);
      double bsi(List<AzimuthResult> fs) =>
          fs.fold(0.0, (a, f) => a + f.sootHeightM * f.sootProportion);
      expect(bsi(twice), closeTo(bsi(base) * 2, 1e-9));
    });
  });

  group('조사자가 넣은 값은 건드리지 않는다', () {
    test('야장 입력 면(manual)은 이미 실측 미터값이라 그대로 둔다', () {
      final r = rec([face('E'), face('W', manual: true, soot: 3.0)], gap: 1.0);
      final fixed = r.withPoleGap(2.0);
      expect(fixed.faces[0].sootHeightM, closeTo(4.0, 1e-9)); // 자동 → 2배
      expect(fixed.faces[1].sootHeightM, 3.0); // 수기 → 그대로
    });

    test('손으로 고친 면은 그을음 높이만 지키고 나머지는 환산한다', () {
      // 조사자가 잰 것은 그을음 높이뿐이다. 같은 면의 줄기 높이·폭·흉고직경·
      // px/m은 여전히 분석이 낸 값이라 새 간격을 따라야 한다 — 재분석이 이
      // 면을 건너뛰므로 여기서 안 고치면 영영 옛 간격에 묶인다.
      final r = rec([face('E', edited: true, soot: 3.0, stem: 8.0, pxm: 100)],
          gap: 1.0);
      final f = r.withPoleGap(0.5).faces.single;
      expect(f.sootHeightM, 3.0); // 실측값 — 보존
      expect(f.visibleStemHeightM, closeTo(4.0, 1e-9)); // 분석값 — 환산
      expect(f.pxPerMetre, closeTo(200.0, 1e-9));
    });

    test('한 면만 손으로 고쳐도 수고가 옛 간격에 묶이지 않는다', () {
      // effectiveHeightM은 면별 최댓값이라, 안 고친 면 하나가 남으면 그 값이
      // 이겨서 화면·CSV의 수고가 틀린 채로 나간다.
      final r = rec([
        face('E', edited: true, stem: 8.0),
        face('W', stem: 8.0),
      ], gap: 1.0);
      expect(r.withPoleGap(0.5).effectiveHeightM, closeTo(4.0, 1e-9));
    });

    test('직접 넣은 수고·그을음 높이는 유지된다', () {
      final r = rec([face('E')], gap: 1.0)
          .copyWith(heightM: 12.3, sootMaxM: 4.5);
      final fixed = r.withPoleGap(2.0);
      expect(fixed.effectiveHeightM, 12.3);
      expect(fixed.effectiveSootMaxM, 4.5);
    });
  });

  group('수고봉에서 나온 스케일만 환산한다', () {
    // px/m에 간격이 들어가는 경로는 수고봉 경계 모델의 해뿐이다. 봉 전장으로
    // 잰 'heuristic', 실측 흉고직경으로 세운 'dbh', 조사자가 준 'manual'은
    // 같은 사진을 새 간격으로 다시 분석해도 값이 그대로다 — 산술 환산도
    // 그래야 미리보기와 재분석 결과가 갈리지 않는다.
    for (final src in const ['heuristic', 'dbh', 'manual']) {
      test("'$src' 면은 간격을 고쳐도 값이 그대로다", () {
        final r = rec([face('E', source: src)], gap: 1.0);
        final f = r.withPoleGap(0.25).faces.single;
        expect(f.sootHeightM, 2.0);
        expect(f.visibleStemHeightM, 8.0);
        expect(f.sootWidthM, 0.4);
        expect(f.dbhEstM, 0.35);
        expect(f.pxPerMetre, 100.0);
      });
    }

    test("수고봉 면과 섞여 있으면 수고봉 면만 움직인다", () {
      final r = rec([face('E'), face('W', source: 'dbh')], gap: 1.0);
      final fixed = r.withPoleGap(2.0);
      expect(fixed.faces[0].sootHeightM, closeTo(4.0, 1e-9));
      expect(fixed.faces[1].sootHeightM, 2.0);
      expect(gapIndependentFaceCount(r.faces), 1);
    });

    test("출처를 남기지 않던 옛 기록('')은 계속 환산된다", () {
      final r = rec([face('E', source: '')], gap: 1.0);
      expect(r.withPoleGap(2.0).faces.single.sootHeightM, closeTo(4.0, 1e-9));
    });
  });

  group('잘못된 입력에는 아무 일도 하지 않는다', () {
    test('0 이하는 무시한다', () {
      final r = rec([face('E')], gap: 1.0);
      expect(r.withPoleGap(0).poleGapM, 1.0);
      expect(r.withPoleGap(-1).faces.single.sootHeightM, 2.0);
    });

    test('같은 값이면 계측값이 바뀌지 않는다', () {
      final r = rec([face('E')], gap: 0.5);
      final same = r.withPoleGap(0.5);
      expect(same.poleGapM, 0.5);
      expect(same.faces.single.sootHeightM, 2.0);
    });

    test('값이 없는(NaN) 면은 NaN으로 남는다', () {
      final r = rec([const AzimuthResult(azimuth: 'E', analysed: true)]);
      final f = r.withPoleGap(2.0).faces.single;
      expect(f.sootHeightM.isNaN, isTrue);
      expect(f.visibleStemHeightM.isNaN, isTrue);
    });
  });

  group('흉고직경으로 세운 스케일은 그 값의 출처를 따른다', () {
    // 'dbh' 면의 px/m은 흉고직경에서 나온다. 그 흉고직경이 조사자 실측값이면
    // 간격과 무관하지만, 앱이 추정한 값이면 그것 자체가 스케일에 비례하므로
    // 결국 간격을 따라 움직인다. 미리보기와 재분석 결과가 갈리지 않으려면
    // 산술 환산도 같은 규칙을 따라야 한다.
    test('실측 흉고직경이면 그 면은 움직이지 않는다', () {
      final r = rec([face('E', source: 'dbh')], gap: 1.0);
      expect(r.withPoleGap(0.5).faces.single.sootHeightM, 2.0);
    });

    test('앱이 추정한 흉고직경이면 그 면도 함께 움직인다', () {
      final r = rec([face('E', source: 'dbh')], gap: 1.0, dbhAuto: true);
      expect(r.withPoleGap(0.5).faces.single.sootHeightM, closeTo(1.0, 1e-9));
    });

    test('출처가 없는 옛 기록은 값이 추정값과 같은지로 가른다', () {
      // 앱은 추정값을 1 cm로 반올림해 채운다. 저장된 값이 지금 다시 센
      // 추정값과 그 자릿수 안에서 같으면 실측이 아니라고 본다.
      // (현장검증 003·005는 242·270 cm로 추정값과 일치, 007은 실측 44 대 추정 238)
      double est(List<AzimuthResult> fs) {
        final v = [
          for (final f in fs)
            if (f.analysed && f.scaleSource != 'dbh' && !f.dbhEstM.isNaN)
              f.dbhEstM * 100
        ]..sort();
        return v.isEmpty ? double.nan : v[v.length ~/ 2];
      }

      final faces = [face('E'), face('W')];
      expect(est(faces).roundToDouble(), 35); // dbhEstM 0.35 m
      // 저장값이 추정값과 같다 → 추정으로 보고 간격을 따라 움직여야 한다
      final auto = rec(faces, gap: 1.0);
      expect((est(auto.faces).roundToDouble() - auto.dbhCm).abs() < 0.5, isTrue);
      // 저장값이 뚜렷이 다르다 → 실측으로 본다
      final measured = rec(faces, gap: 1.0).copyWith(dbhCm: 44);
      expect(
          (est(measured.faces).roundToDouble() - measured.dbhCm).abs() < 0.5,
          isFalse);
    });

    test('추정 여부가 저장·복원된다', () {
      final r = rec([face('E')], dbhAuto: true);
      expect(SurveyRecord.fromMap(r.toMap()).dbhAuto, isTrue);
      expect(SurveyRecord.fromMap(rec([face('E')]).toMap()).dbhAuto, isFalse);
    });
  });

  group('영향받지 않는 면을 빠짐없이 센다', () {
    test('직접 넣은 면과 손으로 고친 면도 안내에 포함한다', () {
      // 세지 않으면 "왜 BSI가 그대로지?"의 답이 안내에서 빠진다.
      final faces = [
        face('E'), // 수고봉 — 움직인다
        face('W', manual: true), // 야장 — 안 움직인다
        face('S', edited: true), // 손으로 고침 — 그을음 높이가 안 움직인다
        face('N', source: 'heuristic'), // 봉 전장 — 안 움직인다
      ];
      expect(gapIndependentFaceCount(faces), 3);
    });

    test('추정 흉고직경이면 dbh 면은 안내에서 빠진다', () {
      final faces = [face('E'), face('W', source: 'dbh')];
      expect(gapIndependentFaceCount(faces), 1);
      expect(gapIndependentFaceCount(faces, dbhFollowsGap: true), 0);
    });
  });

  test('저장했다 읽어도 간격이 남는다', () {
    final r = rec([face('E')], gap: 0.25);
    expect(SurveyRecord.fromMap(r.toMap()).poleGapM, 0.25);
  });
}

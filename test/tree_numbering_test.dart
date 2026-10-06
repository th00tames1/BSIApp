import 'dart:convert';
import 'dart:io';

import 'package:bsi_field/src/app_prefs.dart';
import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:bsi_field/src/services/overlay_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// 조사목 번호 부여·조사지 이름 변경·오버레이 파일명이 서로 겹치지 않는지.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await loadPrefs();
    projects.value = [];
    activeSite.value = null;
  });

  group('자동 번호', () {
    test('이미 쓴 번호는 건너뛰고 숫자가 아닌 번호는 무시한다', () {
      expect(nextFreeTreeSeq(0, const []), 1);
      expect(nextFreeTreeSeq(3, const ['004', '005', 'TA205-001']), 6);
      expect(nextFreeTreeSeq(3, const ['002']), 4); // 지난 번호는 상관없다
      expect(nextFreeTreeSeq(0, const ['1', '002', ' 3 ']), 4); // 자릿수 무관
    });

    test('번호를 미리 보기만 해서는 소모되지 않는다', () {
      upsertProject(site: '산청', location: '', treeSeq: 4);
      expect(peekNextTreeSeq(), 5);
      expect(peekNextTreeSeq(), 5); // 촬영 화면에서 그냥 나온 경우
      expect(activeProject!.treeSeq, 4);
    });

    test('다음 번호를 낮춰도 저장된 번호와 진행 중인 번호를 건너뛴다', () {
      upsertProject(site: '산청', location: '', treeSeq: 0);
      expect(peekNextTreeSeq(used: const ['001', '002', '003']), 4);
    });

    test('저장하면 그 조사지의 카운터가 저장한 번호까지 오른다', () {
      upsertProject(site: '산청', location: '', treeSeq: 3);
      upsertProject(site: '인제', location: '', treeSeq: 0);
      selectProject('산청');

      noteTreeIdSaved('산청', '005'); // 손으로 바꾼 번호도 따라간다
      expect(activeProject!.treeSeq, 5);
      expect(peekNextTreeSeq(), 6);

      noteTreeIdSaved('산청', '002'); // 작은 번호는 카운터를 내리지 않는다
      noteTreeIdSaved('산청', 'TA205-001'); // 숫자가 아닌 번호는 무시
      expect(activeProject!.treeSeq, 5);

      expect(projects.value.firstWhere((x) => x.site == '인제').treeSeq, 0);
    });

    test('번호 비교는 자릿수와 공백을 무시한다', () {
      expect(sameTreeId('5', '005'), isTrue);
      expect(sameTreeId(' 7 ', '007'), isTrue);
      expect(sameTreeId('005', '006'), isFalse);
      expect(sameTreeId('TA205-001', 'TA205-001'), isTrue);
      expect(sameTreeId('TA205-001', '001'), isFalse);
    });
  });

  group('프로젝트 이름 변경', () {
    Map<String, dynamic> draft() =>
        jsonDecode(loadDraftJson()!) as Map<String, dynamic>;

    test('진행 중인 조사가 새 조사지명과 위치를 따라간다', () {
      upsertProject(site: '산청', location: '산청군');
      saveDraftJson(jsonEncode({'treeId': '004', 'site': '산청', 'address': '산청군'}));

      upsertProject(existing: activeProject, site: '산청 2구역', location: '산청군 시천면');

      expect(draft()['site'], '산청 2구역');
      expect(draft()['address'], '산청군 시천면');
      expect(draft()['treeId'], '004');
    });

    test('조사 중에 고친 주소와 다른 프로젝트의 조사는 그대로 둔다', () {
      upsertProject(site: '산청', location: '산청군');
      upsertProject(site: '인제', location: '인제군');
      saveDraftJson(jsonEncode({'site': '산청', 'address': '산청군 단성면'}));

      final sancheong = projects.value.firstWhere((x) => x.site == '산청');
      upsertProject(existing: sancheong, site: '산청A', location: '산청군 시천면');
      expect(draft()['site'], '산청A');
      expect(draft()['address'], '산청군 단성면');

      final inje = projects.value.firstWhere((x) => x.site == '인제');
      upsertProject(existing: inje, site: '인제B', location: '');
      expect(draft()['site'], '산청A');
    });

    test('조사지 경계 파일이 새 이름으로 옮겨진다', () async {
      final docs = Directory.systemTemp.createTempSync('bsi_overlay_');
      addTearDown(() => docs.deleteSync(recursive: true));
      final overlays = Directory(p.join(docs.path, 'overlays'))..createSync();
      File(p.join(overlays.path, '산청.json')).writeAsStringSync('[1]');

      await OverlayStore.rename('산청', '산청 2구역', docs: docs);

      expect(File(p.join(overlays.path, '산청.json')).existsSync(), isFalse);
      expect(File(p.join(overlays.path, '산청 2구역.json')).readAsStringSync(), '[1]');

      // 경계가 없던 조사지는 아무 일도 없다.
      await OverlayStore.rename('없음', '새 이름', docs: docs);
      expect(File(p.join(overlays.path, '새 이름.json')).existsSync(), isFalse);
    });
  });

  group('오버레이 파일명', () {
    const dir = '/docs/overlays';

    test('조사지가 달라 같은 번호·방위라도 사진이 다르면 파일이 다르다', () {
      final a = AnalysisService.overlayPathFor(dir, '/docs/photos/001_E_1787700000000.jpg');
      final b = AnalysisService.overlayPathFor(dir, '/docs/photos/001_E_1787799999999.jpg');
      expect(a, isNot(b));
      expect(p.basename(a), '001_E_1787700000000_overlay.png');
    });

    test('같은 사진을 다시 분석하면 같은 파일을 덮어쓴다', () {
      const photo = '/docs/photos/001_E_1787700000000.jpg';
      expect(AnalysisService.overlayPathFor(dir, photo),
          AnalysisService.overlayPathFor(dir, photo));
    });
  });
}

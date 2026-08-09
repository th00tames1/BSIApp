import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/draft.dart';
import '../theme.dart';

/// 앱에 내장한 예시 조사목(4방위). 카메라 없이 전체 분석 흐름을 시험할 때 쓴다.
///
/// 실제 조사 사진이며 수고봉 1 m 경계가 네 면 모두 5개 이상 보여, 스케일 산출과
/// 원근 보정까지 전 구간이 동작하는 것을 확인할 수 있다.
class DemoSample {
  DemoSample._();

  static const Map<Azimuth, String> _assets = {
    Azimuth.east: 'assets/sample/demo_E.jpg',
    Azimuth.west: 'assets/sample/demo_W.jpg',
    Azimuth.south: 'assets/sample/demo_S.jpg',
    Azimuth.north: 'assets/sample/demo_N.jpg',
  };

  static int get faceCount => _assets.length;

  /// 시연 모드의 촬영 화면이 뷰파인더 배경으로 쓸 에셋 경로.
  static String assetFor(Azimuth az) => _assets[az]!;

  /// 한 방위의 예시 사진만 앱 문서 폴더로 풀어 경로를 돌려준다.
  /// 시연 모드의 순차 "촬영"이 실제 촬영과 같은 저장 경로를 타게 한다.
  static Future<String> photoFor(Azimuth az, String treeId) async {
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(dir.path, 'photos'));
    if (!destDir.existsSync()) destDir.createSync(recursive: true);
    final bytes = await rootBundle.load(_assets[az]!);
    final dest = p.join(destDir.path, '${treeId}_${az.code}_demo.jpg');
    await File(dest).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return dest;
  }

  /// 에셋을 앱 문서 폴더로 풀어 4방위가 채워진 조사를 만든다.
  ///
  /// 촬영 지점 GPS가 없으므로 좌표는 비어 있고(지도 핀 없음), 그 외에는 실제
  /// 촬영으로 만든 조사와 완전히 같은 경로를 탄다.
  static Future<SurveyDraft> createDraft({
    String treeId = 'DEMO',
    String site = '예시 데이터',
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(dir.path, 'photos'));
    if (!destDir.existsSync()) destDir.createSync(recursive: true);

    final draft = SurveyDraft()
      ..treeId = treeId
      ..site = site
      ..address = ''
      ..isSample = true;

    for (final e in _assets.entries) {
      final bytes = await rootBundle.load(e.value);
      final dest = p.join(destDir.path, '${treeId}_${e.key.code}_demo.jpg');
      await File(dest).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      draft.photos[e.key] = dest;
    }
    return draft;
  }
}

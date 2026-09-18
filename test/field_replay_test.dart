/// 현장 사진 재현 — 앱의 Dart 분석 코드를 PC에서 그대로 돌린다.
///
/// 전처리·구제 경로·디코더·수고봉 해·계측은 앱 코드 그대로이고, 추론만
/// `tool/ort_server.py`가 앱과 같은 .onnx 파일로 대신한다. 현장에서 받은
/// 원시 번들(개발자 모드 내보내기)을 넣으면 "지금 앱이라면 무엇을 냈을지"를 본다.
///
/// 평소 `flutter test`에서는 건너뛴다. 돌리려면:
///   BSI_FIELD_DIR=(내보내기 폴더) BSI_ORT_PY=(onnxruntime이 있는 python) \
///     flutter test test/field_replay_test.dart
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:bsi_field/src/services/backlight.dart';
import 'package:bsi_field/src/services/onnx_service.dart';
import 'package:flutter_test/flutter_test.dart';

final _dir = Platform.environment['BSI_FIELD_DIR'];
final _py = Platform.environment['BSI_ORT_PY'];

/// 파이썬 추론 서버 — 모델을 한 번만 올리고 요청마다 파일로 주고받는다.
class _OrtServer {
  late final Process _p;
  late final StreamIterator<String> _lines;
  final Directory _tmp = Directory.systemTemp.createTempSync('bsi_ort_');
  int _n = 0;

  Future<void> start() async {
    _p = await Process.start(_py!, ['tool/ort_server.py']);
    _p.stderr.transform(utf8.decoder).listen(stderr.write);
    _lines = StreamIterator(
        _p.stdout.transform(utf8.decoder).transform(const LineSplitter()));
  }

  Future<List<({Float32List data, List<int> shape})>> run(
      String asset, Float32List chw, int size) async {
    final f = File('${_tmp.path}/in${_n++}.f32');
    f.writeAsBytesSync(chw.buffer.asUint8List(chw.offsetInBytes, chw.lengthInBytes));
    _p.stdin.writeln('$asset\t${f.path}\t$size');
    await _p.stdin.flush();
    if (!await _lines.moveNext()) throw StateError('ort_server 종료됨');
    return [
      for (final part in _lines.current.split(';'))
        () {
          final i = part.lastIndexOf(':');
          final bytes = File(part.substring(0, i)).readAsBytesSync();
          return (
            data: bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4),
            shape: part.substring(i + 1).split(',').map(int.parse).toList(),
          );
        }()
    ];
  }

  Future<void> stop() async {
    await _p.stdin.close();
    await _p.exitCode;
    _tmp.deleteSync(recursive: true);
  }
}

/// 내보내기 폴더에서 조사목·방위의 사진을 찾는다(photos/번호_조사목/조사목_방위_시각.jpg).
String? _photo(String tree, String az) {
  final photos = Directory('$_dir/photos');
  for (final d in photos.listSync().whereType<Directory>()) {
    if (!d.path.endsWith('_$tree')) continue;
    for (final f in d.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (RegExp('^${tree}_${az}_\\d+\\.jpg\$').hasMatch(name)) return f.path;
    }
  }
  return null;
}

String _f(double v, [int d = 3]) => v.isNaN ? '–' : v.toStringAsFixed(d);

void main() {
  final skip = (_dir == null || _py == null)
      ? 'BSI_FIELD_DIR · BSI_ORT_PY 가 없어 건너뜀(현장 재현용)'
      : null;

  test('현장 사진 재현', () async {
    final srv = _OrtServer();
    await srv.start();
    OnnxService.testBackend = srv.run;
    addTearDown(() async {
      OnnxService.testBackend = null;
      await srv.stop();
    });
    await OnnxService.instance.load('assets/models/bsi_seg_yolo26s_640.onnx');
    await OnnxService.pole.load('assets/models/pole_boundary_640.onnx');

    final faces = (Platform.environment['BSI_FACES'] ??
            '001:E,001:S,001:N,003:W,005:E,005:N')
        .split(',');
    final gaps = (Platform.environment['BSI_GAPS'] ?? '1.0')
        .split(',')
        .map(double.parse)
        .toList();
    final out = Directory.systemTemp.createTempSync('bsi_replay_');
    // ignore: avoid_print
    print('면       간격  R_below R_whole  그을음m  줄기m   px/m   스케일  사유     셔터판정(줄기·주변/줄기)');
    for (final fa in faces) {
      final [tree, az] = fa.split(':');
      final path = _photo(tree, az);
      if (path == null) {
        // ignore: avoid_print
        print('$fa: 사진 없음');
        continue;
      }
      for (final gap in gaps) {
        final shot = await Backlight.scoreFile(path, File(path).readAsBytesSync());
        final AzimuthResult r = await AnalysisService.instance.analyzeFace(
          az,
          path,
          poleLengthM: 3.0,
          overlayOutPath: '${out.path}/${tree}_${az}_g$gap.png',
          poleGapMetres: gap,
        );
        // ignore: avoid_print
        print('${tree}_$az  ${gap.toStringAsFixed(1)}  '
            '${_f(r.sootProportion).padLeft(7)} ${_f(r.sootProportionWhole).padLeft(7)} '
            '${_f(r.sootHeightM, 2).padLeft(7)} ${_f(r.visibleStemHeightM, 2).padLeft(6)} '
            '${_f(r.pxPerMetre, 1).padLeft(6)}  ${r.scaleSource.padRight(5)} ${r.issue.padRight(8)} '
            '${shot == null ? '실패' : '${_f(shot.trunk, 0)}·${_f(shot.ratio, 1)}${shot.silhouette ? ' 실루엣' : ''}'}');
      }
    }
    // ignore: avoid_print
    print('오버레이: ${out.path}');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 10)));
}

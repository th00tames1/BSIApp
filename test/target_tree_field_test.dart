/// Opt-in real-photo regression through the production AnalysisService.
///
/// BSI_FIELD_DIR: private export root (photos are never committed).
/// BSI_ORT_PY: Python with numpy/onnxruntime for tool/ort_server.py.
/// BSI_TARGET_OUT: optional retained artifact directory, default .dart_tool/target_tree_field.
/// Uses the app's preprocessing, model files, decoder, rescue paths and metrics;
/// only the ONNX execution provider is replaced by desktop CPU inference.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bsi_field/src/models/survey.dart';
import 'package:bsi_field/src/models/tuning.dart';
import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:bsi_field/src/services/image_ops.dart';
import 'package:bsi_field/src/services/onnx_service.dart';
import 'package:bsi_field/src/services/seg_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

class _OrtServer {
  late Process process;
  late StreamIterator<String> lines;
  late Directory scratch;
  int count = 0;
  final calls = <String, int>{};
  List<({Float32List data, List<int> shape})>? firstSegmentation;

  Future<void> start(String python) async {
    scratch = Directory.systemTemp.createTempSync('bsi_target_');
    process = await Process.start(python, ['tool/ort_server.py']);
    process.stderr.transform(utf8.decoder).listen(stderr.write);
    lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
  }

  Future<List<({Float32List data, List<int> shape})>> run(
    String asset,
    Float32List chw,
    int size,
  ) async {
    calls[asset] = (calls[asset] ?? 0) + 1;
    final input = File('${scratch.path}/in${count++}.f32');
    input.writeAsBytesSync(
      chw.buffer.asUint8List(chw.offsetInBytes, chw.lengthInBytes),
    );
    process.stdin.writeln('$asset\t${input.path}\t$size');
    await process.stdin.flush();
    if (!await lines.moveNext()) throw StateError('ONNX server terminated');
    final outputs = [
      for (final part in lines.current.split(';'))
        () {
          final split = part.lastIndexOf(':');
          final bytes = File(part.substring(0, split)).readAsBytesSync();
          return (
            data: bytes.buffer.asFloat32List(
              bytes.offsetInBytes,
              bytes.lengthInBytes ~/ 4,
            ),
            shape: part.substring(split + 1).split(',').map(int.parse).toList(),
          );
        }(),
    ];
    if (asset == 'assets/models/bsi_seg_yolo26s_640.onnx') {
      firstSegmentation ??= outputs;
    }
    return outputs;
  }

  Future<void> stop() async {
    await process.stdin.close();
    await process.exitCode.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await lines.cancel();
    scratch.deleteSync(recursive: true);
  }
}

/// Map independently annotated ORIGINAL-photo normalized points through the
/// actual final inference crop/letterbox. This also supports the ROI rescue path.
({int x, int y})? _maskPoint(
  List<dynamic> point,
  Map<String, dynamic> raw,
  img.Image mask,
) {
  final region = raw['inputRegion'] as Map<String, dynamic>;
  final lb = raw['letterbox'] as Map<String, dynamic>;
  final sx = (point[0] as num).toDouble() * (region['sourceW'] as num);
  final sy = (point[1] as num).toDouble() * (region['sourceH'] as num);
  if (sx < (region['x'] as num) ||
      sy < (region['y'] as num) ||
      sx >= (region['x'] as num) + (region['w'] as num) ||
      sy >= (region['y'] as num) + (region['h'] as num)) {
    return null;
  }
  final x =
      (((sx - (region['x'] as num)) * (lb['scale'] as num) +
                  (lb['padX'] as num)) *
              mask.width /
              (lb['size'] as num))
          .floor();
  final y =
      (((sy - (region['y'] as num)) * (lb['scale'] as num) +
                  (lb['padY'] as num)) *
              mask.height /
              (lb['size'] as num))
          .floor();
  if (x < 0 || y < 0 || x >= mask.width || y >= mask.height) return null;
  return (x: x, y: y);
}

void main() {
  test(
    'overlay never paints a separate soot detection outside target tree',
    () {
      const size = 8;
      final square = img.Image(width: size, height: size, numChannels: 3);
      img.fill(square, color: img.ColorRgb8(100, 100, 100));
      final tree = Uint8List(size * size);
      final soot = Uint8List(size * size);
      for (var y = 0; y < size; y++) {
        // Left tree is a soot prediction only; right is the chosen target.
        soot[y * size + 1] = 1;
        tree[y * size + 5] = 1;
        if (y >= 4) soot[y * size + 5] = 1;
      }
      final out = img.decodePng(
        ImageOps.renderOverlay(square, tree, soot, size),
      )!;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          final p = out.getPixel(x, y);
          if (tree[y * size + x] == 0) {
            expect(
              [p.r, p.g, p.b],
              [100, 100, 100],
              reason: 'Separate tree/background must remain unchanged at $x,$y',
            );
          } else if (soot[y * size + x] == 1) {
            expect(p.g, greaterThan(p.r), reason: 'Selected soot is green');
          } else {
            expect(p.r, greaterThan(p.g), reason: 'Selected clean stem is red');
          }
        }
      }
    },
  );
  final root = Platform.environment['BSI_FIELD_DIR'];
  final python = Platform.environment['BSI_ORT_PY'];
  final skip = root == null || python == null
      ? 'Requires private photos BSI_FIELD_DIR and ONNX Python BSI_ORT_PY'
      : null;
  final fixture =
      jsonDecode(
            File('test/fixtures/target_tree_field.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final server = _OrtServer();

  setUpAll(() async {
    if (skip != null) return;
    await server.start(python!);
    OnnxService.testBackend = server.run;
    await OnnxService.instance.load('assets/models/bsi_seg_yolo26s_640.onnx');
    await OnnxService.pole.load('assets/models/pole_boundary_640.onnx');
  });
  tearDownAll(() async {
    if (skip != null) return;
    OnnxService.testBackend = null;
    await server.stop();
  });

  for (final entry in fixture['cases'] as List<dynamic>) {
    final c = entry as Map<String, dynamic>;
    test(
      'real target/fork ${c['id']}',
      () async {
        final photo = File('$root/${c['photo']}');
        expect(
          photo.existsSync(),
          isTrue,
          reason: 'Original export photo required',
        );
        expect(
          photo.lengthSync(),
          c['bytes'],
          reason: 'Do not substitute a different photo',
        );
        final out = Directory(
          '${Platform.environment['BSI_TARGET_OUT'] ?? '.dart_tool/target_tree_field'}/${c['id']}',
        )..createSync(recursive: true);
        final az = (c['id'] as String).split('_').last;
        server.firstSegmentation = null;
        final callsBefore = Map<String, int>.from(server.calls);
        final stopwatch = Stopwatch()..start();
        final result = await AnalysisService.instance.analyzeFace(
          az,
          photo.path,
          poleLengthM: 3,
          rawOutDir: out.path,
          overlayOutPath: '${out.path}/overlay.png',
        );
        stopwatch.stop();
        File('${out.path}/execution.json').writeAsStringSync(
          jsonEncode({
            'elapsedMilliseconds': stopwatch.elapsedMilliseconds,
            'onnxCallsByAsset': {
              for (final asset in server.calls.keys)
                asset: server.calls[asset]! - (callsBefore[asset] ?? 0),
            },
            'provider': 'desktop ONNX Runtime CPU; not Android device latency',
          }),
        );
        expect(result.analysed, isTrue);
        final raw =
            jsonDecode(
                  File('${out.path}/${az}_analysis.json').readAsStringSync(),
                )
                as Map<String, dynamic>;
        final mask = img.decodePng(
          File('${out.path}/${az}_mask_tree.png').readAsBytesSync(),
        )!;
        if (c['id'] == '014_W') {
          // Independent original-model reference, using the captured FIRST
          // full-frame tensor before any extra ROI/companion inference.
          final original = server.firstSegmentation!;
          final det = original.firstWhere((o) => o.shape.length == 3);
          final proto = original.firstWhere((o) => o.shape.length == 4);
          final scale = raw['scale'] as Map<String, dynamic>;
          final points =
              (scale['poleModel'] as Map<String, dynamic>)['points']
                  as List<dynamic>;
          final poleX =
              points
                  .map((q) => (q['x'] as num).toDouble())
                  .reduce((a, b) => a + b) /
              points.length;
          final source = SegDecoder.analyze(
            det.data,
            det.shape,
            proto.data,
            proto.shape,
            640,
            poleHintX: poleX,
          );
          expect(source.hasTree, isTrue);
          final basalFrom =
              source.treeTop +
              ((source.treeBottom - source.treeTop + 1) * .80).floor();
          final sourcePng = img.Image(
            width: source.mw,
            height: source.mh,
            numChannels: 1,
          );
          for (var y = 0; y < source.mh; y++) {
            for (var x = 0; x < source.mw; x++) {
              sourcePng.setPixelR(
                x,
                y,
                source.treeMask[y * source.mw + x] * 255,
              );
            }
          }
          File(
            '${out.path}/original_primary_mask_tree.png',
          ).writeAsBytesSync(img.encodePng(sourcePng));
          for (var y = basalFrom; y < source.mh; y++) {
            for (var x = 0; x < source.mw; x++) {
              expect(
                mask.getPixel(x, y).r,
                source.treeMask[y * source.mw + x] * 255,
                reason:
                    '014_W rescue must preserve original basal geometry at $x,$y',
              );
            }
          }
        }
        final reports = <Map<String, dynamic>>[];
        for (final type in ['include', 'exclude']) {
          for (final p in c[type] as List<dynamic>) {
            final point = p as List<dynamic>;
            final pixel = _maskPoint(point, raw, mask);
            final selected =
                pixel != null && mask.getPixel(pixel.x, pixel.y).r > 127;
            reports.add({
              'kind': type,
              'originalNormalized': point,
              'maskPixel': pixel == null ? null : [pixel.x, pixel.y],
              'selected': selected,
              'pass': selected == (type == 'include'),
            });
          }
        }
        File('${out.path}/probe_report.json').writeAsStringSync(
          const JsonEncoder.withIndent(
            '  ',
          ).convert({'id': c['id'], 'probes': reports}),
        );
        // Write every probe before asserting, preserving all failures in the report.
        for (final r in reports) {
          expect(
            r['pass'],
            isTrue,
            reason:
                '${c['id']} ${r['kind']} ${r['originalNormalized']} (${c['reason']})',
          );
        }
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );

    test(
      'saved exclusions survive actual reanalysis ${c['id']}',
      () async {
        final include = c['include'] as List<dynamic>;
        final cut = include[c['id'] == '013_E' ? 0 : 2] as List<dynamic>;
        final anchor = include[c['id'] == '013_E' ? 2 : 0] as List<dynamic>;
        // All fixtures are upright 3:4 photos: full 640 letterbox has padX=80.
        double letterboxX(num originalX) => .125 + originalX * .75;
        final cx = letterboxX(cut[0] as num);
        final cy = (cut[1] as num).toDouble();
        final tuning = FaceTuning(
          targetX: letterboxX(anchor[0] as num),
          targetY: (anchor[1] as num).toDouble(),
          groundNorm: .9,
          excludedAreas: [
            [
              (x: cx - .025, y: cy - .025),
              (x: cx + .025, y: cy - .025),
              (x: cx + .025, y: cy + .025),
              (x: cx - .025, y: cy + .025),
            ],
          ],
        );
        final out = Directory(
          '${Platform.environment['BSI_TARGET_OUT'] ?? '.dart_tool/target_tree_field'}/${c['id']}/exclusion',
        )..createSync(recursive: true);
        final az = (c['id'] as String).split('_').last;
        final first = await AnalysisService.instance.analyzeFace(
          az,
          '$root/${c['photo']}',
          poleLengthM: 3,
          tuning: tuning,
          rawOutDir: '${out.path}/first',
        );
        expect(
          first.tuning.toJson(),
          tuning.toJson(),
          reason: 'AnalysisService must return the exact applied tuning',
        );
        final saved = AzimuthResult.fromJson(
          jsonDecode(jsonEncode(first.toJson())) as Map<String, dynamic>,
        );
        expect(saved.tuning.toJson(), tuning.toJson());
        final second = await AnalysisService.instance.analyzeFace(
          az,
          saved.imagePath!,
          poleLengthM: 3,
          tuning: saved.tuning,
          rawOutDir: '${out.path}/reloaded',
        );
        expect(second.tuning.toJson(), tuning.toJson());
        final firstPng = File(
          '${out.path}/first/${az}_mask_tree.png',
        ).readAsBytesSync();
        final secondPng = File(
          '${out.path}/reloaded/${az}_mask_tree.png',
        ).readAsBytesSync();
        expect(
          secondPng,
          orderedEquals(firstPng),
          reason: 'Persisted tuning must reproduce the identical selected mask',
        );
        final raw =
            jsonDecode(
                  File(
                    '${out.path}/reloaded/${az}_analysis.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final mask = img.decodePng(secondPng)!;
        final removed = _maskPoint(cut, raw, mask);
        expect(removed, isNotNull);
        expect(
          mask.getPixel(removed!.x, removed.y).r,
          0,
          reason: 'ROI/companion rescues must not add excluded pixels back',
        );
        final kept = _maskPoint(anchor, raw, mask);
        expect(kept, isNotNull);
        expect(
          mask.getPixel(kept!.x, kept.y).r,
          255,
          reason: 'Manual correction must retain the selected target anchor',
        );
        expect(raw['tuning'], tuning.toJson());
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  test(
    'actual 004_S measured DBH scaling has physically consistent metrics',
    () async {
      final c = (fixture['cases'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((c) => c['id'] == '004_S');
      final out = Directory(
        '${Platform.environment['BSI_TARGET_OUT'] ?? '.dart_tool/target_tree_field'}/004_S/dbh35',
      )..createSync(recursive: true);
      final result = await AnalysisService.instance.analyzeFace(
        'S',
        '$root/${c['photo']}',
        poleLengthM: 3,
        dbhCmForScale: 35,
        rawOutDir: out.path,
        overlayOutPath: '${out.path}/overlay.png',
      );
      final raw =
          jsonDecode(File('${out.path}/S_analysis.json').readAsStringSync())
              as Map<String, dynamic>;
      expect(
        result.dbhEstM.isNaN,
        isTrue,
        reason: 'A measured 35cm input must not become a circular DBH estimate',
      );
      final integrated = AnalysisService.instance.integrate([result], 35);
      expect(integrated.dbhCm, 35);
      final eligible =
          result.issue.isEmpty &&
          result.sootHeightM.isFinite &&
          result.sootProportion.isFinite;
      expect(integrated.facesUsed, eligible ? 1 : 0);
      if (eligible) {
        expect(
          integrated.bsi,
          closeTo(result.sootHeightM * result.sootProportion * 4, 1e-10),
        );
      } else {
        expect(integrated.bsi.isNaN, isTrue);
      }
      if (result.pxPerMetre.isFinite) {
        expect(result.scaleSource, 'dbh');
        expect(result.pxPerMetre, greaterThan(0));
        expect(
          result.visibleStemHeightM,
          greaterThanOrEqualTo(result.sootHeightM),
        );
        final seg = raw['seg'] as Map<String, dynamic>;
        final span = raw['dbhMeasurement'] as Map<String, dynamic>;
        final lb = raw['letterbox'] as Map<String, dynamic>;
        final unit = (lb['size'] as num) / (seg['mh'] as num);
        expect(
          result.pxPerMetre,
          closeTo((span['width'] as num) * unit / .35, 1e-10),
        );
        expect(
          result.sootHeightM,
          closeTo(
            ((seg['interBottom'] as num) - (seg['interTop'] as num)) *
                unit /
                result.pxPerMetre,
            1e-10,
          ),
        );
        final finalMask = img.decodePng(
          File('${out.path}/S_mask_tree.png').readAsBytesSync(),
        )!;
        final reference = img.decodePng(
          File('${out.path}/S_mask_stem_reference.png').readAsBytesSync(),
        )!;
        final row = span['row'] as int;
        final bottom =
            (raw['stemReference'] as Map<String, dynamic>)['treeBottom'] as int;
        expect(
          (bottom - row) * unit / result.pxPerMetre,
          closeTo(AnalysisService.breastHeightM, unit / result.pxPerMetre),
        );
        for (final mask in [reference, finalMask]) {
          var runs = 0;
          var previous = false;
          for (var x = 0; x < mask.width; x++) {
            final on = mask.getPixel(x, row).r > 127;
            if (on && !previous) runs++;
            previous = on;
          }
          expect(
            runs,
            1,
            reason: 'Physical breast-height cannot span two fork arms',
          );
        }
      } else {
        expect(result.scaleSource, isEmpty);
        expect(raw['dbhMeasurement'], isNull);
        expect(result.sootHeightM.isNaN, isTrue);
        expect(result.visibleStemHeightM.isNaN, isTrue);
      }
      File('${out.path}/integration.json').writeAsStringSync(
        jsonEncode({
          'measuredDbhCm': integrated.dbhCm,
          'facesUsed': integrated.facesUsed,
          'bsi': integrated.bsi.isFinite ? integrated.bsi : null,
        }),
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );

  for (final mode in ['exclude_all', 'target_far']) {
    test(
      'actual analysis warning path $mode',
      () async {
        final c = (fixture['cases'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((c) => c['id'] == '013_E');
        final tuning = mode == 'exclude_all'
            ? const FaceTuning(
                excludedAreas: [
                  [(x: 0, y: 0), (x: 1, y: 0), (x: 1, y: 1), (x: 0, y: 1)],
                ],
              )
            : const FaceTuning(targetX: .98, targetY: .20);
        final out = Directory(
          '${Platform.environment['BSI_TARGET_OUT'] ?? '.dart_tool/target_tree_field'}/warnings/$mode',
        )..createSync(recursive: true);
        final result = await AnalysisService.instance.analyzeFace(
          'E',
          '$root/${c['photo']}',
          poleLengthM: 3,
          tuning: tuning,
          rawOutDir: out.path,
          overlayOutPath: '${out.path}/overlay.png',
        );
        expect(
          result.issue,
          mode == 'exclude_all' ? 'tree_excluded' : 'target_not_found',
        );
        expect(result.treePx, 0);
        expect(result.sootPx, 0);
        expect(result.tuning.toJson(), tuning.toJson());
        final integrated = AnalysisService.instance.integrate([result], 35);
        expect(integrated.facesUsed, 0);
        expect(
          integrated.bsi.isNaN,
          isTrue,
          reason: 'An explicit failed target/exclusion must never enter BSI',
        );
      },
      skip: skip,
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

import 'dart:typed_data';

import 'package:bsi_field/src/services/analysis_service.dart';
import 'package:bsi_field/src/services/seg_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

const _w = 32;
typedef _Pixel = bool Function(int x, int y);

FaceAnalysis _decode(
  List<({int cls, _Pixel pixels})> instances, {
  double? x,
  double? y,
  double? pole,
}) {
  final nm = instances.length, stride = 6 + instances.length;
  final det = Float32List(instances.length * stride);
  final proto = Float32List(nm * _w * _w);
  for (var i = 0; i < instances.length; i++) {
    final k = i * stride;
    // Deliberately identical boxes: only actual masks distinguish the stems.
    det[k + 2] = det[k + 3] = _w.toDouble();
    det[k + 4] = 0.9;
    det[k + 5] = instances[i].cls.toDouble();
    det[k + 6 + i] = 20;
    for (var y = 0; y < _w; y++) {
      for (var x = 0; x < _w; x++) {
        if (instances[i].pixels(x, y)) proto[i * _w * _w + y * _w + x] = 1;
      }
    }
  }
  return SegDecoder.analyze(
    det,
    [1, instances.length, stride],
    proto,
    [1, nm, _w, _w],
    _w,
    targetHintX: x,
    targetHintY: y,
    hintIsTap: x != null,
    poleHintX: pole,
  );
}

bool _on(FaceAnalysis f, int x, int y) => f.treeMask[y * _w + x] == 1;
Uint8List _mask(_Pixel pixel) => Uint8List.fromList([
  for (var y = 0; y < _w; y++)
    for (var x = 0; x < _w; x++) pixel(x, y) ? 1 : 0,
]);

void main() {
  test('overlapping boxes use real tapped stem, not box centre or size', () {
    final f = _decode(
      [
        (cls: kTree, pixels: (x, y) => x >= 4 && x <= 9),
        (cls: kTree, pixels: (x, y) => x >= 21 && x <= 24),
      ],
      x: 23,
      y: 18,
      pole: 7,
    );
    expect(_on(f, 23, 18), isTrue);
    expect(_on(f, 7, 18), isFalse);
  });

  test('tapped small component wins over much larger remote component', () {
    final f = _decode(
      [(cls: kTree, pixels: (x, y) => (x >= 2 && x <= 3 && y > 18) || x >= 10)],
      x: 2,
      y: 24,
    );
    expect(_on(f, 2, 24), isTrue);
    expect(_on(f, 20, 24), isFalse);
  });

  test('missing tapped stem does not silently fall back to a neighbour', () {
    final f = _decode(
      [
        (cls: kTree, pixels: (x, y) => x >= 2 && x <= 5),
        (cls: kSoot, pixels: (x, y) => x >= 2 && x <= 5),
      ],
      x: 28,
      y: 18,
    );
    expect(f.hasTree, isFalse);
    expect(f.sootPx, 0);
    expect(f.bspBelow.isNaN, isTrue);
  });

  test('diagonal fork remains connected without filling its sky gap', () {
    final f = _decode(
      [
        (
          cls: kTree,
          pixels: (x, y) =>
              (y >= 16 && x >= 15 && x <= 18) ||
              (y < 16 && (x == y || x == 31 - y)),
        ),
      ],
      x: 16,
      y: 25,
    );
    expect(_on(f, 5, 5), isTrue);
    expect(_on(f, 26, 5), isTrue);
    expect(_on(f, 16, 5), isFalse);
  });

  test(
    'soot evidence outside selected stem is excluded from masks and counts',
    () {
      final f = _decode([
        (cls: kTree, pixels: (x, y) => x >= 14 && x <= 17),
        (cls: kSoot, pixels: (x, y) => x >= 5 && x <= 17 && y >= 8),
      ]);
      for (var k = 0; k < f.treeMask.length; k++) {
        expect(f.sootMask[k] <= f.treeMask[k], isTrue);
      }
      expect(f.sootPx, f.interPx);
      expect(f.bspWhole, 0.75);
    },
  );

  test(
    'tree rescue can reuse original soot evidence without painting neighbours',
    () {
      final soot = _decode([
        (cls: kTree, pixels: (x, y) => x >= 2 && x <= 5),
        (cls: kSoot, pixels: (x, y) => x >= 20 && x <= 23 && y >= 8),
      ]);
      final tree = _decode([
        (cls: kTree, pixels: (x, y) => x >= 20 && x <= 23),
      ]);
      final recovered = SegDecoder.recombine(tree, soot);
      expect(recovered.interPx, greaterThan(0));
      expect(recovered.bspWhole, 0.75);
      expect(recovered.sootMask[20 * _w + 4], 0);
    },
  );

  test(
    'explicit exclusion separates two stems joined by a bridge and recomputes BSP',
    () {
      final f = _decode(
        [
          (
            cls: kTree,
            pixels: (x, y) =>
                (x >= 8 && x <= 11) ||
                (x >= 20 && x <= 23) ||
                (y == 10 && x >= 8 && x <= 23),
          ),
          (cls: kSoot, pixels: (x, y) => x >= 20 && x <= 23),
        ],
        x: 9,
        y: 25,
      );
      final corrected = SegDecoder.applyExclusions(f, [
        [
          (x: 0.5, y: 0.0),
          (x: 1.0, y: 0.0),
          (x: 1.0, y: 1.0),
          (x: 0.5, y: 1.0),
        ],
      ]);
      expect(_on(corrected, 9, 25), isTrue);
      expect(_on(corrected, 22, 25), isFalse);
      expect(corrected.interPx, 0);
      expect(corrected.bspWhole, 0);
      expect(
        _on(f, 22, 25),
        isTrue,
        reason: 'Correction must not mutate raw input',
      );
    },
  );

  test('full exclusion is unmeasurable, not a valid zero percent result', () {
    final f = _decode([(cls: kTree, pixels: (x, y) => x >= 14 && x <= 17)]);
    final empty = SegDecoder.applyExclusions(f, [
      [(x: 0.0, y: 0.0), (x: 1.0, y: 0.0), (x: 1.0, y: 1.0), (x: 0.0, y: 1.0)],
    ]);
    expect(empty.hasTree, isFalse);
    expect(empty.bspWhole.isNaN, isTrue);
  });

  test(
    'a recovered branch must end in the parent stem, not merely cross it',
    () {
      final f = _decode([(cls: kTree, pixels: (x, y) => x >= 15 && x <= 19)]);
      final branch = _mask(
        (x, y) =>
            y <= 20 &&
            ((y < 16 && x >= 8 + y ~/ 3 && x <= 11 + y ~/ 3) ||
                (y >= 16 && x >= 15 && x <= 18)),
      );
      final merged = SegDecoder.mergeBranchEvidence(
        f,
        branch,
        Uint8List(_w * _w),
      );
      expect(merged.treePx, greaterThan(f.treePx));
      expect(_on(merged, 9, 5), isTrue);
      expect(_on(merged, 13, 5), isFalse);
      final crossing = _mask(
        (x, y) => (x >= 8 && x <= 11) || (y == 10 && x <= 19 && x >= 8),
      );
      expect(
        identical(SegDecoder.mergeBranchEvidence(f, crossing, crossing), f),
        isTrue,
      );
    },
  );

  test(
    'a known independent tree cannot be merged through an upper crossing',
    () {
      final f = _decode(
        [
          (cls: kTree, pixels: (x, y) => x >= 15 && x <= 19),
          (cls: kTree, pixels: (x, y) => x >= 8 && x <= 11),
        ],
        x: 17,
        y: 25,
      );
      final neighbour = _mask(
        (x, y) =>
            (y < 16 && x >= 8 && x <= 11) ||
            (y >= 16 && y <= 20 && x >= 15 && x <= 18),
      );
      expect(
        identical(SegDecoder.mergeBranchEvidence(f, neighbour, neighbour), f),
        isTrue,
      );
    },
  );

  test('fork gap is never counted as breast-height width or scale', () {
    final f = _decode([
      (
        cls: kTree,
        pixels: (x, y) =>
            (y >= 24 && x >= 10 && x <= 22) ||
            (y < 24 && ((x >= 10 && x <= 13) || (x >= 19 && x <= 22))),
      ),
    ]);
    expect(f.treeSpanAtRow(10), isNull);
    expect(f.treeSpanAtHeight(20), isNull);
    expect(AnalysisService.scaleFromDbhCm(f, 1, 35), isNull);
    expect(f.treeSpanAtHeight(100), isNull);
    expect(f.treeSpanAtHeight(-1), isNull);
  });

  test('ground remains authoritative after branch evidence and exclusions', () {
    final f = _decode([(cls: kTree, pixels: (x, y) => x >= 14 && x <= 17)]);
    final clipped = SegDecoder.clipGround(f, 0.5);
    expect(clipped.treeBottom, 16);
    expect(_on(clipped, 15, 25), isFalse);
  });

  test(
    'companion repairs upper forks while its extra roots and ground stay excluded',
    () {
      final f = _decode([(cls: kTree, pixels: (x, y) => x >= 14 && x <= 21)]);
      final candidate = _mask(
        (x, y) =>
            (x >= 14 && x <= 21) ||
            (y <= 10 && x >= 8 && x <= 10) ||
            (y == 10 && x >= 8 && x <= 14) ||
            y >= 30,
      );
      final merged = SegDecoder.mergeCompanionTree(f, candidate);
      expect(_on(merged, 9, 5), isTrue);
      expect(_on(merged, 12, 5), isFalse);
      expect(_on(merged, 2, 31), isFalse);
      expect(merged.treeBottom, f.treeBottom);
      expect(merged.treeSpanAtRow(30), f.treeSpanAtRow(30));
      expect(
        f.treePx,
        8 * _w,
        reason: 'Original evidence must not be modified',
      );
    },
  );

  test(
    'companion cannot add a separate basal stem joined by an upper crossing',
    () {
      final f = _decode([(cls: kTree, pixels: (x, y) => x >= 14 && x <= 21)]);
      final crossing = _mask(
        (x, y) =>
            (x >= 14 && x <= 21) ||
            (x >= 7 && x <= 9) ||
            (y == 10 && x >= 7 && x <= 21),
      );
      expect(identical(SegDecoder.mergeCompanionTree(f, crossing), f), isTrue);
    },
  );

  test(
    'companion cannot exchange the original stem for a partial overlapping tree',
    () {
      final f = _decode([(cls: kTree, pixels: (x, y) => x >= 14 && x <= 21)]);
      final cropped = _mask((x, y) => y < 24 && x >= 12 && x <= 21);
      expect(identical(SegDecoder.mergeCompanionTree(f, cropped), f), isTrue);
    },
  );

  test(
    'uncropped prototype responses never become companion foreground evidence',
    () {
      final det = Float32List.fromList([8, 0, 12, 31, .9, 1, 20]);
      final proto = Float32List.fromList(List.filled(_w * _w, 1));
      final evidence = SegDecoder.branchEvidence(
        det,
        [1, 1, 7],
        proto,
        [1, 1, _w, _w],
        _w,
      ).single;
      expect(_on(evidence.analysis, 10, 16), isTrue);
      expect(_on(evidence.analysis, 18, 16), isFalse);
      final f = _decode([(cls: kTree, pixels: (x, y) => x >= 14 && x <= 21)]);
      expect(
        identical(
          SegDecoder.mergeCompanionTree(f, evidence.analysis.treeMask),
          f,
        ),
        isTrue,
      );
    },
  );

  test(
    'ROI and companion preserve negative space between existing fork arms',
    () {
      final f = _decode([
        (
          cls: kTree,
          pixels: (x, y) =>
              x >= 10 && x <= 21 && (y >= 13 || x <= 13 || x >= 18),
        ),
      ]);
      final filled = _mask(
        (x, y) => (x >= 10 && x <= 21) || (y <= 12 && x >= 8 && x <= 9),
      );
      final roi = SegDecoder.mergeBranchEvidence(f, filled, filled);
      final companion = SegDecoder.mergeCompanionTree(f, filled);
      for (final result in [roi, companion]) {
        expect(
          _on(result, 15, 5),
          isFalse,
          reason: 'The sky gap must stay empty',
        );
        expect(
          _on(result, 8, 5),
          isTrue,
          reason: 'A missing outer arm can still extend',
        );
        expect(result.sootMask[5 * _w + 15], 0);
      }
    },
  );

  test(
    'gap protection cannot leave a floating new fragment above the tree',
    () {
      final f = _decode([
        (
          cls: kTree,
          pixels: (x, y) =>
              y >= 6 &&
              ((y >= 16 && x >= 10 && x <= 19) ||
                  (y < 16 && ((x >= 10 && x <= 12) || (x >= 17 && x <= 19)))),
        ),
      ]);
      final bridge = _mask(
        (x, y) => _on(f, x, y) || (x >= 14 && x <= 15 && y <= 16),
      );
      for (final result in [
        SegDecoder.mergeBranchEvidence(f, bridge, bridge),
        SegDecoder.mergeCompanionTree(f, bridge),
      ]) {
        expect(_on(result, 14, 1), isFalse);
        expect(result.treeTop, f.treeTop);
        expect(result.treeMask, f.treeMask);
      }
    },
  );

  test('expanded upper masks do not become a new DBH calibration ruler', () {
    final reference = _decode([
      (cls: kTree, pixels: (x, y) => x >= 14 && x <= 21),
    ]);
    final wider = _mask(
      (x, y) => _on(reference, x, y) || (y <= 16 && x >= 8 && x <= 13),
    );
    final recovered = SegDecoder.mergeCompanionTree(reference, wider);
    expect(recovered.treePx, greaterThan(reference.treePx));
    final originalScale = AnalysisService.scaleFromDbhCm(reference, 1, 35);
    expect(
      AnalysisService.scaleFromDbhCm(
        reference,
        1,
        35,
        recoveredShape: recovered,
      ),
      originalScale,
    );
    final fork = _mask(
      (x, y) =>
          _on(reference, x, y) ||
          (y <= 16 && x >= 8 && x <= 10) ||
          (y == 16 && x >= 8 && x <= 14),
    );
    final split = SegDecoder.mergeCompanionTree(reference, fork);
    expect(
      AnalysisService.scaleFromDbhCm(reference, 1, 35, recoveredShape: split),
      isNull,
      reason: 'A split physical breast-height row is ambiguous',
    );
  });
}

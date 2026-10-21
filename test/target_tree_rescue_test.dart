import 'dart:typed_data';

import 'package:bsi_field/src/services/image_ops.dart';
import 'package:bsi_field/src/services/seg_decoder.dart';
import 'package:bsi_field/src/services/target_tree_rescue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Letterboxed _view(
  int width,
  int height, {
  TreeRescueRegion? region,
  int size = 600,
}) {
  final source = img.Image(width: width, height: height, numChannels: 3);
  final area = region ?? (x: 0, y: 0, width: width, height: height);
  final cropped = img.copyCrop(
    source,
    x: area.x,
    y: area.y,
    width: area.width,
    height: area.height,
  );
  final lb = ImageOps.letterbox(cropped, size, autoTone: false);
  return Letterboxed(
    lb.square,
    lb.chw,
    lb.scale,
    lb.padX,
    lb.padY,
    size,
    source: source,
    srcX: area.x,
    srcY: area.y,
    srcW: area.width,
    srcH: area.height,
  );
}

FaceAnalysis _tree({
  int x1 = 55,
  int x2 = 94,
  int y1 = 10,
  int y2 = 139,
  bool empty = false,
}) {
  const grid = 150;
  final mask = Uint8List(grid * grid);
  if (!empty) {
    for (var y = y1; y <= y2; y++) {
      for (var x = x1; x <= x2; x++) {
        mask[y * grid + x] = 1;
      }
    }
  }
  return FaceAnalysis(
    sootMask: Uint8List(grid * grid),
    treeMask: mask,
    mh: grid,
    mw: grid,
    size: 600,
    bspWhole: 0,
    bspBelow: 0,
    sootPx: 0,
    treePx: empty ? 0 : (x2 - x1 + 1) * (y2 - y1 + 1),
    interPx: 0,
    nTree: empty ? 0 : 1,
    nSoot: 0,
    interTop: -1,
    interBottom: -1,
    interLeft: -1,
    interRight: -1,
    treeTop: empty ? -1 : y1,
    treeBottom: empty ? -1 : y2,
  );
}

void _expectRectangle(
  Uint8List mask,
  int width,
  int height, {
  required int x1,
  required int x2,
  required int y1,
  required int y2,
}) {
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      expect(
        mask[y * width + x],
        x >= x1 && x < x2 && y >= y1 && y < y2 ? 1 : 0,
        reason: 'Original-grid cell $x,$y must respect crop boundary',
      );
    }
  }
}

void main() {
  group('rescue source geometry', () {
    test('portrait crop mask returns to original frame, excluding padding', () {
      final full = _view(800, 1200);
      const region = (x: 200, y: 240, width: 240, height: 400);
      final crop = _view(800, 1200, region: region);
      final restored = TargetTreeRescue.restoreMask(
        Uint8List(150 * 150)..fillRange(0, 150 * 150, 1),
        150,
        150,
        crop,
        region,
        full,
        150,
        150,
      );
      // full letterbox: scale=.5, padX=100. Each output cell is 8 source px.
      _expectRectangle(restored, 150, 150, x1: 50, x2: 80, y1: 30, y2: 80);
    });

    test('landscape with vertical padding returns to original frame', () {
      final full = _view(1200, 800);
      const region = (x: 240, y: 200, width: 400, height: 240);
      final crop = _view(1200, 800, region: region);
      final restored = TargetTreeRescue.restoreMask(
        Uint8List(150 * 150)..fillRange(0, 150 * 150, 1),
        150,
        150,
        crop,
        region,
        full,
        150,
        150,
      );
      _expectRectangle(restored, 150, 150, x1: 30, x2: 80, y1: 50, y2: 80);
    });

    test('already-cropped full view keeps global source offset', () {
      final full = _view(
        1600,
        1200,
        region: (x: 400, y: 200, width: 800, height: 800),
        size: 400,
      );
      const region = (x: 560, y: 440, width: 320, height: 240);
      final crop = _view(1600, 1200, region: region, size: 400);
      final restored = TargetTreeRescue.restoreMask(
        Uint8List(100 * 100)..fillRange(0, 100 * 100, 1),
        100,
        100,
        crop,
        region,
        full,
        100,
        100,
      );
      // full-grid origin=(400,200), spacing=8 source px.
      _expectRectangle(restored, 100, 100, x1: 20, x2: 60, y1: 30, y2: 60);
    });

    test('crop mask padding and empty pixels never become source tree', () {
      final full = _view(800, 1200);
      const region = (x: 200, y: 240, width: 240, height: 400);
      final crop = _view(800, 1200, region: region);
      final mask = Uint8List(150 * 150);
      // Crop has padX=120 -> columns [0,30) are padding only.
      for (var y = 0; y < 150; y++) {
        for (var x = 0; x < 30; x++) {
          mask[y * 150 + x] = 1;
        }
      }
      final restored = TargetTreeRescue.restoreMask(
        mask,
        150,
        150,
        crop,
        region,
        full,
        150,
        150,
      );
      expect(restored.where((v) => v != 0), isEmpty);
    });

    test('non-square mask grids preserve source-space rectangle', () {
      final full = _view(1200, 800);
      const region = (x: 240, y: 200, width: 400, height: 240);
      final crop = _view(1200, 800, region: region);
      final restored = TargetTreeRescue.restoreMask(
        Uint8List(75 * 150)..fillRange(0, 75 * 150, 1),
        75,
        150,
        crop,
        region,
        full,
        75,
        150,
      );
      _expectRectangle(restored, 150, 75, x1: 30, x2: 80, y1: 25, y2: 40);
    });
  });

  group('bounded rescue regions', () {
    test('empty, short or thin stems do not trigger extra inference', () {
      final full = _view(800, 1200);
      expect(TargetTreeRescue.regions(_tree(empty: true), full), isEmpty);
      expect(TargetTreeRescue.regions(_tree(y1: 90, y2: 120), full), isEmpty);
      expect(TargetTreeRescue.regions(_tree(x1: 70, x2: 72), full), isEmpty);
    });

    test('large central stem requests one bounded upper source-image crop', () {
      final full = _view(800, 1200);
      final regions = TargetTreeRescue.regions(_tree(), full);
      expect(regions, hasLength(1));
      for (final r in regions) {
        expect(r.x, greaterThanOrEqualTo(0));
        expect(r.y, greaterThanOrEqualTo(0));
        expect(r.width, greaterThanOrEqualTo(16));
        expect(r.height, greaterThanOrEqualTo(32));
        expect(r.x + r.width, lessThanOrEqualTo(800));
        expect(r.y + r.height, lessThanOrEqualTo(1200));
      }
    });

    test('left/right edge stems clip crops safely to source bounds', () {
      final full = _view(800, 1200);
      for (final tree in [_tree(x1: 25, x2: 55), _tree(x1: 95, x2: 124)]) {
        final regions = TargetTreeRescue.regions(tree, full);
        expect(regions.length, lessThanOrEqualTo(1));
        for (final r in regions) {
          expect(r.x, greaterThanOrEqualTo(0));
          expect(r.y, greaterThanOrEqualTo(0));
          expect(r.x + r.width, lessThanOrEqualTo(800));
          expect(r.y + r.height, lessThanOrEqualTo(1200));
        }
      }
    });

    test('regions on an existing crop use original-source coordinates', () {
      final full = _view(
        1600,
        1200,
        region: (x: 400, y: 200, width: 800, height: 800),
      );
      final regions = TargetTreeRescue.regions(_tree(), full);
      expect(regions, hasLength(1));
      // The stem top is row10*4=40 in the 600px input; .75 source scale,
      // then the full-view global y offset 200 gives 253 source pixels.
      for (final r in regions) {
        expect(r.y, 253);
        expect(r.x, greaterThan(400));
      }
    });
  });
}

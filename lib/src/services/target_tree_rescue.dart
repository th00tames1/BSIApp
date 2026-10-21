import 'dart:math' as math;
import 'dart:typed_data';

import 'image_ops.dart';
import 'seg_decoder.dart';

typedef TreeRescueRegion = ({int x, int y, int width, int height});

/// One bounded view of the upper stem. Regions depend only on the
/// selected mask geometry, never a photo ID or field-case annotation.
class TargetTreeRescue {
  static const modelAsset = 'assets/models/bsi_tree_rescue_yolo11n_640.onnx';
  static List<TreeRescueRegion> regions(FaceAnalysis tree, Letterboxed full) {
    if (!tree.hasTree) return const [];
    var minX = tree.mw, maxX = -1;
    for (var k = 0; k < tree.treeMask.length; k++) {
      if (tree.treeMask[k] == 1) {
        minX = math.min(minX, k % tree.mw);
        maxX = math.max(maxX, k % tree.mw);
      }
    }
    final unit = full.size / tree.mw;
    final left = minX * unit, right = (maxX + 1) * unit;
    final top = tree.treeTop * unit;
    final h = (tree.treeBottom - tree.treeTop + 1) * unit;
    final w = right - left;
    if (h < full.size * 0.35 || w < full.size * 0.035) return const [];
    final result = <TreeRescueRegion>[];
    for (final view in [(x: left, width: w * 1.1, height: h * 0.5)]) {
      final x = view.x;
      final sx = full.toSourceX(x).round().clamp(0, full.source.width - 1);
      final sy = full.toSourceY(top).round().clamp(0, full.source.height - 1);
      final ex = full
          .toSourceX(x + view.width)
          .round()
          .clamp(sx + 1, full.source.width);
      final ey = full
          .toSourceY(top + view.height)
          .round()
          .clamp(sy + 1, full.source.height);
      if (ex - sx < 16 || ey - sy < 32) continue;
      result.add((x: sx, y: sy, width: ex - sx, height: ey - sy));
    }
    return result;
  }

  /// Pull a crop mask back onto the original grid using pixel centres. The
  /// original image, pole solution, manual target/ground coordinates and scale
  /// never change as a side effect of this extra inference.
  static Uint8List restoreMask(
    Uint8List mask,
    int mh,
    int mw,
    Letterboxed crop,
    TreeRescueRegion region,
    Letterboxed full,
    int targetHeight,
    int targetWidth,
  ) {
    final restored = Uint8List(targetHeight * targetWidth);
    for (var y = 0; y < targetHeight; y++) {
      final sy = full.toSourceY((y + 0.5) * full.size / targetHeight);
      if (sy < region.y || sy >= region.y + region.height) continue;
      final cy = (((sy - region.y) * crop.scale + crop.padY) * mh / crop.size)
          .floor();
      if (cy < 0 || cy >= mh) continue;
      for (var x = 0; x < targetWidth; x++) {
        final sx = full.toSourceX((x + 0.5) * full.size / targetWidth);
        if (sx < region.x || sx >= region.x + region.width) continue;
        final cx = (((sx - region.x) * crop.scale + crop.padX) * mw / crop.size)
            .floor();
        if (cx >= 0 && cx < mw && mask[cy * mw + cx] == 1) {
          restored[y * targetWidth + x] = 1;
        }
      }
    }
    return restored;
  }
}

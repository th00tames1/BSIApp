import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int kSoot = 0;
const int kTree = 1;

class _Det {
  final int cls;
  final double score;
  final double x1, y1, x2, y2; // in input (size×size) pixels
  final List<double> coeffs;
  _Det(this.cls, this.score, this.x1, this.y1, this.x2, this.y2, this.coeffs);
}

class _TreeCandidate {
  final _Det detection;
  final Uint8List mask;
  _TreeCandidate(this.detection, this.mask);
}

class TreeBranchEvidence {
  final FaceAnalysis analysis;

  final double confidence;
  TreeBranchEvidence(this.analysis, this.confidence);
}

/// Decoded per-face analysis. Masks and row/col extents are in the PROTO grid
/// (mh×mw); callers scale to the size×size space with (size/mh).
class FaceAnalysis {
  final Uint8List sootMask; // mh*mw, target-tree ∩ soot union restricted later
  final Uint8List treeMask; // mh*mw, target tree
  // Keep the original soot evidence for a later tree-only rescue/recombine.
  // Public masks and all reported soot areas are restricted to the selected tree.
  final Uint8List? sourceSootMask;
  final Uint8List? otherTreeMask;
  final int mh, mw, size;
  final double bspWhole; // soot∩tree / tree
  final double bspBelow; // soot∩tree / tree below max soot height
  final int sootPx, treePx, interPx, nTree, nSoot;
  final int interTop,
      interBottom,
      interLeft,
      interRight; // proto rows/cols, -1 if none
  final int treeTop, treeBottom;
  const FaceAnalysis({
    required this.sootMask,
    required this.treeMask,
    this.sourceSootMask,
    this.otherTreeMask,
    required this.mh,
    required this.mw,
    required this.size,
    required this.bspWhole,
    required this.bspBelow,
    required this.sootPx,
    required this.treePx,
    required this.interPx,
    required this.nTree,
    required this.nSoot,
    required this.interTop,
    required this.interBottom,
    required this.interLeft,
    required this.interRight,
    required this.treeTop,
    required this.treeBottom,
  });

  bool get hasTree => treePx > 0;

  /// Median tree-mask width (in proto columns) over the lower third of the tree,
  /// used to estimate DBH near breast height.
  int treeWidthLowerCols() {
    if (treeBottom < 0) return 0;
    final from = treeTop + ((treeBottom - treeTop) * 2 ~/ 3);
    final widths = <int>[];
    for (int y = from; y <= treeBottom; y++) {
      final span = treeSpanAtRow(y);
      if (span != null) widths.add(span.hi - span.lo + 1);
    }
    if (widths.isEmpty) return 0;
    widths.sort();
    return widths[widths.length ~/ 2];
  }

  /// 한 행에서 수간 마스크의 좌·우 끝(proto 열). 마스크가 없으면 null.
  ({int lo, int hi})? treeSpanAtRow(int y) {
    if (y < 0 || y >= mh) return null;
    int lo = -1, hi = -1;
    var ended = false;
    final base = y * mw;
    for (int x = 0; x < mw; x++) {
      if (treeMask[base + x] == 1) {
        // A fork at breast height has no single trunk width. Never count the
        // background gap between its arms as DBH or a scale reference.
        if (ended) return null;
        if (lo < 0) lo = x;
        hi = x;
      } else if (lo >= 0) {
        ended = true;
      }
    }
    return lo < 0 ? null : (lo: lo, hi: hi);
  }

  /// 밑둥에서 [rowsUp]만큼 위(= 가슴높이)에서 잰 수간 폭. 잡음을 줄이려고
  /// 그 행 앞뒤 [band]행의 중앙값을 쓴다. 흉고직경 추정의 근거 위치도 함께 돌려준다.
  ({int width, int row, int lo, int hi})? treeSpanAtHeight(
    int rowsUp, {
    int band = 2,
  }) {
    if (treeBottom < 0) return null;
    final target = treeBottom - rowsUp;
    if (rowsUp < 0 || target < treeTop || target > treeBottom) return null;
    if (treeSpanAtRow(target) == null) return null;
    final rows = <({int w, int lo, int hi})>[];
    for (int y = target - band; y <= target + band; y++) {
      final s = treeSpanAtRow(y);
      if (s != null) rows.add((w: s.hi - s.lo + 1, lo: s.lo, hi: s.hi));
    }
    if (rows.isEmpty) return null;
    rows.sort((a, b) => a.w.compareTo(b.w));
    final m = rows[rows.length ~/ 2];
    return (width: m.w, row: target, lo: m.lo, hi: m.hi);
  }
}

class SegDecoder {
  static double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  static List<TreeBranchEvidence> branchEvidence(
    Float32List det,
    List<int> detShape,
    Float32List proto,
    List<int> protoShape,
    int size,
  ) {
    final nm = protoShape[1], mh = protoShape[2], mw = protoShape[3];
    final decoded = _detections(det, detShape, nm, 0.25, 0.10, 0.45);
    final soot = Uint8List(mh * mw);
    for (final d in decoded.soot) {
      _fillMask(d, soot, proto, nm, mh, mw, mw / size);
    }
    final result = <TreeBranchEvidence>[];
    for (final d in decoded.tree) {
      final mask = Uint8List(mh * mw);
      _fillMask(d, mask, proto, nm, mh, mw, mw / size);
      _keepMainComponent(mask, mh, mw);
      final seed = mask.indexOf(1);
      if (seed < 0) continue;
      result.add(
        TreeBranchEvidence(
          _measure(
            soot,
            mask,
            mh,
            mw,
            size,
            decoded.tree.length,
            decoded.soot.length,
          ),
          d.score,
        ),
      );
    }
    return result;
  }

  static ({List<_Det> tree, List<_Det> soot}) _detections(
    Float32List det,
    List<int> detShape,
    int nm,
    double confTree,
    double confSoot,
    double iou,
  ) {
    final dim1 = detShape[1], dim2 = detShape[2];
    List<_Det> soot = [], tree = [];

    if (dim2 == nm + 6) {
      // YOLO26 / end-to-end: [1, nDet, 6+nm], already NMS'd.
      final feat = dim2;
      for (int i = 0; i < dim1; i++) {
        final b = i * feat;
        final conf = det[b + 4];
        final cls = det[b + 5].round();
        final thr = cls == kTree ? confTree : (cls == kSoot ? confSoot : 1.0);
        if ((cls != kTree && cls != kSoot) || conf < thr) continue;
        final c = List<double>.generate(nm, (j) => det[b + 6 + j]);
        final d = _Det(
          cls,
          conf,
          det[b],
          det[b + 1],
          det[b + 2],
          det[b + 3],
          c,
        );
        (cls == kSoot ? soot : tree).add(d);
      }
    } else {
      // YOLO11 / dense: [1, 4+nc+nm, anchors], channel-major det[ch*n+anchor].
      final nc = dim1 - 4 - nm;
      final n = dim2;
      final raw = <_Det>[];
      if (nc >= 1 && nc <= 100) {
        for (int i = 0; i < n; i++) {
          int best = 0;
          double bestScore = -1;
          for (int k = 0; k < nc; k++) {
            final s = det[(4 + k) * n + i];
            if (s > bestScore) {
              bestScore = s;
              best = k;
            }
          }
          final thr = best == kTree
              ? confTree
              : (best == kSoot ? confSoot : 1.0);
          if (bestScore < thr) continue;
          final cx = det[i],
              cy = det[n + i],
              w = det[2 * n + i],
              h = det[3 * n + i];
          final c = List<double>.generate(nm, (j) => det[(4 + nc + j) * n + i]);
          raw.add(
            _Det(
              best,
              bestScore,
              cx - w / 2,
              cy - h / 2,
              cx + w / 2,
              cy + h / 2,
              c,
            ),
          );
        }
      }
      soot = _nms(raw.where((d) => d.cls == kSoot).toList(), iou);
      tree = _nms(raw.where((d) => d.cls == kTree).toList(), iou);
    }

    return (tree: tree, soot: soot);
  }

  static FaceAnalysis analyze(
    Float32List det,
    List<int> detShape,
    Float32List proto,
    List<int> protoShape,
    int size, {
    // 그을음 임계값이 0.25면 멀리서 찍은 나무가 절벽에 걸린다. 현장 사례
    // (같은 나무를 거리만 달리해 찍은 005 동/북)에서 먼 쪽 검출 점수가
    // 0.279·0.240이었고, 기기별 수치 차이로 0.25 아래로 내려가면 그을음이
    // 통째로 사라졌다("그을음이 덮여 있는데 없다고 나옴"). 0.15로 낮추면
    // 검증용 예시 4장과 현장 사진의 계측값은 **완전히 그대로**이면서
    // 그 절벽만 없어진다(0.10까지 내리면 예시 S면이 흔들려 여기가 하한).
    double confSoot = 0.10,
    double confTree = 0.10,
    double iou = 0.45,
    double? targetHintX,
    double? targetHintY,
    bool hintIsTap = false,
    double? poleHintX,
    double? groundNorm,
  }) {
    final nm = protoShape[1], mh = protoShape[2], mw = protoShape[3];
    final mhmw = mh * mw;
    final detections = _detections(det, detShape, nm, confTree, confSoot, iou);
    final tree = detections.tree, soot = detections.soot;

    final factor = mw / size; // input px -> proto grid
    final sootMask = Uint8List(mhmw);
    for (final d in soot) {
      _fillMask(d, sootMask, proto, nm, mh, mw, factor);
    }
    final candidates = <_TreeCandidate>[];
    for (final d in tree) {
      final mask = Uint8List(mhmw);
      _fillMask(d, mask, proto, nm, mh, mw, factor);
      if (mask.contains(1)) candidates.add(_TreeCandidate(d, mask));
    }
    final target = _pickTarget(
      candidates,
      size,
      mh,
      mw,
      hintX: targetHintX,
      hintY: targetHintY,
      hintIsTap: hintIsTap,
      poleHintX: poleHintX,
    );
    final treeMask = Uint8List(mhmw);
    if (target != null) {
      treeMask.setAll(0, target.mask);
      _keepMainComponent(
        treeMask,
        mh,
        mw,
        hintX: hintIsTap && targetHintX != null
            ? targetHintX * mw / size
            : null,
        hintY: hintIsTap && targetHintY != null
            ? targetHintY * mh / size
            : null,
      );
    }
    final otherTrees = Uint8List(mhmw);
    for (final candidate in candidates) {
      if (identical(candidate, target)) continue;
      for (var k = 0; k < mhmw; k++) {
        if (candidate.mask[k] == 1 && treeMask[k] == 0) otherTrees[k] = 1;
      }
    }
    // 지표면을 조사자가 지정했으면 그 아래(풀·그림자·낙엽에 붙은 마스크)는
    // 줄기로 세지 않는다. 밑동이 곧 높이 계측의 기준선이라 여기서 잘라야
    // 그을음 높이·줄기 높이·흉고 위치가 모두 같은 기준을 쓴다.
    if (groundNorm != null) {
      final gRow = (groundNorm * mh).round().clamp(0, mh - 1);
      for (int y = gRow + 1; y < mh; y++) {
        final base = y * mw;
        for (int x = 0; x < mw; x++) {
          treeMask[base + x] = 0;
          sootMask[base + x] = 0;
        }
      }
    }

    return _measure(
      sootMask,
      treeMask,
      mh,
      mw,
      size,
      tree.length,
      soot.length,
      otherTreeMask: otherTrees,
    );
  }

  /// 보정한 사진에서 찾은 **줄기**와 원본에서 잰 **그을음**을 합친다.
  ///
  /// 줄기가 온통 그을려 'tree'로 안 잡히는 사진은 대비를 펴 주면 잘 잡힌다
  /// (현장 007 동: 0.19 → 0.91). 그런데 같은 보정이 그을음 마스크는 줄인다
  /// (측정: 비율 0.877 → 0.602). 그래서 보정본에서는 **분모만 빌려 오고**
  /// 그을음은 원본에서 잰 것을 쓴다(혼합 0.861 — 원본 기준과 거의 같다).
  ///
  /// 두 분석은 같은 모델·같은 입력 크기라 마스크 격자가 일치한다.
  static FaceAnalysis recombine(FaceAnalysis treeFrom, FaceAnalysis sootFrom) {
    if (treeFrom.mh != sootFrom.mh ||
        treeFrom.mw != sootFrom.mw ||
        treeFrom.size != sootFrom.size) {
      return treeFrom;
    }
    return _measure(
      sootFrom.sourceSootMask ?? sootFrom.sootMask,
      treeFrom.treeMask,
      treeFrom.mh,
      treeFrom.mw,
      treeFrom.size,
      treeFrom.nTree,
      sootFrom.nSoot,
      otherTreeMask: treeFrom.otherTreeMask,
    );
  }

  /// 두 마스크에서 계측값을 낸다.
  static FaceAnalysis _measure(
    Uint8List sootMask,
    Uint8List treeMask,
    int mh,
    int mw,
    int size,
    int nTree,
    int nSoot, {
    Uint8List? otherTreeMask,
  }) {
    int sootPx = 0, treePx = 0, interPx = 0;
    final selectedSoot = Uint8List(sootMask.length);
    int iTop = -1, iBot = -1, iLeft = mw, iRight = -1, tTop = -1, tBot = -1;
    for (int y = 0; y < mh; y++) {
      final base = y * mw;
      for (int x = 0; x < mw; x++) {
        final idx = base + x;
        final s = sootMask[idx], t = treeMask[idx];
        if (s == 1 && t == 1) {
          sootPx++;
          selectedSoot[idx] = 1;
        }
        if (t == 1) {
          treePx++;
          if (tTop < 0) tTop = y;
          tBot = y;
        }
        if (s == 1 && t == 1) {
          interPx++;
          if (iTop < 0) iTop = y;
          iBot = y;
          if (x < iLeft) iLeft = x;
          if (x > iRight) iRight = x;
        }
      }
    }
    int treeBelow = 0;
    if (interPx > 0) {
      for (int y = iTop; y <= tBot; y++) {
        final base = y * mw;
        for (int x = 0; x < mw; x++) {
          if (treeMask[base + x] == 1) treeBelow++;
        }
      }
    }
    if (iRight < 0) iLeft = -1;

    return FaceAnalysis(
      sootMask: selectedSoot,
      sourceSootMask: sootMask,
      otherTreeMask: otherTreeMask,
      treeMask: treeMask,
      mh: mh,
      mw: mw,
      size: size,
      bspWhole: treePx > 0 ? interPx / treePx : double.nan,
      bspBelow: treeBelow > 0 ? interPx / treeBelow : double.nan,
      sootPx: sootPx,
      treePx: treePx,
      interPx: interPx,
      nTree: nTree,
      nSoot: nSoot,
      interTop: iTop,
      interBottom: iBot,
      interLeft: iLeft,
      interRight: iRight,
      treeTop: tTop,
      treeBottom: tBot,
    );
  }

  static void _fillMask(
    _Det d,
    Uint8List mask,
    Float32List proto,
    int nm,
    int mh,
    int mw,
    double factor,
  ) {
    final mhmw = mh * mw;
    final bx1 = (d.x1 * factor).toInt().clamp(0, mw - 1);
    final bx2 = (d.x2 * factor).toInt().clamp(0, mw - 1);
    final by1 = (d.y1 * factor).toInt().clamp(0, mh - 1);
    final by2 = (d.y2 * factor).toInt().clamp(0, mh - 1);
    for (int y = by1; y <= by2; y++) {
      final rowBase = y * mw;
      for (int x = bx1; x <= bx2; x++) {
        final pix = rowBase + x;
        double s = 0;
        for (int j = 0; j < nm; j++) {
          s += d.coeffs[j] * proto[j * mhmw + pix];
        }
        if (_sigmoid(s) > 0.5) mask[pix] = 1;
      }
    }
  }

  /// Select from actual instance masks. A tap in an overlapping bounding box
  /// is not evidence that its stem is at the tapped point.
  static _TreeCandidate? _pickTarget(
    List<_TreeCandidate> trees,
    int size,
    int mh,
    int mw, {
    double? hintX,
    double? hintY,
    bool hintIsTap = false,
    double? poleHintX,
  }) {
    if (trees.isEmpty) return null;
    if (hintIsTap && hintX != null && hintY != null) {
      final x = hintX * mw / size, y = hintY * mh / size;
      _TreeCandidate? best;
      var bestDistance = double.infinity, bestSupport = -1;
      for (final tree in trees) {
        var distance = double.infinity, support = 0;
        for (var k = 0; k < tree.mask.length; k++) {
          if (tree.mask[k] == 0) continue;
          final dx = k % mw - x, dy = k ~/ mw - y;
          final d = dx * dx + dy * dy;
          distance = math.min(distance, d);
          if (d <= 9) support++;
        }
        if (distance < bestDistance ||
            (distance == bestDistance && support > bestSupport)) {
          best = tree;
          bestDistance = distance;
          bestSupport = support;
        }
      }
      // Never silently choose a remote neighbour when the requested stem is
      // absent. A few prototype pixels allow for finger and mask-boundary error.
      return bestDistance <= math.pow(math.max(2.0, mw * 0.035), 2)
          ? best
          : null;
    }
    final refX = poleHintX == null
        ? size / 2
        : 0.35 * size / 2 + 0.65 * poleHintX;
    _TreeCandidate? best;
    var bestScore = -1.0;
    for (final tree in trees) {
      final d = tree.detection;
      final center = _lowerStemCenter(tree.mask, mh, mw) * size / mw;
      final dx = ((center - refX).abs() / (size / 2)).clamp(0.0, 1.0);
      final hFrac = ((d.y2 - d.y1) / size).clamp(0.0, 1.0);
      final bottomFrac = (d.y2 / size).clamp(0.0, 1.0);
      final score =
          math.sqrt(tree.mask.where((p) => p == 1).length) *
          math.pow(math.max(0.05, 1 - dx), 2) *
          (0.5 + 0.5 * hFrac) *
          (bottomFrac > 0.55 ? 1.15 : 0.85);
      if (score > bestScore) {
        bestScore = score;
        best = tree;
      }
    }
    return best;
  }

  static double _lowerStemCenter(Uint8List mask, int mh, int mw) {
    final first = mask.indexOf(1), last = mask.lastIndexOf(1);
    if (first < 0) return mw / 2;
    final from = first ~/ mw + ((last ~/ mw - first ~/ mw) * 2 ~/ 3);
    final centers = <double>[];
    for (var y = from; y <= last ~/ mw; y++) {
      var lo = -1, hi = -1;
      for (var x = 0; x < mw; x++) {
        if (mask[y * mw + x] == 1) {
          if (lo < 0) lo = x;
          hi = x;
        }
      }
      if (lo >= 0) centers.add((lo + hi) / 2);
    }
    centers.sort();
    return centers.isEmpty ? mw / 2 : centers[centers.length ~/ 2];
  }

  /// Eight neighbours preserve diagonal, one-pixel-wide forks. Keep the tapped
  /// component as a hard condition, otherwise the largest stem component.
  static void _keepMainComponent(
    Uint8List mask,
    int mh,
    int mw, {
    double? hintX,
    double? hintY,
  }) {
    final labels = Int32List(mask.length);
    final stack = <int>[];
    var next = 0, bestLabel = 0, bestArea = 0;
    var closest = double.infinity, tappedLabel = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 0 || labels[i] != 0) continue;
      next++;
      var area = 0;
      stack.add(i);
      labels[i] = next;
      while (stack.isNotEmpty) {
        final k = stack.removeLast(), x = k % mw, y = k ~/ mw;
        area++;
        if (hintX != null && hintY != null) {
          final distance = math.pow(x - hintX, 2) + math.pow(y - hintY, 2);
          if (distance < closest) {
            closest = distance.toDouble();
            tappedLabel = next;
          }
        }
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || nx >= mw || ny < 0 || ny >= mh) continue;
            final n = ny * mw + nx;
            if (mask[n] == 1 && labels[n] == 0) {
              labels[n] = next;
              stack.add(n);
            }
          }
        }
      }
      if (area > bestArea) {
        bestArea = area;
        bestLabel = next;
      }
    }
    if (tappedLabel > 0) bestLabel = tappedLabel;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 1 && labels[i] != bestLabel) mask[i] = 0;
    }
  }

  /// User-confirmed polygons exclude unwanted stems even when their masks touch.
  /// Operates in the original letterbox grid after all rescue passes.
  static FaceAnalysis applyExclusions(
    FaceAnalysis source,
    List<List<({double x, double y})>> areas,
  ) {
    if (areas.isEmpty) return source;
    final tree = Uint8List.fromList(source.treeMask);
    for (final polygon in areas) {
      if (polygon.length < 3 ||
          polygon.any((p) => !p.x.isFinite || !p.y.isFinite)) {
        continue;
      }
      for (var y = 0; y < source.mh; y++) {
        for (var x = 0; x < source.mw; x++) {
          if (tree[y * source.mw + x] == 0) continue;
          final px = (x + 0.5) / source.mw, py = (y + 0.5) / source.mh;
          var inside = false;
          for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
            final a = polygon[i], b = polygon[j];
            if ((a.y > py) != (b.y > py) &&
                px < (b.x - a.x) * (py - a.y) / (b.y - a.y) + a.x) {
              inside = !inside;
            }
          }
          if (inside) tree[y * source.mw + x] = 0;
        }
      }
    }
    return _measure(
      source.sourceSootMask ?? source.sootMask,
      tree,
      source.mh,
      source.mw,
      source.size,
      source.nTree,
      source.nSoot,
      otherTreeMask: source.otherTreeMask,
    );
  }

  static FaceAnalysis clipGround(FaceAnalysis source, double groundNorm) {
    if (!groundNorm.isFinite) return source;
    final tree = Uint8List.fromList(source.treeMask);
    final row = (groundNorm.clamp(0.0, 1.0) * source.mh).round().clamp(
      0,
      source.mh - 1,
    );
    tree.fillRange((row + 1) * source.mw, tree.length, 0);
    return _measure(
      source.sourceSootMask ?? source.sootMask,
      tree,
      source.mh,
      source.mw,
      source.size,
      source.nTree,
      source.nSoot,
      otherTreeMask: source.otherTreeMask,
    );
  }

  /// A full-frame companion must cover the original stem and share a substantial
  /// single-trunk band. Only pixels ABOVE that band can repair a fork. The
  /// original base is retained so extra roots/poles cannot move the ground.
  /// DBH/scale use the primary stem reference separately in AnalysisService.
  static FaceAnalysis mergeCompanionTree(
    FaceAnalysis source,
    Uint8List evidence, {
    FaceAnalysis? anchor,
  }) {
    anchor ??= source;
    if (!source.hasTree || evidence.length != source.treeMask.length) {
      return source;
    }
    final candidate = Uint8List.fromList(evidence);
    _keepMainComponent(candidate, source.mh, source.mw);
    var pixels = 0, shared = 0, others = 0, added = 0;
    for (var k = 0; k < candidate.length; k++) {
      if (candidate[k] == 0) continue;
      pixels++;
      if (anchor.treeMask[k] == 1) {
        shared++;
      } else {
        added++;
        if (anchor.otherTreeMask?[k] == 1) others++;
      }
    }
    if (pixels == 0 ||
        shared < anchor.treePx * 0.9 ||
        shared < pixels * 0.65 ||
        others > added * 0.2 ||
        added < math.max(3, pixels * 0.08)) {
      return source;
    }
    final height = anchor.treeBottom - anchor.treeTop + 1;
    final first = anchor.treeTop + (height * 0.6).round();
    final last = anchor.treeTop + (height * 0.85).round();
    var consecutive = 0, bandStart = -1, attachment = -1;
    for (var y = first; y <= last; y++) {
      final a = _singleRun(anchor.treeMask, y, source.mw);
      final b = _singleRun(candidate, y, source.mw);
      final overlap = a == null || b == null
          ? 0
          : math.max(0, math.min(a.hi, b.hi) - math.max(a.lo, b.lo) + 1);
      if (a == null ||
          b == null ||
          overlap < (a.hi - a.lo + 1) * 0.75 ||
          overlap < (b.hi - b.lo + 1) * 0.75) {
        consecutive = 0;
        bandStart = -1;
        continue;
      }
      if (bandStart < 0) bandStart = y;
      consecutive++;
      final required = ((a.hi - a.lo + 1) * 0.6).ceil().clamp(3, 12);
      if (consecutive >= required) {
        attachment = bandStart;
        break;
      }
    }
    if (attachment < 0) return source;
    final tree = Uint8List.fromList(source.treeMask);
    final gaps = _forkGaps(anchor.treeMask, source.mh, source.mw);
    for (var k = 0; k < attachment * source.mw; k++) {
      if (candidate[k] == 1 && gaps[k] == 0) tree[k] = 1;
    }
    _retainAnchoredAdditions(tree, anchor.treeMask, source.mh, source.mw);
    return _measure(
      source.sourceSootMask ?? source.sootMask,
      tree,
      source.mh,
      source.mw,
      source.size,
      source.nTree,
      source.nSoot,
      otherTreeMask: source.otherTreeMask,
    );
  }

  static ({int lo, int hi})? _singleRun(Uint8List mask, int y, int mw) {
    if (y < 0 || y >= mask.length ~/ mw) return null;
    var lo = -1, hi = -1, ended = false;
    for (var x = 0; x < mw; x++) {
      if (mask[y * mw + x] == 1) {
        if (ended) return null;
        if (lo < 0) lo = x;
        hi = x;
      } else if (lo >= 0) {
        ended = true;
      }
    }
    return lo < 0 ? null : (lo: lo, hi: hi);
  }

  /// A rescue may extend a missing arm, but must not fill the negative space
  /// between arms that the original instance already separated.
  static Uint8List _forkGaps(Uint8List mask, int mh, int mw) {
    final result = Uint8List(mask.length);
    for (var y = 0; y < mh; y++) {
      var lo = -1, hi = -1;
      for (var x = 0; x < mw; x++) {
        if (mask[y * mw + x] == 1) {
          if (lo < 0) lo = x;
          hi = x;
        }
      }
      for (var x = lo + 1; lo >= 0 && x < hi; x++) {
        if (mask[y * mw + x] == 0) result[y * mw + x] = 1;
      }
    }
    return result;
  }

  /// Gap protection can sever a candidate's only connection. Flood from ALL
  /// original anchor pixels and discard only newly added floating fragments.
  static void _retainAnchoredAdditions(
    Uint8List merged,
    Uint8List anchor,
    int mh,
    int mw,
  ) {
    final seen = Uint8List(merged.length);
    final stack = <int>[];
    for (var k = 0; k < merged.length; k++) {
      if (anchor[k] == 1 && merged[k] == 1) {
        seen[k] = 1;
        stack.add(k);
      }
    }
    while (stack.isNotEmpty) {
      final k = stack.removeLast(), x = k % mw, y = k ~/ mw;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx, ny = y + dy;
          if (nx < 0 || nx >= mw || ny < 0 || ny >= mh) continue;
          final n = ny * mw + nx;
          if (merged[n] == 1 && seen[n] == 0) {
            seen[n] = 1;
            stack.add(n);
          }
        }
      }
    }
    for (var k = 0; k < merged.length; k++) {
      if (merged[k] == 1 && seen[k] == 0) merged[k] = 0;
    }
  }

  /// Only add actual inferred pixels of a branch whose lower end rejoins the
  /// selected stem. A crossing in the middle or another full-frame instance is
  /// not enough evidence. The original anchor remains fixed across rescue views.
  static FaceAnalysis mergeBranchEvidence(
    FaceAnalysis source,
    Uint8List branch,
    Uint8List soot, {
    FaceAnalysis? anchor,
  }) {
    anchor ??= source;
    if (branch.length != source.treeMask.length ||
        soot.length != branch.length) {
      return source;
    }
    final first = branch.indexOf(1), last = branch.lastIndexOf(1);
    if (first < 0) return source;
    final top = first ~/ source.mw, bottom = last ~/ source.mw;
    var pixels = 0, overlap = 0, added = 0, other = 0;
    for (var k = 0; k < branch.length; k++) {
      if (branch[k] == 0) continue;
      pixels++;
      if (anchor.treeMask[k] == 1) {
        overlap++;
      } else {
        added++;
        if (anchor.otherTreeMask?[k] == 1) other++;
      }
    }
    if (added < 3 ||
        overlap < math.max(3, pixels * 0.03) ||
        other > added * 0.2) {
      return source;
    }
    // Require a consecutive, width-scaled basal attachment. All newly recovered
    // pixels must end above it, not form an independent stem below a crossing.
    final bottomWidths = <int>[];
    for (var y = math.max(top, bottom - 3); y <= bottom; y++) {
      var width = 0;
      for (var x = 0; x < source.mw; x++) {
        if (branch[y * source.mw + x] == 1) width++;
      }
      if (width > 0) bottomWidths.add(width);
    }
    bottomWidths.sort();
    final attachRows = math
        .max(2, (bottomWidths[bottomWidths.length ~/ 2] * 0.5).ceil())
        .clamp(2, 8);
    if (bottom - attachRows + 1 <= top + (bottom - top) * 0.6) return source;
    for (var y = bottom - attachRows + 1; y <= bottom; y++) {
      var count = 0, shared = 0, runs = 0, inRun = false;
      for (var x = 0; x < source.mw; x++) {
        final k = y * source.mw + x;
        if (branch[k] == 1) {
          count++;
          if (!inRun) runs++;
          inRun = true;
          if (anchor.treeMask[k] == 1) shared++;
        } else {
          inRun = false;
        }
      }
      if (count == 0 || runs != 1 || shared < count * 0.75) return source;
    }
    final tree = Uint8List.fromList(source.treeMask);
    final gaps = _forkGaps(anchor.treeMask, source.mh, source.mw);
    final combinedSoot = Uint8List.fromList(
      source.sourceSootMask ?? source.sootMask,
    );
    for (var k = 0; k < tree.length; k++) {
      if (branch[k] == 1 && gaps[k] == 0) tree[k] = 1;
      if (soot[k] == 1) combinedSoot[k] = 1;
    }
    _retainAnchoredAdditions(tree, anchor.treeMask, source.mh, source.mw);
    return _measure(
      combinedSoot,
      tree,
      source.mh,
      source.mw,
      source.size,
      source.nTree,
      source.nSoot,
      otherTreeMask: source.otherTreeMask,
    );
  }

  static List<_Det> _nms(List<_Det> input, double iouThr) {
    input.sort((a, b) => b.score.compareTo(a.score));
    final keep = <_Det>[];
    while (input.isNotEmpty) {
      final a = input.removeAt(0);
      keep.add(a);
      input.removeWhere((b) => _iou(a, b) > iouThr);
    }
    return keep;
  }

  static double _iou(_Det a, _Det b) {
    final ix1 = math.max(a.x1, b.x1), iy1 = math.max(a.y1, b.y1);
    final ix2 = math.min(a.x2, b.x2), iy2 = math.min(a.y2, b.y2);
    final iw = math.max(0, ix2 - ix1), ih = math.max(0, iy2 - iy1);
    final inter = iw * ih;
    final ua = math.max(0, a.x2 - a.x1) * math.max(0, a.y2 - a.y1);
    final ub = math.max(0, b.x2 - b.x1) * math.max(0, b.y2 - b.y1);
    final u = ua + ub - inter;
    return u <= 0 ? 0 : inter / u;
  }
}

/// Measuring-pole scale detected from a bright-yellow near-vertical region.
class PoleScale {
  final bool detected;
  final int topY, bottomY, x; // in size×size pixels
  final double poleLengthM;
  const PoleScale(
    this.detected,
    this.topY,
    this.bottomY,
    this.x,
    this.poleLengthM,
  );

  int get spanPx => (bottomY - topY).abs();
  double get pxPerMetre =>
      spanPx > 0 && poleLengthM > 0 ? spanPx / poleLengthM : double.nan;

  static const PoleScale none = PoleScale(false, 0, 0, 0, 3.0);

  /// Heuristic: locate a bright-yellow vertical pole in the square image.
  /// NOTE: heuristic — the UI allows manual endpoint override.
  static PoleScale detect(img.Image square, int size, double poleLengthM) {
    // column-wise count of yellow pixels
    final colTop = List<int>.filled(size, -1);
    final colBot = List<int>.filled(size, -1);
    final colCount = List<int>.filled(size, 0);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final px = square.getPixel(x, y);
        final r = px.r.toInt(), g = px.g.toInt(), b = px.b.toInt();
        final yellow =
            r > 140 && g > 130 && b < 120 && (r - b) > 55 && (g - b) > 35;
        if (yellow) {
          if (colTop[x] < 0) colTop[x] = y;
          colBot[x] = y;
          colCount[x]++;
        }
      }
    }
    // pick the column with the largest vertical yellow extent
    int bestX = -1, bestSpan = 0;
    for (int x = 0; x < size; x++) {
      if (colCount[x] < size * 0.10) continue;
      final span = colBot[x] - colTop[x];
      if (span > bestSpan) {
        bestSpan = span;
        bestX = x;
      }
    }
    if (bestX < 0 || bestSpan < size * 0.25) {
      return PoleScale(false, 0, 0, 0, poleLengthM);
    }
    return PoleScale(true, colTop[bestX], colBot[bestX], bestX, poleLengthM);
  }
}

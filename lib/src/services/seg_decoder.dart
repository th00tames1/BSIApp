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

/// Decoded per-face analysis. Masks and row/col extents are in the PROTO grid
/// (mh×mw); callers scale to the size×size space with (size/mh).
class FaceAnalysis {
  final Uint8List sootMask; // mh*mw, target-tree ∩ soot union restricted later
  final Uint8List treeMask; // mh*mw, target tree
  final int mh, mw, size;
  final double bspWhole; // soot∩tree / tree
  final double bspBelow; // soot∩tree / tree below max soot height
  final int sootPx, treePx, interPx, nTree, nSoot;
  final int interTop, interBottom, interLeft, interRight; // proto rows/cols, -1 if none
  final int treeTop, treeBottom;
  const FaceAnalysis({
    required this.sootMask,
    required this.treeMask,
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
      int lo = -1, hi = -1;
      final base = y * mw;
      for (int x = 0; x < mw; x++) {
        if (treeMask[base + x] == 1) {
          if (lo < 0) lo = x;
          hi = x;
        }
      }
      if (lo >= 0) widths.add(hi - lo + 1);
    }
    if (widths.isEmpty) return 0;
    widths.sort();
    return widths[widths.length ~/ 2];
  }

  /// 한 행에서 수간 마스크의 좌·우 끝(proto 열). 마스크가 없으면 null.
  ({int lo, int hi})? treeSpanAtRow(int y) {
    if (y < 0 || y >= mh) return null;
    int lo = -1, hi = -1;
    final base = y * mw;
    for (int x = 0; x < mw; x++) {
      if (treeMask[base + x] == 1) {
        if (lo < 0) lo = x;
        hi = x;
      }
    }
    return lo < 0 ? null : (lo: lo, hi: hi);
  }

  /// 밑둥에서 [rowsUp]만큼 위(= 가슴높이)에서 잰 수간 폭. 잡음을 줄이려고
  /// 그 행 앞뒤 [band]행의 중앙값을 쓴다. 흉고직경 추정의 근거 위치도 함께 돌려준다.
  ({int width, int row, int lo, int hi})? treeSpanAtHeight(int rowsUp,
      {int band = 2}) {
    if (treeBottom < 0) return null;
    final target = (treeBottom - rowsUp).clamp(treeTop, treeBottom);
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
    double confSoot = 0.15,
    double confTree = 0.25,
    double iou = 0.45,
    double? targetHintX,
    double? targetHintY,
    bool hintIsTap = false,
    double? poleHintX,
    double? groundNorm,
  }) {
    final nm = protoShape[1], mh = protoShape[2], mw = protoShape[3];
    final dim1 = detShape[1], dim2 = detShape[2];
    final mhmw = mh * mw;
    List<_Det> soot = [], tree = [];

    if (dim2 == nm + 6) {
      // YOLO26 / end-to-end: [1, nDet, 6+nm], already NMS'd.
      final feat = dim2;
      for (int i = 0; i < dim1; i++) {
        final b = i * feat;
        final conf = det[b + 4];
        final cls = det[b + 5].round();
        final thr = cls == kTree ? confTree : (cls == kSoot ? confSoot : 1.0);
        if (conf < thr) continue;
        final c = List<double>.generate(nm, (j) => det[b + 6 + j]);
        final d = _Det(cls, conf, det[b], det[b + 1], det[b + 2], det[b + 3], c);
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
          final thr = best == kTree ? confTree : (best == kSoot ? confSoot : 1.0);
          if (bestScore < thr) continue;
          final cx = det[i], cy = det[n + i], w = det[2 * n + i], h = det[3 * n + i];
          final c = List<double>.generate(nm, (j) => det[(4 + nc + j) * n + i]);
          raw.add(_Det(best, bestScore, cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2, c));
        }
      }
      soot = _nms(raw.where((d) => d.cls == kSoot).toList(), iou);
      tree = _nms(raw.where((d) => d.cls == kTree).toList(), iou);
    }

    final factor = mw / size; // input px -> proto grid
    final sootMask = Uint8List(mhmw);
    for (final d in soot) {
      _fillMask(d, sootMask, proto, nm, mh, mw, factor);
    }
    final target = _pickTarget(tree, size,
        hintX: targetHintX,
        hintY: targetHintY,
        hintIsTap: hintIsTap,
        poleHintX: poleHintX);
    final treeMask = Uint8List(mhmw);
    if (target != null) {
      _fillMask(target, treeMask, proto, nm, mh, mw, factor);
      // 뒤에 겹쳐 선 나무가 같은 상자 안에 들어오면 마스크가 두 줄기를 함께
      // 물고, 흉고직경 폭이 부풀고 그을음 비율이 흐려진다(현장 보고).
      // 상자 중심 세로선에 걸친 **하나의 연결 덩어리**만 남긴다.
      _keepMainComponent(
          treeMask, mh, mw, (((target.x1 + target.x2) / 2) * factor).round());
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

    int sootPx = 0, treePx = 0, interPx = 0;
    int iTop = -1, iBot = -1, iLeft = mw, iRight = -1, tTop = -1, tBot = -1;
    for (int y = 0; y < mh; y++) {
      final base = y * mw;
      for (int x = 0; x < mw; x++) {
        final idx = base + x;
        final s = sootMask[idx], t = treeMask[idx];
        if (s == 1) sootPx++;
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
      sootMask: sootMask,
      treeMask: treeMask,
      mh: mh,
      mw: mw,
      size: size,
      bspWhole: treePx > 0 ? interPx / treePx : double.nan,
      bspBelow: treeBelow > 0 ? interPx / treeBelow : double.nan,
      sootPx: sootPx,
      treePx: treePx,
      interPx: interPx,
      nTree: tree.length,
      nSoot: soot.length,
      interTop: iTop,
      interBottom: iBot,
      interLeft: iLeft,
      interRight: iRight,
      treeTop: tTop,
      treeBottom: tBot,
    );
  }

  static void _fillMask(_Det d, Uint8List mask, Float32List proto, int nm, int mh,
      int mw, double factor) {
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

  /// 조사 대상목 하나를 고른다.
  ///
  /// 조사자는 **대상목을 화면 중앙에 세우고 그 옆에 수고봉을 붙여** 찍는다.
  /// 옛 규칙(면적 × 중심거리)은 옆·뒤 나무가 더 크게 잡히면 그쪽으로 넘어갔다
  /// (현장 보고). 그래서 아래를 함께 본다.
  ///   · 가로로 중앙에서 얼마나 벗어났는지 — 가장 강한 단서
  ///   · 수고봉과 얼마나 가까운지 — 봉은 대상목에 붙여 세운다
  ///   · 프레임을 세로로 채우는지, 밑동이 아래쪽에 있는지
  /// [hintIsTap]이면 조사자가 줄기를 직접 찍은 것이므로 그 점을 품는 검출을
  /// 최우선으로 고른다(겹친 경우 더 작은 쪽 = 앞의 나무).
  static _Det? _pickTarget(
    List<_Det> trees,
    int size, {
    double? hintX,
    double? hintY,
    bool hintIsTap = false,
    double? poleHintX,
  }) {
    if (trees.isEmpty) return null;

    if (hintIsTap && hintX != null && hintY != null) {
      final hit = trees
          .where((d) => hintX >= d.x1 && hintX <= d.x2 && hintY >= d.y1 && hintY <= d.y2)
          .toList();
      if (hit.isNotEmpty) {
        hit.sort((a, b) => _area(a).compareTo(_area(b)));
        return hit.first; // 겹치면 더 작은(앞에 선) 나무
      }
      // 품는 검출이 없으면 지정점에 가장 가까운 것
      _Det? near;
      double bestD = double.infinity;
      for (final d in trees) {
        final mx = (d.x1 + d.x2) / 2, my = (d.y1 + d.y2) / 2;
        final dd = (mx - hintX) * (mx - hintX) + (my - hintY) * (my - hintY);
        if (dd < bestD) {
          bestD = dd;
          near = d;
        }
      }
      return near;
    }

    // 기준 가로 위치: 수고봉이 있으면 **봉 쪽**이 대상목이다(봉은 조사목에
    // 붙여 세운다). 없으면 화면 중앙 — 조사자가 대상목을 가운데 두고 찍는다.
    final cx = size / 2;
    final refX = poleHintX == null ? cx : 0.35 * cx + 0.65 * poleHintX;
    _Det? best;
    double bestScore = -1;
    for (final d in trees) {
      final area = _area(d);
      if (area <= 0) continue;
      final mx = (d.x1 + d.x2) / 2;
      // 0 = 기준 위치, 1 = 화면 가장자리만큼 떨어짐
      final dx = ((mx - refX).abs() / (size / 2)).clamp(0.0, 1.0);
      final hFrac = ((d.y2 - d.y1) / size).clamp(0.0, 1.0);
      final bottomFrac = (d.y2 / size).clamp(0.0, 1.0);
      // 면적은 **제곱근**으로만 반영한다. 그대로 쓰면 가까이 선 옆 나무가
      // 면적만으로 이겨 버린다(현장 보고). 가로 위치가 가장 강한 단서다.
      final dev = math.max(0.05, 1 - dx);
      final score = math.sqrt(area) *
          dev * dev * // 기준에서 멀수록 제곱으로 감점
          (0.5 + 0.5 * hFrac) * // 세로로 길게 잡힌 줄기 우대
          (bottomFrac > 0.55 ? 1.15 : 0.85); // 밑동이 아래쪽에 오면 가점
      if (score > bestScore) {
        bestScore = score;
        best = d;
      }
    }
    return best;
  }

  /// 마스크에서 [seedX] 세로선에 걸친 가장 큰 연결 덩어리만 남긴다(4이웃).
  /// 걸친 덩어리가 없으면 전체에서 가장 큰 덩어리를 남긴다.
  static void _keepMainComponent(Uint8List mask, int mh, int mw, int seedX) {
    final sx = seedX.clamp(0, mw - 1);
    final label = Int32List(mh * mw); // 0 = 미방문
    final stack = <int>[];
    var bestLabel = 0, bestScore = -1;
    var cur = 0;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] != 1 || label[i] != 0) continue;
      cur++;
      var size = 0;
      var touchesSeed = false;
      stack.add(i);
      label[i] = cur;
      while (stack.isNotEmpty) {
        final k = stack.removeLast();
        size++;
        final y = k ~/ mw, x = k % mw;
        if (x == sx) touchesSeed = true;
        if (x > 0 && mask[k - 1] == 1 && label[k - 1] == 0) {
          label[k - 1] = cur;
          stack.add(k - 1);
        }
        if (x < mw - 1 && mask[k + 1] == 1 && label[k + 1] == 0) {
          label[k + 1] = cur;
          stack.add(k + 1);
        }
        if (y > 0 && mask[k - mw] == 1 && label[k - mw] == 0) {
          label[k - mw] = cur;
          stack.add(k - mw);
        }
        if (y < mh - 1 && mask[k + mw] == 1 && label[k + mw] == 0) {
          label[k + mw] = cur;
          stack.add(k + mw);
        }
      }
      // 중심선에 걸친 덩어리를 우선(가중 10배), 그중 큰 것.
      final score = size * (touchesSeed ? 10 : 1);
      if (score > bestScore) {
        bestScore = score;
        bestLabel = cur;
      }
    }
    if (bestLabel == 0) return;
    for (var i = 0; i < mask.length; i++) {
      if (mask[i] == 1 && label[i] != bestLabel) mask[i] = 0;
    }
  }

  static double _area(_Det d) =>
      math.max(0, d.x2 - d.x1) * math.max(0, d.y2 - d.y1);

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
  const PoleScale(this.detected, this.topY, this.bottomY, this.x, this.poleLengthM);

  int get spanPx => (bottomY - topY).abs();
  double get pxPerMetre => spanPx > 0 && poleLengthM > 0 ? spanPx / poleLengthM : double.nan;

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
        final yellow = r > 140 && g > 130 && b < 120 && (r - b) > 55 && (g - b) > 35;
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
    if (bestX < 0 || bestSpan < size * 0.25) return PoleScale(false, 0, 0, 0, poleLengthM);
    return PoleScale(true, colTop[bestX], colBot[bestX], bestX, poleLengthM);
  }
}

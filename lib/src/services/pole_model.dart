import 'dart:math' as math;
import 'dart:typed_data';

/// 수고봉 1 m 경계 검출 결과 → px/m 스케일.
///
/// 모델은 노랑/흰 **경계점**을 검출한다(순서·인덱스 없음). 스케일은 다음 순서로
/// 만든다. 파이썬 기준 구현(`4_code/pole/pole_scale.py`)과 규칙이 동일하다.
///
///   ① 사진에 봉이 둘 이상일 수 있으므로 **공선성으로 봉 단위 군집**
///   ② 봉 축(주성분)에 투영해 정렬 → 인접 간격
///   ③ **중앙값**을 1 m 후보로 삼고, 가려져 건너뛴 경계는 정수배로 되돌림
///   ④ 점이 4개 이상이면 **1차 사영변환**을 적합해 높이별 국소 배율을 구함
///      (원근 단축 보정 — 카메라 파라미터가 필요 없어 기기 무관)
class PoleBoundary {
  final double x, y, score;
  const PoleBoundary(this.x, this.y, this.score);
}

class PoleStaff {
  final List<PoleBoundary> points;
  const PoleStaff(this.points);

  int get n => points.length;

  /// 봉 축 방향(주성분) 각도.
  double get _theta {
    final mx = points.map((p) => p.x).reduce((a, b) => a + b) / n;
    final my = points.map((p) => p.y).reduce((a, b) => a + b) / n;
    double sxx = 0, syy = 0, sxy = 0;
    for (final p in points) {
      sxx += (p.x - mx) * (p.x - mx);
      syy += (p.y - my) * (p.y - my);
      sxy += (p.x - mx) * (p.y - my);
    }
    return 0.5 * math.atan2(2 * sxy, sxx - syy);
  }

  ({double mx, double my, double ux, double uy}) get _frame {
    final mx = points.map((p) => p.x).reduce((a, b) => a + b) / n;
    final my = points.map((p) => p.y).reduce((a, b) => a + b) / n;
    final t = _theta;
    return (mx: mx, my: my, ux: math.cos(t), uy: math.sin(t));
  }

  /// 축에 투영한 좌표(오름차순).
  List<double> axisProjection() {
    final f = _frame;
    final v = [
      for (final p in points) (p.x - f.mx) * f.ux + (p.y - f.my) * f.uy
    ]..sort();
    return v;
  }

  double project(double x, double y) {
    final f = _frame;
    return (x - f.mx) * f.ux + (y - f.my) * f.uy;
  }

  List<double> gaps() {
    final v = axisProjection();
    return [for (var i = 0; i < v.length - 1; i++) v[i + 1] - v[i]];
  }
}

/// 한 사진의 스케일 해.
class PoleScaleSolution {
  final double pxPerMetre; // 대표값
  final PoleStaff staff;
  final List<double> _params; // 사영 보정 [a,b,c,d] — 비었으면 상수 스케일
  final List<double> gaps;
  final double curvature; // 봉 직선성 잔차(방사왜곡 지표)

  const PoleScaleSolution({
    required this.pxPerMetre,
    required this.staff,
    required List<double> params,
    required this.gaps,
    required this.curvature,
  }) : _params = params;

  bool get perspectiveCorrected => _params.length == 4;
  int get boundaryCount => staff.n;

  /// 화면 y(및 x) 위치에서의 국소 px/m. 원근 보정이 없으면 대표값.
  double pxPerMetreAt(double x, double y) {
    if (_params.length != 4) return pxPerMetre;
    final proj = staff.axisProjection();
    var t = staff.project(x, y);
    // 봉이 관측된 범위 밖으로는 외삽하지 않는다
    if (t < proj.first) t = proj.first;
    if (t > proj.last) t = proj.last;
    final k = PoleDetector._metreIndexAt(_params, t);
    return PoleDetector._localPxPerM(_params, k);
  }
}

class PoleDetector {
  PoleDetector._();

  /// 사영 적합 최소 점수. 3개면 미지수와 같아 노이즈가 그대로 증폭된다.
  static const int minPointsForPerspective = 4;

  /// YOLO dense 출력 [1, 4+nc, anchors] → 경계점(입력 size×size 좌표계).
  ///
  /// 학습을 점 하나당 작은 정사각 박스로 했으므로 **박스 중심이 곧 경계점**이다.
  /// NMS는 중심 거리 기준으로 한다(박스가 작아 IoU가 불안정하다).
  static List<PoleBoundary> decode(
    Float32List out,
    List<int> shape,
    int size, {
    double conf = 0.25,
    double mergeDist = 0.012,
  }) {
    final ch = shape[1], n = shape[2];
    if (ch < 5) return const [];
    final cands = <PoleBoundary>[];
    for (var i = 0; i < n; i++) {
      // 채널 우선 배치: [cx, cy, w, h, score...]
      var best = out[4 * n + i];
      for (var c = 5; c < ch; c++) {
        final v = out[c * n + i];
        if (v > best) best = v;
      }
      if (best < conf) continue;
      cands.add(PoleBoundary(out[i], out[n + i], best));
    }
    cands.sort((a, b) => b.score.compareTo(a.score));
    // 중심 거리 NMS — 실제 경계 간격보다 훨씬 촘촘한 검출은 같은 경계로 본다
    final minD = size * mergeDist;
    final keep = <PoleBoundary>[];
    for (final c in cands) {
      var dup = false;
      for (final k in keep) {
        final dx = c.x - k.x, dy = c.y - k.y;
        if (dx * dx + dy * dy < minD * minD) {
          dup = true;
          break;
        }
      }
      if (!dup) keep.add(c);
    }
    return keep;
  }

  /// letterbox(size×size) 좌표 → 원본 이미지 좌표.
  static List<PoleBoundary> unletterbox(
      List<PoleBoundary> pts, double scale, int padX, int padY) {
    return [
      for (final p in pts)
        PoleBoundary((p.x - padX) / scale, (p.y - padY) / scale, p.score)
    ];
  }

  /// 검출점 → 스케일 해. 만들 수 없으면 null.
  ///
  /// 중복 병합을 여기서도 한 번 더 한다. [decode]가 이미 걸렀으면 멱등이고,
  /// 다른 경로로 들어온 점(테스트·외부 호출)에도 같은 규칙이 적용된다.
  static PoleScaleSolution? solve(List<PoleBoundary> dets, int imageWidth) {
    if (dets.length < 2) return null;
    dets = _dedupe(dets, imageWidth * 0.012);
    if (dets.length < 2) return null;
    final staffs = _cluster(dets, imageWidth * 0.02)
        .where((s) => s.n >= 2)
        .toList();
    if (staffs.isEmpty) return null;
    // 경계가 가장 많은 봉을 신뢰한다(동수면 점수 합이 큰 쪽)
    staffs.sort((a, b) {
      final c = b.n.compareTo(a.n);
      if (c != 0) return c;
      double s(PoleStaff st) => st.points.fold(0.0, (t, p) => t + p.score);
      return s(b).compareTo(s(a));
    });
    final staff = staffs.first;
    final gaps = staff.gaps();
    final base = _pxPerMetre(gaps);
    if (base == null) return null;

    var params = <double>[];
    if (staff.n >= minPointsForPerspective) {
      final proj = staff.axisProjection();
      final k = _assignIndices(gaps, base);
      final cand = _fitProjective(proj, k);
      if (cand != null) {
        // 관측 구간 안에서 0.5~2배를 벗어나면 퇴화한 적합
        var ok = true;
        final steps = (k.last - k.first).round();
        for (var i = 0; i < math.max(steps, 1); i++) {
          final v = _localPxPerM(cand, k.first + 0.5 + i);
          if (v < 0.5 * base || v > 2.0 * base) ok = false;
        }
        if (ok) params = cand;
      }
    }
    return PoleScaleSolution(
      pxPerMetre: base,
      staff: staff,
      params: params,
      gaps: gaps,
      curvature: _straightness(staff.points),
    );
  }

  /// 같은 경계에 두 번 찍힌 점을 병합한다(점수가 높은 쪽을 남김).
  static List<PoleBoundary> _dedupe(List<PoleBoundary> pts, double minDist) {
    final sorted = [...pts]..sort((a, b) => b.score.compareTo(a.score));
    final out = <PoleBoundary>[];
    for (final p in sorted) {
      var dup = false;
      for (final q in out) {
        final dx = p.x - q.x, dy = p.y - q.y;
        if (dx * dx + dy * dy < minDist * minDist) {
          dup = true;
          break;
        }
      }
      if (!dup) out.add(p);
    }
    return out;
  }

  // ── 봉 군집(공선성) ────────────────────────────────────────────────
  static List<PoleStaff> _cluster(List<PoleBoundary> pts, double tol) {
    final remaining = List<PoleBoundary>.from(pts);
    final out = <PoleStaff>[];
    while (remaining.length >= 2) {
      var best = <int>[];
      for (var i = 0; i < remaining.length; i++) {
        for (var j = i + 1; j < remaining.length; j++) {
          final a = remaining[i], b = remaining[j];
          final dx = b.x - a.x, dy = b.y - a.y;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len < 1e-6) continue;
          final inl = <int>[];
          for (var k = 0; k < remaining.length; k++) {
            final p = remaining[k];
            final d = ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len;
            if (d <= tol) inl.add(k);
          }
          if (inl.length > best.length) best = inl;
        }
      }
      if (best.length < 2) break;
      final set = best.toSet();
      out.add(PoleStaff([for (final k in best) remaining[k]]));
      final rest = <PoleBoundary>[];
      for (var k = 0; k < remaining.length; k++) {
        if (!set.contains(k)) rest.add(remaining[k]);
      }
      remaining
        ..clear()
        ..addAll(rest);
    }
    return out;
  }

  // ── 간격 → px/m (건너뛴 경계는 정수배로 되돌림) ────────────────────
  /// 간격의 중앙값을 그냥 1 m로 삼으면 안 된다. 경계가 가려져 2 m 간격이 섞이고
  /// 간격 수가 짝수면 **2 m짜리를 1 m로 골라 스케일이 2배 틀어진다**(검증에서
  /// 50 % 오차로 확인). 각 간격을 1·2·3…으로 나눈 값을 후보로 놓고, 모든 간격을
  /// 정수배로 설명하는 후보 중 **가장 큰 것**을 고른다(작을수록 무엇이든 설명되므로).
  static double? _pxPerMetre(List<double> gaps,
      {double residTol = 0.16, int maxSkip = 4}) {
    var good = gaps.where((g) => g > 1e-6).toList();
    if (good.isEmpty) return null;
    if (good.length == 1) return good.first;

    // 같은 경계에 두 번 검출되면 거의 0인 간격이 생겨 기준을 끌어내린다
    final big = good.reduce(math.max);
    good = good.where((g) => g >= 0.25 * big).toList();
    if (good.isEmpty) good = [big];

    final cands = <double>{};
    for (final g in good) {
      for (var k = 1; k <= maxSkip; k++) {
        cands.add(g / k);
      }
    }
    final sortedCands = cands.toList()..sort((a, b) => b.compareTo(a));
    double? best;
    for (final c in sortedCands) {
      var resid = 0.0;
      var ok = true;
      for (final g in good) {
        final k = (g / c).round();
        if (k < 1) {
          ok = false;
          break;
        }
        resid += (g / c - k).abs();
      }
      if (ok && resid / good.length <= residTol) {
        best = c; // 내림차순이라 처음 통과한 것이 가장 큰 후보
        break;
      }
    }
    if (best == null) return null;
    final unit = good.map((g) => g / math.max(1, (g / best!).round())).toList()
      ..sort();
    return unit[unit.length ~/ 2];
  }


  static List<double> _assignIndices(List<double> gaps, double base) {
    final k = <double>[0];
    for (final g in gaps) {
      final step = base > 0 ? math.max(1, (g / base).round()) : 1;
      k.add(k.last + step);
    }
    return k;
  }

  // ── 1차 사영변환 t = (a·k + b)/(c·k + d), d=1 고정 ─────────────────
  static List<double>? _fitProjective(List<double> t, List<double> k) {
    final n = t.length;
    if (n < 3) return null;
    final rows = [for (var i = 0; i < n; i++) [k[i], 1.0, -k[i] * t[i]]];
    final ata = List.generate(3, (p) => List<double>.filled(4, 0));
    for (var p = 0; p < 3; p++) {
      for (var q = 0; q < 3; q++) {
        var s = 0.0;
        for (var i = 0; i < n; i++) {
          s += rows[i][p] * rows[i][q];
        }
        ata[p][q] = s;
      }
      var s = 0.0;
      for (var i = 0; i < n; i++) {
        s += rows[i][p] * t[i];
      }
      ata[p][3] = s;
    }
    for (var c = 0; c < 3; c++) {
      var piv = c;
      for (var r = c; r < 3; r++) {
        if (ata[r][c].abs() > ata[piv][c].abs()) piv = r;
      }
      if (ata[piv][c].abs() < 1e-12) return null;
      final tmp = ata[c];
      ata[c] = ata[piv];
      ata[piv] = tmp;
      for (var r = 0; r < 3; r++) {
        if (r == c) continue;
        final f = ata[r][c] / ata[c][c];
        for (var q = c; q < 4; q++) {
          ata[r][q] -= f * ata[c][q];
        }
      }
    }
    return [ata[0][3] / ata[0][0], ata[1][3] / ata[1][1], ata[2][3] / ata[2][2], 1.0];
  }

  static double _localPxPerM(List<double> p, double k) {
    final den = p[2] * k + p[3];
    return (p[0] * p[3] - p[1] * p[2]).abs() / math.max(den * den, 1e-12);
  }

  static double _metreIndexAt(List<double> p, double t) {
    final den = p[0] - p[2] * t;
    if (den.abs() < 1e-12) return 0;
    return (t * p[3] - p[1]) / den;
  }

  static double _straightness(List<PoleBoundary> pts) {
    if (pts.length < 3) return 0;
    final a = pts.first, b = pts.last;
    final dx = b.x - a.x, dy = b.y - a.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-6) return 0;
    var worst = 0.0;
    for (final p in pts) {
      final d = ((p.x - a.x) * dy - (p.y - a.y) * dx).abs() / len;
      if (d > worst) worst = d;
    }
    return worst / len;
  }
}

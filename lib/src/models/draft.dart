import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../services/analysis_service.dart';
import '../theme.dart';
import 'survey.dart';

/// Mutable state carried through the survey flow (register → capture → analyse → result).
class SurveyDraft {
  String treeId = '';
  String site = '';
  String address = '';
  double? lat;
  double? lon;
  bool gapOffsetSet = false; // lat/lon came from an explicit gap-offset (authoritative)
  String species = '소나무';
  double dbhCm = 0;
  String memo = '';
  double poleLengthM = 3.0;
  String modelName = 'YOLO26s@640';
  String modelAsset = 'assets/models/bsi_seg_yolo26s_640.onnx';
  /// 수고봉 1 m 경계 검출 모델(스케일 산출). 없으면 노란픽셀 휴리스틱으로 내려간다.
  String poleModelAsset = 'assets/models/pole_boundary_640.onnx';

  /// 설정의 "예시 사진으로 시험"으로 만든 조사인지. 예시 조사는 시연 모드의
  /// 자동 투어를 돌리지 않고, 저장해도 진행 중이던 실제 조사 초안을 지우지 않는다.
  bool isSample = false;

  final Map<Azimuth, String> photos = {}; // captured photo path per azimuth
  // Per-azimuth standpoint fix: dwell-averaged position + its scatter (m).
  final Map<Azimuth, ({double lat, double lon, double sigma})> photoPos = {};
  final Map<Azimuth, AzimuthResult> results = {};
  BsiIntegration? integ;

  /// Assumed surveyor standing distance from the trunk (m). Used to forward-
  /// project each standpoint onto the trunk. Opposing pairs cancel this; the
  /// projection mainly de-biases partial (1–2 azimuth) coverage.
  static const double standDistanceM = 8.0;

  List<Azimuth> get capturedAzimuths =>
      Azimuth.values.where((a) => photos.containsKey(a)).toList();

  int get gpsPointCount => photoPos.length;

  bool get _hasOpposingPair =>
      (photoPos.containsKey(Azimuth.east) && photoPos.containsKey(Azimuth.west)) ||
      (photoPos.containsKey(Azimuth.north) && photoPos.containsKey(Azimuth.south));

  bool get locationIsFullEstimate => _hasOpposingPair;

  ({double lat, double lon})? get _manualFix =>
      (lat != null && lon != null) ? (lat: lat!, lon: lon!) : null;

  /// Tree location: forward-project each azimuth standpoint onto the trunk
  /// (facing bearing + [standDistanceM]), reject blunders (>25 m from the
  /// weighted mean when ≥3 points), then take the inverse-variance weighted
  /// mean. Falls back to the manual 등록 fix when no shot carried a position.
  ({double lat, double lon})? get treeLocation {
    // An explicit gap-offset means the surveyor distrusts the on-tree fixes.
    if (gapOffsetSet && _manualFix != null) return _manualFix;
    if (photoPos.isEmpty) return _manualFix;
    final pts = <({double lat, double lon, double w})>[];
    photoPos.forEach((az, p) {
      final facing = ((az.heading + 180) % 360) * pi / 180.0; // toward trunk
      final dLat = (standDistanceM * cos(facing)) / 111320.0;
      final dLon =
          (standDistanceM * sin(facing)) / (111320.0 * cos(p.lat * pi / 180.0));
      final w = 1.0 / pow(max(p.sigma, 3.0), 2); // inverse-variance (σ floored 3 m)
      pts.add((lat: p.lat + dLat, lon: p.lon + dLon, w: w));
    });
    var kept = pts;
    if (pts.length >= 3) {
      final m0 = _wmean(pts);
      final k = pts.where((q) => _distM(q.lat, q.lon, m0.lat, m0.lon) <= 25.0).toList();
      if (k.isNotEmpty) kept = k;
    }
    return _wmean(kept);
  }

  ({double lat, double lon}) _wmean(List<({double lat, double lon, double w})> pts) {
    double sw = 0, sLat = 0, sLon = 0;
    for (final q in pts) {
      sw += q.w;
      sLat += q.lat * q.w;
      sLon += q.lon * q.w;
    }
    return (lat: sLat / sw, lon: sLon / sw);
  }

  double _distM(double aLat, double aLon, double bLat, double bLon) {
    final mLat = (aLat + bLat) / 2 * pi / 180.0;
    final dLat = (aLat - bLat) * 111320.0;
    final dLon = (aLon - bLon) * 111320.0 * cos(mLat);
    return sqrt(dLat * dLat + dLon * dLon);
  }

  List<AzimuthResult> get faces =>
      Azimuth.values.where(results.containsKey).map((a) => results[a]!).toList();

  SurveyRecord toRecord() => SurveyRecord(
        treeId: treeId,
        site: site,
        address: address,
        lat: treeLocation?.lat,
        lon: treeLocation?.lon,
        species: species,
        dbhCm: dbhCm,
        memo: memo,
        modelName: modelName,
        poleLengthM: poleLengthM,
        faces: faces,
        bsi: integ?.bsi ?? double.nan,
        mortalityProb: integ?.mortality ?? double.nan,
        verdict: integ?.verdict ?? '',
        createdAt: DateTime.now(),
      );

  /// Has the surveyor started capturing (worth resuming after a close/kill)?
  bool get isInProgress => photos.isNotEmpty;

  // ── Resume persistence ──────────────────────────────────────────────
  // Serialized up to the capture stage (scalars + photo paths + standpoints);
  // analysis results are recomputed on resume, so they are not stored.
  Map<String, dynamic> toJson() => {
        'treeId': treeId,
        'site': site,
        'address': address,
        'lat': lat,
        'lon': lon,
        'gapOffsetSet': gapOffsetSet,
        'species': species,
        'dbhCm': dbhCm,
        'memo': memo,
        'poleLengthM': poleLengthM,
        'modelName': modelName,
        'modelAsset': modelAsset,
        'photos': photos.map((k, v) => MapEntry(k.name, v)),
        'photoPos': photoPos.map((k, v) =>
            MapEntry(k.name, {'lat': v.lat, 'lon': v.lon, 'sigma': v.sigma})),
      };

  String toJsonString() => jsonEncode(toJson());

  static SurveyDraft? fromJsonString(String s) {
    try {
      final j = jsonDecode(s) as Map<String, dynamic>;
      final d = SurveyDraft()
        ..treeId = j['treeId'] as String? ?? ''
        ..site = j['site'] as String? ?? ''
        ..address = j['address'] as String? ?? ''
        ..lat = (j['lat'] as num?)?.toDouble()
        ..lon = (j['lon'] as num?)?.toDouble()
        ..gapOffsetSet = j['gapOffsetSet'] as bool? ?? false
        ..species = j['species'] as String? ?? '소나무'
        ..dbhCm = (j['dbhCm'] as num?)?.toDouble() ?? 0
        ..memo = j['memo'] as String? ?? ''
        ..poleLengthM = (j['poleLengthM'] as num?)?.toDouble() ?? 3.0
        ..modelName = j['modelName'] as String? ?? 'YOLO26s@640'
        ..modelAsset = j['modelAsset'] as String? ??
            'assets/models/bsi_seg_yolo26s_640.onnx';
      (j['photos'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        // Only restore shots whose file survived (a wiped cache would otherwise
        // crash the analysis step later).
        final path = v as String;
        if (File(path).existsSync()) d.photos[Azimuth.values.byName(k)] = path;
      });
      (j['photoPos'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        final m = v as Map<String, dynamic>;
        d.photoPos[Azimuth.values.byName(k)] = (
          lat: (m['lat'] as num).toDouble(),
          lon: (m['lon'] as num).toDouble(),
          sigma: (m['sigma'] as num).toDouble(),
        );
      });
      return d;
    } catch (_) {
      return null;
    }
  }
}

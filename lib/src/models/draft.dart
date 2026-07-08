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
}

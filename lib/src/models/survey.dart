import 'dart:convert';

import 'tuning.dart';

/// NaN is not valid JSON and breaks sqflite; store it as null (round-trips
/// back to NaN via the `?? double.nan` fallbacks on read).
Object? _n(double v) => v.isNaN ? null : v;

/// Per-azimuth analysis result for one captured face.
class AzimuthResult {
  final String azimuth; // 'E' | 'W' | 'S' | 'N'
  final String? imagePath; // captured photo file
  final String? overlayPath; // rendered overlay (stem red / soot green)
  final double sootProportion; // BSP, field-aligned (R_below) [0..1]
  final double sootProportionWhole; // R_whole [0..1]
  final double sootHeightM; // scorch height in metres (from pole scale)
  final double sootWidthM; // scorch width in metres
  final double visibleStemHeightM; // visible stem height in metres
  final double pxPerMetre; // pixel scale from the measuring pole
  final double dbhEstM; // estimated DBH (m) from stem width at breast height
  final int sootPx;
  final int treePx;
  final bool analysed;

  /// 사진 없이 조사자가 직접 넣은 방위인지. 촬영하지 못한 면을 야장 값으로
  /// 채워 4방위 BSI를 완성할 때 쓴다. 재분석은 이 면을 건드리지 않는다.
  final bool manual;

  /// 조사자가 이 면의 값(그을음 높이·면적비)을 직접 고쳤는지.
  /// 사진이 있는 면도 현장에서 손으로 바로잡을 수 있다 — 그 값이 BSI에 들어간다.
  final bool manualEdited;

  /// 이 면의 분석 조정값(지표면·대상목 지정·밝기/대비). 재분석 재현에 쓴다.
  final FaceTuning tuning;

  /// 스케일(px/m)의 출처: 'pole'(수고봉 경계 모델) · 'manual' · 'heuristic'(노란픽셀)
  /// · 'dbh'(수고봉 없이 실측 흉고직경으로 추정 — 정밀도 낮음) · ''(스케일 없음).
  final String scaleSource;

  const AzimuthResult({
    required this.azimuth,
    this.imagePath,
    this.overlayPath,
    this.sootProportion = double.nan,
    this.sootProportionWhole = double.nan,
    this.sootHeightM = double.nan,
    this.sootWidthM = double.nan,
    this.visibleStemHeightM = double.nan,
    this.pxPerMetre = double.nan,
    this.dbhEstM = double.nan,
    this.sootPx = 0,
    this.treePx = 0,
    this.analysed = false,
    this.manual = false,
    this.manualEdited = false,
    this.tuning = FaceTuning.none,
    this.scaleSource = '',
  });

  AzimuthResult copyWith({
    String? imagePath,
    String? overlayPath,
    double? sootProportion,
    double? sootProportionWhole,
    double? sootHeightM,
    double? sootWidthM,
    double? visibleStemHeightM,
    double? pxPerMetre,
    double? dbhEstM,
    int? sootPx,
    int? treePx,
    bool? analysed,
    bool? manual,
    bool? manualEdited,
    FaceTuning? tuning,
    String? scaleSource,
  }) =>
      AzimuthResult(
        azimuth: azimuth,
        imagePath: imagePath ?? this.imagePath,
        overlayPath: overlayPath ?? this.overlayPath,
        sootProportion: sootProportion ?? this.sootProportion,
        sootProportionWhole: sootProportionWhole ?? this.sootProportionWhole,
        sootHeightM: sootHeightM ?? this.sootHeightM,
        sootWidthM: sootWidthM ?? this.sootWidthM,
        visibleStemHeightM: visibleStemHeightM ?? this.visibleStemHeightM,
        pxPerMetre: pxPerMetre ?? this.pxPerMetre,
        dbhEstM: dbhEstM ?? this.dbhEstM,
        sootPx: sootPx ?? this.sootPx,
        treePx: treePx ?? this.treePx,
        analysed: analysed ?? this.analysed,
        manual: manual ?? this.manual,
        manualEdited: manualEdited ?? this.manualEdited,
        tuning: tuning ?? this.tuning,
        scaleSource: scaleSource ?? this.scaleSource,
      );

  Map<String, dynamic> toJson() => {
        'azimuth': azimuth,
        'imagePath': imagePath,
        'overlayPath': overlayPath,
        'sootProportion': _n(sootProportion),
        'sootProportionWhole': _n(sootProportionWhole),
        'sootHeightM': _n(sootHeightM),
        'sootWidthM': _n(sootWidthM),
        'visibleStemHeightM': _n(visibleStemHeightM),
        'pxPerMetre': _n(pxPerMetre),
        'dbhEstM': _n(dbhEstM),
        'sootPx': sootPx,
        'treePx': treePx,
        'analysed': analysed,
        'manual': manual,
        'manualEdited': manualEdited,
        'tuning': tuning.toJson(),
        'scaleSource': scaleSource,
      };

  factory AzimuthResult.fromJson(Map<String, dynamic> j) => AzimuthResult(
        azimuth: j['azimuth'] as String,
        imagePath: j['imagePath'] as String?,
        overlayPath: j['overlayPath'] as String?,
        sootProportion: (j['sootProportion'] as num?)?.toDouble() ?? double.nan,
        sootProportionWhole: (j['sootProportionWhole'] as num?)?.toDouble() ?? double.nan,
        sootHeightM: (j['sootHeightM'] as num?)?.toDouble() ?? double.nan,
        sootWidthM: (j['sootWidthM'] as num?)?.toDouble() ?? double.nan,
        visibleStemHeightM: (j['visibleStemHeightM'] as num?)?.toDouble() ?? double.nan,
        pxPerMetre: (j['pxPerMetre'] as num?)?.toDouble() ?? double.nan,
        dbhEstM: (j['dbhEstM'] as num?)?.toDouble() ?? double.nan,
        sootPx: (j['sootPx'] as num?)?.toInt() ?? 0,
        treePx: (j['treePx'] as num?)?.toInt() ?? 0,
        analysed: j['analysed'] as bool? ?? false,
        manual: j['manual'] as bool? ?? false,
        manualEdited: j['manualEdited'] as bool? ?? false,
        tuning: FaceTuning.fromJson(j['tuning'] as Map<String, dynamic>?),
        scaleSource: j['scaleSource'] as String? ?? '',
      );
}

/// One surveyed tree with its four faces and the integrated BSI.
class SurveyRecord {
  final int? dbId; // storage primary key (null until saved)
  final String treeId; // 조사목 ID e.g. TA205-001
  final String site; // 조사지
  final String address; // 조사 위치
  final double? lat;
  final double? lon;
  final String species; // 수종
  final double dbhCm; // 흉고직경 (user-entered, cm)
  /// 수고 (m). NaN이면 방위별 계측값(visibleStemHeightM 최대)으로 표시한다.
  final double heightM;
  /// 그을음 최고 높이 (m). NaN이면 방위별 계측값(sootHeightM 최대)으로 표시한다.
  final double sootMaxM;
  /// 원시 데이터 번들 폴더(사진 원본·분석 산출물·record.json). 없으면 null.
  final String? rawDir;
  final String memo;
  final String modelName;
  final double poleLengthM; // measuring-pole real length used for scale
  /// 수고봉 경계 간격(m) — 스케일 산출에 쓴 값(재분석·학습 데이터 추적용).
  final double poleGapM;
  final List<AzimuthResult> faces;
  final double bsi; // integrated BSI = Σ(height × proportion)
  final double mortalityProb; // [0..1]
  final String verdict; // '존치' | '벌채'
  final DateTime createdAt;

  const SurveyRecord({
    this.dbId,
    required this.treeId,
    required this.site,
    required this.address,
    this.lat,
    this.lon,
    required this.species,
    required this.dbhCm,
    this.heightM = double.nan,
    this.sootMaxM = double.nan,
    this.rawDir,
    this.memo = '',
    required this.modelName,
    this.poleLengthM = 3.0,
    this.poleGapM = 1.0,
    required this.faces,
    this.bsi = double.nan,
    this.mortalityProb = double.nan,
    this.verdict = '',
    required this.createdAt,
  });

  /// [clearGps]가 참이면 lat/lon을 null로 지운다 — `lat ?? this.lat` 방식으로는
  /// 한 번 들어간 좌표를 지울 방법이 없기 때문.
  SurveyRecord copyWith({
    int? dbId,
    double? lat,
    double? lon,
    bool clearGps = false,
    String? species,
    double? dbhCm,
    double? heightM,
    double? sootMaxM,
    List<AzimuthResult>? faces,
    double? bsi,
    double? mortalityProb,
    String? verdict,
  }) =>
      SurveyRecord(
        dbId: dbId ?? this.dbId,
        treeId: treeId,
        site: site,
        address: address,
        lat: clearGps ? null : lat ?? this.lat,
        lon: clearGps ? null : lon ?? this.lon,
        species: species ?? this.species,
        dbhCm: dbhCm ?? this.dbhCm,
        heightM: heightM ?? this.heightM,
        sootMaxM: sootMaxM ?? this.sootMaxM,
        rawDir: rawDir,
        memo: memo,
        modelName: modelName,
        poleLengthM: poleLengthM,
        poleGapM: poleGapM,
        faces: faces ?? this.faces,
        bsi: bsi ?? this.bsi,
        mortalityProb: mortalityProb ?? this.mortalityProb,
        verdict: verdict ?? this.verdict,
        createdAt: createdAt,
      );

  double _maxOf(double Function(AzimuthResult) pick) {
    double best = double.nan;
    for (final f in faces) {
      final v = pick(f);
      if (v.isNaN) continue;
      if (best.isNaN || v > best) best = v;
    }
    return best;
  }

  /// 화면·CSV가 쓰는 유효 수고: 수정값이 있으면 그것, 없으면 방위별 최대.
  double get effectiveHeightM =>
      heightM.isNaN ? _maxOf((f) => f.visibleStemHeightM) : heightM;

  /// 화면·CSV가 쓰는 유효 그을음 최고 높이.
  double get effectiveSootMaxM =>
      sootMaxM.isNaN ? _maxOf((f) => f.sootHeightM) : sootMaxM;

  Map<String, dynamic> toMap() => {
        if (dbId != null) 'id': dbId,
        'treeId': treeId,
        'site': site,
        'address': address,
        'lat': lat,
        'lon': lon,
        'species': species,
        'dbhCm': dbhCm,
        'heightM': _n(heightM),
        'sootMaxM': _n(sootMaxM),
        'rawDir': rawDir,
        'memo': memo,
        'modelName': modelName,
        'poleLengthM': poleLengthM,
        'poleGapM': poleGapM,
        'faces': jsonEncode(faces.map((f) => f.toJson()).toList()),
        'bsi': _n(bsi),
        'mortalityProb': _n(mortalityProb),
        'verdict': verdict,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SurveyRecord.fromMap(Map<String, dynamic> m) => SurveyRecord(
        dbId: m['id'] as int?,
        treeId: m['treeId'] as String,
        site: m['site'] as String? ?? '',
        address: m['address'] as String? ?? '',
        lat: (m['lat'] as num?)?.toDouble(),
        lon: (m['lon'] as num?)?.toDouble(),
        species: m['species'] as String? ?? '',
        dbhCm: (m['dbhCm'] as num?)?.toDouble() ?? 0,
        heightM: (m['heightM'] as num?)?.toDouble() ?? double.nan,
        sootMaxM: (m['sootMaxM'] as num?)?.toDouble() ?? double.nan,
        rawDir: m['rawDir'] as String?,
        memo: m['memo'] as String? ?? '',
        modelName: m['modelName'] as String? ?? '',
        poleLengthM: (m['poleLengthM'] as num?)?.toDouble() ?? 3.0,
        poleGapM: (m['poleGapM'] as num?)?.toDouble() ?? 1.0,
        faces: ((jsonDecode(m['faces'] as String? ?? '[]')) as List)
            .map((e) => AzimuthResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        bsi: (m['bsi'] as num?)?.toDouble() ?? double.nan,
        mortalityProb: (m['mortalityProb'] as num?)?.toDouble() ?? double.nan,
        verdict: m['verdict'] as String? ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

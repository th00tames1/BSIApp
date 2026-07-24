import 'dart:convert';

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
  final String memo;
  final String modelName;
  final double poleLengthM; // measuring-pole real length used for scale
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
    this.memo = '',
    required this.modelName,
    this.poleLengthM = 3.0,
    required this.faces,
    this.bsi = double.nan,
    this.mortalityProb = double.nan,
    this.verdict = '',
    required this.createdAt,
  });

  SurveyRecord copyWith({
    int? dbId,
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
        lat: lat,
        lon: lon,
        species: species,
        dbhCm: dbhCm,
        memo: memo,
        modelName: modelName,
        poleLengthM: poleLengthM,
        faces: faces ?? this.faces,
        bsi: bsi ?? this.bsi,
        mortalityProb: mortalityProb ?? this.mortalityProb,
        verdict: verdict ?? this.verdict,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        if (dbId != null) 'id': dbId,
        'treeId': treeId,
        'site': site,
        'address': address,
        'lat': lat,
        'lon': lon,
        'species': species,
        'dbhCm': dbhCm,
        'memo': memo,
        'modelName': modelName,
        'poleLengthM': poleLengthM,
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
        memo: m['memo'] as String? ?? '',
        modelName: m['modelName'] as String? ?? '',
        poleLengthM: (m['poleLengthM'] as num?)?.toDouble() ?? 3.0,
        faces: ((jsonDecode(m['faces'] as String? ?? '[]')) as List)
            .map((e) => AzimuthResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        bsi: (m['bsi'] as num?)?.toDouble() ?? double.nan,
        mortalityProb: (m['mortalityProb'] as num?)?.toDouble() ?? double.nan,
        verdict: m['verdict'] as String? ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

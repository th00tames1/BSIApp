/// 한 방위(면)의 분석 조정값.
///
/// 현장에서 자동 분석이 어긋날 때 조사자가 손으로 바로잡는 값들이다.
/// 재분석은 이 값만 있으면 언제든 같은 결과를 다시 만들 수 있어야 하므로
/// 기록(레코드)·원시 번들에 함께 저장한다.
class FaceTuning {
  /// 지표면(밑동) 위치. letterbox 세로 비율 0~1. null이면 마스크에서 자동.
  final double? groundNorm;

  /// 대상목 지정 점(letterbox 0~1). 옆·뒤 나무가 잡힐 때 조사자가 줄기를 찍어
  /// 알려 준다. 이 점을 품는 검출을 우선한다.
  final double? targetX, targetY;

  /// 밝기(-1~1)·대비(0.5~2). 역광·그늘 사진을 보정해 다시 분석할 때 쓴다.
  final double brightness, contrast;

  /// 역광 자동 보정(CLAHE). null이면 사진 밝기를 보고 앱이 판단한다(기본),
  /// true면 항상 적용, false면 끈다.
  final bool? autoTone;

  /// 조사자가 명시적으로 제외한 다각형. 분석의 정사각 letterbox 0~1 좌표.
  final List<List<({double x, double y})>> excludedAreas;

  static const maxExcludedAreas = 16;
  static const maxExclusionPoints = 64;

  const FaceTuning({
    this.groundNorm,
    this.targetX,
    this.targetY,
    this.brightness = 0,
    this.contrast = 1,
    this.autoTone,
    this.excludedAreas = const [],
  });

  static const FaceTuning none = FaceTuning();

  bool get isDefault =>
      groundNorm == null &&
      targetX == null &&
      targetY == null &&
      brightness == 0 &&
      contrast == 1 &&
      autoTone == null &&
      excludedAreas.isEmpty;

  bool get adjustsImage => brightness != 0 || contrast != 1;

  FaceTuning copyWith({
    double? groundNorm,
    bool clearGround = false,
    double? targetX,
    double? targetY,
    bool clearTarget = false,
    double? brightness,
    double? contrast,
    bool? autoTone,
    bool clearAutoTone = false,
    List<List<({double x, double y})>>? excludedAreas,
  }) => FaceTuning(
    groundNorm: clearGround ? null : (groundNorm ?? this.groundNorm),
    targetX: clearTarget ? null : (targetX ?? this.targetX),
    targetY: clearTarget ? null : (targetY ?? this.targetY),
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    autoTone: clearAutoTone ? null : (autoTone ?? this.autoTone),
    excludedAreas: excludedAreas == null
        ? this.excludedAreas
        : validatedExcludedAreas(excludedAreas),
  );

  Map<String, dynamic> toJson() => {
    if (groundNorm != null) 'groundNorm': groundNorm,
    if (targetX != null) 'targetX': targetX,
    if (targetY != null) 'targetY': targetY,
    if (brightness != 0) 'brightness': brightness,
    if (contrast != 1) 'contrast': contrast,
    if (autoTone != null) 'autoTone': autoTone,
    if (excludedAreas.isNotEmpty)
      'excludedAreas': validatedExcludedAreas(
        excludedAreas,
      ).map((area) => area.map((p) => {'x': p.x, 'y': p.y}).toList()).toList(),
  };

  factory FaceTuning.fromJson(Map<String, dynamic>? j) {
    if (j == null) return none;
    return FaceTuning(
      groundNorm: (j['groundNorm'] as num?)?.toDouble(),
      targetX: (j['targetX'] as num?)?.toDouble(),
      targetY: (j['targetY'] as num?)?.toDouble(),
      brightness: (j['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (j['contrast'] as num?)?.toDouble() ?? 1,
      autoTone: j['autoTone'] as bool?,
      excludedAreas: _readExcludedAreas(j['excludedAreas']),
    );
  }

  static List<List<({double x, double y})>> _readExcludedAreas(dynamic raw) {
    if (raw is! List) return const [];
    final areas = <List<({double x, double y})>>[];
    for (final area in raw.take(maxExcludedAreas)) {
      if (area is! List || area.length > maxExclusionPoints) continue;
      final points = <({double x, double y})>[];
      for (final p in area) {
        if (p is! Map || p['x'] is! num || p['y'] is! num) break;
        points.add((
          x: (p['x'] as num).toDouble(),
          y: (p['y'] as num).toDouble(),
        ));
      }
      if (points.length == area.length) areas.add(points);
    }
    return validatedExcludedAreas(areas);
  }

  static List<List<({double x, double y})>> validatedExcludedAreas(
    List<List<({double x, double y})>> areas,
  ) => List.unmodifiable(
    areas
        .take(maxExcludedAreas)
        .where(isValidExcludedArea)
        .map((area) => List<({double x, double y})>.unmodifiable(area)),
  );

  /// 단순 다각형만 허용한다. 교차·일직선·중복 점은 실수로 넓게 지우지 않는다.
  static bool isValidExcludedArea(List<({double x, double y})> area) {
    if (area.length < 3 || area.length > maxExclusionPoints) return false;
    for (final p in area) {
      if (!p.x.isFinite ||
          !p.y.isFinite ||
          p.x < 0 ||
          p.x > 1 ||
          p.y < 0 ||
          p.y > 1) {
        return false;
      }
    }
    if (area.toSet().length != area.length) return false;
    double cross(
      ({double x, double y}) a,
      ({double x, double y}) b,
      ({double x, double y}) c,
    ) => (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    var twiceArea = 0.0;
    for (var i = 0; i < area.length; i++) {
      final a = area[i], b = area[(i + 1) % area.length];
      twiceArea += a.x * b.y - b.x * a.y;
      for (var j = i + 2; j < area.length; j++) {
        if (i == 0 && j == area.length - 1) continue;
        final c = area[j], d = area[(j + 1) % area.length];
        if (cross(a, b, c) * cross(a, b, d) <= 0 &&
            cross(c, d, a) * cross(c, d, b) <= 0 &&
            (a.x < b.x ? a.x : b.x) <= (c.x > d.x ? c.x : d.x) &&
            (c.x < d.x ? c.x : d.x) <= (a.x > b.x ? a.x : b.x) &&
            (a.y < b.y ? a.y : b.y) <= (c.y > d.y ? c.y : d.y) &&
            (c.y < d.y ? c.y : d.y) <= (a.y > b.y ? a.y : b.y)) {
          return false;
        }
      }
    }
    return twiceArea.abs() > 1e-8;
  }
}

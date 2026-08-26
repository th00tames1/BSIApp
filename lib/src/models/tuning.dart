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

  const FaceTuning({
    this.groundNorm,
    this.targetX,
    this.targetY,
    this.brightness = 0,
    this.contrast = 1,
  });

  static const FaceTuning none = FaceTuning();

  bool get isDefault =>
      groundNorm == null &&
      targetX == null &&
      targetY == null &&
      brightness == 0 &&
      contrast == 1;

  bool get adjustsImage => brightness != 0 || contrast != 1;

  FaceTuning copyWith({
    double? groundNorm,
    bool clearGround = false,
    double? targetX,
    double? targetY,
    bool clearTarget = false,
    double? brightness,
    double? contrast,
  }) =>
      FaceTuning(
        groundNorm: clearGround ? null : (groundNorm ?? this.groundNorm),
        targetX: clearTarget ? null : (targetX ?? this.targetX),
        targetY: clearTarget ? null : (targetY ?? this.targetY),
        brightness: brightness ?? this.brightness,
        contrast: contrast ?? this.contrast,
      );

  Map<String, dynamic> toJson() => {
        if (groundNorm != null) 'groundNorm': groundNorm,
        if (targetX != null) 'targetX': targetX,
        if (targetY != null) 'targetY': targetY,
        if (brightness != 0) 'brightness': brightness,
        if (contrast != 1) 'contrast': contrast,
      };

  factory FaceTuning.fromJson(Map<String, dynamic>? j) {
    if (j == null) return none;
    return FaceTuning(
      groundNorm: (j['groundNorm'] as num?)?.toDouble(),
      targetX: (j['targetX'] as num?)?.toDouble(),
      targetY: (j['targetY'] as num?)?.toDouble(),
      brightness: (j['brightness'] as num?)?.toDouble() ?? 0,
      contrast: (j['contrast'] as num?)?.toDouble() ?? 1,
    );
  }
}

import 'dart:math' as math;

/// 촬영 화면 노출 보정 슬라이더의 계산.
///
/// 카메라가 허용하는 노출 보정(하드웨어, 기기마다 대개 ±2 EV)만으로는 역광에서
/// 줄기를 살리기에 모자라 슬라이더를 그 [stretch]배까지 연다. 하드웨어 한계를
/// 넘는 몫은 소프트웨어 밝기로 처리하는데, 미리보기(`ColorFilter.matrix`)와 저장
/// 사진(`PhotoNormalizer.applyGain`)이 **같은 배율**을 써서 보이는 것이 곧
/// 찍히는 것이 되게 한다.
class Exposure {
  Exposure._();

  /// 슬라이더 범위 = 하드웨어 범위 × [stretch].
  static const double stretch = 2.5;

  /// 하드웨어 보정이 없는 기기에서 쓰는 소프트웨어 전용 범위(±EV).
  static const double softwareOnly = 2.5;

  static ({double min, double max}) sliderRange(double hwMin, double hwMax) => (
        min: hwMin < 0 ? hwMin * stretch : -softwareOnly,
        max: hwMax > 0 ? hwMax * stretch : softwareOnly,
      );

  /// 슬라이더 값 중 카메라 하드웨어가 맡는 몫.
  static double hardware(double ev, double hwMin, double hwMax) =>
      hwMax <= hwMin ? 0 : ev.clamp(hwMin, hwMax).toDouble();

  /// 하드웨어 한계를 넘어 소프트웨어가 맡는 몫(EV).
  static double software(double ev, double hwMin, double hwMax) =>
      ev - hardware(ev, hwMin, hwMax);

  /// 소프트웨어 몫(EV)을 sRGB 배율로. 2.2 감마로 나눠 중간 톤에서 1 EV가
  /// 대략 한 스톱이 되게 맞춘다(선형광 2배 ≈ sRGB 1.37배).
  static double gain(double softwareEv) =>
      softwareEv == 0 ? 1.0 : math.pow(2, softwareEv / 2.2).toDouble();
}

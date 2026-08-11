import 'dart:io';

import 'package:flutter/services.dart';

/// 나침반이 가리키는 북쪽의 기준.
enum NorthRef {
  /// 자북 — 자기 나침반이 가리키는 방향. 아날로그 나침반과 맞춰 볼 때.
  magnetic,

  /// 진북 — 지리적 북극. 지도·좌표·임업 야장이 쓰는 기준.
  trueNorth,
}

/// 자기 편각(declination) 조회.
///
/// 편각 = 진북 기준으로 잰 자북의 방위각. 한국은 대략 -7 ~ -9°(자북이 서쪽).
///   진북 = 자북 + 편각,   자북 = 진북 - 편각
///
/// 플랫폼마다 `flutter_compass`가 주는 값의 기준이 다르다는 점이 중요하다.
///   Android : 회전벡터 센서의 방위각 그대로 = **자북**(편각 미보정)
///   iOS     : `CLHeading.trueHeading` = **진북**
/// 그래서 같은 코드가 두 기기에서 다른 북쪽을 가리키고 있었다. 아래
/// [toDisplay]가 그 차이를 흡수한다.
class Geomag {
  Geomag._();

  static const _ch = MethodChannel('bsi/geomag');

  /// 마지막으로 구한 편각(도). 위치를 얻기 전에는 null.
  static double? declinationDeg;

  /// 이 기기에서 편각을 알 수 있는지. Android는 OS가 `GeomagneticField`로
  /// 정확한 값을 주고, iOS는 제공 경로가 없어 진북만 쓸 수 있다.
  static bool get canResolveDeclination => Platform.isAndroid;

  /// 주어진 좌표의 편각을 갱신한다. 실패하면 값을 건드리지 않는다.
  static Future<double?> update(double lat, double lon) async {
    if (!canResolveDeclination) return declinationDeg;
    try {
      final v = await _ch.invokeMethod<double>('declination', {
        'lat': lat,
        'lon': lon,
      });
      if (v != null && v.isFinite) declinationDeg = v;
    } on PlatformException {
      // 채널이 없거나 실패하면 편각 미상으로 둔다(진북 표시가 그대로 유지된다).
    } on MissingPluginException {
      // 구버전 앱에서 올라온 경우.
    }
    return declinationDeg;
  }

  /// 이 기기에서 [ref] 기준으로 표시할 수 있는지.
  ///
  /// iOS는 센서값이 이미 진북이라 진북은 언제나 가능하지만, 자북으로 되돌리려면
  /// 편각이 필요한데 구할 수 없다.
  static bool supports(NorthRef ref) {
    if (Platform.isAndroid) return true; // 자북이 원본, 편각이 있으면 진북도 가능
    return ref == NorthRef.trueNorth;
  }

  /// `flutter_compass`가 준 [raw] 방위각을 [ref] 기준으로 바꾼다.
  ///
  /// 편각을 모르면 변환 없이 원본을 돌려준다(잘못된 보정보다 낫다).
  static double? toDisplay(double? raw, NorthRef ref) {
    if (raw == null) return null;
    final dec = declinationDeg;
    if (Platform.isIOS) {
      // 원본이 진북.
      if (ref == NorthRef.trueNorth || dec == null) return _wrap(raw);
      return _wrap(raw - dec);
    }
    // Android — 원본이 자북.
    if (ref == NorthRef.magnetic || dec == null) return _wrap(raw);
    return _wrap(raw + dec);
  }

  /// [ref]로 실제 표시되고 있는 기준. 편각을 몰라 보정하지 못하면 원본 기준을
  /// 돌려준다. 화면 라벨이 거짓말하지 않게 하려는 것.
  static NorthRef effective(NorthRef ref) {
    if (declinationDeg != null) return ref;
    return Platform.isIOS ? NorthRef.trueNorth : NorthRef.magnetic;
  }

  static double _wrap(double deg) {
    final v = deg % 360;
    return v < 0 ? v + 360 : v;
  }
}

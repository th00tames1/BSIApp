import 'package:geolocator/geolocator.dart';

/// Outcome of a location readiness check — lets the UI say *why* GPS failed
/// instead of silently returning null.
enum GpsStatus { ok, serviceOff, denied, deniedForever }

class LocationService {
  /// Ensure the device location service is on and permission is granted.
  /// Uses geolocator's own permission API (avoids permission_handler mismatch).
  static Future<GpsStatus> ensure() async {
    if (!await Geolocator.isLocationServiceEnabled()) return GpsStatus.serviceOff;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return GpsStatus.deniedForever;
    if (perm == LocationPermission.denied) return GpsStatus.denied;
    return GpsStatus.ok; // whileInUse or always
  }

  /// One-off best-effort fix (manual fallback in 등록). Null on any failure.
  static Future<Position?> current() async {
    try {
      if (await ensure() != GpsStatus.ok) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      // getCurrentPosition can throw on timeout — fall back to last known,
      // but only if recent enough to not be a stale point from another tree.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return null;
        return DateTime.now().difference(last.timestamp).inMinutes < 2 ? last : null;
      } catch (_) {
        return null;
      }
    }
  }

  /// Continuous high-accuracy fixes while the 촬영 screen is open, so each
  /// azimuth shot can be tagged with the surveyor's standpoint.
  static Stream<Position> stream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      );

  static String message(GpsStatus s) => switch (s) {
        GpsStatus.ok => '',
        GpsStatus.serviceOff => '기기 위치 서비스가 꺼져 있습니다',
        GpsStatus.denied => '위치 권한이 거부되었습니다',
        GpsStatus.deniedForever => '위치 권한이 영구 거부됨 · 설정에서 허용하세요',
      };
}

import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  /// Best-effort GPS fix; returns null if unavailable or denied.
  static Future<Position?> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

package com.bsi.bsi_field

import android.hardware.GeomagneticField
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 자기 편각(진북 - 자북). OS가 IGRF 모델로 계산해 주므로 앱이 표를 들고
        // 있을 필요가 없고 오프라인에서도 동작한다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bsi/geomag")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "declination" -> {
                        val lat = call.argument<Double>("lat")
                        val lon = call.argument<Double>("lon")
                        if (lat == null || lon == null) {
                            result.error("ARG", "lat/lon required", null)
                        } else {
                            val f = GeomagneticField(
                                lat.toFloat(),
                                lon.toFloat(),
                                0f,
                                System.currentTimeMillis()
                            )
                            result.success(f.declination.toDouble())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

package com.bsi.bsi_field

import android.content.Intent
import android.hardware.GeomagneticField
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
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
        // 앱 안 업데이트. 같은 키로 서명된 APK면 기록을 지키며 덮어 설치된다.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bsi/update")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                    // 안드로이드 8+는 앱마다 "출처를 알 수 없는 앱 설치"를 허용받아야 한다
                    "canInstall" -> result.success(
                        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls()
                    )
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        }
                        result.success(null)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("ARG", "path required", null)
                        } else {
                            try {
                                val uri = FileProvider.getUriForFile(
                                    this, "$packageName.updates", java.io.File(path)
                                )
                                startActivity(
                                    Intent(Intent.ACTION_VIEW)
                                        .setDataAndType(uri, "application/vnd.android.package-archive")
                                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                )
                                result.success(null)
                            } catch (e: Exception) {
                                result.error("INSTALL", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}

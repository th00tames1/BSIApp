import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 배포용 서명. 앱 안 업데이트는 **같은 키로 서명된 APK만** 덮어 설치할 수 있으므로
// 배포 APK는 늘 한 키로 서명해야 한다. android/key.properties(저장소에 올리지 않는다 —
// .gitignore)가 있으면 그 키를, 없으면 이 컴퓨터의 디버그 키를 쓴다(개발·시험용).
// GitHub Actions 릴리스는 저장소 Secrets에서 이 파일을 만들어 빌드한다(SETUP.md 참고).
val releaseKey = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

val flutterAbiByTarget = mapOf(
    "android-arm" to "armeabi-v7a",
    "android-arm64" to "arm64-v8a",
    "android-x64" to "x86_64",
)
val nativeAbis = (project.findProperty("target-platform") as? String)
    ?.split(",")
    ?.mapNotNull(flutterAbiByTarget::get)
    .orEmpty()

android {
    namespace = "com.bsi.bsi_field"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // BSI_app2 — 연구원 폰에 이미 기록이 든 BSI_app(com.bsi.bsi_field)과 **다른 앱**으로
        // 설치된다(덮어쓰지 않고 나란히). 코드 패키지(namespace)는 그대로 둔다.
        applicationId = "com.bsi.bsi_field2"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                abiFilters += nativeAbis
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (!releaseKey.isEmpty) {
            create("release") {
                storeFile = rootProject.file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseKey.isEmpty) signingConfigs.getByName("debug")
            else signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

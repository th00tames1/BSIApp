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
        applicationId = "com.bsi.bsi_field"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
            // R8 축소는 Flutter 기본값대로 켜 두되, ONNX Runtime(JNI) keep 규칙을
            // 반드시 포함한다 — 없으면 릴리스 빌드가 분석 시작 직후 죽는다.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

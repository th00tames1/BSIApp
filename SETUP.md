# 설치 및 실행 가이드

다른 컴퓨터에서 GitHub 클론만으로 BSI_app 앱을 빌드·실행하기 위한 문서다.
**AI 모델과 예시 사진이 저장소에 함께 들어 있으므로 별도 내려받기 없이 전체 분석이 동작한다.**

- 저장소 : `https://github.com/th00tames1/BSIApp`
- 기본 브랜치 : **`work`** (클론하면 자동으로 이 브랜치를 받는다)
- 클론 용량 : 약 **90 MB** (모델 79 MB · 글꼴 5 MB · 예시 사진 2.4 MB)

앱의 기능·구조 설명은 [README.md](README.md)를 참고한다. 이 문서는 설치·실행만 다룬다.

---

## 1. 사전 준비

| 항목 | 버전 | 비고 |
|---|---|---|
| Flutter SDK | **3.35.4** (Dart 3.9.2) | stable 채널 |
| JDK | **17** | Android Studio 내장 JDK로 충분 |
| Android SDK | **Platform 36** · Build-Tools 35 | compileSdk 36 · minSdk 24 · targetSdk 34 |
| Xcode | 15 이상 | iOS 빌드 시에만 필요 (macOS) |

```bash
flutter --version
flutter doctor
```

`flutter doctor`에서 Android toolchain 항목에 체크가 떠야 한다.
`cmdline-tools component is missing`가 뜨면 Android Studio → **SDK Manager → SDK Tools → Android SDK Command-line Tools** 를 설치한 뒤
`flutter doctor --android-licenses`로 라이선스에 모두 동의한다.

---

## 2. 클론

> ⚠️ **경로에 한글이 들어가면 Gradle 빌드가 실패한다** (`Your project path contains non-ASCII characters`).
> `C:\dev\` 처럼 영문·숫자로만 된 경로에 클론할 것.

```bash
git clone https://github.com/th00tames1/BSIApp.git
```

```bash
cd BSIApp && git branch --show-current
```

`work`가 출력되면 정상이다. 이력이 필요 없으면 `git clone --depth 1 ...` 로 받아도 된다.

클론 직후 아래 파일이 있는지 확인한다. 없으면 분석이 동작하지 않는다.

```bash
ls -lh assets/models assets/sample
```

- `assets/models/bsi_seg_yolo26s_640.onnx` — 수간·그을음 분할 (41.8 MB)
- `assets/models/pole_boundary_640.onnx` — 수고봉 1 m 경계 검출 (38.1 MB)
- `assets/sample/demo_N.jpg` · `demo_E.jpg` · `demo_S.jpg` · `demo_W.jpg` — 시험용 4방위 사진

---

## 3. 의존성 설치 및 테스트

```bash
flutter pub get
```

```bash
flutter test
```

**103건 전부 통과해야 한다.** 수고봉 스케일 환산·경계 간격, 검출 결과 디코딩,
기기 독립성, 입력 해상도 정규화, 흉고직경 기반 스케일, 대상목 선택(옆·뒤 나무),
지표면 지정, 밝기·대비·역광 자동 보정, 그을음 검출 임계값, 통합 BSI 산출, 직접 입력 방위, CSV 열 정합,
BSI 판정표, 경계 파일 임포트를 검증한다.
`54 packages have newer versions incompatible with dependency constraints`는
`pubspec.lock`으로 버전을 고정해 둔 결과이며 정상 메시지다.

---

## 4. 실행

기기 또는 에뮬레이터를 연결한 뒤 목록을 확인한다.

```bash
flutter devices
```

```bash
flutter run
```

APK 파일로 배포하려면 다음과 같이 빌드한다. 첫 빌드는 Gradle 8.12를 내려받으므로 5분 내외 걸린다.

```bash
flutter build apk --debug
```

산출물은 `build/app/outputs/flutter-apk/app-debug.apk` (약 289 MB, 모델 포함)이며
`adb install -r` 로 설치한다.

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

배포용 서명 APK는 `flutter build apk --release` 로 만든다. 별도 키스토어 설정이 없으면 디버그 키로 서명된다.

---

## 5. 동작 확인

카메라나 현장 사진 없이 내장 예시 사진으로 전체 파이프라인을 검증할 수 있다.
시험 메뉴는 개발자 모드에서만 보인다.

1. 앱 실행 → 지도 우하단 **현재 위치 버튼을 2초 안에 7번 연속 탭** → "개발자 모드가 켜졌습니다"
2. 우상단 **설정** 아이콘 → **시험 (개발자)** 섹션의 **예시 사진으로 시험** 선택
   → 내장 4방위 사진으로 **AI 분석이 자동 실행**된다
   (촬영 화면을 거치지 않으므로 카메라 권한도 필요 없다)

아래 값이 나오면 모델 적재부터 판정까지 정상이다.

| 항목 | 기대값 |
|---|---|
| 통합 BSI | **14.5** |
| 흉고직경 (자동 추정) | **35 cm** |
| 고사 확률 | **58 %** |
| 판정 | 벌채 |
| 방위별 그을음 비율 | 동 90 % · 서 92 % · 남 92 % · 북 94 % |

결과 이미지의 계측선 색은 다음과 같다.
흑색 = 나무 밑동 · 청색 = 흉고직경(가슴높이 1.3 m) · 적색 = 그을음 최고 높이 · 황색 원 = 수고봉 1 m 경계.

> 값이 크게 다르거나 BSI가 비어 있으면 수고봉 경계가 검출되지 않은 것이다.
> `assets/models/pole_boundary_640.onnx`가 제대로 클론됐는지 먼저 확인한다.

---

## 6. iOS (macOS 전용)

iOS 빌드는 Xcode가 필요하므로 **macOS에서만 된다.** Windows에는 우회로가 없다.

### 6.1 사전 준비 (사람이 한 번 해야 하는 것)

| 항목 | 방법 | 비고 |
|---|---|---|
| Xcode | App Store에서 설치 | 15 GB 이상, 자동화 불가 |
| 명령줄 도구 | `xcode-select --install` | |
| 라이선스 동의 | `sudo xcodebuild -license accept` | 관리자 암호 필요 |
| CocoaPods | `sudo gem install cocoapods` 또는 `brew install cocoapods` | |
| Flutter SDK | 3.35.4 (stable) | |

```bash
flutter doctor
```

Xcode 항목에 체크가 떠야 다음으로 넘어간다.

### 6.2 시뮬레이터 — 서명 없이 여기까지 됨

```bash
git clone https://github.com/th00tames1/BSIApp.git && cd BSIApp
```

```bash
flutter pub get && cd ios && pod install && cd ..
```

```bash
open -a Simulator && flutter run
```

**서명 설정 없이 시뮬레이터에서 실행된다.** 빌드가 통과하는지, 분석이 도는지는
여기까지로 확인할 수 있다. 컴파일만 확인하려면 `flutter build ios --simulator`.

시뮬레이터에는 카메라·나침반·GPS가 없다. 촬영 화면은 "사용 가능한 카메라가 없습니다"가
정상이고, 분석은 **개발자 모드 → 예시 사진으로 시험**(§5)이나 촬영 화면의 갤러리
불러오기로 확인한다. 실기기에서는 Android와 같은 경로를 탄다 — 촬영 사진은 기기와
무관하게 긴 변 2560·회전 적용·EXIF 없는 JPEG로 저장되고, 분석은 예시 사진과 동일한
파이프라인(1280 정규화 → 640 letterbox)을 거친다. iOS 나침반은 OS가 진북을 주므로
**진북 고정**이며(자북 선택 불가), 카메라 권한은 `ios/Podfile`의
`PERMISSION_CAMERA=1` 매크로로 켜져 있다(`pod install` 시 자동 반영).

Apple Silicon 시뮬레이터도 정상이다 — `flutter_onnxruntime`의 podspec이 제외하는
아키텍처는 `i386` 뿐이다.

### 6.3 실기기 · 배포 — 여기서부터 Apple ID가 필요하다

`DEVELOPMENT_TEAM`이 비어 있고 `CODE_SIGN_STYLE = Automatic`이라 **Team을 한 번 골라야 한다.**

1. Xcode → Settings → Accounts → **＋ 로 Apple ID 로그인** (사람이 직접, 암호 입력)
2. `open ios/Runner.xcworkspace` → Runner → Signing & Capabilities → **Team** 선택
3. 이후에는 명령줄로 된다.

```bash
flutter run -d <기기이름>
```

```bash
flutter build ipa
```

- Bundle ID는 `com.bsi.bsiField`다 (Android의 `com.bsi.bsi_field`와 달리 언더스코어가 없다).
  이미 쓰이는 ID면 Xcode에서 바꿔야 한다.
- 무료 Apple ID로도 실기기 설치는 되지만 **7일마다 재설치**해야 하고 TestFlight는 안 된다.
  배포하려면 유료 Apple Developer Program.
- **배포 타깃 16.0은 낮출 수 없다.** `flutter_onnxruntime` 1.8.0이 `onnxruntime-objc 1.24.2`를
  요구하고 podspec이 16.0으로 고정돼 있다.
- 카메라·위치·사진 권한 문구는 `Info.plist`에 이미 한국어로 들어 있다.
- 앱에 ONNX 모델 80 MB가 들어가므로 IPA가 크다. 배포 시 용량을 감안할 것.

### 6.4 AI 도구에게 맡길 때

6.2까지는 그대로 시켜도 된다. **6.3의 Apple ID 로그인은 시키지 말 것** — 계정 암호를
입력하는 단계이므로 직접 하고, Team을 고른 뒤부터 다시 맡기면 된다.

---

## 7. 문제 해결

| 증상 | 원인 및 조치 |
|---|---|
| `Your project path contains non-ASCII characters` | 경로에 한글이 있다. ASCII 경로로 옮겨 다시 클론한다 |
| `cmdline-tools component is missing` | SDK Manager에서 Command-line Tools 설치 후 `flutter doctor --android-licenses` |
| `Failed to install ... INSTALL_FAILED_INSUFFICIENT_STORAGE` | 에뮬레이터 저장 공간 부족. `adb shell pm uninstall com.bsi.bsi_field` 후 `adb shell pm trim-caches 2G` |
| 분할 결과가 비거나 앱이 분석 중 종료 | `assets/models/*.onnx`가 0 바이트이거나 없는 경우다. `git lfs`가 아닌 일반 파일이므로 재클론으로 해결된다 |
| BSI가 산출되지 않음 | 해당 방위에서 수고봉 1 m 경계가 검출되지 않으면 높이(m)를 구할 수 없어 합에서 빠진다. 수고봉이 사진에 온전히 보이도록 재촬영한다 |
| 지도가 회색으로만 보임 | 타일은 온라인에서 받는다. 최초 1회는 네트워크가 필요하며 이후 디스크 캐시로 동작한다 |
| Gradle이 메모리 부족으로 실패 | `android/gradle.properties`의 `org.gradle.jvmargs=-Xmx8G`를 장비에 맞춰 낮춘다 |

---

## 8. 참고 사항

- 앱 ID는 `com.bsi.bsi_field`이다.
- 지도 타일을 제외한 모든 연산은 **온디바이스**로 이뤄지며 서버·API 키가 필요 없다.
- 이 저장소에는 **앱 소스만** 들어 있다. 학습 스크립트·데이터셋·보고서는 포함하지 않는다.
- APK는 저장소에 커밋하지 않는다.

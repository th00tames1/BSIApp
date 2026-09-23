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
- `assets/models/pole_boundary_640.onnx` — 수고봉 경계 검출, 노랑/흰·빨강/흰 2클래스 (38.1 MB)
- `assets/sample/demo_N.jpg` · `demo_E.jpg` · `demo_S.jpg` · `demo_W.jpg` — 시험용 4방위 사진

---

## 3. 의존성 설치 및 테스트

```bash
flutter pub get
```

```bash
flutter test
```

**160건 전부 통과해야 한다**(현장 재현 1건은 환경변수가 없으면 건너뜀). 수고봉 스케일 환산·경계 간격, 검출 결과 디코딩,
기기 독립성, 입력 해상도 정규화, 흉고직경 기반 스케일, 대상목 선택(옆·뒤 나무),
지표면 지정, 밝기·대비·역광 자동 보정, 촬영 노출 확장, 역광 실루엣 판정, 그을음 검출 임계값, 통합 BSI 산출, 직접 입력 방위, CSV 열 정합,
BSI 판정표, 경계 파일 임포트를 검증한다.
`54 packages have newer versions incompatible with dependency constraints`는
`pubspec.lock`으로 버전을 고정해 둔 결과이며 정상 메시지다.

---

### 현장 사진 재현(개발용)

현장에서 받은 원시 번들(개발자 모드 → 기록 → 전체 내보내기 ZIP을 푼 폴더)을 넣으면
**앱의 Dart 분석 코드를 PC에서 그대로** 돌려 "지금 앱이라면 무엇을 냈을지"를 본다.
추론만 `tool/ort_server.py`가 앱과 같은 `.onnx`로 대신한다(`onnxruntime`이 있는 파이썬 필요).

```bash
BSI_FIELD_DIR=<풀어 둔 폴더> BSI_ORT_PY=<python 경로> BSI_GAPS=1.0,0.2 flutter test test/field_replay_test.dart
```

`BSI_FACES=001:E,003:W`처럼 면을 고를 수 있고, `BSI_GAPS`에 수고봉 간격을 여러 개 주면 비교해 준다.

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
흑색 = 나무 밑동 · 청색 = 흉고직경(가슴높이 1.3 m) · 적색 = 그을음 최고 높이 · 황색 원 = 수고봉 경계(노랑 봉 1 m · 빨강/흰 폴 20 cm).

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

## 7. 안드로이드 배포 — 설치 파일과 앱 안 업데이트

앱의 **설정 → 앱 → 앱 업데이트**는 이 저장소의 GitHub 릴리스(최신)를 읽어, 지금보다 새 버전이면
APK를 받아 설치 화면을 연다. 릴리스는 `.github/workflows/release.yml`이 **버전 태그를 올리면**
빌드·서명·게시한다.

> **서명 키가 핵심이다.** 안드로이드는 **같은 키로 서명된 APK만 덮어 설치**한다(기록 유지).
> 키가 다르면 설치 화면이 "앱이 설치되지 않음"으로 거절한다(기존 앱·기록은 안전).
> 그래서 배포 APK는 늘 **저장소 Secrets에 등록한 키 하나**로만 서명한다. 그 키 없이 각
> 컴퓨터에서 `flutter build apk --release`로 만든 APK는 그 컴퓨터의 디버그 키로 서명되므로
> 시험용이다(키가 다른 폰에 덮어 설치되지 않는다).

### 7.1 한 번만: 서명 키 등록 (사람이 직접)

**배포 키 = v0.3.5를 작업자에게 처음 배포할 때 쓴 컴퓨터의 디버그 키**(인증서 SHA-256 `b3d670e9…`,
2026-09-23). 작업자 폰에 이 키로 서명된 앱이 깔리므로 **이후 모든 배포본은 이 키로 서명해야 한다** —
다른 키로 서명하면 앱 업데이트가 "앱이 설치되지 않음"으로 거절된다. 그 컴퓨터의
`%USERPROFILE%\.android\debug.keystore`를 잃으면 같은 키를 다시 만들 수 없으니 **안전한 곳에 사본을 둔다.**
등록은 그 컴퓨터에서:

1. 키가 맞는지 확인 — SHA256이 `B3:D6:70:E9…`로 시작해야 한다.
   ```powershell
   keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android | Select-String "SHA256"
   ```
2. 키 파일을 base64 텍스트로 클립보드에 복사한다.
   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:USERPROFILE\.android\debug.keystore")) | Set-Clipboard
   ```
3. GitHub 저장소 → **Settings → Secrets and variables → Actions → New repository secret**에 등록한다.

   | 이름 | 값 |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | 2에서 복사한 긴 텍스트 |
   | `ANDROID_KEYSTORE_PASSWORD` | `android` |
   | `ANDROID_KEY_ALIAS` | `androiddebugkey` |
   | `ANDROID_KEY_PASSWORD` | `android` |
   | `ANDROID_CERT_SHA256` | `b3d670e91f63a2afa3d388d21292f14b0e571d6d9cb5d7ba2887389446ecbcd9` (넣어 두면 다른 키로 서명된 빌드는 게시 전에 멈춘다) |

키 파일은 **절대 저장소에 커밋하지 않는다**(`android/.gitignore`가 `key.properties`·`*.keystore`·`*.jks`를 막는다).

> 첫 현장 폰(Galaxy S24, 2026-08-26 기록)은 **다른 컴퓨터의 키**(`9F:FB:70:EA…`)로 설치돼 있어 배포본으로 바로
> 업데이트되지 않는다. 한 번만 옮긴다: 그 컴퓨터에서 v0.3.5를 빌드해 덮어 설치(기록 유지) → 설정 → 백업 내보내기 →
> 앱 삭제 → 배포 APK 설치 → 백업 불러오기.

새 키를 따로 만들고 싶다면 `keytool -genkeypair -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000`
으로 만들어 같은 이름으로 등록하면 된다. 다만 **이미 다른 키로 설치된 폰은 한 번 옮겨야 한다**:
설정 → 데이터 → 백업 내보내기 → 앱 삭제 → 새 APK 설치 → 백업 불러오기.

다른 컴퓨터에서도 배포용과 같은 서명으로 직접 빌드하려면 키 파일을 `android/app/upload.keystore`에 두고
`android/key.properties`를 만든다(둘 다 커밋하지 않는다).
```properties
storeFile=app/upload.keystore
storePassword=android
keyAlias=androiddebugkey
keyPassword=android
```

### 7.2 새 버전을 낼 때마다

1. 버전을 올린다 — `pubspec.yaml`의 `version: 0.3.6+12`(뒤 숫자는 매번 +1)와
   `lib/src/services/raw_archive.dart`의 `kAppVersion = '0.3.6'`. 둘이 다르면 배포가 멈춘다.
2. 커밋·푸시한 뒤 태그를 올린다.
   ```bash
   git tag v0.3.6
   ```
   ```bash
   git push origin v0.3.6
   ```
3. GitHub → **Actions**에서 "Android release"가 끝나면(약 10분) **Releases**에
   `bsi_app-v0.3.6-arm64.apk`가 생긴다. 릴리스 설명은 태그가 가리키는 커밋 메시지다
   — 앱의 업데이트 창에 그대로 보이므로 조사자가 읽을 수 있게 쓴다.
4. 폰에서 **설정 → 앱 업데이트**. 처음 한 번은 "이 출처 허용"을 켜라는 설정 화면이 뜬다.

APK는 arm64 전용이다(현장 폰은 모두 arm64 — 크기를 줄이려고 한 ABI만 넣는다).
Actions의 수동 실행(Run workflow)은 빌드·서명 확인만 하고 게시하지 않는다(결과 APK는 Artifacts).

### 7.3 Secrets 없이 직접 올리기

Secrets를 아직 등록하지 않았으면 태그를 올려도 Actions는 빌드를 **건너뛴다**(실패 아님). 그때는 배포 키가 있는
컴퓨터에서 빌드해 릴리스에 직접 첨부한다.

1. 빌드 — `flutter build apk --release --target-platform android-arm64` → `build/app/outputs/flutter-apk/app-release.apk`를
   `bsi_app-v{버전}-arm64.apk`로 이름을 바꾼다(앱 업데이트가 이름의 `arm64`로 기기에 맞는 파일을 고른다).
2. GitHub 저장소 → **Releases → Draft a new release** → 태그 `v{버전}` 선택(없으면 새로 만든다) → 제목·설명 입력
   → 파일을 끌어다 첨부 → **Publish release**. 설명은 앱 업데이트 창에 그대로 보인다.

---

## 8. 문제 해결

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

## 9. 참고 사항

- 앱 ID는 `com.bsi.bsi_field`이다.
- 지도 타일을 제외한 모든 연산은 **온디바이스**로 이뤄지며 서버·API 키가 필요 없다.
- 이 저장소에는 **앱 소스만** 들어 있다. 학습 스크립트·데이터셋·보고서는 포함하지 않는다.
- APK는 저장소에 커밋하지 않는다. 배포 APK는 GitHub 릴리스에만 올린다(7장).

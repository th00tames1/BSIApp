# 설치 및 실행 가이드

다른 컴퓨터에서 GitHub 클론만으로 ReForest 앱을 빌드·실행하기 위한 문서다.
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

**37건 전부 통과해야 한다.** 수고봉 스케일 환산, 검출 결과 디코딩, 기기 독립성,
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

1. 앱 실행 → 우상단 **설정** 아이콘
2. **예시 사진으로 시험** 선택 → 내장 4방위 사진으로 **AI 분석이 자동 실행**된다
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

```bash
cd ios && pod install && cd ..
```

```bash
flutter build ios
```

- **배포 타깃 16.0** 이상이어야 한다 (`flutter_onnxruntime` 요구 사항).
- Xcode → Runner → Signing & Capabilities → **Team** 을 선택해야 실기기 설치가 된다.
- 카메라·위치·사진 권한 문구는 `Info.plist`에 이미 들어 있다.

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

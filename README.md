# 다시숲 (ReForest) — 산불피해목 진단·복원 지원 앱 (bsi_field)

착수보고 v6 설계에 따른 **현장형 스마트폰 BSI 분석 앱**. Flutter(iOS/Android 단일 코드베이스),
**완전 오프라인**(AI 모델 내장), on-device 추론.

조사목 등록 → 4방위 촬영 → AI 분할(수간/그을음) → 수고봉 스케일로 실측 → 4방위 통합 BSI ·
고사 가능성 → 저장/CSV.

## 화면 흐름 (목업과 동일)
1. **조사목 등록** — ID·조사지·위치(GPS)·수종·DBH·메모
2. **사진 촬영** — 동/서/남/북 4방위, 중심 안내선, 플래시
3. **AI 자동 분석** — 수간(빨강)·그을음(초록) 영역 검출, 진행률
4. **분석 결과 확인** — 픽셀스케일·그을음 높이/폭·비율·DBH(추정)·통합 BSI·고사 판정·방위별 비율
5. **결과 저장** — 저장 완료, 결과 사진 보기, CSV 내보내기

## 요구 사항 / 빌드
- Flutter **3.35** (Dart 3.9). `flutter pub get` 후:

### Android
```bash
flutter build apk --release      # 또는 --debug
# 산출물: build/app/outputs/flutter-apk/app-release.apk
flutter install                  # 연결된 기기에 설치
```
minSdk 24 · compileSdk 35. 권한(CAMERA·위치)은 매니페스트에 포함.

### iOS (Mac + Xcode 필요)
```bash
cd ios && pod install && cd ..
flutter build ios                # 또는 Xcode에서 Runner 열고 Run
```
- **iOS 배포 타깃 16.0** (flutter_onnxruntime 요구; Podfile에 설정됨). Xcode General에서 16.0 확인.
- Signing: Xcode → Signing & Capabilities → Team 선택.
- Info.plist에 카메라·위치 권한 문구 포함.

## AI 모델
- 내장 모델: `assets/models/bsi_seg_yolo26s_640.onnx` (YOLO26s-seg @640, 수간=1·그을음=0).
- 디코더는 **두 출력 형식 자동 감지**: YOLO11 dense `[1,4+nc+nm,anchors]` / YOLO26 end2end `[1,nDet,6+nm]`.
- 다른 모델로 교체: `assets/models/`에 `.onnx`를 넣고 `SurveyDraft.modelAsset` 경로 변경(파일명에 `1280`이 있으면 입력 1280으로 인식).
- 엔진: `flutter_onnxruntime`(iOS/Android CPU). 세션은 앱 실행 중 1회 로드·재사용.

## 계측 파이프라인
- 촬영 사진을 640 letterbox → 분할 마스크(프로토 격자) → **수고봉(노란색) 수직 픽셀 길이로 px/m 스케일** 산정
  → 그을음/줄기 span을 미터로 환산. 모든 계측을 letterbox 640 공간에서 수행(수고봉·그을음 span 비율로
  letterbox 스케일이 상쇄되어 실측 정확).
- **BSI = Σ over 4방위 (그을음 높이[m] × 그을음 비율)** (Kwon et al., 2021).
- 고사 가능성: BSI·DBH 로지스틱(오즈비 기반) — `lib/src/services/mortality.dart`.

## ⚠️ 한계 / 교체 지점 (프로토타입 v0.1)
- **수고봉 검출은 휴리스틱**(밝은 노랑 수직 영역). 미검출 시 높이(m)·BSI 산출 불가 → 수동 스케일 입력 UI 보강 필요.
- **고사확률 표는 근사**(Kwon 오즈비 + 절편 피팅). 착수보고 p.20의 정확한 BSI×DBH 표를 CSV로 받으면
  `mortality.dart`를 교체.
- **DBH(추정)** 은 줄기 하부 폭 × (1/px_per_m)의 간이 추정.
- 지도는 오프라인이라 좌표만 표시(타일 없음).
- 온디바이스 추론은 **빌드 검증**됨(APK 생성). 실제 추론 정확도는 실기기에서 확인 필요.

## 구조
```
lib/
├── main.dart                     앱 셸 + 바텀네비(홈/조사/기록/설정)
└── src/
    ├── theme.dart                디자인 토큰(목업 색상)
    ├── widgets.dart              바텀네비·공용 위젯
    ├── models/{survey,draft}.dart
    ├── services/
    │   ├── onnx_service.dart      ORT 세션·추론
    │   ├── seg_decoder.dart       두 형식 디코더 + BSP + 수고봉 검출
    │   ├── image_ops.dart         letterbox·CHW·오버레이 렌더
    │   ├── analysis_service.dart  방위별 분석 + 통합 BSI
    │   ├── mortality.dart         BSI×DBH 고사확률
    │   ├── db_service.dart        sqflite 저장
    │   ├── csv_export.dart        CSV + 공유
    │   └── location_service.dart  GPS
    └── screens/                   home·register·capture·analysis·result·saved·records·settings
```

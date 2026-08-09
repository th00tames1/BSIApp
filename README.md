# ReForest — 산불피해목 진단·복원 지원 앱 (bsi_field)

산불 피해 소나무의 **수피 그을음 비율(BSI)** 을 현장에서 측정하고 존치/벌채를 판정하는
Flutter 앱(iOS/Android 단일 코드베이스). 분할 모델을 앱에 내장해 **네트워크 없이 온디바이스로 추론**한다
(지도 타일만 온라인, 한 번 본 영역은 디스크 캐시).

프로젝트(조사지) 등록 → 지도에서 조사목 추가 → 4방위 촬영 → AI 분할(수간/그을음) →
수고봉 스케일로 실측 → 4방위 통합 BSI · 고사 확률 → 저장 / CSV.

> 다른 장비에서 처음 받아 실행한다면 **[SETUP.md](SETUP.md)** 를 먼저 볼 것.
> 클론부터 빌드·동작 확인까지의 절차와 문제 해결을 정리해 두었다.

## 화면 흐름

1. **지도(홈)** — 일반/위성(하이브리드) 배경지도, 판정색 핀(존치=초록·벌채=빨강)에 조사목 번호 라벨,
   조사지 경계 오버레이, 내 위치, 진행 중 조사 "이어하기" 배너
2. **프로젝트** — 조사지명·위치·시작 번호를 한 번만 등록. 여러 프로젝트를 만들고 전환·수정·삭제
3. **촬영** — 동/서/남/북 4방위. 실시간 나침반, 수고봉 정렬선, 방위별 GPS 입지 태깅,
   갤러리에서 기존 사진 불러오기
4. **AI 분석** — 수간(빨강)·그을음(초록) 분할, 방위별 진행률과 오버레이 미리보기
5. **결과** — 고사확률 게이지에 BSI를 함께 표시, 방위별 비율, 그을음 높이/폭,
   수간 폭 기반 **흉고직경 자동 추정**(실측값 입력 시 실측값 우선 · 판정 재계산)
6. **기록** — 목록·상세·삭제·CSV 내보내기(단건/전체)

## 요구 사항 / 빌드

Flutter **3.35** (Dart 3.9). `flutter pub get` 후:

### Android
```bash
flutter build apk --debug
```
minSdk 24 · compileSdk 36 · targetSdk 34. 권한(카메라·위치·인터넷)은 매니페스트에 포함.

> ⚠️ 프로젝트 경로에 **한글이 있으면 Gradle 빌드가 실패**한다(`non-ASCII characters`).
> ASCII 경로에서 빌드할 것.

### iOS (Mac + Xcode 필요)
```bash
cd ios && pod install && cd ..
flutter build ios
```
- **iOS 배포 타깃 16.0** (flutter_onnxruntime 요구).
- Signing: Xcode → Signing & Capabilities → Team 선택.
- Info.plist에 카메라·위치·사진 권한 문구 포함.

### 테스트
```bash
flutter test
```
37건. 수고봉 스케일 환산·검출 결과 디코딩·기기 독립성, BSI 판정표,
경계 파일 임포트(SHP 바이너리 파싱, 좌표계 판별/재투영, KML/GeoJSON)를 검증한다.

## AI 모델

두 모델을 함께 내장하며 저장소에 포함돼 있다(별도 내려받기 불필요).

- **분할**: `assets/models/bsi_seg_yolo26s_640.onnx` (YOLO26s-seg @640, 수간=1 · 그을음=0)
- **수고봉**: `assets/models/pole_boundary_640.onnx` (YOLO26s @640, 1 m 경계점 검출)
- 디코더는 **두 출력 형식 자동 감지**: YOLO11 dense `[1,4+nc+nm,anchors]` / YOLO26 end2end `[1,nDet,6+nm]`
- 교체: `assets/models/`에 `.onnx`를 넣고 `SurveyDraft.modelAsset` 변경(파일명에 `1280`이 있으면 입력 1280)
- 엔진: `flutter_onnxruntime`(iOS/Android CPU). 세션은 실행 중 1회 로드·재사용

## 계측 파이프라인

- 사진을 640 letterbox → 분할 마스크(프로토 격자) → **수고봉 수직 픽셀 길이로 px/m 스케일** 산정
  → 그을음/줄기 span을 미터로 환산. 모든 계측을 letterbox 640 공간에서 수행하므로 letterbox 스케일이 상쇄된다
- **BSI = Σ over 4방위 (그을음 높이[m] × 그을음 비율)** (Kwon et al., 2021)
- 그을음 비율은 두 가지를 함께 기록: `R_below`(그을음 최대 높이 이하 구간, 야장 정의) · `R_whole`(수간 전체)
- 고사 확률: BSI·DBH 로지스틱 — `lib/src/services/mortality.dart`

## 조사지 경계 불러오기

지도 → 레이어 → **경계 파일 불러오기**

- **SHP**: `.shp` + `.prj`를 함께 선택하거나 `.zip` 번들. `.prj`로 좌표계를 자동 판별하고
  (중부/서부/동부/동해원점, UTM-K, 보정 중부원점, WGS84 UTM 51N/52N) WGS84로 재투영한다.
  판별할 수 없으면 **추측하지 않고 좌표계를 직접 선택**하도록 묻는다
- **KML / KMZ**, **GeoJSON**: 그대로 사용(WGS84)

## ⚠️ 한계 / 교체 지점 (v0.1)

- **수고봉이 검출되지 않으면 그 방위의 높이(m)를 못 구해 BSI 합에서 빠진다**(BSI 자체가 비어질 수 있음).
  수고봉이 사진에 온전히 보이도록 촬영해야 한다
- **고사확률 계수는 근사**(Kwon 오즈비 + 절편 피팅). 정확한 BSI×DBH 표를 받으면 `mortality.dart` 교체
- **DBH(추정)** 은 가슴높이 1.3 m 지점의 수간 폭 × (1/px_per_m)로 산출한다.
  결과 화면에서 실측값을 입력하면 실측값이 우선하며 판정이 재계산된다
- 갤러리에서 불러온 사진은 촬영 지점 GPS가 없어 지도 핀이 생기지 않을 수 있다
- 한국어 UI 고정(영문 전환 미구현)

## 구조

```
lib/
├── main.dart                       테마·라우트 셸 (홈 = 지도)
└── src/
    ├── theme.dart                  디자인 토큰(AppPalette, 라이트/다크) + Azimuth
    ├── app_prefs.dart              프로젝트 목록·활성 프로젝트·설정·진행 중 조사(영속)
    ├── models/
    │   ├── survey.dart             AzimuthResult · SurveyRecord (DB/JSON)
    │   ├── draft.dart              조사 진행 상태 + GPS centroid + 재개 직렬화
    │   └── geo_shape.dart          경계 도형(WGS84)
    ├── services/
    │   ├── onnx_service.dart       ORT 세션·추론
    │   ├── seg_decoder.dart        두 형식 디코더 + BSP + 수고봉 스케일
    │   ├── image_ops.dart          letterbox·CHW·오버레이 렌더
    │   ├── analysis_service.dart   방위별 분석 + 통합 BSI
    │   ├── mortality.dart          BSI×DBH 고사확률
    │   ├── db_service.dart         sqflite 저장
    │   ├── csv_export.dart         CSV + 공유
    │   ├── location_service.dart   GPS
    │   ├── geo_import.dart         SHP/KML/KMZ/GeoJSON + 좌표계 재투영
    │   ├── overlay_store.dart      프로젝트별 경계 저장
    │   └── tile_cache.dart         지도 타일 디스크 캐시
    └── screens/                    map · projects · register(Project) · capture ·
                                    analysis · result · saved · records · settings · about
```

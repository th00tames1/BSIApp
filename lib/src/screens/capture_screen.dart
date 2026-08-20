import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../models/draft.dart';
import '../services/demo_sample.dart';
import '../services/geomag.dart';
import '../services/location_service.dart';
import '../services/photo_normalizer.dart';
import '../services/raw_archive.dart';
import '../theme.dart';
import 'analysis_screen.dart';

class CaptureScreen extends StatefulWidget {
  final SurveyDraft draft;
  const CaptureScreen({super.key, required this.draft});
  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initing = true;
  bool _camStarting = false; // 초기화 중복 진입 방지 (권한 대화상자의 resume이 재호출함)
  String? _error;
  Azimuth _selected = Azimuth.north;
  bool _busy = false;
  final _picker = ImagePicker();

  /// 촬영 후 백그라운드로 도는 저장 작업(정규화·원본 보관). 셔터는 즉시
  /// 다음 방위로 넘어가고, AI 분석 진입 때만 완료를 기다린다.
  final List<Future<void>> _pendingShots = [];

  /// 시연 모드: 카메라 대신 예시 사진을 뷰파인더처럼 띄우고 자동 "촬영"한다.
  late final bool _demo = demoMode.value && d.photos.isEmpty;
  bool _flash = false; // 셔터 순간의 화면 플래시

  // GPS: tagged onto each shot (silently) so the tree gets a map coordinate.
  StreamSubscription<Position>? _posSub;
  final List<Position> _buf = []; // recent fixes, for dwell-averaging each shot
  Position? _here; // 화면에 띄우는 현재 좌표(가장 최근 픽스)

  // Real device compass.
  StreamSubscription<CompassEvent>? _compassSub;
  double? _heading;

  // 안내 문구. SnackBar 를 쓰면 하단의 AI 분석 버튼을 덮어 누르기 어려워서
  // 화면 위쪽에 잠깐 띄운다.
  String? _notice;
  Timer? _noticeTimer;

  void _showNotice(String msg, {int ms = 2200}) {
    _noticeTimer?.cancel();
    if (!mounted) return;
    setState(() => _notice = msg);
    _noticeTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  static const _navy = Color(0xFF16294A);
  static const _soot = Color(0xFF35A853);
  static const _pole = Color(0xFFF6C518);

  SurveyDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start (or resume) at the first azimuth still needed, going clockwise.
    _selected = _clockwise.firstWhere((a) => !d.photos.containsKey(a),
        orElse: () => Azimuth.north);
    // 시연 모드는 카메라를 아예 쓰지 않으므로 권한 요청도 화면에 안 나온다.
    if (_demo) {
      _initing = false;
      _runDemoCapture();
    } else {
      _initCamera();
    }
    _startGps();
    _startCompass();
    // 상시 배지 대신 진입 시 한 번만 안내하고 사라진다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNotice(
          tr('수고봉이 화면에 보이게 촬영해 주세요',
              'Keep the measuring pole in frame when shooting'),
          ms: 3200);
    });
  }

  /// 영상 촬영용 자동 시연. 방위마다 예시 사진이 뷰파인더에 뜨고, 잠시 뒤
  /// 플래시와 함께 "촬영"된다. 4방위가 채워지면 AI 분석으로 넘어간다.
  Future<void> _runDemoCapture() async {
    // 시연 기록도 지도에 찍히도록 현재 위치를 나무 좌표로 쓴다(영상 촬영용).
    // 촬영 시퀀스와 병렬로 잡고, 분석 진입을 오래 막지 않게 5초까지만 기다린다.
    final fix = LocationService.current();
    await Future.delayed(const Duration(milliseconds: 1600)); // 화면 정착 대기
    for (final a in _clockwise) {
      if (!mounted) return;
      setState(() => _selected = a); // 뷰파인더가 이 방위의 나무 사진으로 바뀐다
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      setState(() => _flash = true); // 셔터 플래시
      await Future.delayed(const Duration(milliseconds: 140));
      final dest = await DemoSample.photoFor(a, d.treeId);
      if (!mounted) return;
      d.photos[a] = dest;
      saveDraftJson(d.toJsonString());
      setState(() => _flash = false);
      await Future.delayed(const Duration(milliseconds: 700));
    }
    final pos =
        await fix.timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (pos != null) {
      d.lat = pos.latitude;
      d.lon = pos.longitude;
      saveDraftJson(d.toJsonString());
    }
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));
    _goAnalyse();
  }

  void _startCompass() {
    _compassSub = FlutterCompass.events?.listen((e) {
      if (mounted) setState(() => _heading = e.heading);
    });
  }

  Future<void> _startGps() async {
    await _posSub?.cancel();
    _posSub = null;
    if (await LocationService.ensure() != GpsStatus.ok) return;
    _posSub = LocationService.stream().listen(
      (p) {
        if (!mounted) return;
        _buf.add(p);
        final cutoff = DateTime.now().subtract(const Duration(seconds: 6));
        _buf.removeWhere((x) => x.timestamp.isBefore(cutoff));
        setState(() => _here = p); // 화면 상단 좌표 표시용
        // 편각은 위치에 따라 달라진다. 조사지 안에서는 거의 변하지 않으므로
        // 첫 픽스에서 한 번만 구한다.
        if (Geomag.declinationDeg == null) {
          Geomag.update(p.latitude, p.longitude).then((_) {
            if (mounted) setState(() {});
          });
        }
      },
      onError: (_) {},
      cancelOnError: true,
    );
  }

  /// 좌표를 클립보드로. 지도 앱 검색창이나 야장에 그대로 붙여 넣는다.
  Future<void> _copyCoords() async {
    final h = _here;
    if (h == null) return;
    final s = '${h.latitude.toStringAsFixed(6)}, ${h.longitude.toStringAsFixed(6)}';
    await Clipboard.setData(ClipboardData(text: s));
    _showNotice(tr('좌표를 복사했습니다 · $s', 'Coordinates copied · $s'));
  }

  /// 나침반을 누르면 진북 ↔ 자북. 편각을 모르는 기기에서는 바꿔도 표시가
  /// 달라지지 않으므로 그 사실을 알려 준다.
  void _toggleNorthRef() {
    final want = northRef.value == NorthRef.trueNorth
        ? NorthRef.magnetic
        : NorthRef.trueNorth;
    setNorthRef(want);
    final shown = Geomag.effective(want);
    if (shown != want) {
      _showNotice(tr('이 기기에서는 편각을 알 수 없어 ${_refName(shown)} 기준으로 표시합니다',
          'Declination unavailable on this device — showing ${_refName(shown)}'));
      return;
    }
    final dec = Geomag.declinationDeg;
    _showNotice(want == NorthRef.trueNorth
        ? tr('진북 기준${dec == null ? '' : ' (편각 ${dec.toStringAsFixed(1)}°)'}',
            'True north${dec == null ? '' : ' (declination ${dec.toStringAsFixed(1)}°)'}')
        : tr('자북 기준', 'Magnetic north'));
  }

  String _refName(NorthRef r) =>
      r == NorthRef.trueNorth ? tr('진북', 'true north') : tr('자북', 'magnetic north');

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _noticeTimer?.cancel();
    _posSub?.cancel();
    _compassSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      // Re-persist before the OS can kill us in the background.
      if (d.isInProgress) saveDraftJson(d.toJsonString());
      _posSub?.cancel();
      _posSub = null;
      _buf.clear();
      _compassSub?.cancel();
      _compassSub = null;
      if (c != null && c.value.isInitialized) {
        _controller = null; // avoid using a disposed controller in _preview()
        c.dispose();
      }
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_camStarting && !_demo) _initCamera();
      if (_posSub == null) _startGps();
      if (_compassSub == null) _startCompass();
    }
  }

  Future<void> _initCamera() async {
    if (_camStarting) return;
    _camStarting = true;
    setState(() {
      _initing = true;
      _error = null;
    });
    try {
      // Android: 권한은 컨트롤러 생성 전에 직접 요청한다. initialize() 도중에
      // 권한 대화상자가 뜨면 resume 시 초기화가 겹쳐 플러그인이 null 오류로 죽는다.
      // iOS: camera 플러그인이 초기화 중 스스로 요청한다. permission_handler는
      // Podfile 매크로가 없으면 묻지도 않고 "거부"를 돌려주므로 여기서 쓰지 않는다.
      if (Platform.isAndroid) {
        final st = await Permission.camera.request();
        if (!st.isGranted) {
          throw StateError(
              tr('카메라 권한이 필요합니다', 'Camera permission is required'));
        }
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError(tr('사용 가능한 카메라가 없습니다', 'No camera available'));
      }
      // max = 센서 최대 해상도(대개 4:3) — 예시 사진과 같은 비율로 찍힌다.
      final controller = CameraController(cameras.first, ResolutionPreset.max,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _initing = false;
      });
    } finally {
      _camStarting = false;
    }
  }

  Future<Directory> _photoDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(dir.path, 'photos'));
    if (!destDir.existsSync()) destDir.createSync(recursive: true);
    return destDir;
  }

  /// 조사자는 나무를 돌면서 찍으므로 다음 방위는 **시계방향으로 가장 가까운
  /// 미촬영 방위**다. (enum 선언 순서 E·W·S·N 를 쓰면 동→서처럼 반대편으로 튄다.)
  static const List<Azimuth> _clockwise = [
    Azimuth.north,
    Azimuth.east,
    Azimuth.south,
    Azimuth.west,
  ];

  Azimuth _nextClockwise(Azimuth from) {
    final i = _clockwise.indexOf(from);
    for (var k = 1; k <= _clockwise.length; k++) {
      final a = _clockwise[(i + k) % _clockwise.length];
      if (!d.photos.containsKey(a)) return a;
    }
    return from; // 4방위 모두 촬영됨
  }

  void _advance() {
    setState(() {
      _selected = _nextClockwise(_selected);
      _busy = false;
    });
  }

  /// 원시 데이터 번들에 분석용 사진 사본과 촬영 메타를 남긴다.
  /// 실패해도 조사는 계속된다.
  Future<void> _keepRaw(Azimuth az, String savedPath, DateTime at,
      {required String source}) async {
    try {
      d.rawDir ??= await RawArchive.create(d.treeId);
      final dir = d.rawDir!;
      final copy = await RawArchive.keepPhoto(dir, savedPath, az.code);
      final here = _here;
      final sp = d.photoPos[az];
      final rawHeading = _heading;
      await RawArchive.writeJson(dir, '${az.code}_capture.json', {
        'azimuth': az.code,
        'source': source,
        'capturedAt': at.toIso8601String(),
        'photo': savedPath,
        'bundledPhoto': copy,
        'treeId': d.treeId,
        'site': d.site,
        'species': d.species,
        'poleLengthM': d.poleLengthM,
        'gps': here == null
            ? null
            : {
                'lat': here.latitude,
                'lon': here.longitude,
                'accuracyM': here.accuracy,
                'altitudeM': here.altitude,
                'timestamp': here.timestamp.toIso8601String(),
              },
        'standpoint': sp == null
            ? null
            : {'lat': sp.lat, 'lon': sp.lon, 'sigmaM': sp.sigma},
        'heading': {
          'rawDeg': rawHeading,
          'displayDeg': Geomag.toDisplay(rawHeading, northRef.value),
          'northRef': Geomag.effective(northRef.value).name,
          'declinationDeg': Geomag.declinationDeg,
        },
        'camera': {
          'preset': 'max',
          'normalizedLongSide': PhotoNormalizer.longSide,
        },
        'environment': RawArchive.environment(),
      });
    } catch (_) {}
  }

  /// 촬영 뒷정리(표준 형태 저장 + 연구용 원본 보관). 실패하면 원본 복사로
  /// 대체되고, 그마저 실패하면 사진 없는 방위로 돌아간다(알림 표시).
  Future<void> _finishShot(
      Azimuth az, String srcPath, String dest, DateTime shotAt) async {
    try {
      // 기기별 해상도·EXIF 방향을 표준 형태로 맞춰 저장한다(분석 경로 통일).
      await PhotoNormalizer.save(srcPath, dest);
      // 연구용 원시 데이터: 분석용 표준 사진 + 촬영 당시 GPS·방위각·기기.
      await _keepRaw(az, dest, shotAt, source: 'camera');
      if (d.isInProgress) saveDraftJson(d.toJsonString());
    } catch (e) {
      if (d.photos[az] == dest) d.photos.remove(az);
      if (mounted) {
        setState(() {});
        _showNotice(tr('${az.label} 사진 저장 실패: $e',
            'Failed to save ${az.label} photo: $e'));
      }
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      final shotAt = DateTime.now();
      final destDir = await _photoDir();
      final az = _selected;
      final dest = p.join(destDir.path,
          '${d.treeId}_${az.code}_${shotAt.millisecondsSinceEpoch}.jpg');
      d.photos[az] = dest;
      final tagged = _tagPosition();
      // 정규화·원본 보관은 대형 센서(2억 화소)에서 몇 초씩 걸린다. 셔터가
      // 그걸 기다리면 조사 흐름이 끊기므로 백그라운드로 돌리고 즉시 다음
      // 방위로 넘어간다. AI 분석 진입 시 [_goAnalyse]가 완료를 기다린다.
      _pendingShots.add(_finishShot(az, shot.path, dest, shotAt));
      saveDraftJson(d.toJsonString()); // persist so a mid-field close can resume
      if (!mounted) return; // screen may have been popped mid-capture
      if (!tagged) {
        _showNotice(tr('이 방위는 GPS 없이 기록됨', 'Recorded without GPS'));
      }
      _advance();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showNotice(tr('촬영 실패: $e', 'Capture failed: $e'));
    }
  }

  /// Import an existing photo from the gallery and assign it to an azimuth.
  Future<void> _pickFromGallery() async {
    if (_busy) return;
    try {
      // 갤러리 원본은 무엇이든 올 수 있다(200 MP·HEIC…) — 먼저 플랫폼에서 줄이고
      // 촬영본과 같은 표준 형태로 저장한다.
      final picked = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: PhotoNormalizer.longSide.toDouble(),
          maxHeight: PhotoNormalizer.longSide.toDouble());
      if (picked == null || !mounted) return;
      final az = await _askAzimuth();
      if (az == null || !mounted) return;
      setState(() => _busy = true);
      final destDir = await _photoDir();
      final at = DateTime.now();
      final dest = p.join(destDir.path,
          '${d.treeId}_${az.code}_${at.millisecondsSinceEpoch}.jpg');
      d.photos[az] = dest;
      _pendingShots.add(() async {
        try {
          await PhotoNormalizer.save(picked.path, dest);
          await _keepRaw(az, dest, at, source: 'gallery');
          if (d.isInProgress) saveDraftJson(d.toJsonString());
        } catch (e) {
          if (d.photos[az] == dest) d.photos.remove(az);
          if (mounted) {
            setState(() {});
            _showNotice(tr('불러오기 실패: $e', 'Import failed: $e'));
          }
        }
      }());
      saveDraftJson(d.toJsonString());
      if (!mounted) return;
      _showNotice(tr('${az.label} 방위에 사진을 불러왔습니다',
          'Photo imported for ${az.label}'));
      _advance();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showNotice(tr('불러오기 실패: $e', 'Import failed: $e'));
    }
  }

  /// Which azimuth does an imported photo belong to?
  Future<Azimuth?> _askAzimuth() {
    return showDialog<Azimuth>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('어느 방위인가요?', 'Which azimuth?')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final a in Azimuth.values)
            ListTile(
              dense: true,
              leading: Icon(
                  d.photos.containsKey(a) ? Icons.check_circle : Icons.circle_outlined,
                  color: d.photos.containsKey(a)
                      ? _soot
                      : Theme.of(context).colorScheme.outline),
              title: Text(tr('${a.label} 방위', '${a.label} azimuth')),
              subtitle: d.photos.containsKey(a)
                  ? Text(tr('덮어쓰기', 'Overwrite'))
                  : null,
              onTap: () => Navigator.pop(context, a),
            ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('취소', 'Cancel'))),
        ],
      ),
    );
  }

  /// Dwell-average the recent buffer into a standpoint fix (median + scatter).
  bool _tagPosition() {
    final now = DateTime.now();
    final good = _buf
        .where((p) => p.accuracy <= 20 && now.difference(p.timestamp).inSeconds <= 6)
        .toList();
    if (good.isEmpty) return false;
    double med(List<double> s) => s.length.isOdd
        ? s[s.length ~/ 2]
        : (s[s.length ~/ 2 - 1] + s[s.length ~/ 2]) / 2;
    final lats = good.map((p) => p.latitude).toList()..sort();
    final lons = good.map((p) => p.longitude).toList()..sort();
    final mLat = med(lats);
    final mLon = med(lons);
    double sigma;
    if (good.length >= 2) {
      double ss = 0;
      for (final p in good) {
        final dy = (p.latitude - mLat) * 111320.0;
        final dx = (p.longitude - mLon) * 111320.0 * math.cos(mLat * math.pi / 180.0);
        ss += dy * dy + dx * dx;
      }
      sigma = math.max(math.sqrt(ss / good.length), 3.0);
    } else {
      sigma = math.max(good.first.accuracy, 3.0);
    }
    d.photoPos[_selected] = (lat: mLat, lon: mLon, sigma: sigma);
    return true;
  }

  Future<void> _goAnalyse() async {
    if (d.photos.isEmpty) return;
    // 백그라운드 저장이 남아 있으면 끝날 때까지 잠깐 기다린다 — 분석은
    // 파일이 완전히 쓰인 뒤에 읽어야 한다.
    if (_pendingShots.isNotEmpty) {
      _showNotice(tr('사진 저장을 마무리하는 중…', 'Finishing photo save…'));
      final waiting = List.of(_pendingShots);
      await Future.wait(waiting);
      _pendingShots.removeWhere(waiting.contains);
      if (!mounted || d.photos.isEmpty) return;
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisScreen(draft: d)));
  }

  Future<void> _editTreeId() async {
    final ctl = TextEditingController(text: d.treeId);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('조사목 번호', 'Tree ID')),
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('취소', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, ctl.text.trim()),
              child: Text(tr('확인', 'OK'))),
        ],
      ),
    );
    if (v != null && v.isNotEmpty && mounted) {
      setState(() => d.treeId = v);
      if (d.isInProgress) saveDraftJson(d.toJsonString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = d.photos.length;
    final padTop = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        _preview(),

        // 셔터 순간의 플래시 (시연 모드의 "촬영" 효과)
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _flash ? 0.85 : 0.0,
            duration: const Duration(milliseconds: 90),
            child: Container(color: Colors.white),
          ),
        ),

        // 수고봉 정렬선 (설정에서 끔) — 프리뷰 이미지 영역 안에만 그린다.
        if (showGuides.value)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AspectRatio(
                  aspectRatio: _previewAspect,
                  child: Center(
                    child:
                        Container(width: 2, color: _pole.withValues(alpha: 0.85)),
                  ),
                ),
              ),
            ),
          ),

        // top: back · 조사목 번호(탭 수정) — 각자 자기 배경만 가짐 (전면 그라데이션 없음)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
              child: Row(children: [
                _CamBtn(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                const Spacer(),
                GestureDetector(
                  onTap: _editTreeId,
                  child: _Scrim(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(tr('조사목 ${d.treeId}', 'Tree ${d.treeId}'),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 5),
                      const Icon(Icons.edit_outlined, size: 14, color: Colors.white70),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _pickSpecies,
                  child: _Scrim(
                    radius: 999,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.forest_outlined,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(speciesLabel(d.species),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      const Icon(Icons.arrow_drop_down,
                          size: 16, color: Colors.white70),
                    ]),
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 42), // balance the back button
              ]),
            ),
          ),
        ),

        // 현재 좌표 — 조사자가 목표 좌표를 찾아가며 찍을 수 있게 항상 띄운다.
        // 누르면 클립보드로 복사된다(지도 앱·야장에 그대로 옮겨 쓰기).
        if (_here != null)
          Positioned(
            top: padTop + 50,
            left: 14,
            child: GestureDetector(
              onTap: _copyCoords,
              child: _Scrim(
                radius: 10,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.my_location, size: 11, color: Colors.white70),
                    const SizedBox(width: 4),
                    Text('±${_here!.accuracy.round()} m',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                            fontSize: 9.5)),
                  ]),
                  const SizedBox(height: 3),
                  Text(_here!.latitude.toStringAsFixed(6),
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  Text(_here!.longitude.toStringAsFixed(6),
                      style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),

        // real device compass (top-right) — 누르면 진북 ↔ 자북
        Positioned(
          top: padTop + 50,
          right: 14,
          child: ValueListenableBuilder<NorthRef>(
            valueListenable: northRef,
            builder: (_, want, __) => _DeviceCompass(
              heading: Geomag.toDisplay(_heading, want),
              ref: Geomag.effective(want),
              onTap: _toggleNorthRef,
            ),
          ),
        ),

        // 안내 문구 — 하단 컨트롤을 가리지 않도록 화면 위쪽에 띄운다.
        if (_notice != null)
          Positioned(
            top: padTop + 108,
            left: 14,
            right: 14,
            child: IgnorePointer(
              child: Center(
                child: _Scrim(
                  radius: 999,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.info_outline, size: 15, color: _pole),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(_notice!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),

        // bottom: gallery · compass+shutter · AI 분석 (각 요소에만 스크림)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _CamBtn(
                      icon: Icons.photo_library_outlined, onTap: _pickFromGallery),
                  Expanded(child: Center(child: _compassBlock(n))),
                  const SizedBox(width: 42), // keep the compass centred
                ]),
                const SizedBox(height: 12),
                _analyseButton(n),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  /// Compass + shutter. The scrim is exactly the compass circle so it stays
  /// concentric with the pods instead of floating behind the whole column.
  Widget _compassBlock(int n) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _Scrim(
        radius: 999,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: _selected.label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: tr(' 방위 · $n/4', ' · $n/4')),
          ]),
          style: const TextStyle(
              color: Colors.white, fontFamily: 'monospace', fontSize: 11.5),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        width: _compassSize,
        height: _compassSize,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            radius: 0.5,
            colors: [Color(0xA6060A10), Color(0x00060A10)],
            stops: [0.62, 1.0],
          ),
        ),
        child: _compass(),
      ),
    ]);
  }

  Widget _analyseButton(int n) {
    final on = n > 0;
    return Center(
      child: Material(
        color: on ? _navy.withValues(alpha: 0.94) : const Color(0x73141A22),
        borderRadius: BorderRadius.circular(11),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: on ? _goAnalyse : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome,
                  size: 17, color: on ? Colors.white : Colors.white38),
              const SizedBox(width: 8),
              Text(tr('AI 분석 · $n/4', 'AI analysis · $n/4'),
                  style: TextStyle(
                      color: on ? Colors.white : Colors.white38,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    );
  }

  /// 수종 선택 — 주요 수종 목록에서 고르거나 직접 입력한다.
  Future<void> _pickSpecies() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final s in majorSpecies)
            ListTile(
              dense: true,
              leading: Icon(
                  s == d.species
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 20),
              title: Text(speciesLabel(s)),
              onTap: () => Navigator.pop(context, s),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.edit_outlined, size: 20),
            title: Text(tr('직접 입력', 'Enter manually')),
            onTap: () => Navigator.pop(context, '__custom__'),
          ),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    var species = v;
    if (v == '__custom__') {
      final ctl = TextEditingController(text: d.species);
      final t = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(tr('수종 입력', 'Species')),
          content: TextField(controller: ctl, autofocus: true),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('취소', 'Cancel'))),
            TextButton(
                onPressed: () => Navigator.pop(context, ctl.text.trim()),
                child: Text(tr('확인', 'OK'))),
          ],
        ),
      );
      if (t == null || t.isEmpty || !mounted) return;
      species = t;
    }
    setState(() => d.species = species);
    setLastSpecies(species); // 다음 조사목의 기본 수종으로 이어진다
    if (d.isInProgress) saveDraftJson(d.toJsonString());
  }

  // compass with the shutter at the centre, 동/서/남/북 around it
  static const double _compassSize = 168;
  static const double _podBox = 44; // pod hit box; the circle inside is _podDot
  static const double _podDot = 40;

  Widget _compass() {
    return SizedBox(
      width: _compassSize,
      height: _compassSize,
      child: Stack(children: [
        Center(
          child: Container(
            // ring passes through the pod centres
            width: _compassSize - _podBox,
            height: _compassSize - _podBox,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
          ),
        ),
        Align(alignment: Alignment.topCenter, child: _pod(Azimuth.north)),
        Align(alignment: Alignment.centerRight, child: _pod(Azimuth.east)),
        Align(alignment: Alignment.bottomCenter, child: _pod(Azimuth.south)),
        Align(alignment: Alignment.centerLeft, child: _pod(Azimuth.west)),
        Align(alignment: Alignment.center, child: _shutter()),
      ]),
    );
  }

  Widget _pod(Azimuth a) {
    final sel = a == _selected;
    final done = d.photos.containsKey(a);
    // 대기 = 반투명 어두움 / 촬영완료 = 초록+체크 / **현재 = 수고봉 노랑**.
    // (navy 는 카메라 화면이 어두우면 대기 상태와 구별이 안 됐다.)
    Color bg = const Color(0x8C0C121A), border = Colors.white54;
    Color fg = Colors.white;
    if (done) {
      bg = _soot;
      border = _soot;
    }
    if (sel) {
      bg = done ? _soot : _pole;
      border = _pole;
      fg = done ? Colors.white : const Color(0xFF11151C);
    }
    return GestureDetector(
      onTap: () => setState(() => _selected = a),
      child: SizedBox(
        width: _podBox,
        height: _podBox,
        // centre the circle in its hit box so it sits on the ring, and hang the
        // check badge off that circle rather than off the larger box
        child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          Container(
            width: _podDot,
            height: _podDot,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: sel ? 3 : 1.4),
              boxShadow: sel
                  ? [BoxShadow(color: _pole.withValues(alpha: 0.55), blurRadius: 10)]
                  : null,
            ),
            child: Text(a.label,
                style: TextStyle(
                    color: fg, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          if (done)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                    color: _soot,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0B1119), width: 2)),
                child: const Icon(Icons.check, size: 9, color: Colors.white),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _shutter() {
    return GestureDetector(
      onTap: _capture,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.14),
          border: Border.all(color: Colors.white, width: 3.4),
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
              : Container(
                  width: 46,
                  height: 46,
                  decoration:
                      const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
        ),
      ),
    );
  }

  /// 뷰파인더(=찍히는 사진)의 세로 화면 기준 종횡비. 정렬선 등 오버레이가
  /// 이미지 영역 밖(위아래 여백)으로 나가지 않도록 함께 쓴다.
  double get _previewAspect {
    if (_demo) return 3 / 4;
    final ps = _controller?.value.previewSize;
    return ps == null ? 3 / 4 : ps.height / ps.width;
  }

  Widget _preview() {
    // 시연 모드: 선택된 방위의 예시 사진이 곧 뷰파인더다. 방위가 바뀌면
    // 조사자가 나무를 돌아간 것처럼 사진이 부드럽게 교체된다.
    // 예시 사진 비율(3:4) 그대로 보여줘 화면에 보이는 것이 곧 찍히는 사진이다.
    if (_demo) {
      return Center(
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: Image.asset(
              DemoSample.assetFor(_selected),
              key: ValueKey(_selected),
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.no_photography, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _initCamera,
              style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54)),
              child: Text(tr('다시 시도', 'Retry')),
            ),
          ]),
        ),
      );
    }
    final c = _controller;
    if (_initing || c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    // 프리뷰를 실제 촬영 비율 그대로 보여준다(전체 화면 크롭 없음) —
    // 화면에 보이는 프레임이 곧 저장·분석되는 사진이다.
    final ps = c.value.previewSize;
    final ar = ps == null ? 3 / 4 : ps.height / ps.width; // 세로 화면 기준
    return Center(child: AspectRatio(aspectRatio: ar, child: CameraPreview(c)));
  }
}

/// Small translucent backdrop so white text stays readable over the preview
/// without darkening a whole band of the screen.
class _Scrim extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  const _Scrim({required this.child, required this.padding, this.radius = 12});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
          color: const Color(0x99080C12), borderRadius: BorderRadius.circular(radius)),
      child: child,
    );
  }
}

class _CamBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CamBtn({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x73080C12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
            width: 42, height: 42, child: Icon(icon, color: Colors.white, size: 21)),
      ),
    );
  }
}

/// Live compass — the rose rotates so N points to real north, and the fixed
/// top tick shows the phone's facing bearing.
///
/// [heading]은 센서 원본이 아니라 **표시 기준으로 이미 변환된** 값이다
/// (`Geomag.toDisplay`). 눌러서 진북 ↔ 자북을 바꾼다.
class _DeviceCompass extends StatelessWidget {
  final double? heading;
  final NorthRef ref; // 실제로 표시 중인 기준
  final VoidCallback? onTap;
  const _DeviceCompass({required this.heading, required this.ref, this.onTap});

  static const _dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  @override
  Widget build(BuildContext context) {
    final h = heading;
    final label = h == null
        ? tr('나침반 없음', 'No compass')
        : '${h.round()}° ${_dirs[((h % 360) / 45).round() % 8]}';
    final refLabel =
        ref == NorthRef.trueNorth ? tr('진북', 'True N') : tr('자북', 'Mag N');
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x8C080C12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
            ),
            Transform.rotate(
              angle: h == null ? 0 : -h * math.pi / 180.0,
              child: CustomPaint(size: const Size(56, 56), painter: _RosePainter()),
            ),
            // fixed facing tick (top)
            const Positioned(
              top: 1,
              child: Icon(Icons.arrow_drop_down, size: 15, color: Colors.white),
            ),
          ]),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
              color: const Color(0x8C080C12),
              borderRadius: BorderRadius.circular(999)),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 3),
        // 어느 북쪽을 보고 있는지 늘 드러낸다 — 방위 기록의 근거가 된다.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
              color: const Color(0x8C080C12),
              borderRadius: BorderRadius.circular(999)),
          child: Text(refLabel,
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

class _RosePainter extends CustomPainter {
  static const _ember = Color(0xFFC24A1E);
  @override
  void paint(Canvas canvas, Size s) {
    final c = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2 - 6;
    // north needle (red) up, south (white) down
    final needle = Paint()..strokeWidth = 3..strokeCap = StrokeCap.round;
    canvas.drawLine(c, Offset(c.dx, c.dy - r), needle..color = _ember);
    canvas.drawLine(c, Offset(c.dx, c.dy + r), needle..color = Colors.white70);
    // E/W ticks
    final tick = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2;
    canvas.drawLine(Offset(c.dx - r, c.dy), Offset(c.dx - r + 5, c.dy), tick);
    canvas.drawLine(Offset(c.dx + r - 5, c.dy), Offset(c.dx + r, c.dy), tick);
  }

  @override
  bool shouldRepaint(_) => false;
}

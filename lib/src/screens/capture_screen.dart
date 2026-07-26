import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../models/draft.dart';
import '../services/location_service.dart';
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
  String? _error;
  Azimuth _selected = Azimuth.east;
  bool _busy = false;
  final _picker = ImagePicker();

  // GPS: tagged onto each shot (silently) so the tree gets a map coordinate.
  StreamSubscription<Position>? _posSub;
  final List<Position> _buf = []; // recent fixes, for dwell-averaging each shot

  // Real device compass.
  StreamSubscription<CompassEvent>? _compassSub;
  double? _heading;

  static const _navy = Color(0xFF16294A);
  static const _soot = Color(0xFF35A853);
  static const _pole = Color(0xFFF6C518);

  SurveyDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Resume onto the first azimuth that still needs a photo.
    _selected = Azimuth.values.firstWhere((a) => !d.photos.containsKey(a),
        orElse: () => Azimuth.east);
    _initCamera();
    _startGps();
    _startCompass();
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
      },
      onError: (_) {},
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      if (_controller == null) _initCamera();
      if (_posSub == null) _startGps();
      if (_compassSub == null) _startCompass();
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _initing = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError(tr('사용 가능한 카메라가 없습니다', 'No camera available'));
      }
      final controller = CameraController(cameras.first, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);
      if (!mounted) return;
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
    }
  }

  Future<Directory> _photoDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final destDir = Directory(p.join(dir.path, 'photos'));
    if (!destDir.existsSync()) destDir.createSync(recursive: true);
    return destDir;
  }

  void _advance() {
    final next = Azimuth.values.firstWhere((a) => !d.photos.containsKey(a),
        orElse: () => _selected);
    setState(() {
      _selected = next;
      _busy = false;
    });
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      final destDir = await _photoDir();
      final dest = p.join(destDir.path,
          '${d.treeId}_${_selected.code}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(shot.path).copy(dest);
      d.photos[_selected] = dest;
      final tagged = _tagPosition();
      saveDraftJson(d.toJsonString()); // persist so a mid-field close can resume
      if (!mounted) return; // screen may have been popped mid-capture
      if (!tagged) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(tr('이 방위는 GPS 없이 기록됨', 'Recorded without GPS')),
          duration: const Duration(milliseconds: 1400),
        ));
      }
      _advance();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('촬영 실패: $e', 'Capture failed: $e'))));
    }
  }

  /// Import an existing photo from the gallery and assign it to an azimuth.
  Future<void> _pickFromGallery() async {
    if (_busy) return;
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      final az = await _askAzimuth();
      if (az == null || !mounted) return;
      setState(() => _busy = true);
      final destDir = await _photoDir();
      final dest = p.join(destDir.path,
          '${d.treeId}_${az.code}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(picked.path).copy(dest);
      d.photos[az] = dest;
      saveDraftJson(d.toJsonString());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(tr('${az.label} 방위에 사진을 불러왔습니다',
            'Photo imported for ${az.label}')),
        duration: const Duration(milliseconds: 1400),
      ));
      _advance();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('불러오기 실패: $e', 'Import failed: $e'))));
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

  void _goAnalyse() {
    if (d.photos.isEmpty) return;
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

        // full-height 수고봉 정렬선 (설정에서 끔)
        if (showGuides.value)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(width: 2, color: _pole.withValues(alpha: 0.85)),
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
                const Spacer(),
                const SizedBox(width: 42), // balance the back button
              ]),
            ),
          ),
        ),

        // real device compass (top-right) + 수고봉 hint (top-left)
        Positioned(top: padTop + 50, right: 14, child: _DeviceCompass(heading: _heading)),
        Positioned(top: padTop + 52, left: 14, child: _hintChip()),

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

  Widget _hintChip() {
    return _Scrim(
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.straighten, size: 15, color: _pole),
        const SizedBox(width: 6),
        Text(tr('수고봉이 화면에 보이게', 'Keep the measuring pole in frame'),
            style: const TextStyle(
                color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
      ]),
    );
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
    // pending = translucent, current = navy (distinct), done = green + check
    Color bg = const Color(0x8C0C121A), border = Colors.white54;
    const fg = Colors.white;
    if (done) {
      bg = _soot;
      border = _soot;
    } else if (sel) {
      bg = _navy;
      border = Colors.white;
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
              border: Border.all(color: border, width: sel && !done ? 2.2 : 1.4),
            ),
            child: Text(a.label,
                style: const TextStyle(
                    color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
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

  Widget _preview() {
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
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: c.value.previewSize?.height ?? 1080,
        height: c.value.previewSize?.width ?? 1920,
        child: CameraPreview(c),
      ),
    );
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

/// Live magnetometer compass — the rose rotates so N points to real north,
/// and the fixed top tick shows the phone's facing bearing.
class _DeviceCompass extends StatelessWidget {
  final double? heading; // degrees from magnetic north, null if no sensor
  const _DeviceCompass({required this.heading});

  static const _dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

  @override
  Widget build(BuildContext context) {
    final h = heading;
    final label = h == null
        ? tr('나침반 없음', 'No compass')
        : '${h.round()}° ${_dirs[((h % 360) / 45).round() % 8]}';
    return Column(children: [
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
            color: const Color(0x8C080C12), borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontFamily: 'monospace', fontSize: 9.5, fontWeight: FontWeight.w700)),
      ),
    ]);
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

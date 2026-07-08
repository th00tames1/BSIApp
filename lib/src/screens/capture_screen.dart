import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../app_prefs.dart';
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
  FlashMode _flash = FlashMode.off;

  // GPS: live standpoint fix, tagged onto each azimuth shot.
  Position? _pos;
  GpsStatus _gps = GpsStatus.ok;
  StreamSubscription<Position>? _posSub;
  final List<Position> _buf = []; // recent fixes, for dwell-averaging each shot

  static const _navy = Color(0xFF16294A);
  static const _soot = Color(0xFF35A853);
  static const _pole = Color(0xFFF6C518);
  static const _amber = Color(0xFFF0A83C); // shot taken but no GPS tag

  SurveyDraft get d => widget.draft;

  /// A fix worth tagging: present, permitted, accurate (≤20 m) and fresh (≤8 s).
  bool get _goodFix {
    final p = _pos;
    if (p == null || _gps != GpsStatus.ok) return false;
    if (p.accuracy > 20) return false;
    if (DateTime.now().difference(p.timestamp).inSeconds > 8) return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _flash = defaultFlashAuto.value ? FlashMode.auto : FlashMode.off;
    _initCamera();
    _startGps();
  }

  Future<void> _startGps() async {
    await _posSub?.cancel();
    _posSub = null;
    final st = await LocationService.ensure();
    if (!mounted) return;
    setState(() => _gps = st);
    if (st != GpsStatus.ok) return;
    // geolocator can emit errors (service turned off / permission revoked) as
    // stream events; without onError the sub would die silently and the chip
    // would stay green on a frozen fix. Re-evaluate status on error.
    _posSub = LocationService.stream().listen(
      (p) {
        if (!mounted) return;
        setState(() {
          _pos = p;
          _buf.add(p);
          final cutoff = DateTime.now().subtract(const Duration(seconds: 6));
          _buf.removeWhere((x) => x.timestamp.isBefore(cutoff));
        });
      },
      onError: (_) async {
        final again = await LocationService.ensure();
        if (mounted) {
          setState(() {
            _pos = null;
            _gps = again;
          });
        }
      },
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (state == AppLifecycleState.inactive) {
      _posSub?.cancel(); // stop high-accuracy GPS in background (battery)
      _posSub = null;
      _pos = null;
      _buf.clear();
      if (c != null && c.value.isInitialized) {
        _controller = null; // avoid using a disposed controller in _preview()
        c.dispose();
      }
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) _initCamera();
      if (_posSub == null) _startGps();
    }
  }

  Future<void> _initCamera() async {
    setState(() {
      _initing = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('사용 가능한 카메라가 없습니다');
      final controller = CameraController(cameras.first, ResolutionPreset.high,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await controller.initialize();
      await controller.setFlashMode(_flash);
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

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      final dir = await getApplicationDocumentsDirectory();
      final destDir = Directory(p.join(dir.path, 'photos'));
      if (!destDir.existsSync()) destDir.createSync(recursive: true);
      final dest = p.join(destDir.path,
          '${d.treeId}_${_selected.code}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(shot.path).copy(dest);
      d.photos[_selected] = dest;
      // Dwell-average the recent buffer into a standpoint fix (median + scatter).
      final now = DateTime.now();
      final good = _buf
          .where((p) => p.accuracy <= 20 && now.difference(p.timestamp).inSeconds <= 6)
          .toList();
      bool tagged = false;
      if (good.isNotEmpty) {
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
        tagged = true;
      }
      if (!mounted) return; // screen may have been popped mid-capture
      if (!tagged) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('GPS 미확보 — 이 방위는 위치 없이 기록됨'),
          duration: Duration(milliseconds: 1500),
        ));
      }
      final next = Azimuth.values.firstWhere((a) => !d.photos.containsKey(a),
          orElse: () => _selected);
      setState(() {
        _selected = next;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('촬영 실패: $e')));
    }
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _flash = _flash == FlashMode.off ? FlashMode.auto : FlashMode.off;
    await c.setFlashMode(_flash);
    if (!mounted) return;
    setState(() {});
  }

  void _goAnalyse() {
    if (d.photos.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisScreen(draft: d)));
  }

  @override
  Widget build(BuildContext context) {
    final n = d.photos.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        _preview(),

        // top translucent bar
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xB3060A10), Colors.transparent]),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 4, 6, 10),
                child: Row(children: [
                  _CamBtn(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
                  const Expanded(
                    child: Text('촬영',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  _CamBtn(
                    icon: _flash == FlashMode.off ? Icons.flash_off : Icons.flash_auto,
                    color: _flash == FlashMode.off ? Colors.white : _pole,
                    onTap: _toggleFlash,
                  ),
                ]),
              ),
            ),
          ),
        ),

        // GPS status (left) · orientation compass (right) · hint (below)
        Positioned(
          top: MediaQuery.of(context).padding.top + 52,
          left: 14,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _gpsChip(),
            const SizedBox(height: 6),
            _gapButton(),
          ]),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 52,
          right: 14,
          child: _OrientCompass(azimuth: _selected),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 112,
          left: 0, right: 0,
          child: Center(child: _hintChip()),
        ),

        // bottom capture zone
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xD1060A10)],
                  stops: [0, 0.42]),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: _selected.ko,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: ' 방위 · $n/4'),
                    ]),
                    style: const TextStyle(
                        color: Colors.white, fontFamily: 'monospace', fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _compass(),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: n > 0 ? _goAnalyse : null,
                      child: Text('AI 분석 · $n/4'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _hintChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: const Color(0x99080C12), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: const [
        Icon(Icons.straighten, size: 16, color: _pole),
        SizedBox(width: 6),
        Text('수고봉이 화면에 보이게',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _gpsChip() {
    final tagged = d.photoPos.length;
    IconData ic;
    Color color;
    String text;
    if (_gps != GpsStatus.ok) {
      ic = Icons.location_disabled;
      color = const Color(0xFFF0824B);
      text = '${_gps == GpsStatus.serviceOff ? 'GPS 꺼짐' : '위치 권한 필요'} · 탭';
    } else if (!_goodFix) {
      ic = Icons.gps_not_fixed;
      color = _amber;
      text = 'GPS 검색 중… · $tagged/4';
    } else {
      ic = Icons.gps_fixed;
      color = const Color(0xFF4FC27C);
      text = 'GPS ±${_pos!.accuracy.round()}m · $tagged/4';
    }
    return GestureDetector(
      onTap: _startGps, // tap to retry (e.g. after enabling location)
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0x99080C12), borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(ic, size: 15, color: color),
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // Canopy-denied trunk: measure a fix at a nearby sky gap, then offset by
  // compass bearing + distance to the tree.
  Widget _gapButton() {
    return GestureDetector(
      onTap: _gapOffset,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0x99080C12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white30),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: const [
          Icon(Icons.explore_outlined, size: 14, color: Colors.white),
          SizedBox(width: 5),
          Text('갭에서 위치',
              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Future<void> _gapOffset() async {
    final result = await showModalBottomSheet<({double lat, double lon})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => const _GapOffsetSheet(),
    );
    if (result != null && mounted) {
      setState(() {
        d.lat = result.lat;
        d.lon = result.lon;
        d.gapOffsetSet = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('갭-오프셋으로 나무 위치를 기록했습니다'),
        duration: Duration(milliseconds: 1600),
      ));
    }
  }

  // compass with the shutter at the centre, 동/서/남/북 around it
  Widget _compass() {
    return SizedBox(
      width: 210,
      height: 210,
      child: Stack(children: [
        // dashed-ish ring
        Center(
          child: Container(
            width: 190,
            height: 190,
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
    Color bg = const Color(0x8C0C121A), border = Colors.white54, fg = Colors.white;
    if (sel) {
      bg = Colors.white;
      border = Colors.white;
      fg = _navy;
    } else if (done) {
      // green = shot with GPS, amber = shot but no position tagged
      bg = d.photoPos.containsKey(a) ? _soot : _amber;
      border = bg;
      fg = Colors.white;
    }
    return GestureDetector(
      onTap: () => setState(() => _selected = a),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 1.6),
          boxShadow: sel
              ? [BoxShadow(color: Colors.white.withValues(alpha: 0.25), blurRadius: 0, spreadRadius: 4)]
              : null,
        ),
        child: Text(a.ko,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 17)),
      ),
    );
  }

  Widget _shutter() {
    return GestureDetector(
      onTap: _capture,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.14),
          border: Border.all(color: Colors.white, width: 4),
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 26, height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Container(
                  width: 56, height: 56,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
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
              child: const Text('다시 시도'),
            ),
          ]),
        ),
      );
    }
    final c = _controller;
    if (_initing || c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Stack(fit: StackFit.expand, children: [
      FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: c.value.previewSize?.height ?? 1080,
          height: c.value.previewSize?.width ?? 1920,
          child: CameraPreview(c),
        ),
      ),
      // 수고봉 정렬 안내선 (상부) + 크로스헤어 — 설정에서 끌 수 있음
      if (showGuides.value) ...[
        IgnorePointer(
          child: Column(children: [
            const Spacer(flex: 12),
            Expanded(
              flex: 42,
              child: Center(
                child: Container(width: 2, color: _pole.withValues(alpha: 0.85)),
              ),
            ),
            const Spacer(flex: 46),
          ]),
        ),
        IgnorePointer(
          child: Align(
            alignment: const Alignment(0, -0.34),
            child: SizedBox(
              width: 30, height: 30,
              child: CustomPaint(painter: _CrossPainter()),
            ),
          ),
        ),
      ],
    ]);
  }
}

class _CamBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CamBtn({required this.icon, this.color = Colors.white, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x40000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 42, height: 42, child: Icon(icon, color: color, size: 23)),
      ),
    );
  }
}

/// Orientation dial: shows heading of the currently selected azimuth.
class _OrientCompass extends StatelessWidget {
  final Azimuth azimuth;
  const _OrientCompass({required this.azimuth});
  static const _ember = Color(0xFFC24A1E);
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        width: 60,
        height: 60,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x8C080C12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
          ),
          const Positioned(top: 5, left: 0, right: 0, child: Center(child: _Card('N', _ember))),
          const Positioned(bottom: 5, left: 0, right: 0, child: Center(child: _Card('S', Colors.white70))),
          const Positioned(left: 6, top: 0, bottom: 0, child: Center(child: _Card('W', Colors.white70))),
          const Positioned(right: 6, top: 0, bottom: 0, child: Center(child: _Card('E', Colors.white70))),
          Transform.rotate(
            angle: azimuth.heading * math.pi / 180,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  width: 3,
                  height: 22,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_ember, _ember, Colors.white70],
                        stops: [0, 0.55, 0.55]),
                  ),
                ),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 5),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: const Color(0x8C080C12), borderRadius: BorderRadius.circular(999)),
        child: Text('${azimuth.ko} · ${azimuth.heading}°',
            style: const TextStyle(
                color: Colors.white, fontFamily: 'monospace', fontSize: 10, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

class _Card extends StatelessWidget {
  final String t;
  final Color c;
  const _Card(this.t, this.c);
  @override
  Widget build(BuildContext context) => Text(t,
      style: TextStyle(color: c, fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700));
}

class _CrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, s.height / 2), Offset(s.width, s.height / 2), paint);
    canvas.drawLine(Offset(s.width / 2, 0), Offset(s.width / 2, s.height), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

/// Gap-offset: measure GPS at a nearby sky gap, then project to the trunk by
/// compass bearing + distance. Returns the computed (lat,lon) via Navigator.pop.
class _GapOffsetSheet extends StatefulWidget {
  const _GapOffsetSheet();
  @override
  State<_GapOffsetSheet> createState() => _GapOffsetSheetState();
}

class _GapOffsetSheetState extends State<_GapOffsetSheet> {
  Position? _gap;
  bool _measuring = false;
  double? _heading; // live compass
  double? _locked; // locked bearing to tree
  final _dist = TextEditingController();
  StreamSubscription<CompassEvent>? _sub;

  @override
  void initState() {
    super.initState();
    final s = FlutterCompass.events;
    if (s != null) {
      _sub = s.listen((e) {
        if (mounted) setState(() => _heading = e.heading);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _dist.dispose();
    super.dispose();
  }

  Future<void> _measureGap() async {
    setState(() => _measuring = true);
    final p = await LocationService.current();
    if (!mounted) return;
    setState(() {
      _measuring = false;
      _gap = p;
    });
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('갭에서도 GPS를 못 잡았습니다 · 더 트인 곳에서')));
    }
  }

  void _apply() {
    final gap = _gap;
    final bearing = _locked;
    final dist = double.tryParse(_dist.text.trim());
    if (gap == null || bearing == null || dist == null || dist <= 0) return;
    final b = bearing * math.pi / 180.0;
    final dLat = (dist * math.cos(b)) / 111320.0;
    final dLon =
        (dist * math.sin(b)) / (111320.0 * math.cos(gap.latitude * math.pi / 180.0));
    Navigator.pop(context, (lat: gap.latitude + dLat, lon: gap.longitude + dLon));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ready =
        _gap != null && _locked != null && (double.tryParse(_dist.text.trim()) ?? 0) > 0;
    return Padding(
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: p.line, borderRadius: BorderRadius.circular(999)),
            ),
          ),
          const SizedBox(height: 14),
          const Text('갭 오프셋 위치',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('나무 밑에서 GPS가 안 잡힐 때 — 트인 곳에서 측정한 뒤 나무까지의 방위·거리로 역산합니다.',
              style: TextStyle(fontSize: 12.5, color: p.muted, height: 1.4)),
          const SizedBox(height: 18),

          _step('① 트인 곳(갭)에서 GPS 측정'),
          Row(children: [
            Expanded(
              child: Text(
                _gap == null
                    ? '아직 측정 전'
                    : '${_gap!.latitude.toStringAsFixed(6)}, ${_gap!.longitude.toStringAsFixed(6)}  ±${_gap!.accuracy.round()}m',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: _gap == null ? p.muted : p.ink),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _measuring ? null : _measureGap,
              child: _measuring
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_gap == null ? '측정' : '재측정'),
            ),
          ]),
          const SizedBox(height: 18),

          _step('② 나무를 향해 폰을 겨눈 뒤 방위 고정'),
          Row(children: [
            Icon(Icons.navigation, color: p.navy),
            const SizedBox(width: 10),
            Text(_heading == null ? '나침반 없음' : '${_heading!.round()}°',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: p.ink)),
            const Spacer(),
            if (_locked != null) ...[
              Text('고정 ${_locked!.round()}°',
                  style: TextStyle(
                      fontFamily: 'monospace', color: p.green, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
            ],
            ElevatedButton(
              onPressed: _heading == null ? null : () => setState(() => _locked = _heading),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              child: const Text('방위 고정'),
            ),
          ]),
          const SizedBox(height: 18),

          _step('③ 나무까지 거리'),
          TextField(
            controller: _dist,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(hintText: '예: 8', suffixText: 'm'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(onPressed: ready ? _apply : null, child: const Text('적용')),
          ),
        ],
      ),
    );
  }

  Widget _step(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      );
}

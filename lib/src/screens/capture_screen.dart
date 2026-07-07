import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/draft.dart';
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

  SurveyDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
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
      // advance to next un-captured face
      final next = Azimuth.values.firstWhere((a) => !d.photos.containsKey(a),
          orElse: () => _selected);
      setState(() {
        _selected = next;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('촬영 실패: $e')));
    }
  }

  Future<void> _toggleFlash() async {
    final c = _controller;
    if (c == null) return;
    _flash = _flash == FlashMode.off ? FlashMode.auto : FlashMode.off;
    await c.setFlashMode(_flash);
    setState(() {});
  }

  void _goAnalyse() {
    if (d.photos.isEmpty) return;
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => AnalysisScreen(draft: d)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('사진 촬영'),
        backgroundColor: Colors.white,
      ),
      body: Column(children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('나무 중심이 화면 안내선에 잘 들어오도록 하세요.',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13)),
        ),
        Expanded(child: _preview()),
        _azimuthTabs(),
        _controls(),
        _analyseBar(),
      ]),
    );
  }

  Widget _analyseBar() {
    final n = d.photos.length;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: ElevatedButton(
        onPressed: n > 0 ? _goAnalyse : null,
        child: Text(n >= 4 ? 'AI 분석 시작 (4/4)' : 'AI 분석 시작 ($n/4)'),
      ),
    );
  }

  Widget _preview() {
    if (_initing) {
      return const Center(child: CircularProgressIndicator());
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
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('다시 시도'),
            ),
          ]),
        ),
      );
    }
    final c = _controller!;
    return Stack(fit: StackFit.expand, children: [
      FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: c.value.previewSize?.height ?? 1080,
          height: c.value.previewSize?.width ?? 1920,
          child: CameraPreview(c),
        ),
      ),
      // center vertical guide line
      Center(
        child: Container(width: 2, color: Colors.white.withValues(alpha: 0.7)),
      ),
    ]);
  }

  Widget _azimuthTabs() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: Azimuth.values.map((a) {
          final sel = a == _selected;
          final done = d.photos.containsKey(a);
          Color bg = Colors.white;
          Color fg = AppColors.textSecondary;
          if (sel) {
            bg = AppColors.green;
            fg = Colors.white;
          } else if (done) {
            bg = AppColors.green.withValues(alpha: 0.15);
            fg = AppColors.green;
          }
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selected = a),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: sel ? AppColors.green : AppColors.border),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (done && !sel) ...[
                    const Icon(Icons.check, size: 15, color: AppColors.green),
                    const SizedBox(width: 3),
                  ],
                  Text(a.ko,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15)),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _controls() {
    final lastPath = d.photos[_selected] ??
        (d.photos.isNotEmpty ? d.photos.values.last : null);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
      child: Row(children: [
        // gallery thumbnail
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.black12,
            image: lastPath != null
                ? DecorationImage(image: FileImage(File(lastPath)), fit: BoxFit.cover)
                : null,
          ),
          child: lastPath == null
              ? const Icon(Icons.photo, color: Colors.black26)
              : null,
        ),
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: _capture,
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.navy, width: 4),
                ),
                child: Container(
                  margin: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.navy),
                  child: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : null,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _toggleFlash,
          icon: Icon(_flash == FlashMode.off ? Icons.flash_off : Icons.flash_auto,
              color: AppColors.textPrimary),
        ),
      ]),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n.dart';
import '../models/draft.dart';
import '../services/analysis_service.dart';
import '../services/onnx_service.dart';
import '../theme.dart';
import 'result_screen.dart';

class AnalysisScreen extends StatefulWidget {
  final SurveyDraft draft;
  const AnalysisScreen({super.key, required this.draft});
  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  double _progress = 0;
  /// null = 첫 진행 문구 전. 언어에 맞춰 build 시점에 정해지도록 필드에 굳히지 않는다.
  String? _status;
  String? _currentOverlay;
  String? _error;

  SurveyDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await OnnxService.instance.load(d.modelAsset);
      // 수고봉 모델은 있으면 쓰고 없으면 건너뛴다(스케일은 휴리스틱으로 대체).
      await OnnxService.pole.tryLoad(d.poleModelAsset);
      final dir = await getApplicationDocumentsDirectory();
      final overlayDir = Directory(p.join(dir.path, 'overlays'));
      if (!overlayDir.existsSync()) overlayDir.createSync(recursive: true);

      final azimuths = d.capturedAzimuths;
      for (int i = 0; i < azimuths.length; i++) {
        final az = azimuths[i];
        if (mounted) {
          setState(() => _status = tr(
              '${az.label} 분석 중 · ${i + 1}/${azimuths.length}',
              'Analyzing ${az.label} · ${i + 1}/${azimuths.length}'));
        }
        final overlayPath =
            p.join(overlayDir.path, '${d.treeId}_${az.code}_overlay.png');
        final res = await AnalysisService.instance.analyzeFace(
          az.code,
          d.photos[az]!,
          poleLengthM: d.poleLengthM,
          poleGapMetres: d.poleGapM,
          overlayOutPath: overlayPath,
          rawOutDir: d.rawDir, // 연구용 원시 산출물(없으면 건너뜀)
        );
        d.results[az] = res;
        // 오버레이 경로는 조사목·방위마다 고정이라, 재촬영 후 다시 분석하면 같은
        // 파일을 덮어쓴다. 캐시를 비우지 않으면 이전 오버레이가 그대로 보인다.
        if (res.overlayPath != null) {
          await FileImage(File(res.overlayPath!)).evict();
        }
        if (mounted) {
          setState(() {
            _currentOverlay = res.overlayPath;
            _progress = (i + 1) / azimuths.length;
          });
        }
      }
      d.integ = AnalysisService.instance.integrate(d.faces, d.dbhCm);
      if (!mounted) return;
      await Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => ResultScreen(draft: d)));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: Text(tr('AI 분석', 'AI Analysis'))),
      body: Padding(
        // 하단 시스템 바 높이를 더해 진행 카드가 네비게이션 바에 가리지 않게 한다.
        padding: EdgeInsets.fromLTRB(
            20, 20, 20, 20 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _error != null
                  ? _errorView(p)
                  : (_currentOverlay != null
                      ? Image.file(File(_currentOverlay!),
                          key: ValueKey(_currentOverlay), fit: BoxFit.contain)
                      : Container(
                          color: p.surface2,
                          child: const Center(child: CircularProgressIndicator()))),
            ),
          ),
          const SizedBox(height: 14),
          _legend(p),
          const SizedBox(height: 16),
          if (_error == null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                      child: Text(_status ?? tr('모델 준비 중', 'Preparing model'),
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                    ),
                    Text('${(_progress * 100).round()}%',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: p.navy)),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 9,
                      backgroundColor: p.surface2,
                      color: p.navy,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('YOLO26s-seg · 온디바이스', 'YOLO26s-seg · On-device'),
                        style: TextStyle(
                            fontFamily: 'monospace', fontSize: 12, color: p.muted)),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _errorView(AppPalette p) => Container(
        color: p.surface2,
        padding: const EdgeInsets.all(20),
        child: Center(
            child: Text(_error!,
                textAlign: TextAlign.center, style: TextStyle(color: p.muted))),
      );

  Widget _legend(AppPalette p) {
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontSize: 12.5, color: p.muted)),
        ]);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      dot(p.stem, tr('수간', 'Stem')),
      const SizedBox(width: 20),
      dot(p.soot, tr('그을음', 'Char')),
      const SizedBox(width: 20),
      dot(p.pole, tr('수고봉', 'Measuring pole')),
    ]);
  }
}

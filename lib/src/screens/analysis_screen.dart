import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  String _status = '모델을 불러오는 중...';
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
      final dir = await getApplicationDocumentsDirectory();
      final overlayDir = Directory(p.join(dir.path, 'overlays'));
      if (!overlayDir.existsSync()) overlayDir.createSync(recursive: true);

      final azimuths = d.capturedAzimuths;
      for (int i = 0; i < azimuths.length; i++) {
        final az = azimuths[i];
        if (mounted) {
          setState(() => _status = '${az.ko} 방위 분석 중... (${i + 1}/${azimuths.length})');
        }
        final overlayPath =
            p.join(overlayDir.path, '${d.treeId}_${az.code}_overlay.png');
        final res = await AnalysisService.instance.analyzeFace(
          az.code,
          d.photos[az]!,
          poleLengthM: d.poleLengthM,
          overlayOutPath: overlayPath,
        );
        d.results[az] = res;
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
    return Scaffold(
      appBar: AppBar(title: const Text('AI 분석 중')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          const SizedBox(height: 6),
          Text(_error == null ? '분석을 기다리세요.' : '분석 오류',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _error != null
                  ? _errorView()
                  : (_currentOverlay != null
                      ? Image.file(File(_currentOverlay!),
                          key: ValueKey(_currentOverlay), fit: BoxFit.contain)
                      : Container(
                          color: Colors.black12,
                          child: const Center(child: CircularProgressIndicator()))),
            ),
          ),
          const SizedBox(height: 14),
          _legend(),
          const SizedBox(height: 16),
          if (_error == null) ...[
            LinearProgressIndicator(
              value: _progress,
              minHeight: 8,
              backgroundColor: AppColors.border,
              color: AppColors.navy,
            ),
            const SizedBox(height: 10),
            Text('$_status  ${(_progress * 100).round()}%',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ],
        ]),
      ),
    );
  }

  Widget _errorView() => Container(
        color: Colors.black12,
        padding: const EdgeInsets.all(20),
        child: Center(
            child: Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary))),
      );

  Widget _legend() {
    Widget dot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ]);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      dot(AppColors.stemRed, '수간 영역'),
      const SizedBox(width: 22),
      dot(AppColors.sootGreen, '그을음 영역'),
    ]);
  }
}

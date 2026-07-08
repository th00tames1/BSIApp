import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/draft.dart';
import '../models/survey.dart';
import '../services/db_service.dart';
import '../theme.dart';

class ResultScreen extends StatefulWidget {
  final SurveyDraft draft;
  const ResultScreen({super.key, required this.draft});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late Azimuth _sel;
  bool _saving = false;

  SurveyDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    _sel = d.capturedAzimuths.isNotEmpty ? d.capturedAzimuths.first : Azimuth.east;
  }

  String _m(double v) => v.isNaN ? '–' : '${v.toStringAsFixed(2)} m';

  Future<void> _save() async {
    setState(() => _saving = true);
    final rec = d.toRecord();
    await DbService.instance.insert(rec);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.palette.green,
        content: const Text('저장되었습니다', style: TextStyle(fontWeight: FontWeight.w700)),
        duration: const Duration(milliseconds: 1400),
      ));
    Navigator.popUntil(context, (r) => r.isFirst); // → 지도
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final f = d.results[_sel];
    final integ = d.integ;
    final bsi = integ?.bsi ?? double.nan;
    final prob = integ?.mortality ?? double.nan;
    final verdict = integ?.verdict ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('결과'),
        actions: [
          IconButton(
            tooltip: '지도',
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            icon: const Icon(Icons.place_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          // eyebrow
          Row(children: [
            Expanded(
              child: Text(d.treeId,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      letterSpacing: 1.2,
                      color: p.muted,
                      fontWeight: FontWeight.w600)),
            ),
            Text(d.site,
                style: TextStyle(
                    fontFamily: 'monospace', fontSize: 11.5, color: p.muted)),
          ]),
          const SizedBox(height: 12),

          _verdictCard(p, bsi, prob, verdict),
          const SizedBox(height: 14),

          if (d.capturedAzimuths.length > 1) ...[
            _faceChips(p),
            const SizedBox(height: 12),
          ],

          _overlay(f, p),
          const SizedBox(height: 14),

          _metricCard(p, f),
          const SizedBox(height: 22),

          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: p.onNavy))
                : Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.check, size: 20),
                    SizedBox(width: 8),
                    Text('저장'),
                  ]),
          ),
        ],
      ),
    );
  }

  // ---- verdict: BSI linear meter + mortality arc gauge ----
  Widget _verdictCard(AppPalette p, double bsi, double prob, String verdict) {
    final cut = verdict == '벌채';
    final bsiColor = bsi.isNaN
        ? p.muted
        : (bsi < 3 ? p.green : (bsi < 6 ? p.ember : p.danger));
    final probColor = prob.isNaN
        ? p.muted
        : (prob < .33 ? p.green : (prob < .66 ? p.ember : p.danger));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Text('고사 판정',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            if (verdict.isNotEmpty)
              _pill(cut ? '벌채 권고' : '존치', cut ? p.danger : p.green,
                  icon: cut ? Icons.local_fire_department : Icons.check_circle_outline),
          ]),
          const SizedBox(height: 16),
          // BSI meter
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('BSI', style: TextStyle(fontSize: 13, color: p.muted, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(bsi.isNaN ? '–' : bsi.toStringAsFixed(1),
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 30,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: bsiColor)),
          ]),
          const SizedBox(height: 9),
          _sevBar(p, bsi.isNaN ? 0 : (bsi / 10).clamp(0, 1)),
          const SizedBox(height: 5),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('경미', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: p.muted)),
            Text('심함', style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: p.muted)),
          ]),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: p.line),
          ),
          // mortality gauge
          Row(children: [
            _ArcGauge(
              value: prob.isNaN ? 0 : prob,
              track: p.surface2,
              fill: probColor,
              label: prob.isNaN ? '–' : '${(prob * 100).round()}%',
              ink: p.ink,
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text('고사 확률',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _sevBar(AppPalette p, double frac) {
    return LayoutBuilder(builder: (_, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 20,
        child: Stack(clipBehavior: Clip.none, children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(colors: [p.green, p.ember, p.danger], stops: const [0, .55, 1]),
              ),
            ),
          ),
          Positioned(
            left: (w * frac).clamp(0, w) - 2.5,
            top: 0,
            child: Container(
              width: 5,
              height: 20,
              decoration: BoxDecoration(
                color: p.ink,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: p.surface, width: 2),
              ),
            ),
          ),
        ]),
      );
    });
  }

  Widget _faceChips(AppPalette p) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: d.capturedAzimuths.map((a) {
        final sel = a == _sel;
        final v = d.results[a]?.sootProportion ?? double.nan;
        final label = '${a.ko} ${v.isNaN ? '–' : '${(v * 100).round()}%'}';
        return GestureDetector(
          onTap: () => setState(() => _sel = a),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? p.green.withValues(alpha: 0.12) : p.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: sel ? p.green : p.line, width: 1.5),
            ),
            child: Text(label,
                style: TextStyle(
                    color: sel ? p.green : p.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ),
        );
      }).toList(),
    );
  }

  Widget _overlay(AzimuthResult? f, AppPalette p) {
    final path = f?.overlayPath ?? f?.imagePath;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: path != null
            ? Image.file(File(path), fit: BoxFit.cover)
            : Container(
                color: p.surface2,
                child: Center(
                    child: Text('이미지 없음', style: TextStyle(color: p.muted)))),
      ),
    );
  }

  Widget _metricCard(AppPalette p, AzimuthResult? f) {
    if (f == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          _metric(p, Icons.height, '그을음 높이', _m(f.sootHeightM)),
          Divider(height: 1, color: p.line),
          _metric(p, Icons.swap_horiz, '그을음 폭', _m(f.sootWidthM)),
          Divider(height: 1, color: p.line),
          _metric(p, Icons.park_outlined, '줄기 높이', _m(f.visibleStemHeightM)),
          Divider(height: 1, color: p.line),
          _metric(p, Icons.local_fire_department_outlined, '그을음 비율',
              f.sootProportion.isNaN ? '–' : f.sootProportion.toStringAsFixed(2),
              valueColor: p.green),
        ]),
      ),
    );
  }

  Widget _metric(AppPalette p, IconData ic, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(children: [
        Icon(ic, size: 20, color: p.green),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontSize: 13.5, color: p.muted))),
        Text(value,
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: valueColor ?? p.ink)),
      ]),
    );
  }

  Widget _pill(String text, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
        Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
    );
  }
}

/// Semicircle gauge for the mortality probability (a bounded %).
class _ArcGauge extends StatelessWidget {
  final double value; // 0..1
  final Color track, fill, ink;
  final String label;
  const _ArcGauge(
      {required this.value,
      required this.track,
      required this.fill,
      required this.ink,
      required this.label});
  @override
  Widget build(BuildContext context) {
    const w = 104.0, h = 60.0;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(children: [
        CustomPaint(size: const Size(w, h), painter: _GaugePainter(value.clamp(0, 1), track, fill)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 20,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: ink)),
        ),
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color track, fill;
  _GaugePainter(this.value, this.track, this.fill);
  @override
  void paint(Canvas canvas, Size size) {
    final strokeW = size.width * 0.12;
    final r = (size.width - strokeW) / 2;
    final center = Offset(size.width / 2, r + strokeW / 2);
    final rect = Rect.fromCircle(center: center, radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeW;
    canvas.drawArc(rect, math.pi, math.pi, false, base..color = track);
    if (value > 0) {
      canvas.drawArc(rect, math.pi, math.pi * value, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = strokeW
            ..color = fill);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.value != value || o.track != track || o.fill != fill;
}

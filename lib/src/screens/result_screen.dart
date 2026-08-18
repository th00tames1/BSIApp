import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../models/draft.dart';
import '../models/survey.dart';
import '../services/analysis_service.dart';
import '../services/db_service.dart';
import '../services/mortality.dart';
import '../theme.dart';
import 'bsi_table_screen.dart';
import 'manual_face_sheet.dart';

class ResultScreen extends StatefulWidget {
  final SurveyDraft draft;
  const ResultScreen({super.key, required this.draft});
  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late Azimuth _sel;
  bool _saving = false;
  late final TextEditingController _dbh =
      TextEditingController(text: d.dbhCm > 0 ? d.dbhCm.toStringAsFixed(0) : '');

  SurveyDraft get d => widget.draft;

  /// 수간 폭과 픽셀 스케일로 앱이 추정한 흉고직경(cm). 없으면 NaN.
  late final double _dbhAuto =
      AnalysisService.estimateDbhCm(d.results.values.toList());

  /// 자동 추정값을 그대로 쓰는 중인지(= 조사자가 손대지 않았는지).
  bool _dbhFromAuto = false;

  @override
  void initState() {
    super.initState();
    _sel = d.capturedAzimuths.isNotEmpty ? d.capturedAzimuths.first : Azimuth.east;
    // 조사자가 값을 넣지 않았으면 추정값을 채워 넣고 바로 판정까지 낸다.
    // 실측값이 있으면 언제든 덮어쓸 수 있다.
    if (d.dbhCm <= 0 && !_dbhAuto.isNaN && _dbhAuto > 0) {
      _dbhFromAuto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dbh.text = _dbhAuto.toStringAsFixed(0);
        _setDbh(_dbh.text);
      });
    }
    // 시연 모드: 결과를 잠시 보여준 뒤 판정표를 띄웠다 닫고 자동 저장한다.
    // "예시 사진으로 시험"으로 들어온 경우는 확인이 목적이므로 돌리지 않는다.
    if (demoMode.value && !d.isSample) _runDemoTour();
  }

  Future<void> _runDemoTour() async {
    await Future.delayed(const Duration(milliseconds: 3200)); // 결과 읽을 시간
    if (!mounted) return;
    final nav = Navigator.of(context);
    nav.push(MaterialPageRoute(
        builder: (_) =>
            BsiTableScreen(bsi: d.integ?.bsi ?? double.nan, dbhCm: d.dbhCm)));
    await Future.delayed(const Duration(milliseconds: 4000)); // 판정표 확인 시간
    if (!mounted) return;
    nav.pop(); // 판정표 닫기 → 결과 화면
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted || _saving) return;
    _save();
  }

  @override
  void dispose() {
    _dbh.dispose();
    super.dispose();
  }

  /// DBH drives the mortality logistic — recompute the verdict when it changes.
  void _setDbh(String s) {
    final v = double.tryParse(s.trim()) ?? 0;
    d.dbhCm = v;
    final integ = d.integ;
    if (integ != null && !integ.bsi.isNaN) {
      // facesUsed를 잃으면 기본값 4가 되어 "N개 방위만 계측" 안내가 사라진다.
      d.integ = BsiIntegration(integ.bsi, v, Mortality.probability(integ.bsi, v),
          Mortality.verdict(integ.bsi, v),
          facesUsed: integ.facesUsed);
    }
    setState(() {});
  }

  String _m(double v) => v.isNaN ? '–' : '${v.toStringAsFixed(2)} m';

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DbService.instance.insert(d.toRecord());
      // 예시 조사 저장이 진행 중이던 실제 조사 초안을 지우면 안 된다.
      if (!d.isSample) await clearDraft();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text(tr('저장 실패: $e', 'Save failed: $e'))));
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    // 시연 모드: 지도 화면이 이 신호를 보고 조사 기록 화면을 이어서 연다.
    if (demoMode.value && !d.isSample) demoTourSaved = true;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.palette.green,
        content: Text(tr('저장되었습니다', 'Saved'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
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
        title: Text(tr('결과', 'Results')),
        actions: [
          IconButton(
            tooltip: tr('판정표에서 확인', 'View in table'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => BsiTableScreen(bsi: bsi, dbhCm: d.dbhCm)),
            ),
            icon: const Icon(Icons.grid_on),
          ),
          IconButton(
            tooltip: tr('지도', 'Map'),
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            icon: const Icon(Icons.place_outlined),
          ),
        ],
      ),
      body: ListView(
        // 하단 시스템 바 높이를 더하지 않으면 마지막 "저장" 버튼이 가려진다.
        padding: EdgeInsets.fromLTRB(
            16, 10, 16, 24 + MediaQuery.viewPaddingOf(context).bottom),
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

          _dbhField(p),
          const SizedBox(height: 12),

          _verdictCard(p, bsi, prob, verdict),
          const SizedBox(height: 14),

          if (d.capturedAzimuths.length > 1) ...[
            _faceChips(p),
            const SizedBox(height: 12),
          ],

          _overlay(f, p),
          const SizedBox(height: 14),

          if (integ != null && integ.isPartial) ...[
            _partialNotice(p, integ.facesUsed),
            const SizedBox(height: 12),
          ],

          // 촬영하지 못한 방위를 야장 값으로 채워 4방위를 완성한다.
          _manualCard(p),
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
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.check, size: 20),
                    const SizedBox(width: 8),
                    Text(tr('저장', 'Save')),
                  ]),
          ),
        ],
      ),
    );
  }

  // ---- verdict: 고사 확률 게이지 하나로 통합 ----
  //
  // BSI 자체에는 경미/심함을 가르는 기준이 없다(판정 기준은 BSI × 흉고직경
  // 판정표의 고사 확률 30 %). 임의 눈금을 보여 주면 근거 없는 해석을 부르므로
  // BSI는 수치로만 두고, 판정은 고사 확률 하나로 읽게 한다.
  Widget _verdictCard(AppPalette p, double bsi, double prob, String verdict) {
    final cut = verdict == '벌채';
    final probColor = prob.isNaN
        ? p.muted
        : (prob < .30 ? p.green : (prob < .60 ? p.ember : p.danger));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text(tr('고사 판정', 'Verdict'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const Spacer(),
            if (verdict.isNotEmpty)
              _pill(cut ? tr('벌채 권고', 'Fell recommended') : verdictLabel(verdict),
                  cut ? p.danger : p.green,
                  icon: cut ? Icons.local_fire_department : Icons.check_circle_outline),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _ArcGauge(
              value: prob.isNaN ? 0 : prob,
              track: p.surface2,
              fill: probColor,
              label: prob.isNaN ? '–' : '${(prob * 100).round()}%',
              ink: p.ink,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('고사 확률', 'Mortality'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                        prob.isNaN
                            ? (d.dbhCm > 0
                                ? tr('판정표 범위를 벗어났습니다',
                                    'Outside the table range')
                                : tr('흉고직경을 입력하면 판정됩니다',
                                    'Enter DBH to evaluate'))
                            : tr('30 % 이상이면 벌채 권고',
                                'Fell recommended at 30 % or above'),
                        style: TextStyle(fontSize: 11.5, color: p.muted)),
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('BSI',
                          style: TextStyle(
                              fontSize: 13,
                              color: p.muted,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 10),
                      Text(bsi.isNaN ? '–' : bsi.toStringAsFixed(1),
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 26,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: p.ink)),
                    ]),
                  ]),
            ),
          ]),
        ]),
      ),
    );
  }

  /// 사진이 없는 방위 목록 — 직접 입력 대상.
  List<Azimuth> get _unshot =>
      Azimuth.values.where((a) => !d.photos.containsKey(a)).toList();

  /// 직접 입력을 받아 결과에 반영하고 BSI를 다시 합산한다.
  Future<void> _editManual(Azimuth a) async {
    final cur = d.results[a];
    final res = await showManualFaceSheet(context, a, cur?.manual == true ? cur : null);
    if (res == null || !mounted) return;
    setState(() {
      if (identical(res, removedManualFace)) {
        d.results.remove(a);
      } else {
        d.results[a] = res as AzimuthResult;
      }
      d.integ = AnalysisService.instance.integrate(d.faces, d.dbhCm);
    });
  }

  /// 미촬영 방위 안내 + 직접 입력 버튼. 넣을 것이 없으면 그리지 않는다.
  Widget _manualCard(AppPalette p) {
    final missing = _unshot;
    if (missing.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.edit_note, size: 20, color: p.navy),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('미촬영 방위 직접 입력', 'Un-photographed aspects'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
              tr('사진이 없는 방위는 야장 값을 넣어 BSI 합에 포함할 수 있습니다.',
                  'Aspects without a photo can be filled from field notes to join the BSI sum.'),
              style: TextStyle(fontSize: 12, height: 1.45, color: p.muted)),
          const SizedBox(height: 12),
          Row(children: [
            for (int i = 0; i < missing.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _manualChip(p, missing[i])),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _manualChip(AppPalette p, Azimuth a) {
    final r = d.results[a];
    final filled = r != null && r.manual;
    final label = filled
        ? '${a.label} ${(r.sootProportion * 100).round()}%'
        : '${a.label} +';
    return GestureDetector(
      onTap: () => _editManual(a),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: filled ? p.navy.withValues(alpha: 0.10) : p.surface,
          borderRadius: BorderRadius.circular(999),
          // 빈 칩도 테두리를 그려야 보인다 — 카드 배경색과 같아서 테두리가
          // 없으면 누를 곳이 있는지 알 수 없다(직접 입력의 유일한 진입점).
          border: Border.all(color: filled ? p.navy : p.line, width: 1.5),
        ),
        child: Text(label,
            style: TextStyle(
                color: filled ? p.navy : p.muted,
                fontWeight: FontWeight.w700,
                fontSize: 13)),
      ),
    );
  }

  Widget _faceChips(AppPalette p) {
    final az = d.capturedAzimuths;
    return Row(children: [
      for (int i = 0; i < az.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: _faceChip(p, az[i])),
      ],
    ]);
  }

  Widget _faceChip(AppPalette p, Azimuth a) {
    final sel = a == _sel;
    final v = d.results[a]?.sootProportion ?? double.nan;
    final label = '${a.label} ${v.isNaN ? '–' : '${(v * 100).round()}%'}';
    return GestureDetector(
      onTap: () => setState(() => _sel = a),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 9),
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
  }

  Widget _dbhField(AppPalette p) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
        child: Row(children: [
          Icon(Icons.straighten, size: 20, color: p.green),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('흉고직경 (DBH)', 'DBH'),
                    style: TextStyle(fontSize: 13.5, color: p.muted)),
                if (!_dbhAuto.isNaN && _dbhAuto > 0)
                  Text(
                    _dbhFromAuto
                        ? tr('자동 추정 ${_dbhAuto.toStringAsFixed(0)} cm',
                            'auto ${_dbhAuto.toStringAsFixed(0)} cm')
                        : tr('자동 추정 ${_dbhAuto.toStringAsFixed(0)} cm · 실측값 사용 중',
                            'auto ${_dbhAuto.toStringAsFixed(0)} cm · using entry'),
                    style: TextStyle(fontSize: 11, color: p.green),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: _dbh,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(hintText: '0', suffixText: 'cm', isDense: true),
              onChanged: (s) {
                _dbhFromAuto = false; // 조사자가 손대면 실측값 우선
                _setDbh(s);
              },
            ),
          ),
        ]),
      ),
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
                    child: Text(tr('이미지 없음', 'No image'),
                        style: TextStyle(color: p.muted)))),
      ),
    );
  }

  Widget _metricCard(AppPalette p, AzimuthResult? f) {
    if (f == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          _metric(p, Icons.height, tr('그을음 높이', 'Char height'),
              _m(f.sootHeightM)),
          Divider(height: 1, color: p.line),
          _metric(p, Icons.swap_horiz, tr('그을음 폭', 'Char width'),
              _m(f.sootWidthM)),
          Divider(height: 1, color: p.line),
          _metric(p, Icons.park_outlined, tr('줄기 높이', 'Stem height'),
              _m(f.visibleStemHeightM)),
          Divider(height: 1, color: p.line),
          _metric(p, Icons.local_fire_department_outlined,
              tr('그을음 비율', 'Char ratio'),
              f.sootProportion.isNaN ? '–' : f.sootProportion.toStringAsFixed(2),
              valueColor: p.green),
          Divider(height: 1, color: p.line),
          // 스케일 근거 — 이 값이 모든 미터 단위 수치를 좌우한다
          _metric(p, Icons.straighten, tr('수고봉 스케일', 'Pole scale'),
              f.pxPerMetre.isNaN
                  ? '–'
                  : '${f.pxPerMetre.toStringAsFixed(0)} px/m'),
        ]),
      ),
    );
  }

  /// 4방위 중 일부만 계측된 경우의 안내. BSI는 4방위 합이라 그대로 두면
  /// 과소평가되므로 환산해 쓰고 있다는 사실을 밝힌다.
  Widget _partialNotice(AppPalette p, int facesUsed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.ember.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.ember.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        Icon(Icons.info_outline, size: 18, color: p.ember),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tr(
              '$facesUsed개 방위만 계측돼 4방위 기준으로 환산했습니다. '
                  '수고봉 1 m 경계가 2개 이상 보이게 찍으면 정확해집니다.',
              'Only $facesUsed of 4 faces could be measured; BSI is scaled to a '
                  '4-face basis. Frame at least two 1 m pole marks for full accuracy.',
            ),
            style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.4),
          ),
        ),
      ]),
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

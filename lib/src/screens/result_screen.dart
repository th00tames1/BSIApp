import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../models/draft.dart';
import '../models/survey.dart';
import '../models/tuning.dart';
import '../services/analysis_service.dart';
import '../services/db_service.dart';
import '../services/mortality.dart';
import '../services/onnx_service.dart';
import '../services/raw_archive.dart';
import '../theme.dart';
import '../widgets/pole_gap_dialog.dart';
import 'bsi_table_screen.dart';
import 'face_adjust_screen.dart';
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
  bool _rescaling = false; // 흉고직경 기반 스케일 재분석 중
  late final TextEditingController _dbh =
      TextEditingController(text: d.dbhCm > 0 ? d.dbhCm.toStringAsFixed(0) : '');

  SurveyDraft get d => widget.draft;

  /// 수간 폭과 픽셀 스케일로 앱이 추정한 흉고직경(cm). 없으면 NaN.
  ///
  /// 흉고직경은 스케일에 비례하므로 수고봉 간격을 고치면 함께 움직인다.
  /// 한 번 굳혀 두면 판정(BSI × 흉고직경)이 서로 다른 간격 기준으로 나오므로
  /// 스케일이 바뀔 때마다 [_refreshAutoDbh]로 다시 센다.
  double _dbhAuto = double.nan;

  /// 자동 추정값을 그대로 쓰는 중인지(= 조사자가 손대지 않았는지).
  bool _dbhFromAuto = false;

  /// 면 계측값이 바뀐 뒤 자동 추정 흉고직경을 다시 센다.
  ///
  /// 조사자가 실측값을 넣지 않아 추정값을 쓰는 중이었다면 그 값도 함께 따라가야
  /// 한다. 그러지 않으면 BSI만 새 간격으로 줄고 흉고직경은 옛 스케일로 남아,
  /// 고사 확률이 두 기준을 섞어 계산된다(존치 쪽으로 기울 수 있다).
  void _refreshAutoDbh() {
    _dbhAuto = AnalysisService.estimateDbhCm(d.results.values.toList());
    if (_dbhFromAuto && !_dbhAuto.isNaN && _dbhAuto > 0) {
      _dbh.text = _dbhAuto.toStringAsFixed(0);
      _setDbh(_dbh.text); // 판정까지 새 값으로 다시 낸다
    }
  }

  @override
  void initState() {
    super.initState();
    _dbhAuto = AnalysisService.estimateDbhCm(d.results.values.toList());
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
      final rec = d.toRecord();
      await DbService.instance.insert(rec);
      // 연구용: 저장 시점의 최종 레코드(판정·DBH·직접 입력 포함)를 번들에 남긴다.
      final raw = d.rawDir;
      if (raw != null) {
        await RawArchive.writeJson(raw, 'record.json', {
          'savedAt': DateTime.now().toIso8601String(),
          'record': rec.toMap()..remove('faces'),
          'faces': [for (final f in rec.faces) f.toJson()],
          'integration': d.integ == null
              ? null
              : {
                  'bsi': d.integ!.bsi.isNaN ? null : d.integ!.bsi,
                  'facesUsed': d.integ!.facesUsed,
                  'mortality': d.integ!.mortality.isNaN ? null : d.integ!.mortality,
                  'verdict': d.integ!.verdict,
                },
          'dbh': {
            'enteredCm': d.dbhCm,
            'autoEstimateCm': _dbhAuto.isNaN ? null : _dbhAuto,
            'usedAuto': _dbhFromAuto,
          },
          'models': {
            'seg': d.modelAsset,
            'pole': d.poleModelAsset,
          },
          'environment': RawArchive.environment(),
        });
      }
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
            tooltip: tr('전체 다시 분석', 'Re-analyse all'),
            onPressed: _rescaling ? null : () => _reanalyse(),
            icon: _rescaling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
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

          // 촬영한 면도 현장에서 손으로 바로잡을 수 있어야 한다(값·지표면·대상목).
          if (f != null && !f.manual) ...[
            _faceActions(p, f),
            const SizedBox(height: 14),
          ],

          // 스케일이 없는 면이 하나라도 있으면, 어느 면을 보고 있든 여기서
          // 흉고직경으로 높이를 세울 수 있어야 한다(현장 보고: 선택한 면에
          // 안내가 없으면 버튼 자체를 찾지 못했다).
          if (_hasUnscaledFace) ...[
            _dbhScaleCard(p),
            const SizedBox(height: 14),
          ],

          // 이 방위에서 무엇이 안 잡혔는지 — 값이 "–"인 이유를 현장에서 바로 알게.
          if (_faceIssue(f) != null) ...[
            // 버튼은 아래 카드에 하나만 둔다(같은 버튼이 두 번 보이지 않게).
            _faceNotice(p, _faceIssue(f)!),
            const SizedBox(height: 12),
          ],
          if (_faceInfo(f) != null) ...[
            _faceNotice(p, _faceInfo(f)!, warning: false),
            const SizedBox(height: 12),
          ],
          _metricCard(p, f),
          const SizedBox(height: 10),

          // 수고봉은 조사목마다 다를 수 있다. 간격이 어긋나면 모든 높이가 같은
          // 배율로 틀어지므로, 저장하기 전에 여기서 바로잡을 수 있어야 한다.
          _poleGapRow(p),
          const SizedBox(height: 22),

          ElevatedButton(
            // 재분석 중 저장하면 일부는 환산값, 일부는 재분석값인 반쯤 갱신된
            // 상태가 저장되고, 화면을 벗어난 뒤에도 남은 루프가 같은 경로의
            // 오버레이·산출물을 덮어써 기록과 어긋난다.
            onPressed: (_saving || _rescaling) ? null : _save,
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
                            ? (bsi.isNaN
                                ? (_hasUnscaledFace
                                    ? tr('높이를 잰 방위가 없어 BSI를 낼 수 없습니다. 실측 흉고직경을 넣고 "흉고직경으로 높이 추정"을 누르세요',
                                        'No face has a scale, so BSI cannot be computed. Enter the measured DBH and tap "Estimate heights from DBH"')
                                    : tr('계측된 방위가 없어 BSI를 낼 수 없습니다',
                                        'No measured face - BSI cannot be computed'))
                                : d.dbhCm > 0
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
          _metric(
              p,
              Icons.straighten,
              f.scaleSource == 'dbh'
                  ? tr('스케일 · 흉고직경 기반', 'Scale · from DBH')
                  : tr('수고봉 스케일', 'Pole scale'),
              f.pxPerMetre.isNaN
                  ? '–'
                  : '${f.pxPerMetre.toStringAsFixed(0)} px/m'),
        ]),
      ),
    );
  }

  /// 4방위 중 일부만 계측된 경우의 안내. BSI는 4방위 합이라 그대로 두면
  /// 과소평가되므로 환산해 쓰고 있다는 사실을 밝힌다.
  /// 수간은 잡혔는데 스케일(수고봉)이 없는 촬영 방위가 하나라도 있는지.
  bool get _hasUnscaledFace => d.results.values.any(_isUnscaled);

  static bool _isUnscaled(AzimuthResult f) =>
      f.analysed && !f.manual && f.treePx > 0 && f.pxPerMetre.isNaN;

  /// 선택된 방위의 검출 실패 사유. 없으면 null.
  String? _faceIssue(AzimuthResult? f) {
    if (f == null || !f.analysed || f.manual) return null;
    if (f.treePx == 0) {
      return tr('이 방위에서 수간을 찾지 못했습니다. 나무 전체가 화면에 들어오게 다시 촬영하세요.',
          'No stem detected on this face. Retake with the whole trunk in frame.');
    }
    if (f.pxPerMetre.isNaN) {
      return d.dbhCm > 0
          ? tr('수고봉 1 m 경계를 찾지 못해 높이(m)를 잴 수 없습니다. 수고봉이 보이게 다시 촬영하거나, 입력한 흉고직경으로 높이를 추정할 수 있습니다(정밀도 낮음).',
              'No 1 m pole marks found, so heights cannot be measured. Retake with the pole visible, or estimate heights from the entered DBH (lower precision).')
          : tr('수고봉 1 m 경계를 찾지 못해 높이(m)를 잴 수 없습니다. 수고봉이 보이게 다시 촬영하거나, 실측 흉고직경을 입력하면 그것으로 높이를 추정할 수 있습니다.',
              'No 1 m pole marks found, so heights cannot be measured. Retake with the pole visible, or enter the measured DBH to estimate heights from it.');
    }
    return null;
  }

  /// 수고봉 없이 흉고직경으로 스케일을 세운 방위에는 그 사실을 남긴다.
  String? _faceInfo(AzimuthResult? f) {
    if (f == null || f.scaleSource != 'dbh') return null;
    return tr('이 방위는 수고봉이 없어 입력한 흉고직경(${d.dbhCm.toStringAsFixed(0)} cm)으로 스케일을 추정했습니다. 수고봉 계측보다 정밀도가 낮습니다.',
        'Scale on this face was estimated from the entered DBH (${d.dbhCm.toStringAsFixed(0)} cm) because no pole was found - lower precision than a pole measurement.');
  }

  Widget _faceNotice(AppPalette p, String msg,
      {bool warning = true, Widget? action}) {
    final c = warning ? p.danger : p.ember;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(warning ? Icons.no_photography_outlined : Icons.info_outline,
              size: 18, color: c),
          const SizedBox(width: 10),
          Expanded(
            child: Text(msg,
                style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.4)),
          ),
        ]),
        if (action != null) ...[const SizedBox(height: 8), action],
      ]),
    );
  }

  /// 스케일이 없는 촬영 방위에 한해, 입력한 흉고직경으로 스케일을 세워 다시 분석한다.
  /// 수고봉·수동 스케일이 있는 방위는 건드리지 않는다(analyzeFace가 보장).
  Future<void> _rescaleFromDbh() async {
    if (_rescaling || d.dbhCm <= 0) return;
    setState(() => _rescaling = true);
    try {
      await OnnxService.instance.load(d.modelAsset);
      await OnnxService.pole.tryLoad(d.poleModelAsset);
      for (final az in d.capturedAzimuths) {
        final f = d.results[az];
        if (f == null || !_isUnscaled(f)) continue;
        final res = await AnalysisService.instance.analyzeFace(
          az.code,
          d.photos[az]!,
          poleLengthM: d.poleLengthM,
          poleGapMetres: d.poleGapM,
          overlayOutPath: f.overlayPath,
          dbhCmForScale: d.dbhCm,
          rawOutDir: d.rawDir, // 흉고직경 스케일 산출물로 덮어쓴다(scale.source='dbh')
          tuning: f.tuning,
        );
        if (res.overlayPath != null) {
          await FileImage(File(res.overlayPath!)).evict();
        }
        d.results[az] = res.copyWith(tuning: f.tuning);
      }
      d.integ = AnalysisService.instance.integrate(d.faces, d.dbhCm);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(tr('흉고직경 스케일 추정 실패: $e',
                  'DBH-scale estimation failed: $e'))));
      }
    } finally {
      if (mounted) setState(() => _rescaling = false);
    }
  }

  /// 선택한 면을 손으로 바로잡는 행동 두 가지.
  Widget _faceActions(AppPalette p, AzimuthResult f) {
    final az = _sel;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.tune, size: 20, color: p.navy),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('${az.label} 면 손보기', 'Fix ${az.label}'),
                  style:
                      const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            ),
            if (f.manualEdited)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                    color: p.ember.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(tr('직접 입력됨', 'edited'),
                    style: TextStyle(
                        color: p.ember,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 4),
          Text(
              tr('자동 분석이 어긋나면 값을 직접 넣거나, 지표면·대상목을 지정해 다시 분석하세요.',
                  'Enter values directly, or set the ground line / target trunk and re-analyse.'),
              style: TextStyle(fontSize: 11.5, height: 1.4, color: p.muted)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _rescaling ? null : () => _editFaceValues(az, f),
                icon: const Icon(Icons.edit_note, size: 18),
                label: Text(tr('값 직접 입력', 'Enter values'),
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _rescaling ? null : () => _adjustFace(az, f),
                icon: const Icon(Icons.crop_free, size: 18),
                label: Text(tr('지표면·대상목', 'Ground / target'),
                    style: const TextStyle(fontSize: 12.5)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  /// 촬영한 면의 값을 조사자 값으로 덮는다(사진·오버레이는 유지).
  Future<void> _editFaceValues(Azimuth az, AzimuthResult f) async {
    final res = await showManualFaceSheet(context, az, f);
    if (res is! AzimuthResult || !mounted) return;
    setState(() {
      d.results[az] = res;
      d.integ = AnalysisService.instance.integrate(d.faces, d.dbhCm);
    });
  }

  /// 지표면·대상목(·개발자 모드에서는 밝기/대비)을 조정하고 그 면만 다시 분석.
  Future<void> _adjustFace(Azimuth az, AzimuthResult f) async {
    final path = d.photos[az];
    if (path == null) return;
    final t = await Navigator.push<FaceTuning>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceAdjustScreen(
            imagePath: path, label: az.label, tuning: f.tuning),
      ),
    );
    if (t == null || !mounted) return;
    await _reanalyse(only: az, tuning: t);
  }

  /// 저장된 사진으로 다시 분석한다. [only]가 있으면 그 면만.
  ///
  /// 조사자가 손으로 넣은 값(manualEdited)은 재분석이 덮어쓰지 않는다 —
  /// 다시 분석하면 애써 넣은 야장 값이 조용히 사라지기 때문. 조정값을 새로
  /// 준 면만 그 값으로 다시 계산한다.
  Future<void> _reanalyse({Azimuth? only, FaceTuning? tuning}) async {
    if (_rescaling) return;
    final targets = (only != null ? [only] : d.capturedAzimuths)
        .where((a) => d.photos[a] != null)
        .toList();
    if (targets.isEmpty) return;
    setState(() => _rescaling = true);
    try {
      await OnnxService.instance.load(d.modelAsset);
      await OnnxService.pole.tryLoad(d.poleModelAsset);
      for (final az in targets) {
        final cur = d.results[az];
        if (only == null && (cur?.manualEdited ?? false)) continue;
        final t = (only != null && tuning != null)
            ? tuning
            : (cur?.tuning ?? FaceTuning.none);
        final res = await AnalysisService.instance.analyzeFace(
          az.code,
          d.photos[az]!,
          poleLengthM: d.poleLengthM,
          poleGapMetres: d.poleGapM,
          overlayOutPath: cur?.overlayPath,
          dbhCmForScale: d.dbhCm > 0 ? d.dbhCm : null,
          rawOutDir: d.rawDir,
          tuning: t,
        );
        if (res.overlayPath != null) {
          await FileImage(File(res.overlayPath!)).evict();
        }
        d.results[az] = res.copyWith(tuning: t);
      }
      _refreshAutoDbh();
      d.integ = AnalysisService.instance.integrate(d.faces, d.dbhCm);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 1400),
            content: Text(only == null
                ? tr('다시 분석했습니다', 'Re-analysed')
                : tr('${only.label} 면을 다시 분석했습니다',
                    '${only.label} re-analysed')),
          ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(tr('다시 분석 실패: $e', 'Re-analysis failed: $e'))));
      }
    } finally {
      if (mounted) setState(() => _rescaling = false);
    }
  }

  /// 스케일 없는 면이 있을 때 늘 보이는 카드 — 어느 면을 보고 있든 접근 가능.
  /// 앱이 낸 값이 실제와 동떨어져 보이는가 — 대개 수고봉 간격이 어긋난 탓이다.
  ///
  /// 간격은 스케일에 그대로 곱해지므로, 값이 틀리면 수고·흉고직경이 함께
  /// 비현실적인 크기로 나온다. 조사자가 저장 전에 알아채도록 짚어 준다.
  bool get _scaleSuspect {
    double best = double.nan;
    for (final f in d.faces) {
      final v = f.visibleStemHeightM;
      if (v.isNaN) continue;
      if (best.isNaN || v > best) best = v;
    }
    if (!best.isNaN && (best > 40 || best < 1.0)) return true;
    if (!_dbhAuto.isNaN && (_dbhAuto > 150 || _dbhAuto < 3)) return true;
    return false;
  }

  /// 수고봉 간격을 고치고 다시 계산한다.
  ///
  /// 간격은 스케일에 선형으로 곱해지므로 산술만으로 즉시 정확히 반영된다.
  /// 사진이 있으면 이어서 다시 분석해 흉고직경 추정까지 맞춘다.
  Future<void> _editPoleGap() async {
    final v = await showDialog<double>(
      context: context,
      builder: (_) => PoleGapDialog(
        faces: d.faces,
        dbhCm: d.dbhCm,
        currentGap: d.poleGapM,
      ),
    );
    if (v == null || !mounted || v == d.poleGapM) return;
    final k = v / d.poleGapM;
    setState(() {
      for (final az in d.results.keys.toList()) {
        d.results[az] = rescaleFacesForGap([d.results[az]!], k).first;
      }
      d.poleGapM = v;
      _refreshAutoDbh();
      d.integ = AnalysisService.instance.integrate(d.faces, d.dbhCm);
    });
    final hasShots = d.capturedAzimuths
        .any((az) => d.photos[az] != null && !(d.results[az]?.manual ?? true));
    if (hasShots) await _reanalyse();
  }

  Widget _poleGapRow(AppPalette p) {
    final suspect = _scaleSuspect;
    return InkWell(
      onTap: _rescaling ? null : _editPoleGap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: suspect ? p.ember.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: suspect
                  ? p.ember.withValues(alpha: 0.45)
                  : p.line),
        ),
        child: Row(children: [
          Icon(suspect ? Icons.warning_amber_rounded : Icons.straighten_outlined,
              size: 18, color: suspect ? p.ember : p.green),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                suspect
                    ? tr('계측값이 실제와 달라 보입니다. 수고봉 간격이 맞는지 확인하세요.',
                        'Measurements look off — check the pole spacing.')
                    : tr('수고봉 간격', 'Pole spacing'),
                style: TextStyle(
                    fontSize: suspect ? 11.5 : 12.5,
                    height: 1.4,
                    color: suspect ? p.ember : p.muted)),
          ),
          const SizedBox(width: 8),
          Text('${d.poleGapM.toStringAsFixed(2)} m',
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          Icon(Icons.chevron_right, size: 18, color: p.muted),
        ]),
      ),
    );
  }

  Widget _dbhScaleCard(AppPalette p) {
    final n = d.results.values.where(_isUnscaled).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: p.ember.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.ember.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.straighten, size: 18, color: p.ember),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                d.dbhCm > 0
                    ? tr('$n개 방위에서 수고봉 스케일이 없습니다. 입력한 흉고직경(${d.dbhCm.toStringAsFixed(0)} cm)으로 높이를 추정할 수 있습니다.',
                        '$n face(s) have no pole scale. Heights can be estimated from the entered DBH (${d.dbhCm.toStringAsFixed(0)} cm).')
                    : tr('$n개 방위에서 수고봉 스케일이 없습니다. 위에 실측 흉고직경을 넣으면 높이를 추정할 수 있습니다.',
                        '$n face(s) have no pole scale. Enter the measured DBH above to estimate heights.'),
                style: TextStyle(fontSize: 11.5, color: p.muted, height: 1.4)),
          ),
        ]),
        const SizedBox(height: 8),
        _rescaleButton(p),
      ]),
    );
  }

  Widget _rescaleButton(AppPalette p) {
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.tonalIcon(
        onPressed: (_rescaling || d.dbhCm <= 0) ? null : _rescaleFromDbh,
        icon: _rescaling
            ? const SizedBox(
                width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.straighten, size: 16),
        label: Text(tr('흉고직경으로 높이 추정', 'Estimate heights from DBH'),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
      ),
    );
  }

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

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/survey.dart';
import '../services/csv_export.dart';
import '../services/db_service.dart';
import '../services/mortality.dart';
import '../theme.dart';

/// Detail view for a saved survey record (opened from the map pin / 기록).
class SavedScreen extends StatefulWidget {
  final SurveyRecord record;
  const SavedScreen({super.key, required this.record});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  final _pager = PageController();
  int _page = 0;
  late SurveyRecord record = widget.record;

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  // ── 계측값: 레코드에 수정값이 있으면 그것을, 없으면 방위별 최대값 ──
  double _maxOf(double Function(AzimuthResult) pick) {
    double best = double.nan;
    for (final f in record.faces) {
      final v = pick(f);
      if (v.isNaN) continue;
      if (best.isNaN || v > best) best = v;
    }
    return best;
  }

  double get _heightM =>
      record.heightM.isNaN ? _maxOf((f) => f.visibleStemHeightM) : record.heightM;
  double get _sootM =>
      record.sootMaxM.isNaN ? _maxOf((f) => f.sootHeightM) : record.sootMaxM;

  /// 수정값을 DB에 반영하고 화면을 갱신한다.
  Future<void> _apply(SurveyRecord next) async {
    await DbService.instance.update(next);
    if (mounted) setState(() => record = next);
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('조사목 삭제', 'Delete tree')),
        content: Text(tr('조사목 ${record.treeId}을(를) 삭제합니다. 되돌릴 수 없습니다.',
            'Tree ${record.treeId} will be deleted. This cannot be undone.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('취소', 'Cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('삭제', 'Delete'))),
        ],
      ),
    );
    if (ok != true) return;
    if (record.dbId != null) await DbService.instance.delete(record.dbId!);
    if (context.mounted) Navigator.pop(context, true);
  }

  // ── 항목 수정 ────────────────────────────────────────────────────
  Future<void> _editSpecies() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final s in majorSpecies)
            ListTile(
              dense: true,
              leading: Icon(
                  s == record.species
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
      final t = await _askText(tr('수종 입력', 'Species'), record.species);
      if (t == null || t.isEmpty) return;
      species = t;
    }
    await _apply(record.copyWith(species: species));
  }

  /// 숫자 항목 수정. [onValue]가 새 레코드를 만든다.
  Future<void> _editNumber(String title, double current, String unit,
      SurveyRecord Function(double v) onValue) async {
    final t = await _askText(
        title, current.isNaN ? '' : current.toStringAsFixed(1),
        number: true, unit: unit);
    if (t == null) return;
    final v = double.tryParse(t);
    if (v == null || v < 0) return;
    await _apply(onValue(v));
  }

  Future<String?> _askText(String title, String initial,
      {bool number = false, String? unit}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(suffixText: unit),
        ),
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
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cut = record.verdict == '벌채';
    final faces =
        record.faces.where((f) => (f.overlayPath ?? f.imagePath) != null).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('조사목 상세', 'Tree detail')),
        actions: [
          IconButton(
            tooltip: tr('CSV 내보내기', 'Export CSV'),
            onPressed: () => CsvExport.share([record]),
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: tr('삭제', 'Delete'),
            onPressed: () => _delete(context),
            icon: Icon(Icons.delete_outline, color: p.danger),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(record.treeId,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            if (record.verdict.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: (cut ? p.danger : p.green).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(verdictLabel(record.verdict),
                    style: TextStyle(
                        color: cut ? p.danger : p.green,
                        fontWeight: FontWeight.w700)),
              ),
          ]),
          if (record.site.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(record.site, style: TextStyle(color: p.muted, fontSize: 13)),
          ],
          const SizedBox(height: 12),
          if (faces.isNotEmpty) ...[
            _photoPager(p, faces),
            const SizedBox(height: 8),
            _dots(p, faces.length),
            const SizedBox(height: 10),
          ],
          // 판정 결과 — 분석에서 나온 값이라 수정하지 않는다.
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                _row(p, Icons.local_fire_department_outlined,
                    tr('통합 BSI', 'Integrated BSI'),
                    record.bsi.isNaN ? '–' : record.bsi.toStringAsFixed(2)),
                Divider(height: 1, color: p.line),
                _row(p, Icons.warning_amber_rounded, tr('고사 확률', 'Mortality'),
                    record.mortalityProb.isNaN
                        ? '–'
                        : '${(record.mortalityProb * 100).round()}%'),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // 조사 정보 — 항목을 누르면 수정할 수 있다.
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                _row(p, Icons.forest_outlined, tr('수종', 'Species'),
                    record.species.isEmpty ? '–' : speciesLabel(record.species),
                    onTap: _editSpecies),
                Divider(height: 1, color: p.line),
                _row(p, Icons.straighten, tr('흉고직경', 'DBH'),
                    record.dbhCm == 0
                        ? '–'
                        : '${record.dbhCm.toStringAsFixed(1)} cm', onTap: () {
                  _editNumber(tr('흉고직경', 'DBH'), record.dbhCm, 'cm', (v) {
                    // DBH가 바뀌면 판정표에서 고사 확률·판정을 다시 읽는다.
                    return record.copyWith(
                      dbhCm: v,
                      mortalityProb: Mortality.probability(record.bsi, v),
                      verdict: Mortality.verdict(record.bsi, v),
                    );
                  });
                }),
                Divider(height: 1, color: p.line),
                _row(p, Icons.height, tr('수고', 'Tree height'),
                    _heightM.isNaN ? '–' : '${_heightM.toStringAsFixed(2)} m',
                    onTap: () {
                  _editNumber(tr('수고', 'Tree height'), _heightM, 'm',
                      (v) => record.copyWith(heightM: v));
                }),
                Divider(height: 1, color: p.line),
                _row(p, Icons.local_fire_department_outlined,
                    tr('그을음 높이', 'Char height'),
                    _sootM.isNaN ? '–' : '${_sootM.toStringAsFixed(2)} m',
                    onTap: () {
                  _editNumber(tr('그을음 높이', 'Char height'), _sootM, 'm',
                      (v) => record.copyWith(sootMaxM: v));
                }),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// 결과 사진을 표 위에 바로 띄우고 옆으로 넘겨 본다.
  /// 각 장에 방위와 그을음 비율을 함께 표시한다.
  Widget _photoPager(AppPalette p, List<AzimuthResult> faces) {
    final h = math.min(math.max(
        MediaQuery.of(context).size.height * 0.38, 240.0), 420.0);
    return SizedBox(
      height: h,
      child: PageView.builder(
        controller: _pager,
        itemCount: faces.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) {
          final f = faces[i];
          final path = f.overlayPath ?? f.imagePath!;
          final pct = f.sootProportion.isNaN
              ? '–'
              : '${(f.sootProportion * 100).round()}%';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(fit: StackFit.expand, children: [
                Image.file(File(path), fit: BoxFit.cover),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xB3080C12),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(
                        tr('${azimuthLabelFromCode(f.azimuth)} · 그을음 $pct',
                            '${azimuthLabelFromCode(f.azimuth)} · Char $pct'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                        color: const Color(0xB3080C12),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('${i + 1}/${faces.length}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _dots(AppPalette p, int n) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (int i = 0; i < n; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == _page ? 18 : 7,
          height: 7,
          decoration: BoxDecoration(
              color: i == _page ? p.navy : p.line,
              borderRadius: BorderRadius.circular(999)),
        ),
    ]);
  }

  // 사진이 위 공간을 차지하는 만큼 표는 세로만 살짝 줄였다(좌우 여백은 유지).
  // onTap이 있으면 수정 가능 표시(연필)를 함께 그린다.
  Widget _row(AppPalette p, IconData ic, String label, String value,
      {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(children: [
        Icon(ic, size: 18, color: p.green),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: p.muted))),
        Text(value,
            style: const TextStyle(
                fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w700)),
        if (onTap != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.edit_outlined, size: 14, color: p.muted),
        ],
      ]),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

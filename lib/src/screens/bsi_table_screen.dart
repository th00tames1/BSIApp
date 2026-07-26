import 'package:flutter/material.dart';

import '../services/bsi_table.dart';
import '../theme.dart';

/// 존치·벌채 판정표 조회. BSI·DBH를 넣으면 해당 칸을 짚어준다.
class BsiTableScreen extends StatefulWidget {
  /// 결과 화면에서 열면 그 조사목의 값으로 시작한다.
  final double? bsi;
  final double? dbhCm;
  const BsiTableScreen({super.key, this.bsi, this.dbhCm});

  @override
  State<BsiTableScreen> createState() => _BsiTableScreenState();
}

class _BsiTableScreenState extends State<BsiTableScreen> {
  late int? _bsi = (widget.bsi != null && !widget.bsi!.isNaN)
      ? widget.bsi!.round().clamp(BsiTable.minBsi, BsiTable.maxBsi)
      : null;
  late int? _dbh = (widget.dbhCm != null && widget.dbhCm! > 0)
      ? _nearestDbh(widget.dbhCm!)
      : null;

  static int _nearestDbh(double v) {
    var best = BsiTable.dbhCm.first;
    for (final d in BsiTable.dbhCm) {
      if ((d - v).abs() < (best - v).abs()) best = d;
    }
    return best;
  }

  static const _cellW = 40.0;
  static const _cellH = 32.0;
  static const _labelW = 46.0;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final hit = (_bsi != null && _dbh != null)
        ? BsiTable.percent[_bsi! - BsiTable.minBsi][BsiTable.dbhCm.indexOf(_dbh!)]
        : null;

    return Scaffold(
      appBar: AppBar(title: const Text('존치·벌채 판정표')),
      body: Column(children: [
        _picker(p, hit),
        Divider(height: 1, color: p.line),
        Expanded(child: _table(p)),
        _footer(p),
      ]),
    );
  }

  // ── 값 선택 + 판정 ────────────────────────────────────────────────
  Widget _picker(AppPalette p, int? hit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: _stepper(p, 'BSI', _bsi?.toString() ?? '–',
                onMinus: () => _setBsi((_bsi ?? BsiTable.minBsi) - 1),
                onPlus: () => _setBsi((_bsi ?? BsiTable.minBsi - 1) + 1)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _stepper(p, 'DBH', _dbh == null ? '–' : '$_dbh cm',
                onMinus: () => _stepDbh(-1), onPlus: () => _stepDbh(1)),
          ),
        ]),
        if (hit != null) ...[
          const SizedBox(height: 10),
          _verdictBar(p, hit),
        ],
      ]),
    );
  }

  Widget _stepper(AppPalette p, String label, String value,
      {required VoidCallback onMinus, required VoidCallback onPlus}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.line)),
      child: Row(children: [
        IconButton(
            onPressed: onMinus,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.remove, size: 18, color: p.muted)),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: TextStyle(fontSize: 10.5, color: p.muted, fontWeight: FontWeight.w700)),
            Text(value,
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700)),
          ]),
        ),
        IconButton(
            onPressed: onPlus,
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 18, color: p.muted)),
      ]),
    );
  }

  Widget _verdictBar(AppPalette p, int hit) {
    final cut = BsiTable.isCut(hit);
    final c = cut ? p.danger : p.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.5))),
      child: Row(children: [
        Icon(cut ? Icons.local_fire_department : Icons.check_circle_outline,
            size: 20, color: c),
        const SizedBox(width: 10),
        Expanded(
          child: Text('BSI $_bsi · DBH $_dbh cm',
              style: TextStyle(fontSize: 13, color: p.muted)),
        ),
        Text('$hit%',
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: c)),
        const SizedBox(width: 10),
        Text(cut ? '벌채' : '존치',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }

  void _setBsi(int v) {
    if (v < BsiTable.minBsi || v > BsiTable.maxBsi) return;
    setState(() => _bsi = v);
  }

  void _stepDbh(int dir) {
    final list = BsiTable.dbhCm;
    final i = _dbh == null ? -1 : list.indexOf(_dbh!);
    final next = (i + dir).clamp(0, list.length - 1);
    setState(() => _dbh = list[i < 0 && dir < 0 ? 0 : next]);
  }

  // ── 표 ────────────────────────────────────────────────────────────
  Widget _table(AppPalette p) {
    return SingleChildScrollView(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 고정 BSI 열
        Column(children: [
          _cell(p, 'BSI', w: _labelW, header: true),
          for (var b = BsiTable.minBsi; b <= BsiTable.maxBsi; b++)
            _cell(p, '$b',
                w: _labelW, header: true, selected: b == _bsi),
        ]),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(children: [
              Row(children: [
                for (final d in BsiTable.dbhCm)
                  _cell(p, '$d', header: true, selected: d == _dbh),
              ]),
              for (var b = BsiTable.minBsi; b <= BsiTable.maxBsi; b++)
                Row(children: [
                  for (var j = 0; j < BsiTable.dbhCm.length; j++)
                    _dataCell(p, b, j),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _dataCell(AppPalette p, int bsi, int j) {
    final v = BsiTable.percent[bsi - BsiTable.minBsi][j];
    final cut = BsiTable.isCut(v);
    final isHit = bsi == _bsi && BsiTable.dbhCm[j] == _dbh;
    final base = cut ? p.danger : p.green;
    return GestureDetector(
      onTap: () => setState(() {
        _bsi = bsi;
        _dbh = BsiTable.dbhCm[j];
      }),
      child: Container(
        width: _cellW,
        height: _cellH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: base.withValues(alpha: cut ? 0.07 : 0.18),
          border: Border(
            right: BorderSide(color: p.line, width: 0.5),
            bottom: BorderSide(color: p.line, width: 0.5),
          ),
        ),
        foregroundDecoration: isHit
            ? BoxDecoration(border: Border.all(color: p.ink, width: 2.4))
            : null,
        child: Text('$v',
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                fontWeight: isHit ? FontWeight.w700 : FontWeight.w600,
                color: cut ? p.ink : base)),
      ),
    );
  }

  Widget _cell(AppPalette p, String text,
      {double w = _cellW, bool header = false, bool selected = false}) {
    return Container(
      width: w,
      height: _cellH,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? p.navy.withValues(alpha: 0.14) : p.surface2,
        border: Border(
          right: BorderSide(color: p.line, width: 0.5),
          bottom: BorderSide(color: p.line, width: 0.5),
        ),
      ),
      child: Text(text,
          style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? p.navy : p.muted)),
    );
  }

  Widget _footer(AppPalette p) {
    Widget key(Color c, double a, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                  color: c.withValues(alpha: a), borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontSize: 12, color: p.muted)),
        ]);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
          color: p.surface, border: Border(top: BorderSide(color: p.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          key(p.green, 0.18, '존치 (30% 미만)'),
          const SizedBox(width: 16),
          key(p.danger, 0.07, '벌채 (30% 이상)'),
        ]),
        const SizedBox(height: 6),
        Text('가로 = 흉고직경(DBH), 세로 = BSI. 값은 고사 확률(%).\n'
            '출처: 산불피해목 BSI 자동측정 모듈 설계 착수보고 v6, p.20',
            style: TextStyle(fontSize: 11, color: p.muted, height: 1.45)),
      ]),
    );
  }
}

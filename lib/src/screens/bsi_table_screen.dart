import 'package:flutter/material.dart';

import '../l10n.dart';
import '../services/bsi_table.dart';
import '../services/mortality.dart';
import '../theme.dart';

/// BSI 정수·DBH 1 cm 간격의 판정표. 해당 판정 위치로 바로 이동한다.
class BsiTableScreen extends StatefulWidget {
  /// 결과 화면에서 열면 그 조사목의 값으로 시작한다.
  final double? bsi;
  final double? dbhCm;
  const BsiTableScreen({super.key, this.bsi, this.dbhCm});

  @override
  State<BsiTableScreen> createState() => _BsiTableScreenState();
}

class _BsiTableScreenState extends State<BsiTableScreen> {
  // 결과 화면과 같은 BSI 반올림 기준을 쓰며 DBH는 실측값을 유지한다.
  late double? _bsi = widget.bsi?.isFinite == true
      ? Mortality.bsiForDecision(widget.bsi!)
      : null;
  late double? _dbh = (widget.dbhCm?.isFinite == true && widget.dbhCm! > 0)
      ? widget.dbhCm
      : null;

  final _horizontal = ScrollController();
  final _vertical = ScrollController();
  final _rowLabels = ScrollController();
  bool _syncingVertical = false;

  static const _bsiStep = 1.0;
  static const _cellW = 44.0;
  static const _cellH = 32.0;
  static const _labelW = 48.0;
  static const _rowCount = BsiTable.maxBsi - BsiTable.minBsi + 1;
  static final _columnCount = BsiTable.dbhCm.last - BsiTable.dbhCm.first + 1;

  // DBH 반올림은 표시 위치만 결정한다. 확률과 판정에는 실측 DBH를 그대로 쓴다.
  int? get _selectedRow => _bsi == null
      ? null
      : ((_bsi! - BsiTable.minBsi) / _bsiStep).round().clamp(0, _rowCount - 1);

  int? get _selectedColumn => _dbh == null
      ? null
      : (_dbh! - BsiTable.dbhCm.first).round().clamp(0, _columnCount - 1);

  static double _bsiAt(int row) => BsiTable.minBsi.toDouble() + row * _bsiStep;
  static int _dbhAt(int column) => BsiTable.dbhCm.first + column;

  @override
  void initState() {
    super.initState();
    _vertical.addListener(_onGridScroll);
    _rowLabels.addListener(_onLabelScroll);
    _scheduleCenter();
  }

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    _rowLabels.dispose();
    super.dispose();
  }

  void _onGridScroll() => _syncVertical(_vertical, _rowLabels);
  void _onLabelScroll() => _syncVertical(_rowLabels, _vertical);

  void _syncVertical(ScrollController source, ScrollController target) {
    if (_syncingVertical || !source.hasClients || !target.hasClients) return;
    final offset = source.offset.clamp(0.0, target.position.maxScrollExtent);
    if ((target.offset - offset).abs() < 0.01) return;
    _syncingVertical = true;
    try {
      target.jumpTo(offset);
    } finally {
      _syncingVertical = false;
    }
  }

  void _scheduleCenter({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _centerAxis(_horizontal, _selectedColumn, _cellW, animate: animate);
      _centerAxis(_vertical, _selectedRow, _cellH, animate: animate);
    });
  }

  void _centerAxis(
    ScrollController controller,
    int? index,
    double extent, {
    required bool animate,
  }) {
    if (index == null || !controller.hasClients) return;
    final position = controller.position;
    final centered = (index + 0.5) * extent - position.viewportDimension / 2;
    // 첫 행·열이 중간에서 잘리지 않도록 칸 단위로 이동한다.
    final offset = ((centered / extent).round() * extent).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if (animate) {
      controller.animateTo(
        offset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(offset);
    }
  }

  static String _formatValue(double v) =>
      v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final probability = (_bsi != null && _dbh != null)
        ? Mortality.probability(_bsi!, _dbh!)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('존치·벌채 판정표', 'Retain / Fell decision table')),
      ),
      // 하단 범례가 네비게이션 바에 가리지 않게 SafeArea 안에 둔다.
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _picker(p, probability),
            Divider(height: 1, color: p.line),
            Expanded(child: _table(p, probability)),
            _footer(p),
          ],
        ),
      ),
    );
  }

  // ── 값 선택 + 판정 ────────────────────────────────────────────────
  Widget _picker(AppPalette p, double? probability) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _stepper(
                  p,
                  'BSI',
                  _bsi == null ? '–' : _formatValue(_bsi!),
                  onMinus: () => _stepBsi(-1),
                  onPlus: () => _stepBsi(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _stepper(
                  p,
                  'DBH',
                  _dbh == null ? '–' : '${_formatValue(_dbh!)} cm',
                  onMinus: () => _stepDbh(-1),
                  onPlus: () => _stepDbh(1),
                ),
              ),
            ],
          ),
          if (probability != null) ...[
            const SizedBox(height: 10),
            _verdictBar(p, probability),
          ],
        ],
      ),
    );
  }

  Widget _stepper(
    AppPalette p,
    String label,
    String value, {
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.line),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onMinus,
            tooltip: tr('$label 감소', 'Decrease $label'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.remove, size: 18, color: p.muted),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: p.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onPlus,
            tooltip: tr('$label 증가', 'Increase $label'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.add, size: 18, color: p.muted),
          ),
        ],
      ),
    );
  }

  Widget _verdictBar(AppPalette p, double probability) {
    final verdict = Mortality.verdict(_bsi!, _dbh!);
    final cut = verdict == '벌채';
    final c = cut ? p.danger : p.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            cut ? Icons.local_fire_department : Icons.check_circle_outline,
            size: 20,
            color: c,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'BSI ${_formatValue(_bsi!)} · DBH ${_formatValue(_dbh!)} cm',
              style: TextStyle(fontSize: 13, color: p.muted),
            ),
          ),
          Text(
            Mortality.probabilityLabel(probability),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            verdictLabel(verdict),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  void _stepBsi(int direction) {
    final row = _selectedRow;
    final next = _bsiAt(
      row == null ? 0 : (row + direction).clamp(0, _rowCount - 1),
    );
    setState(() => _bsi = next);
    _scheduleCenter(animate: true);
  }

  void _stepDbh(int dir) {
    final column = _selectedColumn;
    final next = _dbhAt(
      column == null ? 0 : (column + dir).clamp(0, _columnCount - 1),
    ).toDouble();
    setState(() => _dbh = next);
    _scheduleCenter(animate: true);
  }

  // ── 표 ────────────────────────────────────────────────────────────
  Widget _table(AppPalette p, double? actualProbability) {
    final selectedRow = _selectedRow;
    final selectedColumn = _selectedColumn;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _labelW,
          child: Column(
            children: [
              _axisCorner(p),
              Expanded(
                child: ListView.builder(
                  key: const ValueKey('bsi-table-labels'),
                  controller: _rowLabels,
                  padding: EdgeInsets.zero,
                  itemExtent: _cellH,
                  itemCount: _rowCount,
                  itemBuilder: (_, row) => _cell(
                    p,
                    _bsiAt(row).toStringAsFixed(0),
                    key: ValueKey('bsi-table-row-${_formatValue(_bsiAt(row))}'),
                    w: _labelW,
                    rightAligned: true,
                    selected: row == selectedRow,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: const ValueKey('bsi-table-horizontal'),
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _columnCount * _cellW,
              child: Column(
                children: [
                  Row(
                    children: [
                      for (var column = 0; column < _columnCount; column++)
                        _cell(
                          p,
                          '${_dbhAt(column)}',
                          key: ValueKey('bsi-table-header-${_dbhAt(column)}'),
                          selected: column == selectedColumn,
                        ),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      key: const ValueKey('bsi-table-body'),
                      controller: _vertical,
                      padding: EdgeInsets.zero,
                      cacheExtent: _cellH * 2,
                      itemExtent: _cellH,
                      itemCount: _rowCount,
                      itemBuilder: (_, row) => Row(
                        children: [
                          for (var column = 0; column < _columnCount; column++)
                            _dataCell(
                              p,
                              row,
                              column,
                              selected:
                                  row == selectedRow &&
                                  column == selectedColumn,
                              actualProbability: actualProbability,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dataCell(
    AppPalette p,
    int row,
    int column, {
    required bool selected,
    required double? actualProbability,
  }) {
    final bsi = _bsiAt(row);
    final dbh = _dbhAt(column);
    // 선택 칸도 실측 DBH를 쓴다. 35.25 cm 같은 값은 35 cm로 바꿔 계산하지 않는다.
    final probability = selected
        ? actualProbability!
        : Mortality.probability(bsi, dbh.toDouble());
    final verdict = selected
        ? Mortality.verdict(_bsi!, _dbh!)
        : Mortality.verdict(bsi, dbh.toDouble());
    final cut = verdict == '벌채';
    final base = cut ? p.danger : p.green;
    return GestureDetector(
      key: ValueKey('bsi-table-${_formatValue(bsi)}-$dbh'),
      onTap: () => setState(() {
        _bsi = bsi;
        _dbh = dbh.toDouble();
      }),
      child: Container(
        key: selected ? const ValueKey('bsi-table-selection') : null,
        width: _cellW,
        height: _cellH,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? p.navy : base.withValues(alpha: cut ? 0.07 : 0.08),
          borderRadius: selected ? BorderRadius.circular(5) : null,
          border: Border.all(
            color: selected ? p.navy : p.line.withValues(alpha: 0.55),
            width: 0.5,
          ),
        ),
        child: Text(
          '${Mortality.percentForDisplay(probability)}',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.onNavy : (cut ? p.ink : base),
          ),
        ),
      ),
    );
  }

  Widget _axisCorner(AppPalette p) {
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 10,
      height: 1,
      fontWeight: FontWeight.w700,
      color: p.muted,
    );
    return Semantics(
      label: tr('가로: 흉고직경(DBH), 세로: BSI', 'Columns: DBH, rows: BSI'),
      child: ExcludeSemantics(
        child: Container(
          width: _labelW,
          height: _cellH,
          decoration: BoxDecoration(
            color: p.surface2,
            border: Border(
              right: BorderSide(color: p.line, width: 0.5),
              bottom: BorderSide(color: p.line, width: 0.5),
            ),
          ),
          child: CustomPaint(
            painter: _AxisCornerPainter(p.muted.withValues(alpha: 0.45)),
            child: Stack(
              children: [
                Positioned(top: 3, right: 4, child: Text('DBH', style: style)),
                Positioned(
                  bottom: 3,
                  left: 4,
                  child: Text('BSI', style: style),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cell(
    AppPalette p,
    String text, {
    Key? key,
    double w = _cellW,
    bool rightAligned = false,
    bool selected = false,
  }) {
    return Container(
      key: key,
      width: w,
      height: _cellH,
      alignment: rightAligned ? Alignment.centerRight : Alignment.center,
      padding: rightAligned ? const EdgeInsets.only(right: 8) : null,
      decoration: BoxDecoration(
        color: selected ? p.navy.withValues(alpha: 0.14) : p.surface2,
        border: Border(
          right: BorderSide(color: p.line, width: 0.5),
          bottom: BorderSide(color: p.line, width: 0.5),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: selected ? p.navy : p.muted,
        ),
      ),
    );
  }

  Widget _footer(AppPalette p) {
    Widget key(Color c, double a, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            color: c.withValues(alpha: a),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(fontSize: 12, color: p.muted)),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              key(p.green, 0.08, tr('존치 (30% 미만)', 'Retain (< 30%)')),
              key(p.danger, 0.07, tr('벌채 (30% 이상)', 'Fell (30% or more)')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'BSI는 정수 반올림 · DBH는 실측값 기준입니다.',
              'BSI is rounded to an integer; DBH uses the measured value.',
            ),
            style: TextStyle(fontSize: 11, color: p.muted, height: 1.45),
          ),
          if ((_bsi != null &&
                  (_bsi! < BsiTable.minBsi || _bsi! > BsiTable.maxBsi)) ||
              (_dbh != null &&
                  (_dbh! < BsiTable.dbhCm.first ||
                      _dbh! > BsiTable.dbhCm.last))) ...[
            const SizedBox(height: 4),
            Text(
              tr(
                '표 범위 밖의 측정값은 가장자리 값으로 계산합니다.',
                'Measurements outside the table range use the edge values.',
              ),
              style: TextStyle(fontSize: 11, color: p.muted, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

class _AxisCornerPainter extends CustomPainter {
  final Color color;
  const _AxisCornerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset.zero,
      Offset(size.width, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 0.7,
    );
  }

  @override
  bool shouldRepaint(covariant _AxisCornerPainter oldDelegate) =>
      oldDelegate.color != color;
}

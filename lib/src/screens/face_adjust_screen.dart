import 'dart:io';

import 'package:flutter/material.dart';

import '../app_prefs.dart';
import '../l10n.dart';
import '../models/tuning.dart';
import '../theme.dart';

/// 한 방위 사진의 분석을 조사자가 바로잡는 화면.
///
/// 현장에서 자동 분석이 어긋나는 세 가지를 손으로 고친다.
///   · **지표면** — 풀·낙엽·그림자에 마스크가 붙어 밑동이 아래로 내려가면
///     모든 높이가 함께 늘어난다. 가로선을 끌어 실제 밑동에 맞춘다.
///   · **대상목** — 옆·뒤 나무가 더 크게 잡히면 그쪽이 선택된다. 조사 대상
///     줄기를 한 번 찍어 알려 준다.
///   · **밝기·대비**(개발자 모드) — 역광·그늘 사진을 보정해 다시 분석한다.
///
/// 사진은 분석과 **같은 기하**로 보여 준다(정사각 letterbox, BoxFit.contain).
/// 그래야 화면에서 찍은 위치가 분석 좌표와 정확히 일치한다.
class FaceAdjustScreen extends StatefulWidget {
  final String imagePath;
  final String label; // 방위 표기
  final FaceTuning tuning;
  const FaceAdjustScreen({
    super.key,
    required this.imagePath,
    required this.label,
    required this.tuning,
  });

  @override
  State<FaceAdjustScreen> createState() => _FaceAdjustScreenState();
}

class _ExclusionPainter extends CustomPainter {
  final List<List<({double x, double y})>> areas;
  final List<({double x, double y})> pending;
  final Color color, pointColor;
  const _ExclusionPainter({
    required this.areas,
    required this.pending,
    required this.color,
    required this.pointColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    Offset position(({double x, double y}) p) =>
        Offset(p.x * size.width, p.y * size.height);
    Path pathFor(List<({double x, double y})> points, bool closed) {
      final path = Path()
        ..moveTo(position(points.first).dx, position(points.first).dy);
      for (final p in points.skip(1)) {
        path.lineTo(position(p).dx, position(p).dy);
      }
      if (closed) path.close();
      return path;
    }

    for (final area in FaceTuning.validatedExcludedAreas(areas)) {
      final path = pathFor(area, true);
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .3));
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    if (pending.isEmpty) return;
    canvas.drawPath(
      pathFor(pending, false),
      Paint()
        ..color = pointColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    for (final p in pending) {
      canvas.drawCircle(position(p), 5, Paint()..color = pointColor);
      canvas.drawCircle(
        position(p),
        6,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ExclusionPainter oldDelegate) => true;
}

enum _Tool { ground, target, exclude }

class _FaceAdjustScreenState extends State<FaceAdjustScreen> {
  late FaceTuning _t = widget.tuning;
  _Tool _tool = _Tool.ground;
  final _pending = <({double x, double y})>[];
  String? _polygonError;

  void _onTapDown(TapDownDetails d, Size box) {
    final nx = (d.localPosition.dx / box.width).clamp(0.0, 1.0);
    final ny = (d.localPosition.dy / box.height).clamp(0.0, 1.0);
    setState(() {
      if (_tool == _Tool.exclude) {
        if (_pending.length < FaceTuning.maxExclusionPoints &&
            _t.excludedAreas.length < FaceTuning.maxExcludedAreas) {
          _pending.add((x: nx, y: ny));
          _polygonError = null;
        }
        return;
      }
      _t = _tool == _Tool.ground
          ? _t.copyWith(groundNorm: ny)
          : _t.copyWith(targetX: nx, targetY: ny);
    });
  }

  void _onDrag(Offset local, Size box) {
    if (_tool != _Tool.ground) return;
    final ny = (local.dy / box.height).clamp(0.0, 1.0);
    setState(() => _t = _t.copyWith(groundNorm: ny));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('${widget.label} 방위 보정', '${widget.label} aspect adjustment'),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _t = FaceTuning.none;
              _pending.clear();
              _polygonError = null;
            }),
            child: Text(tr('초기화', 'Reset')),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1, // 분석과 같은 정사각 letterbox 공간
                  child: LayoutBuilder(
                    builder: (_, c) {
                      final box = Size(c.maxWidth, c.maxHeight);
                      return GestureDetector(
                        key: const ValueKey('adjust-photo'),
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (d) => _onTapDown(
                          TapDownDetails(localPosition: d.localPosition),
                          box,
                        ),
                        onVerticalDragUpdate: (d) =>
                            _onDrag(d.localPosition, box),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColorFiltered(
                              // 화면 미리보기도 분석과 같은 보정을 건다.
                              colorFilter: _toneFilter(
                                _t.brightness,
                                _t.contrast,
                              ),
                              child: Image.file(
                                File(widget.imagePath),
                                fit: BoxFit.contain,
                              ),
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _ExclusionPainter(
                                  areas: _t.excludedAreas,
                                  pending: List.of(_pending),
                                  color: p.danger,
                                  pointColor: p.pole,
                                ),
                              ),
                            ),
                            if (_t.groundNorm != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: _t.groundNorm! * box.height - 1.5,
                                child: Container(height: 3, color: p.ember),
                              ),
                            if (_t.groundNorm != null)
                              Positioned(
                                right: 6,
                                top: _t.groundNorm! * box.height - 22,
                                child: _tag(p.ember, tr('지표면', 'Ground')),
                              ),
                            if (_t.targetX != null && _t.targetY != null)
                              Positioned(
                                left: _t.targetX! * box.width - 14,
                                top: _t.targetY! * box.height - 14,
                                child: Icon(
                                  Icons.my_location,
                                  size: 28,
                                  color: p.navy.withValues(alpha: 0.95),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            SizedBox(
              // 그리는 도중 안내 문구가 늘어도 사진의 좌표·크기는 고정한다.
              height: MediaQuery.sizeOf(context).height * .54,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final tool in _Tool.values)
                            ChoiceChip(
                              label: Text(switch (tool) {
                                _Tool.ground => tr('지표면', 'Ground'),
                                _Tool.target => tr('대상목', 'Target tree'),
                                _Tool.exclude => tr('영역 제외', 'Exclude area'),
                              }),
                              selected: _tool == tool,
                              onSelected: (_) => setState(() => _tool = tool),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                        _tool == _Tool.ground
                            ? tr(
                                '기준선을 근원부 지표면에 맞추세요. 기준선 아래는 수간에서 제외됩니다.',
                                'Align the line with the ground at the stem base. Anything below is excluded from the stem.',
                              )
                            : _tool == _Tool.target
                            ? tr(
                                '대상목 수간을 탭하세요. 인접목이 잘못 검출된 경우에 사용합니다.',
                                'Tap the target stem. Use when a neighbouring tree was detected instead.',
                              )
                            : tr(
                                '대상목이 아닌 부분의 둘레를 3점 이상 탭하고 확정하세요. 빨간 영역은 분석에서 제외됩니다.',
                                'Tap at least 3 points around the unwanted area, then confirm. Red areas are excluded from analysis.',
                              ),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: p.muted,
                        ),
                      ),
                    ),
                    if (_tool == _Tool.exclude || _pending.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(
                                '확정 ${_t.excludedAreas.length}개 · 그리는 중 ${_pending.length}점',
                                '${_t.excludedAreas.length} confirmed · ${_pending.length} draft points',
                              ),
                              style: TextStyle(color: p.muted, fontSize: 12),
                            ),
                            if (_polygonError != null)
                              Text(
                                _polygonError!,
                                style: TextStyle(color: p.danger),
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton(
                                  key: const ValueKey('confirm-exclusion'),
                                  onPressed: _pending.length < 3
                                      ? null
                                      : () => setState(() {
                                          if (!FaceTuning.isValidExcludedArea(
                                            _pending,
                                          )) {
                                            _polygonError = tr(
                                              '점이 겹치거나 선이 교차합니다. 점을 되돌려 다시 그려주세요.',
                                              'Points overlap or edges cross. Undo points and draw again.',
                                            );
                                            return;
                                          }
                                          _t = _t.copyWith(
                                            excludedAreas: [
                                              ..._t.excludedAreas,
                                              List.of(_pending),
                                            ],
                                          );
                                          _pending.clear();
                                          _polygonError = null;
                                        }),
                                  child: Text(tr('영역 확정', 'Confirm area')),
                                ),
                                TextButton(
                                  onPressed: _pending.isEmpty
                                      ? null
                                      : () => setState(() {
                                          _pending.removeLast();
                                          _polygonError = null;
                                        }),
                                  child: Text(tr('점 되돌리기', 'Undo point')),
                                ),
                                TextButton(
                                  key: const ValueKey('cancel-exclusion'),
                                  onPressed: _pending.isEmpty
                                      ? null
                                      : () => setState(() {
                                          _pending.clear();
                                          _polygonError = null;
                                        }),
                                  child: Text(tr('그리기 취소', 'Cancel drawing')),
                                ),
                                TextButton(
                                  key: const ValueKey('undo-exclusion'),
                                  onPressed: _t.excludedAreas.isEmpty
                                      ? null
                                      : () => setState(() {
                                          _t = _t.copyWith(
                                            excludedAreas: _t.excludedAreas
                                                .sublist(
                                                  0,
                                                  _t.excludedAreas.length - 1,
                                                ),
                                          );
                                        }),
                                  child: Text(
                                    tr('마지막 영역 되돌리기', 'Undo last area'),
                                  ),
                                ),
                              ],
                            ),
                            if (_pending.isNotEmpty)
                              Text(
                                tr(
                                  '미확정 영역이 있습니다. 확정하거나 그리기를 취소해야 적용할 수 있습니다.',
                                  'Confirm or cancel the draft area before applying.',
                                ),
                                style: TextStyle(color: p.ember, fontSize: 12),
                              ),
                            if (_t.excludedAreas.length >=
                                FaceTuning.maxExcludedAreas)
                              Text(
                                tr(
                                  '최대 16개 영역까지 지정할 수 있습니다.',
                                  'Up to 16 areas can be excluded.',
                                ),
                              ),
                          ],
                        ),
                      ),
                    // 역광 자동 보정 — 기본은 앱이 사진 밝기를 보고 판단한다.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            tr('역광 보정', 'Backlight correction'),
                            style: TextStyle(fontSize: 12.5, color: p.muted),
                          ),
                          SegmentedButton<int>(
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              visualDensity: VisualDensity.compact,
                            ),
                            segments: [
                              ButtonSegment(
                                value: 0,
                                label: Text(tr('자동', 'Auto')),
                              ),
                              ButtonSegment(
                                value: 1,
                                label: Text(tr('켬', 'On')),
                              ),
                              ButtonSegment(
                                value: 2,
                                label: Text(tr('끔', 'Off')),
                              ),
                            ],
                            selected: {
                              _t.autoTone == null ? 0 : (_t.autoTone! ? 1 : 2),
                            },
                            onSelectionChanged: (sel) => setState(() {
                              final v = sel.first;
                              _t = v == 0
                                  ? _t.copyWith(clearAutoTone: true)
                                  : _t.copyWith(autoTone: v == 1);
                            }),
                          ),
                        ],
                      ),
                    ),
                    // 밝기·대비는 연구·검증용이라 개발자 모드에서만 연다.
                    if (devMode.value) ...[
                      _slider(
                        p,
                        tr('밝기', 'Brightness'),
                        _t.brightness,
                        -0.5,
                        0.5,
                        (v) => setState(() => _t = _t.copyWith(brightness: v)),
                      ),
                      _slider(
                        p,
                        tr('대비', 'Contrast'),
                        _t.contrast,
                        0.6,
                        1.8,
                        (v) => setState(() => _t = _t.copyWith(contrast: v)),
                      ),
                    ],
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        10,
                        16,
                        14 + MediaQuery.viewPaddingOf(context).bottom,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final cancel = OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(tr('취소', 'Cancel')),
                          );
                          final apply = ElevatedButton.icon(
                            key: const ValueKey('apply-adjustments'),
                            onPressed: _pending.isNotEmpty
                                ? null
                                : () => Navigator.pop(context, _t),
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(
                              tr('적용 후 재분석', 'Apply and re-analyse'),
                              textAlign: TextAlign.center,
                            ),
                          );
                          if (constraints.maxWidth < 330 ||
                              MediaQuery.textScalerOf(context).scale(14) > 18) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                apply,
                                const SizedBox(height: 8),
                                cancel,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: cancel),
                              const SizedBox(width: 10),
                              Expanded(flex: 2, child: apply),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(Color c, String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      t,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _slider(
    AppPalette p,
    String label,
    double v,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
    child: Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(label, style: TextStyle(fontSize: 12, color: p.muted)),
        ),
        Expanded(
          child: Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 42,
          child: Text(
            v.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  /// 미리보기용 밝기·대비 필터 — 분석의 LUT와 같은 식.
  static ColorFilter _toneFilter(double brightness, double contrast) {
    final t = 128 * (1 - contrast) + brightness * 255;
    return ColorFilter.matrix(<double>[
      contrast,
      0,
      0,
      0,
      t,
      0,
      contrast,
      0,
      0,
      t,
      0,
      0,
      contrast,
      0,
      t,
      0,
      0,
      0,
      1,
      0,
    ]);
  }
}

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

enum _Tool { ground, target }

class _FaceAdjustScreenState extends State<FaceAdjustScreen> {
  late FaceTuning _t = widget.tuning;
  _Tool _tool = _Tool.ground;

  void _onTapDown(TapDownDetails d, Size box) {
    final nx = (d.localPosition.dx / box.width).clamp(0.0, 1.0);
    final ny = (d.localPosition.dy / box.height).clamp(0.0, 1.0);
    setState(() {
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
        title: Text(tr('${widget.label} 면 조정', 'Adjust ${widget.label}')),
        actions: [
          TextButton(
            onPressed: () => setState(() => _t = FaceTuning.none),
            child: Text(tr('초기화', 'Reset')),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1, // 분석과 같은 정사각 letterbox 공간
                child: LayoutBuilder(builder: (_, c) {
                  final box = Size(c.maxWidth, c.maxHeight);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _onTapDown(d, box),
                    onVerticalDragUpdate: (d) => _onDrag(d.localPosition, box),
                    child: Stack(fit: StackFit.expand, children: [
                      ColorFiltered(
                        // 화면 미리보기도 분석과 같은 보정을 건다.
                        colorFilter: _toneFilter(_t.brightness, _t.contrast),
                        child: Image.file(File(widget.imagePath),
                            fit: BoxFit.contain),
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
                          child: Icon(Icons.my_location,
                              size: 28, color: p.navy.withValues(alpha: 0.95)),
                        ),
                    ]),
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<_Tool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: _Tool.ground,
                    icon: const Icon(Icons.horizontal_rule, size: 18),
                    label: Text(tr('지표면', 'Ground'))),
                ButtonSegment(
                    value: _Tool.target,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: Text(tr('대상목', 'Target'))),
              ],
              selected: {_tool},
              onSelectionChanged: (s) => setState(() => _tool = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
                _tool == _Tool.ground
                    ? tr('밑동 높이에 선을 맞추세요. 선 아래는 줄기로 세지 않습니다.',
                        'Drag the line to the stem base. Anything below is ignored.')
                    : tr('조사 대상 줄기를 한 번 누르세요. 옆·뒤 나무가 잡힐 때 씁니다.',
                        'Tap the target trunk — use when a neighbouring tree is picked.'),
                style: TextStyle(fontSize: 12, height: 1.4, color: p.muted)),
          ),
          // 역광 자동 보정 — 기본은 앱이 사진 밝기를 보고 판단한다.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(children: [
              Expanded(
                child: Text(tr('역광 보정', 'Backlight fix'),
                    style: TextStyle(fontSize: 12.5, color: p.muted)),
              ),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: 0, label: Text(tr('자동', 'Auto'))),
                  ButtonSegment(value: 1, label: Text(tr('켬', 'On'))),
                  ButtonSegment(value: 2, label: Text(tr('끔', 'Off'))),
                ],
                selected: {_t.autoTone == null ? 0 : (_t.autoTone! ? 1 : 2)},
                onSelectionChanged: (sel) => setState(() {
                  final v = sel.first;
                  _t = v == 0
                      ? _t.copyWith(clearAutoTone: true)
                      : _t.copyWith(autoTone: v == 1);
                }),
              ),
            ]),
          ),
          // 밝기·대비는 연구·검증용이라 개발자 모드에서만 연다.
          if (devMode.value) ...[
            _slider(p, tr('밝기', 'Brightness'), _t.brightness, -0.5, 0.5,
                (v) => setState(() => _t = _t.copyWith(brightness: v))),
            _slider(p, tr('대비', 'Contrast'), _t.contrast, 0.6, 1.8,
                (v) => setState(() => _t = _t.copyWith(contrast: v))),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 10, 16, 14 + MediaQuery.viewPaddingOf(context).bottom),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr('취소', 'Cancel')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, _t),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(tr('적용하고 다시 분석', 'Apply & re-analyse')),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tag(Color c, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(999)),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _slider(AppPalette p, String label, double v, double min, double max,
          ValueChanged<double> onChanged) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Row(children: [
          SizedBox(
              width: 44,
              child: Text(label,
                  style: TextStyle(fontSize: 12, color: p.muted))),
          Expanded(
              child: Slider(
                  value: v.clamp(min, max),
                  min: min,
                  max: max,
                  onChanged: onChanged)),
          SizedBox(
            width: 42,
            child: Text(v.toStringAsFixed(2),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  /// 미리보기용 밝기·대비 필터 — 분석의 LUT와 같은 식.
  static ColorFilter _toneFilter(double brightness, double contrast) {
    final t = 128 * (1 - contrast) + brightness * 255;
    return ColorFilter.matrix(<double>[
      contrast, 0, 0, 0, t,
      0, contrast, 0, 0, t,
      0, 0, contrast, 0, t,
      0, 0, 0, 1, 0,
    ]);
  }
}

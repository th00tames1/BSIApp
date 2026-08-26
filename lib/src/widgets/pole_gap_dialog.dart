import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/survey.dart';
import '../services/analysis_service.dart';
import '../theme.dart';

/// 수고봉 경계 간격을 고치는 창.
///
/// 봉은 조사목마다 다를 수 있는데(현장에서 나무마다 다른 봉을 썼다), 이 값이
/// 어긋나면 **모든 높이가 같은 배율로** 틀어진다. 촬영을 되돌릴 수는 없으니
/// 찍힌 기록에서 고칠 수 있어야 한다.
///
/// 문제는 조사자가 "그 봉의 띠가 몇 m였나"를 기억으로 답해야 한다는 것이다.
/// 그것만으로는 맞게 골랐는지 확인할 길이 없다. 그래서 값을 넣는 동안
/// **그 값이면 수고·그을음 높이·BSI가 얼마가 되는지**를 바로 보여 준다.
/// 눈앞의 나무와 견주어 보면 어느 값이 맞는지 조사자가 판단할 수 있다.
class PoleGapDialog extends StatefulWidget {
  final List<AzimuthResult> faces;
  final double dbhCm;
  final double currentGap;

  const PoleGapDialog({
    super.key,
    required this.faces,
    required this.dbhCm,
    required this.currentGap,
  });

  @override
  State<PoleGapDialog> createState() => _PoleGapDialogState();
}

class _PoleGapDialogState extends State<PoleGapDialog> {
  late final TextEditingController _c =
      TextEditingController(text: _fmt(widget.currentGap));

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(1) : v.toStringAsFixed(2);

  double? get _value {
    // 한국어 자판의 숫자 키패드는 쉼표를 소수점으로 내놓기도 한다.
    final v = double.tryParse(_c.text.trim().replaceAll(',', '.'));
    return (v == null || v <= 0 || v > 10) ? null : v;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final v = _value;
    final scaled = (v == null || widget.currentGap <= 0)
        ? null
        : rescaleFacesForGap(widget.faces, v / widget.currentGap);
    final integ = scaled == null
        ? null
        : AnalysisService.instance.integrate(scaled, widget.dbhCm);
    return AlertDialog(
      title: Text(tr('수고봉 간격', 'Pole spacing')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              tr('수고봉의 색 띠 하나의 길이입니다. 이 값이 어긋나면 모든 높이가 '
                  '같은 배율로 틀어집니다.',
                  'Length of one colour band. A wrong value scales every height.'),
              style: TextStyle(fontSize: 12, height: 1.4, color: p.muted)),
          const SizedBox(height: 12),
          // 흔한 봉은 눌러서 고른다. 자판을 띄우지 않으므로 미리보기가 가리지
          // 않고 바로 보인다 — 값을 고르는 판단이 이 창의 목적이다.
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final g in const [0.2, 0.25, 0.5, 1.0])
                ChoiceChip(
                  label: Text('${_fmt(g)} m'),
                  visualDensity: VisualDensity.compact,
                  selected: v != null && (v - g).abs() < 1e-9,
                  onSelected: (_) => setState(() => _c.text = _fmt(g)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              isDense: true,
              suffixText: 'm',
              border: const OutlineInputBorder(),
              errorText:
                  v == null ? tr('0보다 큰 값을 넣으세요', 'Enter a value above 0') : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          // 고른 값이면 결과가 어떻게 되는지 — 맞는 값을 눈으로 고르게 한다.
          // 자판이 올라와도 가리지 않도록 입력칸 바로 아래 한 덩어리로 둔다.
          if (scaled != null && integ != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: p.line.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('이 값이면', 'With this value'),
                    style: TextStyle(fontSize: 11, color: p.muted)),
                const SizedBox(height: 4),
                _pv(p, tr('수고', 'Height'),
                    _maxOf(scaled, (f) => f.visibleStemHeightM), 'm'),
                _pv(p, tr('그을음 높이', 'Char height'),
                    _maxOf(scaled, (f) => f.sootHeightM), 'm'),
                _pv(p, tr('통합 BSI', 'Total BSI'), integ.bsi, ''),
                // 수고봉이 아닌 방법으로 스케일을 세운 면은 간격과 무관하다.
                // 알리지 않으면 "왜 기대만큼 안 움직이지?"로 읽힌다.
                if (gapIndependentFaceCount(widget.faces) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        tr('${gapIndependentFaceCount(widget.faces)}개 방위는 수고봉이 아닌 '
                            '방법으로 스케일을 세워 이 값에 영향받지 않습니다.',
                            '${gapIndependentFaceCount(widget.faces)} face(s) were scaled '
                                'without the pole and are unaffected.'),
                        style:
                            TextStyle(fontSize: 10.5, height: 1.35, color: p.muted)),
                  ),
              ]),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('취소', 'Cancel'))),
        FilledButton(
          onPressed: v == null ? null : () => Navigator.pop(context, v),
          child: Text(tr('적용', 'Apply')),
        ),
      ],
    );
  }

  static double _maxOf(
      List<AzimuthResult> faces, double Function(AzimuthResult) pick) {
    double best = double.nan;
    for (final f in faces) {
      final v = pick(f);
      if (v.isNaN) continue;
      if (best.isNaN || v > best) best = v;
    }
    return best;
  }

  Widget _pv(AppPalette p, String label, double value, String unit) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          Expanded(
              child:
                  Text(label, style: TextStyle(fontSize: 12.5, color: p.muted))),
          Text(
              value.isNaN
                  ? '–'
                  : '${value.toStringAsFixed(2)}${unit.isEmpty ? '' : ' $unit'}',
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ]),
      );
}
